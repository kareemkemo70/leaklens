// lib/screens/engineer/analytics_screen.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:animate_do/animate_do.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/prediction_model.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  AnalyticsData? _data;
  bool _loading = true;
  int _days = 30;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await ApiService().getAnalytics(days: _days);
      if (mounted) setState(() => _data = d);
    } catch (_) {
      if (mounted) setState(() => _data = _demoData());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  AnalyticsData _demoData() => AnalyticsData(
    totalAnomalies: 35,
    totalReports: 17,
    mostAffectedZone: 'Zone 2',
    avgConfidence: 0.78,
    leaksPerZone: [
      ZoneAnalytics(zone: 'Zone 1', leakCount: 6,  reportCount: 3,  totalIncidents: 9),
      ZoneAnalytics(zone: 'Zone 2', leakCount: 14, reportCount: 5,  totalIncidents: 19),
      ZoneAnalytics(zone: 'Zone 3', leakCount: 4,  reportCount: 2,  totalIncidents: 6),
      ZoneAnalytics(zone: 'Zone 4', leakCount: 9,  reportCount: 7,  totalIncidents: 16),
      ZoneAnalytics(zone: 'Zone 5', leakCount: 2,  reportCount: 0,  totalIncidents: 2),
    ],
  );

  final _zoneColors = [
    AppTheme.cyan,
    AppTheme.red,
    AppTheme.green,
    AppTheme.orange,
    AppTheme.purple,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          PopupMenuButton<int>(
            color: AppTheme.bgCard,
            icon: const Icon(Icons.calendar_today_outlined,
                             color: AppTheme.textSecondary),
            onSelected: (v) { setState(() => _days = v); _load(); },
            itemBuilder: (_) => [
              for (final d in [7, 14, 30, 90])
                PopupMenuItem<int>(
                  value: d,
                  child: Text('Last $d days',
                    style: GoogleFonts.inter(color: AppTheme.textPrimary)),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                             color: AppTheme.textSecondary),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.cyan))
          : _data == null
              ? const Center(child: Text('Failed to load analytics'))
              : _body(),
    );
  }

  Widget _body() {
    final d = _data!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Period badge ──────────────────────────────────────────
          FadeInDown(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.cyan.withOpacity(0.1),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: AppTheme.cyan.withOpacity(0.3)),
              ),
              child: Text('Last $_days days · ${d.totalAnomalies + d.totalReports} total incidents',
                style: GoogleFonts.inter(
                    color: AppTheme.cyan, fontSize: 12,
                    fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(height: 20),

          // ── Summary KPIs ──────────────────────────────────────────
          FadeInDown(
            delay: const Duration(milliseconds: 80),
            child: Row(
              children: [
                Expanded(child: _Kpi('🚨', 'Model Detections',
                    '${d.totalAnomalies}', AppTheme.red)),
                const SizedBox(width: 12),
                Expanded(child: _Kpi('📢', 'User Reports',
                    '${d.totalReports}', AppTheme.orange)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FadeInDown(
            delay: const Duration(milliseconds: 130),
            child: Row(
              children: [
                Expanded(child: _Kpi('🎯', 'Avg Confidence',
                    '${(d.avgConfidence * 100).round()}%', AppTheme.cyan)),
                const SizedBox(width: 12),
                Expanded(child: _Kpi('📍', 'Most Affected',
                    d.mostAffectedZone, AppTheme.purple)),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Bar chart: leaks per zone ─────────────────────────────
          FadeInUp(
            delay: const Duration(milliseconds: 200),
            child: const SectionTitle('Leaks per Zone'),
          ),
          const SizedBox(height: 14),

          FadeInUp(
            delay: const Duration(milliseconds: 250),
            child: GlassCard(
              child: SizedBox(
                height: 220,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(
                          color: AppTheme.border, strokeWidth: 0.5),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (v, _) => Text('${v.toInt()}',
                            style: GoogleFonts.inter(
                                color: AppTheme.textMuted, fontSize: 10)),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx >= d.leaksPerZone.length) return const SizedBox();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('Z${idx + 1}',
                                style: GoogleFonts.inter(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                            );
                          },
                        ),
                      ),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    barGroups: d.leaksPerZone.asMap().entries.map((e) {
                      final color = _zoneColors[e.key % _zoneColors.length];
                      return BarChartGroupData(
                        x: e.key,
                        barRods: [
                          BarChartRodData(
                            toY: e.value.leakCount.toDouble(),
                            color: color,
                            width: 22,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6)),
                            backDrawRodData: BackgroundBarChartRodData(
                              show: true,
                              toY: (d.leaksPerZone
                                  .map((z) => z.leakCount)
                                  .reduce((a, b) => a > b ? a : b) * 1.2),
                              color: color.withOpacity(0.06),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // ── Zone incident table ───────────────────────────────────
          FadeInUp(
            delay: const Duration(milliseconds: 350),
            child: const SectionTitle('Zone Breakdown'),
          ),
          const SizedBox(height: 14),

          ...d.leaksPerZone.asMap().entries.map((e) {
            final z = e.value;
            final color = _zoneColors[e.key % _zoneColors.length];
            final maxTotal = d.leaksPerZone
                .map((z) => z.totalIncidents)
                .reduce((a, b) => a > b ? a : b);
            final pct = maxTotal > 0 ? z.totalIncidents / maxTotal : 0.0;

            return FadeInLeft(
              delay: Duration(milliseconds: 400 + e.key * 60),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(z.zone,
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            )),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text('${z.totalIncidents} incidents',
                              style: GoogleFonts.inter(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              )),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: pct,
                          backgroundColor: color.withOpacity(0.1),
                          valueColor: AlwaysStoppedAnimation(color),
                          minHeight: 7,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _stat('🚨 Leaks', '${z.leakCount}', AppTheme.red),
                          const SizedBox(width: 20),
                          _stat('📢 Reports', '${z.reportCount}', AppTheme.orange),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Row(
    children: [
      Text(label,
        style: GoogleFonts.inter(
            color: AppTheme.textMuted, fontSize: 12)),
      const SizedBox(width: 6),
      Text(value,
        style: GoogleFonts.inter(
            color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    ],
  );

  Widget _Kpi(String emoji, String label, String value, Color color) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                  style: GoogleFonts.inter(
                      color: AppTheme.textMuted, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value,
                  style: GoogleFonts.inter(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
