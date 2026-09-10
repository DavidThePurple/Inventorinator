import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventorinator/adafruit.dart';
import 'package:inventorinator/adafruit_catalog.dart';
import 'package:inventorinator/adafruit_search_dialog.dart';

List<Map<String, Object>> products() => List.generate(
  40,
  (i) => {
    'product_id': '${i + 1}',
    'product_name': 'Feather USB board $i',
    'product_mpn': 'ADA${i + 1}',
    'product_manufacturer': 'Adafruit',
  },
);
void main() {
  test(
    'catalog refresh is one request, SQL pages persist, bad refresh rolls back',
    () async {
      final dir = await Directory.systemTemp.createTemp('adafruit-catalog-');
      final dbPath = '${dir.path}/catalog.db';
      var catalog = AdafruitCatalog(dbPath);
      var calls = 0;
      var valid = true;
      var now = DateTime.utc(2026);
      final client = AdafruitClient(
        now: () => now,
        client: MockClient((request) async {
          calls++;
          expect(request.url.path, '/api/products');
          return http.Response(
            valid
                ? jsonEncode(products())
                : '[{"product_id":"90","product_name":"Bad"},',
            200,
          );
        }),
      );
      await catalog.refresh(client);
      expect(calls, 1);
      expect(catalog.count, 40);
      final page = catalog.search('USB feather', offset: 12);
      expect(page.total, 40);
      expect(page.parts, hasLength(12));
      expect(catalog.search('feather').parts, hasLength(12));
      expect(catalog.search('%').total, 0);
      expect(catalog.search('USB\' OR 1=1 --').total, 0);
      expect(
        catalog.search('https://www.adafruit.com/product/15').parts.first.id,
        '15',
      );
      expect(calls, 1);
      catalog.close();
      catalog = AdafruitCatalog(dbPath);
      expect(catalog.count, 40);
      expect(catalog.updatedAt, isNotNull);
      final date = catalog.updatedAt;
      valid = false;
      now = now.add(const Duration(seconds: 13));
      await expectLater(catalog.refresh(client), throwsA(anything));
      expect(catalog.count, 40);
      expect(catalog.updatedAt, date);
      catalog.close();
      client.close();
      dir.deleteSync(recursive: true);
    },
  );
  testWidgets(
    'keywords and pages work during cooldown without API calls on a phone',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('adafruit-catalog-ui-');
      final catalog = AdafruitCatalog('${dir.path}/catalog.db');
      final file = File('${dir.path}/products.json')
        ..writeAsStringSync(jsonEncode(products()));
      await tester.runAsync(() => catalog.importFile(file.path));
      var calls = 0;
      final client = AdafruitClient(
        client: MockClient((_) async {
          calls++;
          return http.Response('', 500);
        }),
      )..restoreCooldown(DateTime.now().add(const Duration(seconds: 60)));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdafruitSearchDialog(client: client, catalog: catalog),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('adafruit-query')),
        'feather USB',
      );
      await tester.tap(find.byKey(const Key('adafruit-search')));
      await tester.pumpAndSettle();
      expect(find.text('40 results'), findsOneWidget);
      expect(calls, 0);
      await tester.scrollUntilVisible(
        find.byKey(const Key('adafruit-next')),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('adafruit-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adafruit-next')));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 4'), findsOneWidget);
      expect(calls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      catalog.close();
      client.close();
      dir.deleteSync(recursive: true);
    },
  );
}
