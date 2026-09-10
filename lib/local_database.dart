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
  Future<void> queueWorkshopChanges(Iterable<WorkshopEntityChange> changes) {
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
    final normalization = RegExp(r'[^a-z0-9]');
    _database.createFunction(
      functionName: 'inventory_normalize',
      argumentCount: const AllowedArgumentCount(1),
      deterministic: true,
      function: (args) => (args.single as String? ?? '')
          .toLowerCase()
          .replaceAll(normalization, ''),
    );
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
    if (!outboxColumns.any((row) => row['name'] == 'base_json')) {
      _database.execute("ALTER TABLE sync_outbox ADD COLUMN base_json TEXT NOT NULL DEFAULT '{}'");
    }
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
    final maxRevision =
        _database
                .select(
                  'SELECT coalesce(max(local_revision), 0) AS value FROM sync_outbox',
                )
                .first['value']
            as int;
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
    _database.execute(
      "CREATE TABLE IF NOT EXISTS inventory_metadata (entity_type TEXT NOT NULL DEFAULT 'inventory', entity_id TEXT PRIMARY KEY, payload_json TEXT NOT NULL)",
    );
    _database.execute(
      r"""CREATE TRIGGER IF NOT EXISTS inventory_metadata_insert AFTER INSERT ON entity_state
      WHEN new.entity_type = 'inventory' BEGIN
      INSERT INTO inventory_metadata(entity_id, payload_json)
      VALUES(new.entity_id, json_remove(new.payload_json, '$.thumbnail', '$.image', '$.labelImage')) ON CONFLICT(entity_id) DO UPDATE SET payload_json = excluded.payload_json; END""",
    );
    _database.execute(
      r"""CREATE TRIGGER IF NOT EXISTS inventory_metadata_update AFTER UPDATE ON entity_state
      WHEN new.entity_type = 'inventory' BEGIN
      INSERT INTO inventory_metadata(entity_id, payload_json)
      VALUES(new.entity_id, json_remove(new.payload_json, '$.thumbnail', '$.image', '$.labelImage')) ON CONFLICT(entity_id) DO UPDATE SET payload_json = excluded.payload_json; END""",
    );
    _database.execute(
      "CREATE TRIGGER IF NOT EXISTS inventory_metadata_delete AFTER DELETE ON entity_state WHEN old.entity_type = 'inventory' BEGIN DELETE FROM inventory_metadata WHERE entity_id = old.entity_id; END",
    );
    _database.execute(
      r"""INSERT OR IGNORE INTO inventory_metadata(entity_id, payload_json)
      SELECT entity_id, json_remove(payload_json, '$.thumbnail', '$.image', '$.labelImage') FROM entity_state WHERE entity_type = 'inventory'""",
    );
    _database.execute(
      r"""CREATE INDEX IF NOT EXISTS inventory_metadata_added ON inventory_metadata(
      coalesce(json_extract(payload_json, '$.archived'), 0), julianday(json_extract(payload_json, '$.added')), entity_id)""",
    );
    _database.execute(
      r"""CREATE INDEX IF NOT EXISTS inventory_metadata_quantity ON inventory_metadata(
      coalesce(json_extract(payload_json, '$.archived'), 0), coalesce(json_extract(payload_json, '$.quantity'), 1), entity_id)""",
    );
    _database.execute(
      r"""CREATE INDEX IF NOT EXISTS inventory_page_added ON entity_state(
      coalesce(json_extract(payload_json, '$.archived'), 0),
      julianday(json_extract(payload_json, '$.added')), entity_id)
      WHERE entity_type = 'inventory'""",
    );
    _database.execute(
      r"""CREATE INDEX IF NOT EXISTS inventory_page_quantity ON entity_state(
      coalesce(json_extract(payload_json, '$.archived'), 0),
      coalesce(json_extract(payload_json, '$.quantity'), 1), entity_id)
      WHERE entity_type = 'inventory'""",
    );
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

  void saveStringPreferences(Map<String, String> values) {
    _database.execute('BEGIN IMMEDIATE');
    try {
      for (final entry in values.entries) {
        saveStringPreference(entry.key, entry.value);
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
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

  String? loadState({
    bool includeFullImages = true,
    bool includeInventory = true,
  }) {
    final entities = _database.select(
      "SELECT entity_type, entity_id, payload_json FROM entity_state ${includeInventory ? '' : "WHERE entity_type != 'inventory'"}",
    );
    if (entities.isNotEmpty || !includeInventory && inventoryCount() > 0) {
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

  List<Map<String, Object?>> inventoryMetricGroups(Set<String> untracked) =>
      _database.select(
        r"""
        SELECT json_extract(payload_json, '$.type') AS type,
          trim(coalesce(json_extract(payload_json, '$.materialName'), '')) AS material,
          trim(coalesce(json_extract(payload_json, '$.brand'), '')) AS brand,
          trim(coalesce(nullif(json_extract(payload_json, '$.itemColorName'), ''), json_extract(payload_json, '$.itemColorLabel'), '')) AS color,
          trim(coalesce(json_extract(payload_json, '$.itemColorLabel'), '')) AS colorLabel,
          count(*) AS records,
          sum(coalesce(json_extract(payload_json, '$.quantity'), 1)) AS units,
          sum(CASE WHEN json_extract(payload_json, '$.quantityAlertThreshold') IS NOT NULL AND
            coalesce(json_extract(payload_json, '$.quantity'), 1) <= json_extract(payload_json, '$.quantityAlertThreshold') THEN 1 ELSE 0 END) AS lowStock
        FROM inventory_metadata WHERE entity_type = 'inventory'
          AND coalesce(json_extract(payload_json, '$.archived'), 0) = 0
          AND (CASE WHEN json_extract(payload_json, '$.type') = 'custom'
            THEN 'custom:' || json_extract(payload_json, '$.customTypeId')
            ELSE 'item:' || json_extract(payload_json, '$.type') END) NOT IN (SELECT value FROM json_each(?))
        GROUP BY type, material, brand, color, colorLabel
      """,
        [jsonEncode(untracked.toList())],
      );

  double availableInventoryQuantity(String productId, String name) =>
      (_database
                  .select(
                    r"""SELECT coalesce(sum(json_extract(payload_json, '$.quantity')), 0) AS value
        FROM inventory_metadata WHERE entity_type = 'inventory'
        AND coalesce(json_extract(payload_json, '$.archived'), 0) = 0
        AND json_extract(payload_json, '$.quantity') > 0
        AND (entity_id = ? OR json_extract(payload_json, '$.catalogProductId') = ?
          OR inventory_normalize(json_extract(payload_json, '$.name')) = inventory_normalize(?))""",
                    [productId, productId, name],
                  )
                  .first['value']
              as num)
          .toDouble();

  String inventoryStockKey(String productId, String name) {
    final rows = _database.select(
      r"""SELECT entity_id, json_extract(payload_json, '$.catalogProductId') AS product
      FROM inventory_metadata WHERE entity_type = 'inventory'
      AND (entity_id = ? OR json_extract(payload_json, '$.catalogProductId') = ?
        OR inventory_normalize(json_extract(payload_json, '$.name')) = inventory_normalize(?))
      ORDER BY CASE WHEN entity_id = ? OR json_extract(payload_json, '$.catalogProductId') = ? THEN 0 ELSE 1 END, rowid LIMIT 1""",
      [productId, productId, name, productId, productId],
    );
    if (rows.isEmpty) {
      return productId.isEmpty
          ? 'name:${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}'
          : 'product:$productId';
    }
    final product = rows.first['product'] as String?;
    return product?.isNotEmpty == true
        ? 'product:$product'
        : "inventory:${rows.first['entity_id']}";
  }

  int inventoryCount({
    String where = '1',
    List<Object?> parameters = const [],
  }) =>
      _database
              .select(
                "SELECT count(*) AS n FROM inventory_metadata WHERE entity_type = 'inventory' AND ($where)",
                parameters,
              )
              .first['n']
          as int;

  List<String> inventoryIds() => _database
      .select(
        "SELECT entity_id FROM inventory_metadata WHERE entity_type = 'inventory' ORDER BY rowid",
      )
      .map((r) => r['entity_id'] as String)
      .toList();

  Map<String, dynamic>? inventoryPayload(String id, {bool thumbnail = false}) {
    final table = thumbnail ? 'entity_state' : 'inventory_metadata';
    final rows = _database.select(
      "SELECT payload_json AS payload FROM $table WHERE entity_type = 'inventory' AND entity_id = ?",
      [id],
    );
    return rows.isEmpty
        ? null
        : jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> inventoryPage({
    required String where,
    required List<Object?> parameters,
    required String orderBy,
    required int limit,
    required int offset,
  }) {
    if (limit <= 0 || offset < 0) return [];
    return _database
        .select(
          "SELECT (SELECT payload_json FROM entity_state e WHERE e.entity_type = 'inventory' AND e.entity_id = m.entity_id) AS page_payload FROM inventory_metadata m WHERE entity_type = 'inventory' AND ($where) ORDER BY $orderBy LIMIT ? OFFSET ?",
          [...parameters, limit, offset],
        )
        .map(
          (r) =>
              jsonDecode(r['page_payload'] as String) as Map<String, dynamic>,
        )
        .toList();
  }

  void configureInventoryFunctions({
    required String Function(String) searchText,
    required int Function(String, String) compare,
  }) {
    _database.createFunction(
      functionName: 'inventory_search',
      argumentCount: const AllowedArgumentCount(1),
      function: (args) => searchText(args.single as String),
    );
    _database.createCollation(
      name: 'inventory_order',
      function: (a, b) => compare(a ?? '{}', b ?? '{}'),
    );
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
        final baseline = _conflictBaseline(change);
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
        _database.execute('UPDATE sync_outbox SET base_json = ? WHERE entity_type = ? AND entity_id = ?', [jsonEncode(baseline), change.entityType, change.entityId]);
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
        final baseline = _conflictBaseline(change);
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
        _database.execute('UPDATE sync_outbox SET base_json = ? WHERE entity_type = ? AND entity_id = ?', [jsonEncode(baseline), change.entityType, change.entityId]);
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Map<String, dynamic> _conflictBaseline(WorkshopEntityChange change) {
    final rows = _database.select('SELECT base_json FROM sync_outbox WHERE entity_type = ? AND entity_id = ?', [change.entityType, change.entityId]);
    final base = rows.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(jsonDecode(rows.first['base_json'] as String) as Map);
    final previous = readEntityPayload(change.entityType, change.entityId) ?? {};
    if (change.deleted) { base.putIfAbsent('(deleted)', () => previous); }
    for (final field in change.fields.keys) { base.putIfAbsent(field, () => previous[field]); }
    return base;
  }

  Map<String, dynamic>? readEntityPayload(String type, String id) {
    final rows = _database.select('SELECT payload_json FROM entity_state WHERE entity_type = ? AND entity_id = ?', [type, id]);
    return rows.isEmpty ? null : Map<String, dynamic>.from(jsonDecode(rows.first['payload_json'] as String) as Map);
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
         WHERE entity_type = 'inventory' AND (json_type(payload_json, '\$.image') IS NOT NULL OR json_type(payload_json, '\$.labelImage') IS NOT NULL) ''',
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
            baseFields: Map<String, dynamic>.from(jsonDecode(row['base_json'] as String) as Map),
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
        // A newer local revision still queued after this acknowledgement uses
        // the just-sent values as its remote baseline.
        final remaining = _database.select('SELECT base_json FROM sync_outbox WHERE id = ?', [pending.outboxId]);
        if (remaining.isNotEmpty) {
          final base = Map<String, dynamic>.from(jsonDecode(remaining.first['base_json'] as String) as Map);
          for (final field in pending.change.fields.keys) {
            if (base.containsKey(field)) base[field] = pending.change.fields[field];
          }
          _database.execute('UPDATE sync_outbox SET base_json = ? WHERE id = ?', [jsonEncode(base), pending.outboxId]);
        }
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
