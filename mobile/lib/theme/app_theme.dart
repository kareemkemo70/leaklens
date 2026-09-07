// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Brand Colors ────────────────────────────────────────────────
  static const cyan       = Color(0xFF00D4FF);
  static const cyanDark   = Color(0xFF0096B7);
  static const green      = Color(0xFF00E676);
  static const red        = Color(0xFFFF4756);
  static const orange     = Color(0xFFFF9100);
  static const purple     = Color(0xFF9C27B0);

  static const bgPrimary   = Color(0xFF080D1A);
  static const bgSecondary = Color(0xFF0D1526);
  static const bgCard      = Color(0xFF111927);
  static const bgCardHover = Color(0xFF172133);

  static const textPrimary   = Color(0xFFE8EAF6);
  static const textSecondary = Color(0xFF7986A1);
  static const textMuted     = Color(0xFF4A5568);

  static const border       = Color(0xFF1E2D45);
  static const borderGlow   = Color(0x4D00D4FF);

  // ── Gradient Presets ─────────────────────────────────────────────
  static const leakGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC41230), Color(0xFFFF4756)],
  );
  static const normalGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00875A), Color(0xFF00E676)],
  );
  static const cyanGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF006A7A), Color(0xFF00D4FF)],
  );
  static const cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF111927), Color(0xFF0D1526)],
  );

  // ── ThemeData ─────────────────────────────────────────────────────
  static ThemeData get dark {
    final base = ThemeData.dark();
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge:  GoogleFonts.inter(color: textPrimary, fontWeight: FontWeight.w800),
      headlineMedium: GoogleFonts.inter(color: textPrimary, fontWeight: FontWeight.w700),
      bodyLarge:  GoogleFonts.inter(color: textPrimary),
      bodyMedium: GoogleFonts.inter(color: textSecondary),
      labelLarge: GoogleFonts.inter(color: textPrimary, fontWeight: FontWeight.w600),
    );

    return base.copyWith(
      scaffoldBackgroundColor: bgPrimary,
      colorScheme: const ColorScheme.dark(
        primary: cyan,
        secondary: green,
        error: red,
        surface: bgCard,
        onPrimary: bgPrimary,
        onSurface: textPrimary,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: bgSecondary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cyan,
          foregroundColor: bgPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgCard,
        hintStyle: GoogleFonts.inter(color: textMuted, fontSize: 14),
        labelStyle: GoogleFonts.inter(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cyan, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: red),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerColor: border,
      useMaterial3: true,
    );
  }
}

// ── Reusable Widgets ──────────────────────────────────────────────

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? borderColor;
  final double radius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? AppTheme.border),
      ),
      padding: padding ?? const EdgeInsets.all(20),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  const SectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppTheme.cyan,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}
