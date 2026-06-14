import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../models/minigolf_levels.dart';
import '../widgets/chat_sheet.dart';

class MinigolfScreen extends StatefulWidget {
  const MinigolfScreen({super.key});

  @override
  State<MinigolfScreen> createState() => _MinigolfScreenState();
}

class _MinigolfScreenState extends State<MinigolfScreen> with SingleTickerProviderStateMixin {
  // Game Modes
  bool _isTournamentMode = false;
  int _tournamentScore = 0;
  List<int> _tournamentHoles = [];
  int _currentTournamentIndex = 0; // 0 to 8 (9 holes)

  List<GolfLevel> _levelsList = [];
  late GolfLevel _currentLevel;
  int _currentLevelId = 1;

  // Ball State
  Offset _ballPos = const Offset(180, 440);
  Offset _ballVel = Offset.zero;
  final double _ballRadius = 8.0;
  final double _holeRadius = 13.0;

  // Drag State
  Offset? _dragStart;
  Offset? _dragCurrent;
  final double _maxDragDist = 120.0;
  final double _shotPowerMultiplier = 0.08;

  // Game Loop Ticker
  late Ticker _ticker;
  double _lastElapsedSeconds = 0;

  // Score keeping
  int _strokeCount = 0;
  bool _levelCompleted = false;
  bool _waterResetTriggered = false;

  // P2P / Turn management
  bool _myTurn = true;
  Offset _opponentBallPos = const Offset(180, 440);
  Offset _opponentBallVel = Offset.zero;
  int _opponentStrokeCount = 0;
  bool _opponentCompleted = false;
  Offset? _opponentDragStart;
  Offset? _opponentDragCurrent;
  bool _statsUpdated = false;

  StreamSubscription? _msgSubscription;

  @override
  void initState() {
    super.initState();
    _levelsList = GolfLevel.generate50Levels();
    _loadLevel(_currentLevelId);

    // Setup Ticker for smooth 60fps physics updates
    _ticker = createTicker(_tick);
    _ticker.start();

    // Listen to network synchronization
    final connService = Provider.of<ConnectivityService>(context, listen: false);
    _myTurn = connService.isHost;

    _msgSubscription = connService.messageStream.listen((payload) {
      if (payload['type'] == 'game_move' && payload['gameId'] == 'minigolf') {
        final data = payload['data'] as Map<String, dynamic>;
        final subtype = data['subtype'] as String?;

        if (subtype == 'stroke') {
          setState(() {
            _opponentBallVel = Offset(data['vx'] as double, data['vy'] as double);
            _opponentBallPos = Offset(data['startX'] as double, data['startY'] as double);
            _opponentStrokeCount = data['strokeNumber'] as int;
            
            // Switch turn back to us once opponent shoots (or they alternate)
            _myTurn = true;
          });
        } else if (subtype == 'sync_state') {
          setState(() {
            _opponentBallPos = Offset(data['x'] as double, data['y'] as double);
            _opponentCompleted = data['completed'] as bool;
            _opponentStrokeCount = data['strokes'] as int;
          });
          if (data['completed'] == true) {
            _checkGameWinnerAndIncrementStats();
          }
        } else if (subtype == 'aiming') {
          setState(() {
            if (data['startX'] != null && data['currentX'] != null) {
              _opponentDragStart = Offset(data['startX'] as double, data['startY'] as double);
              _opponentDragCurrent = Offset(data['currentX'] as double, data['currentY'] as double);
            } else {
              _opponentDragStart = null;
              _opponentDragCurrent = null;
            }
          });
        } else if (subtype == 'obstacles_sync') {
          final obstaclesData = data['obstacles'] as List<dynamic>;
          for (var obsData in obstaclesData) {
            final id = obsData['id'] as String;
            final offset = (obsData['offset'] as num).toDouble();
            final angle = (obsData['angle'] as num).toDouble();
            final dir = obsData['dir'] as int;

            final obstacle = _currentLevel.movingObstacles.firstWhere(
              (o) => o.id == id,
              orElse: () => MovingObstacle(id: '', initialRect: Rect.zero),
            );
            if (obstacle.id.isNotEmpty) {
              setState(() {
                obstacle.currentOffset = offset;
                obstacle.currentAngle = angle;
                obstacle.direction = dir;
              });
            }
          }
        }
      } else if (payload['type'] == 'game_reset' && payload['gameId'] == 'minigolf') {
        connService.sendPayload({
          'type': 'game_reset_accept',
          'gameId': 'minigolf',
        });
        _resetLevel();
      } else if (payload['type'] == 'game_reset_accept' && payload['gameId'] == 'minigolf') {
        _resetLevel();
      } else if (payload['type'] == 'game_exit') {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _msgSubscription?.cancel();
    super.dispose();
  }

  void _loadLevel(int id) {
    setState(() {
      _currentLevelId = id;
      _currentLevel = _levelsList.firstWhere((l) => l.id == id);
      _ballPos = _currentLevel.startPos;
      _ballVel = Offset.zero;
      _strokeCount = 0;
      _levelCompleted = false;
      _opponentBallPos = _currentLevel.startPos;
      _opponentBallVel = Offset.zero;
      _opponentStrokeCount = 0;
      _opponentCompleted = false;
      _lastElapsedSeconds = 0;
      _statsUpdated = false;
      _opponentDragStart = null;
      _opponentDragCurrent = null;
    });
  }

  void _resetLevel() {
    _loadLevel(_currentLevelId);
  }

  void _nextLevel() {
    if (_isTournamentMode) {
      _tournamentScore += (_strokeCount - _currentLevel.par);
      _currentTournamentIndex++;
      if (_currentTournamentIndex < _tournamentHoles.length) {
        _loadLevel(_tournamentHoles[_currentTournamentIndex]);
      } else {
        // Show Tournament complete scorecard
        setState(() {
          _levelCompleted = true; // Displays final scorecard in overlay
        });
      }
    } else {
      if (_currentLevelId < 50) {
        _loadLevel(_currentLevelId + 1);
      } else {
        _loadLevel(1); // loop back
      }
    }
  }

  void _startTournament() {
    // Generate a 9-hole set based on selection
    final random = math.Random();
    _tournamentHoles = List.generate(9, (_) => random.nextInt(50) + 1);
    _tournamentScore = 0;
    _currentTournamentIndex = 0;
    _isTournamentMode = true;
    _loadLevel(_tournamentHoles[0]);
  }

  void _stopTournament() {
    setState(() {
      _isTournamentMode = false;
      _loadLevel(1);
    });
  }

  int _obstacleSyncCounter = 0;

  void _tick(Duration elapsed) {
    final double elapsedSeconds = elapsed.inMicroseconds / 1000000.0;
    double dt = elapsedSeconds - _lastElapsedSeconds;
    if (dt > 0.1) dt = 0.1; // Cap time step to avoid massive jumps during lag
    _lastElapsedSeconds = elapsedSeconds;

    if (_levelCompleted) return;

    final connService = Provider.of<ConnectivityService>(context, listen: false);

    // Update moving obstacles
    if (!connService.isConnected || connService.isHost) {
      for (var obstacle in _currentLevel.movingObstacles) {
        obstacle.update(dt);
      }

      // Sync moving obstacle coordinates from Host to Guest
      if (connService.isConnected && connService.isHost) {
        _obstacleSyncCounter++;
        if (_obstacleSyncCounter >= 3) {
          _obstacleSyncCounter = 0;
          final List<Map<String, dynamic>> obstacleStates = _currentLevel.movingObstacles.map((obs) {
            return {
              'id': obs.id,
              'offset': obs.currentOffset,
              'angle': obs.currentAngle,
              'dir': obs.direction,
            };
          }).toList();

          connService.sendPayload({
            'type': 'game_move',
            'gameId': 'minigolf',
            'data': {
              'subtype': 'obstacles_sync',
              'obstacles': obstacleStates,
            }
          });
        }
      }
    }

    _updateBallPhysics(dt);
    _updateOpponentBallPhysics(dt);
    
    // Periodically sync our state to peer when ball is moving
    if (_ballVel.distance > 0.1) {
      if (connService.isConnected) {
        connService.sendPayload({
          'type': 'game_move',
          'gameId': 'minigolf',
          'data': {
            'subtype': 'sync_state',
            'x': _ballPos.dx,
            'y': _ballPos.dy,
            'strokes': _strokeCount,
            'completed': _levelCompleted,
          }
        });
      }
    }
  }

  void _updateBallPhysics(double dt) {
    if (_ballVel == Offset.zero) return;

    // Apply friction based on surface
    double currentFriction = 0.985; // grass
    
    // Check sand traps
    for (var sand in _currentLevel.sandTraps) {
      if (sand.contains(_ballPos)) {
        currentFriction = 0.92;
      }
    }
    // Check ice sheets
    for (var ice in _currentLevel.iceSheets) {
      if (ice.contains(_ballPos)) {
        currentFriction = 0.996;
      }
    }

    // Apply drag
    _ballVel = _ballVel * math.pow(currentFriction, dt * 60).toDouble();

    // Apply velocity limit to stop ball
    if (_ballVel.distance < 0.15) {
      setState(() {
        _ballVel = Offset.zero;
      });
      return;
    }

    // Compute next position
    Offset nextPos = _ballPos + _ballVel * dt * 100; // 100 is scaling speed

    // Collision with walls
    for (var wall in _currentLevel.walls) {
      nextPos = _handleWallCollision(wall, nextPos, true);
    }

    // Collision with moving obstacles
    for (var mover in _currentLevel.movingObstacles) {
      if (mover.isRotating) {
        nextPos = _handleWindmillCollision(mover, nextPos, true);
      } else {
        nextPos = _handleWallCollision(mover.currentRect, nextPos, true);
      }
    }

    // Check water hazards
    for (var water in _currentLevel.waterHazards) {
      if (water.contains(nextPos)) {
        _triggerWaterSplash();
        return;
      }
    }

    setState(() {
      _ballPos = nextPos;
    });

    // Check hole capture
    final distToHole = (_ballPos - _currentLevel.holePos).distance;
    if (distToHole < _holeRadius && _ballVel.distance < 3.5) {
      _sinkBall();
    }
  }

  void _updateOpponentBallPhysics(double dt) {
    if (_opponentBallVel == Offset.zero) return;

    double friction = 0.985;
    for (var sand in _currentLevel.sandTraps) {
      if (sand.contains(_opponentBallPos)) friction = 0.92;
    }
    for (var ice in _currentLevel.iceSheets) {
      if (ice.contains(_opponentBallPos)) friction = 0.996;
    }

    _opponentBallVel = _opponentBallVel * math.pow(friction, dt * 60).toDouble();

    if (_opponentBallVel.distance < 0.15) {
      _opponentBallVel = Offset.zero;
      return;
    }

    Offset nextPos = _opponentBallPos + _opponentBallVel * dt * 100;

    for (var wall in _currentLevel.walls) {
      nextPos = _handleWallCollision(wall, nextPos, false);
    }
    for (var mover in _currentLevel.movingObstacles) {
      if (mover.isRotating) {
        nextPos = _handleWindmillCollision(mover, nextPos, false);
      } else {
        nextPos = _handleWallCollision(mover.currentRect, nextPos, false);
      }
    }

    setState(() {
      _opponentBallPos = nextPos;
    });

    // Check hole capture for opponent
    final distToHole = (_opponentBallPos - _currentLevel.holePos).distance;
    if (distToHole < _holeRadius && _opponentBallVel.distance < 3.5) {
      setState(() {
        _opponentBallVel = Offset.zero;
        _opponentBallPos = _currentLevel.holePos;
        _opponentCompleted = true;
      });
      _checkGameWinnerAndIncrementStats();
    }
  }

  Offset _handleWallCollision(Rect wall, Offset nextPos, bool isMyBall) {
    // Standard AABB-Circle collision resolution with stuck detection (dist == 0)
    double cx = nextPos.dx.clamp(wall.left, wall.right);
    double cy = nextPos.dy.clamp(wall.top, wall.bottom);

    double dx = nextPos.dx - cx;
    double dy = nextPos.dy - cy;
    double dist = math.sqrt(dx * dx + dy * dy);

    if (dist < _ballRadius) {
      double nx = 0;
      double ny = 0;
      double pushDist = 0;

      if (dist > 0.001) {
        nx = dx / dist;
        ny = dy / dist;
        pushDist = _ballRadius - dist;
      } else {
        // If dist is exactly 0, push out to the closest side of the wall box
        double distToLeft = (nextPos.dx - wall.left).abs();
        double distToRight = (nextPos.dx - wall.right).abs();
        double distToTop = (nextPos.dy - wall.top).abs();
        double distToBottom = (nextPos.dy - wall.bottom).abs();

        double minDist = [distToLeft, distToRight, distToTop, distToBottom].reduce(math.min);

        if (minDist == distToLeft) {
          nx = -1.0;
          pushDist = _ballRadius + distToLeft;
        } else if (minDist == distToRight) {
          nx = 1.0;
          pushDist = _ballRadius + distToRight;
        } else if (minDist == distToTop) {
          ny = -1.0;
          pushDist = _ballRadius + distToTop;
        } else {
          ny = 1.0;
          pushDist = _ballRadius + distToBottom;
        }
      }

      // Push ball out of wall
      Offset resolvedPos = Offset(nextPos.dx + nx * pushDist, nextPos.dy + ny * pushDist);

      // Bounce velocity
      if (isMyBall) {
        double velAlongNormal = _ballVel.dx * nx + _ballVel.dy * ny;
        if (velAlongNormal < 0) {
          _ballVel = Offset(
            _ballVel.dx - 1.8 * velAlongNormal * nx,
            _ballVel.dy - 1.8 * velAlongNormal * ny,
          );
        }
      } else {
        double velAlongNormal = _opponentBallVel.dx * nx + _opponentBallVel.dy * ny;
        if (velAlongNormal < 0) {
          _opponentBallVel = Offset(
            _opponentBallVel.dx - 1.8 * velAlongNormal * nx,
            _opponentBallVel.dy - 1.8 * velAlongNormal * ny,
          );
        }
      }
      return resolvedPos;
    }
    return nextPos;
  }

  Offset _handleWindmillCollision(MovingObstacle windmill, Offset nextPos, bool isMyBall) {
    // Windmill blades are rotating lines around the center of windmill
    final center = windmill.initialRect.center;
    final r = windmill.initialRect.width / 2 + 10; // blade length
    final numBlades = 4;

    for (int b = 0; b < numBlades; b++) {
      final angle = windmill.currentAngle + (b * math.pi / 2);
      final bladeEnd = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );

      // Check distance from ball (nextPos) to segment (center to bladeEnd)
      final dPos = _closestPointOnSegment(center, bladeEnd, nextPos);
      final distance = (nextPos - dPos).distance;

      if (distance < _ballRadius) {
        // Push out of segment
        final normal = distance > 0.001 
            ? (nextPos - dPos) / distance 
            : Offset(-math.sin(angle), math.cos(angle)); // perpendicular to blade
        final resolvedPos = dPos + normal * _ballRadius;

        // Bounce velocity + add some blade rotational kick
        final bladeSpeed = windmill.rotationSpeed * r * 0.15;
        final tangNormal = Offset(-math.sin(angle), math.cos(angle));

        if (isMyBall) {
          final dotNorm = _ballVel.dx * normal.dx + _ballVel.dy * normal.dy;
          _ballVel = Offset(
            (_ballVel.dx - 1.8 * dotNorm * normal.dx) + tangNormal.dx * bladeSpeed,
            (_ballVel.dy - 1.8 * dotNorm * normal.dy) + tangNormal.dy * bladeSpeed,
          );
        } else {
          final dotNorm = _opponentBallVel.dx * normal.dx + _opponentBallVel.dy * normal.dy;
          _opponentBallVel = Offset(
            (_opponentBallVel.dx - 1.8 * dotNorm * normal.dx) + tangNormal.dx * bladeSpeed,
            (_opponentBallVel.dy - 1.8 * dotNorm * normal.dy) + tangNormal.dy * bladeSpeed,
          );
        }
        return resolvedPos;
      }
    }

    return nextPos;
  }

  Offset _closestPointOnSegment(Offset a, Offset b, Offset p) {
    final ab = b - a;
    final ap = p - a;
    double t = (ap.dx * ab.dx + ap.dy * ab.dy) / (ab.dx * ab.dx + ab.dy * ab.dy);
    t = t.clamp(0.0, 1.0);
    return a + ab * t;
  }

  void _triggerWaterSplash() {
    setState(() {
      _ballVel = Offset.zero;
      _ballPos = _currentLevel.startPos;
      _strokeCount++;
      _waterResetTriggered = true;
    });
    Timer(const Duration(seconds: 1), () {
      setState(() {
        _waterResetTriggered = false;
      });
    });
  }

  void _sinkBall() {
    setState(() {
      _ballVel = Offset.zero;
      _ballPos = _currentLevel.holePos;
      _levelCompleted = true;
    });

    _checkGameWinnerAndIncrementStats();

    final connService = Provider.of<ConnectivityService>(context, listen: false);
    if (connService.isConnected) {
      connService.sendPayload({
        'type': 'game_move',
        'gameId': 'minigolf',
        'data': {
          'subtype': 'sync_state',
          'x': _ballPos.dx,
          'y': _ballPos.dy,
          'strokes': _strokeCount,
          'completed': true,
        }
      });
    }
  }

  void _takeStroke(Offset aimVector) {
    if (_ballVel != Offset.zero || _levelCompleted) return;

    setState(() {
      _ballVel = aimVector * _shotPowerMultiplier;
      _strokeCount++;
      _myTurn = false; // Turn switches
    });

    // Sync P2P stroke
    final connService = Provider.of<ConnectivityService>(context, listen: false);
    if (connService.isConnected) {
      connService.sendPayload({
        'type': 'game_move',
        'gameId': 'minigolf',
        'data': {
          'subtype': 'stroke',
          'vx': _ballVel.dx,
          'vy': _ballVel.dy,
          'startX': _ballPos.dx,
          'startY': _ballPos.dy,
          'strokeNumber': _strokeCount,
        }
      });
      
      // Auto reply if playing against a Bot
      if (connService.connectedPeer?.isMock == true) {
        _triggerSimulatedOpponentStroke();
      }
    }
  }

  void _triggerSimulatedOpponentStroke() {
    // Generate AI stroke response after 2.5 seconds
    Timer(const Duration(milliseconds: 2500), () {
      if (!mounted || _levelCompleted) return;
      final connService = Provider.of<ConnectivityService>(context, listen: false);
      
      // Target hole position
      final vector = _currentLevel.holePos - _opponentBallPos;
      
      // Simple pathing: aim at hole with some random noise and appropriate speed
      double angle = math.atan2(vector.dy, vector.dx);
      double dist = vector.distance;
      
      // Scale aiming inaccuracy error by difficulty setting
      double errorScale = 0.25; // default medium
      if (connService.botDifficulty == 'einfach') {
        errorScale = 0.55;
      } else if (connService.botDifficulty == 'schwer') {
        errorScale = 0.0;
      }
      
      final offsetAngle = (math.Random().nextDouble() - 0.5) * errorScale;
      angle += offsetAngle;

      double power = (dist * 0.45).clamp(20.0, 90.0);
      
      final vx = math.cos(angle) * power * _shotPowerMultiplier;
      final vy = math.sin(angle) * power * _shotPowerMultiplier;

      setState(() {
        _opponentBallVel = Offset(vx, vy);
        _opponentStrokeCount++;
        _myTurn = true; // Control back to us
      });

      // Sync state back
      connService.sendPayload({
        'type': 'game_move',
        'gameId': 'minigolf',
        'data': {
          'subtype': 'sync_state',
          'x': _opponentBallPos.dx,
          'y': _opponentBallPos.dy,
          'strokes': _opponentStrokeCount,
          'completed': _opponentCompleted,
        }
      });
    });
  }

  void _syncAimingStartOrUpdate() {
    final connService = Provider.of<ConnectivityService>(context, listen: false);
    if (connService.isConnected) {
      connService.sendPayload({
        'type': 'game_move',
        'gameId': 'minigolf',
        'data': {
          'subtype': 'aiming',
          'startX': _dragStart?.dx,
          'startY': _dragStart?.dy,
          'currentX': _dragCurrent?.dx,
          'currentY': _dragCurrent?.dy,
        }
      });
    }
  }

  void _syncAimingEnd() {
    final connService = Provider.of<ConnectivityService>(context, listen: false);
    if (connService.isConnected) {
      connService.sendPayload({
        'type': 'game_move',
        'gameId': 'minigolf',
        'data': {
          'subtype': 'aiming',
          'startX': null,
          'startY': null,
          'currentX': null,
          'currentY': null,
        }
      });
    }
  }

  void _checkGameWinnerAndIncrementStats() {
    if (_statsUpdated) return;
    if (!_levelCompleted || !_opponentCompleted) return;

    final connService = Provider.of<ConnectivityService>(context, listen: false);
    if (_strokeCount < _opponentStrokeCount) {
      connService.incrementWin('minigolf');
      _statsUpdated = true;
    } else if (_strokeCount > _opponentStrokeCount) {
      connService.incrementLoss('minigolf');
      _statsUpdated = true;
    }
  }

  void _exitGame() async {
    final shouldExit = await _showExitConfirmationDialog();
    if (shouldExit) {
      final connService = Provider.of<ConnectivityService>(context, listen: false);
      connService.disconnect();
    }
  }

  Future<bool> _showExitConfirmationDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          content: GlassContainer(
            padding: const EdgeInsets.all(24),
            borderRadius: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 48,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Spiel beenden?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Möchtest du das Spiel wirklich beenden? Dies bricht das Spiel für beide Spieler ab und trennt die Verbindung.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Nein, weiterspielen', style: TextStyle(color: Colors.white70)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Ja, beenden'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  Widget _buildBotDifficultySwitcher(ConnectivityService connService) {
    if (connService.connectedPeer?.isMock != true) return const SizedBox();
    
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: connService.botDifficulty,
          dropdownColor: AppTheme.darkCard,
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          onChanged: (val) {
            if (val != null) {
              connService.setBotDifficulty(val);
            }
          },
          items: const [
            DropdownMenuItem(value: 'einfach', child: Text('🤖 Einfach')),
            DropdownMenuItem(value: 'mittel', child: Text('🤖 Mittel')),
            DropdownMenuItem(value: 'schwer', child: Text('🤖 Schwer')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connService = Provider.of<ConnectivityService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!connService.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const SizedBox();
    }

    final isBallStationary = _ballVel == Offset.zero;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _exitGame();
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: isDark
                ? const LinearGradient(
                    colors: [Color(0xFF0F0B1E), Color(0xFF130A29)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : const LinearGradient(
                    colors: [Color(0xFFF4F6FB), Color(0xFFE9EEF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                isLandscape
                      ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left Column: stats, controls, levels
                        Expanded(
                          flex: 4,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Header Controls
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white70 : Colors.black87),
                                        onPressed: _exitGame,
                                      ),
                                      Column(
                                        children: [
                                          Text(
                                            _currentLevel.name,
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black87),
                                          ),
                                          Text(
                                            _isTournamentMode 
                                                ? 'Loch ${_currentTournamentIndex + 1}/9 (Par ${_currentLevel.par})'
                                                : 'Loch $_currentLevelId/50 (Par ${_currentLevel.par})',
                                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          _buildBotDifficultySwitcher(connService),
                                          IconButton(
                                            icon: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                Icon(Icons.chat_bubble_rounded, color: isDark ? Colors.white70 : Colors.black87, size: 22),
                                                if (connService.unreadChatCount > 0)
                                                  Positioned(
                                                    right: -4,
                                                    top: -4,
                                                    child: Container(
                                                      padding: const EdgeInsets.all(2),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFFF007F),
                                                        shape: BoxShape.circle,
                                                        border: Border.all(color: isDark ? const Color(0xFF0F0B1E) : Colors.white, width: 1.5),
                                                      ),
                                                      constraints: const BoxConstraints(
                                                        minWidth: 14,
                                                        minHeight: 14,
                                                      ),
                                                      child: Text(
                                                        '${connService.unreadChatCount}',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 8,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                        textAlign: TextAlign.center,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            onPressed: () {
                                              showModalBottomSheet(
                                                context: context,
                                                isScrollControlled: true,
                                                backgroundColor: Colors.transparent,
                                                builder: (_) => const ChatSheet(),
                                              );
                                            },
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.replay_rounded, color: isDark ? Colors.white70 : Colors.black87, size: 22),
                                            onPressed: _resetLevel,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildStatusBadge('Du: $_strokeCount', _myTurn && isBallStationary && !_levelCompleted, Colors.greenAccent),
                                const SizedBox(height: 8),
                                _buildStatusBadge('${connService.connectedPeer?.name}: $_opponentStrokeCount', !_myTurn && isBallStationary && !_opponentCompleted, Colors.blueAccent),
                                const SizedBox(height: 16),
                                if (!_isTournamentMode && _strokeCount == 0 && isBallStationary)
                                  Column(
                                    children: [
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF8A2387).withOpacity(0.2),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          side: const BorderSide(color: Color(0xFF8A2387), width: 1),
                                        ),
                                        onPressed: _startTournament,
                                        icon: const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 18),
                                        label: const Text('Turnier starten', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                      ),
                                      const SizedBox(height: 8),
                                      DropdownButtonHideUnderline(
                                        child: DropdownButton<int>(
                                          value: _currentLevelId,
                                          dropdownColor: isDark ? const Color(0xFF1B1437) : Colors.white,
                                          items: List.generate(50, (index) {
                                            return DropdownMenuItem(
                                              value: index + 1,
                                              child: Text('Hole ${index + 1}', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.bold)),
                                            );
                                          }),
                                          onChanged: (id) {
                                            if (id != null) _loadLevel(id);
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                if (_isTournamentMode && isBallStationary)
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.15), foregroundColor: Colors.redAccent),
                                    onPressed: _stopTournament,
                                    child: const Text('Turnier beenden', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        // Right Column: Canvas
                        Expanded(
                          flex: 6,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 360.0 / 500.0,
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.08), width: 2),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(26),
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        return GestureDetector(
                                          onPanStart: (details) {
                                            if (!isBallStationary || _levelCompleted || !_myTurn) return;
                                            final scaleX = 360.0 / constraints.maxWidth;
                                            final scaleY = 500.0 / constraints.maxHeight;

                                            final dx = details.localPosition.dx * scaleX;
                                            final dy = details.localPosition.dy * scaleY;
                                            final tapPos = Offset(dx, dy);

                                            if ((tapPos - _ballPos).distance < 30.0) {
                                              setState(() {
                                                _dragStart = _ballPos;
                                                _dragCurrent = tapPos;
                                              });
                                              _syncAimingStartOrUpdate();
                                            }
                                          },
                                          onPanUpdate: (details) {
                                            if (_dragStart == null) return;
                                            final scaleX = 360.0 / constraints.maxWidth;
                                            final scaleY = 500.0 / constraints.maxHeight;
                                            
                                            setState(() {
                                              _dragCurrent = Offset(
                                                details.localPosition.dx * scaleX,
                                                details.localPosition.dy * scaleY,
                                              );
                                            });
                                            _syncAimingStartOrUpdate();
                                          },
                                          onPanEnd: (details) {
                                            if (_dragStart == null || _dragCurrent == null) return;
                                            final aimVector = _dragStart! - _dragCurrent!;
                                            double dist = aimVector.distance;
                                            if (dist > 5.0) {
                                              final clampedDist = dist.clamp(0.0, _maxDragDist);
                                              final normalizedVec = aimVector / dist;
                                              _takeStroke(normalizedVec * clampedDist);
                                            }
                                            setState(() {
                                              _dragStart = null;
                                              _dragCurrent = null;
                                            });
                                            _syncAimingEnd();
                                          },
                                          child: Stack(
                                            children: [
                                              CustomPaint(
                                                size: Size.infinite,
                                                painter: GolfPainter(
                                                  level: _currentLevel,
                                                  ballPos: _ballPos,
                                                  ballRadius: _ballRadius,
                                                  opponentBallPos: _opponentBallPos,
                                                  opponentCompleted: _opponentCompleted,
                                                  dragStart: _dragStart,
                                                  dragCurrent: _dragCurrent,
                                                  opponentDragStart: _opponentDragStart,
                                                  opponentDragCurrent: _opponentDragCurrent,
                                                  maxDrag: _maxDragDist,
                                                  isDark: isDark,
                                                ),
                                              ),
                                              if (_waterResetTriggered)
                                                Container(
                                                  color: Colors.black45,
                                                  child: Center(
                                                    child: Column(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(Icons.waves_rounded, size: 64, color: Color(0xFF00F2FE)),
                                                        const SizedBox(height: 12),
                                                        const Text(
                                                          'WASSERHINDERNIS!\nStrafschlag +1',
                                                          textAlign: TextAlign.center,
                                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                                                        ).animate().shake(),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        );
                                      }
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        // Header Controls
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white70 : Colors.black87),
                                onPressed: _exitGame,
                              ),
                              Column(
                                children: [
                                  Text(
                                    _currentLevel.name,
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87),
                                  ),
                                  Text(
                                    _isTournamentMode 
                                        ? 'Turnier: Loch ${_currentTournamentIndex + 1}/9 (Par ${_currentLevel.par})'
                                        : 'Loch $_currentLevelId/50 (Par ${_currentLevel.par})',
                                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  _buildBotDifficultySwitcher(connService),
                                  IconButton(
                                    icon: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Icon(Icons.chat_bubble_rounded, color: isDark ? Colors.white70 : Colors.black87, size: 24),
                                        if (connService.unreadChatCount > 0)
                                          Positioned(
                                            right: -4,
                                            top: -4,
                                            child: Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFF007F),
                                                shape: BoxShape.circle,
                                                border: Border.all(color: isDark ? const Color(0xFF0F0B1E) : Colors.white, width: 1.5),
                                              ),
                                              constraints: const BoxConstraints(
                                                minWidth: 16,
                                                minHeight: 16,
                                              ),
                                              child: Text(
                                                '${connService.unreadChatCount}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    onPressed: () {
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (_) => const ChatSheet(),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(Icons.replay_rounded, color: isDark ? Colors.white70 : Colors.black87),
                                    onPressed: _resetLevel,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Game Info Panel
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildStatusBadge('Du: $_strokeCount Schläge', _myTurn && isBallStationary && !_levelCompleted, Colors.greenAccent),
                              _buildStatusBadge('${connService.connectedPeer?.name}: $_opponentStrokeCount Schläge', !_myTurn && isBallStationary && !_opponentCompleted, Colors.blueAccent),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Canvas Frame
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 360.0 / 500.0,
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.08), width: 2),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(26),
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        return GestureDetector(
                                          onPanStart: (details) {
                                            if (!isBallStationary || _levelCompleted || !_myTurn) return;
                                            final scaleX = 360.0 / constraints.maxWidth;
                                            final scaleY = 500.0 / constraints.maxHeight;

                                            final dx = details.localPosition.dx * scaleX;
                                            final dy = details.localPosition.dy * scaleY;
                                            final tapPos = Offset(dx, dy);

                                            if ((tapPos - _ballPos).distance < 30.0) {
                                              setState(() {
                                                _dragStart = _ballPos;
                                                _dragCurrent = tapPos;
                                              });
                                              _syncAimingStartOrUpdate();
                                            }
                                          },
                                          onPanUpdate: (details) {
                                            if (_dragStart == null) return;
                                            final scaleX = 360.0 / constraints.maxWidth;
                                            final scaleY = 500.0 / constraints.maxHeight;

                                            setState(() {
                                              _dragCurrent = Offset(
                                                details.localPosition.dx * scaleX,
                                                details.localPosition.dy * scaleY,
                                              );
                                            });
                                            _syncAimingStartOrUpdate();
                                          },
                                          onPanEnd: (details) {
                                            if (_dragStart == null || _dragCurrent == null) return;
                                            final aimVector = _dragStart! - _dragCurrent!;
                                            double dist = aimVector.distance;
                                            if (dist > 5.0) {
                                              final clampedDist = dist.clamp(0.0, _maxDragDist);
                                              final normalizedVec = aimVector / dist;
                                              _takeStroke(normalizedVec * clampedDist);
                                            }
                                            setState(() {
                                              _dragStart = null;
                                              _dragCurrent = null;
                                            });
                                            _syncAimingEnd();
                                          },
                                          child: Stack(
                                            children: [
                                              CustomPaint(
                                                size: Size.infinite,
                                                painter: GolfPainter(
                                                  level: _currentLevel,
                                                  ballPos: _ballPos,
                                                  ballRadius: _ballRadius,
                                                  opponentBallPos: _opponentBallPos,
                                                  opponentCompleted: _opponentCompleted,
                                                  dragStart: _dragStart,
                                                  dragCurrent: _dragCurrent,
                                                  opponentDragStart: _opponentDragStart,
                                                  opponentDragCurrent: _opponentDragCurrent,
                                                  maxDrag: _maxDragDist,
                                                  isDark: isDark,
                                                ),
                                              ),
                                              if (_waterResetTriggered)
                                                Container(
                                                  color: Colors.black45,
                                                  child: Center(
                                                    child: Column(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(Icons.waves_rounded, size: 64, color: Color(0xFF00F2FE)),
                                                        const SizedBox(height: 12),
                                                        const Text(
                                                          'WASSERHINDERNIS!\nStrafschlag +1',
                                                          textAlign: TextAlign.center,
                                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                                                        ).animate().shake(),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        );
                                      }
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Game Selection / Tournament menu if not in level gameplay
                        if (!_isTournamentMode && _strokeCount == 0 && isBallStationary)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF8A2387).withOpacity(0.2),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      side: const BorderSide(color: Color(0xFF8A2387), width: 1),
                                    ),
                                    onPressed: _startTournament,
                                    icon: const Icon(Icons.emoji_events_rounded, color: Colors.amber),
                                    label: const Text('Turnier starten', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int>(
                                      value: _currentLevelId,
                                      dropdownColor: isDark ? const Color(0xFF1B1437) : Colors.white,
                                      items: List.generate(50, (index) {
                                        return DropdownMenuItem(
                                          value: index + 1,
                                          child: Text('Hole ${index + 1}', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.bold)),
                                        );
                                      }),
                                      onChanged: (id) {
                                        if (id != null) _loadLevel(id);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        if (_isTournamentMode && isBallStationary)
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.15), foregroundColor: Colors.redAccent),
                              onPressed: _stopTournament,
                              child: const Text('Turnier beenden', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],
                    ),
              if (_levelCompleted)
                _buildScorecardOverlay(context, isDark, connService),
            ],
          ),
        ),
      ),
    ),);
  }

  Widget _buildStatusBadge(String label, bool active, Color activeColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active ? activeColor.withOpacity(0.15) : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: active ? activeColor : Colors.transparent, width: 1.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: active ? activeColor : Colors.grey,
        ),
      ),
    );
  }

  Widget _buildScorecardOverlay(BuildContext context, bool isDark, ConnectivityService connService) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final diff = _strokeCount - _currentLevel.par;
    final diffText = diff == 0
        ? 'Par'
        : (diff > 0 ? '+$diff' : '$diff');
        
    final isLastHole = _isTournamentMode && (_currentTournamentIndex == _tournamentHoles.length - 1);
    
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.75),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                width: isLandscape ? 420 : 310,
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF161B26) : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: const Color(0xFF8A2387).withOpacity(0.6),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8A2387).withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.emoji_events_rounded,
                      size: 64,
                      color: Colors.amber,
                    ).animate().scaleXY(begin: 0.8, end: 1.2, duration: 800.ms, curve: Curves.bounceOut),
                    const SizedBox(height: 16),
                    Text(
                      _isTournamentMode && !isLastHole
                          ? 'LOCH BEENDET!'
                          : (_isTournamentMode ? 'TURNIER BEENDET!' : 'EINGELOCHT!'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: Colors.greenAccent,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!_isTournamentMode) ...[
                      Text(
                        'Du hast $_strokeCount Schläge benötigt (Par: ${_currentLevel.par}).\nResultat: $diffText',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Dein Gesamt-Score: ${_tournamentScore + (_strokeCount - _currentLevel.par)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8A2387),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: () {
                        if (_isTournamentMode && isLastHole) {
                          _stopTournament();
                        } else {
                          _nextLevel();
                        }
                      },
                      icon: Icon(_isTournamentMode && isLastHole ? Icons.emoji_events : Icons.arrow_forward_rounded),
                      label: Text(
                        _isTournamentMode && isLastHole
                            ? 'Turnier beenden & Score eintragen'
                            : 'Nächstes Loch',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Custom CustomPainter to render the 2D Mini Golf playing canvas
class GolfPainter extends CustomPainter {
  final GolfLevel level;
  final Offset ballPos;
  final double ballRadius;
  final Offset opponentBallPos;
  final bool opponentCompleted;
  
  // Drag vector
  final Offset? dragStart;
  final Offset? dragCurrent;
  final Offset? opponentDragStart;
  final Offset? opponentDragCurrent;
  final double maxDrag;
  final bool isDark;
  final double holeRadius = 13.0;

  GolfPainter({
    required this.level,
    required this.ballPos,
    required this.ballRadius,
    required this.opponentBallPos,
    required this.opponentCompleted,
    this.dragStart,
    this.dragCurrent,
    this.opponentDragStart,
    this.opponentDragCurrent,
    required this.maxDrag,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Coordinate scale factors from normalized 360 x 500
    final scaleX = size.width / 360.0;
    final scaleY = size.height / 500.0;

    Offset scaleOffset(Offset offset) => Offset(offset.dx * scaleX, offset.dy * scaleY);
    Rect scaleRect(Rect rect) => Rect.fromLTWH(
      rect.left * scaleX,
      rect.top * scaleY,
      rect.width * scaleX,
      rect.height * scaleY,
    );

    // 1. Draw grass background green
    final Paint bgPaint = Paint()
      ..shader = LinearGradient(
        colors: isDark 
            ? [const Color(0xFF0F2613), const Color(0xFF0B1F10)]
            : [const Color(0xFF4CAF50), const Color(0xFF388E3C)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Grid details (light grass patches)
    final patchPaint = Paint()
      ..color = (isDark ? Colors.white.withOpacity(0.015) : Colors.black.withOpacity(0.015))
      ..style = PaintingStyle.fill;
    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 7; c++) {
        if ((r + c) % 2 == 0) {
          canvas.drawRect(
            Rect.fromLTWH(c * 60.0 * scaleX, r * 60.0 * scaleY, 60.0 * scaleX, 60.0 * scaleY),
            patchPaint,
          );
        }
      }
    }

    // 2. Draw Sand traps
    final sandPaint = Paint()
      ..color = const Color(0xFFE6C280)
      ..style = PaintingStyle.fill;
    for (var sand in level.sandTraps) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(scaleRect(sand), const Radius.circular(12)),
        sandPaint,
      );
    }

    // 3. Draw Ice sheets
    final icePaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(isDark ? 0.15 : 0.25)
      ..style = PaintingStyle.fill;
    for (var ice in level.iceSheets) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(scaleRect(ice), const Radius.circular(12)),
        icePaint,
      );
      // Ice borders
      final iceBorder = Paint()
        ..color = Colors.cyanAccent.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRRect(RRect.fromRectAndRadius(scaleRect(ice), const Radius.circular(12)), iceBorder);
    }

    // 4. Draw Water hazards
    final waterPaint = Paint()
      ..color = const Color(0xFF2196F3).withOpacity(0.7)
      ..style = PaintingStyle.fill;
    for (var water in level.waterHazards) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(scaleRect(water), const Radius.circular(16)),
        waterPaint,
      );
      // Draw waves detailing inside water
      final wavesPaint = Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(scaleOffset(water.center), water.width * scaleX * 0.3, wavesPaint);
    }

    // 5. Draw Target Hole
    final holePaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;
    final holeCenter = scaleOffset(level.holePos);
    canvas.drawCircle(holeCenter, holeRadius * scaleX, holePaint);

    // Hole flag
    final flagPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;
    final Path flagPath = Path()
      ..moveTo(holeCenter.dx, holeCenter.dy - 12 * scaleY)
      ..lineTo(holeCenter.dx + 16 * scaleX, holeCenter.dy - 20 * scaleY)
      ..lineTo(holeCenter.dx, holeCenter.dy - 28 * scaleY)
      ..close();
    canvas.drawPath(flagPath, flagPaint);

    // Flagpole line
    final polePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0 * scaleX;
    canvas.drawLine(
      Offset(holeCenter.dx, holeCenter.dy - 2),
      Offset(holeCenter.dx, holeCenter.dy - 28 * scaleY),
      polePaint,
    );

    // 6. Draw Walls
    final wallPaint = Paint()
      ..color = isDark ? const Color(0xFF1B1437) : const Color(0xFF455A64)
      ..style = PaintingStyle.fill;
    final wallBorderPaint = Paint()
      ..color = isDark ? Colors.white24 : Colors.black12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (var wall in level.walls) {
      canvas.drawRect(scaleRect(wall), wallPaint);
      canvas.drawRect(scaleRect(wall), wallBorderPaint);
    }

    // 7. Draw Moving Obstacles
    for (var mover in level.movingObstacles) {
      if (mover.isRotating) {
        // Windmill center tower
        final center = scaleOffset(mover.initialRect.center);
        final towerPaint = Paint()
          ..color = Colors.grey[700]!
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, 12 * scaleX, towerPaint);

        // Windmill blades (rotating cross lines)
        final bladePaint = Paint()
          ..color = Colors.orangeAccent
          ..strokeWidth = 4.0 * scaleX
          ..strokeCap = StrokeCap.round;

        final r = (mover.initialRect.width / 2 + 10) * scaleX;
        final numBlades = 4;

        for (int b = 0; b < numBlades; b++) {
          final angle = mover.currentAngle + (b * math.pi / 2);
          final endPoint = Offset(
            center.dx + r * math.cos(angle),
            center.dy + r * math.sin(angle),
          );
          canvas.drawLine(center, endPoint, bladePaint);
        }
      } else {
        // Sliding wall blocks
        final sliderPaint = Paint()
          ..color = Colors.amber[800]!
          ..style = PaintingStyle.fill;
        canvas.drawRRect(
          RRect.fromRectAndRadius(scaleRect(mover.currentRect), const Radius.circular(6)),
          sliderPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(scaleRect(mover.currentRect), const Radius.circular(6)),
          wallBorderPaint,
        );
      }
    }

    // 8. Draw Opponent Ball if active
    if (!opponentCompleted) {
      final oppPaint = Paint()
        ..color = const Color(0xFFFF007F)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(scaleOffset(opponentBallPos), ballRadius * scaleX, oppPaint);
    }

    // 9. Draw My Golf Ball
    final ballPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final ballCenter = scaleOffset(ballPos);
    canvas.drawCircle(ballCenter, ballRadius * scaleX, ballPaint);
    
    // Core dimple shadow detailing on ball
    final dimplePaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(ballCenter, ballRadius * scaleX, dimplePaint);

    // 10. Draw Aim Vector Arrow (Slingshot indicator)
    if (dragStart != null && dragCurrent != null) {
      final aimVector = dragStart! - dragCurrent!;
      double dist = aimVector.distance;
      if (dist > 5.0) {
        final clampedDist = dist.clamp(0.0, maxDrag);
        final ratio = clampedDist / maxDrag;

        // Color shifts from green to yellow to red depending on shot force
        final Color arrowColor = Color.lerp(
          Colors.greenAccent, 
          Colors.redAccent, 
          ratio
        ) ?? Colors.greenAccent;

        final normalAim = aimVector / dist;
        final scaledAim = normalAim * clampedDist;

        final arrowPaint = Paint()
          ..color = arrowColor
          ..strokeWidth = (2.0 + ratio * 4.0) * scaleX
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        // Draw line from ball position outward in target shot path
        final targetEnd = ballCenter + Offset(scaledAim.dx * scaleX, scaledAim.dy * scaleY);
        
        // Aiming line dots/dashes
        final dashCount = 8;
        for (int d = 0; d < dashCount; d++) {
          final pt1 = Offset.lerp(ballCenter, targetEnd, d / dashCount)!;
          final pt2 = Offset.lerp(ballCenter, targetEnd, (d + 0.5) / dashCount)!;
          canvas.drawLine(pt1, pt2, arrowPaint);
        }

        // Draw aiming arrowhead point
        final headPaint = Paint()
          ..color = arrowColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(targetEnd, (4 + ratio * 3) * scaleX, headPaint);
      }
    }

    // 11. Draw Opponent Aim Vector Arrow (Slingshot indicator) if synced
    if (opponentDragStart != null && opponentDragCurrent != null) {
      final aimVector = opponentDragStart! - opponentDragCurrent!;
      double dist = aimVector.distance;
      if (dist > 5.0) {
        final clampedDist = dist.clamp(0.0, maxDrag);
        final ratio = clampedDist / maxDrag;
        final arrowColor = const Color(0xFFFF007F).withOpacity(0.7); // neon pink for opponent

        final normalAim = aimVector / dist;
        final scaledAim = normalAim * clampedDist;

        final arrowPaint = Paint()
          ..color = arrowColor
          ..strokeWidth = (2.0 + ratio * 4.0) * scaleX
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        final opponentBallCenter = scaleOffset(opponentBallPos);
        final targetEnd = opponentBallCenter + Offset(scaledAim.dx * scaleX, scaledAim.dy * scaleY);
        
        final dashCount = 8;
        for (int d = 0; d < dashCount; d++) {
          final pt1 = Offset.lerp(opponentBallCenter, targetEnd, d / dashCount)!;
          final pt2 = Offset.lerp(opponentBallCenter, targetEnd, (d + 0.5) / dashCount)!;
          canvas.drawLine(pt1, pt2, arrowPaint);
        }

        final headPaint = Paint()
          ..color = arrowColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(targetEnd, (4 + ratio * 3) * scaleX, headPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant GolfPainter oldDelegate) {
    return true; // Continuously repaint as ball or windmill moves
  }
}
