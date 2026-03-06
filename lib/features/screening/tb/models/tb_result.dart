import 'package:equatable/equatable.dart';

/// Result of a TB cough audio analysis.
class TbResult extends Equatable {
  const TbResult({
    required this.label,
    required this.confidence,
    required this.allProbabilities,
    required this.isTbPositive,
    required this.inferenceTimeMs,
    this.riskTier = 'Inconclusive',
  });

  final String label;
  final double confidence;
  final Map<String, double> allProbabilities;
  final bool isTbPositive;
  final int inferenceTimeMs;

  /// Risk tier: 'Low TB Risk', 'Moderate TB Risk', 'High TB Risk', or 'Inconclusive'.
  final String riskTier;

  /// Whether the result is clinically actionable.
  bool get isActionable => riskTier != 'Inconclusive';

  @override
  List<Object?> get props => [label, confidence, isTbPositive, riskTier];
}
