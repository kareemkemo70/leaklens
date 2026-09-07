// lib/screens/user/user_home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/prediction_model.dart';
import 'package:alarm/alarm.dart';
import 'report_issue_screen.dart';
import 'my_reports_screen.dart';
import '../role_selection_screen.dart';
import 'outages_screen.dart';
import '../../main.dart';
import '../../utils/nav.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart' hide NotificationSettings;


class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen>
    with WidgetsBindingObserver {
  String _name = 'User';
  String _zone = '';
  int? _userId;
  List<AlertModel> _alerts = [];
  List<String> _dismissedAlerts = [];
  final List<int> _alarmedOutages = [];
  int _activeOutages = 0;
  bool _loadingAlerts = true;
  // Zone Health Card state
  AlertModel? _latestZoneAlert;
  bool _loadingHealth = false;
  Timer? _refreshTimer;
  StreamSubscription<AlarmSettings>? _alarmSubscription;
  StreamSubscription<Map<String, dynamic>>? _leakAlertSubscription;
  bool _isAlarmDialogShowing = false;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Register so notification tap handler can trigger this screen
    onNotificationTapShowAlarm = _checkRingingAlarms;
    _initAll();
    // Listen for foreground FCM leak alerts — show an in-app banner
    _leakAlertSubscription = leakAlertStreamController.stream.listen(_showInAppLeakBanner);
  }

  // ── Lifecycle: fires when app comes back to FOREGROUND ─────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App just came to foreground (e.g. user tapped notification)
      // Immediately check if an alarm is ringing and show the red screen
      _checkRingingAlarms();
    }
  }

  /// Checks if any outage alarm is currently ringing and shows the red screen.
  /// This is the single source of truth for showing the alarm dialog.
  Future<void> _checkRingingAlarms() async {
    if (!mounted || _isAlarmDialogShowing) return;
    final alarms = await Alarm.getAlarms();
    for (final alarm in alarms) {
      if (await Alarm.isRinging(alarm.id)) {
        _handleAlarmRing(alarm);
        return;
      }
    }
  }


  Future<void> _initAll() async {
    // ── Permissions: exact alarms, overlay, battery optimisation ──────────────
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
    if (await Permission.systemAlertWindow.isDenied) {
      await Permission.systemAlertWindow.request();
    }
    // CRITICAL: ask Android to exclude us from battery optimisation.
    // Without this, Doze mode silently kills our AlarmManager schedules
    // after a few fires — which is exactly the "works twice then stops" bug.
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    // ⚠️ Check for ringing alarms FIRST — before any network calls — so
    // the red screen appears immediately when the user taps the notification.
    await _checkRingingAlarms();

    await _loadProfile();
    if (mounted) {
      _loadData(showLoading: true);
      // Auto-refresh every 30 seconds SILENTLY
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (mounted) _loadData(showLoading: false);
      });

      // Listen for alarms that fire while the app is OPEN/BACKGROUND
      _alarmSubscription = Alarm.ringStream.stream.listen(_handleAlarmRing);
    }
  }


  void _handleAlarmRing(AlarmSettings alarmSettings) {
    if (!mounted || _isAlarmDialogShowing) return;
    _isAlarmDialogShowing = true;
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) => Scaffold(
        backgroundColor: AppTheme.red.withOpacity(0.9),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 100, color: Colors.white),
              const SizedBox(height: 24),
              Text('ALARM', style: GoogleFonts.inter(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Text('Water Outage Scheduled!', style: GoogleFonts.inter(color: Colors.white, fontSize: 20)),
              const SizedBox(height: 8),
              Text(alarmSettings.notificationSettings.body ?? 'Please prepare accordingly.', style: GoogleFonts.inter(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 60),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.red,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                ),
                onPressed: () async {
                  await Alarm.stop(alarmSettings.id);
                  _isAlarmDialogShowing = false;
                  if (mounted) Navigator.pop(ctx);
                },
                child: Text('STOP ALARM', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
      ),
    );
  }

  void _loadData({bool showLoading = false}) {
    _loadAlerts(showLoading: showLoading);
    _loadOutages();
    if (_zone.isNotEmpty) _loadZoneHealth();
  }

  Future<void> _loadZoneHealth() async {
    if (mounted) setState(() => _loadingHealth = true);
    try {
      final alert = await ApiService().getLatestAlert(
        zone: _zone,
        since: DateTime.now().subtract(const Duration(hours: 24)),
      );
      if (mounted) setState(() => _latestZoneAlert = alert);
    } catch (_) {
      // Silent fail — health card just shows loading state
    } finally {
      if (mounted) setState(() => _loadingHealth = false);
    }
  }

  Future<void> _loadOutages() async {
    try {
      final list = await ApiService().getOutages(zone: _zone.isNotEmpty ? _zone : null);
      if (mounted && _activeOutages != list.length) {
        setState(() => _activeOutages = list.length);
      }

      final now = DateTime.now();
      for (var outage in list) {
        if (!_alarmedOutages.contains(outage.id)) {
          // 1. If the outage is in the future, schedule a native OS Alarm clock
          if (outage.startTime.isAfter(now)) {
            _alarmedOutages.add(outage.id);
            _persistAlarmedOutages();
            
            final alarmSettings = AlarmSettings(
              id: outage.id,
              dateTime: outage.startTime,
              assetAudioPath: 'assets/audio/alarm.mp3',
              loopAudio: true,
              vibrate: true,
              androidFullScreenIntent: true,
              androidStopAlarmOnTermination: false, // <<< CRITICAL: keeps alarm alive after app is killed
              warningNotificationOnKill: false, // no warning — alarm will still ring
              volumeSettings: const VolumeSettings.fixed(volume: 1.0), // max volume, no fade delay
              notificationSettings: const NotificationSettings(
                title: '⚠️ WATER OUTAGE ALARM',
                body: 'Water outage is now starting in your zone!',
              ),
            );
            // Path 1: alarm package — handles the sound + full-screen intent
            await Alarm.set(alarmSettings: alarmSettings);
            // Path 2: flutter_local_notifications zonedSchedule — fires via the OS
            // AlarmManager even if the app process is completely dead. This is the
            // reliable background path that was missing before.
            await scheduleAlarmNotification(
              outage.id,
              '⚠️ WATER OUTAGE ALARM',
              'Water outage is now starting in your zone: ${outage.title}',
              outage.startTime,
            );
          }
          // 2. If the outage JUST started and we missed scheduling it
          else if (now.isAfter(outage.startTime) && now.isBefore(outage.endTime)) {
            _alarmedOutages.add(outage.id);
            _persistAlarmedOutages();
            // Trigger immediate local full-screen intent alarm notification
            showLocalNotification(
              '⚠️ WATER OUTAGE STARTED',
              outage.title,
              isAlarm: true,
            );
            
            // Also show a massive visual dialog if the user is currently inside the app
            _handleAlarmRing(AlarmSettings(
              id: outage.id,
              dateTime: DateTime.now(),
              assetAudioPath: '',
              volumeSettings: const VolumeSettings.fixed(volume: 1.0),
              notificationSettings: NotificationSettings(
                title: '⚠️ WATER OUTAGE STARTED',
                body: outage.title,
              ),
            ));
          }
        }
      }
    } catch (_) {
      // Ignore errors for the badge
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    onNotificationTapShowAlarm = null; // unregister callback
    _refreshTimer?.cancel();
    _alarmSubscription?.cancel();
    _leakAlertSubscription?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      // Load persisted alarmed outage IDs so we don't re-trigger after re-login
      final savedIds = prefs.getStringList('alarmed_outage_ids') ?? [];
      _alarmedOutages.clear();
      _alarmedOutages.addAll(savedIds.map((s) => int.tryParse(s) ?? 0).where((id) => id > 0));

      setState(() {
        _name = prefs.getString('name') ?? 'User';
        _zone = prefs.getString('user_zone') ?? '';
        _userId = prefs.getInt('user_id');
        _dismissedAlerts = prefs.getStringList('dismissed_alerts') ?? [];
      });
    }
  }

  Future<void> _loadAlerts({bool showLoading = false}) async {
    if (showLoading && mounted) setState(() => _loadingAlerts = true);
    try {
      final alerts = await ApiService().getAlerts(
        limit: 10,
        zone: _zone.isNotEmpty ? _zone : null,
      );
      if (mounted) {
        setState(() {
          _alerts = alerts.where((a) => !_dismissedAlerts.contains(a.id.toString())).toList();
          _loadingAlerts = false;
        });
      }
    } catch (e) {
      debugPrint('🚨 API ERROR: $e');
      if (mounted) {
        setState(() { _alerts = []; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(label: 'Retry', textColor: Colors.white, onPressed: () => _loadAlerts(showLoading: true)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingAlerts = false);
    }
  }

  /// Persist alarmed outage IDs so re-login doesn't re-trigger old alarms.
  Future<void> _persistAlarmedOutages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'alarmed_outage_ids',
      _alarmedOutages.map((id) => id.toString()).toList(),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    // Unsubscribe from zone FCM topic before clearing prefs
    // (prevents the device from receiving notifications for the old zone
    //  after a different user logs in on the same device)
    final oldZone = prefs.getString('user_zone') ?? '';
    if (oldZone.isNotEmpty) {
      final oldTopic = oldZone.replaceAll(' ', '_');
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic(oldTopic);
        debugPrint('Unsubscribed from FCM topic: $oldTopic');
      } catch (e) {
        debugPrint('Failed to unsubscribe from topic $oldTopic: $e');
      }
    }
    // Preserve settings that should survive logout
    final savedBaseUrl = prefs.getString('custom_base_url');
    final savedAlarmedIds = prefs.getStringList('alarmed_outage_ids');
    await prefs.clear();
    // Restore preserved settings
    if (savedBaseUrl != null) {
      await prefs.setString('custom_base_url', savedBaseUrl);
    }
    if (savedAlarmedIds != null) {
      await prefs.setStringList('alarmed_outage_ids', savedAlarmedIds);
    }
    if (!mounted) return;
    pushAndRemoveAllFade(context, const RoleSelectionScreen());
  }

  // ── Water saving tips ────────────────────────────────────────────
  final _tips = [
    ('🚿', 'Shorter Showers', 'Cut 2 min from your shower to save up to 30L.'),
    ('🪣', 'Reuse Rinse Water', 'Collect pasta / vegetable rinse water for plants.'),
    ('🔧', 'Fix Dripping Taps', 'A dripping tap wastes 15L per day — report it!'),
    ('🕛', 'Water at Night', 'Water plants at dusk to reduce evaporation by 50%.'),
    ('🚰', 'Full Loads Only', 'Run dishwashers and washers with full loads only.'),
  ];

  // ── In-App Leak Banner ────────────────────────────────────────────────
  /// Called when a foreground FCM anomaly_alert message arrives.
  /// Shows a prominent SnackBar so the user sees the alert while using the app.
  void _showInAppLeakBanner(Map<String, dynamic> data) {
    if (!mounted) return;

    final zone       = data['zone'] ?? 'Unknown Zone';
    final rawConf    = double.tryParse(data['confidence'] ?? '') ?? 0.0;
    final confPct    = (rawConf * 100).toStringAsFixed(1);
    final topSensors = data['top_sensors'] ?? '';

    // Only show the banner if the alert is for the user's own zone
    // (or if we can't determine the zone, show it anyway as a safety fallback)
    if (_zone.isNotEmpty && zone != _zone) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: const Duration(seconds: 8),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7B0000), Color(0xFFD32F2F)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              const Text('🚨', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Leak Detected — $zone',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Confidence: $confPct%  |  Sensors: $topSensors',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Also refresh the alerts list so the new alert appears immediately
    _loadAlerts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('WaterGuard', style: GoogleFonts.inter(
          color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            onPressed: _loadAlerts,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppTheme.textSecondary),
            onPressed: _logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.cyan,
        backgroundColor: AppTheme.bgCard,
        onRefresh: () async => _loadData(),
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Greeting ─────────────────────────────────────────
              FadeInDown(
                duration: const Duration(milliseconds: 300),
                child: GlassCard(
                  borderColor: AppTheme.borderGlow,
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: AppTheme.cyanGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                            child: Text('👤', style: TextStyle(fontSize: 26))),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hello, $_name 👋',
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            )),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 12, color: AppTheme.cyan),
                              const SizedBox(width: 4),
                              Text(_zone.isNotEmpty ? _zone : 'Detecting...',
                                style: GoogleFonts.inter(
                                    color: AppTheme.cyan, 
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              Text('· Stay safe',
                                style: GoogleFonts.inter(
                                    color: AppTheme.textSecondary, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Zone Health Card ──────────────────────────────────
              FadeInUp(
                duration: const Duration(milliseconds: 300),
                delay: const Duration(milliseconds: 60),
                child: _ZoneHealthCard(
                  zone: _zone,
                  alert: _latestZoneAlert,
                  loading: _loadingHealth,
                  onTap: () => _scrollToAlerts(),
                ),
              ),
              const SizedBox(height: 24),

              // ── Quick Actions ────────────────────────────────────
              FadeInUp(
                duration: const Duration(milliseconds: 300),
                delay: const Duration(milliseconds: 80),
                child: const SectionTitle('Quick Actions'),
              ),
              const SizedBox(height: 14),

              FadeInUp(
                duration: const Duration(milliseconds: 300),
                delay: const Duration(milliseconds: 120),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionTile(
                        emoji: '📢',
                        label: 'Report\nIssue',
                        color: AppTheme.orange,
                        onTap: () => pushFade(context, const ReportIssueScreen()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: _ActionTile(
                              emoji: '📅',
                              label: 'Water\nOutages',
                              color: AppTheme.cyan,
                              onTap: () => pushFade(context, OutagesScreen(userZone: _zone)),
                            ),
                          ),
                          if (_activeOutages > 0)
                            Positioned(
                              top: -4,
                              right: -4,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: AppTheme.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Text('$_activeOutages',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionTile(
                        emoji: '💡',
                        label: 'Water\nTips',
                        color: AppTheme.green,
                        onTap: () => _scrollToTips(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionTile(
                        emoji: '📋',
                        label: 'My\nReports',
                        color: AppTheme.purple,
                        onTap: () {
                          if (_userId != null) {
                            pushFade(context, MyReportsScreen(userId: _userId!));
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Please log in again to view reports.',
                                  style: GoogleFonts.inter()),
                                backgroundColor: AppTheme.red,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── Alerts ───────────────────────────────────────────
              FadeInUp(
                delay: const Duration(milliseconds: 200),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SectionTitle('Recent Alerts'),
                    if (_alerts.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                              color: AppTheme.red.withOpacity(0.3)),
                        ),
                        child: Text('${_alerts.length} active',
                          style: GoogleFonts.inter(
                            color: AppTheme.red,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          )),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              FadeInUp(
                delay: const Duration(milliseconds: 250),
                child: _loadingAlerts
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(color: AppTheme.cyan),
                        ))
                    : _alerts.isEmpty
                        ? _EmptyAlerts()
                        : Column(
                            children: _alerts.asMap().entries.map((e) =>
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _AlertCard(
                                  alert: e.value,
                                  onDelete: () async {
                                    final prefs = await SharedPreferences.getInstance();
                                    _dismissedAlerts.add(e.value.id.toString());
                                    await prefs.setStringList('dismissed_alerts', _dismissedAlerts);
                                    setState(() {
                                      _alerts.removeAt(e.key);
                                    });
                                  },
                                ),
                              ),
                            ).toList(),
                          ),
              ),
              const SizedBox(height: 28),

              // ── Water Tips ────────────────────────────────────────
              FadeInUp(
                delay: const Duration(milliseconds: 300),
                child: const SectionTitle('💡 Water Saving Tips'),
              ),
              const SizedBox(height: 14),

              ..._tips.asMap().entries.map((e) =>
                FadeInLeft(
                  delay: Duration(milliseconds: 350 + e.key * 60),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TipCard(
                      emoji: e.value.$1,
                      title: e.value.$2,
                      body: e.value.$3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _scrollToTips() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _scrollToAlerts() {
    if (_scrollCtrl.hasClients) {
      // Scroll to roughly where alerts section is
      _scrollCtrl.animateTo(
        300,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }
}

class _ActionTile extends StatelessWidget {
  final String emoji, label;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.emoji,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.3,
              )),
          ],
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final AlertModel alert;
  final VoidCallback onDelete;
  const _AlertCard({required this.alert, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final mins = DateTime.now().difference(alert.detectedAt).inMinutes;
    final timeAgo = mins < 60
        ? '${mins}m ago'
        : '${(mins / 60).floor()}h ago';
    final isBroadcast = alert.message != null && alert.message!.isNotEmpty;
    final accentColor = isBroadcast ? AppTheme.orange : AppTheme.red;

    return GlassCard(
      borderColor: accentColor.withOpacity(0.3),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(isBroadcast ? '📢' : '🚨',
                  style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        isBroadcast
                            ? 'Broadcast Alert — ${alert.zone}'
                            : 'Leak Detected — ${alert.zone}',
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(timeAgo,
                      style: GoogleFonts.inter(
                          color: AppTheme.textMuted, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isBroadcast
                      ? alert.message!
                      : 'Sensors: ${alert.topSensors.join(", ")} · '
                        'Confidence: ${(alert.confidence * 100).round()}%',
                  style: GoogleFonts.inter(
                      color: isBroadcast ? AppTheme.orange : AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: isBroadcast ? FontWeight.w500 : FontWeight.normal),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppTheme.textMuted, size: 20),
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _EmptyAlerts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        children: [
          const Text('✅', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          Text('No Active Alerts',
            style: GoogleFonts.inter(
              color: AppTheme.green,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            )),
          const SizedBox(height: 4),
          Text('Your water network is operating normally.',
            style: GoogleFonts.inter(
                color: AppTheme.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  final String emoji, title, body;
  const _TipCard({required this.emoji, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.green.withOpacity(0.2)),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  )),
                const SizedBox(height: 4),
                Text(body,
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Zone Health Card
// ─────────────────────────────────────────────────────────────────────────────

class _ZoneHealthCard extends StatelessWidget {
  final String zone;
  final AlertModel? alert;
  final bool loading;
  final VoidCallback onTap;

  const _ZoneHealthCard({
    required this.zone,
    required this.alert,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (zone.isEmpty) return const SizedBox.shrink();

    Color borderColor;
    Color accentColor;
    String statusEmoji;
    String statusLabel;
    String subtitle;

    if (loading) {
      borderColor = AppTheme.borderGlow;
      accentColor = AppTheme.cyan;
      statusEmoji = '🔄';
      statusLabel = 'Checking...';
      subtitle = 'Fetching latest zone status';
    } else if (alert == null) {
      borderColor = AppTheme.green.withOpacity(0.4);
      accentColor = AppTheme.green;
      statusEmoji = '✅';
      statusLabel = 'Normal';
      subtitle = 'No anomalies in the last 24 hours';
    } else if (alert!.confidence >= 0.75) {
      borderColor = AppTheme.red.withOpacity(0.5);
      accentColor = AppTheme.red;
      statusEmoji = '🚨';
      statusLabel = 'Leak Detected';
      subtitle = 'Confidence: ${(alert!.confidence * 100).round()}% · '
          'Sensors: ${alert!.topSensors.take(2).join(", ")}';
    } else {
      borderColor = AppTheme.orange.withOpacity(0.4);
      accentColor = AppTheme.orange;
      statusEmoji = '⚠️';
      statusLabel = 'Warning';
      subtitle = 'Confidence: ${(alert!.confidence * 100).round()}% · '
          'Sensors: ${alert!.topSensors.take(2).join(", ")}';
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accentColor.withOpacity(0.08), AppTheme.bgCard],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: accentColor.withOpacity(0.4)),
              ),
              child: Center(
                child: loading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: AppTheme.cyan, strokeWidth: 2))
                    : Text(statusEmoji,
                        style: const TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('ZONE HEALTH',
                          style: GoogleFonts.inter(
                              color: AppTheme.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4)),
                      const SizedBox(width: 6),
                      Text('· $zone',
                          style: GoogleFonts.inter(
                              color: AppTheme.textMuted, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(statusLabel,
                      style: GoogleFonts.inter(
                          color: accentColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          height: 1.3)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: accentColor.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }
}
