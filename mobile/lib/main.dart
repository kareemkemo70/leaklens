import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:alarm/alarm.dart';
import 'dart:typed_data';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import 'theme/app_theme.dart';
import 'screens/role_selection_screen.dart';
import 'screens/user/user_home_screen.dart';
import 'screens/engineer/engineer_dashboard_screen.dart';
import 'services/api_service.dart';

// ── Global Navigator Key — lets us navigate from notification callbacks ────────
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ── In-App Leak Alert Stream ─────────────────────────────────────────────────
// When the app is in the FOREGROUND and an anomaly_alert FCM arrives, we emit
// the notification data here. UserHomeScreen subscribes to show an in-app banner.
final StreamController<Map<String, dynamic>> leakAlertStreamController =
    StreamController<Map<String, dynamic>>.broadcast();


// ── Notification Channel (must match AndroidManifest.xml) ───────────────────
const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'water_leak_alerts',
  'Water Leakage Alerts',
  description: 'Real-time alerts for water network anomalies',
  importance: Importance.max,
  playSound: true,
);

final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// ── Firebase Background Handler ──────────────────────────────────────────────
// NOTE: This runs in a SEPARATE background isolate when app is CLOSED.
// It must only use top-level functions and re-initialise all plugins itself.
//
// CRITICAL DESIGN: The backend sends DATA-ONLY FCM messages (no `notification`
// field). On Android, data-only messages ALWAYS trigger this handler, even when
// the app is killed. Messages with a `notification` field are intercepted by
// Android and shown in the system tray WITHOUT calling this handler.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final msgType = message.data['type'] ?? '';
  debugPrint('📩 Background FCM received — type=$msgType, data=${message.data}');

  switch (msgType) {
    case 'outage_starting':
      // ⏰ THE OUTAGE IS STARTING NOW — show alarm immediately
      await _showImmediateAlarmNotification(message.data);
      break;

    case 'outage_scheduled':
      // 📅 Outage was just created — show confirmation + schedule local backup
      await _showOutageScheduledNotification(message.data);
      await _scheduleLocalAlarmBackup(message.data);
      break;

    default:
      // Regular anomaly alert
      final title = message.data['title'] ?? message.notification?.title ?? '⚠️ Water Leak Alert';
      final body  = message.data['body'] ?? message.notification?.body ?? 'An anomaly was detected.';
      await _ensureNotificationPluginReady();
      await _bgNotificationPlugin!.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title, body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'water_leak_alerts', 'Water Leakage Alerts',
            channelDescription: 'Real-time alerts for water network anomalies',
            importance: Importance.max,
            priority: Priority.max,
            icon: '@mipmap/launcher_icon',
          ),
        ),
      );
  }
}

// ── Background notification plugin (re-initialised for background isolates) ──
FlutterLocalNotificationsPlugin? _bgNotificationPlugin;

Future<void> _ensureNotificationPluginReady() async {
  if (_bgNotificationPlugin != null) return;
  _bgNotificationPlugin = FlutterLocalNotificationsPlugin();
  await _bgNotificationPlugin!.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/launcher_icon'),
    ),
  );
  await _bgNotificationPlugin!
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(const AndroidNotificationChannel(
        'water_leak_alerts', 'Water Leakage Alerts',
        description: 'Real-time alerts for water network anomalies',
        importance: Importance.max,
        playSound: true,
      ));
}

/// Shows an IMMEDIATE full-screen alarm notification — the primary delivery
/// path when the outage actually starts. This fires even if the phone is
/// locked and the app is killed.
Future<void> _showImmediateAlarmNotification(Map<String, dynamic> data) async {
  await _ensureNotificationPluginReady();

  final title = data['outage_title']?.toString() ?? 'Water Outage';
  final zone  = data['zone']?.toString() ?? '';
  final id    = int.tryParse(data['outage_id']?.toString() ?? '') ?? 
                DateTime.now().millisecondsSinceEpoch.remainder(100000);

  await _bgNotificationPlugin!.show(
    id,
    '⚠️ WATER OUTAGE STARTED',
    'Water outage is now starting${zone.isNotEmpty ? ' in $zone' : ''}: $title',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'water_leak_alerts', 'Water Leakage Alerts',
        channelDescription: 'Real-time alerts for water network anomalies',
        importance: Importance.max,
        priority: Priority.max,
        icon: '@mipmap/launcher_icon',
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        fullScreenIntent: true,
        enableVibration: true,
        playSound: true,
        ongoing: true,      // Stays in notification bar until dismissed
        autoCancel: false,   // User must interact to dismiss
        visibility: NotificationVisibility.public, // Show on lock screen
      ),
    ),
  );
  debugPrint('✅ Immediate alarm notification shown for outage: $title');
}

/// Shows a quiet confirmation notification when an outage is scheduled.
Future<void> _showOutageScheduledNotification(Map<String, dynamic> data) async {
  await _ensureNotificationPluginReady();

  final title = data['outage_title']?.toString() ?? 'Water Outage';
  final zone  = data['zone']?.toString() ?? '';
  final startStr = data['start_time']?.toString() ?? '';

  String timeDisplay = '';
  if (startStr.isNotEmpty) {
    final dt = DateTime.tryParse(startStr);
    if (dt != null) {
      timeDisplay = ' at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }

  await _bgNotificationPlugin!.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    '📅 Water Outage Scheduled — $zone',
    '$title$timeDisplay. You will be alerted when it starts.',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'water_leak_alerts', 'Water Leakage Alerts',
        channelDescription: 'Real-time alerts for water network anomalies',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/launcher_icon',
      ),
    ),
  );
  debugPrint('📅 Scheduled confirmation notification shown for: $title');
}

/// Pre-schedules a local alarm as a BACKUP in case the backend FCM #2 fails.
Future<void> _scheduleLocalAlarmBackup(Map<String, dynamic> data) async {
  try {
    final outageId = int.tryParse(data['outage_id']?.toString() ?? '') ?? 0;
    if (outageId == 0) return;

    final title = data['outage_title']?.toString() ?? 'Water Outage';
    final startTimeStr = data['start_time']?.toString() ?? '';
    if (startTimeStr.isEmpty) return;

    final startTime = DateTime.tryParse(startTimeStr);
    if (startTime == null || startTime.isBefore(DateTime.now())) return;

    // Timezone
    tz.initializeTimeZones();
    try {
      final currentTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(currentTz.identifier));
    } catch (_) {}

    await _ensureNotificationPluginReady();

    await _bgNotificationPlugin!.zonedSchedule(
      outageId,
      '⚠️ WATER OUTAGE ALARM',
      'Water outage is now starting: $title',
      tz.TZDateTime.from(startTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'water_leak_alerts', 'Water Leakage Alerts',
          channelDescription: 'Real-time alerts for water network anomalies',
          importance: Importance.max,
          priority: Priority.max,
          icon: '@mipmap/launcher_icon',
          category: AndroidNotificationCategory.alarm,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          fullScreenIntent: true,
          enableVibration: true,
          playSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    debugPrint('✅ Backup local alarm scheduled for: $startTime');
  } catch (e) {
    debugPrint('⚠️ Backup local alarm scheduling failed (non-critical): $e');
  }
}

// ── Helper: Show Notification (for non-outage FCM messages) ──────────────────
Future<void> _showNotification(RemoteMessage message) async {
  final title = message.data['title'] ?? message.notification?.title ?? '⚠️ Water Leak Alert';
  final body  = message.data['body'] ?? message.notification?.body  ?? 'An anomaly was detected.';
  await showLocalNotification(title, body);
}

Future<void> showLocalNotification(String title, String body, {bool isAlarm = false}) async {
  await _flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.max,
        priority: Priority.max,
        icon: '@mipmap/launcher_icon',
        category: isAlarm ? AndroidNotificationCategory.alarm : null,
        audioAttributesUsage: isAlarm ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
        fullScreenIntent: isAlarm,
        enableVibration: true,
        playSound: true,
      ),
    ),
  );
}

Future<void> scheduleAlarmNotification(int id, String title, String body, DateTime scheduledTime) async {
  await _flutterLocalNotificationsPlugin.zonedSchedule(
    id,
    title,
    body,
    tz.TZDateTime.from(scheduledTime, tz.local),
    NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.max,
        priority: Priority.max,
        icon: '@mipmap/launcher_icon',
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        fullScreenIntent: true,
        enableVibration: true,
        playSound: true,
        additionalFlags: Int32List.fromList(<int>[4]), // FLAG_INSISTENT loops sound
      ),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
  );
}

// ── Payload stored when app was cold-started via a notification tap ───────────
String? _pendingNotificationPayload;

/// Global callback: UserHomeScreen registers this so notification taps
/// can trigger the red alarm screen even from outside the widget tree.
VoidCallback? onNotificationTapShowAlarm;

// ── Notification tap handler (foreground / background) ────────────────────────
void _handleNotificationTap(String? payload) {
  _pendingNotificationPayload = payload;
  // If UserHomeScreen is already mounted, ask it to check for ringing alarms
  if (onNotificationTapShowAlarm != null) {
    onNotificationTapShowAlarm!();
  } else {
    // App was killed or UserHomeScreen not yet built — navigate to home,
    // UserHomeScreen.initState will call _checkRingingAlarms on first build.
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/user-home', (route) => false);
  }
}

// Top-level function required by flutter_local_notifications for background taps
@pragma('vm:entry-point')
void _onBackgroundNotificationTap(NotificationResponse response) {
  _pendingNotificationPayload = response.payload;
}


// ── Main Entry ───────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase, Timezones & Alarm
  await Firebase.initializeApp();
  tz.initializeTimeZones();
  // ⚠️ CRITICAL: Set tz.local to the device's REAL timezone.
  // Without this, tz.local defaults to UTC and all scheduled alarms
  // fire at the wrong time on non-UTC devices (e.g. 3 hours late in Egypt).
  try {
    final currentTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(currentTimeZone.identifier));
  } catch (_) {
    // Fallback: keep UTC. Alarm may fire at wrong time but won't crash.
  }
  await Alarm.init();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 2. Create the notification channel on Android
  await _flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);

  // 3. Initialize local notifications plugin with notification-tap callback
  await _flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/launcher_icon'),
    ),
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      // User tapped a local notification while app was foreground/background
      _handleNotificationTap(response.payload);
    },
    onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationTap,
  );

  // 3b. Handle tap when app was KILLED and opened via notification
  final initialResponse =
      await _flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
  if (initialResponse?.didNotificationLaunchApp == true) {
    _pendingNotificationPayload =
        initialResponse!.notificationResponse?.payload;
  }

  // 4. Foreground FCM message listener
  FirebaseMessaging.onMessage.listen((message) {
    final msgType = message.data['type'] ?? '';
    switch (msgType) {
      case 'outage_starting':
        _showImmediateAlarmNotification(message.data);
        break;
      case 'outage_scheduled':
        _showOutageScheduledNotification(message.data);
        _scheduleLocalAlarmBackup(message.data);
        break;
      case 'anomaly_alert':
        // Push to the in-app stream so UserHomeScreen can show a banner/dialog.
        // The data is already fully populated (DATA-ONLY message from backend).
        leakAlertStreamController.add(message.data);
        // Also show a system notification (heads-up) for completeness.
        _showNotification(message);
        break;
      default:
        _showNotification(message);
    }
  });

  // 5. Setup UI orientation & status bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 6. Load auth & network state
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('access_token');
  final role  = prefs.getString('role');
  
  // Load saved custom URL, but validate it first — wipe if malformed.
  final savedUrl = prefs.getString('custom_base_url');
  if (savedUrl != null) {
    final uri = Uri.tryParse(savedUrl);
    if (uri == null || !uri.hasAuthority || uri.port == 0) {
      // Corrupted/invalid URL — remove it so the default kicks in.
      await prefs.remove('custom_base_url');
      ApiService.customBaseUrl = null;
    } else {
      ApiService.customBaseUrl = savedUrl;
    }
  }

  runApp(LeakLensApp(initialToken: token, initialRole: role));
}

class LeakLensApp extends StatefulWidget {
  final String? initialToken;
  final String? initialRole;

  const LeakLensApp({super.key, this.initialToken, this.initialRole});

  @override
  State<LeakLensApp> createState() => _LeakLensAppState();
}

class _LeakLensAppState extends State<LeakLensApp> {
  @override
  void initState() {
    super.initState();
    // Request permission after the first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissions());
  }

  Future<void> _requestPermissions() async {
    final status = await Permission.notification.status;
    if (status.isDenied) {
      // First time asking
      await Permission.notification.request();
    } else if (status.isPermanentlyDenied) {
      // User clicked "Don't ask again" — we must send them to Settings
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0D1B2A),
          title: const Text(
            '🔔 Enable Notifications',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'LeakLens needs notification permission to alert you about leaks even when the app is closed.\n\nPlease tap "Open Settings" and enable Notifications.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Later', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00D4FF)),
              onPressed: () {
                Navigator.pop(ctx);
                openAppSettings(); // Opens phone Settings → App → Notifications
              },
              child: const Text('Open Settings', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
    }
    // If granted, nothing to do — FCM works automatically
  }

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (widget.initialToken != null && widget.initialRole == 'user') {
      home = const UserHomeScreen();
    } else if (widget.initialToken != null && widget.initialRole == 'engineer') {
      home = const EngineerDashboardScreen();
    } else {
      home = const RoleSelectionScreen();
    }

    return MaterialApp(
      title: 'LeakLens',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: home,
      routes: {
        '/role':      (_) => const RoleSelectionScreen(),
        '/user-home': (_) => const UserHomeScreen(),
        '/engineer':  (_) => const EngineerDashboardScreen(),
      },
    );
  }
}
