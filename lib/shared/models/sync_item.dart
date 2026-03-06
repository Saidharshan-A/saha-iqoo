import 'package:equatable/equatable.dart';

/// Represents a single item in the offline sync queue.
class SyncItem extends Equatable {
  const SyncItem({
    this.id,
    required this.tableName,
    required this.rowId,
    required this.operation,
    required this.payload,
    required this.createdAt,
    this.retries = 0,
    this.status = 'pending',
    this.syncedAt,
  });

  final int? id;
  final String tableName;
  final String rowId;
  final String operation;
  final String payload;
  final DateTime createdAt;
  final int retries;
  final String status;
  final DateTime? syncedAt;

  factory SyncItem.fromMap(Map<String, dynamic> map) => SyncItem(
        id: map['id'] as int?,
        tableName: map['table_name'] as String,
        rowId: map['row_id'] as String,
        operation: map['operation'] as String,
        payload: map['payload'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        retries: map['retries'] as int? ?? 0,
        status: map['status'] as String? ?? 'pending',
        syncedAt: map['synced_at'] != null
            ? DateTime.parse(map['synced_at'] as String)
            : null,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'table_name': tableName,
        'row_id': rowId,
        'operation': operation,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
        'retries': retries,
        'status': status,
        'synced_at': syncedAt?.toIso8601String(),
      };

  @override
  List<Object?> get props =>
      [id, tableName, rowId, operation, createdAt, status];
}
