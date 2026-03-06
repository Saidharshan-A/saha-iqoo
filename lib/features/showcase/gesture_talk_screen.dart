import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Showcase page for the GestureTalk project.
///
/// Displays project description, key features, tech stack,
/// and a link to the GitHub repository.
class GestureTalkScreen extends StatelessWidget {
  const GestureTalkScreen({super.key});

  static const _repoUrl =
      'https://github.com/Benedictpatrick/Gesturetalk.git';

  Future<void> _openRepo() async {
    final uri = Uri.parse(_repoUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Hero App Bar ───────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'GestureTalk',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF7B1FA2),
                      Color(0xFF9C27B0),
                      Color(0xFFCE93D8),
                    ],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(40),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.sign_language,
                          size: 56,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sign Language → Speech',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white70,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Body ───────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Description
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: theme.colorScheme.primary),
                            const SizedBox(width: 10),
                            Text('About',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'GestureTalk is a real-time sign language recognition '
                          'system that bridges the communication gap between '
                          'deaf/mute individuals and the hearing world. It uses '
                          'MediaPipe hand tracking and machine learning to convert '
                          'hand gestures into spoken words instantly.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.6,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Key Features
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.star_outline,
                                color: Colors.amber.shade700),
                            const SizedBox(width: 10),
                            Text('Key Features',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _FeatureItem(
                          icon: Icons.back_hand,
                          title: 'Real-Time Hand Tracking',
                          description:
                              'MediaPipe-powered 21-point hand landmark detection',
                        ),
                        _FeatureItem(
                          icon: Icons.record_voice_over,
                          title: 'Text-to-Speech Output',
                          description:
                              'Instantly converts recognized gestures to spoken audio',
                        ),
                        _FeatureItem(
                          icon: Icons.psychology,
                          title: 'ML Classification',
                          description:
                              'Trained CNN model for accurate gesture recognition',
                        ),
                        _FeatureItem(
                          icon: Icons.accessibility_new,
                          title: 'Accessibility First',
                          description:
                              'Designed for ease of use by differently-abled users',
                        ),
                        _FeatureItem(
                          icon: Icons.wifi_off,
                          title: 'Offline Capable',
                          description:
                              'All inference runs on-device — no internet needed',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Tech Stack
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.code,
                                color: Colors.deepPurple.shade400),
                            const SizedBox(width: 10),
                            Text('Tech Stack',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: const [
                            _TechChip(
                                label: 'MediaPipe', color: Color(0xFF0097A7)),
                            _TechChip(
                                label: 'TensorFlow', color: Color(0xFFFF6F00)),
                            _TechChip(
                                label: 'Python', color: Color(0xFF306998)),
                            _TechChip(
                                label: 'Flutter', color: Color(0xFF0175C2)),
                            _TechChip(
                                label: 'OpenCV', color: Color(0xFF5C6BC0)),
                            _TechChip(
                                label: 'TTS Engine', color: Color(0xFF7B1FA2)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // SAHA Integration
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  color: const Color(0xFF7B1FA2).withAlpha(15),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.link, color: Color(0xFF7B1FA2)),
                            const SizedBox(width: 10),
                            Text('SAHA Integration',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF7B1FA2),
                                )),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'GestureTalk powers the gesture-based navigation in SAHA, '
                          'allowing healthcare workers to control the app hands-free '
                          'during clinical procedures. Swipe, pinch, and point gestures '
                          'map to navigation and UI actions.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.6,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // GitHub Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _openRepo,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text(
                      'View on GitHub',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7B1FA2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helper Widgets ───────────────────────────────────────────

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF7B1FA2).withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF7B1FA2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TechChip extends StatelessWidget {
  const _TechChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
