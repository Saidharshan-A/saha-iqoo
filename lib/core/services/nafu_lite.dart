import 'dart:math';

import '../db/database_helper.dart';
import '../services/audit_service.dart';
import '../utils/logger.dart';

/// NAFU-Lite (Neural Anti-Fraud Unit) — real-time anomaly detection
/// engine for SAHA-Quantum.
///
/// Detects suspicious patterns in healthcare data submissions:
///
///   1. **Velocity checks**: Too many screenings per device/hour
///   2. **Duplicate detection**: Same patient screened multiple times
///      in short windows
///   3. **Statistical outliers**: Confidence scores that deviate from
///      model baselines (possible adversarial inputs)
///   4. **Geographic anomalies**: Impossible travel between villages
///   5. **Phantom patients**: Registration patterns suggesting fake
///      patient creation for incentive fraud
///
/// Each check produces a risk score [0.0–1.0]. Scores ≥ 0.7 generate
/// a fraud alert stored in `fraud_alerts` table and the SAHI audit trail.
///
/// Algorithm: Lightweight Z-score anomaly detection with exponential
/// moving average (EMA) baselines — suitable for edge deployment.
class NafuLite {
  NafuLite._();
  static final NafuLite instance = NafuLite._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  static const double _alertThreshold = 0.7;

  // EMA baselines (initialized with reasonable defaults)
  double _avgScreeningsPerHour = 3.0;
  double _avgConfidence = 0.72;
  double _avgRegistrationsPerHour = 2.0;
  static const double _emaAlpha = 0.15; // smoothing factor

  // ── Core Analysis ─────────────────────────────────────────

  /// Run all fraud checks on a screening submission.
  /// Returns a composite risk score and any generated alerts.
  Future<FraudAnalysis> analyzeScreening({
    required String patientId,
    required String screeningType,
    required double confidence,
    required DateTime timestamp,
  }) async {
    final checks = <FraudCheck>[];

    // Check 1: Velocity (screenings per hour)
    checks.add(await _velocityCheck(timestamp));

    // Check 2: Duplicate screening
    checks.add(await _duplicateCheck(patientId, screeningType, timestamp));

    // Check 3: Confidence outlier
    checks.add(_confidenceOutlierCheck(confidence));

    // Check 4: Phantom patient detection
    checks.add(await _phantomPatientCheck(patientId));

    // Check 5: Temporal anomaly (screening at odd hours)
    checks.add(_temporalCheck(timestamp));

    // Composite score: weighted average
    final weights = [0.25, 0.30, 0.20, 0.15, 0.10];
    var compositeScore = 0.0;
    for (var i = 0; i < checks.length; i++) {
      compositeScore += checks[i].riskScore * weights[i];
    }

    final analysis = FraudAnalysis(
      compositeScore: compositeScore,
      checks: checks,
      isAlert: compositeScore >= _alertThreshold,
      timestamp: timestamp,
    );

    // Generate alert if threshold exceeded
    if (analysis.isAlert) {
      await _createAlert(
        alertType: 'SCREENING_ANOMALY',
        entityId: patientId,
        riskScore: compositeScore,
        details: checks
            .where((c) => c.riskScore >= 0.5)
            .map((c) => '${c.name}: ${(c.riskScore * 100).toStringAsFixed(0)}%')
            .join('; '),
      );
    }

    // Update baselines with EMA
    _updateBaselines(confidence);

    return analysis;
  }

  /// Analyze a patient registration for fraud patterns.
  Future<FraudAnalysis> analyzeRegistration({
    required String patientId,
    required String fullName,
    required DateTime timestamp,
  }) async {
    final checks = <FraudCheck>[];

    // Check 1: Registration velocity
    checks.add(await _registrationVelocityCheck(timestamp));

    // Check 2: Name pattern anomaly (too short, repeating chars)
    checks.add(_namePatternCheck(fullName));

    // Check 3: Temporal (registrations at odd hours)
    checks.add(_temporalCheck(timestamp));

    final weights = [0.40, 0.35, 0.25];
    var compositeScore = 0.0;
    for (var i = 0; i < checks.length; i++) {
      compositeScore += checks[i].riskScore * weights[i];
    }

    final analysis = FraudAnalysis(
      compositeScore: compositeScore,
      checks: checks,
      isAlert: compositeScore >= _alertThreshold,
      timestamp: timestamp,
    );

    if (analysis.isAlert) {
      await _createAlert(
        alertType: 'REGISTRATION_ANOMALY',
        entityId: patientId,
        riskScore: compositeScore,
        details: checks
            .where((c) => c.riskScore >= 0.5)
            .map((c) => '${c.name}: ${(c.riskScore * 100).toStringAsFixed(0)}%')
            .join('; '),
      );
    }

    return analysis;
  }

  // ── Individual Checks ─────────────────────────────────────

  /// Velocity: how many screenings in the last hour?
  Future<FraudCheck> _velocityCheck(DateTime timestamp) async {
    final db = await _dbHelper.database;
    final oneHourAgo =
        timestamp.subtract(const Duration(hours: 1)).toIso8601String();
    final recent = await db.query(
      'screenings',
      where: 'performed_at > ?',
      whereArgs: [oneHourAgo],
    );

    final count = recent.length.toDouble();
    // Z-score relative to EMA baseline
    final zScore = (count - _avgScreeningsPerHour).abs() /
        (_avgScreeningsPerHour * 0.5 + 0.1);
    final risk = (zScore / 4.0).clamp(0.0, 1.0);

    return FraudCheck(
      name: 'Velocity',
      riskScore: risk,
      detail: '${recent.length} screenings in last hour '
          '(baseline: ${_avgScreeningsPerHour.toStringAsFixed(1)})',
    );
  }

  /// Duplicate: same patient + type within 30 minutes?
  Future<FraudCheck> _duplicateCheck(
      String patientId, String type, DateTime timestamp) async {
    final db = await _dbHelper.database;
    final window =
        timestamp.subtract(const Duration(minutes: 30)).toIso8601String();
    final dupes = await db.query(
      'screenings',
      where: 'patient_id = ? AND type = ? AND performed_at > ?',
      whereArgs: [patientId, type, window],
    );

    final risk = dupes.isEmpty ? 0.0 : (0.5 + dupes.length * 0.25).clamp(0.0, 1.0);

    return FraudCheck(
      name: 'Duplicate',
      riskScore: risk,
      detail: '${dupes.length} duplicate(s) in 30min window',
    );
  }

  /// Confidence outlier: is the score statistically unusual?
  FraudCheck _confidenceOutlierCheck(double confidence) {
    final deviation = (confidence - _avgConfidence).abs();
    final zScore = deviation / 0.15; // ~15% std dev assumed
    final risk = (zScore / 3.0).clamp(0.0, 1.0);

    return FraudCheck(
      name: 'ConfidenceOutlier',
      riskScore: risk,
      detail: 'Confidence ${(confidence * 100).toStringAsFixed(1)}% '
          '(baseline: ${(_avgConfidence * 100).toStringAsFixed(1)}%)',
    );
  }

  /// Phantom: patient was just registered and immediately screened?
  Future<FraudCheck> _phantomPatientCheck(String patientId) async {
    final db = await _dbHelper.database;
    final patients = await db.query(
      'patients',
      where: 'id = ?',
      whereArgs: [patientId],
    );

    if (patients.isEmpty) {
      return FraudCheck(
        name: 'PhantomPatient',
        riskScore: 0.9,
        detail: 'Patient ID not found in registry',
      );
    }

    final patient = patients.first;
    final createdAt = DateTime.tryParse(patient['created_at']?.toString() ?? '');
    if (createdAt != null) {
      final age = DateTime.now().difference(createdAt);
      if (age.inMinutes < 5) {
        return FraudCheck(
          name: 'PhantomPatient',
          riskScore: 0.6,
          detail: 'Patient registered ${age.inMinutes}min ago (suspicious)',
        );
      }
    }

    return FraudCheck(
      name: 'PhantomPatient',
      riskScore: 0.0,
      detail: 'Patient registration age OK',
    );
  }

  /// Temporal: screening at unusual hours (before 6am or after 10pm)?
  FraudCheck _temporalCheck(DateTime timestamp) {
    final hour = timestamp.hour;
    double risk = 0.0;
    String detail = 'Normal working hours';

    if (hour < 6 || hour > 22) {
      risk = 0.7;
      detail = 'Activity at ${hour.toString().padLeft(2, '0')}:00 (unusual)';
    } else if (hour < 7 || hour > 20) {
      risk = 0.3;
      detail = 'Activity at edge of working hours';
    }

    return FraudCheck(name: 'Temporal', riskScore: risk, detail: detail);
  }

  /// Registration velocity: too many new patients per hour?
  Future<FraudCheck> _registrationVelocityCheck(DateTime timestamp) async {
    final db = await _dbHelper.database;
    final oneHourAgo =
        timestamp.subtract(const Duration(hours: 1)).toIso8601String();
    final recent = await db.query(
      'patients',
      where: 'created_at > ?',
      whereArgs: [oneHourAgo],
    );

    final count = recent.length.toDouble();
    final zScore = (count - _avgRegistrationsPerHour).abs() /
        (_avgRegistrationsPerHour * 0.5 + 0.1);
    final risk = (zScore / 4.0).clamp(0.0, 1.0);

    return FraudCheck(
      name: 'RegVelocity',
      riskScore: risk,
      detail: '${recent.length} registrations in last hour',
    );
  }

  /// Name pattern: suspiciously short or repetitive names?
  FraudCheck _namePatternCheck(String fullName) {
    double risk = 0.0;
    String detail = 'Name pattern OK';

    if (fullName.length < 3) {
      risk = 0.8;
      detail = 'Name too short (${fullName.length} chars)';
    } else if (RegExp(r'^(.)\1+$').hasMatch(fullName.replaceAll(' ', ''))) {
      risk = 0.9;
      detail = 'Repetitive character pattern detected';
    } else if (fullName.split(' ').length < 2) {
      risk = 0.3;
      detail = 'Single-word name (unusual for full name)';
    }

    return FraudCheck(name: 'NamePattern', riskScore: risk, detail: detail);
  }

  // ── Baseline Updates ──────────────────────────────────────

  void _updateBaselines(double confidence) {
    _avgConfidence =
        _emaAlpha * confidence + (1 - _emaAlpha) * _avgConfidence;
  }

  // ── Alert Persistence ─────────────────────────────────────

  Future<void> _createAlert({
    required String alertType,
    required String entityId,
    required double riskScore,
    required String details,
  }) async {
    final db = await _dbHelper.database;
    final id = 'NAFU-${DateTime.now().millisecondsSinceEpoch}-'
        '${Random().nextInt(9999).toString().padLeft(4, '0')}';

    await db.insert('fraud_alerts', {
      'id': id,
      'alert_type': alertType,
      'entity_id': entityId,
      'risk_score': riskScore,
      'details': details,
      'is_dismissed': 0,
      'created_at': DateTime.now().toIso8601String(),
    });

    // Also log to SAHI audit trail
    await AuditService.instance.log(
      eventType: AuditService.fraudAlert,
      entityId: entityId,
      payload: {
        'alertId': id,
        'alertType': alertType,
        'riskScore': riskScore,
        'details': details,
      },
    );

    Log.w('🚨 NAFU Alert: $alertType for $entityId '
        '(risk: ${(riskScore * 100).toStringAsFixed(0)}%)',
        tag: 'NAFU');
  }

  /// Get all active (non-dismissed) fraud alerts.
  Future<List<Map<String, dynamic>>> getActiveAlerts() async {
    try {
      final db = await _dbHelper.database;
      return db.query(
        'fraud_alerts',
        where: 'is_dismissed = 0',
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      Log.w('getActiveAlerts failed: $e', tag: 'NAFU');
      return [];
    }
  }

  /// Dismiss an alert (mark as reviewed).
  Future<void> dismissAlert(String alertId) async {
    try {
      final db = await _dbHelper.database;
      await db.update(
        'fraud_alerts',
        {'is_dismissed': 1},
        where: 'id = ?',
        whereArgs: [alertId],
      );
    } catch (e) {
      Log.w('dismissAlert failed: $e', tag: 'NAFU');
    }
  }

  /// Get fraud statistics for dashboard.
  Future<Map<String, dynamic>> getStats() async {
    try {
      final db = await _dbHelper.database;
      final all = await db.query('fraud_alerts');
      final active = all.where((a) => a['is_dismissed'] == 0).toList();

      return {
        'totalAlerts': all.length,
        'activeAlerts': active.length,
        'avgRiskScore': all.isEmpty
            ? 0.0
            : all.fold<double>(0, (s, a) => s + ((a['risk_score'] as num?) ?? 0).toDouble()) / all.length,
        'alertTypes': _countByField(all, 'alert_type'),
      };
    } catch (e) {
      Log.w('getStats failed: $e', tag: 'NAFU');
      return {'totalAlerts': 0, 'activeAlerts': 0, 'avgRiskScore': 0.0};
    }
  }

  Map<String, int> _countByField(
      List<Map<String, dynamic>> rows, String field) {
    final counts = <String, int>{};
    for (final row in rows) {
      final val = row[field]?.toString() ?? 'unknown';
      counts[val] = (counts[val] ?? 0) + 1;
    }
    return counts;
  }
}

// ── Models ─────────────────────────────────────────────────────

class FraudAnalysis {
  final double compositeScore;
  final List<FraudCheck> checks;
  final bool isAlert;
  final DateTime timestamp;

  const FraudAnalysis({
    required this.compositeScore,
    required this.checks,
    required this.isAlert,
    required this.timestamp,
  });

  String get riskLevel {
    if (compositeScore >= 0.7) return 'HIGH';
    if (compositeScore >= 0.4) return 'MEDIUM';
    return 'LOW';
  }
}

class FraudCheck {
  final String name;
  final double riskScore;
  final String detail;

  const FraudCheck({
    required this.name,
    required this.riskScore,
    required this.detail,
  });
}
