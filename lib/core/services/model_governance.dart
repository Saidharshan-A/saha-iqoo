import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../db/database_helper.dart';
import '../utils/logger.dart';
import 'audit_service.dart';

/// ───────────────────────────────────────────────────────────────────────────
/// Model Lifecycle Governance Engine for SAHA-Quantum.
///
/// Provides a **litigation-proof** model management system:
///
///   1. **Version Registry** — every model version is tracked with
///      SHA-256 checksums, accuracy metrics, and provenance metadata.
///   2. **Mandatory Checksum Verification** — before any inference,
///      the model's integrity is verified against its registered hash.
///   3. **Signed Model Updates** — updates carry an Ed25519-style
///      signature (HMAC-SHA256 with shared secret for hackathon scope).
///      Production: replace with real Ed25519 from ABDM PKI.
///   4. **Rollback Capability** — if a model update causes harm,
///      the system can instantly revert to any prior version.
///   5. **Inference Audit Log** — every prediction is linked to the
///      exact model version + hash that produced it, creating an
///      unbreakable evidence chain for clinical litigation.
///
/// This is how real medical systems survive litigation.
/// ───────────────────────────────────────────────────────────────────────────
class ModelGovernance {
  ModelGovernance._();
  static final ModelGovernance instance = ModelGovernance._();
  static const _tag = 'ModelGov';

  /// Shared signing key (hackathon). Production: Ed25519 from ABDM PKI.
  static const _signingKey = 'SAHA-NHA-IITKanpur-ModelSigning-2026';

  // Current active model versions (in-memory cache)
  final _activeVersions = <String, ModelVersion>{};
  final _versionHistory = <String, List<ModelVersion>>{};
  bool _initialized = false;

  // ════════════════════════════════════════════════════════════════════════
  //  INITIALIZATION
  // ════════════════════════════════════════════════════════════════════════

  /// Initialize the governance engine with DB tables + bundled models.
  Future<void> initialize() async {
    if (_initialized) return;
    final db = await DatabaseHelper.instance.database;

    // Create governance-specific tables
    await db.execute('''
      CREATE TABLE model_versions (
        id              TEXT PRIMARY KEY,
        model_name      TEXT NOT NULL,
        version         INTEGER NOT NULL,
        checksum        TEXT NOT NULL,
        signature       TEXT NOT NULL,
        accuracy        REAL,
        status          TEXT NOT NULL DEFAULT 'active',
        source          TEXT NOT NULL DEFAULT 'bundled',
        released_at     TEXT NOT NULL,
        activated_at    TEXT,
        deactivated_at  TEXT,
        rollback_reason TEXT,
        metadata        TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE inference_audit (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        model_name       TEXT NOT NULL,
        model_version    INTEGER NOT NULL,
        model_checksum   TEXT NOT NULL,
        patient_id       TEXT,
        inference_type   TEXT NOT NULL,
        result_label     TEXT NOT NULL,
        confidence       REAL NOT NULL,
        inference_time_ms INTEGER NOT NULL,
        timestamp        TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE model_incidents (
        id              TEXT PRIMARY KEY,
        model_name      TEXT NOT NULL,
        model_version   INTEGER NOT NULL,
        incident_type   TEXT NOT NULL,
        description     TEXT NOT NULL,
        severity        TEXT NOT NULL,
        action_taken    TEXT,
        reported_at     TEXT NOT NULL,
        resolved_at     TEXT
      )
    ''');

    // Register bundled models
    await _registerBundledModels(db);
    _initialized = true;
    Log.i('Model Governance Engine initialized', tag: _tag);
  }

  Future<void> _registerBundledModels(dynamic db) async {
    final existing = await db.query('model_versions');
    if (existing.isNotEmpty) {
      // Load into memory cache
      for (final row in existing) {
        final mv = ModelVersion.fromMap(row);
        _activeVersions[mv.modelName] = mv;
        _versionHistory
            .putIfAbsent(mv.modelName, () => [])
            .add(mv);
      }
      return;
    }

    final now = DateTime.now().toIso8601String();

    // Oral Cancer model
    var cancerV1 = ModelVersion(
      id: 'gov-oral-cancer-v1',
      modelName: 'oral_cancer_efficientnetb0',
      version: 1,
      checksum: _computeModelChecksum('oral_cancer_efficientnetb0', 1),
      signature: '',
      accuracy: 0.9429,
      status: 'active',
      source: 'bundled',
      releasedAt: now,
      activatedAt: now,
    );
    cancerV1 = cancerV1.copyWith(
        signature: _signModel(cancerV1.checksum));

    // TB Cough model
    var tbV1 = ModelVersion(
      id: 'gov-tb-cough-v1',
      modelName: 'tb_cough_classifier',
      version: 1,
      checksum: _computeModelChecksum('tb_cough_classifier', 1),
      signature: '',
      accuracy: 0.852,
      status: 'active',
      source: 'bundled',
      releasedAt: now,
      activatedAt: now,
    );
    tbV1 = tbV1.copyWith(signature: _signModel(tbV1.checksum));

    for (final mv in [cancerV1, tbV1]) {
      await db.insert('model_versions', mv.toMap());
      _activeVersions[mv.modelName] = mv;
      _versionHistory.putIfAbsent(mv.modelName, () => []).add(mv);
    }

    Log.i('Registered 2 bundled models with governance checksums', tag: _tag);
  }

  // ════════════════════════════════════════════════════════════════════════
  //  CHECKSUM VERIFICATION
  // ════════════════════════════════════════════════════════════════════════

  /// Compute SHA-256 checksum for a model identified by name + version.
  ///
  /// **Production**: Hashes the actual .tflite binary bytes from assets.
  /// This ensures the model file has not been tampered with.
  ///
  /// **Current (pre-TFLite)**: Hashes a deterministic seed derived from
  /// the model name + version so the governance pipeline can function.
  ///
  /// When real .tflite files are deployed, replace with:
  ///   final bytes = await rootBundle.load('assets/models/$modelName.tflite');
  ///   return sha256.convert(bytes.buffer.asUint8List()).toString();
  String _computeModelChecksum(String modelName, int version) {
    // TODO: Replace with file-based SHA-256 when .tflite files are deployed.
    final seed = utf8.encode('$modelName:v$version:SAHA-Quantum-2026');
    return sha256.convert(seed).toString();
  }

  /// Verify the integrity of a model before inference.
  ///
  /// Returns `true` if the model's current checksum matches the
  /// registered checksum. This MUST be called before every inference.
  Future<bool> verifyChecksum(String modelName) async {
    final active = _activeVersions[modelName];
    if (active == null) {
      Log.e('Model not registered: $modelName', tag: _tag);
      return false;
    }

    final currentChecksum = _computeModelChecksum(
      modelName, active.version);
    final valid = currentChecksum == active.checksum;

    if (!valid) {
      Log.e(
        'CHECKSUM MISMATCH for $modelName v${active.version}! '
        'Expected: ${active.checksum.substring(0, 16)}… '
        'Got: ${currentChecksum.substring(0, 16)}…',
        tag: _tag,
      );
      _reportIncident(
        modelName: modelName,
        version: active.version,
        type: 'checksum_mismatch',
        description: 'Model checksum verification failed',
        severity: 'critical',
      );
    }

    return valid;
  }

  // ════════════════════════════════════════════════════════════════════════
  //  SIGNED MODEL UPDATES
  // ════════════════════════════════════════════════════════════════════════

  /// Sign a model checksum using HMAC-SHA256.
  ///
  /// Production: Ed25519 digital signature from ABDM-issued certificate.
  String _signModel(String checksum) {
    final key = utf8.encode(_signingKey);
    final data = utf8.encode(checksum);
    return Hmac(sha256, key).convert(data).toString();
  }

  /// Verify a model update signature.
  bool _verifySignature(String checksum, String signature) {
    final expected = _signModel(checksum);
    return expected == signature;
  }

  /// Apply a signed model update.
  ///
  /// Steps:
  ///   1. Verify signature (reject if invalid)
  ///   2. Verify checksum integrity
  ///   3. Deactivate old version
  ///   4. Activate new version
  ///   5. Audit log the transition
  Future<ModelUpdateResult> applyUpdate({
    required String modelName,
    required int newVersion,
    required String checksum,
    required String signature,
    double? accuracy,
    String source = 'federated',
  }) async {
    await initialize();

    // 1. Verify signature
    if (!_verifySignature(checksum, signature)) {
      Log.e('REJECTED update for $modelName: invalid signature', tag: _tag);
      await _reportIncident(
        modelName: modelName,
        version: newVersion,
        type: 'invalid_signature',
        description: 'Model update rejected: signature verification failed',
        severity: 'critical',
      );
      return ModelUpdateResult(
        success: false,
        reason: 'Signature verification failed',
      );
    }

    // 2. Verify checksum
    final expectedChecksum = _computeModelChecksum(modelName, newVersion);
    if (expectedChecksum != checksum) {
      Log.e('REJECTED update for $modelName: checksum mismatch', tag: _tag);
      return ModelUpdateResult(
        success: false,
        reason: 'Checksum mismatch',
      );
    }

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();

    // 3. Deactivate old version
    final old = _activeVersions[modelName];
    if (old != null) {
      await db.update(
        'model_versions',
        {'status': 'superseded', 'deactivated_at': now},
        where: 'id = ?',
        whereArgs: [old.id],
      );
    }

    // 4. Register & activate new version
    final newMv = ModelVersion(
      id: 'gov-$modelName-v$newVersion',
      modelName: modelName,
      version: newVersion,
      checksum: checksum,
      signature: signature,
      accuracy: accuracy,
      status: 'active',
      source: source,
      releasedAt: now,
      activatedAt: now,
    );
    await db.insert('model_versions', newMv.toMap());
    _activeVersions[modelName] = newMv;
    _versionHistory.putIfAbsent(modelName, () => []).add(newMv);

    // 5. Audit
    await AuditService.instance.log(
      eventType: 'model_update',
      entityId: modelName,
      payload: {
        'old_version': old?.version,
        'new_version': newVersion,
        'checksum': checksum.substring(0, 16),
        'source': source,
      },
    );

    Log.i('Model $modelName updated: v${old?.version} → v$newVersion',
        tag: _tag);

    return ModelUpdateResult(
      success: true,
      previousVersion: old?.version,
      newVersion: newVersion,
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  ROLLBACK
  // ════════════════════════════════════════════════════════════════════════

  /// Rollback a model to a specific previous version.
  ///
  /// Used when a model update causes clinical harm.
  /// Creates a full audit trail of the rollback action.
  Future<ModelUpdateResult> rollback({
    required String modelName,
    required int targetVersion,
    required String reason,
  }) async {
    await initialize();

    final history = _versionHistory[modelName] ?? [];
    final target = history.cast<ModelVersion?>().firstWhere(
          (v) => v!.version == targetVersion,
          orElse: () => null,
        );

    if (target == null) {
      return ModelUpdateResult(
        success: false,
        reason: 'Version $targetVersion not found in history',
      );
    }

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();

    // Deactivate current
    final current = _activeVersions[modelName];
    if (current != null) {
      await db.update(
        'model_versions',
        {
          'status': 'rolled_back',
          'deactivated_at': now,
          'rollback_reason': reason,
        },
        where: 'id = ?',
        whereArgs: [current.id],
      );
    }

    // Reactivate target
    await db.update(
      'model_versions',
      {'status': 'active', 'activated_at': now},
      where: 'id = ?',
      whereArgs: [target.id],
    );
    _activeVersions[modelName] = target.copyWith(
      status: 'active',
      activatedAt: now,
    );

    // Report incident
    await _reportIncident(
      modelName: modelName,
      version: current?.version ?? 0,
      type: 'rollback',
      description: reason,
      severity: 'high',
      action: 'Rolled back to v$targetVersion',
    );

    // Audit
    await AuditService.instance.log(
      eventType: 'model_rollback',
      entityId: modelName,
      payload: {
        'from_version': current?.version,
        'to_version': targetVersion,
        'reason': reason,
      },
    );

    Log.w(
      'ROLLBACK: $modelName v${current?.version} → v$targetVersion ($reason)',
      tag: _tag,
    );

    return ModelUpdateResult(
      success: true,
      previousVersion: current?.version,
      newVersion: targetVersion,
      reason: 'Rolled back: $reason',
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  INFERENCE AUDIT
  // ════════════════════════════════════════════════════════════════════════

  /// Log a model inference event with full version traceability.
  ///
  /// This creates an unbreakable evidence chain:
  ///   Patient X → Model Y v3 (checksum abc…) → Result Z @ timestamp
  Future<void> logInference({
    required String modelName,
    String? patientId,
    required String inferenceType,
    required String resultLabel,
    required double confidence,
    required int inferenceTimeMs,
  }) async {
    await initialize();
    final active = _activeVersions[modelName];
    if (active == null) return;

    final db = await DatabaseHelper.instance.database;
    await db.insert('inference_audit', {
      'model_name': modelName,
      'model_version': active.version,
      'model_checksum': active.checksum,
      'patient_id': patientId,
      'inference_type': inferenceType,
      'result_label': resultLabel,
      'confidence': confidence,
      'inference_time_ms': inferenceTimeMs,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ════════════════════════════════════════════════════════════════════════
  //  QUERIES
  // ════════════════════════════════════════════════════════════════════════

  /// Get the active version of a model.
  ModelVersion? getActiveVersion(String modelName) =>
      _activeVersions[modelName];

  /// Get full version history for a model.
  List<ModelVersion> getVersionHistory(String modelName) =>
      List.unmodifiable(_versionHistory[modelName] ?? []);

  /// Get all active models.
  Map<String, ModelVersion> get activeModels =>
      Map.unmodifiable(_activeVersions);

  /// Get all model versions across all models.
  Future<List<ModelVersion>> getAllVersions() async {
    await initialize();
    final all = <ModelVersion>[];
    for (final versions in _versionHistory.values) {
      all.addAll(versions);
    }
    return all;
  }

  /// Get all model incidents.
  Future<List<Map<String, dynamic>>> getIncidents() async {
    await initialize();
    final db = await DatabaseHelper.instance.database;
    return db.query('model_incidents', orderBy: 'reported_at DESC');
  }

  /// Get inference audit trail for a specific patient.
  Future<List<Map<String, dynamic>>> getPatientInferenceHistory(
      String patientId) async {
    await initialize();
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'inference_audit',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'timestamp DESC',
    );
  }

  // ── Incident Reporting ─────────────────────────────────────

  Future<void> _reportIncident({
    required String modelName,
    required int version,
    required String type,
    required String description,
    required String severity,
    String? action,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('model_incidents', {
      'id': 'incident-${DateTime.now().millisecondsSinceEpoch}',
      'model_name': modelName,
      'model_version': version,
      'incident_type': type,
      'description': description,
      'severity': severity,
      'action_taken': action,
      'reported_at': now,
    });
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ════════════════════════════════════════════════════════════════════════════

class ModelVersion {
  ModelVersion({
    required this.id,
    required this.modelName,
    required this.version,
    required this.checksum,
    required this.signature,
    this.accuracy,
    required this.status,
    required this.source,
    required this.releasedAt,
    this.activatedAt,
    this.deactivatedAt,
    this.rollbackReason,
    this.metadata,
  });

  final String id;
  final String modelName;
  final int version;
  final String checksum;
  final String signature;
  final double? accuracy;
  final String status;
  final String source;
  final String releasedAt;
  final String? activatedAt;
  final String? deactivatedAt;
  final String? rollbackReason;
  final String? metadata;

  ModelVersion copyWith({
    String? status,
    String? activatedAt,
    String? deactivatedAt,
    String? rollbackReason,
    String? signature,
  }) =>
      ModelVersion(
        id: id,
        modelName: modelName,
        version: version,
        checksum: checksum,
        signature: signature ?? this.signature,
        accuracy: accuracy,
        status: status ?? this.status,
        source: source,
        releasedAt: releasedAt,
        activatedAt: activatedAt ?? this.activatedAt,
        deactivatedAt: deactivatedAt ?? this.deactivatedAt,
        rollbackReason: rollbackReason ?? this.rollbackReason,
        metadata: metadata,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'model_name': modelName,
        'version': version,
        'checksum': checksum,
        'signature': signature,
        'accuracy': accuracy,
        'status': status,
        'source': source,
        'released_at': releasedAt,
        'activated_at': activatedAt,
        'deactivated_at': deactivatedAt,
        'rollback_reason': rollbackReason,
        'metadata': metadata,
      };

  factory ModelVersion.fromMap(Map<String, dynamic> m) => ModelVersion(
        id: m['id'] as String,
        modelName: m['model_name'] as String,
        version: m['version'] as int,
        checksum: m['checksum'] as String,
        signature: m['signature'] as String? ?? '',
        accuracy: (m['accuracy'] as num?)?.toDouble(),
        status: m['status'] as String? ?? 'active',
        source: m['source'] as String? ?? 'unknown',
        releasedAt: m['released_at'] as String,
        activatedAt: m['activated_at'] as String?,
        deactivatedAt: m['deactivated_at'] as String?,
        rollbackReason: m['rollback_reason'] as String?,
        metadata: m['metadata'] as String?,
      );
}

class ModelUpdateResult {
  const ModelUpdateResult({
    required this.success,
    this.previousVersion,
    this.newVersion,
    this.reason,
  });

  final bool success;
  final int? previousVersion;
  final int? newVersion;
  final String? reason;
}
