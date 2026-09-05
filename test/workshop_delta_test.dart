import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/workshop_delta.dart';

void main() {
  test('diff emits only changed fields and tombstones', () {
    final changes = diffWorkshopStates(
      jsonEncode({
        'schemaVersion': 8,
        'inventory': [
          {'id': 'A', 'name': 'Bolt', 'quantity': 2, 'brand': 'Acme'},
          {'id': 'B', 'name': 'Nut', 'quantity': 4},
        ],
        'historyLimit': 100,
      }),
      jsonEncode({
        'schemaVersion': 8,
        'inventory': [
          {'id': 'A', 'name': 'Bolt', 'quantity': 3, 'brand': 'Acme'},
        ],
        'historyLimit': 100,
      }),
    );

    expect(changes, hasLength(2));
    expect(changes.first.entityType, 'inventory');
    expect(changes.first.entityId, 'A');
    expect(changes.first.fields, {'quantity': 3});
    expect(changes.last.entityId, 'B');
    expect(changes.last.deleted, isTrue);
  });

  test('changes update one record without replacing its neighbors', () {
    final result = jsonDecode(
      applyWorkshopEntityChanges(
        jsonEncode({
          'schemaVersion': 8,
          'inventory': [
            {'id': 'A', 'name': 'Bolt', 'quantity': 2},
            {'id': 'B', 'name': 'Nut', 'quantity': 4},
          ],
        }),
        const [
          WorkshopEntityChange(
            entityType: 'inventory',
            entityId: 'A',
            fields: {'quantity': 3},
          ),
        ],
      ),
    ) as Map<String, dynamic>;

    expect(result['inventory'], [
      {'id': 'A', 'name': 'Bolt', 'quantity': 3},
      {'id': 'B', 'name': 'Nut', 'quantity': 4},
    ]);
  });

  test('latest pending fields win over an incoming version of the item', () {
    final merged = mergeRemoteChangesWithPending(
      const [
        WorkshopEntityChange(
          entityType: 'inventory',
          entityId: 'FILAMENT-1',
          fields: {
            'name': 'PolyLite PLA',
            'filamentStatus': 'ready',
            'image': 'remote-product-image',
          },
          revision: 42,
        ),
      ],
      const [
        WorkshopEntityChange(
          entityType: 'inventory',
          entityId: 'FILAMENT-1',
          fields: {'filamentStatus': 'wet'},
        ),
      ],
    );

    expect(merged.changes.single.fields, {
      'name': 'PolyLite PLA',
      'filamentStatus': 'wet',
      'image': 'remote-product-image',
    });
    expect(merged.changes.single.revision, 42);
  });

  test(
    'a same-field concurrent edit is kept local but reported as a conflict',
    () {
      final merged = mergeRemoteChangesWithPending(
        const [
          WorkshopEntityChange(
            entityType: 'inventory',
            entityId: 'FILAMENT-1',
            fields: {'filamentStatus': 'ready'},
            revision: 42,
          ),
        ],
        const [
          WorkshopEntityChange(
            entityType: 'inventory',
            entityId: 'FILAMENT-1',
            fields: {'filamentStatus': 'wet'},
          ),
        ],
      );

      expect(merged.changes.single.fields, {'filamentStatus': 'wet'});
      expect(merged.conflicts, hasLength(1));
      final conflict = merged.conflicts.single;
      expect(conflict.entityType, 'inventory');
      expect(conflict.entityId, 'FILAMENT-1');
      expect(conflict.field, 'filamentStatus');
      expect(conflict.localValue, 'wet');
      expect(conflict.remoteValue, 'ready');
    },
  );

  test('disjoint-field edits from different devices produce no conflicts', () {
    final merged = mergeRemoteChangesWithPending(
      const [
        WorkshopEntityChange(
          entityType: 'inventory',
          entityId: 'FILAMENT-1',
          fields: {'filamentStatus': 'ready', 'storageLocationId': 'LOC-A'},
          revision: 42,
        ),
      ],
      const [
        WorkshopEntityChange(
          entityType: 'inventory',
          entityId: 'FILAMENT-1',
          fields: {'quantity': 3},
        ),
      ],
    );

    expect(merged.changes.single.fields, {
      'filamentStatus': 'ready',
      'storageLocationId': 'LOC-A',
      'quantity': 3,
    });
    expect(merged.conflicts, isEmpty);
  });
}
