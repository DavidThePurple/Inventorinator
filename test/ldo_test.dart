import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventorinator/main.dart';
import 'package:inventorinator/west3d.dart';

void main() {
  testWidgets('LDO imports variants with LDO links and identity', (
    tester,
  ) async {
    final paths = <String>[];
    final product = {
      'handle': 'motor',
      'title': 'LDO motor',
      'vendor': 'LDO Motion',
      'type': 'Other',
    };
    final client = West3DClient(
      store: Storefront.ldo,
      client: MockClient((request) async {
        expect(request.url.host, 'store.ldomotion.com');
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
                        'sku': 'LDO-42',
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
                builder: (_) => AddItemDialog(ldoClient: client),
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
    await tester.ensureVisible(find.byKey(const Key('search-ldo')));
    await tester.tap(find.byKey(const Key('search-ldo')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ldo-query')), 'motor');
    await tester.tap(find.byKey(const Key('ldo-search')));
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
    expect(saved!.vendor, 'LDO');
    expect(saved!.quantity, 0);
    expect(saved!.customFieldValues['supplier.ldo.partNumber'], 'LDO-42');
    expect(
      saved!.productUrl,
      'https://store.ldomotion.com/products/motor?variant=1',
    );
    expect(paths, ['/search/suggest.json', '/products/motor.js']);
    expect(tester.takeException(), isNull);
    client.close();
  });
}
