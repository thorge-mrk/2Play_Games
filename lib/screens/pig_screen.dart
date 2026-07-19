import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

/// Würfelduell (Pig): roll the die and collect points. A 1 loses the
/// turn points – bank in time! First player to 50 wins.
class PigScreen extends StatefulWidget {
  const PigScreen({super.key});

  @override
  State<PigScreen> createState() => _PigScreenState();
}

class _PigScreenState extends State<PigScreen> {
  static const int _target = 50;

  int _myTotal = 0;
  int _oppTotal = 0;
  int _turnPoints = 0;
  int _lastRoll = 0;
  bool _myTurn = true;
  bool _rolling = false;
  bool _botPlaying = false;
  String _statusText = '';
  bool _isGameOver = false;
  bool _iWon = false;
  bool _waitingForResetAccept = false;
  bool _statsUpdated = false;

  final math.Random _rng = math.Random();
  StreamSubscription? _msgSubscription;
  final List<Timer> _botTimers = [];

  @override
  void initState() {
    super.initState();
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    _myTurn = svc.isHost;

    _msgSubscription = svc.messageStream.listen(_onMessage);
  }

  void _onMessage(Map<String, dynamic> payload) {
    if (!mounted) return;
    if (payload['type'] == 'game_move' && payload['gameId'] == 'pig') {
      final data = payload['data'] as Map<String, dynamic>;
      switch (data['subtype'] as String?) {
        case 'roll':
          setState(() {
            _lastRoll = data['value'] as int;
            _turnPoints = data['turnPoints'] as int;
            _statusText = _lastRoll == 1
                ? 'Gegner hat eine 1 gewürfelt – Punkte weg!'
                : 'Gegner würfelt: $_lastRoll';
          });
          break;
        case 'turn_end':
          setState(() {
            _oppTotal = data['total'] as int;
            _turnPoints = 0;
            _lastRoll = 0;
            _myTurn = true;
            _statusText = data['busted'] == true
                ? 'Gegner hat verloren – du bist dran!'
                : 'Gegner hat ${data['gained']} Punkte gebankt – du bist dran!';
            _checkWin();
          });
          break;
      }
    } else if (payload['type'] == 'game_reset' && payload['gameId'] == 'pig') {
      Provider.of<ConnectivityService>(context, listen: false)
          .sendPayload({'type': 'game_reset_accept', 'gameId': 'pig'});
      _resetGame();
    } else if (payload['type'] == 'game_reset_accept' &&
        payload['gameId'] == 'pig') {
      _resetGame();
    } else if (payload['type'] == 'game_exit') {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    for (final t in _botTimers) {
      t.cancel();
    }
    _msgSubscription?.cancel();
    super.dispose();
  }

  void _sendMove(Map<String, dynamic> data) {
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (svc.isConnected && svc.connectedPeer?.isMock != true) {
      svc.sendPayload({'type': 'game_move', 'gameId': 'pig', 'data': data});
    }
  }

  void _roll() {
    if (!_myTurn || _isGameOver || _rolling || _botPlaying) return;
    setState(() => _rolling = true);

    Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      final value = 1 + _rng.nextInt(6);
      setState(() {
        _rolling = false;
        _lastRoll = value;
        if (value == 1) {
          _statusText = 'Eine 1! Alle Rundenpunkte verloren.';
          _turnPoints = 0;
        } else {
          _turnPoints += value;
          _statusText = 'Gewürfelt: $value';
        }
      });

      if (value == 1) {
        _sendMove({'subtype': 'roll', 'value': 1, 'turnPoints': 0});
        _endMyTurn(busted: true);
      } else {
        _sendMove(
            {'subtype': 'roll', 'value': value, 'turnPoints': _turnPoints});
      }
    });
  }

  void _bank() {
    if (!_myTurn || _isGameOver || _rolling || _turnPoints == 0) return;
    setState(() {
      _myTotal += _turnPoints;
      _statusText = 'Du hast $_turnPoints Punkte gebankt!';
    });
    _endMyTurn(busted: false);
  }

  void _endMyTurn({required bool busted}) {
    final gained = busted ? 0 : _turnPoints;
    setState(() {
      _turnPoints = 0;
      _myTurn = false;
      _checkWin();
    });
    _sendMove({
      'subtype': 'turn_end',
      'total': _myTotal,
      'gained': gained,
      'busted': busted,
    });
    if (!_isGameOver) _startBotTurn();
  }

  // ── Bot ───────────────────────────────────────────────────────────────────

  void _startBotTurn() {
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (svc.connectedPeer?.isMock != true || _botPlaying) return;

    _botPlaying = true;
    int botTurnPoints = 0;

    final int bankAt = switch (svc.botDifficulty) {
      'einfach' => 10 + _rng.nextInt(6),
      'mittel' => 16 + _rng.nextInt(5),
      _ => math.min(22, math.max(14, _target - _oppTotal)),
    };

    void step() {
      final t = Timer(const Duration(milliseconds: 900), () {
        if (!mounted || _isGameOver) {
          _botPlaying = false;
          return;
        }
        final value = 1 + _rng.nextInt(6);
        if (value == 1) {
          setState(() {
            _lastRoll = 1;
            _statusText = 'Bot würfelt eine 1 – Punkte weg! Du bist dran.';
            _myTurn = true;
          });
          _botPlaying = false;
          return;
        }
        botTurnPoints += value;
        setState(() {
          _lastRoll = value;
          _statusText = 'Bot würfelt $value (Runde: $botTurnPoints)';
        });

        if (botTurnPoints >= bankAt ||
            _oppTotal + botTurnPoints >= _target) {
          final t2 = Timer(const Duration(milliseconds: 800), () {
            if (!mounted) return;
            setState(() {
              _oppTotal += botTurnPoints;
              _statusText =
                  'Bot bankt $botTurnPoints Punkte. Du bist dran!';
              _myTurn = true;
              _checkWin();
            });
            _botPlaying = false;
          });
          _botTimers.add(t2);
        } else {
          step();
        }
      });
      _botTimers.add(t);
    }

    step();
  }

  void _checkWin() {
    if (_isGameOver) return;
    if (_myTotal >= _target) {
      _isGameOver = true;
      _iWon = true;
      _updateStats();
    } else if (_oppTotal >= _target) {
      _isGameOver = true;
      _iWon = false;
      _updateStats();
    }
  }

  void _updateStats() {
    if (_statsUpdated) return;
    _statsUpdated = true;
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (_iWon) {
      svc.incrementWin('pig');
    } else {
      svc.incrementLoss('pig');
    }
  }

  void _requestReset() {
    setState(() => _waitingForResetAccept = true);
    Provider.of<ConnectivityService>(context, listen: false)
        .sendPayload({'type': 'game_reset', 'gameId': 'pig'});
  }

  void _resetGame() {
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    for (final t in _botTimers) {
      t.cancel();
    }
    _botTimers.clear();
    setState(() {
      _myTotal = 0;
      _oppTotal = 0;
      _turnPoints = 0;
      _lastRoll = 0;
      _myTurn = svc.isHost;
      _rolling = false;
      _botPlaying = false;
      _statusText = '';
      _isGameOver = false;
      _iWon = false;
      _waitingForResetAccept = false;
      _statsUpdated = false;
    });
  }

  Future<void> _exitGame() async {
    final shouldExit = await showExitGameDialog(context);
    if (!shouldExit || !mounted) return;
    Provider.of<ConnectivityService>(context, listen: false).exitGame();
    if (mounted) Navigator.of(context).pop();
  }

  static const List<IconData> _diceIcons = [
    Icons.casino_outlined,
    Icons.looks_one_rounded,
    Icons.looks_two_rounded,
    Icons.looks_3_rounded,
    Icons.looks_4_rounded,
    Icons.looks_5_rounded,
    Icons.looks_6_rounded,
  ];

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

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final scoreboard = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        borderRadius: 18,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _totalColumn('DU', _myTotal, const Color(0xFF00F2FE),
                _myTurn && !_isGameOver),
            Column(
              children: [
                Text(
                  'ZIEL: $_target',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Runde: $_turnPoints',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
              ],
            ),
            _totalColumn(
                (svc.connectedPeer?.name ?? 'GEGNER').toUpperCase(),
                _oppTotal,
                AppTheme.accentNeonPink,
                !_myTurn && !_isGameOver),
          ],
        ),
      ),
    );

    final dieArea = Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              _rolling
                  ? Icons.casino_rounded
                  : _diceIcons[_lastRoll.clamp(0, 6)],
              key: ValueKey('$_rolling-$_lastRoll'),
              size: 110,
              color: _lastRoll == 1 && !_rolling
                  ? Colors.redAccent
                  : (isDark ? Colors.white : AppTheme.primaryPurple),
            ),
          )
              .animate(target: _rolling ? 1.0 : 0.0)
              .shake(duration: 400.ms, hz: 6),
          const SizedBox(height: 16),
          SizedBox(
            height: 40,
            child: Text(
              _statusText.isEmpty
                  ? (_myTurn
                      ? 'Du bist dran – würfle!'
                      : 'Gegner ist am Zug...')
                  : _statusText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );

    final buttons = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed:
                  _myTurn && !_isGameOver && !_rolling && !_botPlaying
                      ? _roll
                      : null,
              icon: const Icon(Icons.casino_rounded, size: 20),
              label: const Text('Würfeln',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _myTurn &&
                      !_isGameOver &&
                      !_rolling &&
                      _turnPoints > 0
                  ? _bank
                  : null,
              icon: const Icon(Icons.savings_rounded, size: 20),
              label: Text('Bank ($_turnPoints)',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );

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
                child: isLandscape
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 4,
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  GameHeader(
                                      title: 'Würfelduell',
                                      onExit: _exitGame),
                                  const SizedBox(height: 12),
                                  scoreboard,
                                  const SizedBox(height: 20),
                                  buttons,
                                ],
                              ),
                            ),
                          ),
                          Expanded(flex: 5, child: dieArea),
                        ],
                      )
                    : Column(
                        children: [
                          GameHeader(
                              title: 'Würfelduell', onExit: _exitGame),
                          const SizedBox(height: 8),
                          scoreboard,
                          Expanded(child: dieArea),
                          buttons,
                          const SizedBox(height: 20),
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

  Widget _totalColumn(String label, int total, Color color, bool active) {
    return Column(
      children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: active ? color : Colors.grey)),
        const SizedBox(height: 2),
        Text('$total',
            style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.w900, color: color)),
      ],
    );
  }

  Widget _buildGameOverOverlay() {
    return GameResultOverlay(
      title: _iWon ? 'SIEG!' : 'NIEDERLAGE!',
      description: _iWon
          ? 'Du hast zuerst $_target Punkte erreicht!'
          : 'Dein Gegner hat zuerst $_target Punkte erreicht!',
      color: _iWon ? Colors.greenAccent : Colors.redAccent,
      icon: _iWon
          ? Icons.emoji_events_rounded
          : Icons.sentiment_very_dissatisfied_rounded,
      extra: Text(
        'Endstand: $_myTotal - $_oppTotal',
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amber),
      ),
      onExit: _exitGame,
      onRematch: _requestReset,
      waitingForRematch: _waitingForResetAccept,
    );
  }
}
