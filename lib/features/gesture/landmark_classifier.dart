/// Industry-level hand gesture classifier using 21 MediaPipe landmarks.
///
/// Gesture vocabulary:
///   OPEN_PALM   -> 5 fingers extended       -> "Go Back"
///   FIST        -> 0 fingers extended        -> "Home / Menu"
///   THUMBS_UP   -> only thumb extended       -> "Confirm"
///   POINTING    -> only index extended       -> directional select
///   PEACE       -> index + middle extended   -> "Next"
///   SWIPE_LEFT  -> wrist moves left rapidly  -> "Navigate Forward"
///   SWIPE_RIGHT -> wrist moves right rapidly -> "Navigate Back"
///   SCROLL_UP   -> pointing + hand moves up  -> "Scroll page up"
///   SCROLL_DOWN -> pointing + hand moves down-> "Scroll page down"
library;

enum HandGesture {
  openPalm,
  fist,
  thumbsUp,
  pointing,
  peace,
  swipeLeft,
  swipeRight,
  scrollUp,
  scrollDown,
  none;

  String get displayName {
    switch (this) {
      case openPalm:
        return '\uD83D\uDD90\uFE0F Open Palm';
      case fist:
        return '\u270A Fist';
      case thumbsUp:
        return '\uD83D\uDC4D Thumbs Up';
      case pointing:
        return '\uD83D\uDC46 Pointing';
      case peace:
        return '\u270C\uFE0F Peace';
      case swipeLeft:
        return '\uD83D\uDC48 Swipe Left';
      case swipeRight:
        return '\uD83D\uDC49 Swipe Right';
      case scrollUp:
        return '\u2B06\uFE0F Scroll Up';
      case scrollDown:
        return '\u2B07\uFE0F Scroll Down';
      case none:
        return '...';
    }
  }
}

class LandmarkClassifier {
  // ── Swipe detection ────────────────────────────────────────
  final List<_WristSample> _wristHistory = [];
  static const int _wristWindowSize = 12;
  static const double _swipeThresholdX = 0.12; // normalised [0..1]
  static const double _swipeThresholdY = 0.08; // easier vertical scroll
  static const int _swipeMinMs = 60;
  static const int _swipeMaxMs = 600;

  // ── Gesture stability filter ──────────────────────────────
  HandGesture _prevGesture = HandGesture.none;
  int _stableFrames = 0;
  static const int _requiredStableFrames = 2; // faster recognition

  // ── Cooldown ──────────────────────────────────────────────
  int _lastActionTime = 0;
  static const int _cooldownMs = 400; // faster for surgeons

  /// Classify current hand pose + motion into a [HandGesture].
  HandGesture classify(List<List<double>> lm) {
    if (lm.length != 21) return HandGesture.none;

    final now = DateTime.now().millisecondsSinceEpoch;
    _wristHistory.add(_WristSample(lm[0][0], lm[0][1], now));
    if (_wristHistory.length > _wristWindowSize) _wristHistory.removeAt(0);

    if (now - _lastActionTime < _cooldownMs) return HandGesture.none;

    // 1. Horizontal swipe (highest priority)
    final hSwipe = _detectHorizontalSwipe();
    if (hSwipe != HandGesture.none) {
      _wristHistory.clear();
      _lastActionTime = now;
      return hSwipe;
    }

    // 2. Check finger states
    final fingers = _fingerStates(lm);
    final ext = fingers.where((f) => f).length;

    // 3. If pointing (only index), check vertical scroll
    if (ext == 1 && fingers[1]) {
      final vScroll = _detectVerticalSwipe();
      if (vScroll != HandGesture.none) {
        _wristHistory.clear();
        _lastActionTime = now;
        return vScroll;
      }
    }

    // 4. Static pose classification
    HandGesture raw;
    if (ext == 5) {
      raw = HandGesture.openPalm;
    } else if (ext == 0) {
      raw = HandGesture.fist;
    } else if (ext == 1 && fingers[0]) {
      raw = HandGesture.thumbsUp;
    } else if (ext == 1 && fingers[1]) {
      raw = HandGesture.pointing;
    } else if (ext == 2 && fingers[1] && fingers[2]) {
      raw = HandGesture.peace;
    } else {
      raw = HandGesture.none;
    }

    if (raw == _prevGesture) {
      _stableFrames++;
    } else {
      _prevGesture = raw;
      _stableFrames = 1;
    }

    if (_stableFrames == _requiredStableFrames && raw != HandGesture.none) {
      _lastActionTime = now;
      _stableFrames = _requiredStableFrames + 1;
      return raw;
    }

    return HandGesture.none;
  }

  List<bool> fingerStatesRaw(List<List<double>> lm) =>
      lm.length == 21 ? _fingerStates(lm) : List.filled(5, false);

  void reset() {
    _wristHistory.clear();
    _prevGesture = HandGesture.none;
    _stableFrames = 0;
    _lastActionTime = 0;
  }

  List<bool> _fingerStates(List<List<double>> lm) {
    final wristX = lm[0][0];
    final idxMcpX = lm[5][0];
    final rightHand = wristX > idxMcpX;

    final thumbExt = rightHand ? lm[4][0] < lm[3][0] : lm[4][0] > lm[3][0];
    final indexExt = lm[8][1] < lm[6][1];
    final middleExt = lm[12][1] < lm[10][1];
    final ringExt = lm[16][1] < lm[14][1];
    final pinkyExt = lm[20][1] < lm[18][1];

    return [thumbExt, indexExt, middleExt, ringExt, pinkyExt];
  }

  HandGesture _detectHorizontalSwipe() {
    if (_wristHistory.length < 6) return HandGesture.none;
    final first = _wristHistory.first;
    final last = _wristHistory.last;
    final dt = last.t - first.t;
    if (dt < _swipeMinMs || dt > _swipeMaxMs) return HandGesture.none;
    final dx = last.x - first.x;
    if (dx.abs() < _swipeThresholdX) return HandGesture.none;
    final dy = (last.y - first.y).abs();
    if (dy > dx.abs() * 0.7) return HandGesture.none;
    return dx < 0 ? HandGesture.swipeLeft : HandGesture.swipeRight;
  }

  HandGesture _detectVerticalSwipe() {
    if (_wristHistory.length < 5) return HandGesture.none;
    final first = _wristHistory.first;
    final last = _wristHistory.last;
    final dt = last.t - first.t;
    if (dt < _swipeMinMs || dt > _swipeMaxMs) return HandGesture.none;
    final dy = last.y - first.y;
    if (dy.abs() < _swipeThresholdY) return HandGesture.none;
    final dx = (last.x - first.x).abs();
    if (dx > dy.abs() * 0.7) return HandGesture.none;
    return dy < 0 ? HandGesture.scrollUp : HandGesture.scrollDown;
  }
}

class _WristSample {
  final double x, y;
  final int t;
  _WristSample(this.x, this.y, this.t);
}
