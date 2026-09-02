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

    expect(merged.single.fields, {
      'name': 'PolyLite PLA',
      'filamentStatus': 'wet',
      'image': 'remote-product-image',
    });
    expect(merged.single.revision, 42);
  });
}
