import 'package:equatable/equatable.dart';

/// Result of an AI screening (oral cancer or TB cough analysis).
enum RiskLevel { low, medium, high }

class ScreeningResult extends Equatable {
  const ScreeningResult({
    required this.id,
    required this.patientId,
    required this.type,
    required this.resultLabel,
    required this.confidence,
    required this.riskLevel,
    this.mediaPath,
    this.notes,
    this.performedBy,
    required this.performedAt,
    this.isSynced = false,
  });

  final String id;
  final String patientId;

  /// 'oral_cancer' or 'tb_cough'
  final String type;
  final String resultLabel;
  final double confidence;
  final RiskLevel riskLevel;
  final String? mediaPath;
  final String? notes;
  final String? performedBy;
  final DateTime performedAt;
  final bool isSynced;

  Map<String, dynamic> toMap() => {
        'id': id,
        'patient_id': patientId,
        'type': type,
        'result_label': resultLabel,
        'confidence': confidence,
        'risk_level': riskLevel.name,
        'media_path': mediaPath,
        'notes': notes,
        'performed_by': performedBy,
        'performed_at': performedAt.toIso8601String(),
        'is_synced': isSynced ? 1 : 0,
      };

  factory ScreeningResult.fromMap(Map<String, dynamic> map) =>
      ScreeningResult(
        id: map['id'] as String,
        patientId: map['patient_id'] as String,
        type: map['type'] as String,
        resultLabel: map['result_label'] as String,
        confidence: (map['confidence'] as num).toDouble(),
        riskLevel: RiskLevel.values.firstWhere(
          (r) => r.name == (map['risk_level'] as String),
          orElse: () => RiskLevel.low,
        ),
        mediaPath: map['media_path'] as String?,
        notes: map['notes'] as String?,
        performedBy: map['performed_by'] as String?,
        performedAt: DateTime.parse(map['performed_at'] as String),
        isSynced: (map['is_synced'] as int? ?? 0) == 1,
      );

  @override
  List<Object?> get props => [id, patientId, type, resultLabel, confidence];
}
