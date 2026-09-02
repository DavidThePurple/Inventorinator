import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/workshop_delta.dart';

void main() {
  test('POSIX database and support directory are private', () async {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    final parent = await Directory.systemTemp.createTemp(
      'inventorinator-private-db-',
    );
    addTearDown(() => parent.delete(recursive: true));
    final support = Directory('${parent.path}/support');
    final path = '${support.path}/inventory.sqlite3';

    final database = await LocalDatabase.open(overridePath: path);
    expect((await support.stat()).mode & 0x1ff, 0x1c0); // 0700
    expect((await File(path).stat()).mode & 0x1ff, 0x180); // 0600
    database.close();
  });

  test('SQLite state survives close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'inventorinator-db-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/inventory.sqlite3';
    final database = await LocalDatabase.open(overridePath: path);
    database.saveState('{"inventory":["persistent"]}');
    database.close();

    final reopened = await LocalDatabase.open(overridePath: path);
    expect(reopened.loadState(), '{"inventory":["persistent"]}');
    reopened.close();
  });

  test('delete removes stored state and recreates an empty database', () async {
    final directory = await Directory.systemTemp.createTemp(
      'inventorinator-db-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = await LocalDatabase.open(
      overridePath: '${directory.path}/inventory.sqlite3',
    );
    database.saveState('{"inventory":["delete-me"]}');

    await database.deleteAndRecreate();

    expect(database.loadState(), isNull);
    database.saveState('{"inventory":[]}');
    expect(database.loadState(), '{"inventory":[]}');
    database.close();
  });

  test('sync configuration survives close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'inventorinator-sync-db-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/inventory.sqlite3';
    final database = await LocalDatabase.open(overridePath: path);
    database.saveSyncConfig('{"url":"https://inventory.example"}');
    database.close();

    final reopened = await LocalDatabase.open(overridePath: path);
    expect(reopened.loadSyncConfig(), '{"url":"https://inventory.example"}');
    reopened.close();
  });

  test('device preferences survive close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'inventorinator-preferences-db-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/inventory.sqlite3';
    final database = await LocalDatabase.open(overridePath: path);
    database.saveBoolPreference('sync_chime_enabled', false);
    database.saveStringPreference('device_name', 'Workshop desktop');
    database.close();

    final reopened = await LocalDatabase.open(overridePath: path);
    expect(
      reopened.loadBoolPreference('sync_chime_enabled', fallback: true),
      isFalse,
    );
    expect(
      reopened.loadStringPreference('device_name', fallback: 'Unknown'),
      'Workshop desktop',
    );
    reopened.close();
  });

  test('sync session operations are serialized per database', () async {
    final directory = await Directory.systemTemp.createTemp(
      'inventorinator-sync-lock-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = await LocalDatabase.open(
      overridePath: '${directory.path}/inventory.sqlite3',
    );
    final firstRelease = Completer<void>();
    final order = <String>[];

    final first = database.withSyncSessionLock(() async {
      order.add('first-start');
      await firstRelease.future;
      order.add('first-end');
    });
    final second = database.withSyncSessionLock(() async {
      order.add('second-start');
    });
    await Future<void>.delayed(Duration.zero);
    expect(order, ['first-start']);
    firstRelease.complete();
    await Future.wait([first, second]);
    expect(order, ['first-start', 'first-end', 'second-start']);
    database.close();
  });

  test('owner recovery credential survives close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'inventorinator-recovery-key-db-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/inventory.sqlite3';
    final database = await LocalDatabase.open(overridePath: path);
    database.saveWorkspaceRecoveryKey('workspace-1', 'RECOVERY-KEY');
    database.close();

    final reopened = await LocalDatabase.open(overridePath: path);
    expect(reopened.loadWorkspaceRecoveryKey('workspace-1'), 'RECOVERY-KEY');
    reopened.close();
  });

  test('API cache survives close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'inventorinator-api-cache-db-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/inventory.sqlite3';
    final database = await LocalDatabase.open(overridePath: path);
    database.saveApiCache('filamentcolors:test', '{"results":[]}');
    database.close();

    final reopened = await LocalDatabase.open(overridePath: path);
    expect(reopened.loadApiCache('filamentcolors:test'), '{"results":[]}');
    reopened.close();
  });

  test('entity updates persist and queue only changed fields', () async {
    final directory = await Directory.systemTemp.createTemp(
      'inventorinator-entity-db-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = await LocalDatabase.open(
      overridePath: '${directory.path}/inventory.sqlite3',
    );
    database.saveState(
      '{"schemaVersion":8,"inventory":[{"id":"A","name":"Bolt","quantity":2}],"vendors":[],"brands":[],"products":[]}',
    );

    database.saveEntityPayloadAndQueue('inventory', 'A', {
      'id': 'A',
      'name': 'Bolt',
      'quantity': 3,
    });

    final pending = database.loadPendingWorkshopChanges();
    expect(pending, hasLength(1));
    expect(pending.single.change.fields, {'quantity': 3});
    expect(database.loadState(), contains('"quantity":3'));
    database.acknowledgePendingWorkshopChanges(pending);
    expect(database.loadPendingWorkshopChanges(), isEmpty);
    database.close();
  });

  test(
    'full inventory images stay lazy while thumbnails load with cards',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'inventorinator-lazy-images-db-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final database = await LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      );
      final image = Uint8List.fromList([1, 2, 3, 4]);
      final label = Uint8List.fromList([5, 6, 7]);
      final thumbnail = Uint8List.fromList([8, 9]);
      database.saveState(
        jsonEncode({
          'schemaVersion': 8,
          'inventory': [
            {
              'id': 'IMAGE-A',
              'name': 'Filament',
              'image': base64Encode(image),
              'labelImage': base64Encode(label),
              'thumbnail': base64Encode(thumbnail),
            },
          ],
          'vendors': [],
          'brands': [],
          'products': [],
        }),
      );

      final lightweight = jsonDecode(
        database.loadState(includeFullImages: false)!,
      ) as Map<String, dynamic>;
      final lightweightItem = (lightweight['inventory'] as List).single as Map;
      expect(lightweightItem.containsKey('image'), isFalse);
      expect(lightweightItem.containsKey('labelImage'), isFalse);
      expect(lightweightItem['thumbnail'], base64Encode(thumbnail));

      final loaded = database.loadInventoryImages('IMAGE-A');
      expect(loaded.imageBytes, image);
      expect(loaded.labelImageBytes, label);
      final complete = database.loadState()!;
      expect(complete, contains(base64Encode(image)));
      database.close();
    },
  );

  test('remote entity updates do not enter the local outbox', () async {
    final directory = await Directory.systemTemp.createTemp(
      'inventorinator-remote-entity-db-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = await LocalDatabase.open(
      overridePath: '${directory.path}/inventory.sqlite3',
    );
    database.saveState(
      '{"schemaVersion":8,"inventory":[],"vendors":[],"brands":[],"products":[]}',
    );
    database.applyRemoteWorkshopChanges(const [
      WorkshopEntityChange(
        entityType: 'inventory',
        entityId: 'A',
        fields: {'id': 'A', 'name': 'Bolt', 'quantity': 2},
      ),
    ]);
    expect(database.loadState(), contains('"name":"Bolt"'));
    expect(database.loadPendingWorkshopChanges(), isEmpty);
    database.close();
  });

  test('acknowledging an upload never discards a newer queued edit', () async {
    final directory = await Directory.systemTemp.createTemp(
      'inventorinator-outbox-version-db-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = await LocalDatabase.open(
      overridePath: '${directory.path}/inventory.sqlite3',
    );
    database.saveState(
      '{"schemaVersion":8,"inventory":[{"id":"A","name":"Bolt","quantity":2}],"vendors":[],"brands":[],"products":[]}',
    );
    database.saveEntityPayloadAndQueue('inventory', 'A', {
      'id': 'A',
      'name': 'Bolt',
      'quantity': 3,
    });
    final uploading = database.loadPendingWorkshopChanges();

    await Future<void>.delayed(const Duration(milliseconds: 2));
    database.saveEntityPayloadAndQueue('inventory', 'A', {
      'id': 'A',
      'name': 'Bolt',
      'quantity': 4,
    });
    database.acknowledgePendingWorkshopChanges(uploading);

    final remaining = database.loadPendingWorkshopChanges();
    expect(remaining, hasLength(1));
    expect(remaining.single.change.fields['quantity'], 4);
    database.close();
  });

  test(
    'portable SQLite export imports inventory but preserves device sync',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'inventorinator-portable-db-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final source = await LocalDatabase.open(
        overridePath: '${directory.path}/source.sqlite3',
      );
      const state = '{"inventory":[],"vendors":[],"brands":[],"products":[]}';
      source.saveState(state);
      source.saveSyncConfig('{"workspaceId":"source"}');
      final bytes = await source.exportPortableDatabase();
      source.close();

      final destination = await LocalDatabase.open(
        overridePath: '${directory.path}/destination.sqlite3',
      );
      destination.saveSyncConfig('{"workspaceId":"destination"}');
      expect(await destination.importPortableDatabase(bytes), state);
      expect(destination.loadState(), state);
      expect(destination.loadSyncConfig(), '{"workspaceId":"destination"}');
      destination.close();
    },
  );

  test(
    'invalid SQLite import leaves the existing inventory untouched',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'inventorinator-invalid-db-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final database = await LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      );
      const state = '{"inventory":[],"vendors":[],"brands":[],"products":[]}';
      database.saveState(state);

      await expectLater(
        database.importPortableDatabase(Uint8List.fromList([1, 2, 3])),
        throwsA(anything),
      );
      expect(database.loadState(), state);
      database.close();
    },
  );
}
