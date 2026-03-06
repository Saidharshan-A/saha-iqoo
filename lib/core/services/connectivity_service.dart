import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../utils/logger.dart';

/// Reactive service that tracks network connectivity state.
///
/// Exposes a [Stream<bool>] and a synchronous getter [isOnline]
/// so the rest of the app can branch on connectivity without
/// caring about the underlying platform details.
class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  bool _isOnline = false;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// Current connectivity state (synchronous).
  bool get isOnline => _isOnline;

  /// Reactive stream of connectivity changes.
  Stream<bool> get onConnectivityChanged => _controller.stream;

  /// Call once at app startup.
  Future<void> init() async {
    final results = await _connectivity.checkConnectivity();
    _update(results);

    _sub = _connectivity.onConnectivityChanged.listen(_update);
    Log.i(
      'ConnectivityService initialised – online=$_isOnline',
      tag: 'Connectivity',
    );
  }

  void _update(List<ConnectivityResult> results) {
    final online = results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet);

    if (online != _isOnline) {
      _isOnline = online;
      _controller.add(_isOnline);
      Log.i(
        'Connectivity changed → ${_isOnline ? "ONLINE" : "OFFLINE"}',
        tag: 'Connectivity',
      );
    }
  }

  /// Clean up (e.g. in tests).
  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
