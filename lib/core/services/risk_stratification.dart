import '../db/database_helper.dart';
import '../utils/logger.dart';
import 'audit_service.dart';

/// ───────────────────────────────────────────────────────────────────────────
/// AI Risk Stratification & Clinical Triage Engine for SAHA-Quantum.
///
/// Healthcare systems think in **triage tiers**, not probabilities.
/// This engine transforms raw AI confidence scores into clinically
/// actionable risk bands with automatic referral routing.
///
/// Components:
///   1. **Risk Score Bands** — Low / Medium / High / Critical
///   2. **Auto-Referral Triggers** — based on risk + clinical rules
///   3. **Escalation Routing** — directs patients to the right care tier
///   4. **Clinical Decision Support** — context-aware recommendations
///   5. **Population Risk Monitoring** — village-level risk aggregation
///
/// Risk tiers follow WHO/ICMR screening guidelines:
///   - LOW (0–30%): Routine follow-up, next screening in 12 months
///   - MEDIUM (30–60%): Enhanced monitoring, rescreen in 3 months
///   - HIGH (60–85%): Urgent specialist referral within 7 days
///   - CRITICAL (85–100%): Emergency referral within 24 hours
/// ───────────────────────────────────────────────────────────────────────────
class RiskStratificationEngine {
  RiskStratificationEngine._();
  static final RiskStratificationEngine instance =
      RiskStratificationEngine._();
  static const _tag = 'RiskEngine';

  bool _initialized = false;

  // ════════════════════════════════════════════════════════════════════════
  //  INITIALIZATION
  // ════════════════════════════════════════════════════════════════════════

  Future<void> initialize() async {
    if (_initialized) return;
    final db = await DatabaseHelper.instance.database;

    await db.execute('''
      CREATE TABLE risk_assessments (
        id              TEXT PRIMARY KEY,
        patient_id      TEXT NOT NULL,
        screening_id    TEXT,
        screening_type  TEXT NOT NULL,
        risk_tier       TEXT NOT NULL,
        risk_score      REAL NOT NULL,
        confidence      REAL NOT NULL,
        referral_status TEXT NOT NULL DEFAULT 'none',
        referral_type   TEXT,
        referral_facility TEXT,
        escalation_notes TEXT,
        clinical_flags  TEXT,
        created_at      TEXT NOT NULL,
        resolved_at     TEXT,
        FOREIGN KEY (patient_id) REFERENCES patients (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE referral_queue (
        id              TEXT PRIMARY KEY,
        patient_id      TEXT NOT NULL,
        assessment_id   TEXT NOT NULL,
        priority        INTEGER NOT NULL,
        referral_type   TEXT NOT NULL,
        target_facility TEXT NOT NULL,
        status          TEXT NOT NULL DEFAULT 'pending',
        created_at      TEXT NOT NULL,
        accepted_at     TEXT,
        completed_at    TEXT,
        FOREIGN KEY (patient_id) REFERENCES patients (id)
      )
    ''');

    _initialized = true;
    Log.i('Risk Stratification Engine initialized', tag: _tag);
  }

  // ════════════════════════════════════════════════════════════════════════
  //  CORE RISK ASSESSMENT
  // ════════════════════════════════════════════════════════════════════════

  /// Perform a comprehensive risk assessment for a screening result.
  ///
  /// Combines AI confidence with clinical heuristics to produce
  /// a clinically grounded triage decision.
  Future<RiskAssessment> assess({
    required String patientId,
    required String screeningType,
    required String resultLabel,
    required double confidence,
    required Map<String, double> classProbabilities,
    String? screeningId,
    Map<String, dynamic>? patientContext,
  }) async {
    await initialize();

    // 1. Compute composite risk score
    final riskScore = _computeRiskScore(
      screeningType: screeningType,
      resultLabel: resultLabel,
      confidence: confidence,
      classProbabilities: classProbabilities,
      patientContext: patientContext,
    );

    // 2. Determine risk tier
    final tier = _classifyTier(riskScore);

    // 3. Determine clinical flags
    final flags = _computeClinicalFlags(
      screeningType: screeningType,
      resultLabel: resultLabel,
      confidence: confidence,
      riskScore: riskScore,
      patientContext: patientContext,
    );

    // 4. Determine referral action
    final referral = _determineReferral(
      tier: tier,
      screeningType: screeningType,
      resultLabel: resultLabel,
      flags: flags,
    );

    // 5. Build assessment
    final assessment = RiskAssessment(
      id: 'ra-${DateTime.now().millisecondsSinceEpoch}',
      patientId: patientId,
      screeningId: screeningId,
      screeningType: screeningType,
      riskTier: tier,
      riskScore: riskScore,
      confidence: confidence,
      referral: referral,
      clinicalFlags: flags,
      recommendations: _buildRecommendations(tier, screeningType, flags),
      nextScreeningDate: _computeNextScreening(tier),
      createdAt: DateTime.now(),
    );

    // 6. Persist
    final db = await DatabaseHelper.instance.database;
    await db.insert('risk_assessments', {
      'id': assessment.id,
      'patient_id': patientId,
      'screening_id': screeningId,
      'screening_type': screeningType,
      'risk_tier': tier.name,
      'risk_score': riskScore,
      'confidence': confidence,
      'referral_status': referral?.status ?? 'none',
      'referral_type': referral?.type,
      'referral_facility': referral?.targetFacility,
      'escalation_notes': referral?.notes,
      'clinical_flags': flags.join(','),
      'created_at': assessment.createdAt.toIso8601String(),
    });

    // 7. Create referral if needed
    if (referral != null && referral.status != 'none') {
      await _createReferral(assessment, referral, db);
    }

    // 8. Audit trail
    await AuditService.instance.log(
      eventType: 'risk_assessment',
      entityId: patientId,
      payload: {
        'tier': tier.name,
        'score': riskScore,
        'referral': referral?.type,
        'flags': flags,
      },
    );

    Log.i(
      'Risk assessment: $patientId → ${tier.name} '
      '(score: ${riskScore.toStringAsFixed(2)}, '
      'referral: ${referral?.type ?? "none"})',
      tag: _tag,
    );

    return assessment;
  }

  // ════════════════════════════════════════════════════════════════════════
  //  RISK SCORE COMPUTATION
  // ════════════════════════════════════════════════════════════════════════

  double _computeRiskScore({
    required String screeningType,
    required String resultLabel,
    required double confidence,
    required Map<String, double> classProbabilities,
    Map<String, dynamic>? patientContext,
  }) {
    double baseScore = 0.0;

    if (screeningType == 'oral_cancer') {
      // Weighted combination of class probabilities
      final cancerProb = classProbabilities['Cancer'] ?? 0.0;
      final nonOralProb = classProbabilities['Non-Oral'] ?? 0.0;
      final normalProb = classProbabilities['Normal Oral'] ?? 0.0;

      // Risk = cancer_prob * 1.0 + nonOralProb * 0.6 + (1-normal) * 0.2
      baseScore = cancerProb * 1.0 + nonOralProb * 0.6 +
          (1 - normalProb) * 0.2;
      baseScore = baseScore.clamp(0.0, 1.0);
    } else if (screeningType == 'tb_cough') {
      final tbProb = classProbabilities['TB Indicative'] ?? 0.0;
      baseScore = tbProb;
    } else {
      baseScore = confidence;
    }

    // Age-based risk adjustment
    if (patientContext != null) {
      final age = patientContext['age'] as int?;
      if (age != null) {
        if (age > 60) baseScore = (baseScore * 1.15).clamp(0.0, 1.0);
        if (age > 50 && screeningType == 'oral_cancer') {
          baseScore = (baseScore * 1.10).clamp(0.0, 1.0);
        }
      }

      // Tobacco use (major risk factor for oral cancer)
      final tobacco = patientContext['tobacco_use'] as bool? ?? false;
      if (tobacco && screeningType == 'oral_cancer') {
        baseScore = (baseScore * 1.25).clamp(0.0, 1.0);
      }

      // Previous screenings with high risk
      final priorHighRisk =
          patientContext['prior_high_risk'] as bool? ?? false;
      if (priorHighRisk) {
        baseScore = (baseScore * 1.20).clamp(0.0, 1.0);
      }
    }

    return baseScore;
  }

  RiskTier _classifyTier(double score) {
    if (score >= 0.85) return RiskTier.critical;
    if (score >= 0.60) return RiskTier.high;
    if (score >= 0.30) return RiskTier.medium;
    return RiskTier.low;
  }

  // ════════════════════════════════════════════════════════════════════════
  //  CLINICAL FLAGS
  // ════════════════════════════════════════════════════════════════════════

  List<String> _computeClinicalFlags({
    required String screeningType,
    required String resultLabel,
    required double confidence,
    required double riskScore,
    Map<String, dynamic>? patientContext,
  }) {
    final flags = <String>[];

    // Low confidence flag (model uncertain)
    if (confidence < 0.50) {
      flags.add('LOW_CONFIDENCE');
    }

    // High risk with low confidence = needs human review
    if (riskScore > 0.60 && confidence < 0.70) {
      flags.add('NEEDS_HUMAN_REVIEW');
    }

    // Cancer-specific flags
    if (screeningType == 'oral_cancer') {
      if (resultLabel.contains('Cancer') || resultLabel.contains('cancer')) {
        flags.add('MALIGNANCY_DETECTED');
      }
      if (resultLabel.contains('Pre') || resultLabel.contains('pre')) {
        flags.add('PRECANCEROUS_LESION');
      }
    }

    // TB-specific flags
    if (screeningType == 'tb_cough') {
      if (resultLabel.contains('TB') || resultLabel.contains('tb')) {
        flags.add('TB_POSITIVE_INDICATOR');
        flags.add('NOTIFY_RNTCP'); // Revised National TB Control Programme
      }
    }

    // Age-based flags
    if (patientContext != null) {
      final age = patientContext['age'] as int?;
      if (age != null && age < 18) flags.add('PEDIATRIC_PATIENT');
      if (age != null && age > 65) flags.add('GERIATRIC_PATIENT');
    }

    return flags;
  }

  // ════════════════════════════════════════════════════════════════════════
  //  AUTO-REFERRAL TRIGGERS
  // ════════════════════════════════════════════════════════════════════════

  ReferralAction? _determineReferral({
    required RiskTier tier,
    required String screeningType,
    required String resultLabel,
    required List<String> flags,
  }) {
    switch (tier) {
      case RiskTier.critical:
        return ReferralAction(
          type: 'emergency',
          status: 'urgent',
          priority: 1,
          targetFacility: _getFacilityForType(screeningType, 'tertiary'),
          timeframe: 'Within 24 hours',
          notes: 'CRITICAL risk detected. Immediate specialist consultation '
              'required. ${_getSpecialistType(screeningType)} referral.',
        );

      case RiskTier.high:
        return ReferralAction(
          type: 'urgent',
          status: 'pending',
          priority: 2,
          targetFacility: _getFacilityForType(screeningType, 'secondary'),
          timeframe: 'Within 7 days',
          notes: 'HIGH risk detected. Specialist referral recommended. '
              '${_getSpecialistType(screeningType)} evaluation needed.',
        );

      case RiskTier.medium:
        if (flags.contains('NEEDS_HUMAN_REVIEW') ||
            flags.contains('PRECANCEROUS_LESION')) {
          return ReferralAction(
            type: 'routine',
            status: 'pending',
            priority: 3,
            targetFacility: _getFacilityForType(screeningType, 'primary'),
            timeframe: 'Within 30 days',
            notes: 'MEDIUM risk with clinical flags. '
                'Enhanced monitoring recommended.',
          );
        }
        return null;

      case RiskTier.low:
        return null;
    }
  }

  String _getFacilityForType(String screeningType, String level) {
    if (level == 'tertiary') {
      if (screeningType == 'oral_cancer') {
        return 'Regional Cancer Centre / Medical College';
      }
      return 'District TB Centre / DOTS Plus Site';
    }
    if (level == 'secondary') {
      if (screeningType == 'oral_cancer') {
        return 'District Hospital (ENT/Oncology)';
      }
      return 'Designated Microscopy Centre (DMC)';
    }
    // primary
    if (screeningType == 'oral_cancer') {
      return 'Community Health Centre (CHC)';
    }
    return 'Primary Health Centre (PHC)';
  }

  String _getSpecialistType(String screeningType) {
    if (screeningType == 'oral_cancer') {
      return 'Oral & Maxillofacial Surgery / Oncology';
    }
    return 'Pulmonology / RNTCP';
  }

  Future<void> _createReferral(
      RiskAssessment assessment, ReferralAction referral, dynamic db) async {
    await db.insert('referral_queue', {
      'id': 'ref-${DateTime.now().millisecondsSinceEpoch}',
      'patient_id': assessment.patientId,
      'assessment_id': assessment.id,
      'priority': referral.priority,
      'referral_type': referral.type,
      'target_facility': referral.targetFacility,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // ════════════════════════════════════════════════════════════════════════
  //  RECOMMENDATIONS
  // ════════════════════════════════════════════════════════════════════════

  List<String> _buildRecommendations(
      RiskTier tier, String screeningType, List<String> flags) {
    final recs = <String>[];

    switch (tier) {
      case RiskTier.critical:
        recs.add(
            'IMMEDIATE specialist referral required within 24 hours');
        recs.add('Do not delay — arrange transport to nearest facility');
        if (screeningType == 'oral_cancer') {
          recs.add(
              'Biopsy confirmation recommended before treatment initiation');
        }
        if (screeningType == 'tb_cough') {
          recs.add('Start DOTS-based ATT as per RNTCP guidelines');
          recs.add('Collect sputum samples for AFB smear/culture');
        }
        break;

      case RiskTier.high:
        recs.add('Schedule specialist appointment within 7 days');
        if (screeningType == 'oral_cancer') {
          recs.add('Avoid tobacco and betel nut products');
          recs.add('Maintain oral hygiene; use prescribed mouthwash');
        }
        if (screeningType == 'tb_cough') {
          recs.add('CBNAAT/GeneXpert testing recommended');
          recs.add('Practice cough hygiene and isolation if symptomatic');
        }
        break;

      case RiskTier.medium:
        recs.add('Re-screen in 3 months');
        recs.add('Monitor symptoms and report changes');
        if (flags.contains('PRECANCEROUS_LESION')) {
          recs.add('Dietary counseling: increase fruits and vegetables');
          recs.add('Reduce/eliminate tobacco and alcohol consumption');
        }
        break;

      case RiskTier.low:
        recs.add('Continue routine screening every 12 months');
        recs.add('Maintain healthy lifestyle');
        if (screeningType == 'oral_cancer') {
          recs.add('Annual dental check-up recommended');
        }
        break;
    }

    if (flags.contains('LOW_CONFIDENCE')) {
      recs.add('⚠ AI confidence is low — clinical judgment should prevail');
    }

    return recs;
  }

  DateTime _computeNextScreening(RiskTier tier) {
    final now = DateTime.now();
    switch (tier) {
      case RiskTier.critical:
        return now; // Immediate
      case RiskTier.high:
        return now.add(const Duration(days: 30));
      case RiskTier.medium:
        return now.add(const Duration(days: 90));
      case RiskTier.low:
        return now.add(const Duration(days: 365));
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  QUERIES
  // ════════════════════════════════════════════════════════════════════════

  /// Get all pending referrals sorted by priority.
  Future<List<Map<String, dynamic>>> getPendingReferrals() async {
    await initialize();
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'referral_queue',
      where: "status = ?",
      whereArgs: ['pending'],
      orderBy: 'priority ASC',
    );
  }

  /// Get risk assessment history for a patient.
  Future<List<Map<String, dynamic>>> getPatientRiskHistory(
      String patientId) async {
    await initialize();
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'risk_assessments',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'created_at DESC',
    );
  }

  /// Get population-level risk summary.
  Future<Map<String, int>> getPopulationRiskSummary() async {
    await initialize();
    final db = await DatabaseHelper.instance.database;
    final all = await db.query('risk_assessments');
    final summary = <String, int>{
      'low': 0, 'medium': 0, 'high': 0, 'critical': 0, 'total': 0,
    };
    for (final row in all) {
      final tier = row['risk_tier'] as String? ?? 'low';
      summary[tier] = (summary[tier] ?? 0) + 1;
      summary['total'] = (summary['total'] ?? 0) + 1;
    }
    return summary;
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ════════════════════════════════════════════════════════════════════════════

enum RiskTier {
  low,
  medium,
  high,
  critical;

  String get displayLabel {
    switch (this) {
      case RiskTier.low:
        return 'LOW';
      case RiskTier.medium:
        return 'MEDIUM';
      case RiskTier.high:
        return 'HIGH';
      case RiskTier.critical:
        return 'CRITICAL';
    }
  }

  String get colorHex {
    switch (this) {
      case RiskTier.low:
        return '4CAF50'; // green
      case RiskTier.medium:
        return 'FF9800'; // orange
      case RiskTier.high:
        return 'F44336'; // red
      case RiskTier.critical:
        return '9C27B0'; // purple
    }
  }
}

class RiskAssessment {
  const RiskAssessment({
    required this.id,
    required this.patientId,
    this.screeningId,
    required this.screeningType,
    required this.riskTier,
    required this.riskScore,
    required this.confidence,
    this.referral,
    required this.clinicalFlags,
    required this.recommendations,
    required this.nextScreeningDate,
    required this.createdAt,
  });

  final String id;
  final String patientId;
  final String? screeningId;
  final String screeningType;
  final RiskTier riskTier;
  final double riskScore;
  final double confidence;
  final ReferralAction? referral;
  final List<String> clinicalFlags;
  final List<String> recommendations;
  final DateTime nextScreeningDate;
  final DateTime createdAt;
}

class ReferralAction {
  const ReferralAction({
    required this.type,
    required this.status,
    required this.priority,
    required this.targetFacility,
    required this.timeframe,
    this.notes,
  });

  final String type;
  final String status;
  final int priority;
  final String targetFacility;
  final String timeframe;
  final String? notes;
}
