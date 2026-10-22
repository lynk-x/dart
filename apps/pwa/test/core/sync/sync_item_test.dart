import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:lynk_x/core/sync/sync_item.dart';

bool _isUuidV4(String s) {
  try {
    return UuidValue.fromString(s).isV4;
  } catch (_) {
    return false;
  }
}

void main() {
  group('SyncItem idempotency key', () {
    test('generates a UUID v4 when not supplied', () {
      final item = SyncItem(
        id: 'a',
        table: 't',
        action: SyncAction.insert,
        payload: const {},
      );
      expect(item.idempotencyKey, isNotEmpty);
      expect(_isUuidV4(item.idempotencyKey), isTrue);
    });

    test('uses the supplied key when given', () {
      const key = 'my-key';
      final item = SyncItem(
        id: 'a',
        table: 't',
        action: SyncAction.insert,
        payload: const {},
        idempotencyKey: key,
      );
      expect(item.idempotencyKey, key);
    });

    test('round-trips through toMap/fromMap', () {
      final item = SyncItem(
        id: 'a',
        table: 't',
        schema: 'api',
        action: SyncAction.update,
        payload: const {'id': 'x'},
        conflictPolicy: ConflictPolicy.serverWins,
        serverUpdatedAtBaseline: '2026-01-01T00:00:00Z',
        partitionKeyName: 'created_at',
        partitionKeyValue: '2026-01-01',
        idempotencyKey: 'k',
      );
      final restored = SyncItem.fromMap(item.toMap());
      expect(restored.idempotencyKey, item.idempotencyKey);
      expect(restored.id, item.id);
      expect(restored.table, item.table);
      expect(restored.schema, item.schema);
      expect(restored.action, item.action);
      expect(restored.payload, item.payload);
      expect(restored.conflictPolicy, item.conflictPolicy);
      expect(restored.serverUpdatedAtBaseline, item.serverUpdatedAtBaseline);
      expect(restored.partitionKeyName, item.partitionKeyName);
      expect(restored.partitionKeyValue, item.partitionKeyValue);
    });

    test('fromMap regenerates a key for items persisted before the field existed', () {
      final map = <String, dynamic>{
        'id': 'a',
        'table': 't',
        'schema': null,
        'action': 'insert',
        'payload': '{}',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'retryCount': 0,
        'conflictPolicy': 'serverWins',
        'serverUpdatedAtBaseline': null,
        'partitionKeyName': null,
        'partitionKeyValue': null,
      };
      final restored = SyncItem.fromMap(map);
      expect(restored.idempotencyKey, isNotEmpty);
      expect(_isUuidV4(restored.idempotencyKey), isTrue);
    });

    test('copyWith preserves the idempotency key', () {
      final item = SyncItem(
        id: 'a',
        table: 't',
        action: SyncAction.insert,
        payload: const {},
        idempotencyKey: 'k',
      );
      final bumped = item.copyWith(retryCount: 1);
      expect(bumped.idempotencyKey, 'k');
      expect(bumped.retryCount, 1);
    });
  });
}