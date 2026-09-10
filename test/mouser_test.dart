import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventorinator/mouser.dart';

Map<String, dynamic> mouserFixture() => {
  'Errors': [],
  'SearchResults': {
    'NumberOfResult': 50,
    'Parts': [
      for (final sku in ['TEST-CT-ND', 'TEST-REEL-ND'])
        {
          'MouserPartNumber': sku,
          'Category': 'Fasteners',
          'ManufacturerPartNumber': 'MPN-fixture',
          'Manufacturer': 'Fixture manufacturer',
          'Description': 'Connector with a long description for narrow screens',
          'ProductDetailUrl': 'https://www.mouser.com/ProductDetail/fixture',
          'DataSheetUrl': 'https://example.com/datasheet.pdf',
          'Min': '100',
          'AvailabilityInStock': '2400',
          'Availability': '2,400 In Stock',
          'ProductAttributes': [
            {'AttributeName': 'Packaging', 'AttributeValue': 'Cut Tape'},
          ],
          'PriceBreaks': [
            {'Quantity': 100, 'Price': '\$0.25', 'Currency': 'USD'},
          ],
        },
    ],
  },
};
void main() {
  test('search uses official request shape, paginates and preserves supplier metadata', () async {
    final client = MouserClient(
      apiKey: 'fixture-key',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/search/keyword');
        expect(request.url.queryParameters['apiKey'], 'fixture-key');
        final body = jsonDecode(request.body)['SearchByKeywordRequest'];
        expect(body['keyword'], 'connector');
        expect(body['startingRecord'], 20);
        expect(body['records'], 20);
        return http.Response(jsonEncode(mouserFixture()), 200);
      }),
    );
    final page = await client.search('connector', offset: 20);
    expect(page.hasNext, isTrue);
    final part = page.parts.first;
    expect(part.minimumOrderQuantity, 100);
    expect(part.available, 2400);
    expect(part.unitPrice, isNull);
    expect(part.inventoryMetadata['supplier.mouser.partNumber'], 'TEST-CT-ND');
    client.close();
  });
  test('API error bodies and network URLs cannot disclose API keys', () async {
    for (final response in [
      http.Response('{"Errors":[{"Message":"fixture-secret"}]}', 200),
      http.Response('fixture-secret', 429),
    ]) {
      final client = MouserClient(
        apiKey: 'fixture-secret',
        client: MockClient((_) async => response),
      );
      await expectLater(
        client.search('test'),
        throwsA(
          isA<MouserException>().having(
            (e) => e.message,
            'redacted',
            isNot(contains('fixture-secret')),
          ),
        ),
      );
      client.close();
    }
    final client = MouserClient(
      apiKey: 'fixture-secret',
      client: MockClient(
        (r) async => throw http.ClientException('failed ${r.url}'),
      ),
    );
    await expectLater(
      client.search('test'),
      throwsA(
        isA<MouserException>().having(
          (e) => e.message,
          'redacted',
          isNot(contains('fixture-secret')),
        ),
      ),
    );
    client.close();
  });
}
