import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventorinator/cloud_sync_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/main.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/digikey_credentials.dart';
import 'package:inventorinator/mouser_credentials.dart';
import 'package:inventorinator/supabase_sync.dart';
import 'package:inventorinator/service_status.dart';

void main() {
  for (final scenario in [(true, 21), (true, 25), (false, 21), (false, 25)]) {
    final (succeeds, version) = scenario;
    testWidgets('manual sync LED reflects final result: $succeeds v$version', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('manual-sync-led-');
      final db = (await tester.runAsync(
        () => LocalDatabase.open(overridePath: '${dir.path}/db.sqlite3'),
      ))!;
      final config = SupabaseConfig(
        url: 'https://example.invalid',
        publishableKey: 'fixture',
        syncMode: 'supabase',
        workspaceId: 'led-test',
        userId: 'user',
        refreshToken: 'refresh',
        accessToken: 'access',
        accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
        workspaceRole: 'viewer',
      );
      db.saveSyncConfig(jsonEncode(config.toJson()));
      final upload = Completer<http.Response>();
      final client = MockClient((request) async {
        if (request.url.path.endsWith('inventorinator_schema')) {
          return http.Response(
            jsonEncode([
              {'version': version},
            ]),
            200,
          );
        }
        if (request.url.path.endsWith('get_inventorinator_role')) {
          return http.Response('"viewer"', 200);
        }
        if (request.url.path.endsWith('get_inventorinator_remote_purge_days')) {
          return http.Response('3', 200);
        }
        if (request.url.path.endsWith('workshop_states')) {
          return http.Response('[]', 200);
        }
        if (request.url.path.endsWith('save_inventorinator_workshop_state')) {
          return upload.future;
        }
        throw StateError('Unexpected request: ${request.url.path}');
      });
      final key = 'Supabase:${digiKeyScope(config.url, config.workspaceId)}';
      await tester.pumpWidget(
        MaterialApp(
          home: CloudSyncDialog(
            database: db,
            httpClient: client,
            localStateJson: '{}',
            onCloudState: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      ServiceStatus.set(key, ConnectionStateLed.failed);
      await tester.tap(find.byKey(const Key('sync-now')));
      await tester.pumpAndSettle();
      expect(ServiceStatus.read(key), ConnectionStateLed.checking);
      // An earlier connection result must be replaced by this sync's outcome.
      ServiceStatus.set(
        key,
        succeeds ? ConnectionStateLed.failed : ConnectionStateLed.connected,
      );
      upload.complete(
        succeeds
            ? http.Response('"2026-09-10T12:00:00Z"', 200)
            : http.Response('{"message":"Upload failed"}', 500),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final dynamic dialog = tester.state(find.byType(CloudSyncDialog));
      expect(
        ServiceStatus.read(key),
        succeeds
            ? (version < 25
                  ? ConnectionStateLed.limited
                  : ConnectionStateLed.connected)
            : ConnectionStateLed.failed,
        reason: dialog.message as String,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.close();
      db.close();
      dir.deleteSync(recursive: true);
    });
  }
  testWidgets('background sync completes on v21 with an amber LED', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('auto-sync-compat-');
    final db = (await tester.runAsync(
      () => LocalDatabase.open(overridePath: '${dir.path}/db.sqlite3'),
    ))!;
    final config = SupabaseConfig(
      url: 'https://example.invalid',
      publishableKey: 'fixture',
      syncMode: 'supabase',
      workspaceId: 'auto-compat',
      userId: 'user',
      refreshToken: 'refresh',
      accessToken: 'access',
      accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
      workspaceRole: 'viewer',
      autoSyncEnabled: true,
      syncIntervalSeconds: 15,
    );
    db.saveSyncConfig(jsonEncode(config.toJson()));
    var downloads = 0;
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('inventorinator_schema')) {
        return http.Response('[{"version":21}]', 200);
      }
      if (path.endsWith('get_inventorinator_role')) {
        return http.Response('"viewer"', 200);
      }
      if (path.endsWith('get_inventorinator_remote_purge_days')) {
        return http.Response('3', 200);
      }
      if (path.endsWith('inventorinator_entities')) {
        downloads++;
        return http.Response('[]', 200);
      }
      if (path.endsWith('apply_inventorinator_entity_changes')) {
        return http.Response('1', 200);
      }
      if (path.contains('register')) return http.Response('', 204);
      throw StateError('Unexpected request: $path');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryHome(
          database: db,
          supabaseHttpClient: client,
          persistedState: encodeWorkshopState(
            inventory: [],
            vendors: [],
            brands: [],
            products: [],
            materials: [],
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      if (SupabaseConfig.fromJson(jsonDecode(db.loadSyncConfig()!))
              .lastSyncedAt !=
          null) {
        break;
      }
    }
    expect(downloads, greaterThanOrEqualTo(2));
    expect(
      SupabaseConfig.fromJson(jsonDecode(db.loadSyncConfig()!)).lastSyncedAt,
      isNotNull,
    );
    expect(
      ServiceStatus.read(
        'Supabase:${digiKeyScope(config.url, config.workspaceId)}',
      ),
      ConnectionStateLed.limited,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => db.waitForPendingWrites());
    client.close();
    db.close();
    dir.deleteSync(recursive: true);
  });

  for (final width in [360.0, 1280.0]) {
    testWidgets('configured service LEDs fit beside logo at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('service-led-');
      final db = (await tester.runAsync(
        () => LocalDatabase.open(overridePath: '${dir.path}/db.sqlite3'),
      ))!;
      db.saveSyncConfig(
        jsonEncode(
          const SupabaseConfig(
            url: '',
            publishableKey: '',
            syncMode: 'local',
          ).toJson(),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(width < 600 ? 2 : 1)),
            child: child!,
          ),
          home: InventoryHome(
            database: db,
            persistedState: encodeWorkshopState(
              inventory: [],
              vendors: [],
              brands: [],
              products: [],
              materials: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ServiceStatusLed), findsNothing);
      const config = SupabaseConfig(
        url: 'https://example.invalid',
        publishableKey: 'fixture',
      );
      db.saveSyncConfig(jsonEncode(config.toJson()));
      final store = DigiKeyCredentialStore(db, digiKeyScope(config.url, null));
      store.save(
        const DigiKeyCredentials(clientId: 'fixture', clientSecret: 'fixture'),
        pending: false,
      );
      MouserCredentialStore(
        db,
        'local',
      ).save(const MouserCredentials(apiKey: 'fixture'), pending: false);
      ServiceStatus.set('DigiKey:local', ConnectionStateLed.connected);
      await tester.pumpAndSettle();
      expect(find.byType(ServiceStatusLed), findsNWidgets(3));
      final logo = tester.getRect(find.byKey(const Key('inventorinator-logo')));
      for (final element in find.byType(ServiceStatusLed).evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(rect.left, greaterThan(logo.right));
        expect(rect.right, lessThanOrEqualTo(width));
      }
      expect(
        find.byTooltip('DigiKey: Last connection succeeded'),
        findsOneWidget,
      );
      store.save(const DigiKeyCredentials(), pending: false);
      ServiceStatus.refresh();
      await tester.pumpAndSettle();
      expect(find.byType(ServiceStatusLed), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      db.close();
      dir.deleteSync(recursive: true);
    });
  }
}
