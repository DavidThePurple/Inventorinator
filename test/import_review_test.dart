import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/import_review_dialog.dart';
import 'package:inventorinator/main.dart';

void main() {
  Future<List<InventoryJsonDraft>?> open(
    WidgetTester tester,
    List<InventoryJsonDraft> drafts,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<List<InventoryJsonDraft>>(
                context: context,
                builder: (_) => ImportReviewDialog(
                  drafts: drafts,
                  isDuplicate: (d) => d.name == 'Existing',
                  validate: (d) =>
                      d.typeName == 'Unknown' ? ['Unknown Type'] : [],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    // Return the dialog result through a captured navigation instead in each test.
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return null;
  }

  const draft = InventoryJsonDraft(
    rowNumber: 1,
    name: 'Part',
    typeName: 'Other',
    quantity: 2,
    cost: 0,
  );
  testWidgets('select individual rows and correct before accepting', (
    tester,
  ) async {
    await open(tester, [
      draft,
      const InventoryJsonDraft(
        rowNumber: 2,
        name: 'Second',
        typeName: 'Other',
        quantity: 3,
        cost: 0,
      ),
    ]);
    await tester.tap(find.byKey(const Key('import-select-1')));
    await tester.pumpAndSettle();
    expect(find.text('Import 1 items'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-edit-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('import-field-Name')),
      'Corrected',
    );
    await tester.enterText(
      find.byKey(const Key('import-field-Quantity')),
      '-2',
    );
    await tester.tap(find.byKey(const Key('import-save-row')));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a name and valid, non-negative quantity and cost.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('import-field-Quantity')), '5');
    await tester.tap(find.byKey(const Key('import-save-row')));
    await tester.pumpAndSettle();
    expect(find.text('Corrected'), findsOneWidget);
    expect(find.textContaining('qty 5.0'), findsOneWidget);
    expect(draft.name, 'Part');
  });
  testWidgets('unknown types can be corrected or deselected', (tester) async {
    await open(tester, [
      draft,
      const InventoryJsonDraft(
        rowNumber: 2,
        name: 'Bad type',
        typeName: 'Unknown',
        quantity: 1,
        cost: 0,
      ),
    ]);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirm-inventory-json-import')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('import-select-1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirm-inventory-json-import')),
          )
          .onPressed,
      isNotNull,
    );
  });
  testWidgets('review remains usable at a narrow touch-screen width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester, [draft, draft]);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('import-edit-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('import-field-Name')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicates within the same file are skipped by default', (
    tester,
  ) async {
    await open(tester, [draft, draft]);
    expect(find.text('1 possible duplicates'), findsOneWidget);
    expect(find.text('Import 1 items'), findsOneWidget);
    await tester.tap(find.text('Import them as new items'));
    await tester.pumpAndSettle();
    expect(find.text('Import 2 items'), findsOneWidget);
  });
}
