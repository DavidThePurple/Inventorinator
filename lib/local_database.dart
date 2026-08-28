import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class LocalDatabase {
  LocalDatabase._(this.path, this._database);

  final String path;
  Database _database;

  static Future<LocalDatabase> open({String? overridePath}) async {
    final databasePath =
        overridePath ??
        path_util.join(
          (await getApplicationSupportDirectory()).path,
          'inventorinator.sqlite3',
        );
    await Directory(path_util.dirname(databasePath)).create(recursive: true);
    final database = sqlite3.open(databasePath);
    final result = LocalDatabase._(databasePath, database);
    result._createSchema();
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

  String? loadState() {
    final rows = _database.select(
      'SELECT state_json FROM app_state WHERE id = 1',
    );
    return rows.isEmpty ? null : rows.first['state_json'] as String;
  }

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
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> deleteAndRecreate() async {
    _database.close();
    for (final suffix in const ['', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
    _database = sqlite3.open(path);
    _createSchema();
    await _hardenLocalPermissions(path);
  }

  void close() => _database.close();
}
