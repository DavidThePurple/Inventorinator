import 'dart:io';

import 'package:inventorinator/local_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/main.dart';
import 'package:inventorinator/workshop_delta.dart';

void main() {
  final legacy = sampleInventory.first.copyWith(
    id: 'legacy',
    added: DateTime.utc(2026, 9, 19, 10),
  );
  final edited = legacy.copyWith(
    id: 'edited',
    added: DateTime.utc(2026, 1),
    modifiedAt: DateTime.utc(2026, 9, 19, 10, 1),
  );
  test(
    'Modified sorts newest first with time precision and legacy fallback',
    () {
      expect(defaultInventorySortAscending(InventorySort.modified), isFalse);
      expect(
        compareInventoryItems(
          edited,
          legacy,
          sort: InventorySort.modified,
          ascending: false,
        ),
        lessThan(0),
      );
      expect(
        compareInventoryItems(
          edited,
          legacy,
          sort: InventorySort.modified,
          ascending: true,
        ),
        greaterThan(0),
      );
      final restored = decodeWorkshopState(
        encodeWorkshopState(
          inventory: [legacy, edited],
          vendors: [],
          brands: [],
          products: [],
        ),
      )!.inventory;
      expect(restored.first.effectiveModifiedAt, legacy.added);
      expect(restored.last.modifiedAt, edited.modifiedAt);
    },
  );
  test('Sync keeps newest timestamp without hiding content conflicts', () {
    final merged = mergeRemoteChangesWithPending(
      [
        const WorkshopEntityChange(
          entityType: 'inventory',
          entityId: 'a',
          fields: {'name': 'Remote', 'modifiedAt': '2026-09-19T12:00:00Z'},
        ),
      ],
      [
        const WorkshopEntityChange(
          entityType: 'inventory',
          entityId: 'a',
          fields: {'name': 'Local', 'modifiedAt': '2026-09-19T11:00:00Z'},
        ),
      ],
    );
    expect(merged.changes.single.fields['modifiedAt'], '2026-09-19T12:00:00Z');
    expect(merged.conflicts.map((c) => c.field), ['name']);
  });
  testWidgets('Modified menu uses newest first', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      InventorinatorApp(
        persistedState: encodeWorkshopState(
          inventory: [legacy, edited],
          vendors: [],
          brands: [],
          products: [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('context-action-sort-modified')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<InventoryCard>(find.byType(InventoryCard))
          .map((card) => card.item.id),
      ['edited', 'legacy'],
    );
    await tester.tap(find.byKey(const Key('increase-quantity-legacy')));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final cards = tester.widgetList<InventoryCard>(find.byType(InventoryCard));
    expect(cards.first.item.id, 'legacy');
    expect(cards.first.item.modifiedAt, isNotNull);
  });
  testWidgets('Modified sorting survives database restart', (tester) async {
    final dir = Directory.systemTemp.createTempSync('modified-sort-');
    final path = '${dir.path}/db';
    var db = (await tester.runAsync(
      () => LocalDatabase.open(overridePath: path),
    ))!;
    db.saveState(
      encodeWorkshopState(
        inventory: [legacy, edited],
        vendors: [],
        brands: [],
        products: [],
      ),
    );
    db.saveSyncConfig('{"syncMode":"local"}');
    db.close();
    db = (await tester.runAsync(() => LocalDatabase.open(overridePath: path)))!;
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
    home.setState(() {
      home.sort = InventorySort.modified;
      home.sortAscending = false;
    });
    await tester.pumpAndSettle();
    expect((home.visibleItems as List).map((item) => item.id), [
      'edited',
      'legacy',
    ]);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => db.waitForPendingWrites());
    db.close();
    dir.deleteSync(recursive: true);
  });
}
