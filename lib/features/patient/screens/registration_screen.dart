import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/nfc_patient_card_service.dart';
import '../../../core/utils/constants.dart';
import '../blocs/patient_bloc.dart';
import '../models/patient.dart';
import '../widgets/nfc_scan_dialog.dart';

/// Full-screen patient registration form.
///
/// Works entirely offline — data is persisted to the local encrypted
/// database immediately on submission and queued for sync.
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  // Controllers
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _aadhaarCtrl = TextEditingController();
  final _villageCtrl = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String _gender = 'Male';
  bool _isSaving = false;
  bool _isNfcBusy = false;
  bool _nfcDialogOpen = false;
  String? _cardPatientId;

  final _nfcCards = NfcPatientCardService.instance;

  static const _genders = ['Male', 'Female', 'Other'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _aadhaarCtrl.dispose();
    _villageCtrl.dispose();
    _districtCtrl.dispose();
    _stateCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_isSaving) return; // prevent double-submit
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final now = DateTime.now();
    final patient = Patient(
      id: _cardPatientId ?? _uuid.v4(),
      fullName: _nameCtrl.text.trim(),
      age: int.parse(_ageCtrl.text.trim()),
      gender: _gender,
      aadhaarLast4:
          _aadhaarCtrl.text.trim().isNotEmpty ? _aadhaarCtrl.text.trim() : null,
      village:
          _villageCtrl.text.trim().isNotEmpty ? _villageCtrl.text.trim() : null,
      district: _districtCtrl.text.trim().isNotEmpty
          ? _districtCtrl.text.trim()
          : null,
      state: _stateCtrl.text.trim().isNotEmpty ? _stateCtrl.text.trim() : null,
      phone: _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
      createdAt: now,
      updatedAt: now,
    );

    context.read<PatientBloc>().add(AddPatient(patient));
  }

  Future<void> _scanPatientCard() async {
    if (_isNfcBusy) return;
    setState(() => _isNfcBusy = true);
    _nfcDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NfcScanDialog(
        title: 'Scan SAHA Card',
        instruction: 'Hold the patient card against the back of the phone.',
        onCancel: () async {
          _nfcDialogOpen = false;
          await _nfcCards.cancel();
          if (mounted) Navigator.of(context, rootNavigator: true).pop();
        },
      ),
    );

    try {
      final profile = await _nfcCards.readCard();
      _closeNfcDialog();
      if (!mounted) return;
      setState(() {
        _cardPatientId = profile.patientId;
        _nameCtrl.text = profile.fullName;
        _ageCtrl.text = profile.age.toString();
        _gender = _genders.contains(profile.gender) ? profile.gender : 'Other';
        _aadhaarCtrl.text = profile.aadhaarLast4 ?? '';
        _phoneCtrl.text = profile.phone ?? '';
        _villageCtrl.text = profile.village ?? '';
        _districtCtrl.text = profile.district ?? '';
        _stateCtrl.text = profile.state ?? '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${profile.fullName}\'s card loaded. Review and save.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } on NfcPatientCardException catch (error) {
      _closeNfcDialog();
      if (mounted && !error.cancelled) _showNfcError(error.message);
    } catch (error) {
      _closeNfcDialog();
      if (mounted) _showNfcError('Could not read this card: $error');
    } finally {
      if (mounted) setState(() => _isNfcBusy = false);
    }
  }

  Future<void> _writePatientCard() async {
    if (_isNfcBusy) return;
    if (!_formKey.currentState!.validate()) {
      _showNfcError('Enter the patient name and age first.');
      return;
    }

    final patientId = _cardPatientId ?? _uuid.v4();
    final profile = NfcPatientCardData(
      patientId: patientId,
      fullName: _nameCtrl.text.trim(),
      age: int.parse(_ageCtrl.text.trim()),
      gender: _gender,
      aadhaarLast4: _aadhaarCtrl.text.trim().isEmpty
          ? null
          : _aadhaarCtrl.text.trim(),
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      village:
          _villageCtrl.text.trim().isEmpty ? null : _villageCtrl.text.trim(),
      district: _districtCtrl.text.trim().isEmpty
          ? null
          : _districtCtrl.text.trim(),
      state: _stateCtrl.text.trim().isEmpty ? null : _stateCtrl.text.trim(),
    );

    setState(() => _isNfcBusy = true);
    _nfcDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NfcScanDialog(
        title: 'Write Patient Card',
        instruction: 'Hold the blank NFC card against the back of the phone.',
        onCancel: () async {
          _nfcDialogOpen = false;
          await _nfcCards.cancel();
          if (mounted) Navigator.of(context, rootNavigator: true).pop();
        },
      ),
    );

    try {
      await _nfcCards.writeCard(profile);
      _closeNfcDialog();
      if (!mounted) return;
      setState(() => _cardPatientId = patientId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${profile.fullName}\'s card is ready to scan.'),
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
      if (mounted) setState(() => _isNfcBusy = false);
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

    return BlocListener<PatientBloc, PatientState>(
      listener: (context, state) {
        if (state is PatientOperationSuccess) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.green.shade700,
            ),
          );
          Navigator.of(context).pop(true);
        } else if (state is PatientError) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Register Patient'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ─────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius:
                          BorderRadius.circular(AppConstants.borderRadius),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.person_add,
                            color: theme.colorScheme.onPrimaryContainer),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'New Patient Registration',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'OFFLINE READY',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── NFC patient card ──────────────────────
                  OutlinedButton.icon(
                    onPressed: _isNfcBusy ? null : _scanPatientCard,
                    icon: _isNfcBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.nfc),
                    label: Text(
                      _cardPatientId == null
                          ? 'Scan SAHA Patient Card'
                          : 'Scan Another Patient Card',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _cardPatientId == null
                        ? 'Tap a patient card to fill this form automatically.'
                        : 'NFC profile loaded. Review the details before saving.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _cardPatientId == null
                          ? theme.colorScheme.onSurfaceVariant
                          : Colors.green.shade700,
                      fontWeight: _cardPatientId == null
                          ? FontWeight.normal
                          : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _isNfcBusy ? null : _writePatientCard,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      _cardPatientId == null
                          ? 'Write form details to blank card'
                          : 'Update this patient card',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Full Name ──────────────────────────────
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Full Name *',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Name is required'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // ── Age & Gender Row ───────────────────────
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _ageCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Age *',
                            prefixIcon: Icon(Icons.cake_outlined),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            final age = int.tryParse(v);
                            if (age == null || age < 0 || age > 150) {
                              return 'Invalid age';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          // Controlled value must update after an NFC scan.
                          // ignore: deprecated_member_use
                          value: _gender,
                          decoration: const InputDecoration(
                            labelText: 'Gender *',
                            prefixIcon: Icon(Icons.wc_outlined),
                            border: OutlineInputBorder(),
                          ),
                          items: _genders
                              .map((g) =>
                                  DropdownMenuItem(value: g, child: Text(g)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _gender = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Aadhaar Last 4 ────────────────────────
                  TextFormField(
                    controller: _aadhaarCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Aadhaar Last 4 Digits',
                      prefixIcon: Icon(Icons.credit_card_outlined),
                      border: OutlineInputBorder(),
                      helperText: 'Optional – for identity verification',
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 16),

                  // ── Phone ──────────────────────────────────
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: Icon(Icons.phone_outlined),
                      prefixText: '+91 ',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 16),

                  // ── Location ───────────────────────────────
                  TextFormField(
                    controller: _villageCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Village / Town',
                      prefixIcon: Icon(Icons.location_on_outlined),
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _districtCtrl,
                          decoration: const InputDecoration(
                            labelText: 'District',
                            border: OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.words,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _stateCtrl,
                          decoration: const InputDecoration(
                            labelText: 'State',
                            border: OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.words,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // ── Submit ─────────────────────────────────
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _submit,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _isSaving ? 'Saving…' : 'Register Patient',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
