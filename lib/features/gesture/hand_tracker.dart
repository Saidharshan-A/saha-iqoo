import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/utils/logger.dart';
import 'landmark_classifier.dart';
import 'mediapipe_bridge.dart';

/// Hand gesture tracking — MediaPipe Hands + keyboard fallback.
class HandTracker {
  HandTracker._();
  static final HandTracker instance = HandTracker._();
  static const _tag = 'HandTracker';

  bool _isTracking = false;
  bool get isTracking => _isTracking;

  bool _sterileMode = false;
  bool get isSterileMode => _sterileMode;

  Function(GestureType)? _onGesture;
  Function(bool)? _onSterileModeChanged;
  Function(HandGesture, List<bool>)? _onLandmarkGesture;

  Timer? _pollTimer;
  final _classifier = LandmarkClassifier();

  Future<void> startTracking({
    required Function(GestureType) onGesture,
    Function(bool)? onSterileModeChanged,
    Function(HandGesture, List<bool>)? onLandmarkGesture,
  }) async {
    if (_isTracking) return;
    _isTracking = true;
    _onGesture = onGesture;
    _onSterileModeChanged = onSterileModeChanged;
    _onLandmarkGesture = onLandmarkGesture;
    Log.i('HandTracker started', tag: _tag);
  }

  void toggleSterileMode() {
    _sterileMode = !_sterileMode;
    _onSterileModeChanged?.call(_sterileMode);
    Log.i('Sterile mode ${_sterileMode ? "ON" : "OFF"}', tag: _tag);
    if (_sterileMode) {
      _startMediaPipe();
    } else {
      _stopMediaPipe();
    }
  }

  Future<void> stopTracking() async {
    _isTracking = false;
    _stopMediaPipe();
    _onGesture = null;
    _onSterileModeChanged = null;
    _onLandmarkGesture = null;
    Log.i('HandTracker stopped', tag: _tag);
  }

  void dispose() => stopTracking();

  // ── MediaPipe ─────────────────────────────────────────────

  void _startMediaPipe() {
    final bridge = MediaPipeBridge.instance;
    if (!bridge.isAvailable) {
      Log.w('MediaPipe not available — buttons/keyboard only', tag: _tag);
      return;
    }
    bridge.start();
    _classifier.reset();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => _pollLandmarks(),
    );
    Log.i('MediaPipe camera started', tag: _tag);
  }

  void _stopMediaPipe() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _classifier.reset();
    try {
      MediaPipeBridge.instance.stop();
    } catch (_) {}
  }

  void _pollLandmarks() {
    if (!_isTracking || !_sterileMode) return;

    final lm = MediaPipeBridge.instance.getLandmarks();
    if (lm == null) {
      _onLandmarkGesture?.call(HandGesture.none, List.filled(5, false));
      return;
    }

    final fingers = _classifier.fingerStatesRaw(lm);
    final gesture = _classifier.classify(lm);
    _onLandmarkGesture?.call(gesture, fingers);

    if (gesture == HandGesture.none) return;

    switch (gesture) {
      case HandGesture.openPalm:
        _emit(GestureType.openPalm);
        break;
      case HandGesture.fist:
        _emit(GestureType.fist);
        break;
      case HandGesture.thumbsUp:
        _emit(GestureType.thumbsUp);
        break;
      case HandGesture.peace:
        _emit(GestureType.swipeLeft);
        break;
      case HandGesture.pointing:
        _emit(GestureType.thumbsUp);
        break;
      case HandGesture.swipeLeft:
        _emit(GestureType.swipeLeft);
        break;
      case HandGesture.swipeRight:
        _emit(GestureType.swipeRight);
        break;
      case HandGesture.scrollUp:
        _emit(GestureType.scrollUp);
        break;
      case HandGesture.scrollDown:
        _emit(GestureType.scrollDown);
        break;
      case HandGesture.none:
        break;
    }
  }

  void _emit(GestureType g) => _onGesture?.call(g);

  // ── Keyboard ──────────────────────────────────────────────

  bool handleKeyEvent(KeyEvent event) {
    if (!_isTracking) return false;
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.keyS) {
      toggleSterileMode();
      return true;
    }
    if (!_sterileMode) return false;

    if (key == LogicalKeyboardKey.arrowLeft) {
      _emit(GestureType.swipeLeft);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _emit(GestureType.swipeRight);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _emit(GestureType.scrollUp);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _emit(GestureType.scrollDown);
      return true;
    }
    if (key == LogicalKeyboardKey.enter) {
      _emit(GestureType.thumbsUp);
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      _emit(GestureType.openPalm);
      return true;
    }
    if (key == LogicalKeyboardKey.keyH ||
        key == LogicalKeyboardKey.home) {
      _emit(GestureType.fist);
      return true;
    }
    return false;
  }
}

/// App-level gesture types emitted by HandTracker.
enum GestureType {
  swipeLeft,
  swipeRight,
  thumbsUp,
  openPalm,
  fist,
  scrollUp,
  scrollDown,
  unknown,
}
