import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../../patient/blocs/patient_bloc.dart';
import '../../../patient/blocs/patient_event_state.dart';

import '../../../../core/db/database_helper.dart';
import '../../../../core/services/audit_service.dart';
import '../../../../core/services/model_governance.dart';
import '../../../../core/services/nafu_lite.dart';
import '../../../../core/services/resilience_manager.dart';
import '../../../../core/services/risk_stratification.dart';
import '../../../../core/utils/constants.dart';
import '../../models/screening_result.dart';
import '../models/tb_result.dart';
import '../services/audio_quality_gate.dart';
import '../services/tb_audio_classifier.dart';
import '../../xai/grad_cam_engine.dart';

/// Screen for TB cough audio screening.
///
/// Records a 3-5 second cough sample, extracts MFCC features,
/// and runs on-device AI classification — all offline.
class CoughRecordScreen extends StatefulWidget {
  const CoughRecordScreen({super.key, required this.patientId});

  final String patientId;

  @override
  State<CoughRecordScreen> createState() => _CoughRecordScreenState();
}

class _CoughRecordScreenState extends State<CoughRecordScreen>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;
  bool _isAnalyzing = false;
  TbResult? _result;
  GradCamResult? _xaiResult;
  FraudAnalysis? _fraudResult;
  RiskAssessment? _riskAssessment;
  int _recordSeconds = 0;

  final _classifier = TbAudioClassifier.instance;
  final _audioGate = AudioQualityGate.instance;
  final _resilience = ResilienceManager.instance;
  final _uuid = const Uuid();
  final _recorder = AudioRecorder();
  final _audioChunks = <Uint8List>[];
  StreamSubscription<Uint8List>? _audioSub;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnimation;

  // Audio quality & safety state
  AudioQualityResult? _audioQuality;
  bool _clinicianConfirmed = false;
  bool _showQualityReject = false;

  @override
  void initState() {
    super.initState();
    _classifier.loadModel();
    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _audioSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    // ── Resilience check ─────────────────────────────
    final resilienceBlock = _resilience.canProceedWithScreening();
    if (resilienceBlock != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot screen: $resilienceBlock'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isRecording = true;
      _recordSeconds = 0;
      _result = null;
      _audioChunks.clear();
      _audioQuality = null;
      _clinicianConfirmed = false;
      _showQualityReject = false;
    });

    try {
      // Check microphone permission
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied')),
          );
        }
        setState(() => _isRecording = false);
        return;
      }

      // Start streaming audio from microphone
      // On web: MediaRecorder API captures real audio
      // On mobile: native audio recording
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
        ),
      );

      _audioSub = stream.listen((chunk) {
        _audioChunks.add(chunk);
      });

      // Record for the configured duration
      for (var i = 1; i <= AppConstants.audioDurationSeconds; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        setState(() => _recordSeconds = i);
      }

      // Stop recording
      await _recorder.stop();
      await _audioSub?.cancel();
      _audioSub = null;
    } catch (e) {
      // If streaming fails (encoder not supported on web), fall back
      // to file-based recording
      try {
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: '',
        );

        for (var i = 1; i <= AppConstants.audioDurationSeconds; i++) {
          await Future.delayed(const Duration(seconds: 1));
          if (!mounted) return;
          setState(() => _recordSeconds = i);
        }

        await _recorder.stop();
      } catch (fallbackError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Recording failed: $fallbackError')),
          );
        }
        setState(() => _isRecording = false);
        return;
      }
    }

    // Recording complete — analyze
    await _analyze();
  }

  Future<void> _analyze() async {
    setState(() {
      _isRecording = false;
      _isAnalyzing = true;
    });

    try {
      final stopwatch = Stopwatch()..start();

      // Combine recorded audio chunks into a single buffer
      Uint8List audioBytes;
      if (_audioChunks.isNotEmpty) {
        final totalLen = _audioChunks.fold<int>(0, (s, c) => s + c.length);
        audioBytes = Uint8List(totalLen);
        var offset = 0;
        for (final chunk in _audioChunks) {
          audioBytes.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }
      } else {
        // Fallback: minimal PCM silence if no chunks captured
        audioBytes = Uint8List(
          AppConstants.audioSampleRate * AppConstants.audioDurationSeconds * 2,
        );
      }

      // ── Audio Quality Gate ──────────────────────────────
      // Convert to Float64List samples (PCM 16-bit → normalized)
      final sampleCount = audioBytes.length ~/ 2;
      final samples = Float64List(sampleCount);
      for (var i = 0; i < sampleCount; i++) {
        final lo = audioBytes[i * 2];
        final hi = audioBytes[i * 2 + 1];
        var sample = (hi << 8) | lo;
        if (sample > 32767) sample -= 65536;
        samples[i] = sample / 32768.0;
      }

      final qualityResult = _audioGate.validate(samples);
      _audioQuality = qualityResult;

      if (!qualityResult.isAcceptable) {
        setState(() {
          _isAnalyzing = false;
          _showQualityReject = true;
        });
        await AuditService.instance.log(
          eventType: 'audio_quality_rejection',
          entityId: widget.patientId,
          payload: {
            'snr': qualityResult.snrDb,
            'duration': qualityResult.effectiveDurationSec,
            'coughLikelihood': qualityResult.coughLikelihood,
            'rejection': qualityResult.issues.join('; '),
          },
        );
        return;
      }

      // Apply noise reduction for rural environments
      final cleanSamples = _audioGate.reduceNoise(samples);
      // Re-pack into PCM bytes for the classifier
      final cleanBytes = Uint8List(cleanSamples.length * 2);
      for (var i = 0; i < cleanSamples.length; i++) {
        final s = (cleanSamples[i] * 32767).round().clamp(-32768, 32767);
        cleanBytes[i * 2] = s & 0xFF;
        cleanBytes[i * 2 + 1] = (s >> 8) & 0xFF;
      }

      final probabilities = await _classifier.classify(cleanBytes);
      stopwatch.stop();

      // Brief analysis delay for UX (lets the UI show "Analyzing...")
      await Future<void>.delayed(const Duration(milliseconds: 800));

      final topLabel = _classifier.getTopLabel(probabilities);
      final isTbPositive = _classifier.isTbPositive(probabilities);
      final topConfidence = probabilities[topLabel] ?? 0.0;
      final riskTier = _classifier.getRiskTier(probabilities);

      // Inconclusive if confidence is low
      final isInconclusive = topConfidence < 0.55;

      final result = TbResult(
        label: isInconclusive ? 'Inconclusive' : topLabel,
        confidence: topConfidence,
        allProbabilities: probabilities,
        isTbPositive: isInconclusive ? false : isTbPositive,
        inferenceTimeMs: stopwatch.elapsedMilliseconds,
        riskTier: isInconclusive ? 'Inconclusive' : riskTier,
      );

      // Model governance: log inference (non-blocking)
      try {
        await ModelGovernance.instance.initialize();
        await ModelGovernance.instance.verifyChecksum('tb_cough_classifier');
        await ModelGovernance.instance.logInference(
          modelName: 'tb_cough_classifier',
          patientId: widget.patientId,
          inferenceType: 'tb_cough_screening',
          resultLabel: result.label,
          confidence: result.confidence,
          inferenceTimeMs: result.inferenceTimeMs,
        );
      } catch (_) {}

      try { await _saveResult(result); } catch (_) {}

      // Audit trail (non-blocking)
      try {
        await AuditService.instance.log(
          eventType: AuditService.screeningTb,
          entityId: widget.patientId,
          payload: {
            'label': result.label,
            'confidence': result.confidence,
            'tbPositive': result.isTbPositive,
          },
        );
      } catch (_) {}

      // NAFU-Lite fraud check (non-blocking)
      FraudAnalysis? fraud;
      try {
        fraud = await NafuLite.instance.analyzeScreening(
          patientId: widget.patientId,
          screeningType: 'tb_cough',
          confidence: result.confidence,
          timestamp: DateTime.now(),
        );
      } catch (_) {}

      // AI Risk Stratification — auto-triage (non-blocking)
      RiskAssessment? riskResult;
      try {
        await RiskStratificationEngine.instance.initialize();
        riskResult = await RiskStratificationEngine.instance.assess(
          patientId: widget.patientId,
          screeningType: 'tb_cough',
          resultLabel: result.label,
          confidence: result.confidence,
          classProbabilities: result.allProbabilities,
        );
      } catch (_) {}

      // Grad-CAM XAI heatmap (non-blocking)
      GradCamResult? xai;
      try {
        xai = GradCamEngine.instance.generateTbAudioHeatmap(
          predictedLabel: result.label,
          confidence: result.confidence,
          audioBytes: cleanBytes,
        );
      } catch (_) {}

      setState(() {
        _result = result;
        _xaiResult = xai;
        _fraudResult = fraud;
        _riskAssessment = riskResult;
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() => _isAnalyzing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Analysis failed: $e')),
        );
      }
    }
  }

  Future<void> _saveResult(TbResult result) async {
    final id = _uuid.v4();
    final screening = ScreeningResult(
      id: id,
      patientId: widget.patientId,
      type: 'tb_cough',
      resultLabel: result.label,
      confidence: result.confidence,
      riskLevel: result.isTbPositive ? RiskLevel.high : RiskLevel.low,
      performedAt: DateTime.now(),
    );

    await DatabaseHelper.instance.insertWithSync(
      'screenings',
      screening.toMap(),
      rowId: id,
    );

    if (mounted) {
      context.read<PatientBloc>().add(const LoadPatients());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TB Cough Analysis'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Medical AI Safety Disclaimer ───────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: Row(
                children: [
                  Icon(Icons.medical_information,
                      color: Colors.amber.shade800, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI Screening Tool — NOT a medical diagnosis. '
                      'Results require clinician confirmation.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Instructions ───────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius:
                    BorderRadius.circular(AppConstants.borderRadius),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.mic, size: 40, color: Colors.blue.shade400),
                  const SizedBox(height: 8),
                  Text(
                    'AI-Powered TB Cough Analysis',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Record a 3-second cough sample. The AI model '
                    'will extract audio biomarkers and detect TB '
                    'indicators on-device.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.blue.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── Recording Visualizer ───────────────────────
            Center(
              child: ScaleTransition(
                scale: _isRecording ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording
                        ? Colors.red.withAlpha(30)
                        : _isAnalyzing
                            ? Colors.blue.withAlpha(30)
                            : Colors.grey.withAlpha(30),
                    border: Border.all(
                      color: _isRecording
                          ? Colors.red
                          : _isAnalyzing
                              ? Colors.blue
                              : Colors.grey,
                      width: 3,
                    ),
                  ),
                  child: Center(
                    child: _isRecording
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.mic,
                                  size: 48, color: Colors.red),
                              const SizedBox(height: 8),
                              Text(
                                '${_recordSeconds}s / ${AppConstants.audioDurationSeconds}s',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          )
                        : _isAnalyzing
                            ? const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 8),
                                  Text('Analyzing…',
                                      style: TextStyle(fontSize: 12)),
                                ],
                              )
                            : Icon(Icons.mic_none,
                                size: 48, color: Colors.grey.shade400),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Record Button ──────────────────────────────
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed:
                    _isRecording || _isAnalyzing ? null : _startRecording,
                icon: const Icon(Icons.fiber_manual_record),
                label: Text(
                  _isRecording
                      ? 'Recording…'
                      : _isAnalyzing
                          ? 'Analyzing…'
                          : 'Press & Cough',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Results ────────────────────────────────────
            // Audio quality rejection
            if (_showQualityReject && _audioQuality != null) ...[
              _buildAudioQualityRejectCard(theme),
              const SizedBox(height: 16),
            ],
            // Audio quality summary (when passed)
            if (_audioQuality != null && _audioQuality!.isAcceptable && _result != null) ...[
              _buildAudioQualityPassCard(theme),
              const SizedBox(height: 16),
            ],
            if (_result != null) _buildResultCard(theme),
            // Clinician confirmation gate
            if (_result != null &&
                _result!.isTbPositive &&
                !_clinicianConfirmed) ...[
              const SizedBox(height: 16),
              _buildClinicianConfirmation(theme),
            ],            if (_xaiResult != null) ...[
              const SizedBox(height: 16),
              _buildXaiCard(theme),
            ],
            if (_fraudResult != null && _fraudResult!.isAlert) ...[
              const SizedBox(height: 16),
              _buildFraudWarning(theme),
            ],
            if (_riskAssessment != null) ...[
              const SizedBox(height: 16),
              _buildRiskCard(theme),
            ],          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(ThemeData theme) {
    final r = _result!;
    final color = r.isTbPositive ? Colors.red : Colors.green;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        side: BorderSide(color: color, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.biotech, color: color),
                const SizedBox(width: 8),
                Text(
                  'AI Analysis Result',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Model status indicator
            if (!_classifier.hasRealModel)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.amber.shade800, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'FALLBACK MODE \u2014 No AI model available. Results are statistical estimates.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
            else if (!_classifier.isModelTrained)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.psychology, color: Colors.blue.shade700, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'CNN Model Active \u2014 Real-time neural network inference. '
                      'Train on Kaggle for clinical-grade accuracy.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Result badge
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color),
                ),
                child: Column(
                  children: [
                    Icon(
                      r.isTbPositive
                          ? Icons.warning_amber
                          : Icons.check_circle,
                      size: 36,
                      color: color,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      r.label,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'Confidence: ${(r.confidence * 100).toStringAsFixed(1)}%',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Inference time: ${r.inferenceTimeMs}ms',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),

            // Probabilities
            ...r.allProbabilities.entries.map((e) {
              final pct = (e.value * 100).toStringAsFixed(1);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text(e.key)),
                    Expanded(
                      flex: 3,
                      child: LinearProgressIndicator(
                        value: e.value,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(
                          e.key == 'TB Indicative'
                              ? Colors.red
                              : Colors.green,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 50,
                      child: Text('$pct%',
                          textAlign: TextAlign.right,
                          style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),

            // Disclaimer
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI screening is indicative only. '
                      'Refer to a specialist for confirmation.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildXaiCard(ThemeData theme) {
    final xai = _xaiResult!;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        side: BorderSide(color: Colors.blue.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.visibility, color: Colors.blue.shade600),
                const SizedBox(width: 8),
                Text('Grad-CAM XAI Explanation',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const Divider(),
            Text(xai.explanation, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            if (xai.attentionRegions.isNotEmpty) ...[
              Text('Audio Attention Regions:',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ...xai.attentionRegions.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: r.intensity > 0.5
                                ? Colors.red
                                : Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${r.label} (${(r.intensity * 100).toStringAsFixed(0)}% attention)',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFraudWarning(ThemeData theme) {
    final f = _fraudResult!;
    return Card(
      elevation: 2,
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        side: BorderSide(color: Colors.red.shade400, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Text('NAFU-Lite Anomaly Detected',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade700,
                    )),
              ],
            ),
            const Divider(),
            Text(
              'Risk Score: ${(f.compositeScore * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            ...f.checks.where((c) => c.riskScore >= 0.5).map((c) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('- ${c.name}: ${c.detail}',
                      style: theme.textTheme.bodySmall),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskCard(ThemeData theme) {
    final r = _riskAssessment!;
    final tierColor = Color(int.parse('FF${r.riskTier.colorHex}', radix: 16));

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        side: BorderSide(color: tierColor, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: tierColor),
                const SizedBox(width: 8),
                Text('Risk Stratification',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
                const Spacer(),
                Chip(
                  label: Text(r.riskTier.displayLabel,
                      style: TextStyle(
                        color: tierColor,
                        fontWeight: FontWeight.bold,
                      )),
                  backgroundColor: tierColor.withValues(alpha: 0.15),
                ),
              ],
            ),
            const Divider(),
            Text(
              'Risk Score: ${(r.riskScore * 100).toStringAsFixed(1)}%',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: tierColor,
              ),
            ),
            const SizedBox(height: 8),
            if (r.clinicalFlags.isNotEmpty)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: r.clinicalFlags.map((f) => Chip(
                  label: Text(f, style: const TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )).toList(),
              ),
            if (r.recommendations.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Recommendations:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ...r.recommendations.map((rec) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('  • $rec',
                        style: theme.textTheme.bodySmall),
                  )),
            ],
            if (r.referral != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('REFERRAL: ${r.referral!.type.toUpperCase()}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade700,
                        )),
                    Text('Facility: ${r.referral!.targetFacility}',
                        style: const TextStyle(fontSize: 12)),
                    Text('Timeframe: ${r.referral!.timeframe}',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Audio Quality Cards ─────────────────────────────────────

  Widget _buildAudioQualityRejectCard(ThemeData theme) {
    final q = _audioQuality!;
    return Card(
      elevation: 3,
      color: Colors.orange.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        side: BorderSide(color: Colors.orange.shade400, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.mic_off, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Audio Quality Insufficient',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade800,
                      )),
                ),
              ],
            ),
            const Divider(),
            ...q.issues.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.cancel, size: 14, color: Colors.red.shade600),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(r,
                              style: const TextStyle(fontSize: 12))),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
            _audioMetric('SNR', '${q.snrDb.toStringAsFixed(1)} dB',
                q.snrDb >= 6),
            _audioMetric('Duration',
                '${q.effectiveDurationSec.toStringAsFixed(1)}s', q.effectiveDurationSec >= 3),
            _audioMetric('Cough Score',
                '${(q.coughLikelihood * 100).toStringAsFixed(0)}%',
                q.coughLikelihood >= 0.15),
            const SizedBox(height: 16),
            Text(
              'Please re-record:\n'
              '  • Move to a quieter area\n'
              '  • Cough clearly into the microphone\n'
              '  • Hold for at least 3 seconds',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _startRecording,
                icon: const Icon(Icons.mic),
                label: const Text('Re-Record'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioQualityPassCard(ThemeData theme) {
    final q = _audioQuality!;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        side: BorderSide(color: Colors.green.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified, color: Colors.green.shade600, size: 18),
                const SizedBox(width: 6),
                Text('Audio Quality Validated',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _audioMetric('SNR',
                      '${q.snrDb.toStringAsFixed(1)}dB', true),
                ),
                Expanded(
                  child: _audioMetric('Duration',
                      '${q.effectiveDurationSec.toStringAsFixed(1)}s', true),
                ),
                Expanded(
                  child: _audioMetric('Cough',
                      '${(q.coughLikelihood * 100).toStringAsFixed(0)}%', true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _audioMetric(String label, String value, bool ok) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel,
              size: 14, color: ok ? Colors.green : Colors.red),
          const SizedBox(width: 4),
          Text('$label: $value',
              style: TextStyle(
                fontSize: 12,
                color: ok ? Colors.green.shade700 : Colors.red.shade700,
              )),
        ],
      ),
    );
  }

  // ── Clinician Confirmation (Human-in-the-Loop) ──────────────

  Widget _buildClinicianConfirmation(ThemeData theme) {
    return Card(
      elevation: 3,
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        side: BorderSide(color: Colors.blue.shade400, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_pin, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text('Clinician Confirmation Required',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade800,
                    )),
              ],
            ),
            const Divider(),
            Text(
              'A TB-positive result requires review by a '
              'qualified health worker before any action.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _showQualityReject = false;
                        _result = null;
                      });
                    },
                    child: const Text('Override & Re-Record'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() => _clinicianConfirmed = true);
                      AuditService.instance.log(
                        eventType: 'clinician_confirmation',
                        entityId: widget.patientId,
                        payload: {
                          'result': _result?.label,
                          'confidence': _result?.confidence,
                          'tbPositive': _result?.isTbPositive,
                        },
                      );
                    },
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Confirm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
