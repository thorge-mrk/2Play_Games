import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import 'lobby_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _progress = 0.0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  void _startLoading() {
    const steps = 100;
    const duration = Duration(milliseconds: 1400);
    final interval = duration.inMilliseconds ~/ steps;

    _timer = Timer.periodic(Duration(milliseconds: interval), (timer) {
      setState(() {
        if (_progress < 1.0) {
          _progress += 1.0 / steps;
        } else {
          _timer?.cancel();
          _navigateToLobby();
        }
      });
    });
  }

  void _navigateToLobby() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LobbyScreen()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0C0720), Color(0xFF1D0E39), Color(0xFF0F0B1E)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEFF3F8), Color(0xFFE2EAF4), Color(0xFFF7F8FC)],
          );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: bgGradient),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 3),
              // Glowing Animated App Logo
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: isDark
                      ? AppTheme.neonGlow(const Color(0xFF8A2387))
                      : AppTheme.softShadow,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(70),
                  child: Image.asset(
                    isDark ? 'assets/images/app_icon_dark.png' : 'assets/images/app_icon_light.png',
                    fit: BoxFit.cover,
                  ),
                ),
              )
                  .animate(onPlay: (controller) => controller.repeat(reverse: true))
                  .scaleXY(begin: 0.95, end: 1.05, duration: 1500.ms, curve: Curves.easeInOut)
                  .rotate(begin: -0.02, end: 0.02, duration: 2000.ms, curve: Curves.easeInOut),
              
              const SizedBox(height: 32),
              
              // App Name
              Text(
                '2Play',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  shadows: isDark
                      ? [
                          Shadow(
                            color: const Color(0xFF00F2FE).withValues(alpha: 0.8),
                            blurRadius: 20,
                          ),
                          Shadow(
                            color: const Color(0xFF8A2387).withValues(alpha: 0.8),
                            blurRadius: 40,
                          ),
                        ]
                      : [],
                ),
              ).animate().fadeIn(duration: 800.ms).slideY(begin: 0.2, end: 0),
              
              const SizedBox(height: 8),
              
              // Subtitle
              Text(
                'OFFLINE MULTIPLAYER HUB',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: isDark ? const Color(0xFFC5C2E7).withValues(alpha: 0.7) : Colors.grey[600],
                ),
              ).animate().fadeIn(delay: 300.ms, duration: 600.ms),

              const Spacer(flex: 2),

              // Liquid Glass Progress Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Column(
                  children: [
                    GlassContainer(
                      height: 12,
                      borderRadius: 6,
                      child: Stack(
                        children: [
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: _progress.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF8A2387),
                                    Color(0xFF00F2FE),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'LADE SPIELUMGEBUNG... ${( _progress * 100 ).toInt()}%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: isDark ? Colors.white60 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 500.ms, duration: 600.ms),
              
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
