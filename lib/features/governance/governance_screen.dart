import 'package:flutter/material.dart';

import '../../core/services/model_governance.dart';

/// Model Lifecycle Governance Screen — litigation-proof model version tracking,
/// checksum verification, signed updates, and rollback.
class GovernanceScreen extends StatefulWidget {
  const GovernanceScreen({super.key});

  @override
  State<GovernanceScreen> createState() => _GovernanceScreenState();
}

class _GovernanceScreenState extends State<GovernanceScreen> {
  final _gov = ModelGovernance.instance;
  List<ModelVersion> _versions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _gov.initialize();
      final versions = await _gov.getAllVersions();
      if (mounted) setState(() { _versions = versions; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _verifyChecksum(String modelName) async {
    try {
      final ok = await _gov.verifyChecksum(modelName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Checksum VALID' : 'Checksum FAILED'),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _rollback(ModelVersion v) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Rollback'),
        content: Text(
            'Rollback ${v.modelName} to version ${v.version}?\n'
            'This will deactivate the current version and reactivate v${v.version}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Rollback'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _gov.rollback(modelName: v.modelName, targetVersion: v.version, reason: 'Manual rollback from governance screen');
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rollback successful'), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rollback failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Governance'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    // Group versions by model name
    final grouped = <String, List<ModelVersion>>{};
    for (final v in _versions) {
      grouped.putIfAbsent(v.modelName, () => []).add(v);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary card
        Card(
          color: Colors.indigo.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield, color: Colors.indigo),
                    const SizedBox(width: 8),
                    Text('Model Lifecycle Governance',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            )),
                  ],
                ),
                const SizedBox(height: 8),
                Text('${_versions.length} model versions registered across '
                    '${grouped.keys.length} models'),
                Text('Active: ${_versions.where((v) => v.status == "active").length} | '
                    'Inactive: ${_versions.where((v) => v.status != "active").length}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Per-model sections
        for (final entry in grouped.entries) ...[
          Text(entry.key.replaceAll('_', ' ').toUpperCase(),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  )),
          const SizedBox(height: 8),
          for (final v in entry.value) _versionCard(v),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _versionCard(ModelVersion v) {
    final isActive = v.status == 'active';
    return Card(
      elevation: isActive ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isActive
            ? const BorderSide(color: Colors.green, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isActive ? Icons.check_circle : Icons.history,
                    color: isActive ? Colors.green : Colors.grey, size: 20),
                const SizedBox(width: 8),
                Text('Version ${v.version}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Chip(
                  label: Text(v.status.toUpperCase(),
                      style: const TextStyle(fontSize: 11)),
                  backgroundColor: isActive ? Colors.green.shade100 : Colors.grey.shade200,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _infoRow('Accuracy', '${((v.accuracy ?? 0) * 100).toStringAsFixed(2)}%'),
            _infoRow('Source', v.source),
            _infoRow('Checksum', '${v.checksum.substring(0, 16)}...'),
            _infoRow('Released', v.releasedAt),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _verifyChecksum(v.modelName),
                  icon: const Icon(Icons.fingerprint, size: 16),
                  label: const Text('Verify'),
                ),
                const SizedBox(width: 8),
                if (!isActive)
                  OutlinedButton.icon(
                    onPressed: () => _rollback(v),
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('Rollback'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
