import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/cloud_sync_dialog.dart';
import 'package:inventorinator/digikey_settings.dart';
import 'package:inventorinator/digikey_credentials.dart';
import 'package:inventorinator/local_database.dart';

void main() {
  setUp(DigiKeySettings.clear);
  tearDown(DigiKeySettings.clear);
  testWidgets(
    'DigiKey appears below Supabase in Remote Settings without a connection',
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
        tester.getTopLeft(find.byKey(const Key('digikey-settings'))).dy,
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
    'DigiKey settings apply for later search windows and can be cleared',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'digikey-settings-',
      );
      final database = (await tester.runAsync(
        () => LocalDatabase.open(overridePath: '${directory.path}/db.sqlite3'),
      ))!;
      final store = DigiKeyCredentialStore(database, 'local');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DigiKeySettingsPanel(
                store: store,
                syncRemote: () async => throw StateError('offline'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('DigiKey'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('digikey-client-id')),
        'test-id',
      );
      await tester.enterText(
        find.byKey(const Key('digikey-client-secret')),
        'test-secret',
      );
      await tester.ensureVisible(
        find.byKey(const Key('apply-digikey-settings')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('apply-digikey-settings')));
      await tester.pumpAndSettle();
      expect(DigiKeySettings.configured, isTrue);
      expect(DigiKeySettings.clientId, 'test-id');
      expect(store.read()!.credentials.clientSecret, 'test-secret');
      expect(store.read()!.pending, isTrue);
      expect(
        find.text(
          'Saved locally. Remote update pending; retry when connected.',
        ),
        findsOneWidget,
      );
      expect(DigiKeySettings.sandbox, isFalse);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('digikey-client-secret')))
            .obscureText,
        isTrue,
      );
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(DigiKeySettings.configured, isFalse);
      expect(tester.takeException(), isNull);
      expect(store.read()!.credentials.configured, isFalse);
      await tester.pumpWidget(const SizedBox());
      database.close();
      directory.deleteSync(recursive: true);
    },
  );
}
