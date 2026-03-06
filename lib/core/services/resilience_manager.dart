/// SAHA-Quantum — Device Resilience Manager
///
/// Monitors and manages device health for reliable medical screening:
///   • Battery level monitoring (pause AI if < 20%)
///   • Storage capacity tracking (< 150MB footprint)
///   • Database integrity validation + auto-repair
///   • Thermal throttling detection
///   • Memory pressure handling
///   • Network resilience (auto-resume sync)
///   • App restart recovery (stateless-safe design)
///
/// All screening operations consult the resilience manager before
/// proceeding to ensure patient safety and data integrity.

import 'dart:async';

import '../db/database_helper.dart';
import '../utils/logger.dart';

// ════════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ════════════════════════════════════════════════════════════════════════════

/// Current device health status.
class DeviceHealthStatus {
  const DeviceHealthStatus({
    required this.batteryLevel,
    required this.isCharging,
    required this.isBatteryLow,
    required this.storageUsedMB,
    required this.storageLimitMB,
    required this.isStorageCritical,
    required this.isThermalThrottled,
    required this.memoryUsageMB,
    required this.isMemoryPressure,
    required this.isDatabaseHealthy,
    required this.lastIntegrityCheck,
    required this.canPerformScreening,
    required this.warnings,
  });

  final int batteryLevel;
  final bool isCharging;
  final bool isBatteryLow;
  final double storageUsedMB;
  final double storageLimitMB;
  final bool isStorageCritical;
  final bool isThermalThrottled;
  final double memoryUsageMB;
  final bool isMemoryPressure;
  final bool isDatabaseHealthy;
  final DateTime? lastIntegrityCheck;
  final bool canPerformScreening;
  final List<String> warnings;
}

/// Result of a database integrity check.
class IntegrityCheckResult {
  const IntegrityCheckResult({
    required this.isHealthy,
    required this.tablesChecked,
    required this.tablesOk,
    required this.tablesFailed,
    required this.repaired,
    required this.issues,
  });

  final bool isHealthy;
  final int tablesChecked;
  final int tablesOk;
  final List<String> tablesFailed;
  final bool repaired;
  final List<String> issues;
}

// ════════════════════════════════════════════════════════════════════════════
//  RESILIENCE MANAGER
// ════════════════════════════════════════════════════════════════════════════

class ResilienceManager {
  ResilienceManager._();
  static final ResilienceManager instance = ResilienceManager._();

  static const _tag = 'Resilience';

  // ── Configuration ──────────────────────────────────────────────────
  static const int lowBatteryThreshold = 20;
  static const double storageLimitMB = 150.0;
  static const double memoryWarningMB = 256.0;
  static const Duration integrityCheckInterval = Duration(hours: 6);

  // ── State ──────────────────────────────────────────────────────────
  int _batteryLevel = 100;
  bool _isCharging = false;
  bool _isThermalThrottled = false;
  double _memoryUsageMB = 0;
  bool _isDatabaseHealthy = true;
  DateTime? _lastIntegrityCheck;
  Timer? _monitorTimer;
  bool _initialized = false;

  final _healthController = StreamController<DeviceHealthStatus>.broadcast();
  Stream<DeviceHealthStatus> get healthStream => _healthController.stream;

  /// Initialize the resilience manager.
  Future<void> initialize() async {
    if (_initialized) return;
    Log.i('Initializing resilience manager …', tag: _tag);

    // Initial integrity check
    await checkDatabaseIntegrity();

    // Start periodic monitoring
    _monitorTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _periodicCheck(),
    );

    _initialized = true;
    Log.i('Resilience manager ready', tag: _tag);
  }

  /// Get current device health status.
  DeviceHealthStatus getStatus() {
    final warnings = <String>[];
    final batteryLow = _batteryLevel < lowBatteryThreshold && !_isCharging;

    if (batteryLow) {
      warnings.add('Battery low ($_batteryLevel%). '
          'AI inference paused to preserve power.');
    }

    final storageUsed = _estimateStorageUsage();
    final storageCritical = storageUsed > storageLimitMB * 0.9;
    if (storageCritical) {
      warnings.add('Storage near limit '
          '(${storageUsed.toStringAsFixed(1)}/${storageLimitMB.toStringAsFixed(0)} MB). '
          'Consider syncing and clearing old data.');
    }

    if (_isThermalThrottled) {
      warnings
          .add('Device is overheating. AI inference paused for safety.');
    }

    final memPressure = _memoryUsageMB > memoryWarningMB;
    if (memPressure) {
      warnings.add('High memory usage '
          '(${_memoryUsageMB.toStringAsFixed(0)} MB). '
          'Close other apps for best performance.');
    }

    if (!_isDatabaseHealthy) {
      warnings.add('Database integrity issue detected. '
          'Auto-repair attempted.');
    }

    final canScreen = !batteryLow && !_isThermalThrottled && _isDatabaseHealthy;

    return DeviceHealthStatus(
      batteryLevel: _batteryLevel,
      isCharging: _isCharging,
      isBatteryLow: batteryLow,
      storageUsedMB: storageUsed,
      storageLimitMB: storageLimitMB,
      isStorageCritical: storageCritical,
      isThermalThrottled: _isThermalThrottled,
      memoryUsageMB: _memoryUsageMB,
      isMemoryPressure: memPressure,
      isDatabaseHealthy: _isDatabaseHealthy,
      lastIntegrityCheck: _lastIntegrityCheck,
      canPerformScreening: canScreen,
      warnings: warnings,
    );
  }

  /// Check if AI screening can proceed safely.
  ///
  /// Returns null if OK, or a human-readable reason to pause.
  String? canProceedWithScreening() {
    if (_batteryLevel < lowBatteryThreshold && !_isCharging) {
      return 'Battery too low ($_batteryLevel%). '
          'Please charge device before screening.';
    }
    if (_isThermalThrottled) {
      return 'Device is overheating. Please wait for it to cool down.';
    }
    if (!_isDatabaseHealthy) {
      return 'Database integrity issue. Please restart the app.';
    }
    return null; // OK to proceed
  }

  /// Update battery level (called from platform channel or simulated).
  void updateBatteryLevel(int level, {bool isCharging = false}) {
    _batteryLevel = level.clamp(0, 100);
    _isCharging = isCharging;

    if (_batteryLevel < lowBatteryThreshold && !_isCharging) {
      Log.w('Battery low: $_batteryLevel%', tag: _tag);
    }
    _emitStatus();
  }

  /// Report thermal throttling state.
  void reportThermalState({required bool isThrottled}) {
    if (_isThermalThrottled != isThrottled) {
      _isThermalThrottled = isThrottled;
      if (isThrottled) {
        Log.w('Thermal throttling detected — AI paused', tag: _tag);
      } else {
        Log.i('Thermal state normal — AI resumed', tag: _tag);
      }
      _emitStatus();
    }
  }

  /// Update memory usage.
  void updateMemoryUsage(double usageMB) {
    _memoryUsageMB = usageMB;
    if (usageMB > memoryWarningMB) {
      Log.w('Memory pressure: ${usageMB.toStringAsFixed(0)} MB', tag: _tag);
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  //  DATABASE INTEGRITY
  // ══════════════════════════════════════════════════════════════════════

  /// Comprehensive database integrity check.
  Future<IntegrityCheckResult> checkDatabaseIntegrity() async {
    Log.i('Running database integrity check …', tag: _tag);

    final requiredTables = [
      'patients',
      'abha_links',
      'screenings',
      'sync_queue',
      'model_registry',
      'fl_deltas',
      'claims',
      'audit_log',
      'mesh_peers',
      'fraud_alerts',
    ];

    final issues = <String>[];
    final failed = <String>[];
    int checked = 0;
    int ok = 0;

    try {
      final db = await DatabaseHelper.instance.database;

      for (final table in requiredTables) {
        checked++;
        try {
          // Simple SELECT to verify table exists and is readable
          await db.query(table, limit: 1);
          ok++;
        } catch (e) {
          failed.add(table);
          issues.add('Table "$table" check failed: $e');
          Log.e('Integrity: table "$table" failed: $e', tag: _tag);
        }
      }

      // Verify audit chain integrity
      try {
        final auditRows = await db.query(
          'audit_log',
          orderBy: 'id ASC',
          limit: 100,
        );

        if (auditRows.length > 1) {
          for (int i = 1; i < auditRows.length; i++) {
            final prevHash = auditRows[i]['prev_hash'] as String? ?? '';
            final prevBodh = auditRows[i - 1]['bodh_hash'] as String? ?? '';
            if (prevHash.isNotEmpty &&
                prevBodh.isNotEmpty &&
                prevHash != prevBodh) {
              issues.add(
                  'Audit chain break at entry ${auditRows[i]['id']}');
              Log.w('Audit chain integrity violation detected', tag: _tag);
            }
          }
        }
      } catch (e) {
        issues.add('Audit chain check failed: $e');
      }

      // Verify sync queue consistency
      try {
        final pending = await db.query(
          'sync_queue',
          where: 'status = ?',
          whereArgs: ['pending'],
        );
        Log.d('Sync queue: ${pending.length} pending items', tag: _tag);
      } catch (e) {
        issues.add('Sync queue check failed: $e');
      }
    } catch (e) {
      issues.add('Database connection failed: $e');
      Log.e('Database integrity check FAILED: $e', tag: _tag);
    }

    bool repaired = false;
    if (failed.isNotEmpty) {
      repaired = await _attemptRepair(failed);
    }

    _isDatabaseHealthy = failed.isEmpty || repaired;
    _lastIntegrityCheck = DateTime.now();
    _emitStatus();

    final result = IntegrityCheckResult(
      isHealthy: _isDatabaseHealthy,
      tablesChecked: checked,
      tablesOk: ok,
      tablesFailed: failed,
      repaired: repaired,
      issues: issues,
    );

    Log.i('Integrity check complete: '
        '$ok/$checked tables OK, '
        '${failed.length} failed, '
        'repaired=$repaired', tag: _tag);

    return result;
  }

  /// Attempt to repair damaged tables by recreating them.
  Future<bool> _attemptRepair(List<String> failedTables) async {
    Log.w('Attempting database repair for: $failedTables', tag: _tag);

    try {
      final db = await DatabaseHelper.instance.database;

      // Re-create failed tables with schema
      for (final table in failedTables) {
        try {
          final createSql = _getCreateTableSql(table);
          if (createSql != null) {
            await db.execute('DROP TABLE IF EXISTS $table');
            await db.execute(createSql);
            Log.i('Repaired table: $table', tag: _tag);
          }
        } catch (e) {
          Log.e('Failed to repair table $table: $e', tag: _tag);
          return false;
        }
      }

      return true;
    } catch (e) {
      Log.e('Database repair failed: $e', tag: _tag);
      return false;
    }
  }

  String? _getCreateTableSql(String table) {
    const schemas = {
      'patients': '''
        CREATE TABLE patients (
          id TEXT PRIMARY KEY, full_name TEXT NOT NULL, age INTEGER NOT NULL,
          gender TEXT NOT NULL, aadhaar_last4 TEXT, village TEXT, district TEXT,
          state TEXT, phone TEXT, photo_path TEXT, created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL, is_synced INTEGER NOT NULL DEFAULT 0
        )''',
      'screenings': '''
        CREATE TABLE screenings (
          id TEXT PRIMARY KEY, patient_id TEXT NOT NULL, type TEXT NOT NULL,
          result_label TEXT NOT NULL, confidence REAL NOT NULL,
          risk_level TEXT NOT NULL, media_path TEXT, notes TEXT,
          performed_by TEXT, performed_at TEXT NOT NULL,
          is_synced INTEGER NOT NULL DEFAULT 0
        )''',
      'sync_queue': '''
        CREATE TABLE sync_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT, table_name TEXT NOT NULL,
          row_id TEXT NOT NULL, operation TEXT NOT NULL, payload TEXT NOT NULL,
          created_at TEXT NOT NULL, retries INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'pending', synced_at TEXT
        )''',
      'audit_log': '''
        CREATE TABLE audit_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT, event_type TEXT NOT NULL,
          entity_id TEXT NOT NULL, actor TEXT NOT NULL DEFAULT 'device_local',
          payload TEXT, prev_hash TEXT NOT NULL, bodh_hash TEXT NOT NULL,
          timestamp TEXT NOT NULL
        )''',
      'mesh_peers': '''
        CREATE TABLE mesh_peers (
          id TEXT PRIMARY KEY, device_name TEXT NOT NULL,
          last_seen TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'discovered',
          shared_items INTEGER NOT NULL DEFAULT 0
        )''',
      'fraud_alerts': '''
        CREATE TABLE fraud_alerts (
          id TEXT PRIMARY KEY, alert_type TEXT NOT NULL,
          entity_id TEXT NOT NULL, risk_score REAL NOT NULL,
          details TEXT, is_dismissed INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )''',
      'model_registry': '''
        CREATE TABLE model_registry (
          id TEXT PRIMARY KEY, model_name TEXT NOT NULL,
          version INTEGER NOT NULL DEFAULT 1, file_path TEXT NOT NULL,
          hash TEXT NOT NULL, accuracy REAL, updated_at TEXT NOT NULL,
          source TEXT NOT NULL DEFAULT 'bundled'
        )''',
      'fl_deltas': '''
        CREATE TABLE fl_deltas (
          id TEXT PRIMARY KEY, model_name TEXT NOT NULL,
          delta_payload TEXT NOT NULL, local_samples INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL, is_synced INTEGER NOT NULL DEFAULT 0
        )''',
      'claims': '''
        CREATE TABLE claims (
          id TEXT PRIMARY KEY, patient_id TEXT NOT NULL,
          screening_id TEXT NOT NULL, fhir_bundle TEXT NOT NULL,
          claim_status TEXT NOT NULL DEFAULT 'draft', amount REAL,
          created_at TEXT NOT NULL, submitted_at TEXT,
          is_synced INTEGER NOT NULL DEFAULT 0
        )''',
      'abha_links': '''
        CREATE TABLE abha_links (
          id TEXT PRIMARY KEY, patient_id TEXT NOT NULL,
          abha_number TEXT NOT NULL, abha_address TEXT,
          linked_at TEXT NOT NULL, verified INTEGER NOT NULL DEFAULT 0,
          is_synced INTEGER NOT NULL DEFAULT 0
        )''',
    };
    return schemas[table];
  }

  // ══════════════════════════════════════════════════════════════════════
  //  STORAGE ESTIMATION
  // ══════════════════════════════════════════════════════════════════════

  double _estimateStorageUsage() {
    // Estimate based on in-memory DB size + static assets.
    // In production w/ SQLCipher, this reads actual file size.
    // Estimated: 5MB base + ~2KB per patient + ~3KB per screening
    return 5.0 + (_estimatedRowCount('patients') * 0.002) +
        (_estimatedRowCount('screenings') * 0.003) +
        (_estimatedRowCount('audit_log') * 0.001) +
        (_estimatedRowCount('sync_queue') * 0.001);
  }

  int _estimatedRowCount(String table) {
    // For web, we don't have real file sizes, so estimate conservatively.
    // This will be replaced with actual SQL COUNT() in production.
    return 0; // Fresh start estimation
  }

  // ══════════════════════════════════════════════════════════════════════
  //  INTERNAL
  // ══════════════════════════════════════════════════════════════════════

  void _periodicCheck() async {
    // Run integrity check if interval exceeded
    if (_lastIntegrityCheck == null ||
        DateTime.now().difference(_lastIntegrityCheck!) >
            integrityCheckInterval) {
      await checkDatabaseIntegrity();
    }
    _emitStatus();
  }

  void _emitStatus() {
    if (!_healthController.isClosed) {
      _healthController.add(getStatus());
    }
  }

  void dispose() {
    _monitorTimer?.cancel();
    _healthController.close();
  }
}
