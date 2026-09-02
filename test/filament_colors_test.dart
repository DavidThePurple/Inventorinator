import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventorinator/filament_colors.dart';

const _responseBody = '''
{
  "count": 1,
  "next": null,
  "previous": null,
  "results": [
    {
      "id": 1725,
      "slug": "galaxy-black-petg",
      "manufacturer": {
        "id": 12,
        "name": "Polymaker",
        "website": "https://polymaker.com"
      },
      "color_name": "Galaxy Black",
      "filament_type": {
        "id": 4,
        "name": "PolyLite PETG",
        "hot_end_temp": "230-250",
        "bed_temp": "70-80",
        "parent_type": {"name": "PETG"}
      },
      "hex_color": "#17181A",
      "mfr_purchase_link": "https://example.com/galaxy-black",
      "notes": "A sample swatch note"
    }
  ]
}
''';

void main() {
  test('FilamentColors client parses swatches and applies filters', () async {
    late Uri requested;
    final client = FilamentColorsClient(
      httpClient: MockClient((request) async {
        requested = request.url;
        return http.Response(_responseBody, 200);
      }),
    );

    final results = await client.search(
      brand: 'Polymaker',
      material: 'PETG',
      query: 'Galaxy',
    );

    expect(
      requested.queryParameters['manufacturer__name__icontains'],
      'Polymaker',
    );
    expect(
      requested.queryParameters['filament_type__parent_type__name__icontains'],
      'PETG',
    );
    expect(requested.queryParameters['q'], 'Galaxy');
    expect(results.single.name, 'Galaxy Black');
    expect(results.single.hex, '#17181A');
    expect(results.single.manufacturer, 'Polymaker');
    expect(results.single.material, 'PETG');
    expect(results.single.hotEndTemperature, '230-250');
    expect(results.single.bedTemperature, '70-80');
    expect(results.single.purchaseUrl, 'https://example.com/galaxy-black');
    expect(results.single.notes, 'A sample swatch note');
    expect(results.single.sourceUrl, 'https://filamentcolors.xyz/swatch/1725/');
  });

  test('FilamentColors client reuses its local cache', () async {
    final cache = <String, String>{};
    var requests = 0;
    final client = FilamentColorsClient(
      httpClient: MockClient((_) async {
        requests++;
        return http.Response(_responseBody, 200);
      }),
      cacheRead: (key) => cache[key],
      cacheWrite: (key, value) => cache[key] = value,
      clock: () => DateTime.utc(2026, 8, 29),
    );

    await client.search(brand: 'Polymaker', material: 'PETG');
    await client.search(brand: 'Polymaker', material: 'PETG');

    expect(requests, 1);
    expect(cache, isNotEmpty);
  });

  test('FilamentColors client falls back to an expired cache', () async {
    final cache = <String, String>{};
    final seedClient = FilamentColorsClient(
      httpClient: MockClient((_) async => http.Response(_responseBody, 200)),
      cacheRead: (key) => cache[key],
      cacheWrite: (key, value) => cache[key] = value,
      clock: () => DateTime.utc(2026, 8, 1),
    );
    await seedClient.search(material: 'PETG');

    final offlineClient = FilamentColorsClient(
      httpClient: MockClient((_) async => http.Response('Forbidden', 403)),
      cacheRead: (key) => cache[key],
      cacheWrite: (key, value) => cache[key] = value,
      clock: () => DateTime.utc(2026, 8, 29),
    );

    final results = await offlineClient.search(material: 'PETG');
    expect(results.single.name, 'Galaxy Black');
  });

  test('FilamentColors cache is stored as a small JSON envelope', () async {
    final cache = <String, String>{};
    final client = FilamentColorsClient(
      httpClient: MockClient((_) async => http.Response(_responseBody, 200)),
      cacheWrite: (key, value) => cache[key] = value,
      clock: () => DateTime.utc(2026, 8, 29),
    );
    await client.search(query: 'Galaxy');

    final envelope = jsonDecode(cache.values.single) as Map<String, dynamic>;
    expect(envelope['savedAt'], '2026-08-29T00:00:00.000Z');
    expect(envelope['body'], _responseBody);
  });

  test(
    'FilamentColors rejects broad blank searches without a request',
    () async {
      var requests = 0;
      final client = FilamentColorsClient(
        httpClient: MockClient((_) async {
          requests++;
          return http.Response(_responseBody, 200);
        }),
      );

      await expectLater(
        client.search(),
        throwsA(
          isA<FilamentColorsException>().having(
            (error) => error.message,
            'message',
            contains('brand, material, or color'),
          ),
        ),
      );
      expect(requests, 0);
    },
  );

  test('FilamentColors spaces uncached requests', () async {
    var now = DateTime.utc(2026, 8, 29);
    final waits = <Duration>[];
    final client = FilamentColorsClient(
      httpClient: MockClient((_) async => http.Response(_responseBody, 200)),
      clock: () => now,
      delay: (duration) async {
        waits.add(duration);
        now = now.add(duration);
      },
    );

    await client.search(query: 'Galaxy');
    await client.search(query: 'Black');

    expect(waits, [const Duration(seconds: 2)]);
  });

  test(
    'FilamentColors caps uncached requests inside its rolling window',
    () async {
      final client = FilamentColorsClient(
        httpClient: MockClient((_) async => http.Response(_responseBody, 200)),
        minimumRequestInterval: Duration.zero,
        maximumRequestsPerWindow: 2,
        clock: () => DateTime.utc(2026, 8, 29),
      );

      await client.search(query: 'one');
      await client.search(query: 'two');
      await expectLater(
        client.search(query: 'three'),
        throwsA(
          isA<FilamentColorsException>().having(
            (error) => error.message,
            'message',
            contains('Search limit reached'),
          ),
        ),
      );
    },
  );

  test('FilamentColors collapses identical in-flight requests', () async {
    final response = Completer<http.Response>();
    var requests = 0;
    final client = FilamentColorsClient(
      httpClient: MockClient((_) {
        requests++;
        return response.future;
      }),
      minimumRequestInterval: Duration.zero,
    );

    final first = client.search(query: 'Galaxy');
    final second = client.search(query: 'Galaxy');
    await Future<void>.delayed(Duration.zero);
    response.complete(http.Response(_responseBody, 200));
    await Future.wait([first, second]);

    expect(requests, 1);
  });

  test('FilamentColors honors Retry-After without another request', () async {
    var requests = 0;
    final client = FilamentColorsClient(
      httpClient: MockClient((_) async {
        requests++;
        return http.Response(
          'Too Many Requests',
          429,
          headers: {'retry-after': '30'},
        );
      }),
      minimumRequestInterval: Duration.zero,
      clock: () => DateTime.utc(2026, 8, 29),
    );

    await expectLater(
      client.search(query: 'Galaxy'),
      throwsA(isA<FilamentColorsException>()),
    );
    await expectLater(
      client.search(query: 'Black'),
      throwsA(
        isA<FilamentColorsException>().having(
          (error) => error.message,
          'message',
          contains('cooling down'),
        ),
      ),
    );
    expect(requests, 1);
  });
}
