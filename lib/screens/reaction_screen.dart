import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

/// Reaktionsduell: wait for green, tap as fast as you can.
/// First player with 3 round wins takes the match.
class ReactionScreen extends StatefulWidget {
  const ReactionScreen({super.key});

  @override
  State<ReactionScreen> createState() => _ReactionScreenState();
}

enum _RoundPhase { idle, armed, green, resolved }

class _ReactionScreenState extends State<ReactionScreen> {
  static const int _winsNeeded = 3;

  _RoundPhase _phase = _RoundPhase.idle;
  int _myWins = 0;
  int _oppWins = 0;
  int? _myTimeMs;
  int? _oppTimeMs;
  bool _myFalseStart = false;
  bool _oppFalseStart = false;
  String _roundMessage = '';
  DateTime? _greenAt;
  Timer? _armTimer;
  Timer? _nextRoundTimer;
  bool _isGameOver = false;
  bool _waitingForResetAccept = false;
  bool _statsUpdated = false;

  final math.Random _rng = math.Random();
  StreamSubscription? _msgSubscription;

  @override
  void initState() {
    super.initState();
    final svc = Provider.of<ConnectivityService>(context, listen: false);

    _msgSubscription = svc.messageStream.listen(_onMessage);

    // The host schedules the rounds for both devices.
    if (svc.isHost || svc.connectedPeer?.isMock == true) {
      _nextRoundTimer = Timer(const Duration(milliseconds: 1200), _startRound);
    }
  }

  void _onMessage(Map<String, dynamic> payload) {
    if (!mounted) return;
    if (payload['type'] == 'game_move' && payload['gameId'] == 'reaction') {
      final data = payload['data'] as Map<String, dynamic>;
      switch (data['subtype'] as String?) {
        case 'round':
          _armRound(data['delayMs'] as int);
          break;
        case 'time':
          _oppTimeMs = data['ms'] as int;
          _maybeResolveRound();
          break;
        case 'false_start':
          _oppFalseStart = true;
          _maybeResolveRound();
          break;
      }
    } else if (payload['type'] == 'game_reset' &&
        payload['gameId'] == 'reaction') {
      Provider.of<ConnectivityService>(context, listen: false)
          .sendPayload({'type': 'game_reset_accept', 'gameId': 'reaction'});
      _resetGame();
    } else if (payload['type'] == 'game_reset_accept' &&
        payload['gameId'] == 'reaction') {
      _resetGame();
    } else if (payload['type'] == 'game_exit') {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    _nextRoundTimer?.cancel();
    _msgSubscription?.cancel();
    super.dispose();
  }

  /// Host: picks a random delay and shares it, then arms locally.
  void _startRound() {
    if (!mounted || _isGameOver) return;
    final delay = 1500 + _rng.nextInt(2500);
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (svc.isConnected && svc.connectedPeer?.isMock != true) {
      svc.sendPayload({
        'type': 'game_move',
        'gameId': 'reaction',
        'data': {'subtype': 'round', 'delayMs': delay},
      });
    }
    _armRound(delay);
  }

  void _armRound(int delayMs) {
    _armTimer?.cancel();
    setState(() {
      _phase = _RoundPhase.armed;
      _myTimeMs = null;
      _oppTimeMs = null;
      _myFalseStart = false;
      _oppFalseStart = false;
      _greenAt = null;
      _roundMessage = '';
    });
    _armTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted || _phase != _RoundPhase.armed) return;
      setState(() {
        _phase = _RoundPhase.green;
        _greenAt = DateTime.now();
      });
      _simulateBotTap();
    });
  }

  void _simulateBotTap() {
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (svc.connectedPeer?.isMock != true) return;

    final (base, jitter) = switch (svc.botDifficulty) {
      'einfach' => (420, 180),
      'schwer' => (215, 60),
      _ => (300, 110),
    };
    final botMs = base + _rng.nextInt(jitter);
    Timer(Duration(milliseconds: botMs), () {
      if (!mounted || _phase == _RoundPhase.resolved || _isGameOver) return;
      _oppTimeMs = botMs;
      _maybeResolveRound();
    });
  }

  void _onTap() {
    if (_isGameOver) return;
    switch (_phase) {
      case _RoundPhase.armed:
        // Tapped too early!
        _armTimer?.cancel();
        _myFalseStart = true;
        final svc = Provider.of<ConnectivityService>(context, listen: false);
        if (svc.isConnected && svc.connectedPeer?.isMock != true) {
          svc.sendPayload({
            'type': 'game_move',
            'gameId': 'reaction',
            'data': {'subtype': 'false_start'},
          });
        }
        _resolveRound(myWon: false, message: 'Zu früh getippt! ❌');
        break;

      case _RoundPhase.green:
        if (_myTimeMs != null) return;
        _myTimeMs =
            DateTime.now().difference(_greenAt!).inMilliseconds.clamp(1, 9999);
        final svc = Provider.of<ConnectivityService>(context, listen: false);
        if (svc.isConnected && svc.connectedPeer?.isMock != true) {
          svc.sendPayload({
            'type': 'game_move',
            'gameId': 'reaction',
            'data': {'subtype': 'time', 'ms': _myTimeMs},
          });
        }
        setState(() {});
        _maybeResolveRound();
        break;

      default:
        break;
    }
  }

  void _maybeResolveRound() {
    if (_phase == _RoundPhase.resolved || _isGameOver) return;

    if (_oppFalseStart) {
      _resolveRound(
          myWon: true, message: 'Gegner hat zu früh getippt! ✅');
      return;
    }
    if (_myFalseStart) return; // already resolved in _onTap

    if (_myTimeMs != null && _oppTimeMs != null) {
      if (_myTimeMs == _oppTimeMs) {
        setState(() {
          _phase = _RoundPhase.resolved;
          _roundMessage = 'Exakt gleich schnell – Runde wird wiederholt!';
        });
        _scheduleNextRound();
        return;
      }
      final myWon = _myTimeMs! < _oppTimeMs!;
      _resolveRound(
        myWon: myWon,
        message: myWon
            ? 'Du warst schneller! (${_myTimeMs}ms vs. ${_oppTimeMs}ms)'
            : 'Gegner war schneller! (${_oppTimeMs}ms vs. ${_myTimeMs}ms)',
      );
    } else {
      setState(() {}); // show "waiting for opponent"
    }
  }

  void _resolveRound({required bool myWon, required String message}) {
    setState(() {
      _phase = _RoundPhase.resolved;
      _roundMessage = message;
      if (myWon) {
        _myWins++;
      } else {
        _oppWins++;
      }
      if (_myWins >= _winsNeeded || _oppWins >= _winsNeeded) {
        _isGameOver = true;
        _updateStats();
      }
    });
    if (!_isGameOver) _scheduleNextRound();
  }

  void _scheduleNextRound() {
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (svc.isHost || svc.connectedPeer?.isMock == true) {
      _nextRoundTimer?.cancel();
      _nextRoundTimer = Timer(const Duration(seconds: 2), _startRound);
    }
  }

  void _updateStats() {
    if (_statsUpdated) return;
    _statsUpdated = true;
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (_myWins > _oppWins) {
      svc.incrementWin('reaction');
    } else {
      svc.incrementLoss('reaction');
    }
  }

  void _requestReset() {
    setState(() => _waitingForResetAccept = true);
    Provider.of<ConnectivityService>(context, listen: false)
        .sendPayload({'type': 'game_reset', 'gameId': 'reaction'});
  }

  void _resetGame() {
    _armTimer?.cancel();
    _nextRoundTimer?.cancel();
    setState(() {
      _phase = _RoundPhase.idle;
      _myWins = 0;
      _oppWins = 0;
      _myTimeMs = null;
      _oppTimeMs = null;
      _myFalseStart = false;
      _oppFalseStart = false;
      _roundMessage = '';
      _isGameOver = false;
      _waitingForResetAccept = false;
      _statsUpdated = false;
    });
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (svc.isHost || svc.connectedPeer?.isMock == true) {
      _nextRoundTimer = Timer(const Duration(milliseconds: 1200), _startRound);
    }
  }

  Future<void> _exitGame() async {
    final shouldExit = await showExitGameDialog(context);
    if (!shouldExit || !mounted) return;
    Provider.of<ConnectivityService>(context, listen: false).exitGame();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final svc = Provider.of<ConnectivityService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!svc.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const SizedBox();
    }

    final (fieldColor, fieldText, fieldIcon) = switch (_phase) {
      _RoundPhase.idle => (
          Colors.blueGrey,
          'Gleich geht\'s los...',
          Icons.hourglass_top_rounded
        ),
      _RoundPhase.armed => (
          const Color(0xFFC62828),
          'Warte auf GRÜN...',
          Icons.front_hand_rounded
        ),
      _RoundPhase.green => (
          const Color(0xFF2E7D32),
          _myTimeMs == null ? 'TIPPE JETZT!' : 'Warte auf Gegner...',
          Icons.flash_on_rounded
        ),
      _RoundPhase.resolved => (
          Colors.blueGrey,
          _roundMessage,
          Icons.timer_rounded
        ),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitGame();
      },
      child: Scaffold(
        body: AppBackground(
          child: Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    GameHeader(title: 'Reaktionsduell', onExit: _exitGame),
                    const SizedBox(height: 8),
                    // Scoreboard
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: GlassContainer(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        borderRadius: 18,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _scoreColumn('DU', _myWins,
                                const Color(0xFF00F2FE)),
                            Text(
                              'Erster mit $_winsNeeded gewinnt',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                color:
                                    isDark ? Colors.white24 : Colors.black26,
                              ),
                            ),
                            _scoreColumn(
                                (svc.connectedPeer?.name ?? 'GEGNER')
                                    .toUpperCase(),
                                _oppWins,
                                AppTheme.accentNeonPink),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Tap field
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: GestureDetector(
                          onTapDown: (_) => _onTap(),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: fieldColor,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: fieldColor.withValues(alpha: 0.4),
                                  blurRadius: 24,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(fieldIcon,
                                    size: 72, color: Colors.white),
                                const SizedBox(height: 20),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24),
                                  child: Text(
                                    fieldText,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (_myTimeMs != null &&
                                    _phase == _RoundPhase.green) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    'Deine Zeit: ${_myTimeMs}ms',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 14),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_isGameOver) _buildGameOverOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scoreColumn(String label, int score, Color color) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey)),
        const SizedBox(height: 2),
        Text('$score',
            style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.w900, color: color)),
      ],
    );
  }

  Widget _buildGameOverOverlay() {
    final isWin = _myWins > _oppWins;
    return GameResultOverlay(
      title: isWin ? 'SIEG!' : 'NIEDERLAGE!',
      description: isWin
          ? 'Deine Reflexe sind blitzschnell!'
          : 'Dein Gegner hatte die schnelleren Reflexe!',
      color: isWin ? Colors.greenAccent : Colors.redAccent,
      icon: isWin ? Icons.emoji_events_rounded : Icons.bolt_rounded,
      extra: Text(
        'Endstand: $_myWins - $_oppWins',
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amber),
      ),
      onExit: _exitGame,
      onRematch: _requestReset,
      waitingForRematch: _waitingForResetAccept,
    );
  }
}
