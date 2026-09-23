import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/cloud_sync_dialog.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/session_secrets.dart';
import 'package:inventorinator/supabase_sync.dart';

class _FakeVault implements SecretVault {
  final entries = <String, String>{};
  bool available = true;

  @override
  Future<String?> read(String key) async {
    if (!available) throw const SecretVaultUnavailable('keyring is locked');
    return entries[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (!available) throw const SecretVaultUnavailable('keyring is locked');
    entries[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (!available) throw const SecretVaultUnavailable('keyring is locked');
    entries.remove(key);
  }
}

void main() {
  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('supabase-settings')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('secure-session-storage')));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('secure sign-in storage is off, optional, and warns first', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-secure-dialog-',
    );
    final vault = _FakeVault();
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
        secretVault: vault,
      ),
    ))!;
    const remembered = SupabaseConfig(
      syncMode: 'supabase',
      url: 'https://supabase.example.test',
      publishableKey: 'publishable-key',
      userId: '20000000-0000-0000-0000-000000000001',
      workspaceId: '10000000-0000-0000-0000-000000000001',
      workspaceRole: 'owner',
      refreshToken: 'remembered-refresh-token',
    );
    database.saveSyncConfig(
      jsonEncode(
        const SupabaseConfig(
          url: 'https://supabase.example.test',
          publishableKey: 'publishable-key',
        ).toJson(),
      ),
    );
    database.saveStringPreference(
      LocalDatabase.knownWorkspacesPreference,
      jsonEncode([remembered.toJson()]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CloudSyncDialog(
          database: database,
          localStateJson: '{}',
          onCloudState: (_) {},
        ),
      ),
    );
    await tester.pump();
    await openSettings(tester);

    Switch toggle() => tester.widget<Switch>(
      find.descendant(
        of: find.byKey(const Key('secure-session-storage')),
        matching: find.byType(Switch),
      ),
    );
    expect(find.textContaining('experimental'), findsOneWidget);
    expect(toggle().value, isFalse);

    // Cancelling the warning changes nothing.
    await tester.tap(find.byKey(const Key('secure-session-storage')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('secure-session-warning')), findsOneWidget);
    expect(find.textContaining('This feature is experimental'), findsOneWidget);
    expect(find.textContaining('cannot recover the sign-in'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(database.secureSessionStorageEnabled, isFalse);
    expect(vault.entries, isEmpty);

    // Confirming turns it on and moves the tokens.
    await tester.tap(find.byKey(const Key('secure-session-storage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('secure-session-confirm')));
    await settle(tester);
    expect(database.secureSessionStorageEnabled, isTrue);
    expect(vault.entries.values.join(), contains('remembered-refresh-token'));
    expect(toggle().value, isTrue);
    expect(
      find.text('The sign-in is now stored in the system keyring.'),
      findsOneWidget,
    );

    // Turning it off needs no warning and restores the database copy.
    await tester.tap(find.byKey(const Key('secure-session-storage')));
    await settle(tester);
    expect(find.byKey(const Key('secure-session-warning')), findsNothing);
    expect(database.secureSessionStorageEnabled, isFalse);
    expect(vault.entries, isEmpty);
    expect(toggle().value, isFalse);

    await tester.pumpWidget(const SizedBox());
    database.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets('an unavailable keyring keeps the feature off and says why', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-secure-dialog-',
    );
    final vault = _FakeVault()..available = false;
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
        secretVault: vault,
      ),
    ))!;
    database.saveSyncConfig(
      jsonEncode(
        const SupabaseConfig(
          url: 'https://supabase.example.test',
          publishableKey: 'publishable-key',
        ).toJson(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CloudSyncDialog(
          database: database,
          localStateJson: '{}',
          onCloudState: (_) {},
        ),
      ),
    );
    await tester.pump();
    await openSettings(tester);

    await tester.tap(find.byKey(const Key('secure-session-storage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('secure-session-confirm')));
    await settle(tester);

    expect(database.secureSessionStorageEnabled, isFalse);
    expect(
      find.textContaining('Secure storage was not turned on'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    database.close();
    directory.deleteSync(recursive: true);
  });
}
