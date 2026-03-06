import 'package:flutter/material.dart';

import '../../core/services/district_health_intelligence.dart';

/// District Health Intelligence Dashboard.
///
/// Displays anonymized, aggregated screening data for district officers:
///   • Summary statistics
///   • Risk heatmap by village
///   • Coverage metrics
///   • Outlier alerts
///
/// No personal data is shown — all statistics are aggregated and anonymized.
class DistrictDashboardScreen extends StatefulWidget {
  const DistrictDashboardScreen({super.key});

  @override
  State<DistrictDashboardScreen> createState() =>
      _DistrictDashboardScreenState();
}

class _DistrictDashboardScreenState extends State<DistrictDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _dhi = DistrictHealthIntelligence.instance;
  late TabController _tabCtrl;

  bool _loading = true;
  String? _error;
  DistrictHealthSummary? _summary;
  List<HeatmapPoint> _heatmap = [];
  CoverageStats? _coverage;
  List<OutlierAlert> _alerts = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _dhi.initialize();
      final summary = await _dhi.generateSummary();
      final heatmap = await _dhi.generateHeatmap();
      final coverage = await _dhi.getCoverageStats();
      final alerts = await _dhi.getActiveAlerts();
      if (mounted) {
        setState(() {
          _summary = summary;
          _heatmap = heatmap;
          _coverage = coverage;
          _alerts = alerts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('District Health Intelligence'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Heatmap'),
            Tab(text: 'Coverage'),
            Tab(text: 'Alerts'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildOverview(theme),
                    _buildHeatmap(theme),
                    _buildCoverage(theme),
                    _buildAlerts(theme),
                  ],
                ),
    );
  }

  // ── Overview Tab ──────────────────────────────────────────────────

  Widget _buildOverview(ThemeData theme) {
    final s = _summary;
    if (s == null) return const Center(child: Text('No data available'));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('District: ${s.districtName}',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Generated: ${s.generatedAt.toString().substring(0, 16)}',
                  style: theme.textTheme.bodySmall,
                ),
                const Divider(),
                _statRow('Total Patients', '${s.totalPatients}'),
                _statRow('Total Screenings', '${s.totalScreenings}'),
                _statRow('Cancer Screenings', '${s.cancerScreenings}'),
                _statRow('TB Screenings', '${s.tbScreenings}'),
                _statRow('Avg Confidence',
                    '${(s.avgConfidence * 100).toStringAsFixed(1)}%'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Risk Distribution',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                _riskBar('High Risk', s.highRiskCount, s.totalScreenings,
                    Colors.red),
                const SizedBox(height: 8),
                _riskBar('Medium Risk', s.mediumRiskCount,
                    s.totalScreenings, Colors.orange),
                const SizedBox(height: 8),
                _riskBar('Low Risk', s.lowRiskCount, s.totalScreenings,
                    Colors.green),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (s.villageSummaries.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Villages (${s.villageSummaries.length})',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ...s.villageSummaries.map((v) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(v.villageName),
                        subtitle: Text(
                            '${v.screeningCount} screenings, '
                            '${v.highRiskCount} high-risk'),
                        trailing: _riskChip(v.riskScore),
                      )),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'All data is anonymized. No personal information is aggregated.',
          style: theme.textTheme.bodySmall?.copyWith(
            fontStyle: FontStyle.italic,
            color: Colors.grey,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── Heatmap Tab ──────────────────────────────────────────────────

  Widget _buildHeatmap(ThemeData theme) {
    if (_heatmap.isEmpty) {
      return const Center(child: Text('No heatmap data available'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Risk Heatmap by Village',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Sorted by risk score (highest first)',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        ..._heatmap.map((p) => Card(
              color: Color.lerp(
                Colors.green.shade50,
                Colors.red.shade50,
                p.intensity,
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color.lerp(
                    Colors.green,
                    Colors.red,
                    p.intensity,
                  ),
                  child: Text(
                    '${(p.riskScore * 100).toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                title: Text(p.location),
                subtitle: Text(
                  '${p.screeningCount} screenings  •  '
                  '${p.highRiskCount} high-risk',
                ),
                trailing: Icon(
                  Icons.local_fire_department,
                  color: Color.lerp(Colors.green, Colors.red, p.intensity),
                ),
              ),
            )),
      ],
    );
  }

  // ── Coverage Tab ─────────────────────────────────────────────────

  Widget _buildCoverage(ThemeData theme) {
    final c = _coverage;
    if (c == null) return const Center(child: Text('No coverage data'));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Coverage Statistics', style: theme.textTheme.titleMedium),
                Text('Period: ${c.period}', style: theme.textTheme.bodySmall),
                const Divider(),
                _statRow('Total Screenings', '${c.totalScreenings}'),
                _statRow('Unique Patients', '${c.uniquePatients}'),
                _statRow('Cancer Screenings', '${c.cancerScreenings}'),
                _statRow('TB Screenings', '${c.tbScreenings}'),
                _statRow('High Risk Referrals', '${c.highRiskReferrals}'),
                _statRow('Avg Confidence',
                    '${(c.averageConfidence * 100).toStringAsFixed(1)}%'),
                const SizedBox(height: 12),
                Text('Coverage Rate',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: c.coveragePercentage / 100,
                  minHeight: 20,
                  borderRadius: BorderRadius.circular(10),
                  backgroundColor: Colors.grey.shade200,
                  color: c.coveragePercentage > 70
                      ? Colors.green
                      : c.coveragePercentage > 40
                          ? Colors.orange
                          : Colors.red,
                ),
                const SizedBox(height: 4),
                Text(
                  '${c.coveragePercentage.toStringAsFixed(1)}% of registered patients screened',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Alerts Tab ───────────────────────────────────────────────────

  Widget _buildAlerts(ThemeData theme) {
    if (_alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green.shade300),
            const SizedBox(height: 12),
            const Text('No outlier alerts'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _alerts.length,
      itemBuilder: (ctx, i) {
        final a = _alerts[i];
        final severityColor = a.severity == 'critical'
            ? Colors.red
            : a.severity == 'warning'
                ? Colors.orange
                : Colors.blue;

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: severityColor.withValues(alpha: 0.2),
              child: Icon(
                a.severity == 'critical'
                    ? Icons.error
                    : Icons.warning_amber,
                color: severityColor,
              ),
            ),
            title: Text(a.location),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.description, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Chip(
                      label: Text(a.severity.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            color: severityColor,
                          )),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: severityColor.withValues(alpha: 0.1),
                    ),
                    const SizedBox(width: 8),
                    Text('z=${a.zScore.toStringAsFixed(2)}',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () async {
                await _dhi.dismissAlert(a.id);
                await _loadAll();
              },
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  // ── Helper Widgets ───────────────────────────────────────────────

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _riskBar(String label, int count, int total, Color color) {
    final pct = total > 0 ? count / total : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 90,
          child:
              Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 12,
            borderRadius: BorderRadius.circular(6),
            backgroundColor: Colors.grey.shade200,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text('$count',
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.right),
        ),
      ],
    );
  }

  Widget _riskChip(double riskScore) {
    final color = riskScore > 0.5
        ? Colors.red
        : riskScore > 0.2
            ? Colors.orange
            : Colors.green;
    return Chip(
      label: Text(
        '${(riskScore * 100).toStringAsFixed(0)}%',
        style: TextStyle(color: color, fontSize: 11),
      ),
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: 0.1),
    );
  }
}
