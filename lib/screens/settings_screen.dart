import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _nameController;
  bool _isEditingName = false;

  @override
  void initState() {
    super.initState();
    final connService = Provider.of<ConnectivityService>(context, listen: false);
    _nameController = TextEditingController(text: connService.myUsername);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _saveName() {
    if (_nameController.text.trim().isNotEmpty) {
      Provider.of<ConnectivityService>(context, listen: false)
          .setUsername(_nameController.text.trim());
      setState(() {
        _isEditingName = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final connService = Provider.of<ConnectivityService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
              // Custom Nav Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Einstellungen',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    // Section: Profile
                    _buildSectionHeader(context, 'PROFIL'),
                    const SizedBox(height: 12),
                    GlassContainer(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(colors: AppTheme.primaryGradient),
                                ),
                                child: const Center(
                                  child: Icon(Icons.sports_esports_rounded, color: Colors.white, size: 28),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _isEditingName
                                    ? TextField(
                                        controller: _nameController,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                        autofocus: true,
                                        decoration: InputDecoration(
                                          hintText: 'Spielername',
                                          isDense: true,
                                          border: UnderlineInputBorder(
                                            borderSide: BorderSide(
                                              color: isDark ? Colors.white54 : Colors.black54,
                                            ),
                                          ),
                                        ),
                                        onSubmitted: (_) => _saveName(),
                                      )
                                    : Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            connService.myUsername,
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Eigener Anzeigename',
                                            style: TextStyle(fontSize: 12, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                              ),
                              IconButton(
                                icon: Icon(
                                  _isEditingName ? Icons.check_circle_outline_rounded : Icons.edit_rounded,
                                  color: const Color(0xFF00F2FE),
                                ),
                                onPressed: _isEditingName ? _saveName : () => setState(() => _isEditingName = true),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 400.ms),

                    const SizedBox(height: 28),

                    // Section: Design
                    _buildSectionHeader(context, 'DESIGN'),
                    const SizedBox(height: 12),
                    GlassContainer(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                                color: isDark ? const Color(0xFF00F2FE) : const Color(0xFF8A2387),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                'Dunkles Design (Dark Mode)',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          CupertinoSwitch(
                            activeColor: const Color(0xFF8A2387),
                            trackColor: Colors.grey.withOpacity(0.3),
                            value: connService.isDarkMode,
                            onChanged: (val) => connService.setDarkMode(val),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 100.ms, duration: 400.ms),

                    const SizedBox(height: 28),

                    // Section: Bot difficulty
                    _buildSectionHeader(context, 'BOT-SCHWIERIGKEIT'),
                    const SizedBox(height: 12),
                    GlassContainer(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.smart_toy_rounded,
                                color: const Color(0xFF00F2FE),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                'Schwierigkeitsgrad',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.black38 : Colors.black.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                for (var diff in ['einfach', 'mittel', 'schwer'])
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => connService.setBotDifficulty(diff),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        decoration: BoxDecoration(
                                          color: connService.botDifficulty == diff
                                              ? (isDark ? const Color(0xFF1B1437) : Colors.white)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                          boxShadow: connService.botDifficulty == diff && !isDark
                                              ? AppTheme.softShadow
                                              : [],
                                        ),
                                        child: Center(
                                          child: Text(
                                            diff == 'einfach' ? 'Einfach' : (diff == 'mittel' ? 'Mittel' : 'Schwer'),
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: connService.botDifficulty == diff
                                                  ? (isDark ? Colors.white : Colors.black87)
                                                  : Colors.grey,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

                    const SizedBox(height: 28),

                    // Section: Statistics
                    _buildSectionHeader(context, 'STATISTIKEN'),
                    const SizedBox(height: 12),
                    GlassContainer(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.analytics_rounded,
                                color: const Color(0xFFFF007F),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                'Deine Spielzeit & Erfolge',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildStatItem(
                                context,
                                'Online-Zeit',
                                '${(connService.totalPlayTimeSeconds / 3600).toStringAsFixed(1)} Std',
                                Icons.timer_rounded,
                              ),
                              _buildStatItem(
                                context,
                                'Lieblingsspiel',
                                connService.favoriteGame,
                                Icons.favorite_rounded,
                              ),
                            ],
                          ),
                          const Divider(height: 32, thickness: 1),
                          Text(
                            'Spiel-Statistiken:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (var entry in connService.gameStats.entries)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    entry.key == 'tictactoe'
                                        ? 'Tic-Tac-Toe'
                                        : (entry.key == 'connect4'
                                            ? 'Vier Gewinnt'
                                            : (entry.key == 'battleship'
                                                ? 'Schiffe Versenken'
                                                : (entry.key == 'rockpaperscissors'
                                                    ? 'Schere, Stein, Papier'
                                                    : 'Minigolf'))),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  Text(
                                    'Siege: ${entry.value['wins_vs_bot']! + entry.value['wins_vs_player']!} | Niederlagen: ${entry.value['losses_vs_bot']! + entry.value['losses_vs_player']!}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white54 : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
        color: isDark ? Colors.white60 : Colors.grey[700],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }
}
