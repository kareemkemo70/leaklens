import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/prediction_model.dart';

// ── Cairo Zone definitions ────────────────────────────────────────────────────
class _ZoneDef {
  final String id;
  final String name;
  final String district;
  final LatLng coords;

  const _ZoneDef({
    required this.id,
    required this.name,
    required this.district,
    required this.coords,
  });
}

const _zones = [
  _ZoneDef(id: 'Zone 1', name: 'Zone 1', district: 'Shoubra El Kheima',
      coords: LatLng(30.1236, 31.2429)),
  _ZoneDef(id: 'Zone 2', name: 'Zone 2', district: 'Heliopolis',
      coords: LatLng(30.0870, 31.3217)),
  _ZoneDef(id: 'Zone 3', name: 'Zone 3', district: 'Nasr City',
      coords: LatLng(30.0626, 31.3417)),
  _ZoneDef(id: 'Zone 4', name: 'Zone 4', district: 'Maadi',
      coords: LatLng(29.9600, 31.2600)),
  _ZoneDef(id: 'Zone 5', name: 'Zone 5', district: 'New Cairo',
      coords: LatLng(30.0131, 31.4800)),
];

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class EngineerMapScreen extends StatefulWidget {
  const EngineerMapScreen({super.key});

  @override
  State<EngineerMapScreen> createState() => _EngineerMapScreenState();
}

class _EngineerMapScreenState extends State<EngineerMapScreen> {
  List<AlertModel> _alerts = [];
  bool _loading = true;
  Timer? _refreshTimer;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _loadAlerts();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadAlerts());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    try {
      final alerts = await ApiService().getAlerts(limit: 50);
      if (mounted) setState(() { _alerts = alerts; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Zone status helpers ──────────────────────────────────────────────────
  /// Returns the most severe active alert for a zone (null = normal)
  AlertModel? _alertForZone(String zoneId) {
    final zoneAlerts = _alerts.where((a) => a.zone == zoneId && a.isAnomaly).toList();
    if (zoneAlerts.isEmpty) return null;
    zoneAlerts.sort((a, b) => b.confidence.compareTo(a.confidence));
    return zoneAlerts.first;
  }

  Color _zoneColor(String zoneId) {
    final alert = _alertForZone(zoneId);
    if (alert == null) return AppTheme.green;
    if (alert.confidence >= 0.75) return AppTheme.red;
    return AppTheme.orange;
  }

  String _zoneStatusLabel(String zoneId) {
    final alert = _alertForZone(zoneId);
    if (alert == null) return 'Normal';
    if (alert.confidence >= 0.75) return 'Leak Detected';
    return 'Warning';
  }

  // ── Zone tap → bottom sheet ───────────────────────────────────────────────
  void _showZoneSheet(_ZoneDef zone) {
    final alert = _alertForZone(zone.id);
    final color = _zoneColor(zone.id);
    final statusLabel = _zoneStatusLabel(zone.id);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Zone header
            Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: Center(
                    child: Text(
                      alert == null ? '✅' : (alert.confidence >= 0.75 ? '🚨' : '⚠️'),
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(zone.name,
                          style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800)),
                      Text(zone.district,
                          style: GoogleFonts.inter(
                              color: AppTheme.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withOpacity(0.35)),
                  ),
                  child: Text(statusLabel,
                      style: GoogleFonts.inter(
                          color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: AppTheme.border),
            const SizedBox(height: 16),

            if (alert == null) ...[
              Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: AppTheme.green, size: 18),
                  const SizedBox(width: 8),
                  Text('No anomalies detected in the last 24 hours.',
                      style: GoogleFonts.inter(
                          color: AppTheme.textSecondary, fontSize: 14)),
                ],
              ),
            ] else ...[
              _SheetRow('Confidence',
                  '${(alert.confidence * 100).round()}%', color),
              _SheetRow('MSE Score', alert.mse.toStringAsFixed(5), AppTheme.textSecondary),
              _SheetRow('Top Sensors', alert.topSensors.take(3).join(', '),
                  AppTheme.textSecondary),
              _SheetRow('Source', alert.source, AppTheme.textSecondary),
              _SheetRow('Detected', _timeAgo(alert.detectedAt), AppTheme.textMuted),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: Text('Zone Map — Cairo',
            style: GoogleFonts.inter(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            onPressed: _loadAlerts,
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ───────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(30.0600, 31.3200),
              initialZoom: 10.8,
              minZoom: 9,
              maxZoom: 16,
            ),
            children: [
              // OSM tile layer with dark mode filter
              ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  -0.7, 0, 0, 0, 255,
                   0, -0.7, 0, 0, 255,
                   0, 0, -0.7, 0, 255,
                   0, 0, 0, 1, 0,
                ]),
                child: TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.leaklens.app',
                ),
              ),

              // Zone circles
              CircleLayer(
                circles: _zones.map((z) {
                  final color = _zoneColor(z.id);
                  return CircleMarker(
                    point: z.coords,
                    radius: 28,
                    color: color.withOpacity(0.25),
                    borderColor: color,
                    borderStrokeWidth: 2.5,
                    useRadiusInMeter: false,
                  );
                }).toList(),
              ),

              // Zone labels as markers
              MarkerLayer(
                markers: _zones.map((z) {
                  final color = _zoneColor(z.id);
                  return Marker(
                    point: z.coords,
                    width: 80,
                    height: 70,
                    child: GestureDetector(
                      onTap: () => _showZoneSheet(z),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.bgCard.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: color.withOpacity(0.6)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(z.name,
                                    style: GoogleFonts.inter(
                                        color: color,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800)),
                                Text(
                                  _zoneStatusLabel(z.id),
                                  style: GoogleFonts.inter(
                                      color: AppTheme.textMuted, fontSize: 8),
                                ),
                              ],
                            ),
                          ),
                          CustomPaint(
                            size: const Size(8, 6),
                            painter: _TrianglePainter(color),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // ── Loading overlay ───────────────────────────────────────
          if (_loading)
            const Center(child: CircularProgressIndicator(color: AppTheme.cyan)),

          // ── Legend ────────────────────────────────────────────────
          Positioned(
            bottom: 24,
            left: 16,
            child: FadeInUp(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('STATUS',
                        style: GoogleFonts.inter(
                            color: AppTheme.textMuted,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5)),
                    const SizedBox(height: 8),
                    _LegendItem(color: AppTheme.green, label: 'Normal'),
                    const SizedBox(height: 5),
                    _LegendItem(color: AppTheme.orange, label: 'Warning'),
                    const SizedBox(height: 5),
                    _LegendItem(color: AppTheme.red, label: 'Leak Detected'),
                  ],
                ),
              ),
            ),
          ),

          // ── Tap hint ─────────────────────────────────────────────
          Positioned(
            top: 12,
            left: 0, right: 0,
            child: Center(
              child: FadeInDown(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text('Tap a zone label for details',
                      style: GoogleFonts.inter(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SheetRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _SheetRow(this.label, this.value, this.valueColor);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: GoogleFonts.inter(
                    color: AppTheme.textMuted, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.inter(
                    color: valueColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: GoogleFonts.inter(
                color: AppTheme.textSecondary, fontSize: 12)),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter(this.color);

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final paint = ui.Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = ui.PaintingStyle.fill;
    final path = ui.Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}
