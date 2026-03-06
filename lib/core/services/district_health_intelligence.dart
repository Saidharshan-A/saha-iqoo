/// SAHA-Quantum — District Health Intelligence Layer
///
/// Aggregates anonymized screening data at the district level to provide:
///   • Risk heatmap generation (per-village/block)
///   • Coverage statistics (screenings/population)
///   • Outlier detection alerts (abnormal clusters)
///   • Trend analysis (week-over-week, monthly)
///   • Sync aggregated insights when network returns
///
/// CRITICAL: No personal data is EVER aggregated. All data is anonymized
/// at the point of aggregation — only counts, rates, and statistical
/// summaries leave the device.

import 'dart:convert';

import '../db/database_helper.dart';
import '../services/audit_service.dart';
import '../utils/logger.dart';

// ════════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ════════════════════════════════════════════════════════════════════════════

/// Aggregated district-level health summary.
class DistrictHealthSummary {
  const DistrictHealthSummary({
    required this.districtName,
    required this.totalScreenings,
    required this.cancerScreenings,
    required this.tbScreenings,
    required this.highRiskCount,
    required this.mediumRiskCount,
    required this.lowRiskCount,
    required this.coverageRate,
    required this.avgConfidence,
    required this.totalPatients,
    required this.villageSummaries,
    required this.outlierAlerts,
    required this.generatedAt,
  });

  final String districtName;
  final int totalScreenings;
  final int cancerScreenings;
  final int tbScreenings;
  final int highRiskCount;
  final int mediumRiskCount;
  final int lowRiskCount;
  final double coverageRate;
  final double avgConfidence;
  final int totalPatients;
  final List<VillageSummary> villageSummaries;
  final List<OutlierAlert> outlierAlerts;
  final DateTime generatedAt;

  Map<String, dynamic> toAnonymizedJson() => {
        'district': districtName,
        'total_screenings': totalScreenings,
        'cancer_screenings': cancerScreenings,
        'tb_screenings': tbScreenings,
        'risk_distribution': {
          'high': highRiskCount,
          'medium': mediumRiskCount,
          'low': lowRiskCount,
        },
        'coverage_rate': coverageRate,
        'avg_confidence': avgConfidence,
        'total_patients': totalPatients,
        'villages': villageSummaries.map((v) => v.toMap()).toList(),
        'outlier_alerts': outlierAlerts.map((a) => a.toMap()).toList(),
        'generated_at': generatedAt.toIso8601String(),
        'anonymized': true,
        'schema_version': '1.0',
      };
}

/// Per-village aggregated statistics (no PII).
class VillageSummary {
  const VillageSummary({
    required this.villageName,
    required this.screeningCount,
    required this.highRiskCount,
    required this.coverageRate,
    required this.riskScore,
  });

  final String villageName;
  final int screeningCount;
  final int highRiskCount;
  final double coverageRate;
  final double riskScore; // 0-1, aggregate risk level

  Map<String, dynamic> toMap() => {
        'village': villageName,
        'screenings': screeningCount,
        'high_risk': highRiskCount,
        'coverage': coverageRate,
        'risk_score': riskScore,
      };
}

/// Outlier detection alert.
class OutlierAlert {
  const OutlierAlert({
    required this.id,
    required this.alertType,
    required this.location,
    required this.description,
    required this.severity,
    required this.metric,
    required this.expectedValue,
    required this.observedValue,
    required this.zScore,
    required this.createdAt,
  });

  final String id;
  final String alertType;
  final String location;
  final String description;
  final String severity; // 'info', 'warning', 'critical'
  final String metric;
  final double expectedValue;
  final double observedValue;
  final double zScore;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': alertType,
        'location': location,
        'description': description,
        'severity': severity,
        'metric': metric,
        'expected': expectedValue,
        'observed': observedValue,
        'z_score': zScore,
        'created_at': createdAt.toIso8601String(),
      };
}

/// Coverage statistics for a time period.
class CoverageStats {
  const CoverageStats({
    required this.period,
    required this.totalScreenings,
    required this.uniquePatients,
    required this.cancerScreenings,
    required this.tbScreenings,
    required this.highRiskReferrals,
    required this.averageConfidence,
    required this.coveragePercentage,
  });

  final String period;
  final int totalScreenings;
  final int uniquePatients;
  final int cancerScreenings;
  final int tbScreenings;
  final int highRiskReferrals;
  final double averageConfidence;
  final double coveragePercentage;
}

/// Risk heatmap data point.
class HeatmapPoint {
  const HeatmapPoint({
    required this.location,
    required this.riskScore,
    required this.screeningCount,
    required this.highRiskCount,
    required this.intensity,
  });

  final String location;
  final double riskScore;
  final int screeningCount;
  final int highRiskCount;
  final double intensity; // 0-1, for heatmap color
}

// ════════════════════════════════════════════════════════════════════════════
//  DISTRICT HEALTH INTELLIGENCE
// ════════════════════════════════════════════════════════════════════════════

class DistrictHealthIntelligence {
  DistrictHealthIntelligence._();
  static final DistrictHealthIntelligence instance =
      DistrictHealthIntelligence._();

  static const _tag = 'DHI';
  bool _initialized = false;

  // ── DB table ───────────────────────────────────────────────────────
  static const _tableAggregates = 'dhi_aggregates';
  static const _tableAlerts = 'dhi_alerts';

  Future<void> initialize() async {
    if (_initialized) return;

    final db = await DatabaseHelper.instance.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableAggregates (
        id            TEXT PRIMARY KEY,
        district      TEXT NOT NULL,
        period        TEXT NOT NULL,
        data_json     TEXT NOT NULL,
        created_at    TEXT NOT NULL,
        is_synced     INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableAlerts (
        id            TEXT PRIMARY KEY,
        alert_type    TEXT NOT NULL,
        location      TEXT NOT NULL,
        severity      TEXT NOT NULL,
        description   TEXT NOT NULL,
        metric        TEXT,
        expected_val  REAL,
        observed_val  REAL,
        z_score       REAL,
        is_dismissed  INTEGER NOT NULL DEFAULT 0,
        created_at    TEXT NOT NULL
      )
    ''');

    _initialized = true;
    Log.i('District Health Intelligence ready', tag: _tag);
  }

  // ══════════════════════════════════════════════════════════════════════
  //  AGGREGATION (Anonymized — no PII)
  // ══════════════════════════════════════════════════════════════════════

  /// Generate a district health summary from local anonymized data.
  Future<DistrictHealthSummary> generateSummary() async {
    await initialize();
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();

    // Get all screenings (anonymized — no patient names)
    final screenings = await db.query('screenings');
    final patients = await db.query('patients');

    // Aggregate by type
    int cancer = 0, tb = 0;
    int highRisk = 0, medRisk = 0, lowRisk = 0;
    double totalConf = 0;

    for (final s in screenings) {
      final type = s['type'] as String? ?? '';
      if (type.contains('cancer')) {
        cancer++;
      } else if (type.contains('tb')) {
        tb++;
      }

      final risk = s['risk_level'] as String? ?? 'low';
      switch (risk) {
        case 'high':
          highRisk++;
          break;
        case 'medium':
          medRisk++;
          break;
        default:
          lowRisk++;
      }

      totalConf += (s['confidence'] as num?)?.toDouble() ?? 0;
    }

    final avgConf =
        screenings.isNotEmpty ? totalConf / screenings.length : 0.0;

    // Aggregate by village (anonymized)
    final villageMap = <String, _VillageAgg>{};
    for (final p in patients) {
      final village = p['village'] as String? ?? 'Unknown';
      villageMap.putIfAbsent(village, () => _VillageAgg());
      villageMap[village]!.patientCount++;
    }

    for (final s in screenings) {
      final pid = s['patient_id'] as String? ?? '';
      // Find patient village
      final patient = patients.cast<Map<String, dynamic>?>().firstWhere(
            (p) => p != null && p['id'] == pid,
            orElse: () => null,
          );
      if (patient != null) {
        final village = patient['village'] as String? ?? 'Unknown';
        villageMap.putIfAbsent(village, () => _VillageAgg());
        villageMap[village]!.screeningCount++;
        final risk = s['risk_level'] as String? ?? 'low';
        if (risk == 'high') villageMap[village]!.highRiskCount++;
      }
    }

    final villages = villageMap.entries.map((e) {
      final v = e.value;
      final coverage = v.patientCount > 0
          ? v.screeningCount / v.patientCount
          : 0.0;
      final riskScore = v.screeningCount > 0
          ? v.highRiskCount / v.screeningCount
          : 0.0;
      return VillageSummary(
        villageName: e.key,
        screeningCount: v.screeningCount,
        highRiskCount: v.highRiskCount,
        coverageRate: coverage.clamp(0.0, 1.0),
        riskScore: riskScore.clamp(0.0, 1.0),
      );
    }).toList();

    // Run outlier detection
    final outliers = _detectOutliers(villages);

    // Persist aggregated summary
    final summary = DistrictHealthSummary(
      districtName: _inferDistrict(patients),
      totalScreenings: screenings.length,
      cancerScreenings: cancer,
      tbScreenings: tb,
      highRiskCount: highRisk,
      mediumRiskCount: medRisk,
      lowRiskCount: lowRisk,
      coverageRate: patients.isNotEmpty
          ? screenings.length / patients.length
          : 0.0,
      avgConfidence: avgConf,
      totalPatients: patients.length,
      villageSummaries: villages,
      outlierAlerts: outliers,
      generatedAt: now,
    );

    // Store anonymized aggregate
    await db.insert(_tableAggregates, {
      'id': 'dhi-${now.millisecondsSinceEpoch}',
      'district': summary.districtName,
      'period': '${now.year}-${now.month.toString().padLeft(2, '0')}',
      'data_json': jsonEncode(summary.toAnonymizedJson()),
      'created_at': now.toIso8601String(),
    });

    // Store outlier alerts
    for (final alert in outliers) {
      await db.insert(_tableAlerts, {
        'id': alert.id,
        'alert_type': alert.alertType,
        'location': alert.location,
        'severity': alert.severity,
        'description': alert.description,
        'metric': alert.metric,
        'expected_val': alert.expectedValue,
        'observed_val': alert.observedValue,
        'z_score': alert.zScore,
        'created_at': alert.createdAt.toIso8601String(),
      });
    }

    await AuditService.instance.log(
      eventType: 'dhi_summary_generated',
      entityId: summary.districtName,
      payload: {
        'total_screenings': screenings.length,
        'villages': villages.length,
        'outliers': outliers.length,
      },
    );

    Log.i('District summary generated: '
        '${screenings.length} screenings, ${villages.length} villages, '
        '${outliers.length} outlier alerts', tag: _tag);

    return summary;
  }

  /// Generate risk heatmap data points.
  Future<List<HeatmapPoint>> generateHeatmap() async {
    await initialize();
    final db = await DatabaseHelper.instance.database;

    final patients = await db.query('patients');
    final screenings = await db.query('screenings');

    final villageData = <String, _HeatmapAgg>{};

    for (final s in screenings) {
      final pid = s['patient_id'] as String? ?? '';
      final patient = patients.cast<Map<String, dynamic>?>().firstWhere(
            (p) => p != null && p['id'] == pid,
            orElse: () => null,
          );
      if (patient == null) continue;

      final village = patient['village'] as String? ?? 'Unknown';
      villageData.putIfAbsent(village, () => _HeatmapAgg());
      villageData[village]!.count++;

      final risk = s['risk_level'] as String? ?? 'low';
      if (risk == 'high') villageData[village]!.highRisk++;
      final conf = (s['confidence'] as num?)?.toDouble() ?? 0;
      villageData[village]!.totalConf += conf;
    }

    return villageData.entries.map((e) {
      final d = e.value;
      final riskScore =
          d.count > 0 ? d.highRisk / d.count : 0.0;
      return HeatmapPoint(
        location: e.key,
        riskScore: riskScore,
        screeningCount: d.count,
        highRiskCount: d.highRisk,
        intensity: riskScore.clamp(0.0, 1.0),
      );
    }).toList()
      ..sort((a, b) => b.riskScore.compareTo(a.riskScore));
  }

  /// Get coverage statistics for a time period.
  Future<CoverageStats> getCoverageStats({String? period}) async {
    await initialize();
    final db = await DatabaseHelper.instance.database;

    final screenings = await db.query('screenings');
    final patients = await db.query('patients');

    final uniquePatientIds = <String>{};
    int cancer = 0, tb = 0, highRisk = 0;
    double totalConf = 0;

    for (final s in screenings) {
      uniquePatientIds.add(s['patient_id'] as String? ?? '');
      final type = s['type'] as String? ?? '';
      if (type.contains('cancer')) cancer++;
      if (type.contains('tb')) tb++;
      if (s['risk_level'] == 'high') highRisk++;
      totalConf += (s['confidence'] as num?)?.toDouble() ?? 0;
    }

    return CoverageStats(
      period: period ?? 'all-time',
      totalScreenings: screenings.length,
      uniquePatients: uniquePatientIds.length,
      cancerScreenings: cancer,
      tbScreenings: tb,
      highRiskReferrals: highRisk,
      averageConfidence:
          screenings.isNotEmpty ? totalConf / screenings.length : 0,
      coveragePercentage: patients.isNotEmpty
          ? (uniquePatientIds.length / patients.length * 100)
              .clamp(0, 100)
          : 0,
    );
  }

  /// Get active outlier alerts.
  Future<List<OutlierAlert>> getActiveAlerts() async {
    await initialize();
    final db = await DatabaseHelper.instance.database;

    final rows = await db.query(
      _tableAlerts,
      where: 'is_dismissed = ?',
      whereArgs: [0],
      orderBy: 'created_at DESC',
    );

    return rows.map((r) => OutlierAlert(
          id: r['id'] as String? ?? '',
          alertType: r['alert_type'] as String? ?? '',
          location: r['location'] as String? ?? '',
          description: r['description'] as String? ?? '',
          severity: r['severity'] as String? ?? 'info',
          metric: r['metric'] as String? ?? '',
          expectedValue: (r['expected_val'] as num?)?.toDouble() ?? 0,
          observedValue: (r['observed_val'] as num?)?.toDouble() ?? 0,
          zScore: (r['z_score'] as num?)?.toDouble() ?? 0,
          createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ??
              DateTime.now(),
        )).toList();
  }

  /// Dismiss an outlier alert.
  Future<void> dismissAlert(String alertId) async {
    await initialize();
    final db = await DatabaseHelper.instance.database;
    await db.update(
      _tableAlerts,
      {'is_dismissed': 1},
      where: 'id = ?',
      whereArgs: [alertId],
    );
  }

  /// Get stored aggregate summaries for sync.
  Future<List<Map<String, dynamic>>> getPendingSyncData() async {
    await initialize();
    final db = await DatabaseHelper.instance.database;
    return db.query(
      _tableAggregates,
      where: 'is_synced = ?',
      whereArgs: [0],
    );
  }

  /// Mark aggregates as synced.
  Future<void> markSynced(List<String> ids) async {
    final db = await DatabaseHelper.instance.database;
    for (final id in ids) {
      await db.update(
        _tableAggregates,
        {'is_synced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  OUTLIER DETECTION
  // ══════════════════════════════════════════════════════════════════════

  List<OutlierAlert> _detectOutliers(List<VillageSummary> villages) {
    if (villages.length < 3) return [];

    final alerts = <OutlierAlert>[];
    final now = DateTime.now();

    // Detect risk score outliers (z-score method)
    final riskScores = villages.map((v) => v.riskScore).toList();
    final meanRisk =
        riskScores.fold<double>(0, (a, b) => a + b) / riskScores.length;
    double varRisk = 0;
    for (final r in riskScores) {
      varRisk += (r - meanRisk) * (r - meanRisk);
    }
    final stdRisk = _sqrt(varRisk / riskScores.length);

    for (final v in villages) {
      if (stdRisk > 0.001) {
        final z = (v.riskScore - meanRisk) / stdRisk;
        if (z > 2.0) {
          alerts.add(OutlierAlert(
            id: 'outlier-risk-${v.villageName}-${now.millisecondsSinceEpoch}',
            alertType: 'high_risk_cluster',
            location: v.villageName,
            description:
                'Unusually high cancer/TB risk detected in ${v.villageName} '
                '(${(v.riskScore * 100).toStringAsFixed(0)}% high-risk rate, '
                'z-score: ${z.toStringAsFixed(2)})',
            severity: z > 3.0 ? 'critical' : 'warning',
            metric: 'risk_score',
            expectedValue: meanRisk,
            observedValue: v.riskScore,
            zScore: z,
            createdAt: now,
          ));
        }
      }
    }

    // Detect coverage outliers (villages with very low coverage)
    final coverages = villages.map((v) => v.coverageRate).toList();
    final meanCov =
        coverages.fold<double>(0, (a, b) => a + b) / coverages.length;
    double varCov = 0;
    for (final c in coverages) {
      varCov += (c - meanCov) * (c - meanCov);
    }
    final stdCov = _sqrt(varCov / coverages.length);

    for (final v in villages) {
      if (stdCov > 0.001 && v.screeningCount > 0) {
        final z = (v.coverageRate - meanCov) / stdCov;
        if (z < -2.0) {
          alerts.add(OutlierAlert(
            id: 'outlier-cov-${v.villageName}-${now.millisecondsSinceEpoch}',
            alertType: 'low_coverage',
            location: v.villageName,
            description:
                'Low screening coverage in ${v.villageName} '
                '(${(v.coverageRate * 100).toStringAsFixed(0)}%, '
                'z-score: ${z.toStringAsFixed(2)})',
            severity: 'warning',
            metric: 'coverage_rate',
            expectedValue: meanCov,
            observedValue: v.coverageRate,
            zScore: z,
            createdAt: now,
          ));
        }
      }
    }

    Log.d('Outlier detection: ${alerts.length} alerts from '
        '${villages.length} villages', tag: _tag);

    return alerts;
  }

  String _inferDistrict(List<Map<String, dynamic>> patients) {
    // Get most common district from patients
    final counts = <String, int>{};
    for (final p in patients) {
      final d = p['district'] as String? ?? 'Unknown';
      counts[d] = (counts[d] ?? 0) + 1;
    }
    if (counts.isEmpty) return 'Unknown District';
    return counts.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    var r = x;
    for (int i = 0; i < 15; i++) {
      r = (r + x / r) * 0.5;
    }
    return r;
  }
}

class _VillageAgg {
  int patientCount = 0;
  int screeningCount = 0;
  int highRiskCount = 0;
}

class _HeatmapAgg {
  int count = 0;
  int highRisk = 0;
  double totalConf = 0;
}
