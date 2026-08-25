import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

/// Streichholz-Duell (Misère-Nim): 21 matches, take 1-3 per turn.
/// Whoever has to take the LAST match loses.
class NimScreen extends StatefulWidget {
  const NimScreen({super.key});

  @override
  State<NimScreen> createState() => _NimScreenState();
}

class _NimScreenState extends State<NimScreen> {
  static const int _startCount = 21;

  int _remaining = _startCount;
  bool _myTurn = true;
  int _lastTaker = 0; // 1 = me, 2 = opponent
  int _lastTakeAmount = 0;
  bool _isGameOver = false;
  bool _waitingForResetAccept = false;
  bool _statsUpdated = false;
  bool _botThinking = false;

  final math.Random _rng = math.Random();
  StreamSubscription? _msgSubscription;

  @override
  void initState() {
    super.initState();
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    _myTurn = svc.isHost;

    _msgSubscription = svc.messageStream.listen((payload) {
      if (!mounted) return;
      if (payload['type'] == 'game_move' && payload['gameId'] == 'nim') {
        final data = payload['data'] as Map<String, dynamic>;
        if (data['subtype'] == 'take') {
          _applyTake(data['count'] as int, 2);
        }
      } else if (payload['type'] == 'game_reset' &&
          payload['gameId'] == 'nim') {
        svc.sendPayload({'type': 'game_reset_accept', 'gameId': 'nim'});
        _resetGame();
      } else if (payload['type'] == 'game_reset_accept' &&
          payload['gameId'] == 'nim') {
        _resetGame();
      } else if (payload['type'] == 'game_exit') {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _msgSubscription?.cancel();
    super.dispose();
  }

  void _applyTake(int count, int player) {
    setState(() {
      _remaining = math.max(0, _remaining - count);
      _lastTaker = player;
      _lastTakeAmount = count;
      _myTurn = player == 2;
      if (_remaining == 0) {
        _isGameOver = true;
        _updateStats();
      }
    });
    if (!_isGameOver && !_myTurn) _scheduleBotMove();
  }

  void _take(int count) {
    if (!_myTurn || _isGameOver || _botThinking) return;
    if (count < 1 || count > 3 || count > _remaining) return;

    _applyTake(count, 1);

    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (svc.isConnected && svc.connectedPeer?.isMock != true) {
      svc.sendPayload({
        'type': 'game_move',
        'gameId': 'nim',
        'data': {'subtype': 'take', 'count': count},
      });
    }
  }

  void _scheduleBotMove() {
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (svc.connectedPeer?.isMock != true || _botThinking) return;

    _botThinking = true;
    Timer(const Duration(milliseconds: 1200), () {
      _botThinking = false;
      if (!mounted || _isGameOver || _myTurn || _remaining == 0) return;

      final maxTake = math.min(3, _remaining);
      // Perfect misère play: leave the opponent with 1 (mod 4) matches.
      int perfect = (_remaining - 1) % 4;
      if (perfect == 0 || perfect > maxTake) {
        perfect = 1 + _rng.nextInt(maxTake);
      }
      final random = 1 + _rng.nextInt(maxTake);

      final take = switch (svc.botDifficulty) {
        'einfach' => random,
        'mittel' => _rng.nextDouble() < 0.6 ? perfect : random,
        _ => perfect,
      };

      _applyTake(take, 2);
    });
  }

  void _updateStats() {
    if (_statsUpdated) return;
    _statsUpdated = true;
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    // Whoever took the last match loses.
    if (_lastTaker == 2) {
      svc.incrementWin('nim');
    } else {
      svc.incrementLoss('nim');
    }
  }

  void _requestReset() {
    setState(() => _waitingForResetAccept = true);
    Provider.of<ConnectivityService>(context, listen: false)
        .sendPayload({'type': 'game_reset', 'gameId': 'nim'});
  }

  void _resetGame() {
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    setState(() {
      _remaining = _startCount;
      _myTurn = svc.isHost;
      _lastTaker = 0;
      _lastTakeAmount = 0;
      _isGameOver = false;
      _waitingForResetAccept = false;
      _statsUpdated = false;
      _botThinking = false;
    });
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

    if (!svc.hasSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const SizedBox();
    }

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final info = Column(
      children: [
        GlassContainer(
          padding: const EdgeInsets.all(14),
          borderRadius: 16,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Nimm 1-3 Streichhölzer. Wer das LETZTE nehmen muss, verliert!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _myTurn ? 'Du bist dran!' : '${svc.connectedPeer?.name} überlegt...',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: _myTurn
                ? (isDark ? const Color(0xFF00F2FE) : AppTheme.primaryPurple)
                : Colors.grey,
          ),
        ),
        if (_lastTaker != 0 && !_isGameOver) ...[
          const SizedBox(height: 6),
          Text(
            _lastTaker == 1
                ? 'Du hast $_lastTakeAmount genommen'
                : 'Gegner hat $_lastTakeAmount genommen',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ],
    );

    final matchesField = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: GlassContainer(
            borderRadius: 24,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_remaining',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Text('übrig',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: List.generate(_startCount, (i) {
                    final burned = i >= _remaining;
                    return AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: burned ? 0.15 : 1.0,
                      child: const _Matchstick(),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final takeButtons = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int count = 1; count <= 3; count++) ...[
            if (count > 1) const SizedBox(width: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryPurple,
                foregroundColor: Colors.white,
                disabledBackgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              ),
              onPressed: _myTurn && !_isGameOver && count <= _remaining
                  ? () => _take(count)
                  : null,
              child: Text('$count nehmen',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ],
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
                                      title: 'Streichholz-Duell',
                                      onExit: _exitGame),
                                  const SizedBox(height: 12),
                                  info,
                                  const SizedBox(height: 16),
                                  takeButtons,
                                ],
                              ),
                            ),
                          ),
                          Expanded(flex: 5, child: matchesField),
                        ],
                      )
                    : Column(
                        children: [
                          GameHeader(
                              title: 'Streichholz-Duell', onExit: _exitGame),
                          const SizedBox(height: 8),
                          info,
                          Expanded(child: matchesField),
                          takeButtons,
                          const SizedBox(height: 16),
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

  Widget _buildGameOverOverlay() {
    final isWin = _lastTaker == 2;
    return GameResultOverlay(
      title: isWin ? 'SIEG!' : 'NIEDERLAGE!',
      description: isWin
          ? 'Dein Gegner musste das letzte Streichholz nehmen!'
          : 'Du musstest das letzte Streichholz nehmen!',
      color: isWin ? Colors.greenAccent : Colors.redAccent,
      icon: isWin
          ? Icons.emoji_events_rounded
          : Icons.sentiment_very_dissatisfied_rounded,
      onExit: _exitGame,
      onRematch: _requestReset,
      waitingForRematch: _waitingForResetAccept,
    );
  }
}

class _Matchstick extends StatelessWidget {
  const _Matchstick();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.redAccent,
          ),
        ),
        Container(
          width: 5,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFE6C280),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 200.ms);
  }
}
