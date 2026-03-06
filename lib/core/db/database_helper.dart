import 'app_database.dart';
import 'demo_data_seeder.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

/// Central database helper for SAHA.
///
/// Uses [AppDatabase] (in-memory) which works on **all platforms**
/// including Web/Chrome. For production Android builds, this can be
/// swapped to use sqflite/SQLCipher with:
///   import 'package:sqflite/sqflite.dart';
///   import 'package:path_provider/path_provider.dart';
///
/// Schema: 7 tables, 4 indexes.
class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  AppDatabase? _db;

  Future<AppDatabase> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<AppDatabase> _initDb() async {
    Log.i('Initializing in-memory database', tag: 'DB');
    final db = AppDatabase();
    await _onCreate(db);
    await DemoDataSeeder.seed(db);
    return db;
  }

  // ── Schema Creation ────────────────────────────────────────

  Future<void> _onCreate(AppDatabase db) async {
    Log.i('Creating database schema v${AppConstants.dbVersion}', tag: 'DB');

    await db.execute('''
      CREATE TABLE patients (
        id            TEXT PRIMARY KEY,
        full_name     TEXT NOT NULL,
        age           INTEGER NOT NULL,
        gender        TEXT NOT NULL,
        aadhaar_last4 TEXT,
        village       TEXT,
        district      TEXT,
        state         TEXT,
        phone         TEXT,
        photo_path    TEXT,
        created_at    TEXT NOT NULL,
        updated_at    TEXT NOT NULL,
        is_synced     INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE abha_links (
        id          TEXT PRIMARY KEY,
        patient_id  TEXT NOT NULL,
        abha_number TEXT NOT NULL,
        abha_address TEXT,
        linked_at   TEXT NOT NULL,
        verified    INTEGER NOT NULL DEFAULT 0,
        is_synced   INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (patient_id) REFERENCES patients (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE screenings (
        id              TEXT PRIMARY KEY,
        patient_id      TEXT NOT NULL,
        type            TEXT NOT NULL,
        result_label    TEXT NOT NULL,
        confidence      REAL NOT NULL,
        risk_level      TEXT NOT NULL,
        media_path      TEXT,
        notes           TEXT,
        performed_by    TEXT,
        performed_at    TEXT NOT NULL,
        is_synced       INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (patient_id) REFERENCES patients (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name    TEXT NOT NULL,
        row_id        TEXT NOT NULL,
        operation     TEXT NOT NULL,
        payload       TEXT NOT NULL,
        created_at    TEXT NOT NULL,
        retries       INTEGER NOT NULL DEFAULT 0,
        status        TEXT NOT NULL DEFAULT 'pending',
        synced_at     TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE model_registry (
        id              TEXT PRIMARY KEY,
        model_name      TEXT NOT NULL,
        version         INTEGER NOT NULL DEFAULT 1,
        file_path       TEXT NOT NULL,
        hash            TEXT NOT NULL,
        accuracy        REAL,
        updated_at      TEXT NOT NULL,
        source          TEXT NOT NULL DEFAULT 'bundled'
      )
    ''');

    await db.execute('''
      CREATE TABLE fl_deltas (
        id            TEXT PRIMARY KEY,
        model_name    TEXT NOT NULL,
        delta_payload TEXT NOT NULL,
        local_samples INTEGER NOT NULL DEFAULT 0,
        created_at    TEXT NOT NULL,
        is_synced     INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE claims (
        id              TEXT PRIMARY KEY,
        patient_id      TEXT NOT NULL,
        screening_id    TEXT NOT NULL,
        fhir_bundle     TEXT NOT NULL,
        claim_status    TEXT NOT NULL DEFAULT 'draft',
        amount          REAL,
        created_at      TEXT NOT NULL,
        submitted_at    TEXT,
        is_synced       INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (patient_id) REFERENCES patients (id),
        FOREIGN KEY (screening_id) REFERENCES screenings (id)
      )
    ''');

    // ── SAHI/BODH Audit Trail ──────────────────────────────
    await db.execute('''
      CREATE TABLE audit_log (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        event_type    TEXT NOT NULL,
        entity_id     TEXT NOT NULL,
        actor         TEXT NOT NULL DEFAULT 'device_local',
        payload       TEXT,
        prev_hash     TEXT NOT NULL,
        bodh_hash     TEXT NOT NULL,
        timestamp     TEXT NOT NULL
      )
    ''');

    // ── P2P Mesh Peers ─────────────────────────────────────
    await db.execute('''
      CREATE TABLE mesh_peers (
        id            TEXT PRIMARY KEY,
        device_name   TEXT NOT NULL,
        last_seen     TEXT NOT NULL,
        status        TEXT NOT NULL DEFAULT 'discovered',
        shared_items  INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── Fraud Alerts ───────────────────────────────────────
    await db.execute('''
      CREATE TABLE fraud_alerts (
        id              TEXT PRIMARY KEY,
        alert_type      TEXT NOT NULL,
        entity_id       TEXT NOT NULL,
        risk_score      REAL NOT NULL,
        details         TEXT,
        is_dismissed     INTEGER NOT NULL DEFAULT 0,
        created_at      TEXT NOT NULL
      )
    ''');

    // ── Indexes ──────────────────────────────────────────────
    await db.execute(
        'CREATE INDEX idx_patients_synced ON patients (is_synced)');
    await db.execute(
        'CREATE INDEX idx_screenings_patient ON screenings (patient_id)');
    await db.execute(
        'CREATE INDEX idx_sync_queue_status ON sync_queue (status)');
    await db.execute(
        'CREATE INDEX idx_abha_patient ON abha_links (patient_id)');
    await db.execute(
        'CREATE INDEX idx_audit_type ON audit_log (event_type)');
    await db.execute(
        'CREATE INDEX idx_audit_entity ON audit_log (entity_id)');
    await db.execute(
        'CREATE INDEX idx_fraud_entity ON fraud_alerts (entity_id)');

    Log.i('Database schema created successfully (10 tables, 7 indexes)',
        tag: 'DB');
  }

  // ── Helpers ────────────────────────────────────────────────

  /// Insert a row and enqueue a sync item in a single transaction.
  Future<void> insertWithSync(
    String table,
    Map<String, dynamic> values, {
    required String rowId,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        table,
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert('sync_queue', {
        'table_name': table,
        'row_id': rowId,
        'operation': 'INSERT',
        'payload': values.toString(),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'pending',
        'retries': 0,
      });
    });
    Log.d('Inserted into $table + sync queued ($rowId)', tag: 'DB');
  }

  /// Returns count of pending sync items.
  Future<int> pendingSyncCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM sync_queue WHERE status = 'pending'",
    );
    return result.first['cnt'] as int? ?? 0;
  }

  /// Close the database (used in tests / shutdown).
  Future<void> close() async {
    final db = await database;
    await db.close();
    _db = null;
  }
}
