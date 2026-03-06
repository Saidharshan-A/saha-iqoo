import 'package:flutter/material.dart';

import '../../core/services/mesh_engine.dart';

/// P2P Mesh Network screen — discover nearby SAHA devices and
/// share patient records offline via Kyber-768 encrypted channels.
class MeshNetworkScreen extends StatefulWidget {
  const MeshNetworkScreen({super.key});

  @override
  State<MeshNetworkScreen> createState() => _MeshNetworkScreenState();
}

class _MeshNetworkScreenState extends State<MeshNetworkScreen> {
  final _mesh = MeshEngine.instance;
  bool _isScanning = false;
  final _messages = <MeshMessage>[];

  @override
  void initState() {
    super.initState();
    _mesh.messages.listen((msg) {
      if (mounted) setState(() => _messages.insert(0, msg));
    });
    // Auto-load persisted peers so demo data appears immediately
    _loadPersistedPeers();
  }

  Future<void> _loadPersistedPeers() async {
    try {
      await _mesh.startDiscovery();
      // Give a moment for peers to load, then stop scanning
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _mesh.stopDiscovery();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final peers = _mesh.peers.values.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('P2P Mesh Network'),
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.stop : Icons.radar),
            onPressed: () async {
              if (_isScanning) {
                _mesh.stopDiscovery();
              } else {
                await _mesh.startDiscovery();
              }
              setState(() => _isScanning = !_isScanning);
            },
            tooltip: _isScanning ? 'Stop Scanning' : 'Start Scanning',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _isScanning
                ? Colors.blue.shade50
                : Colors.grey.shade100,
            child: Row(
              children: [
                Icon(
                  _isScanning ? Icons.wifi_tethering : Icons.wifi_off,
                  color: _isScanning ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isScanning
                            ? 'Scanning for nearby devices…'
                            : 'Mesh network inactive',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '${peers.length} peer(s) discovered · '
                        'Kyber-768 encrypted',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (_isScanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),

          // Peer list
          if (peers.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.devices, size: 20),
                  SizedBox(width: 8),
                  Text('Discovered Peers',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: ListView.builder(
                itemCount: peers.length,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemBuilder: (_, i) => _buildPeerTile(peers[i]),
              ),
            ),
          ],

          // Message log
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Icon(Icons.history, size: 20),
                SizedBox(width: 8),
                Text('Activity Log',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: _messages.isEmpty
                ? const Center(
                    child: Text('No activity yet. Start scanning to discover peers.'))
                : ListView.builder(
                    itemCount: _messages.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (_, i) => _buildMessageTile(_messages[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeerTile(MeshPeer peer) {
    final isConnected = peer.status == PeerStatus.connected;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isConnected ? Colors.green.shade100 : Colors.blue.shade50,
          child: Icon(
            isConnected ? Icons.link : Icons.device_hub,
            color: isConnected ? Colors.green : Colors.blue,
          ),
        ),
        title: Text(peer.deviceName),
        subtitle: Text(
          '${peer.status.name} · ${peer.signalStrength} dBm · '
          '${peer.sharedItems} shared',
        ),
        trailing: isConnected
            ? const Chip(
                label: Text('Connected', style: TextStyle(fontSize: 11)),
                backgroundColor: Colors.greenAccent,
              )
            : ElevatedButton(
                onPressed: () async {
                  await _mesh.connectToPeer(peer.id);
                  setState(() {});
                },
                child: const Text('Connect'),
              ),
      ),
    );
  }

  Widget _buildMessageTile(MeshMessage msg) {
    IconData icon;
    Color color;
    switch (msg.type) {
      case MeshMessageType.peerDiscovered:
        icon = Icons.person_add;
        color = Colors.blue;
        break;
      case MeshMessageType.connected:
        icon = Icons.link;
        color = Colors.green;
        break;
      case MeshMessageType.dataSent:
        icon = Icons.upload;
        color = Colors.orange;
        break;
      case MeshMessageType.dataReceived:
        icon = Icons.download;
        color = Colors.teal;
        break;
      default:
        icon = Icons.info;
        color = Colors.grey;
    }

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        msg.type.name,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        msg.payload.entries
            .map((e) => '${e.key}: ${e.value}')
            .join(', '),
        style: const TextStyle(fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${msg.timestamp.hour}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
    );
  }
}
