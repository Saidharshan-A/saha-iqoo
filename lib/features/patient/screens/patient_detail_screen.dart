import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/services/abha_service.dart';
import '../../../core/services/nfc_patient_card_service.dart';
import '../../../core/utils/constants.dart';
import '../blocs/patient_bloc.dart';
import '../models/patient.dart';
import '../repos/patient_repo.dart';
import '../widgets/nfc_scan_dialog.dart';

/// Detailed patient view with ABHA linkage, screening history
/// shortcuts, and demographic information.
class PatientDetailScreen extends StatefulWidget {
  const PatientDetailScreen({super.key, required this.patientId});

  final String patientId;

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  Patient? _patient;
  String? _abhaNumber;
  List<Map<String, dynamic>> _screenings = [];
  bool _loading = true;
  bool _linkingAbha = false;
  bool _writingNfcCard = false;
  bool _nfcDialogOpen = false;

  final _repo = PatientRepository();
  final _abha = AbhaService();
  final _nfcCards = NfcPatientCardService.instance;

  @override
  void initState() {
    super.initState();
    _loadPatient();
  }

  Future<void> _loadPatient() async {
    final patient = await _repo.getPatientById(widget.patientId);
    String? abha;
    List<Map<String, dynamic>> screenings = [];
    if (patient != null) {
      abha = await _abha.getAbhaForPatient(patient.id);
      screenings = await _repo.getScreeningsForPatient(patient.id);
    }
    if (mounted) {
      setState(() {
        _patient = patient;
        _abhaNumber = abha;
        _screenings = screenings;
        _loading = false;
      });
    }
  }

  Future<void> _linkAbha() async {
    if (_patient == null) return;
    setState(() => _linkingAbha = true);
    try {
      final abha = await _abha.linkAbha(_patient!.id);
      if (mounted) {
        setState(() {
          _abhaNumber = abha;
          _linkingAbha = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ABHA $abha linked successfully!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _linkingAbha = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ABHA linking failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _writePatientCard() async {
    final patient = _patient;
    if (patient == null || _writingNfcCard) return;

    setState(() => _writingNfcCard = true);
    _nfcDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NfcScanDialog(
        title: 'Write SAHA Card',
        instruction: 'Hold the patient card against the back of the phone.',
        onCancel: () async {
          _nfcDialogOpen = false;
          await _nfcCards.cancel();
          if (mounted) Navigator.of(context, rootNavigator: true).pop();
        },
      ),
    );

    try {
      await _nfcCards.writeCard(
        NfcPatientCardData(
          patientId: patient.id,
          fullName: patient.fullName,
          age: patient.age,
          gender: patient.gender,
          aadhaarLast4: patient.aadhaarLast4,
          phone: patient.phone,
          village: patient.village,
          district: patient.district,
          state: patient.state,
        ),
      );
      _closeNfcDialog();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${patient.fullName}\'s NFC card is ready.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } on NfcPatientCardException catch (error) {
      _closeNfcDialog();
      if (mounted && !error.cancelled) _showNfcError(error.message);
    } catch (error) {
      _closeNfcDialog();
      if (mounted) _showNfcError('Could not write this card: $error');
    } finally {
      if (mounted) setState(() => _writingNfcCard = false);
    }
  }

  void _closeNfcDialog() {
    if (_nfcDialogOpen && mounted) {
      _nfcDialogOpen = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _showNfcError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Patient')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_patient == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Patient')),
        body: const Center(child: Text('Patient not found')),
      );
    }

    final p = _patient!;

    return Scaffold(
      appBar: AppBar(
        title: Text(p.fullName),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete patient',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete Patient?'),
                  content: Text('Remove ${p.fullName} from local records? '
                      'This cannot be undone.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                context.read<PatientBloc>().add(DeletePatient(p.id));
                context.pop();
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Profile Header ──────────────────────────────
            Center(
              child: CircleAvatar(
                radius: 44,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  p.fullName.isNotEmpty ? p.fullName[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(p.fullName,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Center(
              child: Text(
                '${p.age} years • ${p.gender}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
            const SizedBox(height: 8),

            // ── Sync Badge ──────────────────────────────────
            Center(
              child: Chip(
                avatar: Icon(
                  p.isSynced ? Icons.cloud_done : Icons.cloud_off,
                  size: 16,
                  color: p.isSynced ? Colors.green : Colors.orange,
                ),
                label: Text(p.isSynced ? 'Synced' : 'Pending Sync'),
                backgroundColor:
                    p.isSynced ? Colors.green.shade50 : Colors.orange.shade50,
              ),
            ),
            const SizedBox(height: 24),

            // ── ABHA Section ────────────────────────────────
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.borderRadius)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified_user, size: 20),
                        const SizedBox(width: 8),
                        Text('ABHA Health ID',
                            style: theme.textTheme.titleSmall),
                      ],
                    ),
                    const Divider(),
                    if (_abhaNumber != null) ...[
                      Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.green, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _abhaNumber!,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Linked successfully',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ] else ...[
                      Text(
                        'No ABHA ID linked yet',
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _linkingAbha ? null : _linkAbha,
                          icon: _linkingAbha
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.link),
                          label:
                              Text(_linkingAbha ? 'Linking…' : 'Link ABHA ID'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── NFC Patient Card ────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer.withAlpha(90),
                borderRadius: BorderRadius.circular(AppConstants.borderRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.nfc, color: theme.colorScheme.secondary),
                      const SizedBox(width: 10),
                      Text('SAHA Patient Card',
                          style: theme.textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Stores registration details for instant check-in. '
                    'Aadhaar and screening records are never written.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _writingNfcCard ? null : _writePatientCard,
                    icon: _writingNfcCard
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.contactless_outlined),
                    label: Text(
                      _writingNfcCard
                          ? 'Waiting for card…'
                          : 'Write or Update NFC Card',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Demographics Card ───────────────────────────
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.borderRadius)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Demographics', style: theme.textTheme.titleSmall),
                    const Divider(),
                    _InfoRow(label: 'Village', value: p.village ?? '—'),
                    _InfoRow(label: 'District', value: p.district ?? '—'),
                    _InfoRow(label: 'State', value: p.state ?? '—'),
                    _InfoRow(label: 'Phone', value: p.phone ?? '—'),
                    _InfoRow(
                      label: 'Aadhaar (last 4)',
                      value: p.aadhaarLast4 != null
                          ? '●●●● ●●●● ${p.aadhaarLast4}'
                          : '—',
                    ),
                    _InfoRow(
                        label: 'Registered',
                        value: dateFmt.format(p.createdAt)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Screening Actions ───────────────────────────
            Text('Screenings', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.camera_alt,
                    label: 'Oral Cancer\nScreening',
                    color: Colors.red.shade400,
                    onTap: () async {
                      await context.push('/screening/cancer/${p.id}');
                      _loadPatient(); // refresh after screening
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.mic,
                    label: 'TB Cough\nAnalysis',
                    color: Colors.blue.shade400,
                    onTap: () async {
                      await context.push('/screening/tb/${p.id}');
                      _loadPatient(); // refresh after screening
                    },
                  ),
                ),
              ],
            ),

            // ── Screening History ───────────────────────────
            if (_screenings.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Screening History', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ..._screenings.map((s) {
                final type = s['type']?.toString() ?? '';
                final label = s['result_label']?.toString() ?? '';
                final confidence = (s['confidence'] as num?)?.toDouble() ?? 0.0;
                final risk = s['risk_level']?.toString() ?? 'low';
                final date = s['performed_at']?.toString() ?? '';
                final isCancer = type.contains('cancer');

                Color riskColor;
                switch (risk) {
                  case 'high':
                    riskColor = Colors.red;
                    break;
                  case 'medium':
                    riskColor = Colors.orange;
                    break;
                  default:
                    riskColor = Colors.green;
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: riskColor.withAlpha(30),
                      child: Icon(
                        isCancer ? Icons.camera_alt : Icons.mic,
                        color: riskColor,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Text(
                      '${isCancer ? "Oral Cancer" : "TB Cough"} • '
                      '${(confidence * 100).toStringAsFixed(1)}% • '
                      '${date.length >= 16 ? date.substring(0, 16) : date}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Chip(
                      label: Text(
                        risk.toUpperCase(),
                        style: TextStyle(
                          color: riskColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      backgroundColor: riskColor.withAlpha(20),
                      side: BorderSide.none,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: AppConstants.cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 36, color: color),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
