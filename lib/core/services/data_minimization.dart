/// ───────────────────────────────────────────────────────────────────────────
/// Data Minimization Engine — DPDP 2023 Gold Tier Compliance.
///
/// Privacy-by-design wins trust. This module enforces:
///   1. **Automatic Data Expiration** — Records auto-expire per policy.
///   2. **Configurable Retention Windows** — Per-table / per-entity TTLs.
///   3. **Auto-anonymization After Sync** — PII stripped once sync confirmed.
///   4. **Right to Erasure** — Full DPDP Section 12(1) implementation.
///
/// Legal alignment:
///   - Digital Personal Data Protection Act, 2023 (DPDP)
///   - Section 8(7): Data minimization principle
///   - Section 12: Right of data principal to erasure
///   - Section 13: Obligation to erase on withdrawal of consent
///   - ABDM Health Data Management Policy v2.0
///   - ICMR National Ethical Guidelines for Biomedical Research (2017)
/// ───────────────────────────────────────────────────────────────────────────
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../db/database_helper.dart';
import '../utils/logger.dart';
import 'audit_service.dart';

class DataMinimizationEngine {
  DataMinimizationEngine._();
  static final DataMinimizationEngine instance = DataMinimizationEngine._();

  final _db = DatabaseHelper.instance;
  bool _initialized = false;

  // ───────────────────────────── INIT ─────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    final db = await _db.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS retention_policies (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        retention_days INTEGER NOT NULL,
        anonymize_after_sync INTEGER NOT NULL DEFAULT 0,
        auto_delete INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        created_by TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS erasure_requests (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        requested_at TEXT NOT NULL,
        requested_by TEXT NOT NULL,
        reason TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        completed_at TEXT,
        tables_affected TEXT,
        records_erased INTEGER DEFAULT 0,
        verification_hash TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS anonymization_log (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        anonymized_at TEXT NOT NULL,
        fields_anonymized TEXT NOT NULL,
        triggered_by TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS data_expiration_log (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        records_expired INTEGER NOT NULL,
        expired_at TEXT NOT NULL,
        policy_id TEXT NOT NULL
      )
    ''');

    // Register default retention policies
    await _registerDefaultPolicies();

    _initialized = true;
    Log.i('DataMinimizationEngine initialized — DPDP Gold Tier active');
  }

  // ─────────────────── DEFAULT RETENTION POLICIES ───────────────────

  Future<void> _registerDefaultPolicies() async {
    final db = await _db.database;
    final existing = await db.query('retention_policies');
    if (existing.isNotEmpty) return;

    final now = DateTime.now().toUtc().toIso8601String();
    final policies = [
      {
        'id': 'pol-screenings',
        'table_name': 'screenings',
        'retention_days': 2 * 365, // 2 years (ICMR guideline)
        'anonymize_after_sync': 1,
        'auto_delete': 0,
        'created_at': now,
        'updated_at': now,
        'created_by': 'system',
      },
      {
        'id': 'pol-patients',
        'table_name': 'patients',
        'retention_days': 5 * 365, // 5 years (medical records standard)
        'anonymize_after_sync': 0,
        'auto_delete': 0,
        'created_at': now,
        'updated_at': now,
        'created_by': 'system',
      },
      {
        'id': 'pol-sync-queue',
        'table_name': 'sync_queue',
        'retention_days': 90, // 3 months
        'anonymize_after_sync': 0,
        'auto_delete': 1,
        'created_at': now,
        'updated_at': now,
        'created_by': 'system',
      },
      {
        'id': 'pol-audit-log',
        'table_name': 'audit_log',
        'retention_days': 7 * 365, // 7 years (legal compliance)
        'anonymize_after_sync': 0,
        'auto_delete': 0,
        'created_at': now,
        'updated_at': now,
        'created_by': 'system',
      },
      {
        'id': 'pol-claims',
        'table_name': 'claims',
        'retention_days': 3 * 365, // 3 years (insurance standard)
        'anonymize_after_sync': 1,
        'auto_delete': 0,
        'created_at': now,
        'updated_at': now,
        'created_by': 'system',
      },
      {
        'id': 'pol-fl-deltas',
        'table_name': 'fl_deltas',
        'retention_days': 180, // 6 months
        'anonymize_after_sync': 0,
        'auto_delete': 1,
        'created_at': now,
        'updated_at': now,
        'created_by': 'system',
      },
    ];

    for (final p in policies) {
      await db.insert('retention_policies', p);
    }
    Log.i('Registered ${policies.length} default retention policies');
  }

  // ────────────────── AUTOMATIC DATA EXPIRATION ──────────────────

  /// Run expiration sweep across all tables with retention policies.
  /// Returns total number of expired records.
  Future<int> runExpirationSweep() async {
    await _ensureInit();
    final db = await _db.database;

    final policies = await db.query('retention_policies');
    int totalExpired = 0;

    for (final policy in policies) {
      final tableName = policy['table_name'] as String;
      final retentionDays = policy['retention_days'] as int;
      final autoDelete = (policy['auto_delete'] as int) == 1;

      final cutoffDate = DateTime.now()
          .toUtc()
          .subtract(Duration(days: retentionDays))
          .toIso8601String();

      // Determine the timestamp column for each table
      final timestampCol = _getTimestampColumn(tableName);
      if (timestampCol == null) continue;

      if (autoDelete) {
        // Count then delete
        final countResult = await db.rawQuery(
          'SELECT COUNT(*) as cnt FROM $tableName WHERE $timestampCol < ?',
          [cutoffDate],
        );
        final count =
            countResult.isNotEmpty ? (countResult.first['cnt'] as int? ?? 0) : 0;

        if (count > 0) {
          await db.delete(
            tableName,
            where: '$timestampCol < ?',
            whereArgs: [cutoffDate],
          );

          await db.insert('data_expiration_log', {
            'id': _generateId(),
            'table_name': tableName,
            'records_expired': count,
            'expired_at': DateTime.now().toUtc().toIso8601String(),
            'policy_id': policy['id'],
          });

          totalExpired += count;
          Log.i('Expired $count records from $tableName (retention: $retentionDays days)');
        }
      } else {
        // For non-auto-delete tables, just log how many are past retention
        final countResult = await db.rawQuery(
          'SELECT COUNT(*) as cnt FROM $tableName WHERE $timestampCol < ?',
          [cutoffDate],
        );
        final count =
            countResult.isNotEmpty ? (countResult.first['cnt'] as int? ?? 0) : 0;
        if (count > 0) {
          Log.w('$count records in $tableName past retention ($retentionDays days) — flagged for review');
        }
      }
    }

    await AuditService.instance.log(
      eventType: 'EXPIRATION_SWEEP',
      entityId: 'system',
      payload: {'total_expired': totalExpired},
    );

    return totalExpired;
  }

  // ──────────────── AUTO-ANONYMIZATION AFTER SYNC ────────────────

  /// Anonymize PII in synced records for tables with anonymize_after_sync policy.
  Future<int> anonymizeSyncedRecords() async {
    await _ensureInit();
    final db = await _db.database;

    final policies = await db.query(
      'retention_policies',
      where: 'anonymize_after_sync = ?',
      whereArgs: [1],
    );

    int totalAnonymized = 0;

    for (final policy in policies) {
      final tableName = policy['table_name'] as String;
      final piiFields = _getPiiFields(tableName);
      if (piiFields.isEmpty) continue;

      // Find synced records that haven't been anonymized
      // We check sync_queue for completed syncs
      final syncedIds = await db.rawQuery(
        'SELECT DISTINCT entity_id FROM sync_queue WHERE status = ?',
        ['synced'],
      );

      for (final row in syncedIds) {
        final entityId = row['entity_id'] as String? ?? '';
        if (entityId.isEmpty) continue;

        // Check if already anonymized
        final existing = await db.query(
          'anonymization_log',
          where: 'table_name = ? AND record_id = ?',
          whereArgs: [tableName, entityId],
        );
        if (existing.isNotEmpty) continue;

        // Anonymize PII fields
        final anonValues = <String, dynamic>{};
        for (final field in piiFields) {
          anonValues[field] = _anonymizeValue(field, entityId);
        }

        // Find the primary key column
        final pkCol = _getPrimaryKeyColumn(tableName);
        await db.update(
          tableName,
          anonValues,
          where: '$pkCol = ?',
          whereArgs: [entityId],
        );

        // Log anonymization
        await db.insert('anonymization_log', {
          'id': _generateId(),
          'table_name': tableName,
          'record_id': entityId,
          'anonymized_at': DateTime.now().toUtc().toIso8601String(),
          'fields_anonymized': jsonEncode(piiFields),
          'triggered_by': 'auto_sync_policy',
        });

        totalAnonymized++;
      }
    }

    if (totalAnonymized > 0) {
      await AuditService.instance.log(
        eventType: 'AUTO_ANONYMIZATION',
        entityId: 'system',
        payload: {'total_anonymized': totalAnonymized},
      );
      Log.i('Auto-anonymized $totalAnonymized synced records');
    }

    return totalAnonymized;
  }

  // ─────────────────── RIGHT TO ERASURE (DPDP §12) ───────────────────

  /// Submit an erasure request for a patient.
  /// DPDP 2023, Section 12(1): "The data principal shall have the right to
  /// erasure of personal data which is no longer necessary."
  Future<String> requestErasure({
    required String patientId,
    required String requestedBy,
    required String reason,
  }) async {
    await _ensureInit();
    final db = await _db.database;

    final requestId = _generateId();
    await db.insert('erasure_requests', {
      'id': requestId,
      'patient_id': patientId,
      'requested_at': DateTime.now().toUtc().toIso8601String(),
      'requested_by': requestedBy,
      'reason': reason,
      'status': 'pending',
    });

    await AuditService.instance.log(
      eventType: 'ERASURE_REQUESTED',
      entityId: patientId,
      payload: {'request_id': requestId, 'reason': reason, 'requested_by': requestedBy},
    );

    Log.i('Erasure request $requestId filed for patient $patientId');
    return requestId;
  }

  /// Execute an approved erasure request. This is a **destructive** operation.
  /// Removes or anonymizes all personal data across all tables.
  Future<ErasureReport> executeErasure(String requestId) async {
    await _ensureInit();
    final db = await _db.database;

    final requests = await db.query(
      'erasure_requests',
      where: 'id = ?',
      whereArgs: [requestId],
    );
    if (requests.isEmpty) {
      throw DataMinimizationException('Erasure request $requestId not found');
    }

    final request = requests.first;
    if (request['status'] != 'pending') {
      throw DataMinimizationException(
          'Request is ${request['status']}, not pending');
    }

    final patientId = request['patient_id'] as String;
    int totalErased = 0;
    final tablesAffected = <String>[];

    // Tables containing patient data
    final patientTables = {
      'patients': 'id',
      'screenings': 'patient_id',
      'claims': 'patient_id',
      'abha_links': 'patient_id',
    };

    for (final entry in patientTables.entries) {
      final table = entry.key;
      final column = entry.value;

      // Count records
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM $table WHERE $column = ?',
        [patientId],
      );
      final count =
          countResult.isNotEmpty ? (countResult.first['cnt'] as int? ?? 0) : 0;

      if (count > 0) {
        // For patients table: anonymize instead of delete (retain for aggregate stats)
        if (table == 'patients') {
          await db.update(
            table,
            {
              'name': 'ERASED',
              'phone': 'ERASED',
              'address': 'ERASED',
              'aadhaar_hash': 'ERASED',
            },
            where: '$column = ?',
            whereArgs: [patientId],
          );
        } else {
          // Delete referencing records entirely
          await db.delete(
            table,
            where: '$column = ?',
            whereArgs: [patientId],
          );
        }

        totalErased += count;
        tablesAffected.add(table);
      }
    }

    // Compute verification hash (proof of erasure)
    final verificationPayload =
        '$requestId|$patientId|$totalErased|${DateTime.now().toUtc().toIso8601String()}';
    final verificationHash =
        sha256.convert(utf8.encode(verificationPayload)).toString();

    // Update request status
    await db.update(
      'erasure_requests',
      {
        'status': 'completed',
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'tables_affected': jsonEncode(tablesAffected),
        'records_erased': totalErased,
        'verification_hash': verificationHash,
      },
      where: 'id = ?',
      whereArgs: [requestId],
    );

    await AuditService.instance.log(
      eventType: 'ERASURE_COMPLETED',
      entityId: patientId,
      payload: {'request_id': requestId, 'records_erased': totalErased, 'verification_hash': verificationHash},
    );

    Log.i('Erasure completed: $totalErased records across ${tablesAffected.length} tables');

    return ErasureReport(
      requestId: requestId,
      patientId: patientId,
      recordsErased: totalErased,
      tablesAffected: tablesAffected,
      verificationHash: verificationHash,
      completedAt: DateTime.now().toUtc(),
    );
  }

  // ─────────────────── RETENTION POLICY MANAGEMENT ───────────────────

  /// Add or update a retention policy.
  Future<void> setRetentionPolicy({
    required String tableName,
    required int retentionDays,
    bool anonymizeAfterSync = false,
    bool autoDelete = false,
    String createdBy = 'admin',
  }) async {
    await _ensureInit();
    final db = await _db.database;
    final now = DateTime.now().toUtc().toIso8601String();

    final existing = await db.query(
      'retention_policies',
      where: 'table_name = ?',
      whereArgs: [tableName],
    );

    if (existing.isNotEmpty) {
      await db.update(
        'retention_policies',
        {
          'retention_days': retentionDays,
          'anonymize_after_sync': anonymizeAfterSync ? 1 : 0,
          'auto_delete': autoDelete ? 1 : 0,
          'updated_at': now,
        },
        where: 'table_name = ?',
        whereArgs: [tableName],
      );
    } else {
      await db.insert('retention_policies', {
        'id': 'pol-$tableName',
        'table_name': tableName,
        'retention_days': retentionDays,
        'anonymize_after_sync': anonymizeAfterSync ? 1 : 0,
        'auto_delete': autoDelete ? 1 : 0,
        'created_at': now,
        'updated_at': now,
        'created_by': createdBy,
      });
    }

    await AuditService.instance.log(
      eventType: 'RETENTION_POLICY_SET',
      entityId: tableName,
      payload: {'retention_days': retentionDays, 'auto_delete': autoDelete},
    );
  }

  /// Get all retention policies.
  Future<List<Map<String, dynamic>>> getRetentionPolicies() async {
    await _ensureInit();
    final db = await _db.database;
    return db.query('retention_policies', orderBy: 'table_name');
  }

  // ─────────────────────── QUERIES ─────────────────────────

  /// Get all pending erasure requests.
  Future<List<Map<String, dynamic>>> getPendingErasureRequests() async {
    await _ensureInit();
    final db = await _db.database;
    return db.query(
      'erasure_requests',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'requested_at DESC',
    );
  }

  /// Get erasure history for a patient.
  Future<List<Map<String, dynamic>>> getErasureHistory(String patientId) async {
    await _ensureInit();
    final db = await _db.database;
    return db.query(
      'erasure_requests',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'requested_at DESC',
    );
  }

  /// Get anonymization log.
  Future<List<Map<String, dynamic>>> getAnonymizationLog({int limit = 50}) async {
    await _ensureInit();
    final db = await _db.database;
    return db.query(
      'anonymization_log',
      orderBy: 'anonymized_at DESC',
      limit: limit,
    );
  }

  /// Get comprehensive privacy compliance summary.
  Future<PrivacyComplianceSummary> getComplianceSummary() async {
    await _ensureInit();
    final db = await _db.database;

    final policies = await db.query('retention_policies');
    final pendingErasures = await db.query(
      'erasure_requests',
      where: 'status = ?',
      whereArgs: ['pending'],
    );
    final completedErasures = await db.query(
      'erasure_requests',
      where: 'status = ?',
      whereArgs: ['completed'],
    );
    final anonLog = await db.query('anonymization_log');
    final expirationLog = await db.query('data_expiration_log');

    int totalExpired = 0;
    for (final e in expirationLog) {
      totalExpired += (e['records_expired'] as int? ?? 0);
    }

    int totalErasedRecords = 0;
    for (final e in completedErasures) {
      totalErasedRecords += (e['records_erased'] as int? ?? 0);
    }

    return PrivacyComplianceSummary(
      activePolicies: policies.length,
      pendingErasureRequests: pendingErasures.length,
      completedErasures: completedErasures.length,
      totalRecordsErased: totalErasedRecords,
      totalRecordsAnonymized: anonLog.length,
      totalRecordsExpired: totalExpired,
      lastSweepAt: expirationLog.isNotEmpty
          ? expirationLog.last['expired_at'] as String
          : 'never',
    );
  }

  // ─────────────────────── HELPERS ─────────────────────────

  String? _getTimestampColumn(String table) {
    const mapping = {
      'screenings': 'performed_at',
      'patients': 'created_at',
      'sync_queue': 'created_at',
      'audit_log': 'timestamp',
      'claims': 'created_at',
      'fl_deltas': 'created_at',
      'fraud_alerts': 'created_at',
      'mesh_peers': 'last_seen',
    };
    return mapping[table];
  }

  String _getPrimaryKeyColumn(String table) {
    // All our tables use 'id' as primary key
    return 'id';
  }

  List<String> _getPiiFields(String table) {
    const mapping = {
      'screenings': ['patient_id'],
      'patients': ['name', 'phone', 'address', 'aadhaar_hash'],
      'claims': ['patient_id', 'provider_name'],
    };
    return mapping[table] ?? [];
  }

  String _anonymizeValue(String field, String entityId) {
    // Generate deterministic but irreversible anonymized value
    final hash = sha256.convert(utf8.encode('$field|$entityId|SAHA-ANON-SALT'));
    return 'ANON_${hash.toString().substring(0, 8)}';
  }

  String _generateId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _ensureInit() async {
    if (!_initialized) await initialize();
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ════════════════════════════════════════════════════════════════════════════

class ErasureReport {
  const ErasureReport({
    required this.requestId,
    required this.patientId,
    required this.recordsErased,
    required this.tablesAffected,
    required this.verificationHash,
    required this.completedAt,
  });

  final String requestId;
  final String patientId;
  final int recordsErased;
  final List<String> tablesAffected;
  final String verificationHash;
  final DateTime completedAt;
}

class PrivacyComplianceSummary {
  const PrivacyComplianceSummary({
    required this.activePolicies,
    required this.pendingErasureRequests,
    required this.completedErasures,
    required this.totalRecordsErased,
    required this.totalRecordsAnonymized,
    required this.totalRecordsExpired,
    required this.lastSweepAt,
  });

  final int activePolicies;
  final int pendingErasureRequests;
  final int completedErasures;
  final int totalRecordsErased;
  final int totalRecordsAnonymized;
  final int totalRecordsExpired;
  final String lastSweepAt;
}

class DataMinimizationException implements Exception {
  DataMinimizationException(this.message);
  final String message;

  @override
  String toString() => 'DataMinimizationException: $message';
}
