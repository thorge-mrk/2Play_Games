import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import 'tictactoe_screen.dart';
import 'connectfour_screen.dart';
import 'battleship_screen.dart';
import 'rockpaperscissors_screen.dart';
import 'minigolf_screen.dart';
import '../widgets/chat_sheet.dart';

class GameSelectionScreen extends StatefulWidget {
  const GameSelectionScreen({super.key});

  @override
  State<GameSelectionScreen> createState() => _GameSelectionScreenState();
}

class _GameSelectionScreenState extends State<GameSelectionScreen> {
  StreamSubscription? _msgSubscription;

  @override
  void initState() {
    super.initState();
    final connService = Provider.of<ConnectivityService>(context, listen: false);
    
    // Listen to incoming messages for game selection triggers (needed for client)
    _msgSubscription = connService.messageStream.listen((payload) {
      if (payload['type'] == 'game_select') {
        final gameId = payload['gameId'] as String;
        if (!connService.isHost) {
          _navigateToGame(gameId);
        }
      }
    });
  }

  @override
  void dispose() {
    _msgSubscription?.cancel();
    super.dispose();
  }

  void _navigateToGame(String gameId) {
    Widget gameScreen;
    switch (gameId) {
      case 'tictactoe':
        gameScreen = const TicTacToeScreen();
        break;
      case 'connect4':
        gameScreen = const ConnectFourScreen();
        break;
      case 'battleship':
        gameScreen = const BattleshipScreen();
        break;
      case 'rockpaperscissors':
        gameScreen = const RockPaperScissorsScreen();
        break;
      case 'minigolf':
        gameScreen = const MinigolfScreen();
        break;
      default:
        return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => gameScreen),
    ).then((_) {
      // When popping back from a game, let the connection service know we exited
      final connService = Provider.of<ConnectivityService>(context, listen: false);
      if (connService.isHost && connService.activeGameId != null) {
        connService.exitGame();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final connService = Provider.of<ConnectivityService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Guard: Return to lobby if connection is lost
    if (!connService.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      });
      return const SizedBox();
    }

    final games = [
      {
        'id': 'tictactoe',
        'title': 'Tic-Tac-Toe',
        'desc': 'Klassisches 3x3 Raster. Bringe 3 deiner Symbole in eine Reihe!',
        'icon': Icons.grid_3x3_rounded,
        'colors': AppTheme.primaryGradient,
      },
      {
        'id': 'connect4',
        'title': 'Vier Gewinnt',
        'desc': 'Lasse deine Chips in das Gitter fallen und bilde eine 4er-Reihe!',
        'icon': Icons.view_column_rounded,
        'colors': AppTheme.neonBlueGradient,
      },
      {
        'id': 'battleship',
        'title': 'Schiffe Versenken',
        'desc': 'Platziere deine Flotte geheim und vernichte die gegnerischen Schiffe!',
        'icon': Icons.directions_boat_rounded,
        'colors': AppTheme.neonPurpleGradient,
      },
      {
        'id': 'rockpaperscissors',
        'title': 'Schere, Stein, Papier',
        'desc': 'Ein schnelles Duell. Wähle deine Geste und besiege den Gegner!',
        'icon': Icons.sports_handball_rounded,
        'colors': [const Color(0xFFFF8C00), const Color(0xFFFF007F)],
      },
      {
        'id': 'minigolf',
        'title': 'Mini-Golf',
        'desc': 'Bringe den Ball mit möglichst wenigen Schlägen ins Loch! 50 Levels & Turnier-Modus.',
        'icon': Icons.flag_rounded,
        'colors': [Colors.green[600]!, Colors.teal],
      },
    ];

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Custom Navigation Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.sports_esports_rounded,
                          color: Color(0xFF00F2FE),
                          size: 32,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '2Play Spiele',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(Icons.chat_bubble_rounded, color: isDark ? Colors.white70 : Colors.black87, size: 26),
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
                                        fontSize: 9,
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
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.withOpacity(0.1),
                            foregroundColor: Colors.redAccent,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onPressed: () => connService.disconnect(),
                          icon: const Icon(Icons.power_settings_new_rounded, size: 16),
                          label: const Text('Trennen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Sub-info: Who are we connected with?
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 14,
                      color: Colors.greenAccent[400],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Verbunden mit: ${connService.connectedPeer?.name}',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Host vs Client instructions banner
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GlassContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  borderRadius: 16,
                  child: Row(
                    children: [
                      Icon(
                        connService.isHost ? Icons.vpn_key_rounded : Icons.hourglass_empty_rounded,
                        color: const Color(0xFF00F2FE),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          connService.isHost
                              ? 'Du bist der Host. Wähle ein Spiel aus, um die Runde für beide zu starten!'
                              : 'Warte darauf, dass der Host ein Spiel auswählt, um das Duell zu beginnen...',
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
              ).animate().fadeIn(delay: 150.ms),

              const SizedBox(height: 24),

              // Games List
              Expanded(
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                  itemCount: games.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final game = games[index];
                    final canInteract = connService.isHost;

                    return GestureDetector(
                      onTap: canInteract
                          ? () {
                              connService.selectGame(game['id'] as String);
                              _navigateToGame(game['id'] as String);
                            }
                          : null,
                      child: Opacity(
                        opacity: canInteract ? 1.0 : 0.6,
                        child: GlassContainer(
                          borderRadius: 24,
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              // Icon block
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: game['colors'] as List<Color>,
                                  ),
                                  boxShadow: isDark
                                      ? AppTheme.neonGlow((game['colors'] as List<Color>)[0])
                                      : AppTheme.softShadow,
                                ),
                                child: Icon(
                                  game['icon'] as IconData,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Info text block
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      game['title'] as String,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      game['desc'] as String,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.white60 : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Play arrow if Host
                              if (canInteract)
                                const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: Color(0xFF00F2FE),
                                  size: 16,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ).animate().fadeIn(delay: Duration(milliseconds: 200 + index * 100)).slideX(begin: 0.1, end: 0);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
