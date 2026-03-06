import 'package:flutter/material.dart';

import '../../features/federated/fl_manager.dart';

/// Alpha-Investing Federated Learning dashboard — shows FL round
/// history, sparsification stats, and allows triggering new rounds.
class FlDashboardScreen extends StatefulWidget {
  const FlDashboardScreen({super.key});

  @override
  State<FlDashboardScreen> createState() => _FlDashboardScreenState();
}

class _FlDashboardScreenState extends State<FlDashboardScreen> {
  final _fl = FlManager.instance;
  List<Map<String, dynamic>> _history = [];
  bool _isTraining = false;
  Map<String, dynamic>? _lastDelta;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      await _fl.loadPersistedHistory();
      final history = _fl.getTrainingHistory();
      if (mounted) setState(() => _history = history);
    } catch (e) {
      debugPrint('FL: loadHistory error: $e');
    }
  }

  Future<void> _runRound() async {
    setState(() => _isTraining = true);
    try {
      final delta = await _fl.runLocalTrainingRound(localSampleCount: 50);
      _loadHistory();
      if (mounted) {
        setState(() {
          _isTraining = false;
          _lastDelta = delta;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTraining = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('FL round failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _fl.alphaStats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Federated Learning'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Alpha-Investing Stats Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.model_training, color: Colors.purple),
                        const SizedBox(width: 8),
                        const Text('Alpha-Investing Stats',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const Divider(),
                    _statRow('Current Round', '${_fl.currentRound}'),
                    _statRow('Wealth (α budget)',
                        ((stats['wealth'] as double?)?.toStringAsFixed(4) ?? '0.0500')),
                    _statRow('Gradients Accepted', '${stats['accepted'] ?? 0}'),
                    _statRow('Gradients Rejected', '${stats['rejected'] ?? 0}'),
                    _statRow(
                      'Acceptance Rate',
                      '${(((stats['acceptanceRate'] as double?) ?? 0.0) * 100).toStringAsFixed(1)}%',
                    ),
                    _statRow('Estimated FDR',
                        ((stats['estimatedFDR'] as double?)?.toStringAsFixed(4) ?? '0.0000')),
                    _statRow('FWER',
                        ((stats['fwer'] as double?)?.toStringAsFixed(4) ?? '0.0000')),
                    _statRow('Rényi DP ε',
                        ((stats['renyiEpsilon'] as double?)?.toStringAsFixed(3) ?? '0.000')),
                    _statRow('DP Rounds', '${stats['dpRounds'] ?? 0}'),
                    _statRow('Convergence',
                        ((stats['convergenceScore'] as double?)?.toStringAsFixed(3) ?? '0.000')),
                    _statRow('Fairness Score',
                        ((stats['fairnessScore'] as double?)?.toStringAsFixed(3) ?? '1.000')),
                    _statRow('Data Quality',
                        ((stats['dataQualityScore'] as double?)?.toStringAsFixed(3) ?? '1.000')),
                    _statRow('Model', 'EfficientNetB0 (1280-dim features)'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Train button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isTraining ? null : _runRound,
                icon: _isTraining
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_isTraining
                    ? 'Training Round ${_fl.currentRound + 1}…'
                    : 'Run Local Training Round'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            // Last delta info
            if (_lastDelta != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.purple.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Last Training Round',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _statRow(
                          'Local Accuracy',
                          '${(((_lastDelta!['local_accuracy'] as double?) ?? ((_lastDelta!['accepted'] as int? ?? 0) / ((_lastDelta!['accepted'] as int? ?? 0) + (_lastDelta!['rejected'] as int? ?? 1)).clamp(1, 999999))) * 100).toStringAsFixed(1)}%'),
                      _statRow(
                          'Local Loss',
                          ((_lastDelta!['local_loss'] as double?) ??
                              (1.0 - (_lastDelta!['wealth'] as double? ?? 0.05)))
                              .toStringAsFixed(4)),
                      if (_lastDelta!['alpha_investing'] != null) ...[
                        _statRow(
                            'Sparsification',
                            '${(((_lastDelta!['alpha_investing'] as Map?)?['sparsity_ratio'] as double? ?? 0.0) * 100).toStringAsFixed(1)}% sparse'),
                        _statRow('Accepted',
                            '${(_lastDelta!['alpha_investing'] as Map?)?['accepted'] ?? 0}'),
                        _statRow('Rejected',
                            '${(_lastDelta!['alpha_investing'] as Map?)?['rejected'] ?? 0}'),
                      ] else ...[
                        _statRow('Gradients Accepted',
                            '${_lastDelta!['accepted'] ?? 0}'),
                        _statRow('Gradients Rejected',
                            '${_lastDelta!['rejected'] ?? 0}'),
                        _statRow('Wealth',
                            (_lastDelta!['wealth'] as double? ?? 0.0).toStringAsFixed(4)),
                        _statRow('FDR',
                            (_lastDelta!['fdr'] as double? ?? 0.0).toStringAsFixed(4)),
                        _statRow('Rényi ε',
                            (_lastDelta!['renyi_epsilon'] as double? ?? 0.0).toStringAsFixed(3)),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Training History
            const Text('Training History',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),

            if (_history.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No training rounds yet. Run a round to start.'),
                ),
              )
            else
              ..._history.map((entry) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.purple,
                        child: Icon(Icons.science, color: Colors.white, size: 18),
                      ),
                      title: Text(
                        entry['model_name']?.toString() ?? 'Unknown',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        'Samples: ${entry['local_samples']} · '
                        '${entry['created_at']?.toString().substring(0, 19) ?? ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Icon(
                        entry['is_synced'] == 1
                            ? Icons.cloud_done
                            : Icons.cloud_upload,
                        color: entry['is_synced'] == 1
                            ? Colors.green
                            : Colors.orange,
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
