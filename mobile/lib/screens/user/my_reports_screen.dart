// lib/screens/user/my_reports_screen.dart
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/prediction_model.dart';
import '../../utils/nav.dart';
import 'report_issue_screen.dart';

class MyReportsScreen extends StatefulWidget {
  final int userId;
  const MyReportsScreen({super.key, required this.userId});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  List<ReportModel> _reports = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final reports = await ApiService().getMyReports(userId: widget.userId);
      if (mounted) setState(() => _reports = reports);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Reports',
            style: GoogleFonts.inter(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            onPressed: _loadReports,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.cyan,
        backgroundColor: AppTheme.bgCard,
        onRefresh: _loadReports,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.cyan));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text('Could not load reports',
                  style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                onPressed: _loadReports,
              ),
            ],
          ),
        ),
      );
    }

    if (_reports.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FadeIn(
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: AppTheme.cyan.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.cyan.withOpacity(0.3)),
                        ),
                        child: const Center(
                          child: Text('📋', style: TextStyle(fontSize: 40)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('No Reports Yet',
                        style: GoogleFonts.inter(
                            color: AppTheme.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                      'You haven\'t reported any issues yet.\nHelp us keep your water supply safe!',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Report an Issue'),
                      onPressed: () => pushFade(context, const ReportIssueScreen()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      itemCount: _reports.length,
      itemBuilder: (ctx, i) => FadeInUp(
        duration: const Duration(milliseconds: 280),
        delay: Duration(milliseconds: i * 50),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _ReportCard(report: _reports[i]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Report Card
// ─────────────────────────────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final ReportModel report;
  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final sevColor = _sevColor(report.severity);
    final statusInfo = _statusInfo(report.status);
    final mins = DateTime.now().difference(report.createdAt).inMinutes;
    final timeAgo = mins < 60
        ? '${mins}m ago'
        : mins < 1440
            ? '${(mins / 60).floor()}h ago'
            : '${(mins / 1440).floor()}d ago';

    return GlassCard(
      borderColor: sevColor.withOpacity(0.3),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────
          Row(
            children: [
              // Severity badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: sevColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: sevColor.withOpacity(0.4)),
                ),
                child: Text(
                  report.severity.toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                      color: sevColor, fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  report.zone,
                  style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
              ),
              Text(timeAgo,
                  style: GoogleFonts.inter(
                      color: AppTheme.textMuted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),

          // ── Description ──────────────────────────────────────────
          Text(
            report.description,
            style: GoogleFonts.inter(
                color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),

          // ── Status row ───────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: statusInfo.$2.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusInfo.$2.withOpacity(0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: statusInfo.$2,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusInfo.$1,
                      style: GoogleFonts.inter(
                          color: statusInfo.$2,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '#${report.id}',
                style: GoogleFonts.jetBrainsMono(
                    color: AppTheme.textMuted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _sevColor(String sev) {
    switch (sev) {
      case 'high':
        return AppTheme.red;
      case 'medium':
        return AppTheme.orange;
      default:
        return AppTheme.green;
    }
  }

  /// Returns (label, color) for the status
  (String, Color) _statusInfo(String status) {
    switch (status) {
      case 'investigating':
        return ('Investigating', AppTheme.cyan);
      case 'resolved':
        return ('Resolved', AppTheme.green);
      default:
        return ('Pending', AppTheme.orange);
    }
  }
}
