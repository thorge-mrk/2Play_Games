import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

/// Memory (Paare finden): 4x4 cards, matching a pair grants an extra turn.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  static const List<String> _symbols = [
    '🎮', '🚀', '🌟', '🍕', '🐙', '🎲', '🌈', '⚽'
  ];

  List<int> _cards = []; // pair ids, host generates & syncs
  List<int> _owner = List.filled(16, 0); // 0 = unmatched, 1 = me, 2 = opponent
  int? _firstFlip;
  int? _secondFlip;
  bool _busy = false;
  bool _myTurn = true;
  int _myPairs = 0;
  int _oppPairs = 0;
  bool _isGameOver = false;
  bool _waitingForResetAccept = false;
  bool _statsUpdated = false;

  final Set<int> _botSeen = {};
  final math.Random _rng = math.Random();
  StreamSubscription? _msgSubscription;
  bool _boardRequested = false;

  @override
  void initState() {
    super.initState();
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    _myTurn = svc.isHost;

    _msgSubscription = svc.messageStream.listen(_onMessage);

    if (svc.isHost || svc.connectedPeer?.isMock == true) {
      _generateBoard();
      if (svc.connectedPeer?.isMock != true) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _sendBoard());
      }
    }
  }

  void _generateBoard() {
    final cards = [for (int i = 0; i < 8; i++) ...[i, i]];
    cards.shuffle(_rng);
    _cards = cards;
  }

  void _sendBoard() {
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (!svc.isConnected) return;
    svc.sendPayload({
      'type': 'game_move',
      'gameId': 'memory',
      'data': {'subtype': 'board', 'cards': _cards},
    });
  }

  void _onMessage(Map<String, dynamic> payload) {
    if (!mounted) return;
    if (payload['type'] == 'game_move' && payload['gameId'] == 'memory') {
      final data = payload['data'] as Map<String, dynamic>;
      switch (data['subtype'] as String?) {
        case 'board':
          setState(() => _cards = List<int>.from(data['cards']));
          break;
        case 'board_request':
          _sendBoard();
          break;
        case 'flip':
          _applyOpponentFlip(data['a'] as int, data['b'] as int);
          break;
      }
    } else if (payload['type'] == 'game_reset' &&
        payload['gameId'] == 'memory') {
      Provider.of<ConnectivityService>(context, listen: false).sendPayload(
          {'type': 'game_reset_accept', 'gameId': 'memory'});
      _resetBoard();
    } else if (payload['type'] == 'game_reset_accept' &&
        payload['gameId'] == 'memory') {
      _resetBoard();
    } else if (payload['type'] == 'game_exit') {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _msgSubscription?.cancel();
    super.dispose();
  }

  /// Shows the opponent's two flips and applies the outcome.
  void _applyOpponentFlip(int a, int b) {
    setState(() {
      _firstFlip = a;
      _secondFlip = b;
      _busy = true;
    });
    Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        if (_cards[a] == _cards[b]) {
          _owner[a] = 2;
          _owner[b] = 2;
          _oppPairs++;
          // Opponent keeps the turn on a match.
        } else {
          _myTurn = true;
        }
        _firstFlip = null;
        _secondFlip = null;
        _busy = false;
        _checkGameOver();
      });
    });
  }

  void _tapCard(int index) {
    if (!_myTurn || _busy || _isGameOver || _cards.isEmpty) return;
    if (_owner[index] != 0 || index == _firstFlip) return;

    _botSeen.add(index);

    if (_firstFlip == null) {
      setState(() => _firstFlip = index);
      return;
    }

    setState(() {
      _secondFlip = index;
      _busy = true;
    });

    final a = _firstFlip!;
    final b = index;
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (svc.isConnected && svc.connectedPeer?.isMock != true) {
      svc.sendPayload({
        'type': 'game_move',
        'gameId': 'memory',
        'data': {'subtype': 'flip', 'a': a, 'b': b},
      });
    }

    Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        final match = _cards[a] == _cards[b];
        if (match) {
          _owner[a] = 1;
          _owner[b] = 1;
          _myPairs++;
        } else {
          _myTurn = false;
        }
        _firstFlip = null;
        _secondFlip = null;
        _busy = false;
        _checkGameOver();
      });
      if (!_myTurn && !_isGameOver) _scheduleBotMove();
    });
  }

  void _scheduleBotMove() {
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (svc.connectedPeer?.isMock != true) return;

    Timer(const Duration(milliseconds: 1100), () {
      if (!mounted || _isGameOver || _myTurn) return;

      final memoryChance = switch (svc.botDifficulty) {
        'einfach' => 0.25,
        'schwer' => 0.9,
        _ => 0.55,
      };

      final free = [
        for (int i = 0; i < 16; i++)
          if (_owner[i] == 0) i
      ];
      if (free.length < 2) return;

      int a = -1, b = -1;

      // Remembered pair?
      if (_rng.nextDouble() < memoryChance) {
        final seenFree = _botSeen.where((i) => _owner[i] == 0).toList();
        outer:
        for (final i in seenFree) {
          for (final j in seenFree) {
            if (i != j && _cards[i] == _cards[j]) {
              a = i;
              b = j;
              break outer;
            }
          }
        }
      }

      if (a == -1) {
        // Prefer exploring cards the bot has not seen yet.
        final unseen = free.where((i) => !_botSeen.contains(i)).toList();
        a = unseen.isNotEmpty
            ? unseen[_rng.nextInt(unseen.length)]
            : free[_rng.nextInt(free.length)];
        // Does the first card match something remembered?
        if (_rng.nextDouble() < memoryChance) {
          for (final j in _botSeen) {
            if (j != a && _owner[j] == 0 && _cards[j] == _cards[a]) {
              b = j;
              break;
            }
          }
        }
        if (b == -1) {
          final others = free.where((i) => i != a).toList();
          b = others[_rng.nextInt(others.length)];
        }
      }

      _botSeen.addAll([a, b]);

      final first = a;
      final second = b;
      setState(() {
        _firstFlip = first;
        _busy = true;
      });
      Timer(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        setState(() => _secondFlip = second);
        Timer(const Duration(milliseconds: 900), () {
          if (!mounted) return;
          setState(() {
            final match = _cards[first] == _cards[second];
            if (match) {
              _owner[first] = 2;
              _owner[second] = 2;
              _oppPairs++;
            } else {
              _myTurn = true;
            }
            _firstFlip = null;
            _secondFlip = null;
            _busy = false;
            _checkGameOver();
          });
          if (!_myTurn && !_isGameOver) _scheduleBotMove();
        });
      });
    });
  }

  void _checkGameOver() {
    if (_myPairs + _oppPairs < 8) return;
    _isGameOver = true;
    if (_statsUpdated) return;
    _statsUpdated = true;
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (_myPairs > _oppPairs) {
      svc.incrementWin('memory');
    } else if (_myPairs < _oppPairs) {
      svc.incrementLoss('memory');
    }
  }

  void _requestReset() {
    setState(() => _waitingForResetAccept = true);
    Provider.of<ConnectivityService>(context, listen: false)
        .sendPayload({'type': 'game_reset', 'gameId': 'memory'});
  }

  void _resetBoard() {
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    setState(() {
      _owner = List.filled(16, 0);
      _firstFlip = null;
      _secondFlip = null;
      _busy = false;
      _myPairs = 0;
      _oppPairs = 0;
      _isGameOver = false;
      _waitingForResetAccept = false;
      _statsUpdated = false;
      _botSeen.clear();
      _myTurn = svc.isHost;
      if (svc.isHost || svc.connectedPeer?.isMock == true) {
        _generateBoard();
        if (svc.connectedPeer?.isMock != true) _sendBoard();
      } else {
        _cards = [];
      }
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

    // Guest without a board yet? Ask the host once.
    if (_cards.isEmpty && !svc.isHost && !_boardRequested) {
      _boardRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        svc.sendPayload({
          'type': 'game_move',
          'gameId': 'memory',
          'data': {'subtype': 'board_request'},
        });
      });
    }

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final scoreRow = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ScoreChip(
            label: 'Du: $_myPairs Paare',
            active: _myTurn && !_isGameOver,
            color: AppTheme.accentNeonCyan,
          ),
          _ScoreChip(
            label:
                '${svc.connectedPeer?.name ?? 'Gegner'}: $_oppPairs Paare',
            active: !_myTurn && !_isGameOver,
            color: AppTheme.accentNeonPink,
          ),
        ],
      ),
    );

    final grid = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 480),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _cards.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: 16,
                    itemBuilder: (context, index) {
                      final revealed = _owner[index] != 0 ||
                          index == _firstFlip ||
                          index == _secondFlip;
                      return _MemoryCard(
                        symbol: _symbols[_cards[index]],
                        revealed: revealed,
                        owner: _owner[index],
                        isDark: isDark,
                        onTap: () => _tapCard(index),
                      );
                    },
                  ),
          ),
        ),
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
                                      title: 'Memory', onExit: _exitGame),
                                  const SizedBox(height: 16),
                                  scoreRow,
                                ],
                              ),
                            ),
                          ),
                          Expanded(flex: 5, child: grid),
                        ],
                      )
                    : Column(
                        children: [
                          GameHeader(title: 'Memory', onExit: _exitGame),
                          const SizedBox(height: 8),
                          scoreRow,
                          Expanded(child: grid),
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
    final isWin = _myPairs > _oppPairs;
    final isDraw = _myPairs == _oppPairs;
    return GameResultOverlay(
      title: isDraw ? 'UNENTSCHIEDEN!' : (isWin ? 'SIEG!' : 'NIEDERLAGE!'),
      description: 'Endstand: $_myPairs - $_oppPairs Paare',
      color: isWin
          ? Colors.greenAccent
          : (isDraw ? Colors.amberAccent : Colors.redAccent),
      icon: isWin
          ? Icons.emoji_events_rounded
          : (isDraw
              ? Icons.handshake_rounded
              : Icons.sentiment_very_dissatisfied_rounded),
      onExit: _exitGame,
      onRematch: _requestReset,
      waitingForRematch: _waitingForResetAccept,
    );
  }
}

class _MemoryCard extends StatelessWidget {
  final String symbol;
  final bool revealed;
  final int owner;
  final bool isDark;
  final VoidCallback onTap;

  const _MemoryCard({
    required this.symbol,
    required this.revealed,
    required this.owner,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = owner == 1
        ? AppTheme.accentNeonCyan
        : owner == 2
            ? AppTheme.accentNeonPink
            : (isDark ? Colors.white12 : Colors.black12);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: revealed
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white)
              : (isDark ? const Color(0xFF1B1437) : AppTheme.primaryPurple),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: owner != 0 ? AppTheme.neonGlow(borderColor) : null,
        ),
        child: Center(
          child: revealed
              ? Text(symbol, style: const TextStyle(fontSize: 30))
                  .animate()
                  .scaleXY(begin: 0.4, end: 1.0, duration: 200.ms)
              : const Icon(Icons.question_mark_rounded,
                  color: Colors.white54, size: 22),
        ),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;

  const _ScoreChip(
      {required this.label, required this.active, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color:
            active ? color.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: active ? color : Colors.transparent, width: 1.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: active ? color : Colors.grey,
        ),
      ),
    );
  }
}
