import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Indian Government themed splash/loading screen for SAHA.
///
/// Features:
///   • Tricolour gradient (Saffron → White → Green)
///   • Ashoka Chakra spinner
///   • NHA / ABDM / Digital India branding
///   • "Sovereign Autonomous Health Architecture" tagline
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  /// Called when splash animation completes — navigate to home.
  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _chakraCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeIn;
  late AnimationController _progressCtrl;

  // Indian flag colours
  static const Color _saffron = Color(0xFFFF9933);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _green = Color(0xFF138808);
  static const Color _navyBlue = Color(0xFF000080);

  @override
  void initState() {
    super.initState();

    _chakraCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeIn = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();

    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _progressCtrl.forward();

    // Transition after 3.5 seconds
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _chakraCtrl.dispose();
    _fadeCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _saffron,
              Color(0xFFFFC285), // light saffron
              _white,
              _white,
              Color(0xFFA8E6A1), // light green
              _green,
            ],
            stops: [0.0, 0.15, 0.30, 0.70, 0.85, 1.0],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeIn,
            child: Column(
              children: [
                const SizedBox(height: 30),

                // ── Government Header Bar ─────────────────────
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(220),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _navyBlue.withAlpha(50)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(15),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Emblem representation
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: _navyBlue, width: 2),
                            ),
                            child: const Icon(
                              Icons.account_balance,
                              size: 20,
                              color: _navyBlue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Government of India',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _navyBlue,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                'Ministry of Health & Family Welfare',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF444444),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildBadge('NHA', _saffron),
                          const SizedBox(width: 8),
                          _buildBadge('ABDM', _green),
                          const SizedBox(width: 8),
                          _buildBadge('Digital India', _navyBlue),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                // ── Ashoka Chakra (spinning) ──────────────────
                AnimatedBuilder(
                  animation: _chakraCtrl,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _chakraCtrl.value * 2 * math.pi,
                      child: child,
                    );
                  },
                  child: CustomPaint(
                    size: const Size(120, 120),
                    painter: _AshokaChakraPainter(),
                  ),
                ),

                const SizedBox(height: 24),

                // ── SAHA Title ────────────────────────────────
                const Text(
                  'S.A.H.A.',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: _navyBlue,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  decoration: BoxDecoration(
                    color: _navyBlue.withAlpha(15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Sovereign Autonomous Health Architecture',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333366),
                      letterSpacing: 0.8,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Tagline ───────────────────────────────────
                const Text(
                  'AI-Powered Healthcare for Every Indian',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF555555),
                  ),
                ),

                const Spacer(flex: 2),

                // ── Loading Progress ──────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 60),
                  child: Column(
                    children: [
                      AnimatedBuilder(
                        animation: _progressCtrl,
                        builder: (context, _) {
                          return Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _progressCtrl.value,
                                  minHeight: 6,
                                  backgroundColor: _navyBlue.withAlpha(30),
                                  valueColor:
                                      const AlwaysStoppedAnimation(_navyBlue),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _loadingText(_progressCtrl.value),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF666666),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // ── Footer ────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 30,
                            height: 3,
                            color: _saffron,
                          ),
                          Container(
                            width: 30,
                            height: 3,
                            color: _white,
                          ),
                          Container(
                            width: 30,
                            height: 3,
                            color: _green,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Made in India  •  Made for Bharat',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF888888),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Offline-First  •  Privacy-First  •  India-First',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _loadingText(double progress) {
    if (progress < 0.2) return 'Initializing secure database…';
    if (progress < 0.4) return 'Loading AI models…';
    if (progress < 0.6) return 'Configuring offline services…';
    if (progress < 0.8) return 'Verifying model governance…';
    return 'Ready to serve Bharat ✓';
  }
}

// ═════════════════════════════════════════════════════════════════
//  Ashoka Chakra Painter
// ═════════════════════════════════════════════════════════════════

class _AshokaChakraPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const navyBlue = Color(0xFF000080);

    // Outer circle
    final circlePaint = Paint()
      ..color = navyBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(center, radius - 2, circlePaint);

    // Inner circle
    canvas.drawCircle(center, radius * 0.2, circlePaint);

    // 24 spokes
    final spokePaint = Paint()
      ..color = navyBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (int i = 0; i < 24; i++) {
      final angle = (i * 15.0) * math.pi / 180.0;
      final inner = Offset(
        center.dx + radius * 0.22 * math.cos(angle),
        center.dy + radius * 0.22 * math.sin(angle),
      );
      final outer = Offset(
        center.dx + (radius - 4) * math.cos(angle),
        center.dy + (radius - 4) * math.sin(angle),
      );
      canvas.drawLine(inner, outer, spokePaint);
    }

    // 24 small circles between spokes (at outer rim)
    final dotPaint = Paint()
      ..color = navyBlue
      ..style = PaintingStyle.fill;
    for (int i = 0; i < 24; i++) {
      final angle = ((i * 15.0) + 7.5) * math.pi / 180.0;
      final pos = Offset(
        center.dx + (radius - 10) * math.cos(angle),
        center.dy + (radius - 10) * math.sin(angle),
      );
      canvas.drawCircle(pos, 2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
