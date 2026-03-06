// import 'package:sqflite/sqflite.dart';

import '../../../core/db/database_helper.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/utils/logger.dart';
import '../models/patient.dart';

/// Repository for [Patient] CRUD operations against the local DB.
///
/// Every mutation also enqueues a [SyncItem] so the offline-first
/// sync engine can push changes when connectivity returns.
class PatientRepository {
  PatientRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;
  static const _tag = 'PatientRepo';
  static const _table = 'patients';

  // ── Create ─────────────────────────────────────────────────

  Future<Patient> createPatient(Patient patient) async {
    await _dbHelper.insertWithSync(
      _table,
      patient.toMap(),
      rowId: patient.id,
    );
    Log.i('Created patient ${patient.id}', tag: _tag);
    await AuditService.instance.log(
      eventType: AuditService.patientCreate,
      entityId: patient.id,
      payload: {'name': patient.fullName, 'village': patient.village},
    );
    return patient;
  }

  // ── Read ───────────────────────────────────────────────────

  Future<List<Patient>> getAllPatients() async {
    final db = await _dbHelper.database;
    final rows = await db.query(_table, orderBy: 'created_at DESC');
    return rows.map(Patient.fromMap).toList();
  }

  Future<Patient?> getPatientById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(_table, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Patient.fromMap(rows.first);
  }

  Future<List<Patient>> searchPatients(String query) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      _table,
      where: 'full_name LIKE ? OR village LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'created_at DESC',
    );
    return rows.map(Patient.fromMap).toList();
  }

  Future<int> getTotalCount() async {
    final db = await _dbHelper.database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM $_table');
    return result.first['cnt'] as int? ?? 0;
  }

  Future<int> getUnsyncedCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM $_table WHERE is_synced = 0',
    );
    return result.first['cnt'] as int? ?? 0;
  }

  Future<int> getScreeningsCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM screenings',
    );
    return result.first['cnt'] as int? ?? 0;
  }

  Future<List<Map<String, dynamic>>> getScreeningsForPatient(
      String patientId) async {
    final db = await _dbHelper.database;
    return db.query(
      'screenings',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'performed_at DESC',
    );
  }

  // ── Update ─────────────────────────────────────────────────

  Future<void> updatePatient(Patient patient) async {
    final db = await _dbHelper.database;
    final updated = patient.copyWith(updatedAt: DateTime.now());

    await db.transaction((txn) async {
      await txn.update(
        _table,
        {...updated.toMap(), 'is_synced': 0},
        where: 'id = ?',
        whereArgs: [patient.id],
      );
      await txn.insert('sync_queue', {
        'table_name': _table,
        'row_id': patient.id,
        'operation': 'UPDATE',
        'payload': updated.toMap().toString(),
        'created_at': DateTime.now().toIso8601String(),
        'status': 'pending',
      });
    });

    Log.i('Updated patient ${patient.id}', tag: _tag);
    await AuditService.instance.log(
      eventType: AuditService.patientUpdate,
      entityId: patient.id,
      payload: {'name': updated.fullName},
    );
  }

  // ── Delete ─────────────────────────────────────────────────

  Future<void> deletePatient(String id) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
      await txn.insert('sync_queue', {
        'table_name': _table,
        'row_id': id,
        'operation': 'DELETE',
        'payload': '{}',
        'created_at': DateTime.now().toIso8601String(),
        'status': 'pending',
      });
    });
    Log.i('Deleted patient $id', tag: _tag);
    await AuditService.instance.log(
      eventType: AuditService.patientDelete,
      entityId: id,
    );
  }
}
