import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'session_secrets.dart';
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

  /// Preference holding the list of other workspaces this device can switch to.
  /// Each entry is a serialized `SupabaseConfig`, tokens included.
  static const knownWorkspacesPreference = 'known_supabase_workspaces';
  static const _secureSessionPreference = 'secure_session_storage';
  static const _currentSessionSlot = 'current';
  static const _recoveryKeyPrefix = 'workspace_recovery_key_';
  static const _recoverySlotPrefix = 'rk:';

  /// The keyring slot for a workspace recovery key preference, or null for any
  /// other preference.
  static String? _recoverySlot(String preferenceKey) =>
      preferenceKey.length > _recoveryKeyPrefix.length &&
          preferenceKey.startsWith(_recoveryKeyPrefix)
      ? '$_recoverySlotPrefix${preferenceKey.substring(_recoveryKeyPrefix.length)}'
      : null;

  final String path;
  Database _database;
  final RandomAccessFile? _instanceLock;
  bool _closed = false;
  int _writeGeneration = 0;
  Future<void> _syncSessionTail = Future<void>.value();
  Future<void> _writeTail = Future<void>.value();
  final Map<String, WorkshopEntityChange> _queuedWrites = {};
  final SessionSecretCache _secrets = SessionSecretCache();

  /// Keyring used when turning secure storage on. Tests supply a fake; the app
  /// leaves it null and uses the operating system's keyring.
  SecretVault? _preferredVault;

  /// Counts writes of session config, so enabling secure storage can tell that
  /// a token refresh landed while it was copying tokens to the keyring.
  int _sessionWrites = 0;

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

  Future<void> waitForPendingWrites() =>
      Future.wait([_writeTail, _secrets.flush()]);

  bool get isClosed => _closed;

  static Future<LocalDatabase> open({
    String? overridePath,
    SecretVault? secretVault,
  }) async {
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
    final result = LocalDatabase._(databasePath, database, instanceLock)
      .._preferredVault = secretVault;
    result._createSchema();
    result._seedEntityStateFromSnapshot();
    result._migrateInventoryImages();
    await _hardenLocalPermissions(databasePath);
    if (result.loadBoolPreference(_secureSessionPreference, fallback: false)) {
      await result._secrets.restore(
        secretVault ?? KeyringSecretVault(),
        result._persistedSessionSlots(),
      );
    }
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
    // UI edits and remote sync share this database. WAL keeps a short sync
    // read from blocking an item save, while the timeout lets the next writer
    // wait for the current transaction instead of immediately failing.
    _database.execute('PRAGMA journal_mode = WAL');
    _database.execute('PRAGMA busy_timeout = 10000');
    _database.execute('PRAGMA synchronous = NORMAL');
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
      _database.execute(
        "ALTER TABLE sync_outbox ADD COLUMN base_json TEXT NOT NULL DEFAULT '{}'",
      );
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
    final value = rows.isEmpty ? fallback : rows.first['value'] as String;
    if (!_secrets.attached) return value;
    if (key == knownWorkspacesPreference) return _withWorkspaceTokens(value);
    final slot = _recoverySlot(key);
    return slot == null ? value : _secrets.valueFor(slot) ?? fallback;
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
    var stored = value;
    if (key == knownWorkspacesPreference) {
      _sessionWrites++;
      if (_secrets.attached) stored = _stripWorkspaceTokens(value);
    } else if (_recoverySlot(key) case final slot?) {
      _sessionWrites++;
      if (_secrets.attached) {
        _secrets.put(slot, value);
        stored = '';
      }
    }
    _database.execute(
      '''
      INSERT INTO preferences (key, value) VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      ''',
      [key, stored],
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
    if (rows.isEmpty) return null;
    final source = rows.first['config_json'] as String;
    return _secrets.attached
        ? _withSessionTokens(
            source,
            SessionTokens.decode(_secrets.valueFor(_currentSessionSlot)),
          )
        : source;
  }

  void saveSyncConfig(String configJson) {
    _sessionWrites++;
    final stored = _secrets.attached
        ? _stripCurrentSessionTokens(configJson)
        : configJson;
    _database.execute(
      '''
      INSERT INTO sync_config (id, config_json, updated_at)
      VALUES (1, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        config_json = excluded.config_json,
        updated_at = excluded.updated_at
      ''',
      [stored, DateTime.now().toUtc().toIso8601String()],
    );
  }

  /// Whether Remote Sync sign-in tokens are kept in the system keyring rather
  /// than in this database.
  bool get secureSessionStorageEnabled => _secrets.attached;

  /// The latest keyring failure, or null when the keyring is working.
  Object? get secureSessionError => _secrets.error;

  /// Moves the Remote Sync tokens and the workspace recovery keys into the
  /// system keyring. Nothing changes if the keyring cannot store and return
  /// them; throws [SecretVaultUnavailable].
  Future<void> enableSecureSessionStorage({SecretVault? vault}) async {
    if (_secrets.attached) return;
    final target = vault ?? _preferredVault ?? KeyringSecretVault();
    await _secrets.probe(target);
    var secrets = const <String, String>{};
    try {
      for (var attempt = 0; attempt < 5; attempt++) {
        final writes = _sessionWrites;
        secrets = _storedSecrets();
        await _secrets.adopt(target, secrets);
        // A token refresh may have landed while the keyring was busy. Copy
        // again rather than strip newer tokens that were never stored.
        if (writes != _sessionWrites) continue;
        _moveSecretsOutOfSql();
        _secrets.activate(target, secrets);
        return;
      }
      throw const SecretVaultUnavailable(
        'The sign-in changed repeatedly while it was being moved. Try again.',
      );
    } catch (_) {
      await _secrets.discard(target, secrets.keys);
      rethrow;
    }
  }

  /// Moves the tokens back into this database and removes them from the
  /// keyring. Resolves to false if a keyring entry could not be removed.
  Future<bool> disableSecureSessionStorage() {
    if (!_secrets.attached) return Future.value(true);
    _restoreSecretsToSql();
    return _secrets.release();
  }

  static String? _workspaceSlot(Map<String, dynamic> entry) {
    final url = entry['url'];
    final id = entry['workspaceId'];
    if (url is! String || id is! String || url.isEmpty || id.isEmpty) {
      return null;
    }
    return 'ws:${Uri.encodeComponent(url)}:$id';
  }

  static List<Map<String, dynamic>>? _workspaceEntries(String source) {
    try {
      final decoded = jsonDecode(source);
      return decoded is List
          ? decoded.whereType<Map<String, dynamic>>().toList()
          : null;
    } on FormatException {
      return null;
    }
  }

  String? _rawPreference(String key) {
    final rows = _database.select(
      'SELECT value FROM preferences WHERE key = ?',
      [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  String? _rawSyncConfig() {
    final rows = _database.select(
      'SELECT config_json FROM sync_config WHERE id = 1',
    );
    return rows.isEmpty ? null : rows.first['config_json'] as String;
  }

  /// Preference keys of the recovery keys stored on this device, whether they
  /// currently hold the key or an empty placeholder.
  List<String> _recoveryPreferenceKeys() => _database
      .select('SELECT key FROM preferences WHERE substr(key, 1, ?) = ?', [
        _recoveryKeyPrefix.length,
        _recoveryKeyPrefix,
      ])
      .map((row) => row['key'] as String)
      .where((key) => _recoverySlot(key) != null)
      .toList();

  Set<String> _persistedSessionSlots() => {
    _currentSessionSlot,
    for (final entry
        in _workspaceEntries(_rawPreference(knownWorkspacesPreference) ?? '') ??
            const <Map<String, dynamic>>[])
      ?_workspaceSlot(entry),
    for (final key in _recoveryPreferenceKeys()) _recoverySlot(key)!,
  };

  static String _tokenValue(SessionTokens tokens) =>
      tokens.isEmpty ? '' : tokens.encode();

  /// The secrets currently stored in plain SQLite rows, by keyring slot.
  Map<String, String> _storedSecrets() {
    final secrets = <String, String>{};
    final config = _rawSyncConfig();
    if (config != null) {
      try {
        final json = jsonDecode(config);
        if (json is Map<String, dynamic>) {
          secrets[_currentSessionSlot] = _tokenValue(
            SessionTokens.fromJson(json),
          );
        }
      } on FormatException {
        // An unreadable config holds no usable tokens.
      }
    }
    for (final entry
        in _workspaceEntries(_rawPreference(knownWorkspacesPreference) ?? '') ??
            const <Map<String, dynamic>>[]) {
      final slot = _workspaceSlot(entry);
      if (slot != null) {
        secrets[slot] = _tokenValue(SessionTokens.fromJson(entry));
      }
    }
    for (final key in _recoveryPreferenceKeys()) {
      secrets[_recoverySlot(key)!] = (_rawPreference(key) ?? '').trim();
    }
    return secrets;
  }

  /// Rewrites the stored rows without tokens or recovery keys and records that
  /// the keyring is in use, atomically. SQLite is told to overwrite freed
  /// pages so the old text does not linger in the file.
  void _moveSecretsOutOfSql() {
    final previous = _database
        .select('PRAGMA secure_delete')
        .first
        .values
        .first;
    _database.execute('PRAGMA secure_delete = ON');
    _database.execute('BEGIN IMMEDIATE');
    try {
      final config = _rawSyncConfig();
      if (config != null) {
        _database.execute(
          'UPDATE sync_config SET config_json = ? WHERE id = 1',
          [_stripTokensFromConfigText(config)],
        );
      }
      final known = _rawPreference(knownWorkspacesPreference);
      final entries = known == null ? null : _workspaceEntries(known);
      if (entries != null) {
        _database.execute('UPDATE preferences SET value = ? WHERE key = ?', [
          jsonEncode([for (final entry in entries) SessionTokens.strip(entry)]),
          knownWorkspacesPreference,
        ]);
      }
      for (final key in _recoveryPreferenceKeys()) {
        _database.execute("UPDATE preferences SET value = '' WHERE key = ?", [
          key,
        ]);
      }
      _database.execute(
        '''
        INSERT INTO preferences (key, value) VALUES (?, 'true')
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        ''',
        [_secureSessionPreference],
      );
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    } finally {
      _database.execute('PRAGMA secure_delete = $previous');
    }
    _database.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  }

  void _restoreSecretsToSql() {
    _database.execute('BEGIN IMMEDIATE');
    try {
      final config = _rawSyncConfig();
      if (config != null) {
        _database.execute(
          'UPDATE sync_config SET config_json = ? WHERE id = 1',
          [
            _withSessionTokens(
              config,
              SessionTokens.decode(_secrets.valueFor(_currentSessionSlot)),
            ),
          ],
        );
      }
      final known = _rawPreference(knownWorkspacesPreference);
      if (known != null) {
        _database.execute('UPDATE preferences SET value = ? WHERE key = ?', [
          _withWorkspaceTokens(known),
          knownWorkspacesPreference,
        ]);
      }
      for (final slot in _secrets.slotsWithPrefix(_recoverySlotPrefix)) {
        final key =
            _recoveryKeyPrefix + slot.substring(_recoverySlotPrefix.length);
        _database.execute(
          '''
          INSERT INTO preferences (key, value) VALUES (?, ?)
          ON CONFLICT(key) DO UPDATE SET value = excluded.value
          ''',
          [key, _secrets.valueFor(slot) ?? ''],
        );
      }
      _database.execute('DELETE FROM preferences WHERE key = ?', [
        _secureSessionPreference,
      ]);
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  static String _stripTokensFromConfigText(String config) {
    try {
      final json = jsonDecode(config);
      return json is Map<String, dynamic>
          ? jsonEncode(SessionTokens.strip(json))
          : config;
    } on FormatException {
      return config;
    }
  }

  String _stripCurrentSessionTokens(String configJson) {
    try {
      final json = jsonDecode(configJson);
      if (json is! Map<String, dynamic>) return configJson;
      _secrets.put(
        _currentSessionSlot,
        _tokenValue(SessionTokens.fromJson(json)),
      );
      return jsonEncode(SessionTokens.strip(json));
    } on FormatException {
      return configJson;
    }
  }

  static String _withSessionTokens(String source, SessionTokens tokens) {
    if (tokens.isEmpty) return source;
    // The stored text is a JSON object written by jsonEncode, so the tokens
    // can be spliced in after the opening brace. That avoids re-parsing the
    // config, which carries a snapshot of the whole inventory.
    if (source.length > 2 && source.startsWith('{') && source[1] != '}') {
      return '{"accessToken":${jsonEncode(tokens.accessToken)},'
          '"refreshToken":${jsonEncode(tokens.refreshToken)},'
          '${source.substring(1)}';
    }
    try {
      final json = jsonDecode(source);
      return json is Map<String, dynamic>
          ? jsonEncode(tokens.mergeInto(json))
          : source;
    } on FormatException {
      return source;
    }
  }

  String _withWorkspaceTokens(String source) {
    final entries = _workspaceEntries(source);
    if (entries == null) return source;
    return jsonEncode([
      for (final entry in entries)
        switch (_workspaceSlot(entry)) {
          final slot? => SessionTokens.decode(
            _secrets.valueFor(slot),
          ).mergeInto(entry),
          null => entry,
        },
    ]);
  }

  String _stripWorkspaceTokens(String source) {
    final entries = _workspaceEntries(source);
    if (entries == null) return source;
    final listed = <String>{};
    for (final entry in entries) {
      final slot = _workspaceSlot(entry);
      if (slot == null) continue;
      listed.add(slot);
      _secrets.put(slot, _tokenValue(SessionTokens.fromJson(entry)));
    }
    // A workspace dropped from the list also loses its stored sign-in.
    for (final slot in _secrets.slotsWithPrefix('ws:').toList()) {
      if (!listed.contains(slot)) _secrets.put(slot, null);
    }
    return jsonEncode([
      for (final entry in entries) SessionTokens.strip(entry),
    ]);
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

  /// The sort fields of every inventory record matching [where], used to
  /// place kits, builds and machines within the paged inventory order.
  List<({String type, String name, String customTypeName, String added})>
  inventorySortFields({
    String where = '1',
    List<Object?> parameters = const [],
  }) => _database
      .select(
        "SELECT json_extract(payload_json, '\$.type') AS type, "
        "json_extract(payload_json, '\$.name') AS name, "
        "coalesce(json_extract(payload_json, '\$.customTypeName'), '') AS custom, "
        "json_extract(payload_json, '\$.added') AS added "
        "FROM inventory_metadata WHERE entity_type = 'inventory' AND ($where)",
        parameters,
      )
      .map(
        (row) => (
          type: row['type'] as String,
          name: row['name'] as String,
          customTypeName: row['custom'] as String,
          added: row['added'] as String,
        ),
      )
      .toList();

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
        _database.execute(
          'UPDATE sync_outbox SET base_json = ? WHERE entity_type = ? AND entity_id = ?',
          [jsonEncode(baseline), change.entityType, change.entityId],
        );
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  void applyAndQueueWorkshopChanges(
    Iterable<WorkshopEntityChange> changes, {
    Map<String, String> localPreferences = const {},
  }) {
    final pending = changes.toList();
    if (pending.isEmpty && localPreferences.isEmpty) return;
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
        _database.execute(
          'UPDATE sync_outbox SET base_json = ? WHERE entity_type = ? AND entity_id = ?',
          [jsonEncode(baseline), change.entityType, change.entityId],
        );
      }
      for (final entry in localPreferences.entries) {
        _database.execute(
          'INSERT INTO preferences(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
          [entry.key, entry.value],
        );
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Map<String, dynamic> _conflictBaseline(WorkshopEntityChange change) {
    if (change.baseFields?['(importUndo)'] == true) {
      return Map.of(change.baseFields!);
    }

    final rows = _database.select(
      'SELECT base_json FROM sync_outbox WHERE entity_type = ? AND entity_id = ?',
      [change.entityType, change.entityId],
    );
    final base = rows.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(
            jsonDecode(rows.first['base_json'] as String) as Map,
          );
    if (!change.deleted && base['(importUndo)'] == true) base.clear();
    final previous =
        readEntityPayload(change.entityType, change.entityId) ?? {};
    if (change.deleted) {
      // A tombstone supersedes every earlier queued local edit. Keep the
      // original remote values for future diagnostics rather than treating the
      // current local payload (which may contain unsynced edits) as remote.
      final remoteBaseline = Map<String, dynamic>.from(previous);
      for (final entry in base.entries) {
        if (!entry.key.startsWith('(')) remoteBaseline[entry.key] = entry.value;
      }
      base['(deleted)'] = remoteBaseline;
    }
    if (change.entityType == 'inventory') base.remove('modifiedAt');
    for (final field in change.fields.keys) {
      if (change.entityType == 'inventory' && field == 'modifiedAt') continue;
      base.putIfAbsent(field, () => previous[field]);
    }
    return base;
  }

  Map<String, dynamic>? readFullInventoryPayload(String id) {
    final payload = readEntityPayload('inventory', id);
    if (payload == null) return null;
    final images = loadInventoryImages(id);
    return {
      ...payload,
      'image': images.imageBytes == null
          ? null
          : base64Encode(images.imageBytes!),
      'labelImage': images.labelImageBytes == null
          ? null
          : base64Encode(images.labelImageBytes!),
    };
  }

  // Conservative: protect direct IDs, inventory product references and name-based
  // kit/build requirements. Audit/addition history intentionally survives undo.
  bool hasImportItemReferences(String id, String name) {
    final rows = _database.select(
      "SELECT payload_json FROM entity_state WHERE entity_type NOT IN ('inventory','auditLog','additionHistory','workshopMetadata')",
    );
    bool references(dynamic value) {
      if (value is String) {
        return value == id ||
            value == 'inventory:$id' ||
            (name.isNotEmpty &&
                value.trim().toLowerCase() == name.trim().toLowerCase());
      }
      if (value is List) return value.any(references);
      if (value is Map) return value.values.any(references);
      return false;
    }

    return rows.any(
      (row) => references(jsonDecode(row['payload_json'] as String)),
    );
  }

  Map<String, dynamic>? readEntityPayload(String type, String id) {
    final rows = _database.select(
      'SELECT payload_json FROM entity_state WHERE entity_type = ? AND entity_id = ?',
      [type, id],
    );
    return rows.isEmpty
        ? null
        : Map<String, dynamic>.from(
            jsonDecode(rows.first['payload_json'] as String) as Map,
          );
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
            baseFields: Map<String, dynamic>.from(
              jsonDecode(row['base_json'] as String) as Map,
            ),
          ),
        ),
      )
      .toList();

  /// Lets an explicit "keep local" conflict decision replace the stale
  /// conditional-write baseline with the user's chosen change.
  void rebasePendingWorkshopChange(String entityType, String entityId) {
    _database.execute(
      'UPDATE sync_outbox SET base_json = ? WHERE entity_type = ? AND entity_id = ?',
      [jsonEncode(<String, dynamic>{}), entityType, entityId],
    );
  }

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
        final remaining = _database.select(
          'SELECT base_json FROM sync_outbox WHERE id = ?',
          [pending.outboxId],
        );
        if (remaining.isNotEmpty) {
          final base = Map<String, dynamic>.from(
            jsonDecode(remaining.first['base_json'] as String) as Map,
          );
          for (final field in pending.change.fields.keys) {
            if (base.containsKey(field)) {
              base[field] = pending.change.fields[field];
            }
          }
          _database.execute(
            'UPDATE sync_outbox SET base_json = ? WHERE id = ?',
            [jsonEncode(base), pending.outboxId],
          );
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
    // Deleting the local data also forgets the sign-in kept in the keyring.
    if (_secrets.attached) await _secrets.release();
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
