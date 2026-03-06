import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Showcase page for the SmartTriage AI Hospital Optimization project.
///
/// Displays project description, key features, tech stack,
/// and a link to the GitHub repository.
class SmartTriageScreen extends StatelessWidget {
  const SmartTriageScreen({super.key});

  static const _repoUrl =
      'https://github.com/Benedictpatrick/SmartTriage-AI-Hospital-Optimization.git';

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
                'Smart Triage',
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
                      Color(0xFF00695C),
                      Color(0xFF00897B),
                      Color(0xFF80CBC4),
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
                          Icons.local_hospital,
                          size: 56,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'AI-Powered Hospital Optimization',
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
                          'SmartTriage uses artificial intelligence to optimize '
                          'hospital patient flow, reduce wait times, and improve '
                          'resource allocation. It provides intelligent triage '
                          'scoring, bed management, and predictive analytics for '
                          'hospital administrators and clinicians.',
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
                          icon: Icons.speed,
                          title: 'AI Triage Scoring',
                          description:
                              'ML-driven patient severity classification for faster treatment',
                        ),
                        _FeatureItem(
                          icon: Icons.bed,
                          title: 'Smart Bed Management',
                          description:
                              'Real-time bed availability and automatic assignment',
                        ),
                        _FeatureItem(
                          icon: Icons.timeline,
                          title: 'Predictive Analytics',
                          description:
                              'Forecast patient influx, discharge rates, and resource needs',
                        ),
                        _FeatureItem(
                          icon: Icons.schedule,
                          title: 'Wait Time Optimization',
                          description:
                              'Dynamic queue management reducing average wait by 40%',
                        ),
                        _FeatureItem(
                          icon: Icons.dashboard,
                          title: 'Admin Dashboard',
                          description:
                              'Live hospital KPIs, staff allocation, and capacity charts',
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
                            Icon(Icons.code, color: Colors.teal.shade400),
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
                                label: 'Python', color: Color(0xFF306998)),
                            _TechChip(
                                label: 'Scikit-learn',
                                color: Color(0xFFF7931E)),
                            _TechChip(
                                label: 'TensorFlow', color: Color(0xFFFF6F00)),
                            _TechChip(
                                label: 'Flask/FastAPI',
                                color: Color(0xFF00897B)),
                            _TechChip(
                                label: 'Pandas', color: Color(0xFF150458)),
                            _TechChip(
                                label: 'Plotly', color: Color(0xFF3F4F75)),
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
                  color: const Color(0xFF00695C).withAlpha(15),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.link, color: Color(0xFF00695C)),
                            const SizedBox(width: 10),
                            Text('SAHA Integration',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF00695C),
                                )),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'SmartTriage feeds into SAHA\'s risk stratification engine. '
                          'Patient severity scores from triage directly influence the '
                          '4-tier risk classification, enabling district health officers '
                          'to allocate resources where they\'re needed most.',
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
                      backgroundColor: const Color(0xFF00695C),
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
              color: const Color(0xFF00695C).withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF00695C)),
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
