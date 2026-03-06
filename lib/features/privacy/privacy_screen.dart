import 'package:flutter/material.dart';

import '../../core/services/data_minimization.dart';

/// Data Minimization / Privacy Compliance screen — DPDP 2023 Gold Tier.
/// Retention policies, erasure requests, anonymization status, and
/// compliance dashboard.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen>
    with SingleTickerProviderStateMixin {
  final _engine = DataMinimizationEngine.instance;
  late TabController _tabs;
  PrivacyComplianceSummary? _summary;
  List<Map<String, dynamic>> _policies = [];
  List<Map<String, dynamic>> _erasureRequests = [];
  List<Map<String, dynamic>> _anonLog = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
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
      final summary = await _engine.getComplianceSummary();
      final policies = await _engine.getRetentionPolicies();
      final erasures = await _engine.getPendingErasureRequests();
      final anonLog = await _engine.getAnonymizationLog();
      if (mounted) {
        setState(() {
          _summary = summary;
          _policies = policies;
          _erasureRequests = erasures;
          _anonLog = anonLog;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runExpirationSweep() async {
    try {
      final count = await _engine.runExpirationSweep();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Expiration sweep: $count records expired'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _runAnonymization() async {
    try {
      final count = await _engine.anonymizeSyncedRecords();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Anonymized $count synced records'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _requestErasure() async {
    final patientIdController = TextEditingController();
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Right to Erasure (DPDP §12)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Submit an erasure request for a patient\'s data.'),
            const SizedBox(height: 12),
            TextField(
              controller: patientIdController,
              decoration: const InputDecoration(
                labelText: 'Patient ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit Request'),
          ),
        ],
      ),
    );

    if (confirmed != true || patientIdController.text.isEmpty) return;

    try {
      await _engine.requestErasure(
        patientId: patientIdController.text,
        requestedBy: 'admin',
        reason: reasonController.text.isNotEmpty
            ? reasonController.text
            : 'Consent withdrawal',
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erasure request submitted'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _executeErasure(String requestId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Execute Erasure'),
        content: const Text(
            'This will PERMANENTLY delete or anonymize all personal data '
            'for this patient. This action cannot be undone.\n\n'
            'Are you absolutely sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('EXECUTE ERASURE'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final report = await _engine.executeErasure(requestId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erased ${report.recordsErased} records from '
              '${report.tablesAffected.length} tables'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Privacy (DPDP)'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Compliance', icon: Icon(Icons.verified_user)),
            Tab(text: 'Policies', icon: Icon(Icons.policy)),
            Tab(text: 'Erasure', icon: Icon(Icons.delete_sweep)),
            Tab(text: 'Anonymization', icon: Icon(Icons.visibility_off)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [_complianceTab(), _policiesTab(), _erasureTab(), _anonTab()],
            ),
    );
  }

  // ────────────── COMPLIANCE TAB ──────────────

  Widget _complianceTab() {
    final s = _summary;
    if (s == null) return const Center(child: Text('No data'));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.purple.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.privacy_tip, color: Colors.purple),
                    const SizedBox(width: 8),
                    Text('DPDP 2023 Compliance Dashboard',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            )),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Digital Personal Data Protection Act',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _metricCard('Active Retention Policies', '${s.activePolicies}',
            Icons.policy, Colors.blue),
        _metricCard('Records Expired', '${s.totalRecordsExpired}',
            Icons.timer_off, Colors.orange),
        _metricCard('Records Anonymized', '${s.totalRecordsAnonymized}',
            Icons.visibility_off, Colors.teal),
        _metricCard('Erasures Completed', '${s.completedErasures}',
            Icons.delete_forever, Colors.red),
        _metricCard('Pending Erasure Requests', '${s.pendingErasureRequests}',
            Icons.pending, Colors.amber),
        _metricCard('Total Records Erased', '${s.totalRecordsErased}',
            Icons.delete_sweep, Colors.deepOrange),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.schedule),
            title: Text('Last Sweep: ${s.lastSweepAt}'),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _runExpirationSweep,
                icon: const Icon(Icons.cleaning_services),
                label: const Text('Run Expiration Sweep'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _runAnonymization,
                icon: const Icon(Icons.visibility_off),
                label: const Text('Run Anonymization'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.2),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(label),
        trailing: Text(value, style: TextStyle(
          fontSize: 20, fontWeight: FontWeight.bold, color: color,
        )),
      ),
    );
  }

  // ────────────── POLICIES TAB ──────────────

  Widget _policiesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.blue.shade50,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Retention policies define how long data is kept on-device. '
                    'Expired data is automatically deleted or flagged for review.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final p in _policies) _policyCard(p),
      ],
    );
  }

  Widget _policyCard(Map<String, dynamic> p) {
    final tableName = p['table_name']?.toString() ?? '';
    final days = (p['retention_days'] as num?)?.toInt() ?? 0;
    final autoAnon = _toBool(p['anonymize_after_sync']);
    final autoDelete = _toBool(p['auto_delete']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.table_chart, size: 18),
                const SizedBox(width: 8),
                Text(tableName, style: const TextStyle(
                  fontWeight: FontWeight.bold, fontFamily: 'monospace')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _policyChip('Retention: ${_formatDays(days)}', Colors.blue),
                const SizedBox(width: 4),
                if (autoAnon) _policyChip('Auto-anonymize', Colors.teal),
                if (autoDelete) _policyChip('Auto-delete', Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _policyChip(String label, Color color) {
    return Chip(
      label: Text(label, style: TextStyle(fontSize: 10, color: color)),
      backgroundColor: color.withValues(alpha: 0.1),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  String _formatDays(int days) {
    if (days >= 365) return '${days ~/ 365} year${days >= 730 ? 's' : ''}';
    if (days >= 30) return '${days ~/ 30} month${days >= 60 ? 's' : ''}';
    return '$days days';
  }

  // ────────────── ERASURE TAB ──────────────

  Widget _erasureTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.red.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.gavel, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Right to Erasure',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'DPDP 2023, Section 12(1): "The data principal shall have '
                  'the right to erasure of personal data."',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _requestErasure,
                  icon: const Icon(Icons.add),
                  label: const Text('New Erasure Request'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_erasureRequests.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No pending erasure requests',
                style: TextStyle(color: Colors.grey))),
          ),
        for (final r in _erasureRequests) _erasureCard(r),
      ],
    );
  }

  Widget _erasureCard(Map<String, dynamic> r) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.red,
          child: Icon(Icons.delete_forever, color: Colors.white),
        ),
        title: Text('Patient: ${r['patient_id']}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reason: ${r['reason']}'),
            Text('Requested: ${r['requested_at']}',
                style: const TextStyle(fontSize: 11)),
          ],
        ),
        isThreeLine: true,
        trailing: ElevatedButton(
          onPressed: () => _executeErasure(r['id']?.toString() ?? ''),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Execute'),
        ),
      ),
    );
  }

  // ────────────── ANONYMIZATION TAB ──────────────

  Widget _anonTab() {
    if (_anonLog.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.visibility_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('No anonymization events yet'),
            const SizedBox(height: 4),
            Text('Records are anonymized after sync confirmation',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _runAnonymization,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Run Anonymization Now'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _anonLog.length,
      itemBuilder: (ctx, i) {
        final a = _anonLog[i];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.visibility_off, color: Colors.teal),
            title: Text('${a['table_name']} / ${a['record_id']}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fields: ${a['fields_anonymized']}',
                    style: const TextStyle(fontSize: 11)),
                Text('Time: ${a['anonymized_at']}',
                    style: const TextStyle(fontSize: 11)),
                Text('Trigger: ${a['triggered_by']}',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  /// Safely convert any dynamic value to bool (handles int, String, bool).
  static bool _toBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is int) return v == 1;
    if (v is String) return v == '1' || v.toLowerCase() == 'true';
    return false;
  }
}
