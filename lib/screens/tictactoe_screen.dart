import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

class TicTacToeScreen extends StatefulWidget {
  const TicTacToeScreen({super.key});

  @override
  State<TicTacToeScreen> createState() => _TicTacToeScreenState();
}

class _TicTacToeScreenState extends State<TicTacToeScreen> {
  List<String> _board = List.filled(9, '');
  late String _mySymbol;
  late String _opponentSymbol;
  String _currentTurn = 'X'; // X starts
  StreamSubscription? _msgSubscription;
  bool _isGameOver = false;
  String _winner = ''; // 'X', 'O', or 'draw'
  bool _waitingForResetAccept = false;
  bool _statsUpdated = false;

  @override
  void initState() {
    super.initState();
    final connService =
        Provider.of<ConnectivityService>(context, listen: false);

    // Host is X, guest is O. Against the bot the local player is always host.
    _mySymbol = connService.isHost ? 'X' : 'O';
    _opponentSymbol = connService.isHost ? 'O' : 'X';

    _msgSubscription = connService.messageStream.listen((payload) {
      if (!mounted) return;
      if (payload['type'] == 'game_move' && payload['gameId'] == 'tictactoe') {
        final moveData = payload['data'] as Map<String, dynamic>;
        setState(() {
          _board = List<String>.from(moveData['board']);
          _currentTurn = moveData['nextTurn'] as String;
          _checkWinner();
        });
      } else if (payload['type'] == 'game_reset' &&
          payload['gameId'] == 'tictactoe') {
        connService.sendPayload({
          'type': 'game_reset_accept',
          'gameId': 'tictactoe',
        });
        _resetBoard();
      } else if (payload['type'] == 'game_reset_accept' &&
          payload['gameId'] == 'tictactoe') {
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

  void _makeMove(int index) {
    if (_board[index].isNotEmpty || _isGameOver || _currentTurn != _mySymbol) {
      return;
    }

    setState(() {
      _board[index] = _mySymbol;
      _currentTurn = _opponentSymbol;
      _checkWinner();
    });

    Provider.of<ConnectivityService>(context, listen: false).sendPayload({
      'type': 'game_move',
      'gameId': 'tictactoe',
      'data': {
        'board': _board,
        'lastMoveIndex': index,
        'nextTurn': _opponentSymbol,
        'playerSymbol': _mySymbol,
      }
    });
  }

  void _checkWinner() {
    const lines = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8],
      [0, 3, 6], [1, 4, 7], [2, 5, 8],
      [0, 4, 8], [2, 4, 6],
    ];

    for (final line in lines) {
      if (_board[line[0]].isNotEmpty &&
          _board[line[0]] == _board[line[1]] &&
          _board[line[0]] == _board[line[2]]) {
        _isGameOver = true;
        _winner = _board[line[0]];
        _updateStats();
        return;
      }
    }

    if (!_board.contains('')) {
      _isGameOver = true;
      _winner = 'draw';
      _updateStats();
    }
  }

  void _updateStats() {
    if (_statsUpdated) return;
    final connService =
        Provider.of<ConnectivityService>(context, listen: false);
    if (_winner == _mySymbol) {
      connService.incrementWin('tictactoe');
      _statsUpdated = true;
    } else if (_winner == _opponentSymbol) {
      connService.incrementLoss('tictactoe');
      _statsUpdated = true;
    }
  }

  void _requestReset() {
    setState(() => _waitingForResetAccept = true);
    Provider.of<ConnectivityService>(context, listen: false).sendPayload({
      'type': 'game_reset',
      'gameId': 'tictactoe',
    });
  }

  void _resetBoard() {
    setState(() {
      _board = List.filled(9, '');
      _currentTurn = 'X';
      _isGameOver = false;
      _winner = '';
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

  @override
  Widget build(BuildContext context) {
    final connService = Provider.of<ConnectivityService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!connService.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const SizedBox();
    }

    final isMyTurn = _currentTurn == _mySymbol;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final board = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 480),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildBoardGrid(context, isDark),
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
                                      title: 'Tic-Tac-Toe',
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
                          Expanded(flex: 5, child: board),
                        ],
                      )
                    : Column(
                        children: [
                          GameHeader(title: 'Tic-Tac-Toe', onExit: _exitGame),
                          const SizedBox(height: 12),
                          _buildPlayerStats(context, connService, isMyTurn),
                          const Spacer(),
                          board,
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
            text: 'Du ($_mySymbol)',
            isActive: isMyTurn && !_isGameOver,
            color: _mySymbol == 'X'
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
            text:
                '${connService.connectedPeer?.name ?? 'Gegner'} ($_opponentSymbol)',
            isActive: !isMyTurn && !_isGameOver,
            color: _opponentSymbol == 'X'
                ? AppTheme.accentNeonPink
                : AppTheme.accentNeonCyan,
          ),
        ],
      ),
    );
  }

  Widget _buildBoardGrid(BuildContext context, bool isDark) {
    return GlassContainer(
      borderRadius: 28,
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: 9,
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () => _makeMove(index),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white10
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Center(child: _buildSymbolWidget(_board[index])),
            ),
          );
        },
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
        isMyTurn ? 'Du bist an der Reihe!' : 'Gegner wählt einen Zug...',
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
    final isWin = _winner == _mySymbol;
    final isDraw = _winner == 'draw';

    return GameResultOverlay(
      title: isDraw ? 'UNENTSCHIEDEN!' : (isWin ? 'SIEG!' : 'NIEDERLAGE!'),
      description: isDraw
          ? 'Gute Runde! Wollt ihr Revanche?'
          : (isWin
              ? 'Du hast diese Runde gewonnen!'
              : 'Dein Gegner war schneller!'),
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

  Widget _buildSymbolWidget(String value) {
    if (value == 'X') {
      return Icon(
        Icons.close_rounded,
        size: 56,
        color: AppTheme.accentNeonPink,
        shadows: [
          Shadow(
            color: AppTheme.accentNeonPink.withValues(alpha: 0.8),
            blurRadius: 16,
          ),
        ],
      )
          .animate()
          .scaleXY(
              begin: 0.5, end: 1.0, duration: 250.ms, curve: Curves.easeOutBack);
    } else if (value == 'O') {
      return Icon(
        Icons.circle_outlined,
        size: 48,
        color: AppTheme.accentNeonCyan,
        shadows: [
          Shadow(
            color: AppTheme.accentNeonCyan.withValues(alpha: 0.8),
            blurRadius: 16,
          ),
        ],
      )
          .animate()
          .scaleXY(
              begin: 0.5, end: 1.0, duration: 250.ms, curve: Curves.easeOutBack);
    }
    return const SizedBox.shrink();
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
