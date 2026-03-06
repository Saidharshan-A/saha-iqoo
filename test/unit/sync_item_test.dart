import 'package:flutter_test/flutter_test.dart';

import 'package:saha/shared/models/sync_item.dart';

void main() {
  group('SyncItem', () {
    test('fromMap / toMap round-trip', () {
      final now = DateTime.now();
      final item = SyncItem(
        id: 1,
        tableName: 'patients',
        rowId: 'p-001',
        operation: 'INSERT',
        payload: '{"name":"test"}',
        createdAt: now,
      );

      final map = item.toMap();
      final restored = SyncItem.fromMap(map);

      expect(restored.tableName, 'patients');
      expect(restored.rowId, 'p-001');
      expect(restored.operation, 'INSERT');
      expect(restored.status, 'pending');
    });
  });
}
