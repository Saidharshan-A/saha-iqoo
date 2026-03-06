import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/connectivity_service.dart';

/// A persistent banner at the top of every screen showing
/// ONLINE (green) or OFFLINE (red) status.
///
/// This is the visual centrepiece of the "Internet Kill-Switch" demo.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner>
    with SingleTickerProviderStateMixin {
  late bool _isOnline;
  StreamSubscription<bool>? _sub;
  late AnimationController _animCtrl;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    _sub = ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });

    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      color: _isOnline ? Colors.green.shade600 : Colors.red.shade700,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!_isOnline)
            FadeTransition(
              opacity: _animation,
              child: const Icon(Icons.wifi_off, size: 16, color: Colors.white),
            )
          else
            const Icon(Icons.wifi, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            _isOnline
                ? 'ONLINE — Data will sync automatically'
                : 'OFFLINE — All data saved locally & encrypted',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
