import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/import_format_dialog.dart';
import 'package:inventorinator/inventory_spreadsheet.dart';
import 'package:inventorinator/main.dart';

void main() {
  test('Displayed examples are accepted by the real import parsers', () {
    final json = parseInventoryJson(inventoryImportJsonExample);
    expect(json.errors, isEmpty);
    expect(json.items.single.name, 'Purple PLA');
    final table = decodeInventorySpreadsheet(
      Uint8List.fromList(utf8.encode(inventoryImportCsvExample)),
      'example.csv',
    );
    final csv = parseInventoryJson(
      jsonEncode(
        spreadsheetRowsToInventoryJson(
          table,
          guessSpreadsheetMapping(table.headers),
        ),
      ),
    );
    expect(csv.errors, isEmpty);
    expect(csv.items, hasLength(2));
    expect(csv.items.first.cost, 19.99);
    expect(csv.items.last.quantity, 50);
  });

  testWidgets(
    'Guide scrolls on phones, copies example, and keeps choose file accessible',
    (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    builder: (_) => const ImportFormatDialog(chooseFile: true),
                  );
                },
                child: const Text('Open guide'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open guide'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Copy CSV example'));
      await tester.tap(find.text('Copy CSV example'));
      await tester.pumpAndSettle();
      expect(copied, inventoryImportCsvExample);
      await tester.ensureVisible(find.text('All supported columns'));
      await tester.tap(find.text('All supported columns'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Archived · archived'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Choose file…'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    },
  );
}
