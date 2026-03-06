import 'dart:js_interop';

@JS('startHandTracking')
external void _jsStart();

@JS('stopHandTracking')
external void _jsStop();

@JS('getHandLandmarksJson')
external JSString _jsGetLandmarks();

@JS('getHandedness')
external JSString _jsGetHandedness();

@JS('isMediaPipeAvailable')
external JSBoolean _jsIsAvailable();

@JS('isHandTrackingActive')
external JSBoolean _jsIsActive();

/// Bridge to MediaPipe Hands running in the browser.
class MediaPipeBridge {
  MediaPipeBridge._();
  static final instance = MediaPipeBridge._();

  bool get isAvailable {
    try {
      return _jsIsAvailable().toDart;
    } catch (_) {
      return false;
    }
  }

  bool get isActive {
    try {
      return _jsIsActive().toDart;
    } catch (_) {
      return false;
    }
  }

  void start() {
    try {
      _jsStart();
    } catch (_) {}
  }

  void stop() {
    try {
      _jsStop();
    } catch (_) {}
  }

  String get handedness {
    try {
      return _jsGetHandedness().toDart;
    } catch (_) {
      return '';
    }
  }

  /// Returns 21 landmarks as `List<[x, y, z]>`, or `null` if no hand.
  List<List<double>>? getLandmarks() {
    try {
      final csv = _jsGetLandmarks().toDart;
      if (csv.isEmpty) return null;

      final parts = csv.split(',');
      if (parts.length != 63) return null;

      final landmarks = <List<double>>[];
      for (var i = 0; i < 63; i += 3) {
        landmarks.add([
          double.parse(parts[i]),
          double.parse(parts[i + 1]),
          double.parse(parts[i + 2]),
        ]);
      }
      return landmarks;
    } catch (_) {
      return null;
    }
  }
}
