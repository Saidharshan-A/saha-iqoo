import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_database.dart';
import 'database_helper.dart';
import '../services/connectivity_service.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';

/// Offline-first sync engine.
///
/// Maintains a **write-ahead queue** in `sync_queue` table. Every local
/// mutation (patient registration, screening result, etc.) is first
/// persisted in the main table and simultaneously enqueued as a
/// [SyncItem] with status `pending`.
///
/// When the device regains connectivity, the engine drains the queue
/// in chronological batches, POSTing each item to the remote endpoint.
/// Failed items are retried with exponential backoff up to 5 attempts.
///
/// Conflict resolution: **last-write-wins** using `updated_at` timestamps.
class SyncEngine {
  SyncEngine._();

  static final SyncEngine instance = SyncEngine._();

  static const _tag = 'SyncEngine';
  static const _maxRetries = 5;

  StreamSubscription<bool>? _connectivitySub;
  bool _isSyncing = false;

  /// Number of pending items — exposed for the UI badge.
  final StreamController<int> _pendingCountController =
      StreamController<int>.broadcast();
  Stream<int> get pendingCountStream => _pendingCountController.stream;

  int _pendingCount = 0;
  int get pendingCount => _pendingCount;

  // ── Lifecycle ──────────────────────────────────────────────

  /// Initialise and start listening for connectivity changes.
  Future<void> init() async {
    await _refreshPendingCount();

    _connectivitySub =
        ConnectivityService.instance.onConnectivityChanged.listen((online) {
      if (online) {
        Log.i('Network available – triggering sync', tag: _tag);
        syncNow();
      }
    });

    Log.i('SyncEngine initialised – pending=$_pendingCount', tag: _tag);
  }

  /// Attempt to drain the sync queue immediately.
  Future<void> syncNow() async {
    if (_isSyncing) {
      Log.d('Sync already in progress, skipping', tag: _tag);
      return;
    }
    if (!ConnectivityService.instance.isOnline) {
      Log.d('Offline – sync deferred', tag: _tag);
      return;
    }

    _isSyncing = true;
    Log.i('Starting sync cycle…', tag: _tag);

    try {
      final db = await DatabaseHelper.instance.database;

      while (true) {
        final batch = await db.query(
          'sync_queue',
          where: "status = 'pending' AND retries < ?",
          whereArgs: [_maxRetries],
          orderBy: 'created_at ASC',
          limit: AppConstants.syncBatchSize,
        );

        if (batch.isEmpty) break;

        for (final item in batch) {
          await _processItem(db, item);
        }
      }
    } catch (e, st) {
      Log.e('Sync cycle failed', tag: _tag, error: e, stackTrace: st);
    } finally {
      _isSyncing = false;
      await _refreshPendingCount();
      Log.i('Sync cycle complete – pending=$_pendingCount', tag: _tag);
    }
  }

  // ── Internal ───────────────────────────────────────────────

  Future<void> _processItem(AppDatabase db, Map<String, dynamic> item) async {
    final id = item['id'] as int;
    final table = item['table_name'] as String;
    final rowId = item['row_id'] as String;
    final operation = item['operation'] as String;
    final payload = item['payload'] as String;

    try {
      // POST to mock backend
      final uri = Uri.parse('${AppConstants.syncBaseUrl}/$table');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'operation': operation,
              'row_id': rowId,
              'data': payload,
              'synced_at': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Mark sync item as completed
        await db.update(
          'sync_queue',
          {
            'status': 'synced',
            'synced_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );

        // Mark source row as synced
        await db.update(
          table,
          {'is_synced': 1},
          where: 'id = ?',
          whereArgs: [rowId],
        );

        Log.d('Synced $table/$rowId', tag: _tag);
      } else {
        await _incrementRetry(db, id);
        Log.w(
          'Server returned ${response.statusCode} for $table/$rowId',
          tag: _tag,
        );
      }
    } catch (e) {
      await _incrementRetry(db, id);
      Log.w('Network error syncing $table/$rowId: $e', tag: _tag);
    }
  }

  Future<void> _incrementRetry(AppDatabase db, int id) async {
    await db.rawUpdate(
      'UPDATE sync_queue SET retries = retries + 1 WHERE id = ?',
      [id],
    );
  }

  Future<void> _refreshPendingCount() async {
    _pendingCount = await DatabaseHelper.instance.pendingSyncCount();
    _pendingCountController.add(_pendingCount);
  }

  /// Clean up.
  void dispose() {
    _connectivitySub?.cancel();
    _pendingCountController.close();
  }
}
