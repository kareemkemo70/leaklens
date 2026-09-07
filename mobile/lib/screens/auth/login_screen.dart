// lib/screens/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../user/user_home_screen.dart';
import '../engineer/engineer_dashboard_screen.dart';
import 'register_screen.dart';
import '../../utils/nav.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class LoginScreen extends StatefulWidget {
  final String role; // 'user' | 'engineer'
  const LoginScreen({super.key, required this.role});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _idCtrl    = TextEditingController();
  final _passCtrl  = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  String? _error;

  bool get _isUser => widget.role == 'user';

  @override
  void dispose() {
    _emailCtrl.dispose();
    _idCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      final api = ApiService();
      Map<String, dynamic> result;

      if (_isUser) {
        result = await api.loginUser(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text.trim(),
        );
      } else {
        result = await api.loginEngineer(
          engineerId: _idCtrl.text.trim(),
          password: _passCtrl.text.trim(),
        );
      }

      // Persist session
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', result['access_token']);
      await prefs.setString('role',         result['role']);
      await prefs.setString('name',         result['name']);
      await prefs.setInt('user_id',         result['user_id']);
      if (result['zone'] != null) {
        final zoneString = result['zone'] as String;
        await prefs.setString('user_zone', zoneString);
        
        // Unsubscribe from ALL zone topics first to prevent cross-zone alerts
        // (e.g. if a Zone 4 user previously logged in as Zone 2 on this device)
        final allZones = ['Zone_1', 'Zone_2', 'Zone_3', 'Zone_4', 'Zone_5'];
        for (final z in allZones) {
          try { await FirebaseMessaging.instance.unsubscribeFromTopic(z); } catch (_) {}
        }
        // Also unsubscribe from engineers topic in case they previously logged in as engineer
        try { await FirebaseMessaging.instance.unsubscribeFromTopic('engineers'); } catch (_) {}
        
        // Now subscribe only to this user's zone
        final topic = zoneString.replaceAll(' ', '_');
        try {
          await FirebaseMessaging.instance.subscribeToTopic(topic);
        } catch (e) {
          debugPrint('Failed to subscribe to topic $topic: $e');
        }
      } else if (!_isUser) {
        // Engineers: unsubscribe from all zone topics, subscribe to engineers only
        final allZones = ['Zone_1', 'Zone_2', 'Zone_3', 'Zone_4', 'Zone_5'];
        for (final z in allZones) {
          try { await FirebaseMessaging.instance.unsubscribeFromTopic(z); } catch (_) {}
        }
        try {
          await FirebaseMessaging.instance.subscribeToTopic('engineers');
        } catch (e) {
          debugPrint('Failed to subscribe engineer to global topic: $e');
        }
      }

      if (!mounted) return;
      pushAndRemoveAllFade(
        context,
        _isUser ? const UserHomeScreen() : const EngineerDashboardScreen(),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Unexpected error. Is the backend running?');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showServerConfig() async {
    // Extract just the IP if a custom URL is already set
    String currentIp = '';
    if (ApiService.customBaseUrl != null) {
      currentIp = ApiService.customBaseUrl!.replaceAll('http://', '').replaceAll(':8000', '');
    }

    final ctrl = TextEditingController(text: currentIp);
    
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text('Server Configuration', style: GoogleFonts.inter(color: AppTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          style: GoogleFonts.inter(color: AppTheme.textPrimary),
          keyboardType: TextInputType.number, // Better keyboard for IPs
          decoration: InputDecoration(
            hintText: 'e.g. 192.168.100.8',
            labelText: 'Wi-Fi IPv4 Address',
            labelStyle: GoogleFonts.inter(color: AppTheme.textMuted),
            hintStyle: GoogleFonts.inter(color: AppTheme.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final ip = ctrl.text.trim();
              if (ip.isNotEmpty) {
                // Automatically format the string to the correct URL format
                final url = 'http://$ip:8000';
                await prefs.setString('custom_base_url', url);
                ApiService.customBaseUrl = url;
              } else {
                await prefs.remove('custom_base_url');
                ApiService.customBaseUrl = null;
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: Text('Save', style: GoogleFonts.inter(color: AppTheme.cyan, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF050B16), AppTheme.bgPrimary],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top Bar ───────────────────────────────────────────────
                FadeIn(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                                         color: AppTheme.textPrimary),
                      ),
                      IconButton(
                        onPressed: _showServerConfig,
                        icon: const Icon(Icons.settings_outlined,
                                         color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Header ─────────────────────────────────────────────
                FadeInDown(
                  duration: const Duration(milliseconds: 250),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isUser ? '👤' : '👷',
                        style: const TextStyle(fontSize: 40),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isUser ? 'Welcome Back' : 'Engineer Login',
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isUser
                            ? 'Sign in with your email or phone'
                            : 'Sign in with your engineer ID',
                        style: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // ── Form ───────────────────────────────────────────────
                FadeInUp(
                  duration: const Duration(milliseconds: 250),
                  delay: const Duration(milliseconds: 100),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // Email / Engineer ID
                        if (_isUser)
                          _field(
                            controller: _emailCtrl,
                            label: 'Email Address',
                            hint: 'you@example.com',
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'Enter your email' : null,
                          )
                        else
                          _field(
                            controller: _idCtrl,
                            label: 'Engineer ID',
                            hint: 'ENG-001',
                            icon: Icons.badge_outlined,
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'Enter your ID' : null,
                          ),
                        const SizedBox(height: 16),

                        // Password
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscure,
                          style: GoogleFonts.inter(color: AppTheme.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: '••••••••',
                            prefixIcon: const Icon(Icons.lock_outline_rounded,
                                                   color: AppTheme.textMuted),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure ? Icons.visibility_off_outlined
                                         : Icons.visibility_outlined,
                                color: AppTheme.textMuted,
                              ),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) =>
                              (v == null || v.length < 6)
                                  ? 'Password must be 6+ characters'
                                  : null,
                        ),

                        // Forgot Password
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => _showForgotPassword(context),
                            child: Text(
                              'Forgot Password?',
                              style: GoogleFonts.inter(
                                color: AppTheme.cyan,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),

                        // Error
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.red.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: AppTheme.red, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(_error!,
                                    style: GoogleFonts.inter(
                                        color: AppTheme.red, fontSize: 13)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        const SizedBox(height: 8),

                        // Login button
                        _GradientButton(
                          label: 'Sign In',
                          loading: _loading,
                          gradient: _isUser ? AppTheme.cyanGradient : const LinearGradient(
                            colors: [Color(0xFF4A0080), Color(0xFF9C27B0)],
                          ),
                          onPressed: _login,
                        ),

                        const SizedBox(height: 24),

                        // Register link
                        if (_isUser)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("Don't have an account? ",
                                style: GoogleFonts.inter(
                                    color: AppTheme.textSecondary, fontSize: 14)),
                              GestureDetector(
                                onTap: () => pushFade(context, const RegisterScreen()),
                                child: Text('Sign Up',
                                  style: GoogleFonts.inter(
                                    color: AppTheme.cyan,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  )),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: GoogleFonts.inter(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.textMuted),
      ),
      validator: validator,
    );
  }

  void _showForgotPassword(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reset Password',
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          'Please contact your system administrator or use the registered email to reset your password.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK', style: GoogleFonts.inter(color: AppTheme.cyan)),
          ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatefulWidget {
  final String label;
  final bool loading;
  final LinearGradient gradient;
  final VoidCallback onPressed;

  const _GradientButton({
    required this.label,
    required this.loading,
    required this.gradient,
    required this.onPressed,
  });

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp:   (_) { setState(() => _pressed = false); widget.onPressed(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: widget.gradient.colors.last.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: widget.loading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : Text(
                    widget.label,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
