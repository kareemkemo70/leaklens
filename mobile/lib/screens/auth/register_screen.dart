// lib/screens/auth/register_screen.dart
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../user/user_home_screen.dart';
import '../../utils/nav.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _nameCtrl   = TextEditingController();
  final _addrCtrl   = TextEditingController();
  final _phoneCtrl  = TextEditingController();
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  final _confirmCtrl = TextEditingController();

  String _selectedZone = 'Zone 1';
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  static const _zones = ['Zone 1', 'Zone 2', 'Zone 3', 'Zone 4', 'Zone 5'];

  @override
  void dispose() {
    for (final c in [_nameCtrl,_addrCtrl,_phoneCtrl,_emailCtrl,_passCtrl,_confirmCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      final result = await ApiService().registerUser(
        name: _nameCtrl.text.trim(),
        address: _addrCtrl.text.trim(),
        zone: _selectedZone,
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', result['access_token']);
      await prefs.setString('role', 'user');
      await prefs.setString('name', result['name']);
      await prefs.setInt('user_id', result['user_id']);
      if (result['zone'] != null) {
        final zoneString = result['zone'] as String;
        await prefs.setString('user_zone', zoneString);
        
        // Unsubscribe from ALL zone topics first to prevent cross-zone alerts
        final allZones = ['Zone_1', 'Zone_2', 'Zone_3', 'Zone_4', 'Zone_5'];
        for (final z in allZones) {
          try { await FirebaseMessaging.instance.unsubscribeFromTopic(z); } catch (_) {}
        }
        try { await FirebaseMessaging.instance.unsubscribeFromTopic('engineers'); } catch (_) {}
        
        // Now subscribe only to this user's zone
        final topic = zoneString.replaceAll(' ', '_');
        try {
          await FirebaseMessaging.instance.subscribeToTopic(topic);
        } catch (e) {
          debugPrint('Failed to subscribe to topic $topic: $e');
        }
      }

      if (!mounted) return;
      pushAndRemoveAllFade(context, const UserHomeScreen());
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Registration failed. Check your connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                FadeIn(
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                                     color: AppTheme.textPrimary),
                  ),
                ),
                const SizedBox(height: 16),

                FadeInDown(
                  duration: const Duration(milliseconds: 250),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📝', style: TextStyle(fontSize: 36)),
                      const SizedBox(height: 12),
                      Text('Create Account',
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        )),
                      const SizedBox(height: 6),
                      Text('Fill in your details to get started',
                        style: GoogleFonts.inter(
                            color: AppTheme.textSecondary, fontSize: 14)),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                FadeInUp(
                  duration: const Duration(milliseconds: 250),
                  delay: const Duration(milliseconds: 100),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _field(_nameCtrl,  'Full Name',       'Ahmed Mohamed',   Icons.person_outline),
                        const SizedBox(height: 14),
                        _field(_addrCtrl,  'Address',         '123 Nile Street', Icons.home_outlined),
                        const SizedBox(height: 14),

                        // Zone dropdown
                        DropdownButtonFormField<String>(
                          value: _selectedZone,
                          dropdownColor: AppTheme.bgCard,
                          style: GoogleFonts.inter(color: AppTheme.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Select Your Zone',
                            prefixIcon: Icon(Icons.location_on_outlined,
                                            color: AppTheme.textMuted),
                          ),
                          items: _zones.map((z) => DropdownMenuItem<String>(
                            value: z,
                            child: Text(z),
                          )).toList(),
                          onChanged: (v) => setState(() => _selectedZone = v!),
                        ),
                        const SizedBox(height: 14),

                        _field(_phoneCtrl, 'Phone Number',    '+20 10 0000 0000', Icons.phone_outlined,
                               type: TextInputType.phone),
                        const SizedBox(height: 14),
                        _field(_emailCtrl, 'Email Address',   'you@example.com', Icons.email_outlined,
                               type: TextInputType.emailAddress,
                               validator: (v) => (v == null || !v.contains('@'))
                                   ? 'Enter a valid email' : null),
                        const SizedBox(height: 14),

                        // Password
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscure,
                          style: GoogleFonts.inter(color: AppTheme.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: 'Min. 6 characters',
                            prefixIcon: const Icon(Icons.lock_outline,
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
                          validator: (v) => (v == null || v.length < 6)
                              ? 'Minimum 6 characters' : null,
                        ),
                        const SizedBox(height: 14),

                        // Confirm password
                        TextFormField(
                          controller: _confirmCtrl,
                          obscureText: _obscure,
                          style: GoogleFonts.inter(color: AppTheme.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Confirm Password',
                            hintText: 'Re-enter password',
                            prefixIcon: Icon(Icons.lock_outline,
                                           color: AppTheme.textMuted),
                          ),
                          validator: (v) => v != _passCtrl.text
                              ? 'Passwords do not match' : null,
                        ),

                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.red.withOpacity(0.3)),
                            ),
                            child: Text(_error!,
                              style: GoogleFonts.inter(
                                  color: AppTheme.red, fontSize: 13)),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Register button
                        GestureDetector(
                          onTap: _loading ? null : _register,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: double.infinity,
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: AppTheme.cyanGradient,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.cyan.withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Center(
                              child: _loading
                                  ? const SizedBox(
                                      width: 22, height: 22,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2.5))
                                  : Text('Create Account',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      )),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
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

  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint,
    IconData icon, {
    TextInputType type = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      style: GoogleFonts.inter(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.textMuted),
      ),
      validator: validator ??
          (v) => (v == null || v.isEmpty) ? 'This field is required' : null,
    );
  }
}
