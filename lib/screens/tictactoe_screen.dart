import 'dart:async';
import 'dart:ui';
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
  bool _statsUpdated = false;

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
        _updateStats();
        return;
      }
    }

    if (!_board.contains('')) {
      setState(() {
        _isGameOver = true;
        _winner = 'draw';
      });
      _updateStats();
    }
  }

  void _updateStats() {
    if (_statsUpdated) return;
    final connService = Provider.of<ConnectivityService>(context, listen: false);
    if (_winner == _mySymbol) {
      connService.incrementWin('tictactoe');
      _statsUpdated = true;
    } else if (_winner == _opponentSymbol) {
      connService.incrementLoss('tictactoe');
      _statsUpdated = true;
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
      _statsUpdated = false;
    });
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
        final isDark = Theme.of(context).brightness == Brightness.dark;
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
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        _exitGame();
      },
      child: Scaffold(
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
        child: Stack(
          children: [
            SafeArea(
              child: isLandscape
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left column: Stats, status, settings
                        Expanded(
                          flex: 4,
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildHeader(context, connService, isDark),
                                const SizedBox(height: 16),
                                _buildPlayerStats(context, connService, isMyTurn),
                                const SizedBox(height: 24),
                                if (!_isGameOver) _buildTurnStatus(isMyTurn, isDark),
                              ],
                            ),
                          ),
                        ),
                        // Right column: Board grid
                        Expanded(
                          flex: 5,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1.0,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: _buildBoardGrid(context, isDark),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _buildHeader(context, connService, isDark),
                        const SizedBox(height: 20),
                        _buildPlayerStats(context, connService, isMyTurn),
                        const Spacer(),
                        AspectRatio(
                          aspectRatio: 1.0,
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: _buildBoardGrid(context, isDark),
                          ),
                        ),
                        const Spacer(),
                        if (!_isGameOver) _buildTurnStatus(isMyTurn, isDark),
                        const Spacer(),
                      ],
                    ),
            ),
            if (_isGameOver) _buildGameOverOverlay(context, isDark, connService),
          ],
        ),
      ),
    ));
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

  Widget _buildHeader(BuildContext context, ConnectivityService connService, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white70 : Colors.black87),
            onPressed: _exitGame,
          ),
          Expanded(
            child: Center(
              child: Text(
                'Tic-Tac-Toe',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
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
        ],
      ),
    );
  }

  Widget _buildPlayerStats(BuildContext context, ConnectivityService connService, bool isMyTurn) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
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
    );
  }

  Widget _buildTurnStatus(bool isMyTurn, bool isDark) {
    return Container(
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
    ).animate(target: isMyTurn ? 1.0 : 0.0).shimmer(duration: 1500.ms);
  }

  Widget _buildGameOverOverlay(BuildContext context, bool isDark, ConnectivityService connService) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isWin = _winner == _mySymbol;
    final isDraw = _winner == 'draw';

    final winColor = isWin
        ? Colors.greenAccent
        : (isDraw ? Colors.amberAccent : Colors.redAccent);

    final title = isDraw
        ? 'UNENTSCHIEDEN!'
        : (isWin ? 'SIEG!' : 'NIEDERLAGE!');

    final desc = isDraw
        ? 'Gute Runde! Wollt ihr Revanche?'
        : (isWin
            ? 'Du hast diese Runde gewonnen!'
            : 'Dein Gegner war schneller!');

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
                    color: winColor.withOpacity(0.6),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: winColor.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isWin
                          ? Icons.emoji_events_rounded
                          : (isDraw ? Icons.handshake_rounded : Icons.sentiment_very_dissatisfied_rounded),
                      size: 64,
                      color: winColor,
                    ).animate().scaleXY(begin: 0.8, end: 1.2, duration: 800.ms, curve: Curves.bounceOut),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: winColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      desc,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _exitGame,
                            child: Text(
                              'Beenden',
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8A2387),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _waitingForResetAccept ? null : _requestReset,
                            child: _waitingForResetAccept
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Revanche', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
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
