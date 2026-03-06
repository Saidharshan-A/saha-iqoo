import 'package:equatable/equatable.dart';

/// Result of an oral cancer AI screening.
class CancerResult extends Equatable {
  const CancerResult({
    required this.label,
    required this.confidence,
    required this.allProbabilities,
    required this.riskLevel,
    required this.inferenceTimeMs,
    this.isInconclusive = false,
    this.isRejected = false,
    this.rejectionReason,
  });

  /// Top predicted label: Cancer, Normal Oral, or Non-Oral
  final String label;

  /// Confidence of the top label (0.0 – 1.0)
  final double confidence;

  /// All label probabilities
  final Map<String, double> allProbabilities;

  /// Risk level: low, medium, high, inconclusive, or rejected
  final String riskLevel;

  /// Inference time in milliseconds
  final int inferenceTimeMs;

  /// True when max confidence < inconclusive threshold.
  final bool isInconclusive;

  /// True when the image is not a valid oral cavity (Non-Oral > reject threshold).
  final bool isRejected;

  /// Human-readable rejection reason (e.g. "Not an oral cavity image").
  final String? rejectionReason;

  /// Whether the result is clinically actionable.
  bool get isActionable => !isInconclusive && !isRejected;

  @override
  List<Object?> get props =>
      [label, confidence, riskLevel, isInconclusive, isRejected];
}
