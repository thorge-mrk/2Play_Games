import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../models/minigolf_levels.dart';
import '../widgets/game_ui.dart';

class MinigolfScreen extends StatefulWidget {
  const MinigolfScreen({super.key});

  @override
  State<MinigolfScreen> createState() => _MinigolfScreenState();
}

class _MinigolfScreenState extends State<MinigolfScreen>
    with SingleTickerProviderStateMixin {
  static const double _fieldWidth = 360.0;
  static const double _fieldHeight = 500.0;

  // Game modes
  bool _isTournamentMode = false;
  int _tournamentScore = 0;
  List<int> _tournamentHoles = [];
  int _currentTournamentIndex = 0;

  List<GolfLevel> _levelsList = [];
  late GolfLevel _currentLevel;
  int _currentLevelId = 1;

  // Ball state
  Offset _ballPos = const Offset(180, 440);
  Offset _ballVel = Offset.zero;
  final double _ballRadius = 8.0;
  final double _holeRadius = 13.0;

  // Drag state
  Offset? _dragStart;
  Offset? _dragCurrent;
  final double _maxDragDist = 120.0;
  final double _shotPowerMultiplier = 0.08;

  // Game loop
  late Ticker _ticker;
  double _lastElapsedSeconds = 0;
  int _syncCounter = 0;

  // Score keeping
  int _strokeCount = 0;
  bool _levelCompleted = false;
  bool _waterResetTriggered = false;

  // P2P / turn management
  bool _myTurn = true;
  Offset _opponentBallPos = const Offset(180, 440);
  Offset _opponentBallVel = Offset.zero;
  int _opponentStrokeCount = 0;
  bool _opponentCompleted = false;
  Offset? _opponentDragStart;
  Offset? _opponentDragCurrent;
  bool _statsUpdated = false;
  bool _botStrokePending = false;

  StreamSubscription? _msgSubscription;

  @override
  void initState() {
    super.initState();
    _levelsList = GolfLevel.generate50Levels();
    _loadLevel(_currentLevelId);

    _ticker = createTicker(_tick);
    _ticker.start();

    final connService =
        Provider.of<ConnectivityService>(context, listen: false);
    // The host takes the first stroke. Against the bot the local player is
    // always the host (see ConnectivityService.invitePeer).
    _myTurn = connService.isHost || !connService.isConnected;

    _msgSubscription = connService.messageStream.listen(_onMessage);
  }

  void _onMessage(Map<String, dynamic> payload) {
    if (!mounted) return;
    if (payload['type'] == 'game_move' && payload['gameId'] == 'minigolf') {
      final data = payload['data'] as Map<String, dynamic>;
      final subtype = data['subtype'] as String?;

      switch (subtype) {
        case 'stroke':
          setState(() {
            _opponentBallVel = Offset(
                (data['vx'] as num).toDouble(), (data['vy'] as num).toDouble());
            _opponentBallPos = Offset((data['startX'] as num).toDouble(),
                (data['startY'] as num).toDouble());
            _opponentStrokeCount = data['strokeNumber'] as int;
            _myTurn = true;
          });
          break;

        case 'sync_state':
          setState(() {
            _opponentBallPos = Offset(
                (data['x'] as num).toDouble(), (data['y'] as num).toDouble());
            _opponentCompleted = data['completed'] as bool? ?? false;
            _opponentStrokeCount = data['strokes'] as int? ?? 0;
            if (_opponentCompleted) {
              // Nothing left for the opponent to do – it is our turn.
              _opponentBallVel = Offset.zero;
              _myTurn = true;
            }
          });
          if (_opponentCompleted) _checkGameWinnerAndIncrementStats();
          break;

        case 'aiming':
          setState(() {
            if (data['startX'] != null && data['currentX'] != null) {
              _opponentDragStart = Offset((data['startX'] as num).toDouble(),
                  (data['startY'] as num).toDouble());
              _opponentDragCurrent = Offset(
                  (data['currentX'] as num).toDouble(),
                  (data['currentY'] as num).toDouble());
            } else {
              _opponentDragStart = null;
              _opponentDragCurrent = null;
            }
          });
          break;

        case 'level_change':
          final id = data['levelId'] as int?;
          if (id != null && id >= 1 && id <= _levelsList.length) {
            _isTournamentMode = false;
            _loadLevel(id);
          }
          break;

        case 'obstacles_sync':
          final obstaclesData = data['obstacles'] as List<dynamic>;
          for (final obsData in obstaclesData) {
            final id = obsData['id'] as String;
            final matches =
                _currentLevel.movingObstacles.where((o) => o.id == id);
            if (matches.isEmpty) continue;
            final obstacle = matches.first;
            obstacle.currentOffset = (obsData['offset'] as num).toDouble();
            obstacle.currentAngle = (obsData['angle'] as num).toDouble();
            obstacle.direction = obsData['dir'] as int;
          }
          setState(() {});
          break;
      }
    } else if (payload['type'] == 'game_reset' &&
        payload['gameId'] == 'minigolf') {
      Provider.of<ConnectivityService>(context, listen: false).sendPayload({
        'type': 'game_reset_accept',
        'gameId': 'minigolf',
      });
      _resetLevel();
    } else if (payload['type'] == 'game_reset_accept' &&
        payload['gameId'] == 'minigolf') {
      _resetLevel();
    } else if (payload['type'] == 'game_exit') {
      Navigator.of(context).pop();
    }
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
      _statsUpdated = false;
      _botStrokePending = false;
      _opponentDragStart = null;
      _opponentDragCurrent = null;
      final svc = Provider.of<ConnectivityService>(context, listen: false);
      _myTurn = svc.isHost || !svc.isConnected;
    });
  }

  void _resetLevel() => _loadLevel(_currentLevelId);

  void _changeLevel(int id) {
    _loadLevel(id);
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (svc.isConnected) {
      svc.sendPayload({
        'type': 'game_move',
        'gameId': 'minigolf',
        'data': {'subtype': 'level_change', 'levelId': id},
      });
    }
  }

  void _nextLevel() {
    if (_isTournamentMode) {
      _tournamentScore += (_strokeCount - _currentLevel.par);
      _currentTournamentIndex++;
      if (_currentTournamentIndex < _tournamentHoles.length) {
        _loadLevel(_tournamentHoles[_currentTournamentIndex]);
      } else {
        setState(() => _levelCompleted = true);
      }
    } else {
      _changeLevel(_currentLevelId < 50 ? _currentLevelId + 1 : 1);
    }
  }

  void _startTournament() {
    final random = math.Random();
    _tournamentHoles = List.generate(9, (_) => random.nextInt(50) + 1);
    _tournamentScore = 0;
    _currentTournamentIndex = 0;
    _isTournamentMode = true;
    _loadLevel(_tournamentHoles[0]);
  }

  void _stopTournament() {
    setState(() => _isTournamentMode = false);
    _changeLevel(1);
  }

  // ── Game loop ─────────────────────────────────────────────────────────────

  void _tick(Duration elapsed) {
    final elapsedSeconds = elapsed.inMicroseconds / 1000000.0;
    double dt = elapsedSeconds - _lastElapsedSeconds;
    _lastElapsedSeconds = elapsedSeconds;
    if (dt <= 0) return;
    if (dt > 0.1) dt = 0.1;

    final svc = Provider.of<ConnectivityService>(context, listen: false);
    bool needsPaint = false;

    // Moving obstacles: simulated on host (or offline), mirrored on guest.
    final isObstacleAuthority = !svc.isConnected || svc.isHost;
    if (isObstacleAuthority && _currentLevel.movingObstacles.isNotEmpty) {
      for (final obstacle in _currentLevel.movingObstacles) {
        obstacle.update(dt);
      }
      needsPaint = true;
    }

    needsPaint = _updateBallPhysics(dt) || needsPaint;
    needsPaint = _updateOpponentBallPhysics(dt) || needsPaint;

    // Throttled network sync (~10 Hz instead of every frame).
    _syncCounter++;
    if (svc.isConnected && _syncCounter >= 6) {
      _syncCounter = 0;
      if (isObstacleAuthority && _currentLevel.movingObstacles.isNotEmpty) {
        svc.sendPayload({
          'type': 'game_move',
          'gameId': 'minigolf',
          'data': {
            'subtype': 'obstacles_sync',
            'obstacles': [
              for (final obs in _currentLevel.movingObstacles)
                {
                  'id': obs.id,
                  'offset': obs.currentOffset,
                  'angle': obs.currentAngle,
                  'dir': obs.direction,
                }
            ],
          }
        });
      }
      if (_ballVel.distance > 0.1) {
        svc.sendPayload({
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

    if (needsPaint && mounted) setState(() {});
  }

  /// Advances the local ball. Returns true when a repaint is needed.
  bool _updateBallPhysics(double dt) {
    if (_levelCompleted || _ballVel == Offset.zero) return false;

    _ballVel = _ballVel *
        math.pow(_frictionAt(_ballPos), dt * 60).toDouble();

    if (_ballVel.distance < 0.15) {
      _ballVel = Offset.zero;
      return true;
    }

    Offset nextPos = _ballPos + _ballVel * dt * 100;

    for (final wall in _currentLevel.walls) {
      nextPos = _handleWallCollision(wall, nextPos, true);
    }
    for (final mover in _currentLevel.movingObstacles) {
      nextPos = mover.isRotating
          ? _handleWindmillCollision(mover, nextPos, true)
          : _handleWallCollision(mover.currentRect, nextPos, true);
    }

    for (final water in _currentLevel.waterHazards) {
      if (water.contains(nextPos)) {
        _triggerWaterSplash();
        return true;
      }
    }

    _ballPos = nextPos;

    final distToHole = (_ballPos - _currentLevel.holePos).distance;
    if (distToHole < _holeRadius && _ballVel.distance < 3.5) {
      _sinkBall();
    }
    return true;
  }

  /// Advances the opponent ball. Returns true when a repaint is needed.
  bool _updateOpponentBallPhysics(double dt) {
    if (_opponentCompleted || _opponentBallVel == Offset.zero) return false;

    _opponentBallVel = _opponentBallVel *
        math.pow(_frictionAt(_opponentBallPos), dt * 60).toDouble();

    if (_opponentBallVel.distance < 0.15) {
      _opponentBallVel = Offset.zero;
      _maybeScheduleBotStroke();
      return true;
    }

    Offset nextPos = _opponentBallPos + _opponentBallVel * dt * 100;

    for (final wall in _currentLevel.walls) {
      nextPos = _handleWallCollision(wall, nextPos, false);
    }
    for (final mover in _currentLevel.movingObstacles) {
      nextPos = mover.isRotating
          ? _handleWindmillCollision(mover, nextPos, false)
          : _handleWallCollision(mover.currentRect, nextPos, false);
    }

    // Water hazard also applies to the opponent ball.
    for (final water in _currentLevel.waterHazards) {
      if (water.contains(nextPos)) {
        _opponentBallVel = Offset.zero;
        _opponentBallPos = _currentLevel.startPos;
        _opponentStrokeCount++;
        _maybeScheduleBotStroke();
        return true;
      }
    }

    _opponentBallPos = nextPos;

    final distToHole = (_opponentBallPos - _currentLevel.holePos).distance;
    if (distToHole < _holeRadius && _opponentBallVel.distance < 3.5) {
      _opponentBallVel = Offset.zero;
      _opponentBallPos = _currentLevel.holePos;
      _opponentCompleted = true;
      _myTurn = true;
      _checkGameWinnerAndIncrementStats();
    }
    return true;
  }

  double _frictionAt(Offset pos) {
    for (final sand in _currentLevel.sandTraps) {
      if (sand.contains(pos)) return 0.92;
    }
    for (final ice in _currentLevel.iceSheets) {
      if (ice.contains(pos)) return 0.996;
    }
    return 0.985;
  }

  Offset _handleWallCollision(Rect wall, Offset nextPos, bool isMyBall) {
    final cx = nextPos.dx.clamp(wall.left, wall.right);
    final cy = nextPos.dy.clamp(wall.top, wall.bottom);

    final dx = nextPos.dx - cx;
    final dy = nextPos.dy - cy;
    final dist = math.sqrt(dx * dx + dy * dy);

    if (dist >= _ballRadius) return nextPos;

    double nx = 0, ny = 0, pushDist = 0;
    if (dist > 0.001) {
      nx = dx / dist;
      ny = dy / dist;
      pushDist = _ballRadius - dist;
    } else {
      // Ball center inside the wall: push out to the closest side.
      final distToLeft = (nextPos.dx - wall.left).abs();
      final distToRight = (nextPos.dx - wall.right).abs();
      final distToTop = (nextPos.dy - wall.top).abs();
      final distToBottom = (nextPos.dy - wall.bottom).abs();
      final minDist = [distToLeft, distToRight, distToTop, distToBottom]
          .reduce(math.min);
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

    final resolvedPos =
        Offset(nextPos.dx + nx * pushDist, nextPos.dy + ny * pushDist);

    if (isMyBall) {
      final velAlongNormal = _ballVel.dx * nx + _ballVel.dy * ny;
      if (velAlongNormal < 0) {
        _ballVel = Offset(
          _ballVel.dx - 1.8 * velAlongNormal * nx,
          _ballVel.dy - 1.8 * velAlongNormal * ny,
        );
      }
    } else {
      final velAlongNormal =
          _opponentBallVel.dx * nx + _opponentBallVel.dy * ny;
      if (velAlongNormal < 0) {
        _opponentBallVel = Offset(
          _opponentBallVel.dx - 1.8 * velAlongNormal * nx,
          _opponentBallVel.dy - 1.8 * velAlongNormal * ny,
        );
      }
    }
    return resolvedPos;
  }

  Offset _handleWindmillCollision(
      MovingObstacle windmill, Offset nextPos, bool isMyBall) {
    final center = windmill.initialRect.center;
    final r = windmill.initialRect.width / 2 + 10;
    const numBlades = 4;

    for (int b = 0; b < numBlades; b++) {
      final angle = windmill.currentAngle + (b * math.pi / 2);
      final bladeEnd = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );

      final dPos = _closestPointOnSegment(center, bladeEnd, nextPos);
      final distance = (nextPos - dPos).distance;

      if (distance < _ballRadius) {
        final normal = distance > 0.001
            ? (nextPos - dPos) / distance
            : Offset(-math.sin(angle), math.cos(angle));
        final resolvedPos = dPos + normal * _ballRadius;

        final bladeSpeed = windmill.rotationSpeed * r * 0.15;
        final tangNormal = Offset(-math.sin(angle), math.cos(angle));

        if (isMyBall) {
          final dotNorm = _ballVel.dx * normal.dx + _ballVel.dy * normal.dy;
          _ballVel = Offset(
            (_ballVel.dx - 1.8 * dotNorm * normal.dx) +
                tangNormal.dx * bladeSpeed,
            (_ballVel.dy - 1.8 * dotNorm * normal.dy) +
                tangNormal.dy * bladeSpeed,
          );
        } else {
          final dotNorm = _opponentBallVel.dx * normal.dx +
              _opponentBallVel.dy * normal.dy;
          _opponentBallVel = Offset(
            (_opponentBallVel.dx - 1.8 * dotNorm * normal.dx) +
                tangNormal.dx * bladeSpeed,
            (_opponentBallVel.dy - 1.8 * dotNorm * normal.dy) +
                tangNormal.dy * bladeSpeed,
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
    double t = (ap.dx * ab.dx + ap.dy * ab.dy) /
        (ab.dx * ab.dx + ab.dy * ab.dy);
    t = t.clamp(0.0, 1.0);
    return a + ab * t;
  }

  void _triggerWaterSplash() {
    _ballVel = Offset.zero;
    _ballPos = _currentLevel.startPos;
    _strokeCount++;
    _waterResetTriggered = true;
    Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _waterResetTriggered = false);
    });
  }

  void _sinkBall() {
    _ballVel = Offset.zero;
    _ballPos = _currentLevel.holePos;
    _levelCompleted = true;

    _checkGameWinnerAndIncrementStats();

    final connService =
        Provider.of<ConnectivityService>(context, listen: false);
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
      // The bot keeps playing until it finishes the hole too.
      _maybeScheduleBotStroke();
    }
  }

  void _takeStroke(Offset aimVector) {
    if (_ballVel != Offset.zero || _levelCompleted) return;

    setState(() {
      _ballVel = aimVector * _shotPowerMultiplier;
      _strokeCount++;
      _myTurn = false;
    });

    final connService =
        Provider.of<ConnectivityService>(context, listen: false);
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
      _maybeScheduleBotStroke();
    } else {
      // Solo play (should not happen, but never lock the player out).
      _myTurn = true;
    }
  }

  /// Schedules the bot's next stroke when playing vs. bot and it still has
  /// work to do. Safe to call often – only one stroke is pending at a time.
  void _maybeScheduleBotStroke() {
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (svc.connectedPeer?.isMock != true) return;
    if (_opponentCompleted || _botStrokePending) return;
    if (_opponentBallVel != Offset.zero) return;

    _botStrokePending = true;
    Timer(const Duration(milliseconds: 1500), () {
      _botStrokePending = false;
      if (!mounted || _opponentCompleted) return;
      if (_opponentBallVel != Offset.zero) return;
      final connService =
          Provider.of<ConnectivityService>(context, listen: false);
      if (!connService.isConnected) return;

      final vector = _currentLevel.holePos - _opponentBallPos;
      double angle = math.atan2(vector.dy, vector.dx);
      final dist = vector.distance;

      double errorScale = 0.25;
      if (connService.botDifficulty == 'einfach') {
        errorScale = 0.55;
      } else if (connService.botDifficulty == 'schwer') {
        errorScale = 0.05;
      }
      angle += (math.Random().nextDouble() - 0.5) * errorScale;

      final power = (dist * 0.45).clamp(20.0, 90.0);

      setState(() {
        _opponentBallVel = Offset(
          math.cos(angle) * power * _shotPowerMultiplier,
          math.sin(angle) * power * _shotPowerMultiplier,
        );
        _opponentStrokeCount++;
        _myTurn = true;
      });
    });
  }

  int _lastAimSyncMs = 0;

  void _syncAiming({required bool clear}) {
    final connService =
        Provider.of<ConnectivityService>(context, listen: false);
    if (!connService.isConnected ||
        connService.connectedPeer?.isMock == true) {
      return;
    }
    // Throttle aim updates to ~12 Hz; the final "clear" is always sent.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!clear && now - _lastAimSyncMs < 80) return;
    _lastAimSyncMs = now;
    connService.sendPayload({
      'type': 'game_move',
      'gameId': 'minigolf',
      'data': {
        'subtype': 'aiming',
        'startX': clear ? null : _dragStart?.dx,
        'startY': clear ? null : _dragStart?.dy,
        'currentX': clear ? null : _dragCurrent?.dx,
        'currentY': clear ? null : _dragCurrent?.dy,
      }
    });
  }

  void _checkGameWinnerAndIncrementStats() {
    if (_statsUpdated) return;
    if (!_levelCompleted || !_opponentCompleted) return;

    final connService =
        Provider.of<ConnectivityService>(context, listen: false);
    if (_strokeCount < _opponentStrokeCount) {
      connService.incrementWin('minigolf');
    } else if (_strokeCount > _opponentStrokeCount) {
      connService.incrementLoss('minigolf');
    }
    _statsUpdated = true;
  }

  Future<void> _exitGame() async {
    final shouldExit = await showExitGameDialog(context);
    if (!shouldExit || !mounted) return;
    final connService =
        Provider.of<ConnectivityService>(context, listen: false);
    connService.exitGame();
    if (mounted) Navigator.of(context).pop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final connService = Provider.of<ConnectivityService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!connService.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
      return const SizedBox();
    }

    final isBallStationary = _ballVel == Offset.zero;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final header = GameHeader(
      title: _currentLevel.name,
      subtitle: _isTournamentMode
          ? 'Turnier: Loch ${_currentTournamentIndex + 1}/9 · Par ${_currentLevel.par}'
          : 'Loch $_currentLevelId/50 · Par ${_currentLevel.par}',
      onExit: _exitGame,
      extraActions: [
        IconButton(
          tooltip: 'Loch neu starten',
          icon: Icon(Icons.replay_rounded,
              color: isDark ? Colors.white70 : Colors.black87, size: 22),
          onPressed: () {
            final svc =
                Provider.of<ConnectivityService>(context, listen: false);
            if (svc.isConnected) {
              svc.sendPayload({'type': 'game_reset', 'gameId': 'minigolf'});
            }
            _resetLevel();
          },
        ),
      ],
    );

    final scoreRow = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          _StatusBadge(
            label: 'Du: $_strokeCount',
            active: _myTurn && isBallStationary && !_levelCompleted,
            activeColor: Colors.greenAccent,
          ),
          _StatusBadge(
            label:
                '${connService.connectedPeer?.name ?? 'Gegner'}: $_opponentStrokeCount',
            active: !_myTurn && !_opponentCompleted,
            activeColor: Colors.blueAccent,
          ),
        ],
      ),
    );

    final bottomControls = _buildBottomControls(isBallStationary, isDark);
    final canvas = _buildCanvas(isDark);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitGame();
      },
      child: Scaffold(
        body: AppBackground(
          child: SafeArea(
            child: Stack(
              children: [
                if (isLandscape)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 4,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            children: [
                              header,
                              const SizedBox(height: 8),
                              scoreRow,
                              const SizedBox(height: 8),
                              bottomControls,
                            ],
                          ),
                        ),
                      ),
                      Expanded(flex: 6, child: Center(child: canvas)),
                    ],
                  )
                else
                  Column(
                    children: [
                      header,
                      scoreRow,
                      const SizedBox(height: 8),
                      Expanded(child: Center(child: canvas)),
                      bottomControls,
                      const SizedBox(height: 8),
                    ],
                  ),
                if (_levelCompleted)
                  _buildScorecardOverlay(context, isDark, connService),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls(bool isBallStationary, bool isDark) {
    if (!_isTournamentMode && _strokeCount == 0 && isBallStationary) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    AppTheme.primaryPurple.withValues(alpha: 0.2),
                foregroundColor: isDark ? Colors.white : Colors.black87,
                side: const BorderSide(color: AppTheme.primaryPurple),
              ),
              onPressed: _startTournament,
              icon: const Icon(Icons.emoji_events_rounded,
                  color: Colors.amber, size: 18),
              label: const Text('Turnier',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const SizedBox(width: 16),
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _currentLevelId,
                dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
                items: List.generate(50, (index) {
                  return DropdownMenuItem(
                    value: index + 1,
                    child: Text('Loch ${index + 1}',
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                  );
                }),
                onChanged: (id) {
                  if (id != null) _changeLevel(id);
                },
              ),
            ),
          ],
        ),
      );
    }
    if (_isTournamentMode && isBallStationary) {
      return Padding(
        padding: const EdgeInsets.all(4.0),
        child: TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          onPressed: _stopTournament,
          child: const Text('Turnier beenden',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildCanvas(bool isDark) {
    return AspectRatio(
      aspectRatio: _fieldWidth / _fieldHeight,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
                color: isDark
                    ? Colors.white10
                    : Colors.black.withValues(alpha: 0.08),
                width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scaleX = _fieldWidth / constraints.maxWidth;
                final scaleY = _fieldHeight / constraints.maxHeight;

                Offset toField(Offset local) =>
                    Offset(local.dx * scaleX, local.dy * scaleY);

                return GestureDetector(
                  onPanStart: (details) {
                    if (_ballVel != Offset.zero ||
                        _levelCompleted ||
                        !_myTurn) {
                      return;
                    }
                    final tapPos = toField(details.localPosition);
                    if ((tapPos - _ballPos).distance < 40.0) {
                      setState(() {
                        _dragStart = _ballPos;
                        _dragCurrent = tapPos;
                      });
                      _syncAiming(clear: false);
                    }
                  },
                  onPanUpdate: (details) {
                    if (_dragStart == null) return;
                    setState(() {
                      _dragCurrent = toField(details.localPosition);
                    });
                    _syncAiming(clear: false);
                  },
                  onPanEnd: (details) {
                    if (_dragStart == null || _dragCurrent == null) return;
                    final aimVector = _dragStart! - _dragCurrent!;
                    final dist = aimVector.distance;
                    if (dist > 5.0) {
                      final clampedDist = dist.clamp(0.0, _maxDragDist);
                      _takeStroke(aimVector / dist * clampedDist);
                    }
                    setState(() {
                      _dragStart = null;
                      _dragCurrent = null;
                    });
                    _syncAiming(clear: true);
                  },
                  child: Stack(
                    children: [
                      RepaintBoundary(
                        child: CustomPaint(
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
                      ),
                      if (_waterResetTriggered)
                        Container(
                          color: Colors.black45,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.waves_rounded,
                                    size: 64, color: Color(0xFF00F2FE)),
                                const SizedBox(height: 12),
                                const Text(
                                  'WASSERHINDERNIS!\nStrafschlag +1',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18),
                                ).animate().shake(),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScorecardOverlay(
      BuildContext context, bool isDark, ConnectivityService connService) {
    final diff = _strokeCount - _currentLevel.par;
    final diffText = diff == 0 ? 'Par' : (diff > 0 ? '+$diff' : '$diff');
    final isLastHole = _isTournamentMode &&
        (_currentTournamentIndex == _tournamentHoles.length - 1);
    final opponentStillPlaying =
        connService.isConnected && !_opponentCompleted;

    return GameResultOverlay(
      title: _isTournamentMode && !isLastHole
          ? 'LOCH BEENDET!'
          : (_isTournamentMode ? 'TURNIER BEENDET!' : 'EINGELOCHT!'),
      description: _isTournamentMode
          ? 'Dein Gesamt-Score: ${_tournamentScore + (_strokeCount - _currentLevel.par)}'
          : 'Du hast $_strokeCount Schläge benötigt (Par: ${_currentLevel.par}).\nErgebnis: $diffText',
      color: Colors.greenAccent,
      icon: Icons.emoji_events_rounded,
      extra: opponentStillPlaying
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  '${connService.connectedPeer?.name ?? 'Gegner'} spielt noch...',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            )
          : Text(
              connService.isConnected
                  ? 'Gegner: $_opponentStrokeCount Schläge'
                  : '',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
      onExit: _exitGame,
      onRematch: () {
        if (_isTournamentMode && isLastHole) {
          _stopTournament();
        } else {
          _nextLevel();
        }
      },
      rematchLabel:
          _isTournamentMode && isLastHole ? 'Turnier abschließen' : 'Nächstes Loch',
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;

  const _StatusBadge({
    required this.label,
    required this.active,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? activeColor.withValues(alpha: 0.15)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: active ? activeColor : Colors.transparent, width: 1.5),
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
}

/// Renders the 2D minigolf course.
class GolfPainter extends CustomPainter {
  final GolfLevel level;
  final Offset ballPos;
  final double ballRadius;
  final Offset opponentBallPos;
  final bool opponentCompleted;
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
    final scaleX = size.width / 360.0;
    final scaleY = size.height / 500.0;

    Offset scaleOffset(Offset offset) =>
        Offset(offset.dx * scaleX, offset.dy * scaleY);
    Rect scaleRect(Rect rect) => Rect.fromLTWH(
          rect.left * scaleX,
          rect.top * scaleY,
          rect.width * scaleX,
          rect.height * scaleY,
        );

    // Grass background
    final bgPaint = Paint()
      ..shader = LinearGradient(
        colors: isDark
            ? [const Color(0xFF0F2613), const Color(0xFF0B1F10)]
            : [const Color(0xFF4CAF50), const Color(0xFF388E3C)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Checkered grass patches
    final patchPaint = Paint()
      ..color = (isDark
          ? Colors.white.withValues(alpha: 0.015)
          : Colors.black.withValues(alpha: 0.015))
      ..style = PaintingStyle.fill;
    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 7; c++) {
        if ((r + c) % 2 == 0) {
          canvas.drawRect(
            Rect.fromLTWH(c * 60.0 * scaleX, r * 60.0 * scaleY,
                60.0 * scaleX, 60.0 * scaleY),
            patchPaint,
          );
        }
      }
    }

    // Sand traps
    final sandPaint = Paint()
      ..color = const Color(0xFFE6C280)
      ..style = PaintingStyle.fill;
    for (final sand in level.sandTraps) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(scaleRect(sand), const Radius.circular(12)),
        sandPaint,
      );
    }

    // Ice sheets
    final icePaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: isDark ? 0.15 : 0.25)
      ..style = PaintingStyle.fill;
    final iceBorder = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (final ice in level.iceSheets) {
      final rrect =
          RRect.fromRectAndRadius(scaleRect(ice), const Radius.circular(12));
      canvas.drawRRect(rrect, icePaint);
      canvas.drawRRect(rrect, iceBorder);
    }

    // Water hazards
    final waterPaint = Paint()
      ..color = const Color(0xFF2196F3).withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    final wavesPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final water in level.waterHazards) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(scaleRect(water), const Radius.circular(16)),
        waterPaint,
      );
      canvas.drawCircle(
          scaleOffset(water.center), water.width * scaleX * 0.3, wavesPaint);
    }

    // Hole + flag
    final holePaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;
    final holeCenter = scaleOffset(level.holePos);
    canvas.drawCircle(holeCenter, holeRadius * scaleX, holePaint);

    final flagPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;
    final flagPath = Path()
      ..moveTo(holeCenter.dx, holeCenter.dy - 12 * scaleY)
      ..lineTo(holeCenter.dx + 16 * scaleX, holeCenter.dy - 20 * scaleY)
      ..lineTo(holeCenter.dx, holeCenter.dy - 28 * scaleY)
      ..close();
    canvas.drawPath(flagPath, flagPaint);

    final polePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0 * scaleX;
    canvas.drawLine(
      Offset(holeCenter.dx, holeCenter.dy - 2),
      Offset(holeCenter.dx, holeCenter.dy - 28 * scaleY),
      polePaint,
    );

    // Walls
    final wallPaint = Paint()
      ..color = isDark ? const Color(0xFF1B1437) : const Color(0xFF455A64)
      ..style = PaintingStyle.fill;
    final wallBorderPaint = Paint()
      ..color = isDark ? Colors.white24 : Colors.black12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final wall in level.walls) {
      canvas.drawRect(scaleRect(wall), wallPaint);
      canvas.drawRect(scaleRect(wall), wallBorderPaint);
    }

    // Moving obstacles
    for (final mover in level.movingObstacles) {
      if (mover.isRotating) {
        final center = scaleOffset(mover.initialRect.center);
        final towerPaint = Paint()
          ..color = Colors.grey[700]!
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, 12 * scaleX, towerPaint);

        final bladePaint = Paint()
          ..color = Colors.orangeAccent
          ..strokeWidth = 4.0 * scaleX
          ..strokeCap = StrokeCap.round;
        final r = (mover.initialRect.width / 2 + 10) * scaleX;
        for (int b = 0; b < 4; b++) {
          final angle = mover.currentAngle + (b * math.pi / 2);
          canvas.drawLine(
            center,
            Offset(center.dx + r * math.cos(angle),
                center.dy + r * math.sin(angle)),
            bladePaint,
          );
        }
      } else {
        final sliderPaint = Paint()
          ..color = Colors.amber[800]!
          ..style = PaintingStyle.fill;
        final rrect = RRect.fromRectAndRadius(
            scaleRect(mover.currentRect), const Radius.circular(6));
        canvas.drawRRect(rrect, sliderPaint);
        canvas.drawRRect(rrect, wallBorderPaint);
      }
    }

    // Opponent ball
    if (!opponentCompleted) {
      final oppPaint = Paint()
        ..color = const Color(0xFFFF007F)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
          scaleOffset(opponentBallPos), ballRadius * scaleX, oppPaint);
    }

    // My ball
    final ballPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final ballCenter = scaleOffset(ballPos);
    canvas.drawCircle(ballCenter, ballRadius * scaleX, ballPaint);
    final dimplePaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(ballCenter, ballRadius * scaleX, dimplePaint);

    // Aim arrows
    _drawAimArrow(canvas, ballCenter, dragStart, dragCurrent, scaleX, scaleY,
        powerColored: true);
    _drawAimArrow(canvas, scaleOffset(opponentBallPos), opponentDragStart,
        opponentDragCurrent, scaleX, scaleY,
        powerColored: false);
  }

  void _drawAimArrow(Canvas canvas, Offset ballCenter, Offset? start,
      Offset? current, double scaleX, double scaleY,
      {required bool powerColored}) {
    if (start == null || current == null) return;
    final aimVector = start - current;
    final dist = aimVector.distance;
    if (dist <= 5.0) return;

    final clampedDist = dist.clamp(0.0, maxDrag);
    final ratio = clampedDist / maxDrag;
    final arrowColor = powerColored
        ? (Color.lerp(Colors.greenAccent, Colors.redAccent, ratio) ??
            Colors.greenAccent)
        : const Color(0xFFFF007F).withValues(alpha: 0.7);

    final scaledAim = aimVector / dist * clampedDist;
    final arrowPaint = Paint()
      ..color = arrowColor
      ..strokeWidth = (2.0 + ratio * 4.0) * scaleX
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final targetEnd =
        ballCenter + Offset(scaledAim.dx * scaleX, scaledAim.dy * scaleY);
    const dashCount = 8;
    for (int d = 0; d < dashCount; d++) {
      final pt1 = Offset.lerp(ballCenter, targetEnd, d / dashCount)!;
      final pt2 = Offset.lerp(ballCenter, targetEnd, (d + 0.5) / dashCount)!;
      canvas.drawLine(pt1, pt2, arrowPaint);
    }

    final headPaint = Paint()
      ..color = arrowColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(targetEnd, (4 + ratio * 3) * scaleX, headPaint);
  }

  @override
  bool shouldRepaint(covariant GolfPainter oldDelegate) => true;
}
