import 'package:flutter/material.dart';

import '../../core/services/device_provisioning.dart';

/// Secure Device Provisioning screen — device enrollment, certificate
/// management, revocation, and lockdown controls.
class ProvisioningScreen extends StatefulWidget {
  const ProvisioningScreen({super.key});

  @override
  State<ProvisioningScreen> createState() => _ProvisioningScreenState();
}

class _ProvisioningScreenState extends State<ProvisioningScreen>
    with SingleTickerProviderStateMixin {
  final _prov = DeviceProvisioning.instance;
  late TabController _tabs;
  ProvisioningSummary? _summary;
  List<Map<String, dynamic>> _devices = [];
  List<Map<String, dynamic>> _lockdowns = [];
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
      await _prov.initialize();
      final summary = await _prov.getSummary();
      final devices = await _prov.getAllDevices();
      final lockdowns = await _prov.getLockdownEvents();
      if (mounted) {
        setState(() {
          _summary = summary;
          _devices = devices;
          _lockdowns = lockdowns;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enrollThisDevice() async {
    try {
      final deviceId = 'web-${DateTime.now().millisecondsSinceEpoch}';
      await _prov.enrollDevice(
        deviceId: deviceId,
        deviceName: 'SAHA Web Client',
        enrolledBy: 'admin',
        facilityCode: 'PHC-001',
        district: 'Demo District',
        state: 'Demo State',
        osInfo: 'Web Browser',
        appVersion: '1.0.0',
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device enrolled (pending approval)'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _approveDevice(String enrollmentId) async {
    try {
      await _prov.approveEnrollment(enrollmentId: enrollmentId, adminId: 'admin');
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device approved & certificate issued'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _revokeDevice(String deviceId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Device'),
        content: Text('Revoke device $deviceId?\nAll certificates will be invalidated.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _prov.revokeDevice(
        deviceId: deviceId,
        revokedBy: 'admin',
        reason: 'Administrative revocation',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _lockdownDevice(String deviceId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('LOCKDOWN Device'),
        content: Text(
            'Lockdown device $deviceId?\nThis will WIPE all local data and '
            'permanently disable the device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade900),
            child: const Text('LOCKDOWN'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _prov.lockdownDevice(
        deviceId: deviceId,
        reason: 'Administrative lockdown (stolen / compromised)',
        reportedBy: 'admin',
      );
      await _load();
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
        title: const Text('Device Provisioning'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.devices)),
            Tab(text: 'Devices', icon: Icon(Icons.phone_android)),
            Tab(text: 'Lockdowns', icon: Icon(Icons.lock)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _enrollThisDevice,
        icon: const Icon(Icons.add),
        label: const Text('Enroll Device'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [_overviewTab(), _devicesTab(), _lockdownsTab()],
            ),
    );
  }

  Widget _overviewTab() {
    final s = _summary;
    if (s == null) return const Center(child: Text('No data'));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.security, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text('Provisioning Summary',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            )),
                  ],
                ),
                const SizedBox(height: 12),
                _summaryRow('Total Devices', '${s.totalDevices}', Icons.devices),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _statCard('Active', s.activeDevices, Colors.green, Icons.check_circle),
        _statCard('Pending', s.pendingDevices, Colors.orange, Icons.hourglass_empty),
        _statCard('Revoked', s.revokedDevices, Colors.red, Icons.block),
        _statCard('Locked', s.lockedDevices, Colors.red.shade900, Icons.lock),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Certificates', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _summaryRow('Active', '${s.activeCertificates}', Icons.verified),
                _summaryRow('Expired', '${s.expiredCertificates}', Icons.timer_off),
                _summaryRow('Revoked', '${s.revokedCertificates}', Icons.cancel),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          color: Colors.red.shade50,
          child: ListTile(
            leading: const Icon(Icons.warning, color: Colors.red),
            title: Text('${s.lockdownEvents} lockdown events'),
            subtitle: const Text('Tap Lockdowns tab for details'),
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, int count, Color color, IconData icon) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.2),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        trailing: Text('$count', style: TextStyle(
          fontSize: 22, fontWeight: FontWeight.bold, color: color,
        )),
      ),
    );
  }

  Widget _summaryRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _devicesTab() {
    if (_devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.devices, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('No enrolled devices'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _enrollThisDevice,
              icon: const Icon(Icons.add),
              label: const Text('Enroll This Device'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _devices.length,
      itemBuilder: (ctx, i) {
        final d = _devices[i];
        final status = d['status'] as String? ?? 'unknown';
        final color = status == 'active'
            ? Colors.green
            : status == 'pending'
                ? Colors.orange
                : status == 'locked'
                    ? Colors.red.shade900
                    : Colors.red;

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.phone_android, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(d['device_name'] as String? ?? 'Unknown',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Chip(
                      label: Text(status.toUpperCase(),
                          style: TextStyle(fontSize: 10, color: color)),
                      backgroundColor: color.withValues(alpha: 0.1),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('ID: ${d['device_id'] ?? 'N/A'}',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                Text('Enrolled by: ${d['enrolled_by'] ?? 'N/A'}',
                    style: const TextStyle(fontSize: 11)),
                Text('Facility: ${d['facility_code'] ?? 'N/A'} | ${d['district'] ?? ''}, ${d['state'] ?? ''}',
                    style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (status == 'pending')
                      ElevatedButton.icon(
                        onPressed: () => _approveDevice(d['id']?.toString() ?? ''),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    if (status == 'active') ...[
                      OutlinedButton.icon(
                        onPressed: () => _revokeDevice(d['device_id']?.toString() ?? ''),
                        icon: const Icon(Icons.block, size: 16),
                        label: const Text('Revoke'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _lockdownDevice(d['device_id']?.toString() ?? ''),
                        icon: const Icon(Icons.lock, size: 16),
                        label: const Text('Lockdown'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade900),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _lockdownsTab() {
    if (_lockdowns.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield, size: 64, color: Colors.green.shade300),
            const SizedBox(height: 12),
            const Text('No lockdown events', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text('All devices are secure',
                style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _lockdowns.length,
      itemBuilder: (ctx, i) {
        final l = _lockdowns[i];
        return Card(
          color: Colors.red.shade50,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.red,
              child: Icon(
                _toBool(l['data_wiped'])
                    ? Icons.delete_forever
                    : Icons.lock,
                color: Colors.white,
              ),
            ),
            title: Text('Device: ${l['device_id']}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reason: ${l['trigger_reason']}'),
                Text('Time: ${l['triggered_at']}',
                    style: const TextStyle(fontSize: 11)),
                Text('Data wiped: ${_toBool(l['data_wiped']) ? 'YES' : 'NO'}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _toBool(l['data_wiped']) ? Colors.red : Colors.grey,
                    )),
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
