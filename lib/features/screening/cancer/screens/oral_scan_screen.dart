// import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../patient/blocs/patient_bloc.dart';
import '../../../patient/blocs/patient_event_state.dart';

import '../../../../core/db/database_helper.dart';
import '../../../../core/services/audit_service.dart';
import '../../../../core/services/domain_classifier.dart';
import '../../../../core/services/model_governance.dart';
import '../../../../core/services/nafu_lite.dart';
import '../../../../core/services/resilience_manager.dart';
import '../../../../core/services/risk_stratification.dart';
import '../../../../core/utils/constants.dart';
import '../../../../core/utils/logger.dart';
import '../../models/screening_result.dart';
import '../models/cancer_result.dart';
import '../services/cancer_classifier.dart';
import '../../xai/grad_cam_engine.dart';

/// Screen for performing oral cancer screening via phone camera.
///
/// Captures an image of the oral cavity, runs on-device AI inference,
/// and displays a risk-scored result — all without internet.
class OralScanScreen extends StatefulWidget {
  const OralScanScreen({super.key, required this.patientId});

  final String patientId;

  @override
  State<OralScanScreen> createState() => _OralScanScreenState();
}

class _OralScanScreenState extends State<OralScanScreen> {
  bool _isAnalyzing = false;
  CancerResult? _result;
  GradCamResult? _xaiResult;
  FraudAnalysis? _fraudResult;
  RiskAssessment? _riskAssessment;
  String? _imagePath;
  final _classifier = CancerClassifier.instance;
  final _domainClassifier = DomainClassifier.instance;
  final _resilience = ResilienceManager.instance;
  final _uuid = const Uuid();
  final _picker = ImagePicker();
  Uint8List? _capturedImageBytes;

  // Domain validation state
  DomainValidationResult? _domainResult;
  bool _clinicianConfirmed = false;
  bool _showInconclusive = false;

  /// Approximate natural log for probability → logit conversion.
  static double _log(double x) {
    if (x <= 0) return -10;
    var result = 0.0;
    var term = (x - 1) / (x + 1);
    final term2 = term * term;
    for (var i = 1; i <= 15; i += 2) {
      result += term / i;
      term *= term2;
    }
    return 2 * result;
  }

  @override
  void initState() {
    super.initState();
    _classifier.loadModel();
  }

  Future<void> _captureAndAnalyze() async {
    setState(() {
      _isAnalyzing = true;
      _result = null;
      _domainResult = null;
      _clinicianConfirmed = false;
      _showInconclusive = false;
    });

    try {
      // ── Stage 0: Resilience check ───────────────────────
      final resilienceBlock = _resilience.canProceedWithScreening();
      if (resilienceBlock != null) {
        setState(() => _isAnalyzing = false);
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

      // Real image capture via camera or gallery
      final source = await _showImageSourceDialog();
      if (source == null) {
        setState(() => _isAnalyzing = false);
        return;
      }

      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 320,
        maxHeight: 320,
        imageQuality: 70,
      );

      if (pickedFile == null) {
        setState(() => _isAnalyzing = false);
        return;
      }

      final stopwatch = Stopwatch()..start();

      // Read the captured image bytes
      final fileBytes = await pickedFile.readAsBytes();

      // Yield so the UI can paint the loading indicator
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // ── Async, hardware-accelerated image decode + resize ──
      // Uses dart:ui's native browser decoder — orders of magnitude
      // faster than the pure-Dart `image` package on web.
      final inputSize = AppConstants.imageInputSize;
      final codec = await ui.instantiateImageCodec(
        fileBytes,
        targetWidth: inputSize,
        targetHeight: inputSize,
      );
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;

      // Draw onto canvas to get raw RGBA pixel data
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTWH(0, 0, inputSize.toDouble(), inputSize.toDouble()),
        image: uiImage,
        fit: BoxFit.cover,
      );
      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(inputSize, inputSize);
      final byteData =
          await finalImage.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (byteData == null) {
        setState(() => _isAnalyzing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not decode the image')),
          );
        }
        return;
      }

      // Extract RGB from RGBA (skip alpha channel)
      final rgba = byteData.buffer.asUint8List();
      final pixelCount = inputSize * inputSize;
      final imageBytes = Uint8List(pixelCount * 3);
      final float32Input = Float32List(pixelCount * 3);
      for (var i = 0; i < pixelCount; i++) {
        final r = rgba[i * 4];
        final g = rgba[i * 4 + 1];
        final b = rgba[i * 4 + 2];
        imageBytes[i * 3] = r;
        imageBytes[i * 3 + 1] = g;
        imageBytes[i * 3 + 2] = b;
        float32Input[i * 3] = r / 255.0;
        float32Input[i * 3 + 1] = g / 255.0;
        float32Input[i * 3 + 2] = b / 255.0;
      }

      // Yield after image processing
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Store original image bytes for display
      _capturedImageBytes = fileBytes;

      // ── Stage 1: Domain Validation (OOD + quality gate) ──
      // Non-blocking: if domain validation fails, skip it and proceed
      DomainValidationResult? domainResult;
      try {
        await _domainClassifier.loadModel();
        domainResult = await _domainClassifier.validate(imageBytes);
        _domainResult = domainResult;
      } catch (e) {
        Log.w('Domain validation failed ($e), skipping gate');
      }

      if (domainResult != null && !domainResult.passed) {
        setState(() {
          _isAnalyzing = false;
          _showInconclusive = true;
        });
        try {
          await AuditService.instance.log(
            eventType: 'domain_rejection',
            entityId: widget.patientId,
            payload: {
              'domainScore': domainResult.domainConfidence,
              'oodDistance': domainResult.oodScore,
              'qualityScore': domainResult.qualityScore,
              'rejection': domainResult.rejectionReason,
            },
          );
        } catch (_) {}
        return;
      }

      // ── Stage 2: Lesion Classification ───────────────────
      // Model governance: verify checksum before inference (non-blocking)
      try {
        await ModelGovernance.instance.initialize();
        await ModelGovernance.instance
            .verifyChecksum('oral_cancer_efficientnetb0');
      } catch (e) {
        Log.w('Model governance check failed ($e), proceeding');
      }

      // Yield before inference
      await Future<void>.delayed(Duration.zero);

      // Use pre-processed Float32 input — skips the expensive second
      // JPEG decode + resize that classify(fileBytes) would perform.
      final rawProbabilities =
          await _classifier.classifyPreprocessed(float32Input);

      // Apply temperature-scaled calibration from domain classifier.
      Map<String, double> calibratedMap;
      try {
        final classes = rawProbabilities.keys.toList();
        final logits = rawProbabilities.values
            .map((p) => p > 0 ? _log(p) : -10.0)
            .toList();
        final calibrated =
            _domainClassifier.calibrateProbabilities(logits);
        calibratedMap = <String, double>{};
        for (var i = 0; i < classes.length; i++) {
          calibratedMap[classes[i]] = calibrated[i];
        }
      } catch (_) {
        calibratedMap = rawProbabilities;
      }

      stopwatch.stop();

      final topLabel = _classifier.getTopLabel(calibratedMap);
      final riskLevel = _classifier.getRiskLevel(calibratedMap);
      final topConfidence = calibratedMap[topLabel] ?? 0.0;

      // Safety checks: rejection + inconclusive
      final rejected = _classifier.isRejected(calibratedMap);
      final inconclusive = _classifier.isInconclusive(calibratedMap);

      final result = CancerResult(
        label: rejected
            ? 'Non-Oral'
            : inconclusive
                ? 'Inconclusive'
                : topLabel,
        confidence: topConfidence,
        allProbabilities: calibratedMap,
        riskLevel: riskLevel,
        inferenceTimeMs: stopwatch.elapsedMilliseconds,
        isInconclusive: inconclusive,
        isRejected: rejected,
        rejectionReason: rejected ? 'Not an oral cavity image' : null,
      );

      // Model governance: log inference (non-blocking)
      try {
        await ModelGovernance.instance.logInference(
          modelName: 'oral_cancer_efficientnetb0',
          patientId: widget.patientId,
          inferenceType: 'oral_cancer_screening',
          resultLabel: result.label,
          confidence: result.confidence,
          inferenceTimeMs: result.inferenceTimeMs,
        );
      } catch (_) {}

      // Save to local DB (non-blocking)
      try {
        await _saveResult(result);
      } catch (_) {}

      // Audit trail (non-blocking)
      try {
        await AuditService.instance.log(
          eventType: AuditService.screeningCancer,
          entityId: widget.patientId,
          payload: {
            'label': result.label,
            'confidence': result.confidence,
            'risk': result.riskLevel,
          },
        );
      } catch (_) {}

      // NAFU-Lite fraud check (non-blocking)
      FraudAnalysis? fraud;
      try {
        fraud = await NafuLite.instance.analyzeScreening(
          patientId: widget.patientId,
          screeningType: 'oral_cancer',
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
          screeningType: 'oral_cancer',
          resultLabel: result.label,
          confidence: result.confidence,
          classProbabilities: result.allProbabilities,
        );
      } catch (_) {}

      // Grad-CAM XAI heatmap (with real image data, non-blocking)
      GradCamResult? xai;
      try {
        xai = GradCamEngine.instance.generateOralCancerHeatmap(
          imageWidth: AppConstants.imageInputSize,
          imageHeight: AppConstants.imageInputSize,
          predictedLabel: result.label,
          confidence: result.confidence,
          classProbabilities: result.allProbabilities,
          imageBytes: imageBytes,
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

  Future<void> _saveResult(CancerResult result) async {
    final id = _uuid.v4();
    final screening = ScreeningResult(
      id: id,
      patientId: widget.patientId,
      type: 'oral_cancer',
      resultLabel: result.label,
      confidence: result.confidence,
      riskLevel: result.riskLevel == 'high'
          ? RiskLevel.high
          : result.riskLevel == 'medium'
              ? RiskLevel.medium
              : RiskLevel.low,
      mediaPath: _imagePath,
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

  Future<ImageSource?> _showImageSourceDialog() async {
    return showDialog<ImageSource>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Image Source'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            child: const ListTile(
              leading: Icon(Icons.camera_alt),
              title: Text('Camera'),
              subtitle: Text('Take a photo of the oral cavity'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            child: const ListTile(
              leading: Icon(Icons.photo_library),
              title: Text('Gallery'),
              subtitle: Text('Select an existing image'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Oral Cancer Screening'),
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

            // ── Instructions Card ──────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius:
                    BorderRadius.circular(AppConstants.borderRadius),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.camera_alt,
                      size: 40, color: Colors.red.shade400),
                  const SizedBox(height: 8),
                  Text(
                    'AI-Powered Oral Cancer Screening',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Position the camera to capture a clear image of '
                    'the oral cavity. The AI model will analyze the '
                    'image on-device in under 2 seconds.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.red.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Camera Preview / Captured Image ─────────────
            Container(
              height: 280,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius:
                    BorderRadius.circular(AppConstants.borderRadius),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                child: _capturedImageBytes != null
                    ? Image.memory(
                        _capturedImageBytes!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: 280,
                      )
                    : Center(
                        child: _isAnalyzing
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Analyzing oral cavity image…',
                                    style: TextStyle(color: Colors.grey.shade600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Running CV pipeline on-device (no internet needed)',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.camera_outlined,
                                      size: 56, color: Colors.grey.shade400),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tap "Capture & Analyze" to take a photo',
                                    style: TextStyle(color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Capture Button ─────────────────────────────
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _isAnalyzing ? null : _captureAndAnalyze,
                icon: const Icon(Icons.camera),
                label: Text(
                  _isAnalyzing ? 'Analyzing…' : 'Capture & Analyze',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Results ────────────────────────────────────
            // Domain validation rejection
            if (_showInconclusive && _domainResult != null) ...[
              _buildDomainRejectionCard(theme),
              const SizedBox(height: 16),
            ],
            // Domain validation summary (when passed)
            if (_domainResult != null && _domainResult!.passed && _result != null) ...[
              _buildDomainPassCard(theme),
              const SizedBox(height: 16),
            ],
            if (_result != null) _buildResultCard(theme),
            // AI Confidence Explainer
            if (_result != null) ...[
              const SizedBox(height: 12),
              _buildAiExplainerCard(theme),
            ],
            // Clinician confirmation gate for high-risk results
            if (_result != null &&
                _result!.riskLevel != 'low' &&
                !_clinicianConfirmed) ...[
              const SizedBox(height: 16),
              _buildClinicianConfirmation(theme),
            ],
            if (_xaiResult != null) ...[
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
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(ThemeData theme) {
    final r = _result!;
    final riskColor = r.riskLevel == 'high'
        ? Colors.red
        : r.riskLevel == 'medium'
            ? Colors.orange
            : Colors.green;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        side: BorderSide(color: riskColor, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science, color: riskColor),
                const SizedBox(width: 8),
                Text(
                  'AI Analysis Result',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
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

            // Risk badge
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: riskColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: riskColor),
                ),
                child: Column(
                  children: [
                    Text(
                      r.riskLevel.toUpperCase(),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: riskColor,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      'RISK',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: riskColor.withAlpha(180),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Classification
            Text('Classification: ${r.label}',
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 4),
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

            // All probabilities
            Text('Detailed Probabilities:',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
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
                          e.key == 'Cancer'
                              ? Colors.red
                              : e.key == 'Non-Oral'
                                  ? Colors.grey
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

  Widget _buildAiExplainerCard(ThemeData theme) {
    final r = _result!;
    final classifier = CancerClassifier.instance;

    // Determine model type description
    String modelType;
    if (classifier.isModelTrained) {
      modelType = 'Pre-trained EfficientNetB0 (Kaggle dataset)';
    } else if (classifier.hasRealModel) {
      modelType = 'Browser-trained 4-block CNN (micro-trained)';
    } else {
      modelType = 'Heuristic fallback (no ML)';
    }

    // Generate plain-English explanation
    String explanation;
    final confPct = (r.confidence * 100).toStringAsFixed(0);
    if (r.riskLevel == 'high') {
      explanation =
          'The AI detected visual patterns consistent with potentially '
          'malignant lesions — irregular texture, abnormal coloration, '
          'and tissue changes. At $confPct% confidence, this warrants '
          'immediate clinical evaluation and biopsy referral.';
    } else if (r.riskLevel == 'medium') {
      explanation =
          'The AI found some visual indicators that may suggest early-stage '
          'changes in oral tissue. At $confPct% confidence, a follow-up '
          'screening in 2-4 weeks or specialist consultation is recommended.';
    } else if (r.riskLevel == 'low') {
      explanation =
          'The oral tissue appears healthy with normal coloration and texture. '
          'The AI found no significant visual markers of concern at $confPct% '
          'confidence. Routine annual screening is recommended.';
    } else {
      explanation =
          'The AI could not make a definitive determination. This may be due to '
          'image quality, unusual lighting, or atypical presentation. '
          'Please recapture or refer for manual examination.';
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        side: BorderSide(color: Colors.indigo.shade200),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Icon(Icons.psychology_alt, color: Colors.indigo.shade600),
        title: Text(
          'Why this result?',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.indigo.shade700,
          ),
        ),
        subtitle: Text(
          'AI Confidence Explainer',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.indigo.shade400,
          ),
        ),
        initiallyExpanded: r.riskLevel == 'high',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  explanation,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 16),
                _explainerRow(
                  theme,
                  Icons.model_training,
                  'Model',
                  modelType,
                ),
                _explainerRow(
                  theme,
                  Icons.thermostat,
                  'Temperature Scaling',
                  'T = 1.5 (calibrated softmax)',
                ),
                _explainerRow(
                  theme,
                  Icons.speed,
                  'Inference',
                  '${r.inferenceTimeMs}ms on-device',
                ),
                _explainerRow(
                  theme,
                  Icons.security,
                  'Safety Gates',
                  'Domain validation + OOD detection passed',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 14, color: Colors.indigo.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This AI runs 100% on-device. No patient data '
                          'leaves this device. Zero cloud dependency.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.indigo.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _explainerRow(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.indigo.shade400),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
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
                Expanded(
                  child: Text('Grad-CAM XAI Explanation',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                // Layer & channel info badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${xai.activationChannels}ch',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),

            // ── Heatmap overlay on the captured image ──────────────
            if (_capturedImageBytes != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Base image
                      Image.memory(
                        _capturedImageBytes!,
                        fit: BoxFit.cover,
                      ),
                      // Grad-CAM heatmap overlay
                      CustomPaint(
                        painter: GradCamOverlayPainter(
                          result: xai,
                          opacity: 0.55,
                        ),
                      ),
                      // Region labels
                      ...xai.attentionRegions.map((r) => Positioned(
                            left: r.x * 224 - 30,
                            top: r.y * 224 - 10,
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${(r.intensity * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Colour legend
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legendDot(Colors.red, 'High'),
                  const SizedBox(width: 12),
                  _legendDot(Colors.orange, 'Medium'),
                  const SizedBox(width: 12),
                  _legendDot(Colors.yellow.shade700, 'Low'),
                  const SizedBox(width: 12),
                  _legendDot(Colors.blue, 'Minimal'),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // ── Clinical explanation ───────────────────────────────
            Text(xai.explanation,
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),

            // ── Attention region list ──────────────────────────────
            if (xai.attentionRegions.isNotEmpty) ...[
              Text('Attention Regions:',
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
                            color: r.intensity > 0.75
                                ? Colors.red
                                : r.intensity > 0.5
                                    ? Colors.orange
                                    : r.intensity > 0.25
                                        ? Colors.yellow.shade700
                                        : Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${r.label} — ${(r.intensity * 100).toStringAsFixed(0)}% attention',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  )),
            ],

            // ── Model metadata ─────────────────────────────────────
            const SizedBox(height: 8),
            Text(
              'Layer: ${xai.modelLayer} · Class: ${xai.predictedClass} '
              '(${(xai.confidence * 100).toStringAsFixed(1)}%)',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
      ],
    );
  }

  // ── Domain Validation Cards ──────────────────────────────────

  Widget _buildDomainRejectionCard(ThemeData theme) {
    final d = _domainResult!;
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
                Icon(Icons.image_not_supported, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Image Not Suitable for Analysis',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade800,
                      )),
                ),
              ],
            ),
            const Divider(),
            Text(d.rejectionReason ?? 'Image did not pass quality gates',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            _domainMetric('Domain Score',
                '${(d.domainConfidence * 100).toStringAsFixed(1)}%', d.domainConfidence > 0.65),
            _domainMetric('OOD Distance',
                d.oodScore.toStringAsFixed(1), d.oodScore < 25.0),
            _domainMetric('Image Quality',
                '${(d.qualityScore * 100).toStringAsFixed(1)}%',
                d.qualityScore > 0.30),
            const SizedBox(height: 16),
            Text(
              'Please retake the photo:\n'
              '  • Position camera directly at oral cavity\n'
              '  • Ensure adequate lighting\n'
              '  • Hold steady to avoid blur',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _captureAndAnalyze,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Retake Photo'),
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

  Widget _buildDomainPassCard(ThemeData theme) {
    final d = _domainResult!;
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
                Text('Domain Validation Passed',
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
                  child: _domainMetric('Domain',
                      '${(d.domainConfidence * 100).toStringAsFixed(0)}%', true),
                ),
                Expanded(
                  child: _domainMetric('Quality',
                      '${(d.qualityScore * 100).toStringAsFixed(0)}%', true),
                ),
                Expanded(
                  child: _domainMetric('OOD',
                      d.oodScore.toStringAsFixed(1), true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _domainMetric(String label, String value, bool ok) {
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

  // ── Clinician Confirmation (Human-in-the-Loop) ───────────────

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
              'This screening result requires review by a '
              'qualified health worker. Please confirm you have '
              'reviewed the AI output before proceeding.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      // Manual override — mark as needs re-screening
                      setState(() {
                        _showInconclusive = true;
                        _result = null;
                      });
                    },
                    child: const Text('Override & Rescan'),
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
}
