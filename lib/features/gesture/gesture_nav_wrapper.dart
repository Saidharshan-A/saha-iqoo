import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;

import '../../app/routes.dart';
import '../../features/voice/bhashini_service.dart';
import 'hand_tracker.dart';
import 'landmark_classifier.dart';

/// Gesture Navigation Wrapper — surgeon-grade sterile mode HUD.
///
/// **Normal mode**: child renders untouched (zero interference).
/// **Sterile mode**: content stays FULLY VISIBLE and INTERACTIVE.
///   - Animated pulsing green glow border
///   - Translucent top HUD with live finger dots + gesture name
///   - Floating side action panel (scroll, back, home, ok, next)
///   - Gesture scroll via point-and-move
///   - Animated ripple on gesture recognition
///   - Session timer, hand detection indicator
class GestureNavWrapper extends StatefulWidget {
  final Widget child;

  const GestureNavWrapper({super.key, required this.child});

  @override
  State<GestureNavWrapper> createState() => _GestureNavWrapperState();
}

class _GestureNavWrapperState extends State<GestureNavWrapper>
    with TickerProviderStateMixin {
  bool _showGestureHint = false;
  String _gestureHint = '';
  String _gestureIcon = '';
  bool _sterileMode = false;

  // Live MediaPipe state
  HandGesture _currentGesture = HandGesture.none;
  List<bool> _fingerStates = List.filled(5, false);
  bool _handDetected = false;

  // Session timer
  DateTime? _sterileStartTime;
  Timer? _sessionTimer;
  Duration _sessionDuration = Duration.zero;

  // Animations
  late AnimationController _borderGlowCtrl;
  late Animation<double> _borderGlow;
  late AnimationController _rippleCtrl;
  late Animation<double> _ripple;
  bool _showRipple = false;

  @override
  void initState() {
    super.initState();

    _borderGlowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _borderGlow = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _borderGlowCtrl, curve: Curves.easeInOut),
    );

    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _ripple = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOut),
    );
    _rippleCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _showRipple = false);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      HardwareKeyboard.instance.addHandler(_onKey);
      HandTracker.instance.startTracking(
        onGesture: _handleGesture,
        onSterileModeChanged: _onSterileModeChanged,
        onLandmarkGesture: _onLandmarkGesture,
      );
    });
  }

  @override
  void dispose() {
    _borderGlowCtrl.dispose();
    _rippleCtrl.dispose();
    _sessionTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    HandTracker.instance.stopTracking();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    // Don't intercept keyboard when a text field has focus — lets the
    // user type freely (e.g. patient name, search box).
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus.context != null) {
      final widget = focus.context!.widget;
      if (widget is EditableText) return false;
    }
    return HandTracker.instance.handleKeyEvent(event);
  }

  void _onSterileModeChanged(bool active) {
    if (!mounted) return;
    setState(() => _sterileMode = active);
    if (active) {
      _sterileStartTime = DateTime.now();
      _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _sterileMode) {
          setState(() {
            _sessionDuration =
                DateTime.now().difference(_sterileStartTime!);
          });
        }
      });
    } else {
      _sessionTimer?.cancel();
      _sterileStartTime = null;
      _sessionDuration = Duration.zero;
    }
    _speakIfSterile(
        active ? 'Sterile mode activated' : 'Sterile mode off');
  }

  void _onLandmarkGesture(HandGesture gesture, List<bool> fingers) {
    if (!mounted) return;
    setState(() {
      _currentGesture = gesture;
      _fingerStates = fingers;
      _handDetected = fingers.any((f) => f);
    });
  }

  void _speakIfSterile(String text) {
    if (_sterileMode || text.contains('Sterile')) {
      try {
        BhashiniService.instance.speak(text);
      } catch (_) {}
    }
  }

  // ─────────────────────────────────────────────────────────
  // Gesture handling
  // ─────────────────────────────────────────────────────────

  void _handleGesture(GestureType gesture) {
    switch (gesture) {
      case GestureType.swipeLeft:
        _showAction('\u2192 Next', '\uD83D\uDC49');
        _speakIfSterile('Next');
        _navigateForward();
        break;
      case GestureType.swipeRight:
        _showAction('\u2190 Back', '\uD83D\uDC48');
        _speakIfSterile('Back');
        _navigateBack();
        break;
      case GestureType.thumbsUp:
        _showAction('\u2713 Confirmed', '\uD83D\uDC4D');
        _speakIfSterile('Confirmed');
        break;
      case GestureType.openPalm:
        _showAction('\u2B05 Back', '\u270B');
        _speakIfSterile('Go back');
        _navigateBack();
        break;
      case GestureType.fist:
        _showAction('\u2302 Home', '\u270A');
        _speakIfSterile('Home');
        _navigateHome();
        break;
      case GestureType.scrollUp:
        _scrollPage(-180);
        break;
      case GestureType.scrollDown:
        _scrollPage(180);
        break;
      case GestureType.unknown:
        break;
    }
  }

  void _scrollPage(double delta) {
    try {
      final sc = PrimaryScrollController.maybeOf(context);
      if (sc != null && sc.hasClients) {
        final target = (sc.offset + delta).clamp(
          sc.position.minScrollExtent,
          sc.position.maxScrollExtent,
        );
        sc.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } catch (_) {}
    if (delta < 0) {
      _showAction('\u2B06 Scroll Up', '\u261D\uFE0F');
    } else {
      _showAction('\u2B07 Scroll Down', '\u261D\uFE0F');
    }
  }

  void _navigateForward() => appRouter.push('/patients');
  void _navigateBack() {
    if (appRouter.canPop()) appRouter.pop();
  }

  void _navigateHome() => appRouter.go('/');

  void _showAction(String hint, String icon) {
    setState(() {
      _gestureHint = hint;
      _gestureIcon = icon;
      _showGestureHint = true;
      _showRipple = true;
    });
    _rippleCtrl.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _showGestureHint = false);
    });
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ─────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final h = MediaQuery.of(context).size.height;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Child always visible and interactive ──────────
        widget.child,

        if (_sterileMode) ...[
          // ── Animated pulsing glow border ────────────────
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _borderGlow,
              builder: (_, __) => Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.greenAccent
                        .withValues(alpha: _borderGlow.value * 0.85),
                    width: 3,
                  ),
                ),
              ),
            ),
          ),

          // Inner glow effect
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _borderGlow,
              builder: (_, __) => Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.2,
                    colors: [
                      Colors.transparent,
                      Colors.greenAccent
                          .withValues(alpha: _borderGlow.value * 0.06),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Top HUD Strip ──────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: pad.top + 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                  ),
                ),
                padding: EdgeInsets.only(
                    top: pad.top + 6, left: 12, right: 12),
                child: Row(
                  children: [
                    // Sterile badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade900
                            .withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color:
                              Colors.greenAccent.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Pulsing detection dot
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _handDetected
                                  ? Colors.greenAccent
                                  : Colors.grey,
                              shape: BoxShape.circle,
                              boxShadow: _handDetected
                                  ? [
                                      BoxShadow(
                                        color: Colors.greenAccent
                                            .withValues(alpha: 0.6),
                                        blurRadius: 6,
                                      ),
                                    ]
                                  : [],
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'STERILE',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Finger dots
                    ..._buildFingerDots(),
                    const Spacer(),
                    // Gesture name
                    if (_currentGesture != HandGesture.none)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade900
                              .withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _currentGesture.displayName,
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    // Session timer
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _fmtDuration(_sessionDuration),
                        style: TextStyle(
                          color:
                              Colors.greenAccent.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Right-side floating action panel ────────────
          Positioned(
            right: 6,
            top: h * 0.18,
            child: Column(
              children: [
                _FloatingBtn(
                  icon: Icons.keyboard_arrow_up,
                  label: 'UP',
                  color: Colors.cyanAccent,
                  onTap: () => _scrollPage(-200),
                ),
                const SizedBox(height: 5),
                _FloatingBtn(
                  icon: Icons.arrow_back_rounded,
                  label: 'BACK',
                  color: Colors.orangeAccent,
                  onTap: () {
                    _speakIfSterile('Back');
                    _navigateBack();
                  },
                ),
                const SizedBox(height: 5),
                _FloatingBtn(
                  icon: Icons.home_rounded,
                  label: 'HOME',
                  color: Colors.lightBlueAccent,
                  onTap: () {
                    _speakIfSterile('Home');
                    _navigateHome();
                  },
                ),
                const SizedBox(height: 5),
                _FloatingBtn(
                  icon: Icons.check_circle_outline,
                  label: 'OK',
                  color: Colors.greenAccent,
                  onTap: () {
                    _speakIfSterile('Confirmed');
                    _showAction('\u2713 OK', '\uD83D\uDC4D');
                  },
                ),
                const SizedBox(height: 5),
                _FloatingBtn(
                  icon: Icons.arrow_forward_rounded,
                  label: 'NEXT',
                  color: Colors.tealAccent,
                  onTap: () {
                    _speakIfSterile('Next');
                    _navigateForward();
                  },
                ),
                const SizedBox(height: 5),
                _FloatingBtn(
                  icon: Icons.keyboard_arrow_down,
                  label: 'DOWN',
                  color: Colors.cyanAccent,
                  onTap: () => _scrollPage(200),
                ),
              ],
            ),
          ),

          // ── Center gesture ripple ──────────────────────
          if (_showRipple)
            Center(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _ripple,
                  builder: (_, __) {
                    final scale = 0.5 + _ripple.value * 0.5;
                    final opacity = 1.0 - _ripple.value;
                    return Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.greenAccent
                                .withValues(alpha: 0.12),
                            border: Border.all(
                              color: Colors.greenAccent
                                  .withValues(alpha: 0.5 * opacity),
                              width: 2.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _gestureIcon,
                            style: TextStyle(fontSize: 44 * scale),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // ── Center gesture hint ────────────────────────
          if (_showGestureHint)
            Positioned(
              top: h * 0.42,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _showGestureHint ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 26, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.greenAccent
                              .withValues(alpha: 0.35),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.greenAccent
                                .withValues(alpha: 0.15),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                      child: Text(
                        _gestureHint,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ── Bottom gesture guide ───────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                  ),
                ),
                padding: const EdgeInsets.only(
                    bottom: 10, top: 20, left: 12, right: 70),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _GuideChip(
                        emoji: '\u270B',
                        label: 'Palm\u2192Back',
                        color: Colors.orangeAccent),
                    _GuideChip(
                        emoji: '\u270A',
                        label: 'Fist\u2192Home',
                        color: Colors.lightBlueAccent),
                    _GuideChip(
                        emoji: '\uD83D\uDC4D',
                        label: 'Thumb\u2192OK',
                        color: Colors.greenAccent),
                    _GuideChip(
                        emoji: '\u270C\uFE0F',
                        label: 'Peace\u2192Next',
                        color: Colors.tealAccent),
                    _GuideChip(
                        emoji: '\u261D\uFE0F',
                        label: 'Point\u2192Scroll',
                        color: Colors.cyanAccent),
                  ],
                ),
              ),
            ),
          ),

          // ── EXIT pill button ───────────────────────────
          Positioned(
            top: pad.top + 50,
            right: 8,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () =>
                    HandTracker.instance.toggleSterileMode(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        Colors.red.shade900.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color:
                          Colors.redAccent.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'EXIT',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],

        // ── Floating toggle FAB (always visible) ─────────
        Positioned(
          bottom: _sterileMode ? 56 : 24,
          right: _sterileMode ? 64 : 16,
          child: Material(
            color: _sterileMode
                ? Colors.green.shade700
                : Colors.grey.shade800,
            shape: const CircleBorder(),
            elevation: 8,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () =>
                  HandTracker.instance.toggleSterileMode(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: _sterileMode ? 46 : 56,
                height: _sterileMode ? 46 : 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: _sterileMode
                      ? [
                          BoxShadow(
                            color: Colors.greenAccent
                                .withValues(alpha: 0.5),
                            blurRadius: 14,
                          ),
                        ]
                      : [],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _sterileMode
                          ? Icons.pan_tool
                          : Icons.pan_tool_alt,
                      color: Colors.white,
                      size: _sterileMode ? 18 : 24,
                    ),
                    if (!_sterileMode)
                      const Text(
                        'S',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildFingerDots() {
    const labels = ['T', 'I', 'M', 'R', 'P'];
    return List.generate(5, (i) {
      final ext = i < _fingerStates.length && _fingerStates[i];
      return Padding(
        padding: const EdgeInsets.only(right: 3),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: ext
                ? Colors.greenAccent.withValues(alpha: 0.85)
                : Colors.red.shade700.withValues(alpha: 0.6),
            shape: BoxShape.circle,
            border: Border.all(
              color: ext ? Colors.greenAccent : Colors.red.shade400,
              width: 1.5,
            ),
            boxShadow: ext
                ? [
                    BoxShadow(
                      color:
                          Colors.greenAccent.withValues(alpha: 0.4),
                      blurRadius: 4,
                    ),
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Text(
            labels[i],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    });
  }
}

// ── Floating side action button ──────────────────────────────

class _FloatingBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _FloatingBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 58,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 7,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom gesture guide chip ────────────────────────────────

class _GuideChip extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;

  const _GuideChip({
    required this.emoji,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
