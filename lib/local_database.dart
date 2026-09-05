import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'workshop_delta.dart';

class PendingWorkshopChange {
  const PendingWorkshopChange({
    required this.outboxId,
    required this.localRevision,
    required this.change,
  });

  final int outboxId;
  final int localRevision;
  final WorkshopEntityChange change;

  // Kept as a compatibility label for callers that only displayed the old
  // timestamp-based version value. Acknowledgements use localRevision.
  String get version => localRevision.toString();
}

class InventoryImageData {
  const InventoryImageData({this.imageBytes, this.labelImageBytes});

  final Uint8List? imageBytes;
  final Uint8List? labelImageBytes;
}

class LocalDatabaseAlreadyOpenException implements Exception {
  const LocalDatabaseAlreadyOpenException();

  @override
  String toString() => 'Inventorinator is already running.';
}

class LocalDatabase {
  LocalDatabase._(this.path, this._database, this._instanceLock);

  final String path;
  Database _database;
  final RandomAccessFile? _instanceLock;
  bool _closed = false;
  int _writeGeneration = 0;
  Future<void> _syncSessionTail = Future<void>.value();
  Future<void> _writeTail = Future<void>.value();
  final Map<String, WorkshopEntityChange> _queuedWrites = {};

  Future<T> withSyncSessionLock<T>(Future<T> Function() action) async {
    final previous = _syncSessionTail;
    final release = Completer<void>();
    _syncSessionTail = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  /// Queues changed records outside the current UI callback and coalesces
  /// rapid edits to the same record before committing them to SQLite.
  ///
  /// The existing synchronous methods remain available for import/migration
  /// code and tests. Interactive edits use this queue so a burst of changes
  /// does not perform one SQLite transaction per tap or keystroke.
  Future<void> queueWorkshopChanges(
    Iterable<WorkshopEntityChange> changes,
  ) {
    if (_closed) return Future<void>.value();
    for (final change in changes) {
      final key = '${change.entityType}\u0000${change.entityId}';
      final previous = _queuedWrites[key];
      if (previous == null || change.deleted) {
        _queuedWrites[key] = change;
      } else {
        _queuedWrites[key] = WorkshopEntityChange(
          entityType: change.entityType,
          entityId: change.entityId,
          fields: {...previous.fields, ...change.fields},
        );
      }
    }
    if (_queuedWrites.isEmpty) return _writeTail;
    final generation = _writeGeneration;
    _writeTail = _writeTail.catchError((_) {}).then((_) async {
      if (_closed || generation != _writeGeneration) return;
      final batch = _queuedWrites.values.toList();
      _queuedWrites.clear();
      applyAndQueueWorkshopChanges(batch);
    });
    return _writeTail;
  }

  /// Computes a payload diff without writing synchronously, then sends only
  /// the changed fields through the deferred outbox queue.
  Future<void> queueEntityPayloadChange(
    String entityType,
    String entityId,
    Map<String, dynamic> payload,
  ) {
    if (_closed) return Future<void>.value();
    final rows = _database.select(
      '''SELECT payload_json FROM entity_state
         WHERE entity_type = ? AND entity_id = ?''',
      [entityType, entityId],
    );
    final previous = rows.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(
            jsonDecode(rows.first['payload_json'] as String) as Map,
          );
    final fields = rows.isEmpty
        ? payload
        : changedWorkshopEntityFields(previous, payload);
    if (fields.isEmpty) return Future<void>.value();
    return queueWorkshopChanges([
      WorkshopEntityChange(
        entityType: entityType,
        entityId: entityId,
        fields: fields,
      ),
    ]);
  }

  Future<void> waitForPendingWrites() => _writeTail;

  bool get isClosed => _closed;

  static Future<LocalDatabase> open({String? overridePath}) async {
    final databasePath =
        overridePath ??
        path_util.join(
          (await getApplicationSupportDirectory()).path,
          'inventorinator.sqlite3',
        );
    await Directory(path_util.dirname(databasePath)).create(recursive: true);
    RandomAccessFile? instanceLock;
    if (overridePath == null &&
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      instanceLock = File('$databasePath.lock').openSync(mode: FileMode.append);
      try {
        instanceLock.lockSync(FileLock.exclusive);
      } on FileSystemException {
        instanceLock.closeSync();
        throw const LocalDatabaseAlreadyOpenException();
      }
    }
    final database = sqlite3.open(databasePath);
    final result = LocalDatabase._(databasePath, database, instanceLock);
    result._createSchema();
    result._seedEntityStateFromSnapshot();
    result._migrateInventoryImages();
    await _hardenLocalPermissions(databasePath);
    return result;
  }

  static Future<void> _hardenLocalPermissions(String databasePath) async {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    try {
      await Process.run('chmod', ['700', path_util.dirname(databasePath)]);
      if (await File(databasePath).exists()) {
        await Process.run('chmod', ['600', databasePath]);
      }
    } catch (_) {
      // SQLite remains usable on unusual POSIX systems without chmod.
    }
  }

  void _createSchema() {
    _database.execute('''
      CREATE TABLE IF NOT EXISTS app_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        state_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      ) STRICT
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS sync_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        config_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      ) STRICT
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS preferences (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      ) STRICT
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS api_cache (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      ) STRICT
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        fields_json TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        local_revision INTEGER NOT NULL DEFAULT 0,
        UNIQUE(entity_type, entity_id)
      ) STRICT
    ''');
    final outboxColumns = _database.select('PRAGMA table_info(sync_outbox)');
    if (!outboxColumns.any((row) => row['name'] == 'local_revision')) {
      _database.execute(
        'ALTER TABLE sync_outbox ADD COLUMN local_revision INTEGER NOT NULL DEFAULT 0',
      );
    }
    // Existing rows predate explicit local revisions. Their outbox id is
    // already monotonic, so it is a safe one-time seed for the new counter.
    _database.execute(
      'UPDATE sync_outbox SET local_revision = id WHERE local_revision = 0',
    );
    _database.execute('''
      CREATE TABLE IF NOT EXISTS sync_local_revisions (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        next_revision INTEGER NOT NULL
      ) STRICT
    ''');
    final maxRevision = _database
        .select('SELECT coalesce(max(local_revision), 0) AS value FROM sync_outbox')
        .first['value'] as int;
    _database.execute(
      '''INSERT INTO sync_local_revisions (id, next_revision) VALUES (1, ?)
         ON CONFLICT(id) DO NOTHING''',
      [maxRevision + 1],
    );
    _database.execute('''
      CREATE TABLE IF NOT EXISTS entity_state (
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        PRIMARY KEY(entity_type, entity_id)
      ) STRICT
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS sync_cursors (
        workspace_id TEXT PRIMARY KEY,
        revision INTEGER NOT NULL DEFAULT 0
      ) STRICT
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS inventory_images (
        entity_id TEXT PRIMARY KEY,
        image_bytes BLOB,
        label_image_bytes BLOB
      ) STRICT
    ''');
  }

  bool loadBoolPreference(String key, {required bool fallback}) {
    final rows = _database.select(
      'SELECT value FROM preferences WHERE key = ?',
      [key],
    );
    if (rows.isEmpty) return fallback;
    return rows.first['value'] == 'true';
  }

  String loadStringPreference(String key, {required String fallback}) {
    final rows = _database.select(
      'SELECT value FROM preferences WHERE key = ?',
      [key],
    );
    return rows.isEmpty ? fallback : rows.first['value'] as String;
  }

  void saveBoolPreference(String key, bool value) {
    _database.execute(
      '''
      INSERT INTO preferences (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      ''',
      [key, value.toString()],
    );
  }

  void saveStringPreference(String key, String value) {
    _database.execute(
      '''
      INSERT INTO preferences (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      ''',
      [key, value],
    );
  }

  String? loadApiCache(String key) {
    final rows = _database.select('SELECT value FROM api_cache WHERE key = ?', [
      key,
    ]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void saveApiCache(String key, String value) {
    _database.execute(
      '''
      INSERT INTO api_cache (key, value, updated_at) VALUES (?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        value = excluded.value,
        updated_at = excluded.updated_at
      ''',
      [key, value, DateTime.now().toUtc().toIso8601String()],
    );
  }

  String? loadSyncConfig() {
    final rows = _database.select(
      'SELECT config_json FROM sync_config WHERE id = 1',
    );
    return rows.isEmpty ? null : rows.first['config_json'] as String;
  }

  void saveSyncConfig(String configJson) {
    _database.execute(
      '''
      INSERT INTO sync_config (id, config_json, updated_at)
      VALUES (1, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        config_json = excluded.config_json,
        updated_at = excluded.updated_at
      ''',
      [configJson, DateTime.now().toUtc().toIso8601String()],
    );
  }

  String? loadWorkspaceRecoveryKey(String workspaceId) {
    final value = loadStringPreference(
      'workspace_recovery_key_$workspaceId',
      fallback: '',
    ).trim();
    return value.isEmpty ? null : value;
  }

  void saveWorkspaceRecoveryKey(String workspaceId, String recoveryKey) {
    if (workspaceId.trim().isEmpty || recoveryKey.trim().isEmpty) return;
    saveStringPreference(
      'workspace_recovery_key_${workspaceId.trim()}',
      recoveryKey.trim(),
    );
  }

  String? loadState({bool includeFullImages = true}) {
    final entities = _database.select(
      'SELECT entity_type, entity_id, payload_json FROM entity_state',
    );
    if (entities.isNotEmpty) {
      var state = jsonEncode({
        for (final type in workshopEntityCollections) type: <Object?>[],
      });
      final changes = entities.map((row) {
        final entityType = row['entity_type'] as String;
        final entityId = row['entity_id'] as String;
        final fields = Map<String, dynamic>.from(
          jsonDecode(row['payload_json'] as String) as Map,
        );
        if (includeFullImages && entityType == 'inventory') {
          final images = loadInventoryImages(entityId);
          fields['image'] = images.imageBytes == null
              ? null
              : base64Encode(images.imageBytes!);
          fields['labelImage'] = images.labelImageBytes == null
              ? null
              : base64Encode(images.labelImageBytes!);
        }
        return WorkshopEntityChange(
          entityType: entityType,
          entityId: entityId,
          fields: fields,
        );
      });
      state = applyWorkshopEntityChanges(state, changes);
      return state;
    }
    final rows = _database.select(
      'SELECT state_json FROM app_state WHERE id = 1',
    );
    return rows.isEmpty ? null : rows.first['state_json'] as String;
  }

  InventoryImageData loadInventoryImages(String entityId) {
    final rows = _database.select(
      '''SELECT image_bytes, label_image_bytes FROM inventory_images
         WHERE entity_id = ?''',
      [entityId],
    );
    if (rows.isEmpty) return const InventoryImageData();
    return InventoryImageData(
      imageBytes: rows.first['image_bytes'] as Uint8List?,
      labelImageBytes: rows.first['label_image_bytes'] as Uint8List?,
    );
  }

  Set<String> inventoryIdsWithFullImages() => _database
      .select('''SELECT entity_id FROM inventory_images
           WHERE image_bytes IS NOT NULL''')
      .map((row) => row['entity_id'] as String)
      .toSet();

  Future<Uint8List> exportPortableDatabase() async {
    final exportPath = '$path.export-${DateTime.now().microsecondsSinceEpoch}';
    final exported = sqlite3.open(exportPath);
    await _hardenLocalPermissions(exportPath);
    try {
      exported.execute('''
        CREATE TABLE app_state (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          state_json TEXT NOT NULL,
          updated_at TEXT NOT NULL
        ) STRICT
      ''');
      final state = loadState();
      if (state != null) {
        exported.execute('INSERT INTO app_state VALUES (1, ?, ?)', [
          state,
          DateTime.now().toUtc().toIso8601String(),
        ]);
      }
      exported.execute('PRAGMA optimize');
    } finally {
      exported.close();
    }
    final file = File(exportPath);
    try {
      return await file.readAsBytes();
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  Future<String> importPortableDatabase(Uint8List bytes) async {
    final importPath = '$path.import-${DateTime.now().microsecondsSinceEpoch}';
    final file = File(importPath);
    await file.writeAsBytes(bytes, flush: true);
    await _hardenLocalPermissions(importPath);
    Database? imported;
    try {
      imported = sqlite3.open(importPath, mode: OpenMode.readOnly);
      final integrity = imported
          .select('PRAGMA integrity_check')
          .first
          .values
          .first;
      if (integrity != 'ok') {
        throw const FormatException('SQLite integrity check failed.');
      }
      final rows = imported.select(
        'SELECT state_json FROM app_state WHERE id = 1',
      );
      if (rows.isEmpty) {
        throw const FormatException(
          'This database contains no Inventorinator inventory.',
        );
      }
      final state = rows.first['state_json'] as String;
      final root = jsonDecode(state);
      if (root is! Map<String, dynamic> ||
          !root.containsKey('inventory') ||
          !root.containsKey('vendors') ||
          !root.containsKey('brands') ||
          !root.containsKey('products')) {
        throw const FormatException(
          'This is not a compatible Inventorinator database.',
        );
      }
      saveState(state);
      return state;
    } finally {
      imported?.close();
      if (await file.exists()) await file.delete();
    }
  }

  void saveState(String stateJson) {
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        '''
        INSERT INTO app_state (id, state_json, updated_at)
        VALUES (1, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          state_json = excluded.state_json,
          updated_at = excluded.updated_at
        ''',
        [stateJson, DateTime.now().toUtc().toIso8601String()],
      );
      _replaceEntityState(stateJson);
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  void saveStateAndQueueChanges(
    String stateJson,
    Iterable<WorkshopEntityChange> changes,
  ) {
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute('BEGIN IMMEDIATE');
    try {
      for (final change in changes) {
        final localRevision = _nextLocalRevision();
        _applyEntityStateChange(change);
        final existing = _database.select(
          '''
          SELECT fields_json, deleted FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ?
          ''',
          [change.entityType, change.entityId],
        );
        var fields = <String, dynamic>{};
        if (existing.isNotEmpty && existing.first['deleted'] != 1) {
          fields = Map<String, dynamic>.from(
            jsonDecode(existing.first['fields_json'] as String) as Map,
          );
        }
        if (change.deleted) {
          fields.clear();
        } else {
          fields.addAll(change.fields);
        }
        _database.execute(
          '''
          INSERT INTO sync_outbox (
            entity_type, entity_id, fields_json, deleted, created_at,
            local_revision
          ) VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(entity_type, entity_id) DO UPDATE SET
            fields_json = excluded.fields_json,
            deleted = excluded.deleted,
            created_at = excluded.created_at,
            local_revision = excluded.local_revision
          ''',
          [
            change.entityType,
            change.entityId,
            jsonEncode(fields),
            change.deleted ? 1 : 0,
            now,
            localRevision,
          ],
        );
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  void applyAndQueueWorkshopChanges(Iterable<WorkshopEntityChange> changes) {
    final pending = changes.toList();
    if (pending.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute('BEGIN IMMEDIATE');
    try {
      for (final change in pending) {
        final localRevision = _nextLocalRevision();
        _applyEntityStateChange(change);
        final existing = _database.select(
          '''SELECT fields_json, deleted FROM sync_outbox
             WHERE entity_type = ? AND entity_id = ?''',
          [change.entityType, change.entityId],
        );
        var fields = <String, dynamic>{};
        if (existing.isNotEmpty && existing.first['deleted'] != 1) {
          fields = Map<String, dynamic>.from(
            jsonDecode(existing.first['fields_json'] as String) as Map,
          );
        }
        if (change.deleted) {
          fields.clear();
        } else {
          fields.addAll(change.fields);
        }
        _database.execute(
          '''
          INSERT INTO sync_outbox(
            entity_type, entity_id, fields_json, deleted, created_at,
            local_revision
          )
          VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(entity_type, entity_id) DO UPDATE SET
            fields_json = excluded.fields_json,
            deleted = excluded.deleted,
            created_at = excluded.created_at,
            local_revision = excluded.local_revision
          ''',
          [
            change.entityType,
            change.entityId,
            jsonEncode(fields),
            change.deleted ? 1 : 0,
            now,
            localRevision,
          ],
        );
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  void saveEntityPayloadAndQueue(
    String entityType,
    String entityId,
    Map<String, dynamic> payload,
  ) {
    final rows = _database.select(
      '''SELECT payload_json FROM entity_state
         WHERE entity_type = ? AND entity_id = ?''',
      [entityType, entityId],
    );
    final previous = rows.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(
            jsonDecode(rows.first['payload_json'] as String) as Map,
          );
    final fields = rows.isEmpty
        ? payload
        : changedWorkshopEntityFields(previous, payload);
    if (fields.isEmpty) return;
    applyAndQueueWorkshopChanges([
      WorkshopEntityChange(
        entityType: entityType,
        entityId: entityId,
        fields: fields,
      ),
    ]);
  }

  void deleteEntityAndQueue(String entityType, String entityId) {
    applyAndQueueWorkshopChanges([
      WorkshopEntityChange(
        entityType: entityType,
        entityId: entityId,
        fields: const {},
        deleted: true,
      ),
    ]);
  }

  void applyRemoteWorkshopChanges(Iterable<WorkshopEntityChange> changes) {
    _database.execute('BEGIN IMMEDIATE');
    try {
      for (final change in changes) {
        _applyEntityStateChange(change);
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  void queueAllEntitiesForSync() {
    final rows = _database.select(
      'SELECT entity_type, entity_id, payload_json FROM entity_state',
    );
    applyAndQueueWorkshopChanges(
      rows.map(
        (row) => WorkshopEntityChange(
          entityType: row['entity_type'] as String,
          entityId: row['entity_id'] as String,
          fields: Map<String, dynamic>.from(
            jsonDecode(row['payload_json'] as String) as Map,
          ),
        ),
      ),
    );
  }

  List<WorkshopEntityChange> replaceWithRemoteEntities(
    Iterable<WorkshopEntityChange> remoteChanges,
  ) {
    final remote = remoteChanges.where((change) => !change.deleted).toList();
    final removals = _database
        .select('SELECT entity_type, entity_id FROM entity_state')
        .map(
          (row) => WorkshopEntityChange(
            entityType: row['entity_type'] as String,
            entityId: row['entity_id'] as String,
            fields: const {},
            deleted: true,
          ),
        )
        .toList();
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute('DELETE FROM entity_state');
      _database.execute('DELETE FROM inventory_images');
      _database.execute('DELETE FROM sync_outbox');
      for (final change in remote) {
        _applyEntityStateChange(change);
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
    return [...removals, ...remote];
  }

  void _seedEntityStateFromSnapshot() {
    final count =
        _database
                .select('SELECT count(*) AS count FROM entity_state')
                .first['count']
            as int;
    if (count != 0) return;
    final rows = _database.select(
      'SELECT state_json FROM app_state WHERE id = 1',
    );
    if (rows.isEmpty) return;
    _replaceEntityState(rows.first['state_json'] as String);
  }

  void _replaceEntityState(String stateJson) {
    _database.execute('DELETE FROM entity_state');
    _database.execute('DELETE FROM inventory_images');
    for (final change in diffWorkshopStates(null, stateJson)) {
      _applyEntityStateChange(change);
    }
  }

  void _applyEntityStateChange(WorkshopEntityChange change) {
    if (change.deleted) {
      _database.execute(
        'DELETE FROM entity_state WHERE entity_type = ? AND entity_id = ?',
        [change.entityType, change.entityId],
      );
      if (change.entityType == 'inventory') {
        _database.execute('DELETE FROM inventory_images WHERE entity_id = ?', [
          change.entityId,
        ]);
      }
      return;
    }
    final rows = _database.select(
      '''SELECT payload_json FROM entity_state
         WHERE entity_type = ? AND entity_id = ?''',
      [change.entityType, change.entityId],
    );
    final payload = rows.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(
            jsonDecode(rows.first['payload_json'] as String) as Map,
          );
    if (change.entityType == 'inventory') {
      _storeInventoryImageFields(change.entityId, change.fields);
      payload
        ..remove('image')
        ..remove('labelImage');
    }
    for (final entry in change.fields.entries.where(
      (entry) =>
          change.entityType != 'inventory' ||
          (entry.key != 'image' && entry.key != 'labelImage'),
    )) {
      if (entry.value == null) {
        payload.remove(entry.key);
      } else {
        payload[entry.key] = entry.value;
      }
    }
    if (change.entityType != workshopMetadataEntityType) {
      payload['id'] = change.entityId;
    }
    _database.execute(
      '''
      INSERT INTO entity_state(entity_type, entity_id, payload_json)
      VALUES (?, ?, ?)
      ON CONFLICT(entity_type, entity_id) DO UPDATE SET
        payload_json = excluded.payload_json
      ''',
      [change.entityType, change.entityId, jsonEncode(payload)],
    );
  }

  void _storeInventoryImageFields(
    String entityId,
    Map<String, dynamic> fields,
  ) {
    if (!fields.containsKey('image') && !fields.containsKey('labelImage')) {
      return;
    }
    final current = loadInventoryImages(entityId);
    Uint8List? decode(Object? value) =>
        value is String && value.isNotEmpty ? base64Decode(value) : null;
    final image = fields.containsKey('image')
        ? decode(fields['image'])
        : current.imageBytes;
    final label = fields.containsKey('labelImage')
        ? decode(fields['labelImage'])
        : current.labelImageBytes;
    if (image == null && label == null) {
      _database.execute('DELETE FROM inventory_images WHERE entity_id = ?', [
        entityId,
      ]);
      return;
    }
    _database.execute(
      '''INSERT INTO inventory_images(entity_id, image_bytes, label_image_bytes)
         VALUES (?, ?, ?)
         ON CONFLICT(entity_id) DO UPDATE SET
           image_bytes = excluded.image_bytes,
           label_image_bytes = excluded.label_image_bytes''',
      [entityId, image, label],
    );
  }

  void _migrateInventoryImages() {
    final rows = _database.select(
      '''SELECT entity_id, payload_json FROM entity_state
         WHERE entity_type = 'inventory' ''',
    );
    for (final row in rows) {
      final payload = Map<String, dynamic>.from(
        jsonDecode(row['payload_json'] as String) as Map,
      );
      if (!payload.containsKey('image') && !payload.containsKey('labelImage')) {
        continue;
      }
      final entityId = row['entity_id'] as String;
      _storeInventoryImageFields(entityId, payload);
      payload
        ..remove('image')
        ..remove('labelImage');
      _database.execute(
        '''UPDATE entity_state SET payload_json = ?
           WHERE entity_type = 'inventory' AND entity_id = ?''',
        [jsonEncode(payload), entityId],
      );
    }
  }

  List<PendingWorkshopChange> loadPendingWorkshopChanges() => _database
      .select('SELECT * FROM sync_outbox ORDER BY id')
      .map(
        (row) => PendingWorkshopChange(
          outboxId: row['id'] as int,
          localRevision: row['local_revision'] as int,
          change: WorkshopEntityChange(
            entityType: row['entity_type'] as String,
            entityId: row['entity_id'] as String,
            fields: Map<String, dynamic>.from(
              jsonDecode(row['fields_json'] as String) as Map,
            ),
            deleted: row['deleted'] == 1,
          ),
        ),
      )
      .toList();

  void acknowledgePendingWorkshopChanges(
    Iterable<PendingWorkshopChange> changes,
  ) {
    final statement = _database.prepare(
      'DELETE FROM sync_outbox WHERE id = ? AND local_revision = ?',
    );
    try {
      for (final pending in changes) {
        statement.execute([pending.outboxId, pending.localRevision]);
      }
    } finally {
      statement.close();
    }
  }

  int _nextLocalRevision() {
    final rows = _database.select(
      'SELECT next_revision FROM sync_local_revisions WHERE id = 1',
    );
    if (rows.isEmpty) {
      _database.execute(
        'INSERT INTO sync_local_revisions (id, next_revision) VALUES (1, 2)',
      );
      return 1;
    }
    final revision = rows.first['next_revision'] as int;
    _database.execute(
      'UPDATE sync_local_revisions SET next_revision = ? WHERE id = 1',
      [revision + 1],
    );
    return revision;
  }

  int loadSyncCursor(String workspaceId) {
    final rows = _database.select(
      'SELECT revision FROM sync_cursors WHERE workspace_id = ?',
      [workspaceId],
    );
    return rows.isEmpty ? 0 : rows.first['revision'] as int;
  }

  void saveSyncCursor(String workspaceId, int revision) {
    _database.execute(
      '''
      INSERT INTO sync_cursors (workspace_id, revision) VALUES (?, ?)
      ON CONFLICT(workspace_id) DO UPDATE SET revision = excluded.revision
      ''',
      [workspaceId, revision],
    );
  }

  Future<void> deleteAndRecreate() async {
    _database.close();
    _closed = true;
    _writeGeneration++;
    _queuedWrites.clear();
    for (final suffix in const ['', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
    _database = sqlite3.open(path);
    _closed = false;
    _createSchema();
    await _hardenLocalPermissions(path);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _writeGeneration++;
    _queuedWrites.clear();
    _database.close();
    _instanceLock?.closeSync();
  }
}
