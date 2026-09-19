import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/inventory_spreadsheet.dart';
import 'package:inventorinator/main.dart';

InventoryItem _item(
  String id,
  String name, {
  InventoryType type = InventoryType.other,
  double quantity = 1,
  double cost = 0,
  String brand = '',
  List<String> compatibility = const [],
  bool archived = false,
}) => InventoryItem(
  id: id,
  name: name,
  type: type,
  compatibility: compatibility,
  added: DateTime(2026),
  cost: cost,
  color: Colors.grey,
  quantity: quantity,
  brand: brand,
  archived: archived,
);

String _typeLabel(InventoryItem item) => switch (item.type) {
  InventoryType.filament => 'Filament',
  InventoryType.fastener => 'Fastener',
  _ => 'Other',
};

void main() {
  final items = [
    _item(
      'INV-A',
      'PLA, matte "black"',
      type: InventoryType.filament,
      quantity: 2,
      cost: 19.99,
      brand: 'Polymaker',
      compatibility: ['MK3S+', 'Voron 2.4'],
    ),
    _item(
      'INV-B',
      'M4 × 10 bolt',
      type: InventoryType.fastener,
      quantity: 0.5,
      archived: true,
    ),
  ];

  void expectRoundTrip(InventoryJsonParseResult parsed) {
    expect(parsed.errors, isEmpty);
    expect(parsed.items, hasLength(items.length));
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final draft = parsed.items[index];
      expect(draft.id, item.id);
      expect(draft.name, item.name);
      expect(draft.typeName, _typeLabel(item));
      expect(draft.quantity, item.quantity);
      expect(draft.cost, item.cost);
      expect(draft.brand, item.brand);
      expect(draft.compatibility, item.compatibility);
      expect(draft.archived, item.archived);
    }
  }

  InventoryJsonParseResult reimport(SpreadsheetTable table) {
    final mapping = guessSpreadsheetMapping(table.headers);
    // Every exported column maps back to its field without manual matching.
    expect(mapping, everyElement(isNotNull));
    return parseInventoryJson(
      jsonEncode(spreadsheetRowsToInventoryJson(table, mapping)),
    );
  }

  test('CSV export re-imports with the same items', () {
    final csv = encodeCsv(inventoryExportTable(items, typeLabel: _typeLabel));
    expectRoundTrip(
      reimport(
        decodeInventorySpreadsheet(
          Uint8List.fromList(utf8.encode(csv)),
          'inventory.csv',
        ),
      ),
    );
  });

  test('XLSX export re-imports with the same items', () {
    final bytes = encodeXlsx(
      inventoryExportTable(items, typeLabel: _typeLabel),
    );
    expectRoundTrip(
      reimport(decodeInventorySpreadsheet(bytes, 'inventory.xlsx')),
    );
  });

  test('portable JSON re-imports with the same items and is versioned', () {
    final document = portableInventoryDocument(
      items,
      typeLabel: _typeLabel,
      kits: const [
        KitRecord(
          id: 'KIT-1',
          name: 'Frame',
          bom: [KitBomEntry(id: 'L1', productId: 'INV-B', quantity: 4)],
        ),
      ],
    );
    expect(document['format'], portableInventoryFormat);
    expect(document['version'], portableInventoryVersion);
    expect((document['kits']! as List).single['bom'].single['quantity'], 4);
    expectRoundTrip(parseInventoryJson(jsonEncode(document)));
  });

  test('portable JSON from a newer app version is rejected clearly', () {
    final parsed = parseInventoryJson(
      jsonEncode({
        'format': portableInventoryFormat,
        'version': portableInventoryVersion + 1,
        'items': [
          {'name': 'Bolt'},
        ],
      }),
    );
    expect(parsed.isValid, isFalse);
    expect(parsed.errors.single, contains('newer Inventorinator'));
  });

  Future<dynamic> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryHome(
          persistedState: encodeWorkshopState(
            inventory: [
              _item(
                'INV-EXISTING',
                'M4 bolt',
                type: InventoryType.fastener,
                quantity: 9,
              ),
            ],
            vendors: const [],
            brands: const [],
            products: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state(find.byType(InventoryHome));
  }

  const csv =
      'Item ID,Name,Type,Qty,Notes\n'
      'INV-NEW,Hex key set,Other,2,keep\n'
      'INV-EXISTING,M4 bolt,Fastener,9,dup\n';

  testWidgets('CSV import maps columns, keeps IDs and skips duplicates', (
    tester,
  ) async {
    final dynamic home = await pumpHome(tester);
    final result = home.importInventoryData(
      Uint8List.fromList(utf8.encode(csv)),
      'stock.csv',
    ) as Future<bool>;
    await tester.pumpAndSettle();

    // Headers were matched; the unrecognised Notes column is skipped.
    expect(find.byKey(const Key('spreadsheet-preview')), findsOneWidget);
    expect(find.text('Hex key set'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-spreadsheet-mapping')));
    await tester.pumpAndSettle();

    expect(find.text('1 possible duplicates'), findsOneWidget);
    expect(find.text('Import 1 items'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-inventory-json-import')));
    await tester.pumpAndSettle();
    expect(await result, isTrue);

    final inventory = (home.inventory as List<InventoryItem>);
    expect(inventory.map((item) => item.id), ['INV-EXISTING', 'INV-NEW']);
    expect(inventory.last.quantity, 2);
  });

  testWidgets('CSV import can bring duplicates in as new items', (
    tester,
  ) async {
    final dynamic home = await pumpHome(tester);
    final result = home.importInventoryData(
      Uint8List.fromList(utf8.encode(csv)),
      'stock.csv',
    ) as Future<bool>;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-spreadsheet-mapping')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import them as new items'));
    await tester.pumpAndSettle();
    expect(find.text('Import 2 items'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-inventory-json-import')));
    await tester.pumpAndSettle();
    expect(await result, isTrue);

    final ids = (home.inventory as List<InventoryItem>).map((item) => item.id);
    expect(ids, hasLength(3));
    // The duplicate gets a fresh ID; the free one is kept.
    expect(ids.where((id) => id == 'INV-EXISTING'), hasLength(1));
    expect(ids, contains('INV-NEW'));
  });

  testWidgets('mapping requires a Name column', (tester) async {
    final dynamic home = await pumpHome(tester);
    final result = home.importInventoryData(
      Uint8List.fromList(utf8.encode('Label,Qty\nBolt,4\n')),
      'stock.csv',
    ) as Future<bool>;
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('confirm-spreadsheet-mapping'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.tap(find.byKey(const Key('spreadsheet-column-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name').last);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('Bulk Import flyout offers import, Rapidizer and export', (
    tester,
  ) async {
    await pumpHome(tester);
    final button = find.byKey(const Key('open-inventory-json-import'));
    expect(
      find.descendant(of: button, matching: find.text('Bulk Import')),
      findsOneWidget,
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Import CSV, XLSX or JSON…'), findsOneWidget);
    expect(find.text('Rapidizer…'), findsOneWidget);
    expect(find.text('Export inventory…'), findsOneWidget);

    await tester.tap(find.text('Rapidizer…'));
    await tester.pumpAndSettle();
    expect(find.byType(RapidizerDialog), findsOneWidget);
  });

  testWidgets('export writes the chosen format and scope', (tester) async {
    final dynamic home = await pumpHome(tester);
    String? savedName;
    Uint8List? savedBytes;
    final done = home.exportInventory(
      save: (String name, Uint8List bytes) async {
        savedName = name;
        savedBytes = bytes;
        return '/tmp/$name';
      },
    ) as Future<void>;
    await tester.pumpAndSettle();
    await tester.tap(find.text('CSV'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-inventory-export')));
    await tester.pumpAndSettle();
    await done;

    expect(savedName, endsWith('.csv'));
    final rows = decodeCsv(utf8.decode(savedBytes!));
    expect(rows.first.first, 'Item ID');
    expect(rows[1].take(4), ['INV-EXISTING', 'M4 bolt', 'Fasteners', '9']);
  });
}
