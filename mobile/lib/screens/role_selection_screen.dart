// lib/screens/role_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'auth/login_screen.dart';
import '../utils/nav.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF050B16), AppTheme.bgPrimary],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),

                  // ── Logo ─────────────────────────────────────────────
                  FadeInDown(
                    duration: const Duration(milliseconds: 250),
                    child: Column(
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            gradient: AppTheme.cyanGradient,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.cyan.withOpacity(0.35),
                                blurRadius: 30,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text('💧', style: TextStyle(fontSize: 44)),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'LeakLens',
                          style: GoogleFonts.inter(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Intelligent Water Leakage Detection',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 50),

                  FadeInUp(
                    duration: const Duration(milliseconds: 250),
                    delay: const Duration(milliseconds: 100),
                    child: Text(
                      'SELECT YOUR ROLE',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── User Card ──────────────────────────────────────────
                  FadeInLeft(
                    duration: const Duration(milliseconds: 250),
                    delay: const Duration(milliseconds: 150),
                    child: _RoleCard(
                      emoji: '👤',
                      title: 'User',
                      subtitle: 'Report issues, get alerts\nand water-saving tips',
                      gradient: AppTheme.cyanGradient,
                      onTap: () => pushFade(context, const LoginScreen(role: 'user')),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Engineer Card ──────────────────────────────────────
                  FadeInRight(
                    duration: const Duration(milliseconds: 250),
                    delay: const Duration(milliseconds: 200),
                    child: _RoleCard(
                      emoji: '👷',
                      title: 'Engineer',
                      subtitle: 'View dashboards, analytics\nand anomaly detections',
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF4A0080), Color(0xFF9C27B0)],
                      ),
                      onTap: () => pushFade(context, const LoginScreen(role: 'engineer')),
                    ),
                  ),

                  const SizedBox(height: 50),

                  FadeInUp(
                    duration: const Duration(milliseconds: 250),
                    delay: const Duration(milliseconds: 250),
                    child: Text(
                      'Powered by Conv1D Autoencoder · 119 Sensors · 95th-percentile threshold',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatefulWidget {
  final String emoji, title, subtitle;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _RoleCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp:   (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: widget.gradient.colors.last.withOpacity(0.25),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(widget.emoji, style: const TextStyle(fontSize: 28)),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: GoogleFonts.inter(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                   color: Colors.white.withOpacity(0.7), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
