import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventorinator/main.dart';
import 'package:inventorinator/supplier_search_menu.dart';
import 'package:inventorinator/west3d.dart';

void main() {
  testWidgets('last supplier is reachable in the menu on a large-text phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Storefront? selected;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SupplierSearchMenu(
              onDigiKey: () {},
              onMouser: () {},
              onWest3D: () {},
              onLdo: () {},
              onAdafruit: () {},
              onStorefront: (store) => selected = store,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('supplier-search-menu')));
    await tester.pumpAndSettle();
    final panel = tester.getRect(
      find.byKey(const Key('supplier-provider-panel')),
    );
    expect(panel.center.dx, closeTo(160, 1));
    expect(panel.center.dy, closeTo(320, 1));
    final first = tester.getRect(find.byKey(const Key('search-digikey')));
    final second = tester.getRect(find.byKey(const Key('search-mouser')));
    expect(first.top, second.top);
    expect(second.left, greaterThanOrEqualTo(first.right));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.enterText(find.byKey(const Key('supplier-filter')), 'BIGtree');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-biqu')), findsOneWidget);
    expect(find.byKey(const Key('search-digikey')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('supplier-filter')),
      'unknown supplier',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching suppliers'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear supplier filter'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-digikey')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('supplier-filter')), 'sLiCe');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('search-slice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('search-slice')));
    await tester.pumpAndSettle();
    expect(selected, Storefront.slice);
    expect(find.byKey(const Key('search-slice')), findsNothing);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.tap(find.byKey(const Key('supplier-search-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-digikey')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('supplier-filter')))
          .controller!
          .text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider panel stays centered with an off-center trigger', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: SupplierSearchMenu(
              onDigiKey: () {},
              onMouser: () {},
              onWest3D: () {},
              onLdo: () {},
              onAdafruit: () {},
              onStorefront: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('supplier-search-menu')));
    await tester.pumpAndSettle();
    final panel = tester.getRect(
      find.byKey(const Key('supplier-provider-panel')),
    );
    expect(panel.center.dx, closeTo(640, 1));
    expect(panel.center.dy, closeTo(450, 1));
    expect(tester.takeException(), isNull);
  });

  for (final store in Storefront.values.where(
    (s) => s != Storefront.ldo && s != Storefront.west3d,
  )) {
    testWidgets(
      '${store.label} imports variants with its own links and identity',
      (tester) async {
        final paths = <String>[];
        final product = {
          'handle': 'motor',
          'title': 'LDO motor',
          'vendor': 'LDO Motion',
          'type': 'Other',
        };
        final client = West3DClient(
          store: store,
          client: MockClient((request) async {
            expect(request.url.host, store.host);
            paths.add(request.url.path);
            return http.Response(
              jsonEncode(
                request.url.path.endsWith('suggest.json')
                    ? {
                        'resources': {
                          'results': {
                            'products': [product],
                          },
                        },
                      }
                    : {
                        ...product,
                        'variants': [
                          {
                            'id': 1,
                            'sku': store == Storefront.petgusa
                                ? null
                                : 'LDO-42',
                            'title': 'Long shaft',
                            'available': true,
                          },
                        ],
                      },
              ),
              200,
            );
          }),
        );
        InventoryItem? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await showDialog<InventoryItem>(
                    context: context,
                    builder: (_) =>
                        AddItemDialog(storefrontClients: {store: client}),
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
        await tester.ensureVisible(find.byKey(Key('search-${store.name}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('search-${store.name}')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(Key('${store.name}-query')), 'motor');
        await tester.tap(find.byKey(Key('${store.name}-search')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose variant'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use this part'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('item-type')));
        await tester.tap(find.byKey(const Key('item-type')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Other').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('save-item')));
        await tester.pumpAndSettle();
        expect(saved!.vendor, store.label);
        expect(saved!.quantity, 0);
        expect(
          saved!.customFieldValues['supplier.${store.name}.partNumber'],
          store == Storefront.petgusa ? '' : 'LDO-42',
        );
        expect(
          saved!.customFieldValues['supplier.${store.name}.variantId'],
          '1',
        );
        expect(
          saved!.productUrl,
          'https://${store.host}/products/motor?variant=1',
        );
        expect(paths, ['/search/suggest.json', '/products/motor.js']);
        expect(tester.takeException(), isNull);
        client.close();
      },
    );
  }
}
