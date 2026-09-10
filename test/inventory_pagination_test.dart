import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/main.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/disk_inventory_list.dart';

String fixture(int count) => jsonEncode({
  'schemaVersion': 8,
  'inventory': [
    for (var i = 0; i < count; i++)
      {
        'id': 'ITEM-${i.toString().padLeft(4, '0')}',
        'name': 'Bolt $i',
        'type': 'other',
        'compatibility': <String>[],
        'added': '2026-01-01T00:00:00.000',
        'cost': i.toDouble(),
        'quantity': i,
        'color': 0xff888888,
        'archived': false,
        'thumbnail': base64Encode(List.filled(1024, 1)),
      },
  ],
  'kits': [],
  'builds': [],
  'machines': [],
  'products': [],
});

void main() {
  test(
    'SQL pages are bounded, counts independent and offline payloads preserved',
    () async {
      final dir = Directory.systemTemp.createTempSync('paging-db-');
      var db = await LocalDatabase.open(
        overridePath: '${dir.path}/test.sqlite3',
      );
      db.saveState(fixture(1000));
      final metadata = jsonDecode(
        db.loadState(includeFullImages: false, includeInventory: false)!,
      );
      expect(metadata['inventory'], isEmpty);
      expect(db.inventoryCount(), 1000);
      expect(db.inventoryMetricGroups({'item:other'}), isEmpty);
      const where = "json_extract(payload_json, '\$.quantity') >= ?";
      expect(db.inventoryCount(where: where, parameters: [900]), 100);
      final page = db.inventoryPage(
        where: where,
        parameters: [900],
        orderBy: "json_extract(payload_json, '\$.quantity') ASC, entity_id ASC",
        limit: 12,
        offset: 12,
      );
      expect(page, hasLength(12));
      expect(page.first['quantity'], 912);
      expect(page.last['quantity'], 923);
      expect(page.first['thumbnail'], isNotNull);
      expect(db.inventoryPayload('ITEM-0001')!.containsKey('thumbnail'), false);
      db.close();
      db = await LocalDatabase.open(overridePath: '${dir.path}/test.sqlite3');
      expect(db.inventoryCount(), 1000);
      expect(
        db.inventoryPayload('ITEM-0999', thumbnail: true)!['thumbnail'],
        isNotNull,
      );
      db.close();
      dir.deleteSync(recursive: true);
    },
  );

  testWidgets(
    'home retains only a page and filters/sorts the complete database',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('paging-home-');
      final db = (await tester.runAsync(
        () => LocalDatabase.open(overridePath: '${dir.path}/test.sqlite3'),
      ))!;
      // No image decoder work is needed for this object-retention test.
      final state = jsonDecode(fixture(300)) as Map<String, dynamic>;
      for (final row in state['inventory'] as List) {
        row.remove('thumbnail');
      }
      db.saveState(jsonEncode(state));
      db.saveSyncConfig(jsonEncode({'syncMode': 'local'}));
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryHome(
            database: db,
            persistedState: db.loadState(
              includeFullImages: false,
              includeInventory: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic home = tester.state(find.byType(InventoryHome));
      expect(home.inventory, isA<DiskInventoryList<InventoryItem>>());
      home.setState(() {
        home.type = InventoryType.other;
        home.sort = InventorySort.quantity;
        home.sortAscending = true;
      });
      await tester.pumpAndSettle();
      expect((home.visibleItems as List).first.quantity, 0);
      expect(home.retainedInventoryItemCount, lessThanOrEqualTo(12));
      home.setState(() {
        home.currentPage = 5;
      });
      await tester.pumpAndSettle();
      expect((home.visibleItems as List).first.quantity, 60);
      expect(home.retainedInventoryItemCount, lessThanOrEqualTo(12));
      home.setState(() {
        home.query = 'Bolt 299';
        home.currentPage = 0;
      });
      await tester.pumpAndSettle();
      expect((home.visibleItems as List).single.name, 'Bolt 299');
      expect(home.retainedInventoryItemCount, 1);
      expect(db.inventoryCount(), 300);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      db.close();
      dir.deleteSync(recursive: true);
    },
  );
}
