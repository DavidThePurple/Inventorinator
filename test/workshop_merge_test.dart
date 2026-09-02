import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/workshop_merge.dart';

void main() {
  Map<String, dynamic> state() => {
    'schemaVersion': 3,
    'inventory': [
      {
        'id': 'INV-1',
        'name': 'PLA',
        'quantity': 1,
        'location': 'Shelf A',
        'filamentStatus': 'ready',
        'image': null,
      },
    ],
    'customItemTypes': [
      {
        'id': 'TYPE-1',
        'name': 'Soap',
        'contextualFields': ['Cure time'],
      },
    ],
    'kits': [
      {'id': 'KIT-1', 'name': 'Printer kit', 'bom': []},
    ],
    'builds': [
      {'id': 'BUILD-1', 'name': 'Printer build', 'lines': []},
    ],
    'auditLog': [
      {'id': 'AUD-1', 'action': 'create'},
    ],
    'futureSection': [
      {'id': 'FUTURE-1', 'value': 'preserve me'},
    ],
    'historyLimit': 100,
  };

  test('three-way sync preserves every known and future section', () {
    final base = state();
    final local = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
    final cloud = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
    (local['inventory'] as List).single['quantity'] = 2;
    (cloud['kits'] as List).single['name'] = 'Updated kit';

    final merged = jsonDecode(
      mergeWorkshopStates(
        jsonEncode(base),
        jsonEncode(local),
        jsonEncode(cloud),
      ),
    ) as Map<String, dynamic>;

    expect((merged['inventory'] as List).single['quantity'], 2);
    expect((merged['kits'] as List).single['name'], 'Updated kit');
    expect((merged['builds'] as List).single['id'], 'BUILD-1');
    expect((merged['auditLog'] as List).single['id'], 'AUD-1');
    expect((merged['customItemTypes'] as List).single['id'], 'TYPE-1');
    expect((merged['futureSection'] as List).single['value'], 'preserve me');
  });

  test(
    'different fields on the same item merge without losing either edit',
    () {
      final base = state();
      final local = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
      final cloud = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
      (local['inventory'] as List).single['quantity'] = 2;
      (cloud['inventory'] as List).single['location'] = 'Shelf B';

      final merged = jsonDecode(
        mergeWorkshopStates(
          jsonEncode(base),
          jsonEncode(local),
          jsonEncode(cloud),
        ),
      ) as Map<String, dynamic>;
      final item = (merged['inventory'] as List).single;

      expect(item['quantity'], 2);
      expect(item['location'], 'Shelf B');
    },
  );

  test('an in-flight image save cannot reset a newer filament status', () {
    final base = state();
    final local = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
    final cloud = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
    final localItem = (local['inventory'] as List).single;
    final cloudItem = (cloud['inventory'] as List).single;
    localItem['filamentStatus'] = 'queuedForDrying';
    localItem['image'] = null;
    cloudItem['filamentStatus'] = 'ready';
    cloudItem['image'] = 'base64-product-image';

    final merged = jsonDecode(
      mergeWorkshopStates(
        jsonEncode(base),
        jsonEncode(local),
        jsonEncode(cloud),
      ),
    ) as Map<String, dynamic>;
    final item = (merged['inventory'] as List).single;

    expect(item['filamentStatus'], 'queuedForDrying');
    expect(item['image'], 'base64-product-image');
  });

  test('same-field conflicts pause instead of silently choosing a device', () {
    final base = state();
    final local = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
    final cloud = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
    (local['inventory'] as List).single['quantity'] = 2;
    (cloud['inventory'] as List).single['quantity'] = 3;

    expect(
      () => mergeWorkshopStates(
        jsonEncode(base),
        jsonEncode(local),
        jsonEncode(cloud),
      ),
      throwsA(
        isA<WorkshopMergeConflict>().having(
          (error) => error.path,
          'path',
          contains('INV-1'),
        ),
      ),
    );
  });
}
