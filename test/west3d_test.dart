import 'dart:convert';

import 'package:image/image.dart' as img;
import 'package:inventorinator/supplier_images.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventorinator/main.dart';
import 'package:inventorinator/west3d.dart';
import 'package:inventorinator/west3d_search_dialog.dart';

Map<String, dynamic> product() => {
  'handle': 'test-bolt',
  'title': 'Socket bolt',
  'vendor': 'West hardware',
  'type': 'Fasteners',
};
West3DClient fixture(List<Uri> requests, {String imageUrl = ''}) =>
    West3DClient(
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('suggest.json')) {
          return http.Response(
            jsonEncode({
              'resources': {
                'results': {
                  'products': [product()],
                },
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            ...product(),
            'featured_image': imageUrl,
            'variants': [
              {
                'id': 123,
                'sku': 'BOLT-M3',
                'title': 'M3 × 10 mm',
                'available': true,
                'price': 125,
              },
              {
                'id': 124,
                'sku': 'BOLT-M4',
                'title': 'M4 × 10 mm',
                'available': false,
                'price': 200,
              },
            ],
          }),
          200,
        );
      }),
    );

void main() {
  test('search is bounded and loads variants only on selection', () async {
    final requests = <Uri>[];
    final client = fixture(requests);
    final products = await client.search('bolt');
    expect(requests, hasLength(1));
    expect(requests.single.queryParameters['resources[limit]'], '10');
    final variants = await client.variants(products.single);
    expect(variants, hasLength(2));
    expect(variants.first.itemName, 'Socket bolt — M3 × 10 mm');
    expect(
      variants.first.inventoryMetadata['supplier.west3d.variantId'],
      '123',
    );
    expect(variants.last.available, false);
    expect(requests.last.host, 'west3d.com');
    expect(variants.first.productUrl, endsWith('?variant=123'));
    client.close();
  });
  test(
    'empty queries, invalid JSON and service failures are readable',
    () async {
      final client = West3DClient(
        client: MockClient((_) async => http.Response('busy', 429)),
      );
      await expectLater(client.search(''), throwsA(isA<West3DException>()));
      await expectLater(client.search('bolt'), throwsA(isA<West3DException>()));
      client.close();
      final malformed = West3DClient(
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(
        malformed.search('bolt'),
        throwsA(isA<West3DException>()),
      );
      malformed.close();
    },
  );
  for (final scenario in [
    (size: const Size(1280, 800), scale: 1.0, keyboard: 0.0),
    (size: const Size(360, 800), scale: 2.0, keyboard: 0.0),
    (size: const Size(360, 800), scale: 1.0, keyboard: 300.0),
  ]) {
    testWidgets(
      'search and variant layout ${scenario.size} ${scenario.scale}',
      (tester) async {
        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = FakeViewPadding(bottom: scenario.keyboard);
        addTearDown(tester.view.reset);
        final client = fixture([]);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scenario.scale)),
              child: child!,
            ),
            home: Scaffold(body: West3DSearchDialog(client: client)),
          ),
        );
        await tester.enterText(find.byKey(const Key('west3d-query')), 'bolt');
        await tester.ensureVisible(find.byKey(const Key('west3d-search')));
        await tester.tap(find.byKey(const Key('west3d-search')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Choose variant'));
      await tester.pumpAndSettle();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Choose variant'));
      await tester.pumpAndSettle();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Choose variant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose variant'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Use this part').first);
      await tester.pumpAndSettle();
        expect(find.text('Socket bolt — M3 × 10 mm'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        client.close();
      },
    );
  }
  testWidgets(
    'supplier button imports chosen variant into existing item editor',
    (tester) async {
      const imageUrl = 'https://example.com/west3d.png';
      final previousCache = SupplierImageCache.shared;
      var imageCalls = 0;
      SupplierImageCache.shared = SupplierImageCache(
        clientFactory: () => MockClient((_) async {
          imageCalls++;
          return http.Response.bytes(
            img.encodePng(img.Image(width: 40, height: 30)),
            200,
          );
        }),
      );
      addTearDown(() => SupplierImageCache.shared = previousCache);
      // Preload exactly as a result preview would; selection must reuse it.
      await tester.runAsync(() => SupplierImageCache.shared.load(imageUrl));
      final client = fixture([], imageUrl: imageUrl);
      InventoryItem? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showDialog<InventoryItem>(
                  context: context,
                  builder: (_) => AddItemDialog(west3dClient: client),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('supplier-search-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search-west3d')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('west3d-query')), 'bolt');
      await tester.tap(find.byKey(const Key('west3d-search')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Choose variant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose variant'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use this part').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this part').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-item')));
      await tester.pumpAndSettle();
      expect(saved!.name, 'Socket bolt — M3 × 10 mm');
      expect(saved!.type, InventoryType.fastener);
      expect(saved!.quantity, 0);
      expect(saved!.cost, 0);
      expect(saved!.vendor, 'West3D');
      expect(saved!.imageBytes, isNotNull);
      expect(saved!.thumbnailBytes, isNotNull);
      expect(imageCalls, 1);
      expect(saved!.customFieldValues['supplier.west3d.partNumber'], 'BOLT-M3');
      expect(tester.takeException(), isNull);
      client.close();
    },
  );
}
