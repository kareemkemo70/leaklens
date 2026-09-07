import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:animate_do/animate_do.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../models/prediction_model.dart';

class OutagesScreen extends StatefulWidget {
  final String userZone;
  const OutagesScreen({super.key, required this.userZone});

  @override
  State<OutagesScreen> createState() => _OutagesScreenState();
}

class _OutagesScreenState extends State<OutagesScreen> {
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
      final list = await ApiService().getOutages(zone: widget.userZone);
      if (mounted) setState(() => _outages = list);
    } catch (_) {
      if (mounted) setState(() => _outages = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scheduled Outages', style: GoogleFonts.inter()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOutages,
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.cyan))
          : _outages.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _outages.length,
                  itemBuilder: (ctx, i) {
                    final o = _outages[i];
                    return FadeInUp(
                      delay: Duration(milliseconds: i * 100),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassCard(
                          borderColor: AppTheme.orange.withOpacity(0.3),
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: AppTheme.orange.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                    child: Text('📅',
                                        style: TextStyle(fontSize: 24))),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      o.title,
                                      style: GoogleFonts.inter(
                                          color: AppTheme.textPrimary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15),
                                    ),
                                    const SizedBox(height: 4),
                                    if (o.description != null && o.description!.isNotEmpty) ...[
                                      Text(
                                        o.description!,
                                        style: GoogleFonts.inter(
                                            color: AppTheme.textSecondary,
                                            fontSize: 13),
                                      ),
                                      const SizedBox(height: 6),
                                    ],
                                    Row(
                                      children: [
                                        const Icon(Icons.access_time, size: 14, color: AppTheme.orange),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${DateFormat('h:mm a').format(o.startTime)} - ${DateFormat('h:mm a').format(o.endTime)}',
                                          style: GoogleFonts.inter(color: AppTheme.orange, fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BounceInDown(
            child: const Text('✅', style: TextStyle(fontSize: 72)),
          ),
          const SizedBox(height: 24),
          Text('No Outages',
            style: GoogleFonts.inter(
              color: AppTheme.green,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            )),
          const SizedBox(height: 12),
          Text(
            'There are no scheduled water outages\nfor ${widget.userZone}.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 14,
                height: 1.6),
          ),
        ],
      ),
    );
  }
}
