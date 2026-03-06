import 'package:flutter/material.dart';

import '../../core/services/audit_service.dart';

/// SAHI/BODH Audit Trail screen — view the tamper-evident event log
/// with chain verification and filtering.
class AuditTrailScreen extends StatefulWidget {
  const AuditTrailScreen({super.key});

  @override
  State<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends State<AuditTrailScreen> {
  final _audit = AuditService.instance;
  List<Map<String, dynamic>> _entries = [];
  Map<String, int> _stats = {};
  bool _isVerifying = false;
  bool? _chainValid;
  String? _filterType;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final entries = await _audit.getTrail(
      eventType: _filterType,
      limit: 100,
    );
    final stats = await _audit.getStats();
    if (mounted) {
      setState(() {
        _entries = entries;
        _stats = stats;
      });
    }
  }

  Future<void> _verifyChain() async {
    setState(() => _isVerifying = true);
    final valid = await _audit.verifyChain();
    if (mounted) {
      setState(() {
        _isVerifying = false;
        _chainValid = valid;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SAHI/BODH Audit Trail'),
        actions: [
          IconButton(
            icon: _isVerifying
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.verified_user),
            onPressed: _isVerifying ? null : _verifyChain,
            tooltip: 'Verify Chain Integrity',
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.indigo.shade50,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statChip('Total Events', '${_stats['total'] ?? 0}',
                        Icons.event_note),
                    _statChip(
                        'Event Types',
                        '${(_stats.length - 1).clamp(0, 999)}',
                        Icons.category),
                    _statChip(
                      'Chain',
                      _chainValid == null
                          ? 'Unverified'
                          : _chainValid!
                              ? 'Valid ✓'
                              : 'BROKEN ✗',
                      Icons.link,
                      color: _chainValid == null
                          ? Colors.grey
                          : _chainValid!
                              ? Colors.green
                              : Colors.red,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Filter chips
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _filterChip(null, 'All'),
                _filterChip(AuditService.patientCreate, 'Patient'),
                _filterChip(AuditService.screeningCancer, 'Cancer'),
                _filterChip(AuditService.screeningTb, 'TB'),
                _filterChip(AuditService.claimSubmit, 'Claims'),
                _filterChip(AuditService.syncPush, 'Sync'),
                _filterChip(AuditService.flRound, 'FL'),
                _filterChip(AuditService.meshSend, 'Mesh'),
                _filterChip(AuditService.fraudAlert, 'Fraud'),
                _filterChip(AuditService.keyExchange, 'PQC'),
              ],
            ),
          ),

          // Event list
          Expanded(
            child: _entries.isEmpty
                ? const Center(child: Text('No audit events recorded yet.'))
                : ListView.builder(
                    itemCount: _entries.length,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemBuilder: (_, i) => _buildEntryCard(_entries[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, IconData icon,
      {Color? color}) {
    return Column(
      children: [
        Icon(icon, color: color ?? Colors.indigo, size: 22),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color ?? Colors.indigo,
            )),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _filterChip(String? type, String label) {
    final selected = _filterType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) {
          setState(() => _filterType = type);
          _loadData();
        },
      ),
    );
  }

  Widget _buildEntryCard(Map<String, dynamic> entry) {
    final type = entry['event_type']?.toString() ?? '';
    final entityId = entry['entity_id']?.toString() ?? '';
    final hash = entry['bodh_hash']?.toString() ?? '';
    final ts = entry['timestamp']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ExpansionTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: _typeColor(type).withValues(alpha: 0.15),
          child: Icon(_typeIcon(type), size: 18, color: _typeColor(type)),
        ),
        title: Text(type.replaceAll('_', ' '),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(
          'Entity: ${entityId.length > 12 ? '${entityId.substring(0, 12)}…' : entityId}\n'
          'BODH: ${hash.length > 16 ? '${hash.substring(0, 16)}…' : hash}',
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        ),
        trailing: Text(
          _formatTimestamp(ts),
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('Full BODH Hash', hash),
                _detailRow('Previous Hash',
                    entry['prev_hash']?.toString() ?? ''),
                _detailRow('Actor', entry['actor']?.toString() ?? ''),
                _detailRow('Payload', entry['payload']?.toString() ?? ''),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(String ts) {
    final dt = DateTime.tryParse(ts);
    if (dt == null) return ts;
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  IconData _typeIcon(String type) {
    if (type.contains('PATIENT')) return Icons.person;
    if (type.contains('SCREENING')) return Icons.medical_services;
    if (type.contains('CLAIM')) return Icons.receipt;
    if (type.contains('SYNC')) return Icons.sync;
    if (type.contains('FL')) return Icons.model_training;
    if (type.contains('MESH')) return Icons.hub;
    if (type.contains('FRAUD')) return Icons.warning;
    if (type.contains('KEY')) return Icons.vpn_key;
    return Icons.event;
  }

  Color _typeColor(String type) {
    if (type.contains('PATIENT')) return Colors.blue;
    if (type.contains('SCREENING')) return Colors.teal;
    if (type.contains('CLAIM')) return Colors.green;
    if (type.contains('SYNC')) return Colors.orange;
    if (type.contains('FL')) return Colors.purple;
    if (type.contains('MESH')) return Colors.indigo;
    if (type.contains('FRAUD')) return Colors.red;
    if (type.contains('KEY')) return Colors.amber;
    return Colors.grey;
  }
}
