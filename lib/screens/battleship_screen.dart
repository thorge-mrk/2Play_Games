import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_sheet.dart';

class BattleshipScreen extends StatefulWidget {
  const BattleshipScreen({super.key});

  @override
  State<BattleshipScreen> createState() => _BattleshipScreenState();
}

class _BattleshipScreenState extends State<BattleshipScreen> with SingleTickerProviderStateMixin {
  // Board states: 10x10. 0 = Empty, 1 = Ship, 2 = Hit, 3 = Miss
  List<List<int>> _myBoard = List.generate(10, (_) => List.generate(10, (_) => 0));
  List<List<int>> _opponentBoard = List.generate(10, (_) => List.generate(10, (_) => 0)); // What we fired at

  // Placement Phase states
  bool _isPlacementPhase = true;
  final List<int> _shipSizes = [5, 4, 3, 3, 2];
  int _currentShipIndex = 0;
  bool _isHorizontal = true;
  bool _iAmReady = false;
  bool _opponentIsReady = false;

  // Battle Phase states
  late TabController _tabController;
  bool _myTurn = true; // Host starts
  StreamSubscription? _msgSubscription;
  bool _isGameOver = false;
  bool _iWon = false;
  bool _waitingForResetAccept = false;
  bool _statsUpdated = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    final connService = Provider.of<ConnectivityService>(context, listen: false);
    _myTurn = connService.isHost; // Host fires first

    _msgSubscription = connService.messageStream.listen((payload) {
      if (payload['type'] == 'game_move' && payload['gameId'] == 'battleship') {
        final data = payload['data'] as Map<String, dynamic>;
        final subtype = data['subtype'] as String?;

        if (subtype == 'player_ready') {
          setState(() {
            _opponentIsReady = true;
            _checkStartBattle();
          });
        } else if (subtype == 'ai_ready') {
          // AI generated board
          setState(() {
            _opponentIsReady = true;
            // Record AI board secretly for hit checking
            // Map AI board as 1s (unhit ships) in its own board
            _opponentBoard = List<List<int>>.from(
              (data['aiBoard'] as List).map((row) => List<int>.from(row))
            );
            _checkStartBattle();
          });
        } else if (subtype == 'fire') {
          // Opponent fired at our grid
          final tx = data['x'] as int;
          final ty = data['y'] as int;
          final hit = _myBoard[ty][tx] == 1;
          
          setState(() {
            _myBoard[ty][tx] = hit ? 2 : 3;
            _myTurn = true; // It's our turn now
            _checkWinState();
          });

          // Report back the result
          connService.sendPayload({
            'type': 'game_move',
            'gameId': 'battleship',
            'data': {
              'subtype': 'fire_result',
              'x': tx,
              'y': ty,
              'isHit': hit,
              'winnerName': _isGameOver && !_iWon ? connService.connectedPeer?.name : null,
            }
          });
        } else if (subtype == 'fire_result') {
          final tx = data['x'] as int;
          final ty = data['y'] as int;
          final isHit = data['isHit'] as bool;
          
          setState(() {
            // Update what we see on opponent's ocean
            _opponentBoard[ty][tx] = isHit ? 2 : 3;
            _myTurn = false; // Opponent's turn
            _checkWinState();
          });
        } else if (subtype == 'ai_fire') {
          // AI fired at us – board state comes pre-computed from the bot
          setState(() {
            _myBoard = List<List<int>>.from(
              (data['userBoard'] as List).map((row) => List<int>.from(row))
            );
            _myTurn = true;
            _checkWinState();
          });
        }
      } else if (payload['type'] == 'game_reset' && payload['gameId'] == 'battleship') {
        connService.sendPayload({
          'type': 'game_reset_accept',
          'gameId': 'battleship',
        });
        _resetBoard();
      } else if (payload['type'] == 'game_reset_accept' && payload['gameId'] == 'battleship') {
        _resetBoard();
      } else if (payload['type'] == 'game_exit') {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _msgSubscription?.cancel();
    super.dispose();
  }

  void _checkStartBattle() {
    if (_iAmReady && _opponentIsReady) {
      setState(() {
        _isPlacementPhase = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kampfphase gestartet! Feuer frei!'), backgroundColor: Color(0xFF8A2387)),
      );
    }
  }

  void _placeShip(int x, int y) {
    if (_currentShipIndex >= _shipSizes.length || _iAmReady) return;

    final size = _shipSizes[_currentShipIndex];
    if (_canPlaceShip(x, y, size, _isHorizontal)) {
      setState(() {
        for (int i = 0; i < size; i++) {
          if (_isHorizontal) {
            _myBoard[y][x + i] = 1;
          } else {
            _myBoard[y + i][x] = 1;
          }
        }
        _currentShipIndex++;
        if (_currentShipIndex == _shipSizes.length) {
          // Auto-ready once all are placed
          _setPlayerReady();
        }
      });
    }
  }

  bool _canPlaceShip(int x, int y, int size, bool horizontal) {
    if (horizontal) {
      if (x + size > 10) return false;
      for (int i = 0; i < size; i++) {
        if (_myBoard[y][x + i] != 0) return false;
      }
    } else {
      if (y + size > 10) return false;
      for (int i = 0; i < size; i++) {
        if (_myBoard[y + i][x] != 0) return false;
      }
    }
    return true;
  }

  void _setPlayerReady() {
    setState(() {
      _iAmReady = true;
      _checkStartBattle();
    });

    Provider.of<ConnectivityService>(context, listen: false).sendPayload({
      'type': 'game_move',
      'gameId': 'battleship',
      'data': {
        'subtype': 'player_ready',
        'userBoard': _myBoard,
      }
    });
  }

  void _fireAtOpponent(int x, int y) {
    if (_isPlacementPhase || !_myTurn || _isGameOver) return;
    if (_opponentBoard[y][x] == 2 || _opponentBoard[y][x] == 3) return; // Already targeted

    final connService = Provider.of<ConnectivityService>(context, listen: false);

    if (connService.connectedPeer?.isMock == true) {
      // In simulator, AI board holds the ships. We calculate hit locally using _opponentBoard as the AI's actual fleet board.
      // (Normally _opponentBoard is what we've fired at, but in simulator we use it as their board).
      final isHit = _opponentBoard[y][x] == 1;
      setState(() {
        _opponentBoard[y][x] = isHit ? 2 : 3;
        _myTurn = false;
        _checkWinState();
      });

      // Notify service so AI can generate fire move back
      connService.sendPayload({
        'type': 'game_move',
        'gameId': 'battleship',
        'data': {
          'subtype': 'fire',
          'x': x,
          'y': y,
          'userBoard': _myBoard,
        }
      });
    } else {
      // Real Mode: Send fire coordinate, wait for fire_result reply
      connService.sendPayload({
        'type': 'game_move',
        'gameId': 'battleship',
        'data': {
          'subtype': 'fire',
          'x': x,
          'y': y,
        }
      });
    }
  }

  void _checkWinState() {
    
    // Total ship squares is 5 + 4 + 3 + 3 + 2 = 17
    int myHits = 0;
    int opponentHits = 0;

    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 10; c++) {
        if (_myBoard[r][c] == 2) myHits++;
        if (_opponentBoard[r][c] == 2) opponentHits++;
      }
    }

    if (opponentHits == 17) {
      setState(() {
        _isGameOver = true;
        _iWon = true;
      });
      _updateStats();
    } else if (myHits == 17) {
      setState(() {
        _isGameOver = true;
        _iWon = false;
      });
      _updateStats();
    }
  }

  void _updateStats() {
    if (_statsUpdated) return;
    final connService = Provider.of<ConnectivityService>(context, listen: false);
    if (_iWon) {
      connService.incrementWin('battleship');
      _statsUpdated = true;
    } else {
      connService.incrementLoss('battleship');
      _statsUpdated = true;
    }
  }

  void _requestReset() {
    setState(() {
      _waitingForResetAccept = true;
    });
    Provider.of<ConnectivityService>(context, listen: false).sendPayload({
      'type': 'game_reset',
      'gameId': 'battleship',
    });
  }

  void _resetBoard() {
    setState(() {
      _myBoard = List.generate(10, (_) => List.generate(10, (_) => 0));
      _opponentBoard = List.generate(10, (_) => List.generate(10, (_) => 0));
      _isPlacementPhase = true;
      _currentShipIndex = 0;
      _iAmReady = false;
      _opponentIsReady = false;
      _isGameOver = false;
      _iWon = false;
      _waitingForResetAccept = false;
      _tabController.index = 0;
      _statsUpdated = false;
      
      final connService = Provider.of<ConnectivityService>(context, listen: false);
      _myTurn = connService.isHost;
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

    // Guard dropped connection
    if (!connService.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const SizedBox();
    }


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
                        Expanded(
                          child: Center(
                            child: Text(
                              'Schiffe Versenken',
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
                  ),

                  if (_isPlacementPhase)
                    Expanded(child: _buildPlacementView(isDark))
                  else
                    Expanded(child: _buildBattleView(isDark, connService)),
                ],
              ),
            ),
            if (_isGameOver) _buildGameOverOverlay(context, isDark, connService),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildPlacementView(bool isDark) {
    final remainingShips = _shipSizes.length - _currentShipIndex;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    if (isLandscape) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left column: Instructions and orientation toggles
            Expanded(
              flex: 4,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Help card
                    GlassContainer(
                      padding: const EdgeInsets.all(12),
                      borderRadius: 16,
                      child: Row(
                        children: [
                          Icon(
                            Icons.help_outline_rounded,
                            color: isDark ? const Color(0xFF00F2FE) : const Color(0xFF8A2387),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _iAmReady
                                  ? 'Warte auf Gegner...'
                                  : 'Platziere Schiffe. Tippe auf das Gitter.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Placement Controls
                    if (!_iAmReady)
                      GlassContainer(
                        padding: const EdgeInsets.all(12),
                        borderRadius: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Nächstes Schiff: Gr. ${_shipSizes[_currentShipIndex]}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              'Noch $remainingShips Schiffe zu platzieren',
                              style: const TextStyle(color: Colors.grey, fontSize: 10),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF8A2387),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              onPressed: () {
                                setState(() {
                                  _isHorizontal = !_isHorizontal;
                                });
                              },
                              icon: Icon(_isHorizontal ? Icons.swap_horiz_rounded : Icons.swap_vert_rounded, size: 16),
                              label: Text(_isHorizontal ? 'Horizontal' : 'Vertikal', style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Right column: placement grid
            Expanded(
              flex: 5,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: _buildPlacementGrid(isDark),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          const SizedBox(height: 10),
          // Help card
          GlassContainer(
            padding: const EdgeInsets.all(16),
            borderRadius: 20,
            child: Row(
              children: [
                Icon(
                  Icons.help_outline_rounded,
                  color: isDark ? const Color(0xFF00F2FE) : const Color(0xFF8A2387),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _iAmReady
                        ? 'Warte auf Gegner...'
                        : 'Platziere deine Schiffe. Tippe auf das Gitter zum Platzieren.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),

          // Placement Controls
          if (!_iAmReady)
            GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              borderRadius: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nächstes Schiff: Gr. ${_shipSizes[_currentShipIndex]}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        'Noch $remainingShips Schiffe zu platzieren',
                        style: const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8A2387),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      setState(() {
                        _isHorizontal = !_isHorizontal;
                      });
                    },
                    icon: Icon(_isHorizontal ? Icons.swap_horiz_rounded : Icons.swap_vert_rounded),
                    label: Text(_isHorizontal ? 'Horizontal' : 'Vertikal'),
                  ),
                ],
              ),
            ),

          const Spacer(),

          // Grid View
          AspectRatio(
            aspectRatio: 1.0,
            child: _buildPlacementGrid(isDark),
          ),

          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildPlacementGrid(bool isDark) {
    return GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 10,
        ),
        itemCount: 100,
        itemBuilder: (context, index) {
          final x = index % 10;
          final y = index ~/ 10;
          final cellVal = _myBoard[y][x];

          return GestureDetector(
            onTap: () => _placeShip(x, y),
            child: Container(
              decoration: BoxDecoration(
                color: cellVal == 1
                    ? const Color(0xFF8A2387).withOpacity(0.5)
                    : (isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.01)),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                  width: 0.5,
                ),
              ),
              child: cellVal == 1
                  ? const Center(
                      child: Icon(Icons.directions_boat_rounded, size: 14, color: Colors.white),
                    )
                  : const SizedBox(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBattleView(bool isDark, ConnectivityService service) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    if (isLandscape) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          children: [
            // Turn Status / Game Over info bar
            if (!_isGameOver)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: _myTurn
                      ? (isDark ? const Color(0xFF8A2387).withOpacity(0.1) : Colors.purple.withOpacity(0.05))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _myTurn ? 'Du bist am Zug! Feuere!' : 'Gegner wählt Ziel...',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _myTurn
                        ? (isDark ? const Color(0xFF00F2FE) : const Color(0xFF8A2387))
                        : (isDark ? Colors.white60 : Colors.black54),
                  ),
                ),
              ),
            // The two grids side-by-side
            Expanded(
              child: Row(
                children: [
                  // My fleet grid (Mein Ozean)
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'Meine Flotte',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1.0,
                              child: _buildMyOceanGrid(isDark),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Attack target grid (Angriff)
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'Angriff (Ziel)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1.0,
                              child: _buildAttackGrid(isDark),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Tab Headers to switch view
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: isDark ? const Color(0xFF1B1437) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: isDark ? [] : AppTheme.softShadow,
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: isDark ? Colors.white : Colors.black87,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            unselectedLabelColor: Colors.grey,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'Angriff (Ziel)'),
              Tab(text: 'Meine Flotte'),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Turn Status / Game Over
        if (!_isGameOver)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: _myTurn
                  ? (isDark ? const Color(0xFF8A2387).withOpacity(0.1) : Colors.purple.withOpacity(0.05))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _myTurn ? 'Du bist am Zug! Feuere!' : 'Gegner wählt Ziel...',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _myTurn
                    ? (isDark ? const Color(0xFF00F2FE) : const Color(0xFF8A2387))
                    : (isDark ? Colors.white60 : Colors.black54),
              ),
            ),
          ),

        const Spacer(),

        // Ocean Grid View
        Expanded(
          flex: 8,
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Opponent ocean (Where we fire)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: _buildAttackGrid(isDark),
                ),
              ),

              // Tab 2: My ocean (Where opponent fires)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: _buildMyOceanGrid(isDark),
                ),
              ),
            ],
          ),
        ),
        
        const Spacer(),
      ],
    );
  }

  Widget _buildMyOceanGrid(bool isDark) {
    return GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 10,
        ),
        itemCount: 100,
        itemBuilder: (context, index) {
          final x = index % 10;
          final y = index ~/ 10;
          final cellVal = _myBoard[y][x];

          return Container(
            decoration: BoxDecoration(
              color: cellVal == 1
                  ? const Color(0xFF00F2FE).withOpacity(0.15)
                  : (isDark ? const Color(0xFF0B0F19) : Colors.white),
              border: Border.all(
                color: isDark ? const Color(0xFF00F2FE).withOpacity(0.15) : Colors.black.withOpacity(0.05),
                width: 0.5,
              ),
            ),
            child: Center(
              child: _buildMyFleetIndicator(cellVal),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAttackGrid(bool isDark) {
    return GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 10,
        ),
        itemCount: 100,
        itemBuilder: (context, index) {
          final x = index % 10;
          final y = index ~/ 10;
          final cellVal = _opponentBoard[y][x];

          return GestureDetector(
            onTap: () => _fireAtOpponent(x, y),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0B0F19) : Colors.white,
                border: Border.all(
                  color: isDark ? const Color(0xFF00F2FE).withOpacity(0.15) : Colors.black.withOpacity(0.05),
                  width: 0.5,
                ),
              ),
              child: Center(
                child: _buildAttackIndicator(cellVal),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAttackIndicator(int val) {
    if (val == 2) {
      return Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFFF007F).withOpacity(0.3),
          border: Border.all(color: const Color(0xFFFF007F), width: 2),
          boxShadow: AppTheme.neonGlow(const Color(0xFFFF007F)),
        ),
        child: const Center(
          child: Icon(Icons.close_rounded, size: 12, color: Colors.white),
        ),
      ).animate(onPlay: (c) => c.repeat())
       .scaleXY(begin: 0.9, end: 1.1, duration: 800.ms, curve: Curves.easeInOut);
    } else if (val == 3) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF00F2FE).withOpacity(0.4),
          boxShadow: AppTheme.neonGlow(const Color(0xFF00F2FE)),
        ),
      ).animate(onPlay: (c) => c.repeat())
       .scaleXY(begin: 0.8, end: 1.6, duration: 1500.ms, curve: Curves.easeInOut)
       .fadeOut(duration: 1500.ms);
    }
    return const SizedBox();
  }

  Widget _buildMyFleetIndicator(int val) {
    if (val == 1) {
      return const Icon(Icons.directions_boat_rounded, size: 14, color: Color(0xFF00F2FE))
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(begin: 0.95, end: 1.05, duration: 1500.ms);
    } else if (val == 2) {
      return Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFFF007F).withOpacity(0.4),
          border: Border.all(color: const Color(0xFFFF007F), width: 2),
          boxShadow: AppTheme.neonGlow(const Color(0xFFFF007F)),
        ),
        child: const Center(
          child: Icon(Icons.close_rounded, size: 10, color: Colors.white),
        ),
      ).animate().shake(duration: 300.ms);
    } else if (val == 3) {
      return Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF00F2FE),
        ),
      );
    }
    return const SizedBox();
  }

  Widget _buildGameOverOverlay(BuildContext context, bool isDark, ConnectivityService connService) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final winColor = _iWon ? Colors.greenAccent : Colors.redAccent;
    final title = _iWon ? 'SIEG!' : 'NIEDERLAGE!';
    final desc = _iWon
        ? 'Alle gegnerischen Schiffe wurden erfolgreich versenkt!'
        : 'Deine Flotte wurde vollständig vernichtet!';

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
                      _iWon ? Icons.emoji_events_rounded : Icons.sentiment_very_dissatisfied_rounded,
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
}
