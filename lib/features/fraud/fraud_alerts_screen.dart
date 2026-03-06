import 'package:flutter/material.dart';

import '../../core/services/nafu_lite.dart';

/// NAFU-Lite Fraud Alerts screen — view and manage anti-fraud
/// anomaly detections from the Neural Anti-Fraud Unit.
class FraudAlertsScreen extends StatefulWidget {
  const FraudAlertsScreen({super.key});

  @override
  State<FraudAlertsScreen> createState() => _FraudAlertsScreenState();
}

class _FraudAlertsScreenState extends State<FraudAlertsScreen> {
  List<Map<String, dynamic>> _alerts = [];
  Map<String, dynamic> _stats = {};

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final alerts = await NafuLite.instance.getActiveAlerts();
      final stats = await NafuLite.instance.getStats();
      if (mounted) {
        setState(() {
          _alerts = alerts;
          _stats = stats;
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
        title: const Text('NAFU-Lite Fraud Alerts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Stats header
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.red.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat(
                  'Active',
                  '${_stats['activeAlerts'] ?? 0}',
                  Colors.red,
                  Icons.warning,
                ),
                _buildStat(
                  'Total',
                  '${_stats['totalAlerts'] ?? 0}',
                  Colors.orange,
                  Icons.security,
                ),
                _buildStat(
                  'Avg Risk',
                  '${((_stats['avgRiskScore'] as num? ?? 0).toDouble() * 100).toStringAsFixed(0)}%',
                  Colors.amber.shade800,
                  Icons.analytics,
                ),
              ],
            ),
          ),

          // Alert list
          Expanded(
            child: _alerts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield, size: 64, color: Colors.green.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'No active fraud alerts',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'NAFU-Lite is monitoring all submissions',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _alerts.length,
                    padding: const EdgeInsets.all(12),
                    itemBuilder: (_, i) => _buildAlertCard(_alerts[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            )),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final risk = (alert['risk_score'] as num?)?.toDouble() ?? 0;
    final type = alert['alert_type']?.toString() ?? '';
    final details = alert['details']?.toString() ?? '';
    final createdAt = alert['created_at']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: risk >= 0.8
          ? Colors.red.shade50
          : risk >= 0.5
              ? Colors.orange.shade50
              : Colors.yellow.shade50,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: risk >= 0.8
              ? Colors.red
              : risk >= 0.5
                  ? Colors.orange
                  : Colors.amber,
          child: Text(
            '${(risk * 100).round()}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        title: Text(
          type.replaceAll('_', ' '),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              details,
              style: const TextStyle(fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (createdAt.isNotEmpty)
              Text(
                createdAt.length >= 16 ? createdAt.substring(0, 16) : createdAt,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.check_circle_outline),
          onPressed: () async {
            final id = alert['id']?.toString();
            if (id != null) {
              await NafuLite.instance.dismissAlert(id);
              _loadData();
            }
          },
          tooltip: 'Dismiss',
        ),
      ),
    );
  }
}
