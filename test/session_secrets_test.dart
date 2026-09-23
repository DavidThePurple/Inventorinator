import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/session_secrets.dart';
import 'package:inventorinator/supabase_sync.dart';

class _FakeVault implements SecretVault {
  final entries = <String, String>{};
  bool available = true;
  Completer<void>? gate;

  void _check() {
    if (!available) throw const SecretVaultUnavailable('keyring is locked');
  }

  @override
  Future<String?> read(String key) async {
    _check();
    return entries[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _check();
    await gate?.future;
    entries[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _check();
    entries.remove(key);
  }
}

SupabaseConfig _config({
  String access = 'access-token-AAAA',
  String refresh = 'refresh-token-BBBB',
  String? lastSynced,
}) => SupabaseConfig(
  url: 'https://sync.example.test',
  publishableKey: 'publishable-key',
  syncMode: 'supabase',
  userId: '20000000-0000-0000-0000-000000000001',
  workspaceId: '10000000-0000-0000-0000-000000000001',
  workspaceRole: 'owner',
  accessToken: access,
  accessTokenExpiresAt: DateTime.utc(2030),
  refreshToken: refresh,
  lastSyncedStateJson: lastSynced,
);

SupabaseConfig _other() => SupabaseConfig(
  url: 'https://sync.example.test',
  publishableKey: 'publishable-key',
  syncMode: 'supabase',
  userId: '20000000-0000-0000-0000-000000000002',
  workspaceId: '10000000-0000-0000-0000-000000000002',
  workspaceRole: 'admin',
  accessToken: 'other-access-CCCC',
  refreshToken: 'other-refresh-DDDD',
);

void main() {
  late Directory directory;
  late String path;
  late _FakeVault vault;
  final opened = <LocalDatabase>[];

  Future<LocalDatabase> open() async {
    final database = await LocalDatabase.open(
      overridePath: path,
      secretVault: vault,
    );
    opened.add(database);
    return database;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('inventorinator-vault-');
    path = '${directory.path}/inventory.sqlite3';
    vault = _FakeVault();
  });

  tearDown(() async {
    for (final database in opened) {
      database.close();
    }
    opened.clear();
    await directory.delete(recursive: true);
  });

  /// Everything SQLite holds for the current config and known workspaces,
  /// read through a separate connection so nothing is merged in.
  String rawStoredSession(LocalDatabase database) {
    database.close();
    final files = [path, '$path-wal']
        .map(File.new)
        .where((file) => file.existsSync())
        .map((file) => latin1.decode(file.readAsBytesSync()))
        .join();
    return files;
  }

  test('is off by default and stores tokens exactly as before', () async {
    final database = await open();
    database.saveSyncConfig(jsonEncode(_config().toJson()));

    expect(database.secureSessionStorageEnabled, isFalse);
    expect(database.loadSyncConfig(), contains('refresh-token-BBBB'));
    expect(vault.entries, isEmpty);
  });

  test('enabling moves tokens to the vault and out of the database', () async {
    final database = await open();
    database.saveSyncConfig(
      jsonEncode(_config(lastSynced: '{"inventory":[]}').toJson()),
    );
    database.saveStringPreference(
      LocalDatabase.knownWorkspacesPreference,
      jsonEncode([_other().toJson()]),
    );

    await database.enableSecureSessionStorage(vault: vault);

    expect(database.secureSessionStorageEnabled, isTrue);
    expect(vault.entries.length, 2);
    // The app still sees complete configs.
    final config = SupabaseConfig.fromJson(
      jsonDecode(database.loadSyncConfig()!) as Map<String, dynamic>,
    );
    expect(config.refreshToken, 'refresh-token-BBBB');
    expect(config.accessToken, 'access-token-AAAA');
    expect(config.lastSyncedStateJson, '{"inventory":[]}');
    final known = jsonDecode(
      database.loadStringPreference(
        LocalDatabase.knownWorkspacesPreference,
        fallback: '[]',
      ),
    ) as List<dynamic>;
    expect((known.single as Map)['refreshToken'], 'other-refresh-DDDD');

    // The database file itself no longer contains any token text.
    final raw = rawStoredSession(database);
    for (final secret in [
      'access-token-AAAA',
      'refresh-token-BBBB',
      'other-access-CCCC',
      'other-refresh-DDDD',
    ]) {
      expect(
        raw.contains(secret),
        isFalse,
        reason: 'database still holds $secret',
      );
    }
    expect(raw.contains('publishable-key'), isTrue);
  });

  test(
    'enabling leaves no token text in freed pages of a large config',
    () async {
      final database = await open();
      final snapshot = jsonEncode({
        'inventory': List.filled(4000, 'item-data'),
      });
      // Each save rewrites the multi-page row, leaving older copies on the
      // freelist unless the pages are overwritten.
      for (var i = 0; i < 4; i++) {
        database.saveSyncConfig(
          jsonEncode(_config(lastSynced: snapshot).toJson()),
        );
      }

      await database.enableSecureSessionStorage(vault: vault);

      final raw = rawStoredSession(database);
      expect(raw.contains('refresh-token-BBBB'), isFalse);
      expect(raw.contains('access-token-AAAA'), isFalse);
    },
  );

  test('saved config JSON carries no token keys while enabled', () async {
    final database = await open();
    await database.enableSecureSessionStorage(vault: vault);
    database.saveSyncConfig(jsonEncode(_config().toJson()));
    database.saveStringPreference(
      LocalDatabase.knownWorkspacesPreference,
      jsonEncode([_other().toJson()]),
    );
    await database.waitForPendingWrites();
    database.close();

    final raw =
        latin1.decode(File(path).readAsBytesSync()) +
        (File('$path-wal').existsSync()
            ? latin1.decode(File('$path-wal').readAsBytesSync())
            : '');
    // accessTokenExpiresAt is not a secret and stays in the database, so look
    // for the exact key names.
    expect(raw.contains('"accessToken"'), isFalse);
    expect(raw.contains('"refreshToken"'), isFalse);
    expect(raw.contains('refresh-token-BBBB'), isFalse);
    expect(vault.entries.values.join(), contains('refresh-token-BBBB'));
  });

  test('tokens survive a restart from the vault', () async {
    var database = await open();
    await database.enableSecureSessionStorage(vault: vault);
    database.saveSyncConfig(jsonEncode(_config().toJson()));
    database.saveStringPreference(
      LocalDatabase.knownWorkspacesPreference,
      jsonEncode([_other().toJson()]),
    );
    await database.waitForPendingWrites();
    database.close();

    database = await open();
    expect(database.secureSessionStorageEnabled, isTrue);
    final config = SupabaseConfig.fromJson(
      jsonDecode(database.loadSyncConfig()!) as Map<String, dynamic>,
    );
    expect(config.hasSession, isTrue);
    expect(config.refreshToken, 'refresh-token-BBBB');
    final known = jsonDecode(
      database.loadStringPreference(
        LocalDatabase.knownWorkspacesPreference,
        fallback: '[]',
      ),
    ) as List<dynamic>;
    expect((known.single as Map)['refreshToken'], 'other-refresh-DDDD');
  });

  test('a refreshed token replaces the stored one', () async {
    final database = await open();
    database.saveSyncConfig(jsonEncode(_config().toJson()));
    await database.enableSecureSessionStorage(vault: vault);

    database.saveSyncConfig(
      jsonEncode(_config(refresh: 'refresh-token-NEW1').toJson()),
    );
    await database.waitForPendingWrites();

    expect(vault.entries.values.join(), contains('refresh-token-NEW1'));
    expect(vault.entries.values.join(), isNot(contains('refresh-token-BBBB')));
    expect(database.loadSyncConfig(), contains('refresh-token-NEW1'));
  });

  test('unchanged tokens do not rewrite the keyring', () async {
    final database = await open();
    database.saveSyncConfig(jsonEncode(_config().toJson()));
    await database.enableSecureSessionStorage(vault: vault);
    vault.entries.clear();

    database.saveSyncConfig(
      jsonEncode(_config(lastSynced: '{"changed":true}').toJson()),
    );
    await database.waitForPendingWrites();

    expect(vault.entries, isEmpty);
  });

  test('a token refresh during the move is not lost', () async {
    final database = await open();
    database.saveSyncConfig(jsonEncode(_config().toJson()));
    vault.gate = Completer<void>();

    final enabling = database.enableSecureSessionStorage(vault: vault);
    await Future<void>.delayed(Duration.zero);
    database.saveSyncConfig(
      jsonEncode(_config(refresh: 'refresh-token-NEW2').toJson()),
    );
    vault.gate!.complete();
    await enabling;

    expect(vault.entries.values.join(), contains('refresh-token-NEW2'));
    expect(database.loadSyncConfig(), contains('refresh-token-NEW2'));
    expect(rawStoredSession(database).contains('refresh-token-NEW2'), isFalse);
  });

  test('a keyring that cannot store leaves everything unchanged', () async {
    final database = await open();
    database.saveSyncConfig(jsonEncode(_config().toJson()));
    vault.available = false;

    await expectLater(
      database.enableSecureSessionStorage(vault: vault),
      throwsA(isA<SecretVaultUnavailable>()),
    );

    expect(database.secureSessionStorageEnabled, isFalse);
    expect(database.loadSyncConfig(), contains('refresh-token-BBBB'));
    vault.available = true;
    database.close();
    final reopened = await open();
    expect(reopened.secureSessionStorageEnabled, isFalse);
    expect(reopened.loadSyncConfig(), contains('refresh-token-BBBB'));
  });

  test('disabling puts tokens back and clears the keyring', () async {
    final database = await open();
    database.saveSyncConfig(jsonEncode(_config().toJson()));
    database.saveStringPreference(
      LocalDatabase.knownWorkspacesPreference,
      jsonEncode([_other().toJson()]),
    );
    await database.enableSecureSessionStorage(vault: vault);

    final cleared = await database.disableSecureSessionStorage();

    expect(cleared, isTrue);
    expect(database.secureSessionStorageEnabled, isFalse);
    expect(vault.entries, isEmpty);
    database.close();
    final reopened = await open();
    expect(reopened.secureSessionStorageEnabled, isFalse);
    expect(reopened.loadSyncConfig(), contains('refresh-token-BBBB'));
    expect(
      reopened.loadStringPreference(
        LocalDatabase.knownWorkspacesPreference,
        fallback: '[]',
      ),
      contains('other-refresh-DDDD'),
    );
  });

  test('signing out removes the stored tokens', () async {
    final database = await open();
    database.saveSyncConfig(jsonEncode(_config().toJson()));
    await database.enableSecureSessionStorage(vault: vault);

    database.saveSyncConfig(
      jsonEncode(
        const SupabaseConfig(
          url: 'https://sync.example.test',
          publishableKey: 'k',
        ).toJson(),
      ),
    );
    await database.waitForPendingWrites();

    expect(vault.entries, isEmpty);
  });

  test('a workspace dropped from the list loses its stored tokens', () async {
    final database = await open();
    database.saveStringPreference(
      LocalDatabase.knownWorkspacesPreference,
      jsonEncode([_other().toJson()]),
    );
    await database.enableSecureSessionStorage(vault: vault);
    expect(vault.entries, hasLength(1));

    database.saveStringPreference(
      LocalDatabase.knownWorkspacesPreference,
      jsonEncode(<Object>[]),
    );
    await database.waitForPendingWrites();

    expect(vault.entries, isEmpty);
  });

  test('a locked keyring at startup means signed out, never a wipe', () async {
    var database = await open();
    database.saveSyncConfig(jsonEncode(_config().toJson()));
    await database.enableSecureSessionStorage(vault: vault);
    await database.waitForPendingWrites();
    database.close();

    vault.available = false;
    database = await open();
    expect(database.secureSessionStorageEnabled, isTrue);
    expect(database.secureSessionError, isNotNull);
    final config = SupabaseConfig.fromJson(
      jsonDecode(database.loadSyncConfig()!) as Map<String, dynamic>,
    );
    expect(config.hasSession, isFalse);
    expect(config.url, 'https://sync.example.test');

    // Routine saves while locked must not delete the entry that exists.
    database.saveSyncConfig(jsonEncode(config.toJson()));
    await database.waitForPendingWrites();
    vault.available = true;
    expect(vault.entries.values.join(), contains('refresh-token-BBBB'));

    database.close();
    final unlocked = await open();
    final restored = SupabaseConfig.fromJson(
      jsonDecode(unlocked.loadSyncConfig()!) as Map<String, dynamic>,
    );
    expect(restored.hasSession, isTrue);
    expect(unlocked.secureSessionError, isNull);
  });

  test('deleting local data also clears the keyring', () async {
    final database = await open();
    database.saveSyncConfig(jsonEncode(_config().toJson()));
    await database.enableSecureSessionStorage(vault: vault);
    expect(vault.entries, isNotEmpty);

    await database.deleteAndRecreate();

    expect(vault.entries, isEmpty);
    expect(database.secureSessionStorageEnabled, isFalse);
    expect(database.loadSyncConfig(), isNull);
  });

  test('portable exports never contain sync tokens', () async {
    final database = await open();
    database.saveState(
      '{"inventory":[],"vendors":[],"brands":[],"products":[]}',
    );
    database.saveSyncConfig(jsonEncode(_config().toJson()));

    final exported = latin1.decode(await database.exportPortableDatabase());

    expect(exported.contains('refresh-token-BBBB'), isFalse);
  });
}
