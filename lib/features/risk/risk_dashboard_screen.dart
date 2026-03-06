import 'package:flutter/material.dart';

import '../../core/services/risk_stratification.dart';

/// AI Risk Stratification Dashboard — population risk overview,
/// pending referrals, and patient risk history.
class RiskDashboardScreen extends StatefulWidget {
  const RiskDashboardScreen({super.key});

  @override
  State<RiskDashboardScreen> createState() => _RiskDashboardScreenState();
}

class _RiskDashboardScreenState extends State<RiskDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _engine = RiskStratificationEngine.instance;
  late TabController _tabs;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _referrals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _engine.initialize();
      final summary = await _engine.getPopulationRiskSummary();
      final referrals = await _engine.getPendingReferrals();
      if (mounted) {
        setState(() {
          _summary = summary;
          _referrals = referrals;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Risk Stratification'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard)),
            Tab(text: 'Referrals', icon: Icon(Icons.local_hospital)),
            Tab(text: 'Tiers', icon: Icon(Icons.bar_chart)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [_overviewTab(), _referralsTab(), _tiersTab()],
            ),
    );
  }

  Widget _overviewTab() {
    final total = _summary['total'] as int? ?? 0;
    final critical = _summary['critical'] as int? ?? 0;
    final high = _summary['high'] as int? ?? 0;
    final medium = _summary['medium'] as int? ?? 0;
    final low = _summary['low'] as int? ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.deepOrange.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.deepOrange),
                    const SizedBox(width: 8),
                    Text('Population Risk Summary',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            )),
                  ],
                ),
                const SizedBox(height: 12),
                Text('$total total assessments',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Risk tier breakdown
        _tierRow('CRITICAL', critical, Colors.red, Icons.emergency),
        _tierRow('HIGH', high, Colors.orange, Icons.warning),
        _tierRow('MEDIUM', medium, Colors.amber, Icons.info),
        _tierRow('LOW', low, Colors.green, Icons.check_circle),
        const SizedBox(height: 16),

        // Pending referrals count
        Card(
          child: ListTile(
            leading: const Icon(Icons.local_hospital, color: Colors.red),
            title: Text('Pending Referrals: ${_referrals.length}'),
            subtitle: const Text('Tap Referrals tab to manage'),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () => _tabs.animateTo(1),
          ),
        ),

        if (total == 0) ...[
          const SizedBox(height: 32),
          Center(
            child: Column(
              children: [
                Icon(Icons.analytics, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text('No assessments yet',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Risk assessments are created automatically when screenings are completed.',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _tierRow(String label, int count, Color color, IconData icon) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.2),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        trailing: Text('$count', style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: color,
        )),
      ),
    );
  }

  Widget _referralsTab() {
    if (_referrals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade300),
            const SizedBox(height: 12),
            const Text('No pending referrals', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _referrals.length,
      itemBuilder: (context, index) {
        final r = _referrals[index];
        final urgency = r['urgency'] as String? ?? 'routine';
        final color = urgency == 'emergency'
            ? Colors.red
            : urgency == 'urgent'
                ? Colors.orange
                : Colors.blue;
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.2),
              child: Icon(Icons.local_hospital, color: color),
            ),
            title: Text(r['facility_type'] as String? ?? 'Unknown Facility'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Patient: ${r['patient_id'] ?? 'N/A'}'),
                Text('Urgency: ${urgency.toUpperCase()}',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                Text('Deadline: ${r['deadline'] ?? 'N/A'}'),
              ],
            ),
            isThreeLine: true,
            trailing: Chip(
              label: Text(r['status'] as String? ?? 'pending',
                  style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
            ),
          ),
        );
      },
    );
  }

  Widget _tiersTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final tier in RiskTier.values) _tierInfoCard(tier),
      ],
    );
  }

  Widget _tierInfoCard(RiskTier tier) {
    final color = Color(int.parse('FF${tier.colorHex}', radix: 16));
    String range;
    String action;
    switch (tier) {
      case RiskTier.low:
        range = '0 – 30%';
        action = 'Annual rescreening';
      case RiskTier.medium:
        range = '30 – 60%';
        action = 'Rescreen in 90 days; counseling if flagged';
      case RiskTier.high:
        range = '60 – 85%';
        action = 'Refer to secondary facility within 7 days';
      case RiskTier.critical:
        range = '85 – 100%';
        action = 'EMERGENCY referral to tertiary centre within 24 hours';
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color,
                  radius: 14,
                  child: Text(tier.displayLabel[0],
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Text(tier.displayLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: color,
                    )),
              ],
            ),
            const SizedBox(height: 8),
            Text('Risk Score: $range', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            Text('Action: $action',
                style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}
