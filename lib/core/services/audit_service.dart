import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../db/database_helper.dart';
import '../utils/logger.dart';

/// SAHI/BODH Audit Trail — tamper-evident, append-only event log.
///
/// **SAHI** (Secure Audit for Health Integrity): Every mutation
/// (patient CRUD, screening, claim, sync, model update) is logged
/// with a SHA-256 chain hash linking each entry to its predecessor,
/// making post-hoc tampering detectable.
///
/// **BODH** (Blockchain-Oriented Data Hash): Each audit entry carries
/// a `bodhHash` — a hash of (previousHash + payload + timestamp) that
/// can be anchored to a future blockchain layer for non-repudiation.
///
/// Fields per entry:
///   - `id`: auto-increment
///   - `event_type`: e.g. PATIENT_CREATE, SCREENING_CANCER, FL_ROUND
///   - `entity_id`: the ID of the affected record
///   - `actor`: user/device identifier
///   - `payload`: JSON snapshot of the change
///   - `prev_hash`: SHA-256 of the previous entry
///   - `bodh_hash`: SHA-256(prev_hash + payload + timestamp)
///   - `timestamp`: ISO-8601 UTC
class AuditService {
  AuditService._();
  static final AuditService instance = AuditService._();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  String _lastHash = '0' * 64; // genesis hash

  // ── Event Types ──────────────────────────────────────────────

  static const String patientCreate = 'PATIENT_CREATE';
  static const String patientUpdate = 'PATIENT_UPDATE';
  static const String patientDelete = 'PATIENT_DELETE';
  static const String screeningCancer = 'SCREENING_CANCER';
  static const String screeningTb = 'SCREENING_TB';
  static const String claimSubmit = 'CLAIM_SUBMIT';
  static const String syncPush = 'SYNC_PUSH';
  static const String syncPull = 'SYNC_PULL';
  static const String flRound = 'FL_ROUND';
  static const String flGlobalUpdate = 'FL_GLOBAL_UPDATE';
  static const String modelRegister = 'MODEL_REGISTER';
  static const String abhaLink = 'ABHA_LINK';
  static const String meshSend = 'MESH_SEND';
  static const String meshReceive = 'MESH_RECEIVE';
  static const String fraudAlert = 'FRAUD_ALERT';
  static const String keyExchange = 'KEY_EXCHANGE';
  static const String authLogin = 'AUTH_LOGIN';
  static const String authLogout = 'AUTH_LOGOUT';

  // ── Core API ─────────────────────────────────────────────────

  /// Log an auditable event. Returns the BODH hash of the new entry.
  Future<String> log({
    required String eventType,
    required String entityId,
    String actor = 'device_local',
    Map<String, dynamic> payload = const {},
  }) async {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final payloadJson = jsonEncode(payload);

    // Compute BODH hash: SHA-256(prevHash + payload + timestamp)
    final bodhInput = '$_lastHash$payloadJson$timestamp';
    final bodhHash = sha256.convert(utf8.encode(bodhInput)).toString();

    final db = await _dbHelper.database;
    await db.insert('audit_log', {
      'event_type': eventType,
      'entity_id': entityId,
      'actor': actor,
      'payload': payloadJson,
      'prev_hash': _lastHash,
      'bodh_hash': bodhHash,
      'timestamp': timestamp,
    });

    _lastHash = bodhHash;
    Log.d('Audit: $eventType → $entityId [${bodhHash.substring(0, 12)}…]',
        tag: 'SAHI');

    return bodhHash;
  }

  /// Retrieve the full audit trail, newest first.
  Future<List<Map<String, dynamic>>> getTrail({
    String? eventType,
    String? entityId,
    int? limit,
  }) async {
    final db = await _dbHelper.database;
    String? where;
    List<Object?>? whereArgs;

    if (eventType != null && entityId != null) {
      where = 'event_type = ? AND entity_id = ?';
      whereArgs = [eventType, entityId];
    } else if (eventType != null) {
      where = 'event_type = ?';
      whereArgs = [eventType];
    } else if (entityId != null) {
      where = 'entity_id = ?';
      whereArgs = [entityId];
    }

    return db.query(
      'audit_log',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  /// Verify chain integrity. Returns `true` if the chain is valid
  /// (each entry's bodh_hash matches recomputation from prev_hash).
  Future<bool> verifyChain() async {
    final db = await _dbHelper.database;
    final entries = await db.query('audit_log', orderBy: 'id ASC');

    String prevHash = '0' * 64;
    for (final entry in entries) {
      final expectedInput =
          '$prevHash${entry['payload']}${entry['timestamp']}';
      final expectedHash =
          sha256.convert(utf8.encode(expectedInput)).toString();

      if (entry['bodh_hash'] != expectedHash) {
        Log.e('Chain break at id=${entry['id']}', tag: 'SAHI');
        return false;
      }
      if (entry['prev_hash'] != prevHash) {
        Log.e('Prev-hash mismatch at id=${entry['id']}', tag: 'SAHI');
        return false;
      }
      prevHash = entry['bodh_hash'] as String;
    }

    Log.i('Chain verified: ${entries.length} entries, integrity OK',
        tag: 'SAHI');
    return true;
  }

  /// Get audit statistics for the dashboard.
  Future<Map<String, int>> getStats() async {
    final db = await _dbHelper.database;
    final all = await db.query('audit_log');

    final stats = <String, int>{};
    for (final entry in all) {
      final type = entry['event_type'] as String? ?? 'UNKNOWN';
      stats[type] = (stats[type] ?? 0) + 1;
    }
    stats['total'] = all.length;
    return stats;
  }

  /// Reload chain state from DB (e.g., after app restart).
  Future<void> restoreChainState() async {
    final db = await _dbHelper.database;
    final last = await db.query(
      'audit_log',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (last.isNotEmpty) {
      _lastHash = last.first['bodh_hash'] as String? ?? '0' * 64;
    }
  }
}
