import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/game_ui.dart';

class BattleshipScreen extends StatefulWidget {
  const BattleshipScreen({super.key});

  @override
  State<BattleshipScreen> createState() => _BattleshipScreenState();
}

class _BattleshipScreenState extends State<BattleshipScreen>
    with SingleTickerProviderStateMixin {
  // Board states: 10x10. 0 = Empty, 1 = Ship, 2 = Hit, 3 = Miss
  List<List<int>> _myBoard = List.generate(10, (_) => List.filled(10, 0));
  List<List<int>> _opponentBoard =
      List.generate(10, (_) => List.filled(10, 0));

  // Placement phase
  bool _isPlacementPhase = true;
  final List<int> _shipSizes = [5, 4, 3, 3, 2];
  int _currentShipIndex = 0;
  bool _isHorizontal = true;
  bool _iAmReady = false;
  bool _opponentIsReady = false;

  // Battle phase
  late TabController _tabController;
  bool _myTurn = true;
  StreamSubscription? _msgSubscription;
  bool _isGameOver = false;
  bool _iWon = false;
  bool _waitingForResetAccept = false;
  bool _statsUpdated = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final connService =
        Provider.of<ConnectivityService>(context, listen: false);
    _myTurn = connService.isHost; // Host fires first

    _msgSubscription = connService.messageStream.listen(_onMessage);
  }

  void _onMessage(Map<String, dynamic> payload) {
    if (!mounted) return;
    final connService =
        Provider.of<ConnectivityService>(context, listen: false);

    if (payload['type'] == 'game_move' && payload['gameId'] == 'battleship') {
      final data = payload['data'] as Map<String, dynamic>;
      final subtype = data['subtype'] as String?;

      if (subtype == 'player_ready') {
        setState(() {
          _opponentIsReady = true;
          _checkStartBattle();
        });
      } else if (subtype == 'ai_ready') {
        setState(() {
          _opponentIsReady = true;
          // The bot's fleet layout, kept locally for hit checking.
          _opponentBoard = [
            for (final row in data['aiBoard'] as List) List<int>.from(row)
          ];
          _checkStartBattle();
        });
      } else if (subtype == 'fire') {
        // Opponent fired at our grid.
        final tx = data['x'] as int;
        final ty = data['y'] as int;
        final cell = _myBoard[ty][tx];
        // Ignore duplicate shots on an already resolved cell.
        if (cell == 2 || cell == 3) return;
        final hit = cell == 1;

        setState(() {
          _myBoard[ty][tx] = hit ? 2 : 3;
          _myTurn = true;
          _checkWinState();
        });

        connService.sendPayload({
          'type': 'game_move',
          'gameId': 'battleship',
          'data': {
            'subtype': 'fire_result',
            'x': tx,
            'y': ty,
            'isHit': hit,
          }
        });
      } else if (subtype == 'fire_result') {
        final tx = data['x'] as int;
        final ty = data['y'] as int;
        final isHit = data['isHit'] as bool;

        setState(() {
          _opponentBoard[ty][tx] = isHit ? 2 : 3;
          _checkWinState();
        });
      } else if (subtype == 'ai_fire') {
        // The bot fired at us – board state comes pre-computed.
        setState(() {
          _myBoard = [
            for (final row in data['userBoard'] as List) List<int>.from(row)
          ];
          _myTurn = true;
          _checkWinState();
        });
      }
    } else if (payload['type'] == 'game_reset' &&
        payload['gameId'] == 'battleship') {
      connService.sendPayload({
        'type': 'game_reset_accept',
        'gameId': 'battleship',
      });
      _resetBoard();
    } else if (payload['type'] == 'game_reset_accept' &&
        payload['gameId'] == 'battleship') {
      _resetBoard();
    } else if (payload['type'] == 'game_exit') {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _msgSubscription?.cancel();
    super.dispose();
  }

  void _checkStartBattle() {
    if (_iAmReady && _opponentIsReady && _isPlacementPhase) {
      _isPlacementPhase = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Kampfphase gestartet! Feuer frei!'),
            backgroundColor: AppTheme.primaryPurple),
      );
    }
  }

  void _placeShip(int x, int y) {
    if (_currentShipIndex >= _shipSizes.length || _iAmReady) return;

    final size = _shipSizes[_currentShipIndex];
    if (!_canPlaceShip(x, y, size, _isHorizontal)) return;

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
        _setPlayerReady();
      }
    });
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

  void _undoPlacement() {
    if (_iAmReady || _currentShipIndex == 0) return;
    setState(() {
      _myBoard = List.generate(10, (_) => List.filled(10, 0));
      _currentShipIndex = 0;
    });
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
    if (_opponentBoard[y][x] == 2 || _opponentBoard[y][x] == 3) return;

    final connService =
        Provider.of<ConnectivityService>(context, listen: false);

    if (connService.connectedPeer?.isMock == true) {
      // Vs. bot: _opponentBoard holds the bot's actual fleet.
      final isHit = _opponentBoard[y][x] == 1;
      setState(() {
        _opponentBoard[y][x] = isHit ? 2 : 3;
        _myTurn = false;
        _checkWinState();
      });

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
      // Real mode: turn ends immediately so quick taps can't double-fire.
      setState(() => _myTurn = false);
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
    // Total ship squares: 5 + 4 + 3 + 3 + 2 = 17
    int myHits = 0;
    int opponentHits = 0;
    for (int r = 0; r < 10; r++) {
      for (int c = 0; c < 10; c++) {
        if (_myBoard[r][c] == 2) myHits++;
        if (_opponentBoard[r][c] == 2) opponentHits++;
      }
    }

    if (opponentHits == 17) {
      _isGameOver = true;
      _iWon = true;
      _updateStats();
    } else if (myHits == 17) {
      _isGameOver = true;
      _iWon = false;
      _updateStats();
    }
  }

  void _updateStats() {
    if (_statsUpdated) return;
    _statsUpdated = true;
    final connService =
        Provider.of<ConnectivityService>(context, listen: false);
    if (_iWon) {
      connService.incrementWin('battleship');
    } else {
      connService.incrementLoss('battleship');
    }
  }

  void _requestReset() {
    setState(() => _waitingForResetAccept = true);
    Provider.of<ConnectivityService>(context, listen: false).sendPayload({
      'type': 'game_reset',
      'gameId': 'battleship',
    });
  }

  void _resetBoard() {
    setState(() {
      _myBoard = List.generate(10, (_) => List.filled(10, 0));
      _opponentBoard = List.generate(10, (_) => List.filled(10, 0));
      _isPlacementPhase = true;
      _currentShipIndex = 0;
      _iAmReady = false;
      _opponentIsReady = false;
      _isGameOver = false;
      _iWon = false;
      _waitingForResetAccept = false;
      _tabController.index = 0;
      _statsUpdated = false;
      _myTurn =
          Provider.of<ConnectivityService>(context, listen: false).isHost;
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
                child: Column(
                  children: [
                    GameHeader(title: 'Schiffe Versenken', onExit: _exitGame),
                    if (_isPlacementPhase)
                      Expanded(child: _buildPlacementView(isDark))
                    else
                      Expanded(child: _buildBattleView(isDark)),
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

  Widget _buildPlacementView(bool isDark) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final infoCard = GlassContainer(
      padding: const EdgeInsets.all(14),
      borderRadius: 16,
      child: Row(
        children: [
          Icon(
            Icons.help_outline_rounded,
            color: isDark ? const Color(0xFF00F2FE) : AppTheme.primaryPurple,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _iAmReady
                  ? 'Warte auf Gegner...'
                  : 'Platziere deine Schiffe. Tippe auf das Gitter zum Platzieren.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );

    final controls = _iAmReady
        ? const SizedBox.shrink()
        : GlassContainer(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            borderRadius: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nächstes Schiff: ${_currentShipIndex < _shipSizes.length ? _shipSizes[_currentShipIndex] : '-'} Felder',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        'Noch ${_shipSizes.length - _currentShipIndex} Schiffe',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Platzierung zurücksetzen',
                  onPressed: _currentShipIndex > 0 ? _undoPlacement : null,
                  icon: const Icon(Icons.restart_alt_rounded, size: 20),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryPurple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () =>
                      setState(() => _isHorizontal = !_isHorizontal),
                  icon: Icon(
                      _isHorizontal
                          ? Icons.swap_horiz_rounded
                          : Icons.swap_vert_rounded,
                      size: 18),
                  label: Text(_isHorizontal ? 'Horizontal' : 'Vertikal',
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          );

    final grid = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: _buildPlacementGrid(isDark),
        ),
      ),
    );

    if (isLandscape) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 4,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    infoCard,
                    const SizedBox(height: 12),
                    controls,
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(flex: 5, child: grid),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          const SizedBox(height: 8),
          infoCard,
          const SizedBox(height: 12),
          controls,
          const Spacer(),
          grid,
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
                    ? AppTheme.primaryPurple.withValues(alpha: 0.5)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.02)
                        : Colors.black.withValues(alpha: 0.01)),
                border: Border.all(
                  color: isDark
                      ? Colors.white10
                      : Colors.black.withValues(alpha: 0.05),
                  width: 0.5,
                ),
              ),
              child: cellVal == 1
                  ? const Center(
                      child: Icon(Icons.directions_boat_rounded,
                          size: 14, color: Colors.white),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBattleView(bool isDark) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final turnBanner = _isGameOver
        ? const SizedBox.shrink()
        : Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            decoration: BoxDecoration(
              color: _myTurn
                  ? AppTheme.primaryPurple
                      .withValues(alpha: isDark ? 0.1 : 0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _myTurn ? 'Du bist am Zug! Feuere!' : 'Gegner wählt Ziel...',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _myTurn
                    ? (isDark
                        ? const Color(0xFF00F2FE)
                        : AppTheme.primaryPurple)
                    : (isDark ? Colors.white60 : Colors.black54),
              ),
            ),
          );

    Widget boxedGrid(Widget grid) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 480),
            child: AspectRatio(aspectRatio: 1.0, child: grid),
          ),
        );

    if (isLandscape) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          children: [
            turnBanner,
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text('Meine Flotte',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.grey)),
                        const SizedBox(height: 4),
                        Expanded(child: boxedGrid(_buildMyOceanGrid(isDark))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        const Text('Angriff (Ziel)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.grey)),
                        const SizedBox(height: 4),
                        Expanded(child: boxedGrid(_buildAttackGrid(isDark))),
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
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black26
                : Colors.black.withValues(alpha: 0.05),
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
            labelStyle:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            unselectedLabelColor: Colors.grey,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'Angriff (Ziel)'),
              Tab(text: 'Meine Flotte'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        turnBanner,
        const SizedBox(height: 6),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: boxedGrid(_buildAttackGrid(isDark)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: boxedGrid(_buildMyOceanGrid(isDark)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
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
                  ? const Color(0xFF00F2FE).withValues(alpha: 0.15)
                  : (isDark ? AppTheme.darkBg : Colors.white),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF00F2FE).withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.05),
                width: 0.5,
              ),
            ),
            child: Center(child: _FleetCell(value: cellVal)),
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
                color: isDark ? AppTheme.darkBg : Colors.white,
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF00F2FE).withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.05),
                  width: 0.5,
                ),
              ),
              child: Center(child: _AttackCell(value: cellVal)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGameOverOverlay() {
    return GameResultOverlay(
      title: _iWon ? 'SIEG!' : 'NIEDERLAGE!',
      description: _iWon
          ? 'Alle gegnerischen Schiffe wurden erfolgreich versenkt!'
          : 'Deine Flotte wurde vollständig vernichtet!',
      color: _iWon ? Colors.greenAccent : Colors.redAccent,
      icon: _iWon
          ? Icons.emoji_events_rounded
          : Icons.sentiment_very_dissatisfied_rounded,
      onExit: _exitGame,
      onRematch: _requestReset,
      waitingForRematch: _waitingForResetAccept,
    );
  }
}

/// Cell of the attack grid. Hits/misses animate once (no endless repaint).
class _AttackCell extends StatelessWidget {
  final int value;
  const _AttackCell({required this.value});

  @override
  Widget build(BuildContext context) {
    if (value == 2) {
      return Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.accentNeonPink.withValues(alpha: 0.3),
          border: Border.all(color: AppTheme.accentNeonPink, width: 2),
        ),
        child: const Center(
          child: Icon(Icons.close_rounded, size: 12, color: Colors.white),
        ),
      )
          .animate()
          .scaleXY(begin: 0.4, end: 1.0, duration: 300.ms, curve: Curves.easeOutBack);
    } else if (value == 3) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF00F2FE).withValues(alpha: 0.5),
        ),
      ).animate().scaleXY(begin: 0.4, end: 1.0, duration: 250.ms);
    }
    return const SizedBox.shrink();
  }
}

/// Cell of my fleet grid.
class _FleetCell extends StatelessWidget {
  final int value;
  const _FleetCell({required this.value});

  @override
  Widget build(BuildContext context) {
    if (value == 1) {
      return const Icon(Icons.directions_boat_rounded,
          size: 14, color: Color(0xFF00F2FE));
    } else if (value == 2) {
      return Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.accentNeonPink.withValues(alpha: 0.4),
          border: Border.all(color: AppTheme.accentNeonPink, width: 2),
        ),
        child: const Center(
          child: Icon(Icons.close_rounded, size: 10, color: Colors.white),
        ),
      ).animate().shake(duration: 300.ms);
    } else if (value == 3) {
      return Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF00F2FE),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
