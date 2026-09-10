import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/cloud_sync_dialog.dart';
import 'package:inventorinator/mouser_settings.dart';
import 'package:inventorinator/mouser_credentials.dart';
import 'package:inventorinator/local_database.dart';

void main() {
  setUp(MouserSettings.clear);
  tearDown(MouserSettings.clear);
  testWidgets(
    'Mouser appears below Supabase in Remote Settings without a connection',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'remote-settings-test-',
      );
      final database = (await tester.runAsync(
        () => LocalDatabase.open(
          overridePath: '${directory.path}/inventory.sqlite3',
        ),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: CloudSyncDialog(
            database: database,
            localStateJson: '{}',
            onCloudState: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remote Settings'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('mouser-settings'))).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const Key('supabase-settings'))).dy,
        ),
      );
      final dynamic settings = tester.state(find.byType(CloudSyncDialog));
      settings.setState(() {
        settings.message = 'Connection fixture failed';
      });
      await tester.pumpAndSettle();
      expect(find.text('Connection fixture failed'), findsNothing);
      await tester.tap(find.text('Supabase Settings'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('supabase-settings')),
          matching: find.text('Connection fixture failed'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      database.close();
      directory.deleteSync(recursive: true);
    },
  );
  testWidgets(
    'Mouser settings apply for later search windows and can be cleared',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('mouser-settings-');
      final database = (await tester.runAsync(
        () => LocalDatabase.open(overridePath: '${directory.path}/db.sqlite3'),
      ))!;
      final store = MouserCredentialStore(database, 'local');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MouserSettingsPanel(
                store: store,
                syncRemote: () async => throw StateError('offline'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mouser'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('mouser-api-key')),
        'test-secret',
      );
      await tester.ensureVisible(
        find.byKey(const Key('apply-mouser-settings')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apply-mouser-settings')));
      await tester.pumpAndSettle();
      expect(MouserSettings.configured, isTrue);
      expect(store.read()!.credentials.apiKey, 'test-secret');
      expect(store.read()!.pending, isTrue);
      expect(
        find.text(
          'Saved locally. Remote update pending; retry when connected.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('mouser-api-key')))
            .obscureText,
        isTrue,
      );
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(MouserSettings.configured, isFalse);
      expect(tester.takeException(), isNull);
      expect(store.read()!.credentials.configured, isFalse);
      await tester.pumpWidget(const SizedBox());
      database.close();
      directory.deleteSync(recursive: true);
    },
  );
}
