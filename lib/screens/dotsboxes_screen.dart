import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

/// Käsekästchen (Dots and Boxes) on a 4x4 box grid.
/// Completing a box grants an extra turn.
class DotsBoxesScreen extends StatefulWidget {
  const DotsBoxesScreen({super.key});

  @override
  State<DotsBoxesScreen> createState() => _DotsBoxesScreenState();
}

class _DotsBoxesScreenState extends State<DotsBoxesScreen> {
  static const int n = 4; // boxes per side

  // Edge owners: 0 = free, 1 = me/host, 2 = opponent/guest.
  // _h[r][c]: horizontal edge above box row r (r: 0..n), c: 0..n-1
  // _v[r][c]: vertical edge left of box col c (r: 0..n-1, c: 0..n)
  List<List<int>> _h = List.generate(n + 1, (_) => List.filled(n, 0));
  List<List<int>> _v = List.generate(n, (_) => List.filled(n + 1, 0));
  List<List<int>> _boxes = List.generate(n, (_) => List.filled(n, 0));

  late int _myNumber;
  late int _oppNumber;
  int _currentTurn = 1;
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
    _myNumber = svc.isHost ? 1 : 2;
    _oppNumber = svc.isHost ? 2 : 1;

    _msgSubscription = svc.messageStream.listen((payload) {
      if (!mounted) return;
      if (payload['type'] == 'game_move' &&
          payload['gameId'] == 'dotsboxes') {
        final data = payload['data'] as Map<String, dynamic>;
        if (data['subtype'] == 'edge') {
          setState(() {
            _applyEdge(data['o'] as String, data['r'] as int,
                data['c'] as int, _oppNumber);
          });
        }
      } else if (payload['type'] == 'game_reset' &&
          payload['gameId'] == 'dotsboxes') {
        svc.sendPayload({'type': 'game_reset_accept', 'gameId': 'dotsboxes'});
        _resetBoard();
      } else if (payload['type'] == 'game_reset_accept' &&
          payload['gameId'] == 'dotsboxes') {
        _resetBoard();
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

  int _myBoxes() =>
      [for (final row in _boxes) ...row].where((o) => o == _myNumber).length;
  int _oppBoxes() =>
      [for (final row in _boxes) ...row].where((o) => o == _oppNumber).length;

  int _sidesOfBox(int r, int c) {
    int sides = 0;
    if (_h[r][c] != 0) sides++;
    if (_h[r + 1][c] != 0) sides++;
    if (_v[r][c] != 0) sides++;
    if (_v[r][c + 1] != 0) sides++;
    return sides;
  }

  /// Claims an edge for [player]; returns the number of boxes completed.
  int _applyEdge(String o, int r, int c, int player) {
    if (o == 'h') {
      if (_h[r][c] != 0) return 0;
      _h[r][c] = player;
    } else {
      if (_v[r][c] != 0) return 0;
      _v[r][c] = player;
    }

    int completed = 0;
    for (int br = 0; br < n; br++) {
      for (int bc = 0; bc < n; bc++) {
        if (_boxes[br][bc] == 0 && _sidesOfBox(br, bc) == 4) {
          _boxes[br][bc] = player;
          completed++;
        }
      }
    }

    if (completed == 0) {
      _currentTurn = player == 1 ? 2 : 1;
    }
    _checkGameOver();
    if (!_isGameOver && _currentTurn == _oppNumber) _scheduleBotMove();
    return completed;
  }

  void _tapEdge(String o, int r, int c) {
    if (_isGameOver || _currentTurn != _myNumber || _botThinking) return;
    final taken = o == 'h' ? _h[r][c] != 0 : _v[r][c] != 0;
    if (taken) return;

    setState(() => _applyEdge(o, r, c, _myNumber));

    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (svc.isConnected && svc.connectedPeer?.isMock != true) {
      svc.sendPayload({
        'type': 'game_move',
        'gameId': 'dotsboxes',
        'data': {'subtype': 'edge', 'o': o, 'r': r, 'c': c},
      });
    }
  }

  // ── Bot ───────────────────────────────────────────────────────────────────

  List<(String, int, int)> _freeEdges() => [
        for (int r = 0; r <= n; r++)
          for (int c = 0; c < n; c++)
            if (_h[r][c] == 0) ('h', r, c),
        for (int r = 0; r < n; r++)
          for (int c = 0; c <= n; c++)
            if (_v[r][c] == 0) ('v', r, c),
      ];

  /// Would claiming this edge complete at least one box?
  bool _completesBox(String o, int r, int c) =>
      _boxesTouched(o, r, c).any((b) => _sidesOfBox(b.$1, b.$2) == 3);

  /// Would claiming this edge give a box away (create a 3-sided box)?
  bool _givesAwayBox(String o, int r, int c) =>
      _boxesTouched(o, r, c).any((b) => _sidesOfBox(b.$1, b.$2) == 2);

  List<(int, int)> _boxesTouched(String o, int r, int c) {
    if (o == 'h') {
      return [
        if (r < n) (r, c),
        if (r > 0) (r - 1, c),
      ];
    }
    return [
      if (c < n) (r, c),
      if (c > 0) (r, c - 1),
    ];
  }

  void _scheduleBotMove() {
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (svc.connectedPeer?.isMock != true || _botThinking) return;

    _botThinking = true;
    Timer(const Duration(milliseconds: 900), () {
      _botThinking = false;
      if (!mounted || _isGameOver || _currentTurn != _oppNumber) return;

      final free = _freeEdges();
      if (free.isEmpty) return;

      final difficulty = svc.botDifficulty;
      (String, int, int)? pick;

      // 1. Complete a box when possible (einfach misses this half the time).
      final closers =
          free.where((e) => _completesBox(e.$1, e.$2, e.$3)).toList();
      if (closers.isNotEmpty &&
          (difficulty != 'einfach' || _rng.nextBool())) {
        pick = closers[_rng.nextInt(closers.length)];
      }

      // 2. Otherwise pick a safe edge (does not hand a box to the player).
      if (pick == null) {
        final safe =
            free.where((e) => !_givesAwayBox(e.$1, e.$2, e.$3)).toList();
        final useSafe = switch (difficulty) {
          'einfach' => _rng.nextDouble() < 0.3,
          'mittel' => _rng.nextDouble() < 0.8,
          _ => true,
        };
        if (useSafe && safe.isNotEmpty) {
          pick = safe[_rng.nextInt(safe.length)];
        }
      }

      pick ??= free[_rng.nextInt(free.length)];

      setState(() => _applyEdge(pick!.$1, pick.$2, pick.$3, _oppNumber));
    });
  }

  void _checkGameOver() {
    if (_myBoxes() + _oppBoxes() < n * n) return;
    _isGameOver = true;
    if (_statsUpdated) return;
    _statsUpdated = true;
    final svc = Provider.of<ConnectivityService>(context, listen: false);
    if (_myBoxes() > _oppBoxes()) {
      svc.incrementWin('dotsboxes');
    } else if (_myBoxes() < _oppBoxes()) {
      svc.incrementLoss('dotsboxes');
    }
  }

  void _requestReset() {
    setState(() => _waitingForResetAccept = true);
    Provider.of<ConnectivityService>(context, listen: false)
        .sendPayload({'type': 'game_reset', 'gameId': 'dotsboxes'});
  }

  void _resetBoard() {
    setState(() {
      _h = List.generate(n + 1, (_) => List.filled(n, 0));
      _v = List.generate(n, (_) => List.filled(n + 1, 0));
      _boxes = List.generate(n, (_) => List.filled(n, 0));
      _currentTurn = 1;
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

    if (!svc.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const SizedBox();
    }

    final isMyTurn = _currentTurn == _myNumber;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final scoreRow = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _score('Du: ${_myBoxes()}', isMyTurn && !_isGameOver,
              AppTheme.accentNeonCyan),
          _score(
              '${svc.connectedPeer?.name ?? 'Gegner'}: ${_oppBoxes()}',
              !isMyTurn && !_isGameOver,
              AppTheme.accentNeonPink),
        ],
      ),
    );

    final board = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 460),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: GlassContainer(
              borderRadius: 24,
              padding: const EdgeInsets.all(16),
              child: _buildGrid(isDark),
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
                                      title: 'Käsekästchen',
                                      onExit: _exitGame),
                                  const SizedBox(height: 16),
                                  scoreRow,
                                  const SizedBox(height: 16),
                                  _turnHint(isMyTurn, isDark),
                                ],
                              ),
                            ),
                          ),
                          Expanded(flex: 5, child: board),
                        ],
                      )
                    : Column(
                        children: [
                          GameHeader(
                              title: 'Käsekästchen', onExit: _exitGame),
                          const SizedBox(height: 8),
                          scoreRow,
                          Expanded(child: board),
                          _turnHint(isMyTurn, isDark),
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

  Widget _turnHint(bool isMyTurn, bool isDark) {
    return Text(
      isMyTurn
          ? 'Du bist dran – tippe auf eine Linie!'
          : 'Gegner ist am Zug...',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: isMyTurn
            ? (isDark ? const Color(0xFF00F2FE) : AppTheme.primaryPurple)
            : Colors.grey,
      ),
    );
  }

  Widget _score(String label, bool active, Color color) {
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

  Widget _buildGrid(bool isDark) {
    const dot = 10.0;
    final dotColor = isDark ? Colors.white70 : Colors.black87;

    Color edgeColor(int owner) {
      if (owner == 0) {
        return isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.08);
      }
      return owner == _myNumber
          ? AppTheme.accentNeonCyan
          : AppTheme.accentNeonPink;
    }

    Color boxColor(int owner) {
      if (owner == 0) return Colors.transparent;
      return (owner == _myNumber
              ? AppTheme.accentNeonCyan
              : AppTheme.accentNeonPink)
          .withValues(alpha: 0.25);
    }

    Widget dotWidget() => Container(
          width: dot,
          height: dot,
          decoration:
              BoxDecoration(shape: BoxShape.circle, color: dotColor),
        );

    final rows = <Widget>[];
    for (int r = 0; r <= n; r++) {
      // Dot row with horizontal edges
      rows.add(SizedBox(
        height: dot,
        child: Row(
          children: [
            for (int c = 0; c < n; c++) ...[
              dotWidget(),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _tapEdge('h', r, c),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: edgeColor(_h[r][c]),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            dotWidget(),
          ],
        ),
      ));
      // Box row with vertical edges
      if (r < n) {
        rows.add(Expanded(
          child: Row(
            children: [
              for (int c = 0; c <= n; c++) ...[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _tapEdge('v', r, c),
                  child: SizedBox(
                    width: dot,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 5,
                        margin: const EdgeInsets.symmetric(vertical: 1),
                        height: double.infinity,
                        decoration: BoxDecoration(
                          color: edgeColor(_v[r][c]),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
                if (c < n)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: boxColor(_boxes[r][c]),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _boxes[r][c] != 0
                          ? Center(
                              child: Icon(
                                _boxes[r][c] == _myNumber
                                    ? Icons.person_rounded
                                    : Icons.smart_toy_rounded,
                                size: 18,
                                color: _boxes[r][c] == _myNumber
                                    ? AppTheme.accentNeonCyan
                                    : AppTheme.accentNeonPink,
                              ),
                            )
                          : null,
                    ),
                  ),
              ],
            ],
          ),
        ));
      }
    }

    return Column(children: rows);
  }

  Widget _buildGameOverOverlay() {
    final me = _myBoxes();
    final opp = _oppBoxes();
    final isWin = me > opp;
    final isDraw = me == opp;
    return GameResultOverlay(
      title: isDraw ? 'UNENTSCHIEDEN!' : (isWin ? 'SIEG!' : 'NIEDERLAGE!'),
      description: 'Endstand: $me - $opp Kästchen',
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
