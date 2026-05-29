import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_sheet.dart';

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

  @override
  void initState() {
    super.initState();
    final connService = Provider.of<ConnectivityService>(context, listen: false);
    
    // Host is X, Client is O
    _mySymbol = connService.isHost ? 'X' : 'O';
    _opponentSymbol = connService.isHost ? 'O' : 'X';

    _msgSubscription = connService.messageStream.listen((payload) {
      if (payload['type'] == 'game_move' && payload['gameId'] == 'tictactoe') {
        final moveData = payload['data'] as Map<String, dynamic>;
        setState(() {
          _board = List<String>.from(moveData['board']);
          _currentTurn = moveData['nextTurn'] as String;
          _checkWinner();
        });
      } else if (payload['type'] == 'game_reset' && payload['gameId'] == 'tictactoe') {
        // Automatically accept and reset
        connService.sendPayload({
          'type': 'game_reset_accept',
          'gameId': 'tictactoe',
        });
        _resetBoard();
      } else if (payload['type'] == 'game_reset_accept' && payload['gameId'] == 'tictactoe') {
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
    if (_board[index].isNotEmpty || _isGameOver || _currentTurn != _mySymbol) return;

    setState(() {
      _board[index] = _mySymbol;
      _currentTurn = _opponentSymbol;
      _checkWinner();
    });

    // Send payload
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
      [0, 1, 2], [3, 4, 5], [6, 7, 8], // Rows
      [0, 3, 6], [1, 4, 7], [2, 5, 8], // Columns
      [0, 4, 8], [2, 4, 6]             // Diagonals
    ];

    for (var line in lines) {
      if (_board[line[0]].isNotEmpty &&
          _board[line[0]] == _board[line[1]] &&
          _board[line[0]] == _board[line[2]]) {
        setState(() {
          _isGameOver = true;
          _winner = _board[line[0]];
        });
        return;
      }
    }

    if (!_board.contains('')) {
      setState(() {
        _isGameOver = true;
        _winner = 'draw';
      });
    }
  }

  void _requestReset() {
    setState(() {
      _waitingForResetAccept = true;
    });
    Provider.of<ConnectivityService>(context, listen: false).sendPayload({
      'type': 'game_reset',
      'gameId': 'tictactoe',
    });
  }

  void _resetBoard() {
    setState(() {
      _board = List.filled(9, '');
      _currentTurn = 'X'; // X starts again
      _isGameOver = false;
      _winner = '';
      _waitingForResetAccept = false;
    });
  }

  void _exitGame() {
    Provider.of<ConnectivityService>(context, listen: false).exitGame();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final connService = Provider.of<ConnectivityService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Guard: connection dropped
    if (!connService.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const SizedBox();
    }

    final isMyTurn = _currentTurn == _mySymbol;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0F0B1E), Color(0xFF130A29), Color(0xFF0F0B1E)],
                )
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF4F6FB), Color(0xFFE9EEF6), Color(0xFFF7F8FC)],
                ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white70 : Colors.black87),
                      onPressed: _exitGame,
                    ),
                    Text(
                      'Tic-Tac-Toe',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
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
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Player Stats Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildPlayerLabel(
                      context,
                      'Du ($_mySymbol)',
                      isMyTurn && !_isGameOver,
                      _mySymbol == 'X' ? AppTheme.accentNeonPink : AppTheme.accentNeonCyan,
                    ),
                    Text(
                      'VS',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white30 : Colors.black38,
                      ),
                    ),
                    _buildPlayerLabel(
                      context,
                      '${connService.connectedPeer?.name} ($_opponentSymbol)',
                      !isMyTurn && !_isGameOver,
                      _opponentSymbol == 'X' ? AppTheme.accentNeonPink : AppTheme.accentNeonCyan,
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Game Board Grid
              AspectRatio(
                aspectRatio: 1.0,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: GlassContainer(
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
                              color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                              ),
                            ),
                            child: Center(
                              child: _buildSymbolWidget(_board[index]),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Turn Status Description
              if (!_isGameOver)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: isMyTurn
                        ? (isDark ? const Color(0xFF8A2387).withOpacity(0.1) : Colors.purple.withOpacity(0.05))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isMyTurn ? 'Du bist an der Reihe!' : 'Gegner wählt einen Zug...',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isMyTurn
                          ? (isDark ? const Color(0xFF00F2FE) : const Color(0xFF8A2387))
                          : (isDark ? Colors.white60 : Colors.black54),
                    ),
                  ),
                ).animate(target: isMyTurn ? 1.0 : 0.0).shimmer(duration: 1500.ms),

              // Game Over Screen Banner / Dialog overlay
              if (_isGameOver)
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: GlassContainer(
                    padding: const EdgeInsets.all(20),
                    borderRadius: 24,
                    gradientColors: [
                      const Color(0xFF8A2387).withOpacity(0.3),
                      const Color(0xFF00F2FE).withOpacity(0.1),
                    ],
                    child: Column(
                      children: [
                        Text(
                          _winner == 'draw'
                              ? 'Unentschieden!'
                              : (_winner == _mySymbol ? 'Sieg!' : 'Niederlage!'),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: _winner == 'draw'
                                ? Colors.amberAccent
                                : (_winner == _mySymbol ? Colors.greenAccent : Colors.redAccent),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _winner == 'draw'
                              ? 'Gute Runde! Wollt ihr Revanche?'
                              : (_winner == _mySymbol
                                  ? 'Du hast diese Runde gewonnen!'
                                  : 'Dein Gegner war schneller!'),
                          style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8A2387),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          onPressed: _waitingForResetAccept ? null : _requestReset,
                          icon: _waitingForResetAccept
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.replay_rounded),
                          label: Text(
                            _waitingForResetAccept ? 'Warte auf Gegner...' : 'Nochmal spielen',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().scaleXY(begin: 0.8, end: 1.0, duration: 400.ms, curve: Curves.bounceOut),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerLabel(BuildContext context, String text, bool isActive, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? color.withOpacity(0.12)
            : (isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? color.withOpacity(0.6) : Colors.transparent,
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

  Widget _buildSymbolWidget(String value) {
    if (value == 'X') {
      return Icon(
        Icons.close_rounded,
        size: 56,
        color: AppTheme.accentNeonPink,
        shadows: [
          Shadow(
            color: AppTheme.accentNeonPink.withOpacity(0.8),
            blurRadius: 16,
          ),
        ],
      ).animate().scaleXY(begin: 0.5, end: 1.0, duration: 250.ms, curve: Curves.easeOutBack);
    } else if (value == 'O') {
      return Icon(
        Icons.circle_outlined,
        size: 48,
        color: AppTheme.accentNeonCyan,
        shadows: [
          Shadow(
            color: AppTheme.accentNeonCyan.withOpacity(0.8),
            blurRadius: 16,
          ),
        ],
      ).animate().scaleXY(begin: 0.5, end: 1.0, duration: 250.ms, curve: Curves.easeOutBack);
    }
    return const SizedBox();
  }
}
