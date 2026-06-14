import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_sheet.dart';

class ConnectFourScreen extends StatefulWidget {
  const ConnectFourScreen({super.key});

  @override
  State<ConnectFourScreen> createState() => _ConnectFourScreenState();
}

class _ConnectFourScreenState extends State<ConnectFourScreen> {
  // 7 columns, 6 rows. 0 = Empty, 1 = Player 1 (Host), 2 = Player 2 (Client)
  List<List<int>> _board = List.generate(7, (_) => List.generate(6, (_) => 0));
  
  late int _myPlayerNumber;
  late int _opponentPlayerNumber;
  int _currentTurn = 1; // Player 1 starts
  StreamSubscription? _msgSubscription;
  bool _isGameOver = false;
  int _winnerNum = 0; // 0 = None, 1 = P1, 2 = P2, 3 = Draw
  bool _waitingForResetAccept = false;
  bool _statsUpdated = false;

  // Track coordinates of last played token for win animations
  int _lastCol = -1;
  int _lastRow = -1;

  @override
  void initState() {
    super.initState();
    final connService = Provider.of<ConnectivityService>(context, listen: false);

    // Host is Player 1, Client is Player 2
    _myPlayerNumber = connService.isHost ? 1 : 2;
    _opponentPlayerNumber = connService.isHost ? 2 : 1;

    _msgSubscription = connService.messageStream.listen((payload) {
      if (payload['type'] == 'game_move' && payload['gameId'] == 'connect4') {
        final moveData = payload['data'] as Map<String, dynamic>;
        setState(() {
          _board = List<List<int>>.from(
            (moveData['board'] as List).map((col) => List<int>.from(col))
          );
          _lastCol = moveData['playedCol'] as int;
          _lastRow = moveData['playedRow'] as int;
          _currentTurn = moveData['nextTurn'] as int;
          _checkWinner();
        });
      } else if (payload['type'] == 'game_reset' && payload['gameId'] == 'connect4') {
        connService.sendPayload({
          'type': 'game_reset_accept',
          'gameId': 'connect4',
        });
        _resetBoard();
      } else if (payload['type'] == 'game_reset_accept' && payload['gameId'] == 'connect4') {
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

    // Find lowest empty slot in the column
    int rowIndex = -1;
    for (int r = 5; r >= 0; r--) {
      if (_board[colIndex][r] == 0) {
        rowIndex = r;
        break;
      }
    }

    // Column full
    if (rowIndex == -1) return;

    setState(() {
      _board[colIndex][rowIndex] = _myPlayerNumber;
      _lastCol = colIndex;
      _lastRow = rowIndex;
      _currentTurn = _opponentPlayerNumber;
      _checkWinner();
    });

    // Send payload
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
            _board[c][r] == _board[c+1][r] &&
            _board[c][r] == _board[c+2][r] &&
            _board[c][r] == _board[c+3][r]) {
          _setWinner(_board[c][r]);
          return;
        }
      }
    }

    // Vertical
    for (int c = 0; c < 7; c++) {
      for (int r = 0; r < 3; r++) {
        if (_board[c][r] != 0 &&
            _board[c][r] == _board[c][r+1] &&
            _board[c][r] == _board[c][r+2] &&
            _board[c][r] == _board[c][r+3]) {
          _setWinner(_board[c][r]);
          return;
        }
      }
    }

    // Positive Diagonal
    for (int c = 0; c < 4; c++) {
      for (int r = 3; r < 6; r++) {
        if (_board[c][r] != 0 &&
            _board[c][r] == _board[c+1][r-1] &&
            _board[c][r] == _board[c+2][r-2] &&
            _board[c][r] == _board[c+3][r-3]) {
          _setWinner(_board[c][r]);
          return;
        }
      }
    }

    // Negative Diagonal
    for (int c = 0; c < 4; c++) {
      for (int r = 0; r < 3; r++) {
        if (_board[c][r] != 0 &&
            _board[c][r] == _board[c+1][r+1] &&
            _board[c][r] == _board[c+2][r+2] &&
            _board[c][r] == _board[c+3][r+3]) {
          _setWinner(_board[c][r]);
          return;
        }
      }
    }

    // Check Draw
    bool isFull = true;
    for (int c = 0; c < 7; c++) {
      if (_board[c][0] == 0) {
        isFull = false;
        break;
      }
    }

    if (isFull) {
      setState(() {
        _isGameOver = true;
        _winnerNum = 3; // Draw
      });
    }
  }

  void _setWinner(int winnerCode) {
    setState(() {
      _isGameOver = true;
      _winnerNum = winnerCode;
    });
    _updateStats();
  }

  void _updateStats() {
    if (_statsUpdated) return;
    final connService = Provider.of<ConnectivityService>(context, listen: false);
    if (_winnerNum == _myPlayerNumber) {
      connService.incrementWin('connect4');
      _statsUpdated = true;
    } else if (_winnerNum == _opponentPlayerNumber) {
      connService.incrementLoss('connect4');
      _statsUpdated = true;
    }
  }

  void _requestReset() {
    setState(() {
      _waitingForResetAccept = true;
    });
    Provider.of<ConnectivityService>(context, listen: false).sendPayload({
      'type': 'game_reset',
      'gameId': 'connect4',
    });
  }

  void _resetBoard() {
    setState(() {
      _board = List.generate(7, (_) => List.generate(6, (_) => 0));
      _currentTurn = 1; // P1 starts again
      _isGameOver = false;
      _winnerNum = 0;
      _waitingForResetAccept = false;
      _lastCol = -1;
      _lastRow = -1;
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

    // Guard connection
    if (!connService.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const SizedBox();
    }

    final isMyTurn = _currentTurn == _myPlayerNumber;
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
                        // Left column: Stats, turn status, controls
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
                        // Right column: Sized game board
                        Expanded(
                          flex: 5,
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 7.0 / 6.5,
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: _buildBoardWidget(context, isDark, isMyTurn),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _buildHeader(context, connService, isDark),
                        const SizedBox(height: 16),
                        _buildPlayerStats(context, connService, isMyTurn),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildBoardWidget(context, isDark, isMyTurn),
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
        border: Border.all(color: Colors.white.withOpacity(0.15)),
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
                'Vier Gewinnt',
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
            'Du',
            isMyTurn && !_isGameOver,
            _myPlayerNumber == 1 ? AppTheme.accentNeonPink : AppTheme.accentNeonCyan,
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
            connService.connectedPeer?.name ?? 'Gegner',
            !isMyTurn && !_isGameOver,
            _opponentPlayerNumber == 1 ? AppTheme.accentNeonPink : AppTheme.accentNeonCyan,
          ),
        ],
      ),
    );
  }

  Widget _buildBoardWidget(BuildContext context, bool isDark, bool isMyTurn) {
    return GlassContainer(
      padding: const EdgeInsets.all(8),
      borderRadius: 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Column Selectors indicators
          Row(
            children: List.generate(7, (colIndex) {
              final colFull = _board[colIndex][0] != 0;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _playColumn(colIndex),
                  child: Container(
                    height: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isMyTurn && !colFull && !_isGameOver
                          ? (_myPlayerNumber == 1 ? AppTheme.accentNeonPink : AppTheme.accentNeonCyan).withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.arrow_downward_rounded,
                      size: 14,
                      color: isMyTurn && !colFull && !_isGameOver
                          ? (_myPlayerNumber == 1 ? AppTheme.accentNeonPink : AppTheme.accentNeonCyan)
                          : Colors.transparent,
                    ),
                  ),
                ),
              );
            }),
          ),
          
          const SizedBox(height: 4),

          // Grid Box
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: List.generate(7, (colIndex) {
                  return Expanded(
                    child: Column(
                      children: List.generate(6, (rowIndex) {
                        final cellVal = _board[colIndex][rowIndex];
                        final isLastMove = colIndex == _lastCol && rowIndex == _lastRow;
                        
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => _playColumn(colIndex),
                            child: Container(
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDark ? const Color(0xFF0F0B1E) : Colors.white,
                                border: Border.all(
                                  color: isDark ? Colors.white10 : Colors.black.withOpacity(0.08),
                                ),
                              ),
                              child: cellVal == 0
                                  ? const SizedBox()
                                  : Container(
                                      margin: const EdgeInsets.all(1.5),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          colors: cellVal == 1
                                              ? [AppTheme.accentNeonPink, const Color(0xFFFF007F)]
                                              : [AppTheme.accentNeonCyan, const Color(0xFF4FACFE)],
                                        ),
                                        boxShadow: isDark
                                            ? AppTheme.neonGlow(cellVal == 1 ? AppTheme.accentNeonPink : AppTheme.accentNeonCyan)
                                            : AppTheme.softShadow,
                                      ),
                                    )
                                      .animate(target: isLastMove ? 1.0 : 0.0)
                                      .scaleXY(begin: 0.1, end: 1.0, duration: 300.ms, curve: Curves.bounceOut)
                                      .shake(duration: 250.ms),
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
            ? (isDark ? const Color(0xFF8A2387).withOpacity(0.1) : Colors.purple.withOpacity(0.05))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isMyTurn ? 'Du bist dran!' : 'Gegner überlegt...',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: isMyTurn
              ? (isDark ? const Color(0xFF00F2FE) : const Color(0xFF8A2387))
              : (isDark ? Colors.white60 : Colors.black54),
        ),
      ),
    );
  }

  Widget _buildGameOverOverlay(BuildContext context, bool isDark, ConnectivityService connService) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isWin = _winnerNum == _myPlayerNumber;
    final isDraw = _winnerNum == 3;

    final winColor = isWin
        ? Colors.greenAccent
        : (isDraw ? Colors.amberAccent : Colors.redAccent);

    final title = isDraw
        ? 'UNENTSCHIEDEN!'
        : (isWin ? 'GEWONNEN!' : 'VERLOREN!');

    final desc = isDraw
        ? 'Ein knappes Unentschieden!'
        : (isWin
            ? 'Klasse Kombination, du hast gewonnen!'
            : 'Gegner hat eine 4er-Reihe gebildet!');

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
}
