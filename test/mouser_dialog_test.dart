import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/mouser.dart';
import 'package:inventorinator/mouser_search_dialog.dart';
import 'package:inventorinator/main.dart';

import 'mouser_test.dart' show mouserFixture;

void main() {
  for (final scenario in [
    (name: 'desktop', size: const Size(1280, 800), scale: 1.0, keyboard: 0.0),
    (name: 'tablet', size: const Size(800, 1100), scale: 1.0, keyboard: 0.0),
    (
      name: 'Android narrow',
      size: const Size(320, 640),
      scale: 1.0,
      keyboard: 0.0,
    ),
    (
      name: 'Android large text',
      size: const Size(360, 800),
      scale: 2.0,
      keyboard: 0.0,
    ),
    (
      name: 'Android keyboard',
      size: const Size(360, 800),
      scale: 1.3,
      keyboard: 300.0,
    ),
    (
      name: 'Android landscape',
      size: const Size(740, 360),
      scale: 1.0,
      keyboard: 140.0,
    ),
  ]) {
    testWidgets('responsive results: ${scenario.name}', (tester) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scenario.scale)),
            child: child!,
          ),
          home: Scaffold(
            body: MouserSearchDialog(
              searchOverride: (_, offset) async =>
                  MouserPage.fromJson(mouserFixture(), offset: offset),
            ),
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('mouser-query')), 'test');
      await tester.ensureVisible(find.byKey(const Key('mouser-search')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mouser-search')));
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('mouser-part-TEST-CT-ND'));
      final second = find.byKey(const ValueKey('mouser-part-TEST-REEL-ND'));
      if (scenario.name == 'desktop') {
        expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
        expect(
          tester.getTopLeft(second).dx,
          greaterThan(tester.getTopLeft(first).dx),
        );
      } else if (scenario.size.width <= 360) {
        expect(
          tester.getSize(first).width,
          greaterThan(scenario.size.width - 80),
        );
        expect(
          tester.getTopLeft(second).dy,
          greaterThan(tester.getTopLeft(first).dy),
        );
      }
      tester.view.viewInsets = FakeViewPadding(bottom: scenario.keyboard);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use this part').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'search select review and save keeps SKU without inventing owned stock or cost',
    (tester) async {
      InventoryItem? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Start'),
                onPressed: () async {
                  saved = await showDialog<InventoryItem>(
                    context: context,
                    builder: (_) => AddItemDialog(
                      mouserSearch: (query, offset) async =>
                          MouserPage.fromJson(mouserFixture()),
                      existingMouserPartNumbers: const {'TEST-CT-ND'},
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('supplier-search-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search-mouser')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('mouser-query')), 'test');
      await tester.tap(find.byKey(const Key('mouser-search')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use this part').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this part').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('already in your inventory'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('item-quantity')))
            .controller!
            .text,
        '0',
      );
      await tester.tap(find.byKey(const Key('save-item')));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      expect(
        saved!.name,
        'Connector with a long description for narrow screens',
      );
      expect(saved!.type, InventoryType.fastener);
      expect(saved!.quantity, 0);
      expect(saved!.cost, 0);
      expect(saved!.barcode, isEmpty);
      expect(saved!.vendor, 'Mouser');
      expect(
        saved!.customFieldValues['supplier.mouser.partNumber'],
        'TEST-CT-ND',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Mouser access form fits a phone with the keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MouserSearchDialog())),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
