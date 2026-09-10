import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventorinator/digikey.dart';

Map<String, dynamic> digiKeyFixture() => {
  'ProductsCount': 40,
  'SearchLocaleUsed': {'Currency': 'USD'},
  'Products': [
    {
      'ManufacturerProductNumber': 'TEST-123',
      'Category': {'Name': 'Fasteners'},
      'Manufacturer': {'Name': 'Example Components'},
      'Description': {'ProductDescription': 'Test component'},
      'ProductUrl': 'https://www.digikey.com/en/products/detail/example/123',
      'DatasheetUrl': 'https://example.com/part.pdf',
      'ProductVariations': [
        {
          'DigiKeyProductNumber': 'TEST-CT-ND',
          'PackageType': {'Name': 'Cut Tape'},
          'QuantityAvailableforPackageType': 900,
          'MinimumOrderQuantity': 1,
          'StandardPackage': 1000,
          'StandardPricing': [
            {'BreakQuantity': 1, 'UnitPrice': .25},
          ],
        },
        {
          'DigiKeyProductNumber': 'TEST-REEL-ND',
          'PackageType': {'Name': 'Tape & Reel'},
          'QuantityAvailableforPackageType': 10000,
          'MinimumOrderQuantity': 1000,
          'StandardPackage': 1000,
          'StandardPricing': [
            {'BreakQuantity': 1000, 'UnitPrice': .12},
          ],
        },
      ],
    },
  ],
};
void main() {
  test(
    'preserves package SKU and units without treating supplier stock as owned',
    () {
      final page = DigiKeyPage.fromJson(digiKeyFixture());
      expect(page.parts.length, 2);
      expect(page.parts.last.supplierPartNumber, 'TEST-REEL-ND');
      expect(page.parts.first.unitPrice, .25);
      expect(page.parts.last.unitPrice, isNull);
      expect(page.parts.last.minimumOrderQuantity, 1000);
      expect(
        page.parts.last.inventoryMetadata['supplier.digikey.standardPackage'],
        '1000',
      );
      expect(
        page.parts.first.inventoryMetadata.keys.any(
          (k) => k.contains('available'),
        ),
        isFalse,
      );
      expect(page.returnedProducts, 1);
      expect(page.hasNext, isTrue);
      expect(safeProductLink('javascript:alert(1)'), isEmpty);
      expect(safeProductLink('https://user:secret@example.com/'), isEmpty);
    },
  );
  test(
    'uses official OAuth and search paths with cached token and pagination',
    () async {
      var tokens = 0;
      var searches = 0;
      final client = DigiKeyClient(
        clientId: 'id',
        clientSecret: 'secret',
        client: MockClient((request) async {
          expect(request.url.host, 'api.digikey.com');
          if (request.url.path == '/v1/oauth2/token') {
            tokens++;
            expect(
              Uri.splitQueryString(request.body)['grant_type'],
              'client_credentials',
            );
            return http.Response(
              '{"access_token":"token","expires_in":599}',
              200,
            );
          }
          expect(request.url.path, '/products/v4/search/keyword');
          expect(request.headers['Authorization'], 'Bearer token');
          final body = jsonDecode(request.body) as Map;
          expect(body['Offset'], searches == 0 ? 0 : 20);
          expect(body['Keywords'], 'resistor');
          searches++;
          return http.Response(jsonEncode(digiKeyFixture()), 200);
        }),
      );
      addTearDown(client.close);
      await client.search(' resistor ');
      await client.search('resistor', offset: 20);
      expect(tokens, 1);
      expect(searches, 2);
    },
  );
  test('API errors never expose raw response secrets', () async {
    final client = DigiKeyClient(
      clientId: 'id',
      clientSecret: 'secret',
      client: MockClient((_) async => http.Response('private-secret', 429)),
    );
    addTearDown(client.close);
    await expectLater(
      client.search('resistor'),
      throwsA(
        isA<DigiKeyException>().having(
          (e) => e.message,
          'message',
          allOf(contains('limit'), isNot(contains('private-secret'))),
        ),
      ),
    );
  });
}
