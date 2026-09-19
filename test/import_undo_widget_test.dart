import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/import_batches.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/main.dart';

void main() {
  testWidgets('review edits commit and history undo works after app restart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('undo-widget-');
    var db = (await tester.runAsync(
      () => LocalDatabase.open(overridePath: '${dir.path}/db'),
    ))!;
    db.saveState(
      encodeWorkshopState(
        inventory: const [],
        vendors: const [],
        brands: const [],
        products: const [],
      ),
    );
    db.saveStringPreference('onboarding_completed', 'true');
    Future<dynamic> pump() async {
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryHome(
            database: db,
            persistedState: db.loadState(includeInventory: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.state(find.byType(InventoryHome));
    }

    dynamic home = await pump();
    final importing = home.importInventoryData(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode([
            {
              'id': 'IMPORT-A',
              'name': 'Original name',
              'type': 'Other',
              'quantity': 2,
            },
            {
              'id': 'IMPORT-B',
              'name': 'Rejected row',
              'type': 'Other',
              'quantity': 1,
            },
          ]),
        ),
      ),
      'parts.json',
    ) as Future<bool>;
    bool? importCompleted;
    importing.then((value) => importCompleted = value);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-select-1')));
    await tester.tap(find.byKey(const Key('import-edit-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('import-field-Name')),
      'Correct name',
    );
    await tester.tap(find.byKey(const Key('import-save-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-inventory-json-import')));

    await tester.pumpAndSettle();
    for (var i = 0; i < 20 && importCompleted == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
    }
    expect(importCompleted, true);

    expect(
      db.readEntityPayload('inventory', 'IMPORT-A')?['name'],
      'Correct name',
    );
    expect(db.readEntityPayload('inventory', 'IMPORT-B'), isNull);
    final batchId = ImportBatchStore(db, 'local').list().single['id'] as String;

    await tester.pumpWidget(const SizedBox());

    await tester.pumpAndSettle();

    db.close();
    db = (await tester.runAsync(
      () => LocalDatabase.open(overridePath: '${dir.path}/db'),
    ))!;

    home = await pump();
    home.openImportHistory();
    await tester.pumpAndSettle();
    expect(find.text('parts.json'), findsOneWidget);
    await tester.tap(find.byKey(Key('undo-import-$batchId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-undo-import')));
    await tester.pumpAndSettle();
    for (
      var i = 0;
      i < 20 && db.readEntityPayload('inventory', 'IMPORT-A') != null;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
    }
    expect(db.readEntityPayload('inventory', 'IMPORT-A'), isNull);
    expect(
      db
          .loadPendingWorkshopChanges()
          .where((p) => p.change.entityId == 'IMPORT-A')
          .single
          .change
          .baseFields?['(importUndo)'],
      true,
    );
    expect((home.inventory as List<InventoryItem>), isEmpty);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());

    await tester.pumpAndSettle();
    db.close();
    dir.deleteSync(recursive: true);
  });
}
