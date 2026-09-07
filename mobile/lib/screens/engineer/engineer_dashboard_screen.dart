// lib/screens/engineer/engineer_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:animate_do/animate_do.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'package:alarm/alarm.dart';
import '../../main.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/prediction_model.dart';
import '../../utils/nav.dart';
import '../role_selection_screen.dart';
import 'analytics_screen.dart';
import 'engineer_map_screen.dart';

class EngineerDashboardScreen extends StatefulWidget {
  const EngineerDashboardScreen({super.key});

  @override
  State<EngineerDashboardScreen> createState() =>
      _EngineerDashboardScreenState();
}

class _EngineerDashboardScreenState extends State<EngineerDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  String _name = 'Engineer';
  List<AlertModel> _alerts = [];
  List<TimeseriesPoint> _timeseries = [];
  List<ReportModel> _userReports = [];
  bool _loadingTs = true;
  bool _loadingAlerts = true;
  bool _loadingReports = true;
  StreamSubscription<Map<String, dynamic>>? _leakAlertSubscription;
  StreamSubscription<AlarmSettings>? _alarmSubscription;
  bool _isAlarmDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _loadData();
    _leakAlertSubscription = leakAlertStreamController.stream.listen(_onNewLeakAlert);
  }

  void _onNewLeakAlert(Map<String, dynamic> data) async {
    if (!mounted) return;
    _loadData(); // Auto-refresh the dashboard
    
    final zone = data['zone'] ?? 'Unknown';
    final conf = data['confidence'] != null ? '${(double.parse(data['confidence']) * 100).round()}%' : '';
    
    // Trigger a loud alarm immediately for the engineer!
    final alarmSettings = AlarmSettings(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      dateTime: DateTime.now(),
      assetAudioPath: 'assets/audio/alarm.mp3',
      loopAudio: true,
      vibrate: true,
      volumeSettings: const VolumeSettings.fixed(volume: 1.0),
      notificationSettings: NotificationSettings(
        title: '🚨 CRITICAL LEAK DETECTED',
        body: 'Anomaly detected in $zone ($conf)',
      ),
    );
    
    await Alarm.set(alarmSettings: alarmSettings);
    _handleAlarmRing(alarmSettings);
  }

  void _handleAlarmRing(AlarmSettings alarmSettings) {
    if (!mounted || _isAlarmDialogShowing) return;
    _isAlarmDialogShowing = true;
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) => Scaffold(
        backgroundColor: AppTheme.red.withOpacity(0.95),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 120, color: Colors.white),
              const SizedBox(height: 30),
              Text('LEAK ALARM', style: GoogleFonts.inter(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 16),
              Text(alarmSettings.notificationSettings.body ?? 'Anomaly detected.', textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
              const SizedBox(height: 60),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.red,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 10,
                ),
                onPressed: () async {
                  await Alarm.stop(alarmSettings.id);
                  _isAlarmDialogShowing = false;
                  if (mounted) Navigator.pop(ctx);
                },
                child: Text('ACKNOWLEDGE ALARM', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() { 
    _leakAlertSubscription?.cancel();
    _alarmSubscription?.cancel();
    _tabs.dispose(); 
    super.dispose(); 
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _name = prefs.getString('name') ?? 'Engineer');
    _loadTimeseries();
    _loadAlerts();
    _loadReports();
  }

  Future<void> _loadTimeseries() async {
    setState(() => _loadingTs = true);
    try {
      final ts = await ApiService().getTimeseries(hours: 24);
      if (mounted) setState(() => _timeseries = ts);
    } catch (_) {
      if (mounted) setState(() => _timeseries = _demoTs());
    } finally {
      if (mounted) setState(() => _loadingTs = false);
    }
  }

  Future<void> _loadAlerts() async {
    setState(() => _loadingAlerts = true);
    try {
      final a = await ApiService().getAlerts(limit: 20);
      if (mounted) setState(() => _alerts = a);
    } catch (e, stack) {
      debugPrint('Error loading alerts: $e\n$stack');
      if (mounted) setState(() => _alerts = _demoAlerts());
    } finally {
      if (mounted) setState(() => _loadingAlerts = false);
    }
  }

  Future<void> _loadReports() async {
    setState(() => _loadingReports = true);
    try {
      final r = await ApiService().getReports(limit: 50);
      if (mounted) setState(() => _userReports = r);
    } catch (_) {
      // Just keep empty if fail
      if (mounted) setState(() => _userReports = []);
    } finally {
      if (mounted) setState(() => _loadingReports = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(10),
          child: Text('💧', style: TextStyle(fontSize: 24)),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Engineer Panel',
              style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 17)),
            Text('Welcome, $_name',
              style: GoogleFonts.inter(
                  color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined, color: AppTheme.textSecondary),
            tooltip: 'Zone Map',
            onPressed: () => pushFade(context, const EngineerMapScreen()),
          ),
          IconButton(
            icon: const Icon(Icons.analytics_outlined,
                             color: AppTheme.textSecondary),
            tooltip: 'Analytics',
            onPressed: () => pushFade(context, const AnalyticsScreen()),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                             color: AppTheme.textSecondary),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded,
                             color: AppTheme.textSecondary),
            onPressed: _logout,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.center,
                  indicatorColor: AppTheme.cyan,
                  labelColor: AppTheme.cyan,
                  unselectedLabelColor: AppTheme.textSecondary,
                  labelStyle: GoogleFonts.inter(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  tabs: [
                    Tab(text: 'Overview'),
                    Tab(text: 'Charts'),
                    Tab(text: 'Model Alerts'),
                    Tab(text: 'Reports'),
                    Tab(text: 'Outages'),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 12.0),
                child: Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OverviewTab(
            alerts: _alerts,
            loading: _loadingAlerts,
            onRefresh: _loadData,
          ),
          _ChartsTab(timeseries: _timeseries, loading: _loadingTs),
          _AlertsTab(
            alerts: _alerts,
            loading: _loadingAlerts,
            onRefresh: _loadAlerts,
          ),
          _ReportsTab(
            reports: _userReports,
            loading: _loadingReports,
            onRefresh: _loadReports,
          ),
          const _OutagesTab(),
        ],
      ),
    );
  }

  // ── Demo data ──────────────────────────────────────────────────
  List<TimeseriesPoint> _demoTs() {
    final now = DateTime.now();
    final pts = <TimeseriesPoint>[];
    double p = 5.5;
    for (int i = 120; i >= 0; i--) {
      final t = now.subtract(Duration(minutes: i * 12));
      if (i > 75 && i < 90) {
        p -= 0.06;
      } else {
        p += (i % 5 == 0 ? 0.05 : -0.02);
        p = p.clamp(3.5, 7.0);
      }
      pts.add(TimeseriesPoint(
        timestamp: t.toIso8601String(),
        pressure: double.parse(p.toStringAsFixed(2)),
        flow: double.parse((p * 0.5).toStringAsFixed(2)),
        isAnomaly: (i > 75 && i < 90 && p < 4.8) ? 1 : 0,
        zone: 'Zone 2',
      ));
    }
    return pts;
  }

  List<AlertModel> _demoAlerts() => [
    AlertModel(id: 1, isAnomaly: true, confidence: 0.87, mse: 0.24,
      topSensors: ['n33', 'n28', 'n41'], zone: 'Zone 2',
      detectedAt: DateTime.now().subtract(const Duration(minutes: 12)),
      source: 'model'),
    AlertModel(id: 2, isAnomaly: true, confidence: 0.72, mse: 0.18,
      topSensors: ['n95', 'n102'], zone: 'Zone 4',
      detectedAt: DateTime.now().subtract(const Duration(hours: 2)),
      source: 'model'),
    AlertModel(id: 3, isAnomaly: true, confidence: 0.91, mse: 0.31,
      topSensors: ['n5', 'n12', 'n18'], zone: 'Zone 1',
      detectedAt: DateTime.now().subtract(const Duration(hours: 6)),
      source: 'model'),
  ];
}

// ════════════════════════════════════════════════════════════════
// Overview Tab
// ════════════════════════════════════════════════════════════════

class _OverviewTab extends StatelessWidget {
  final List<AlertModel> alerts;
  final bool loading;
  final VoidCallback onRefresh;
  const _OverviewTab({required this.alerts, required this.loading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final active = alerts.where((a) => a.isAnomaly).length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── KPI row ─────────────────────────────────────────────
          FadeInDown(
            child: Row(
              children: [
                Expanded(child: _KpiCard('🚨', 'Active\nAnomalies',
                    '$active', AppTheme.red)),
                const SizedBox(width: 12),
                Expanded(child: _KpiCard('📊', 'Total\nAlerts',
                    '${alerts.length}', AppTheme.orange)),
                const SizedBox(width: 12),
                Expanded(child: _KpiCard('🎯', 'Avg\nConfidence',
                    active > 0
                        ? '${(alerts.where((a) => a.isAnomaly).map((a) => a.confidence).reduce((a, b) => a + b) / active * 100).round()}%'
                        : 'N/A',
                    AppTheme.cyan)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Zone summary ─────────────────────────────────────────
          FadeInUp(
            delay: const Duration(milliseconds: 150),
            child: const SectionTitle('Zone Status'),
          ),
          const SizedBox(height: 14),

          FadeInUp(
            delay: const Duration(milliseconds: 200),
            child: _ZoneStatusGrid(alerts: alerts),
          ),
          const SizedBox(height: 24),

          // ── Latest alert ─────────────────────────────────────────
          FadeInUp(
            delay: const Duration(milliseconds: 250),
            child: const SectionTitle('Latest Detection'),
          ),
          const SizedBox(height: 12),

          if (loading)
            const Center(
                child: CircularProgressIndicator(color: AppTheme.cyan))
          else if (alerts.isNotEmpty)
            FadeInUp(
              delay: const Duration(milliseconds: 300),
              child: _DetailCard(alert: alerts.first),
            ),
          const SizedBox(height: 32),

          // ── Reset Data ───────────────────────────────────────────
          FadeInUp(
            delay: const Duration(milliseconds: 350),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.warning_amber_rounded, color: AppTheme.red),
                label: Text('Reset System Data', 
                  style: GoogleFonts.inter(color: AppTheme.red, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: AppTheme.red.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: AppTheme.red.withOpacity(0.05),
                ),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppTheme.bgCard,
                      title: Text('Reset All Data?', style: GoogleFonts.inter(color: AppTheme.textPrimary)),
                      content: Text('This will delete all anomalies, reports, and logs. User and Engineer accounts will remain intact. This action cannot be undone.',
                        style: GoogleFonts.inter(color: AppTheme.textSecondary)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textMuted)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text('Reset', style: GoogleFonts.inter(color: AppTheme.red, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    try {
                      await ApiService().resetData();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('System data wiped successfully.', style: GoogleFonts.inter()), backgroundColor: AppTheme.green),
                        );
                        onRefresh();
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to reset data: $e', style: GoogleFonts.inter()), backgroundColor: AppTheme.red),
                        );
                      }
                    }
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}


class _KpiCard extends StatelessWidget {
  final String emoji, label, value;
  final Color color;
  const _KpiCard(this.emoji, this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 10),
          Text(value,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            )),
          const SizedBox(height: 4),
          Text(label,
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 11,
              height: 1.4,
            )),
        ],
      ),
    );
  }
}

class _ZoneStatusGrid extends StatelessWidget {
  final List<AlertModel> alerts;
  const _ZoneStatusGrid({required this.alerts});

  @override
  Widget build(BuildContext context) {
    const zones = ['Zone 1', 'Zone 2', 'Zone 3', 'Zone 4', 'Zone 5'];
    return Wrap(
      spacing: 10, runSpacing: 10,
      children: zones.map((z) {
        final count = alerts.where((a) => a.zone == z && a.isAnomaly).length;
        final color = count > 0 ? AppTheme.red : AppTheme.green;
        return Container(
          width: (MediaQuery.of(context).size.width - 62) / 3,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(z,
                style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(count > 0 ? '$count alerts' : 'Normal',
                    style: GoogleFonts.inter(
                        color: color, fontSize: 11,
                        fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final AlertModel alert;
  const _DetailCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderColor: AppTheme.red.withOpacity(0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🚨', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Anomaly Detected',
                  style: GoogleFonts.inter(
                    color: AppTheme.red,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text('${(alert.confidence * 100).round()}% confidence',
                style: GoogleFonts.inter(
                    color: AppTheme.textMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          _row('Zone',        alert.zone),
          _row('Sensors',     alert.topSensors.join(', ')),
          _row('MSE',         alert.mse.toStringAsFixed(5)),
          _row('Source',      alert.source),
          _row('Detected',    _timeAgo(alert.detectedAt)),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(k,
            style: GoogleFonts.inter(
                color: AppTheme.textMuted, fontSize: 13)),
        ),
        Text(v,
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          )),
      ],
    ),
  );

  String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}

// ════════════════════════════════════════════════════════════════
// Charts Tab
// ════════════════════════════════════════════════════════════════

class _ChartsTab extends StatefulWidget {
  final List<TimeseriesPoint> timeseries;
  final bool loading;
  const _ChartsTab({required this.timeseries, required this.loading});

  @override
  State<_ChartsTab> createState() => _ChartsTabState();
}

class _ChartsTabState extends State<_ChartsTab> {
  String _selectedZone = 'All Zones';
  String _filterState = 'All'; // All, Normal, Anomaly
  int _limit = 0; // 0 = 24h (all), 20, 10, 5

  List<TimeseriesPoint> get _filteredData {
    var list = widget.timeseries.where((p) {
      final matchZone = _selectedZone == 'All Zones' || p.zone == _selectedZone;
      final matchState = _filterState == 'All' ||
          (_filterState == 'Normal' && p.isAnomaly == 0) ||
          (_filterState == 'Anomaly' && p.isAnomaly == 1);
      return matchZone && matchState;
    }).toList();

    // Sort descending by time to get the "latest", then take the limit, then re-sort ascending for chart
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (_limit > 0 && list.length > _limit) {
      list = list.take(_limit).toList();
    }
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.cyan));
    }

    final data = _filteredData;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Filters ───────────────────────────────────────────
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedZone,
                      isExpanded: true,
                      dropdownColor: AppTheme.bgCard,
                      icon: const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
                      style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13),
                      items: ['All Zones', 'Zone 1', 'Zone 2', 'Zone 3', 'Zone 4', 'Zone 5']
                          .map((z) => DropdownMenuItem(value: z, child: Text(z)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedZone = v!),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: ['All', 'Normal', 'Anomaly'].map((s) {
                      final active = _filterState == s;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _filterState = s),
                          child: Container(
                            decoration: BoxDecoration(
                              color: active ? AppTheme.cyan.withOpacity(0.2) : Colors.transparent,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            alignment: Alignment.center,
                            child: Text(s,
                              style: GoogleFonts.inter(
                                color: active ? AppTheme.cyan : AppTheme.textMuted,
                                fontSize: 11,
                                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                              )),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Limit Filter ───────────────────────────────────────────
          Row(
            children: [
              Text('Show: ', style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13)),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _limit,
                      isExpanded: true,
                      dropdownColor: AppTheme.bgCard,
                      icon: const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
                      style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Last 24h (All)')),
                        DropdownMenuItem(value: 20, child: Text('Last 20 Data Points')),
                        DropdownMenuItem(value: 10, child: Text('Last 10 Data Points')),
                        DropdownMenuItem(value: 5, child: Text('Last 5 Data Points')),
                      ],
                      onChanged: (v) => setState(() => _limit = v!),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // ── Pressure Chart ──────────────────────────────────────
          const SectionTitle('Pressure'),
          const SizedBox(height: 14),
          GlassCard(
            child: SizedBox(
              height: 200,
              child: data.isEmpty
                  ? const Center(child: Text('No data for selected filters',
                      style: TextStyle(color: AppTheme.textMuted)))
                  : LineChart(_buildChart(data, isPressure: true)),
            ),
          ),
          const SizedBox(height: 24),

          // ── Flow Rate Chart ─────────────────────────────────────
          const SectionTitle('Flow Rate'),
          const SizedBox(height: 14),
          GlassCard(
            child: SizedBox(
              height: 200,
              child: data.isEmpty
                  ? const Center(child: Text('No data for selected filters',
                      style: TextStyle(color: AppTheme.textMuted)))
                  : LineChart(_buildChart(data, isPressure: false)),
            ),
          ),
        ],
      ),
    );
  }

  LineChartData _buildChart(List<TimeseriesPoint> data, {required bool isPressure}) {
    final color = isPressure ? AppTheme.cyan : AppTheme.green;
    
    // Sort data chronologically just in case
    final sorted = List<TimeseriesPoint>.from(data)..sort((a,b) => a.timestamp.compareTo(b.timestamp));

    final spots = sorted.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), isPressure ? e.value.pressure : e.value.flow);
    }).toList();

    return LineChartData(
      gridData: FlGridData(
        getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.border, strokeWidth: 0.5),
        getDrawingVerticalLine: (_) => FlLine(color: AppTheme.border, strokeWidth: 0.5),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1),
              style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 10)),
          ),
        ),
        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 2.5,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              final pt = sorted[index];
              if (pt.isAnomaly == 1) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: AppTheme.red,
                  strokeWidth: 1.5,
                  strokeColor: Colors.white,
                );
              }
              // Hide dots for normal points
              return FlDotCirclePainter(radius: 0, color: Colors.transparent, strokeWidth: 0);
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            color: color.withOpacity(0.08),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Alerts Tab
// ════════════════════════════════════════════════════════════════

class _AlertsTab extends StatelessWidget {
  final List<AlertModel> alerts;
  final bool loading;
  final VoidCallback onRefresh;
  const _AlertsTab({required this.alerts, required this.loading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.cyan));
    }
    if (alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('✅', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 16),
            Text('No Anomalies Detected',
              style: GoogleFonts.inter(
                  color: AppTheme.green,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('System is operating normally.',
              style: GoogleFonts.inter(
                  color: AppTheme.textSecondary, fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: alerts.length,
      itemBuilder: (ctx, i) {
        final a = alerts[i];
        final mins = DateTime.now().difference(a.detectedAt).inMinutes;
        final ago = mins < 60 ? '${mins}m ago' : '${(mins/60).floor()}h ago';
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            borderColor: AppTheme.red.withOpacity(0.25),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text('#${a.id}',
                      style: GoogleFonts.jetBrainsMono(
                        color: AppTheme.red, fontSize: 13,
                        fontWeight: FontWeight.w700))),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(a.zone,
                            style: GoogleFonts.inter(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                          const Spacer(),
                          Text(ago,
                            style: GoogleFonts.inter(
                                color: AppTheme.textMuted, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Show the custom message for broadcast alerts, sensor info for model alerts
                      if (a.message != null && a.message!.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.red.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.campaign_outlined, size: 13, color: AppTheme.orange),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  a.message!,
                                  style: GoogleFonts.inter(
                                      color: AppTheme.orange, fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Text(
                          'Sensors: ${a.topSensors.join(", ")} · '
                          'Conf: ${(a.confidence * 100).round()}% · '
                          'MSE: ${a.mse.toStringAsFixed(4)}',
                          style: GoogleFonts.inter(
                              color: AppTheme.textSecondary, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppTheme.red),
                  tooltip: 'Delete Alert',
                  onPressed: () async {
                    try {
                      await ApiService().deleteAlert(a.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Alert deleted', style: GoogleFonts.inter())),
                        );
                      }
                      onRefresh();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e', style: GoogleFonts.inter())),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


// ════════════════════════════════════════════════════════════════
// User Reports Tab (Management Queue)
// ════════════════════════════════════════════════════════════════

class _ReportsTab extends StatefulWidget {
  final List<ReportModel> reports;
  final bool loading;
  final VoidCallback onRefresh;
  const _ReportsTab({required this.reports, required this.loading, required this.onRefresh});

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  String _filter = 'All'; // All | pending | investigating | resolved
  bool _updating = false;

  List<ReportModel> get _filtered {
    if (_filter == 'All') return widget.reports;
    return widget.reports.where((r) => r.status == _filter).toList();
  }

  int _pendingCount() =>
      widget.reports.where((r) => r.status == 'pending').length;

  Future<void> _updateStatus(ReportModel report, String newStatus) async {
    setState(() => _updating = true);
    try {
      await ApiService().updateReportStatus(
          reportId: report.id, newStatus: newStatus);
      widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to "$newStatus"',
                style: GoogleFonts.inter()),
            backgroundColor: AppTheme.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e', style: GoogleFonts.inter()),
            backgroundColor: AppTheme.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.cyan));
    }

    final displayed = _filtered;
    final pendingCount = _pendingCount();

    return Column(
      children: [
        // ── Filter chips ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
              _FilterChip(label: 'All', active: _filter == 'All',
                  color: AppTheme.cyan,
                  onTap: () => setState(() => _filter = 'All')),
              const SizedBox(width: 8),
              _FilterChip(
                label: pendingCount > 0
                    ? 'Pending ($pendingCount)' : 'Pending',
                active: _filter == 'pending',
                color: AppTheme.orange,
                onTap: () => setState(() => _filter = 'pending'),
              ),
              const SizedBox(width: 8),
              _FilterChip(label: 'In Progress', active: _filter == 'investigating',
                  color: AppTheme.cyan,
                  onTap: () => setState(() => _filter = 'investigating')),
              const SizedBox(width: 8),
              _FilterChip(label: 'Resolved', active: _filter == 'resolved',
                  color: AppTheme.green,
                  onTap: () => setState(() => _filter = 'resolved')),
            ],
          ),
        ),
      ),
      const Divider(height: 1, color: AppTheme.border),

        // ── List ──────────────────────────────────────────────
        if (displayed.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('📄', style: TextStyle(fontSize: 52)),
                  const SizedBox(height: 16),
                  Text('No Reports',
                      style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                    _filter == 'All'
                        ? 'No issues have been reported manually.'
                        : 'No reports with status "$_filter".',
                    style: GoogleFonts.inter(
                        color: AppTheme.textSecondary, fontSize: 14)),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: displayed.length,
              itemBuilder: (ctx, i) {
                final r = displayed[i];
                final mins = DateTime.now().difference(r.createdAt).inMinutes;
                final ago = mins < 60 ? '${mins}m ago' : '${(mins / 60).floor()}h ago';

                Color sevColor = AppTheme.green;
                if (r.severity == 'high') sevColor = AppTheme.red;
                if (r.severity == 'medium') sevColor = AppTheme.orange;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassCard(
                    borderColor: sevColor.withOpacity(0.3),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Top row ───────────────────────────
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: sevColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(r.severity.toUpperCase(),
                                style: GoogleFonts.jetBrainsMono(
                                    color: sevColor, fontSize: 10,
                                    fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 10),
                            Text(r.zone,
                              style: GoogleFonts.inter(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14)),
                            const Spacer(),
                            Text(ago,
                              style: GoogleFonts.inter(
                                  color: AppTheme.textMuted, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // ── Description ──────────────────────
                        Text(r.description,
                          style: GoogleFonts.inter(
                              color: AppTheme.textSecondary,
                              fontSize: 13, height: 1.4)),
                        const SizedBox(height: 10),

                        // ── Reporter & status ───────────────
                        Row(
                          children: [
                            const Icon(Icons.person_outline,
                                size: 14, color: AppTheme.textMuted),
                            const SizedBox(width: 4),
                            Text(
                              r.userName ?? (r.userId != null
                                  ? 'User ${r.userId}' : 'Anonymous'),
                              style: GoogleFonts.inter(
                                  color: AppTheme.textMuted, fontSize: 11)),
                            const Spacer(),
                            _StatusBadge(r.status),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ── Action row ────────────────────────
                        Row(
                          children: [
                            if (r.status == 'pending')
                              _ActionButton(
                                label: 'Start Investigating',
                                color: AppTheme.cyan,
                                icon: Icons.search_rounded,
                                loading: _updating,
                                onTap: () => _updateStatus(r, 'investigating'),
                              )
                            else if (r.status == 'investigating')
                              _ActionButton(
                                label: 'Mark Resolved',
                                color: AppTheme.green,
                                icon: Icons.check_circle_outline_rounded,
                                loading: _updating,
                                onTap: () => _updateStatus(r, 'resolved'),
                              )
                            else
                              Row(
                                children: [
                                  const Icon(Icons.check_circle,
                                      color: AppTheme.green, size: 16),
                                  const SizedBox(width: 6),
                                  Text('Resolved',
                                      style: GoogleFonts.inter(
                                          color: AppTheme.green,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: AppTheme.red),
                              tooltip: 'Delete Report',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () async {
                                try {
                                  await ApiService().deleteReport(r.id);
                                  widget.onRefresh();
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e')),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Reports Tab helpers
// ──────────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label,
      required this.active,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.18) : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? color.withOpacity(0.6) : AppTheme.border),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
                color: active ? color : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (status) {
      case 'investigating':
        color = AppTheme.cyan;
        label = 'In Progress';
        break;
      case 'resolved':
        color = AppTheme.green;
        label = 'Resolved';
        break;
      default:
        color = AppTheme.orange;
        label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5, height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.inter(
                  color: color, fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: color))
            else
              Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.inter(
                    color: color, fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// Outages Tab
// ════════════════════════════════════════════════════════════════

class _OutagesTab extends StatefulWidget {
  const _OutagesTab();

  @override
  State<_OutagesTab> createState() => _OutagesTabState();
}

class _OutagesTabState extends State<_OutagesTab> {
  List<OutageModel> _outages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadOutages();
  }

  Future<void> _loadOutages() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService().getOutages();
      if (mounted) setState(() => _outages = list);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCreateDialog() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String zone = 'Zone 1';
    int hours = 2;
    TimeOfDay selectedTime = TimeOfDay.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            decoration: const BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 24, right: 24, top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Schedule Outage',
                  style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                
                // Zone Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.bgPrimary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: zone,
                      isExpanded: true,
                      dropdownColor: AppTheme.bgPrimary,
                      style: GoogleFonts.inter(color: AppTheme.textPrimary),
                      items: ['Zone 1', 'Zone 2', 'Zone 3', 'Zone 4', 'Zone 5']
                          .map((z) => DropdownMenuItem(value: z, child: Text(z)))
                          .toList(),
                      onChanged: (v) => setModalState(() => zone = v!),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Title
                TextField(
                  controller: titleCtrl,
                  style: GoogleFonts.inter(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Title (min. 3 characters)',
                    hintStyle: GoogleFonts.inter(color: AppTheme.textMuted),
                    filled: true,
                    fillColor: AppTheme.bgPrimary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Start Time
                Row(
                  children: [
                    Text('Start Time: ', style: GoogleFonts.inter(color: AppTheme.textSecondary)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.cyan,
                          side: const BorderSide(color: AppTheme.cyan),
                        ),
                        icon: const Icon(Icons.access_time, size: 18),
                        label: Text(selectedTime.format(context), style: GoogleFonts.inter()),
                        onPressed: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: selectedTime,
                            builder: (context, child) => Theme(
                              data: ThemeData.dark().copyWith(
                                colorScheme: const ColorScheme.dark(
                                  primary: AppTheme.cyan,
                                  onPrimary: AppTheme.bgPrimary,
                                  surface: AppTheme.bgCard,
                                  onSurface: AppTheme.textPrimary,
                                ),
                              ),
                              child: child!,
                            ),
                          );
                          if (time != null) setModalState(() => selectedTime = time);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Duration
                Row(
                  children: [
                    Text('Duration: ', style: GoogleFonts.inter(color: AppTheme.textSecondary)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: hours.toDouble(),
                        min: 1, max: 24, divisions: 23,
                        activeColor: AppTheme.cyan,
                        label: '$hours hours',
                        onChanged: (v) => setModalState(() => hours = v.toInt()),
                      ),
                    ),
                    Text('${hours}h', style: GoogleFonts.inter(color: AppTheme.cyan, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.cyan,
                      foregroundColor: AppTheme.bgPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      if (titleCtrl.text.trim().length < 3) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Title must be at least 3 characters.', style: GoogleFonts.inter()), backgroundColor: AppTheme.red),
                        );
                        return;
                      }
                      
                      final now = DateTime.now();
                      var startTime = DateTime(now.year, now.month, now.day, selectedTime.hour, selectedTime.minute);
                      if (startTime.isBefore(now)) {
                        // If selected time is earlier today, assume it's for tomorrow
                        startTime = startTime.add(const Duration(days: 1));
                      }
                      
                      Navigator.pop(ctx);
                      try {
                        await ApiService().createOutage(
                          zone: zone,
                          title: titleCtrl.text.trim(),
                          description: descCtrl.text,
                          startTime: startTime,
                          endTime: startTime.add(Duration(hours: hours)),
                        );
                        _loadOutages();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    },
                    child: Text('Broadcast Outage Notice',
                      style: GoogleFonts.inter(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.cyan));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        backgroundColor: AppTheme.cyan,
        icon: const Icon(Icons.add, color: AppTheme.bgPrimary),
        label: Text('Schedule Outage', style: GoogleFonts.inter(color: AppTheme.bgPrimary, fontWeight: FontWeight.w600)),
      ),
      body: _outages.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('📅', style: TextStyle(fontSize: 52)),
                  const SizedBox(height: 16),
                  Text('No Outages',
                    style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('All zones have normal water service.',
                    style: GoogleFonts.inter(
                        color: AppTheme.textSecondary, fontSize: 14)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(20).copyWith(bottom: 100),
              itemCount: _outages.length,
              itemBuilder: (ctx, i) {
                final o = _outages[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    borderColor: AppTheme.orange.withOpacity(0.3),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.orange.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(o.zone,
                                      style: GoogleFonts.jetBrainsMono(
                                        color: AppTheme.orange, fontSize: 10,
                                        fontWeight: FontWeight.w800)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(o.title,
                                      style: GoogleFonts.inter(
                                          color: AppTheme.textPrimary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(Icons.access_time, size: 14, color: AppTheme.textMuted),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${o.startTime.hour.toString().padLeft(2, '0')}:${o.startTime.minute.toString().padLeft(2, '0')} - ${o.endTime.hour.toString().padLeft(2, '0')}:${o.endTime.minute.toString().padLeft(2, '0')}',
                                    style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 11),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppTheme.red),
                          tooltip: 'Cancel Outage',
                          onPressed: () async {
                            try {
                              await ApiService().deleteOutage(o.id);
                              _loadOutages();
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
