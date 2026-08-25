import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

class ConnectFourScreen extends StatefulWidget {
  const ConnectFourScreen({super.key});

  @override
  State<ConnectFourScreen> createState() => _ConnectFourScreenState();
}

class _ConnectFourScreenState extends State<ConnectFourScreen> {
  // 7 columns, 6 rows. 0 = Empty, 1 = Player 1 (Host), 2 = Player 2 (Guest)
  List<List<int>> _board = List.generate(7, (_) => List.filled(6, 0));

  late int _myPlayerNumber;
  late int _opponentPlayerNumber;
  int _currentTurn = 1; // Player 1 starts
  StreamSubscription? _msgSubscription;
  bool _isGameOver = false;
  int _winnerNum = 0; // 0 = None, 1 = P1, 2 = P2, 3 = Draw
  bool _waitingForResetAccept = false;
  bool _statsUpdated = false;

  int _lastCol = -1;
  int _lastRow = -1;

  @override
  void initState() {
    super.initState();
    final connService =
        Provider.of<ConnectivityService>(context, listen: false);

    _myPlayerNumber = connService.isHost ? 1 : 2;
    _opponentPlayerNumber = connService.isHost ? 2 : 1;

    _msgSubscription = connService.messageStream.listen((payload) {
      if (!mounted) return;
      if (payload['type'] == 'game_move' && payload['gameId'] == 'connect4') {
        final moveData = payload['data'] as Map<String, dynamic>;
        setState(() {
          _board = [
            for (final col in moveData['board'] as List) List<int>.from(col)
          ];
          _lastCol = moveData['playedCol'] as int;
          _lastRow = moveData['playedRow'] as int;
          _currentTurn = moveData['nextTurn'] as int;
          _checkWinner();
        });
      } else if (payload['type'] == 'game_reset' &&
          payload['gameId'] == 'connect4') {
        connService.sendPayload({
          'type': 'game_reset_accept',
          'gameId': 'connect4',
        });
        _resetBoard();
      } else if (payload['type'] == 'game_reset_accept' &&
          payload['gameId'] == 'connect4') {
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

  void _playColumn(int colIndex) {
    if (_isGameOver || _currentTurn != _myPlayerNumber) return;

    int rowIndex = -1;
    for (int r = 5; r >= 0; r--) {
      if (_board[colIndex][r] == 0) {
        rowIndex = r;
        break;
      }
    }
    if (rowIndex == -1) return; // Column full

    setState(() {
      _board[colIndex][rowIndex] = _myPlayerNumber;
      _lastCol = colIndex;
      _lastRow = rowIndex;
      _currentTurn = _opponentPlayerNumber;
      _checkWinner();
    });

    Provider.of<ConnectivityService>(context, listen: false).sendPayload({
      'type': 'game_move',
      'gameId': 'connect4',
      'data': {
        'board': _board,
        'playedCol': colIndex,
        'playedRow': rowIndex,
        'nextTurn': _opponentPlayerNumber,
      }
    });
  }

  void _checkWinner() {
    // Horizontal
    for (int r = 0; r < 6; r++) {
      for (int c = 0; c < 4; c++) {
        if (_board[c][r] != 0 &&
            _board[c][r] == _board[c + 1][r] &&
            _board[c][r] == _board[c + 2][r] &&
            _board[c][r] == _board[c + 3][r]) {
          _setWinner(_board[c][r]);
          return;
        }
      }
    }
    // Vertical
    for (int c = 0; c < 7; c++) {
      for (int r = 0; r < 3; r++) {
        if (_board[c][r] != 0 &&
            _board[c][r] == _board[c][r + 1] &&
            _board[c][r] == _board[c][r + 2] &&
            _board[c][r] == _board[c][r + 3]) {
          _setWinner(_board[c][r]);
          return;
        }
      }
    }
    // Diagonal /
    for (int c = 0; c < 4; c++) {
      for (int r = 3; r < 6; r++) {
        if (_board[c][r] != 0 &&
            _board[c][r] == _board[c + 1][r - 1] &&
            _board[c][r] == _board[c + 2][r - 2] &&
            _board[c][r] == _board[c + 3][r - 3]) {
          _setWinner(_board[c][r]);
          return;
        }
      }
    }
    // Diagonal \
    for (int c = 0; c < 4; c++) {
      for (int r = 0; r < 3; r++) {
        if (_board[c][r] != 0 &&
            _board[c][r] == _board[c + 1][r + 1] &&
            _board[c][r] == _board[c + 2][r + 2] &&
            _board[c][r] == _board[c + 3][r + 3]) {
          _setWinner(_board[c][r]);
          return;
        }
      }
    }
    // Draw
    bool isFull = true;
    for (int c = 0; c < 7; c++) {
      if (_board[c][0] == 0) {
        isFull = false;
        break;
      }
    }
    if (isFull) {
      _isGameOver = true;
      _winnerNum = 3;
    }
  }

  void _setWinner(int winnerCode) {
    _isGameOver = true;
    _winnerNum = winnerCode;
    _updateStats();
  }

  void _updateStats() {
    if (_statsUpdated) return;
    final connService =
        Provider.of<ConnectivityService>(context, listen: false);
    if (_winnerNum == _myPlayerNumber) {
      connService.incrementWin('connect4');
      _statsUpdated = true;
    } else if (_winnerNum == _opponentPlayerNumber) {
      connService.incrementLoss('connect4');
      _statsUpdated = true;
    }
  }

  void _requestReset() {
    setState(() => _waitingForResetAccept = true);
    Provider.of<ConnectivityService>(context, listen: false).sendPayload({
      'type': 'game_reset',
      'gameId': 'connect4',
    });
  }

  void _resetBoard() {
    setState(() {
      _board = List.generate(7, (_) => List.filled(6, 0));
      _currentTurn = 1;
      _isGameOver = false;
      _winnerNum = 0;
      _waitingForResetAccept = false;
      _lastCol = -1;
      _lastRow = -1;
      _statsUpdated = false;
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
    final connService = Provider.of<ConnectivityService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!connService.hasSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const SizedBox();
    }

    final isMyTurn = _currentTurn == _myPlayerNumber;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final boardWidget = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AspectRatio(
          aspectRatio: 7.0 / 6.6,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: _buildBoardWidget(context, isDark, isMyTurn),
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
                                      title: 'Vier Gewinnt',
                                      onExit: _exitGame),
                                  const SizedBox(height: 16),
                                  _buildPlayerStats(
                                      context, connService, isMyTurn),
                                  const SizedBox(height: 24),
                                  if (!_isGameOver)
                                    _buildTurnStatus(isMyTurn, isDark),
                                ],
                              ),
                            ),
                          ),
                          Expanded(flex: 5, child: boardWidget),
                        ],
                      )
                    : Column(
                        children: [
                          GameHeader(title: 'Vier Gewinnt', onExit: _exitGame),
                          const SizedBox(height: 12),
                          _buildPlayerStats(context, connService, isMyTurn),
                          const Spacer(),
                          boardWidget,
                          const Spacer(),
                          if (!_isGameOver) _buildTurnStatus(isMyTurn, isDark),
                          const Spacer(),
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

  Widget _buildPlayerStats(
      BuildContext context, ConnectivityService connService, bool isMyTurn) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _PlayerLabel(
            text: 'Du',
            isActive: isMyTurn && !_isGameOver,
            color: _myPlayerNumber == 1
                ? AppTheme.accentNeonPink
                : AppTheme.accentNeonCyan,
          ),
          Text(
            'VS',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white30 : Colors.black38,
            ),
          ),
          _PlayerLabel(
            text: connService.connectedPeer?.name ?? 'Gegner',
            isActive: !isMyTurn && !_isGameOver,
            color: _opponentPlayerNumber == 1
                ? AppTheme.accentNeonPink
                : AppTheme.accentNeonCyan,
          ),
        ],
      ),
    );
  }

  Widget _buildBoardWidget(BuildContext context, bool isDark, bool isMyTurn) {
    final myColor = _myPlayerNumber == 1
        ? AppTheme.accentNeonPink
        : AppTheme.accentNeonCyan;

    return GlassContainer(
      padding: const EdgeInsets.all(8),
      borderRadius: 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Column selectors
          Row(
            children: List.generate(7, (colIndex) {
              final colFull = _board[colIndex][0] != 0;
              final enabled = isMyTurn && !colFull && !_isGameOver;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _playColumn(colIndex),
                  child: Container(
                    height: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: enabled
                          ? myColor.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.arrow_downward_rounded,
                      size: 14,
                      color: enabled ? myColor : Colors.transparent,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          // Grid
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: List.generate(7, (colIndex) {
                  return Expanded(
                    child: Column(
                      children: List.generate(6, (rowIndex) {
                        final cellVal = _board[colIndex][rowIndex];
                        final isLastMove =
                            colIndex == _lastCol && rowIndex == _lastRow;

                        return Expanded(
                          child: GestureDetector(
                            onTap: () => _playColumn(colIndex),
                            child: Container(
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    isDark ? AppTheme.darkBg : Colors.white,
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white10
                                      : Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              child: cellVal == 0
                                  ? null
                                  : Container(
                                      margin: const EdgeInsets.all(1.5),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          colors: cellVal == 1
                                              ? [
                                                  AppTheme.accentNeonPink,
                                                  const Color(0xFFFF007F)
                                                ]
                                              : [
                                                  AppTheme.accentNeonCyan,
                                                  const Color(0xFF4FACFE)
                                                ],
                                        ),
                                        boxShadow: isDark
                                            ? AppTheme.neonGlow(cellVal == 1
                                                ? AppTheme.accentNeonPink
                                                : AppTheme.accentNeonCyan)
                                            : AppTheme.softShadow,
                                      ),
                                    )
                                      .animate(
                                          target: isLastMove ? 1.0 : 0.0)
                                      .scaleXY(
                                          begin: 0.1,
                                          end: 1.0,
                                          duration: 300.ms,
                                          curve: Curves.bounceOut),
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnStatus(bool isMyTurn, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: isMyTurn
            ? AppTheme.primaryPurple.withValues(alpha: isDark ? 0.1 : 0.05)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isMyTurn ? 'Du bist dran!' : 'Gegner überlegt...',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: isMyTurn
              ? (isDark ? const Color(0xFF00F2FE) : AppTheme.primaryPurple)
              : (isDark ? Colors.white60 : Colors.black54),
        ),
      ),
    );
  }

  Widget _buildGameOverOverlay() {
    final isWin = _winnerNum == _myPlayerNumber;
    final isDraw = _winnerNum == 3;

    return GameResultOverlay(
      title:
          isDraw ? 'UNENTSCHIEDEN!' : (isWin ? 'GEWONNEN!' : 'VERLOREN!'),
      description: isDraw
          ? 'Ein knappes Unentschieden!'
          : (isWin
              ? 'Klasse Kombination, du hast gewonnen!'
              : 'Gegner hat eine 4er-Reihe gebildet!'),
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

class _PlayerLabel extends StatelessWidget {
  final String text;
  final bool isActive;
  final Color color;

  const _PlayerLabel({
    required this.text,
    required this.isActive,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? color.withValues(alpha: 0.12)
            : (isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? color.withValues(alpha: 0.6) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: isActive
              ? (isDark ? Colors.white : Colors.black)
              : (isDark ? Colors.white30 : Colors.black38),
        ),
      ),
    );
  }
}
