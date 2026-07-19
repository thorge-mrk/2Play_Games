import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design tokens and themes for 2Play.
class AppTheme {
  // Brand base colors
  static const Color darkBg = Color(0xFF0B0F19);
  static const Color darkCard = Color(0xFF161B26);
  static const Color lightBg = Color(0xFFF8F9FD);
  static const Color lightCard = Color(0xFFFFFFFF);

  static const Color primaryPurple = Color(0xFF8A2387);

  // Gradient colors
  static const List<Color> primaryGradient = [
    Color(0xFF8A2387), // Violet
    Color(0xFFE94057), // Sunset Pink
    Color(0xFFF27121), // Amber
  ];

  static const List<Color> neonBlueGradient = [
    Color(0xFF00F2FE), // Cyan
    Color(0xFF4FACFE), // Blue
  ];

  static const List<Color> neonPurpleGradient = [
    Color(0xFFB92B27), // Dark red/purple
    Color(0xFF1565C0), // Deep blue
  ];

  // Accent colors
  static const Color accentNeonCyan = Color(0xFF00E5FF);
  static const Color accentNeonPink = Color(0xFFFF007F);
  static const Color accentNeonGreen = Color(0xFF39FF14);
  static const Color accentNeonYellow = Color(0xFFFFEA00);

  // Box shadows
  static List<BoxShadow> neonGlow(Color color) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.3),
        blurRadius: 12,
        spreadRadius: 1,
      ),
    ];
  }

  static List<BoxShadow> softShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 16,
      offset: const Offset(0, 8),
    ),
  ];

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = isDark
        ? const ColorScheme.dark(
            primary: primaryPurple,
            secondary: Color(0xFF00F2FE),
            surface: darkCard,
            error: Color(0xFFEF4444),
          )
        : const ColorScheme.light(
            primary: primaryPurple,
            secondary: Color(0xFF4FACFE),
            surface: lightCard,
            error: Color(0xFFDC2626),
          );

    final baseText = isDark ? ThemeData.dark() : ThemeData.light();

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      primaryColor: primaryPurple,
      scaffoldBackgroundColor: isDark ? darkBg : lightBg,
      cardColor: isDark ? darkCard : lightCard,
      dividerColor: isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB),
      splashFactory: InkSparkle.splashFactory,
      textTheme: GoogleFonts.outfitTextTheme(baseText.textTheme).copyWith(
        titleLarge: GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : const Color(0xFF111827),
        ),
        bodyLarge: GoogleFonts.outfit(
          fontSize: 16,
          height: 1.4,
          color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF4B5563),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? darkCard : lightCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }

  static ThemeData get lightTheme => _base(Brightness.light);
  static ThemeData get darkTheme => _base(Brightness.dark);
}

/// Simple card container used across the app (formerly a glass effect,
/// now a flat, elevated card look).
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur; // Kept for interface compatibility
  final double borderRadius;
  final Border? border;
  final List<Color>? gradientColors;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final AlignmentGeometry? alignment;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 0.0,
    this.borderRadius = 20.0,
    this.border,
    this.gradientColors,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final backgroundColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final finalBorder = border ??
        Border.all(
          color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB),
          width: 1.5,
        );

    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: gradientColors == null ? backgroundColor : null,
        gradient: gradientColors != null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors!,
              )
            : null,
        borderRadius: BorderRadius.circular(borderRadius),
        border: finalBorder,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
