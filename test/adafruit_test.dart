import 'dart:convert';
import 'dart:io';

import 'package:inventorinator/adafruit_catalog.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventorinator/adafruit.dart';
import 'package:inventorinator/adafruit_search_dialog.dart';

Map<String, dynamic> part(String id) => {
  'product_id': id,
  'product_name': 'Test board',
  'product_mpn': 'ADA$id',
};
void main() {
  test('cooldown spaces calls, shares repeated lookups, and permits cached results', () async {
    var now = DateTime.utc(2026);
    var calls = 0;
    DateTime? persisted;
    final client = AdafruitClient(
      now: () => now,
      client: MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode(part(request.url.pathSegments.last)),
          200,
        );
      }),
    )..persistCooldown = (value) => persisted = value;
    final a = client.lookup('998');
    final b = client.lookup('998');
    expect(await a, same(await b));
    expect(calls, 1);
    expect(client.secondsRemaining, 13);
    await expectLater(client.lookup('999'), throwsA(isA<AdafruitException>()));
    expect(
      (await client.lookup('https://www.adafruit.com/product/998')).id,
      '998',
    );
    expect(calls, 1);
    final reopened = AdafruitClient(now: () => now)..restoreCooldown(persisted);
    expect(reopened.secondsRemaining, 13);
    reopened.close();
    now = now.add(const Duration(seconds: 13));
    await client.lookup('999');
    expect(calls, 2);
    expect(client.secondsRemaining, 13);
    client.close();
  });
  test(
    'invalid input makes no request; server backoff survives ordinary cooldown',
    () async {
      var now = DateTime.utc(2026);
      var calls = 0;
      final client = AdafruitClient(
        now: () => now,
        client: MockClient((_) async {
          calls++;
          return http.Response('', 429, headers: {'retry-after': '90'});
        }),
      );
      await expectLater(
        client.lookup('feather'),
        throwsA(isA<AdafruitException>()),
      );
      expect(calls, 0);
      await expectLater(
        client.lookup('998'),
        throwsA(isA<AdafruitException>()),
      );
      expect(client.secondsRemaining, 90);
      now = now.add(const Duration(seconds: 13));
      await expectLater(
        client.lookup('998'),
        throwsA(isA<AdafruitException>()),
      );
      expect(calls, 1);
      expect(client.secondsRemaining, 77);
      client.close();
    },
  );
  testWidgets(
    'phone cooldown counts down, cached lookup remains enabled, closing keeps gate',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var now = DateTime.utc(2026);
      var calls = 0;
      final client = AdafruitClient(
        now: () => now,
        client: MockClient((request) async {
          calls++;
          return http.Response(jsonEncode(part('998')), 200);
        }),
      );
      final folder = Directory.systemTemp.createTempSync('adafruit-ui-');
      final catalog = AdafruitCatalog('${folder.path}/catalog.db');
      addTearDown(() async {
        catalog.close();
        folder.deleteSync(recursive: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: AdafruitSearchDialog(client: client, catalog: catalog),
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('adafruit-query')), '998');
      await tester.tap(find.byKey(const Key('adafruit-search')));
      await tester.pumpAndSettle();
      expect(find.text('Next request in 13s'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('adafruit-search')))
            .onPressed,
        isNotNull,
      );
      await tester.enterText(find.byKey(const Key('adafruit-query')), '999');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('adafruit-search')))
            .onPressed,
        isNull,
      );
      now = now.add(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Next request in 9s'), findsOneWidget);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(client.secondsRemaining, 9);
      client.close();
    },
  );
}
