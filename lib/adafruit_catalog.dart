import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import 'adafruit.dart';

class AdafruitCatalogPage {
  const AdafruitCatalogPage(this.parts, this.total, this.offset);
  final List<AdafruitPart> parts;
  final int total, offset;
}

/// Separate, disposable supplier cache: never part of inventory or remote sync.
class AdafruitCatalog {
  AdafruitCatalog(this.path) : _db = sqlite3.open(path) {
    _schema(_db);
  }
  final String path;
  final Database _db;
  static final _refreshes = <String, Future<void>>{};
  static void _schema(Database db) {
    db.execute('PRAGMA busy_timeout = 5000');
    db.execute('PRAGMA journal_mode = WAL');
    db.execute(
      'CREATE TABLE IF NOT EXISTS products (id TEXT PRIMARY KEY, name TEXT NOT NULL, search TEXT NOT NULL, payload TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS catalog_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  DateTime? get updatedAt {
    final rows = _db.select(
      "SELECT value FROM catalog_meta WHERE key = 'updated'",
    );
    return rows.isEmpty
        ? null
        : DateTime.tryParse(rows.first['value'] as String);
  }

  int get count =>
      _db.select('SELECT count(*) AS n FROM products').first['n'] as int;
  AdafruitCatalogPage search(String query, {int offset = 0, int limit = 12}) {
    if (offset < 0 || limit < 1 || limit > 50 || query.length > 250) {
      throw const AdafruitException('Invalid catalog search.');
    }
    final id = AdafruitClient.productId(query);
    final tokens = (id ?? query)
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final args = <Object?>[];
    final clauses = <String>[];
    for (final token in tokens) {
      clauses.add("search LIKE ? ESCAPE '\\'");
      args.add(
        '%${token.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%',
      );
    }
    final where = clauses.isEmpty ? '1' : clauses.join(' AND ');
    final total =
        _db
                .select('SELECT count(*) AS n FROM products WHERE $where', args)
                .first['n']
            as int;
    final rows = _db.select(
      'SELECT payload FROM products WHERE $where ORDER BY CASE WHEN id = ? THEN 0 ELSE 1 END, name COLLATE NOCASE, id LIMIT ? OFFSET ?',
      [...args, id ?? '', limit, offset],
    );
    return AdafruitCatalogPage(
      rows
          .map(
            (row) => AdafruitPart.fromJson(
              jsonDecode(row['payload'] as String) as Map<String, dynamic>,
            ),
          )
          .toList(),
      total,
      offset,
    );
  }

  Future<void> refresh(AdafruitClient client) =>
      _refreshes.putIfAbsent(path, () async {
        final download = File(
          '$path.download-${DateTime.now().microsecondsSinceEpoch}',
        );
        try {
          await client.downloadCatalog(download);
          await importFile(download.path);
        } finally {
          if (await download.exists()) await download.delete();
          _refreshes.remove(path);
        }
      });
  Future<void> importFile(String filePath) {
    final dbPath = path;
    return Isolate.run(() => _importCatalog(dbPath, filePath));
  }

  void close() => _db.close();
}

/// Stream one JSON object at a time into a single SQLite transaction. An invalid
/// or interrupted refresh rolls back, leaving the previous catalog searchable.
Future<void> _importCatalog(String dbPath, String filePath) async {
  final db = sqlite3.open(dbPath);
  AdafruitCatalog._schema(db);
  final insert = db.prepare(
    'INSERT INTO products(id, name, search, payload) VALUES (?, ?, ?, ?)',
  );
  var depth = 0, count = 0, length = 0;
  var started = false,
      ended = false,
      quoted = false,
      escaped = false,
      expectValue = true;
  var object = StringBuffer();
  db.execute('BEGIN IMMEDIATE');
  try {
    db.execute('DELETE FROM products');
    await for (final chunk in File(
      filePath,
    ).openRead().transform(utf8.decoder)) {
      for (final char in chunk.codeUnits) {
        if (depth == 0) {
          if (char == 32 || char == 9 || char == 10 || char == 13) continue;
          if (!started && char == 91) {
            started = true;
            continue;
          }
          if (!started || ended) throw const FormatException('Invalid catalog');
          if (char == 93 && (!expectValue || count == 0)) {
            ended = true;
            continue;
          }
          if (char == 44 && !expectValue) {
            expectValue = true;
            continue;
          }
          if (char != 123 || !expectValue) {
            throw const FormatException('Invalid catalog entry');
          }
          object = StringBuffer();
          length = 0;
          depth = 1;
          object.writeCharCode(char);
          continue;
        }
        object.writeCharCode(char);
        if (++length > 512 * 1024) {
          throw const FormatException('Oversized catalog entry');
        }
        if (quoted) {
          if (escaped) {
            escaped = false;
          } else if (char == 92) {
            escaped = true;
          } else if (char == 34) {
            quoted = false;
          }
        } else if (char == 34) {
          quoted = true;
        } else if (char == 123 || char == 91) {
          depth++;
        } else if (char == 125 || char == 93) {
          depth--;
        }
        if (depth == 0) {
          final raw = jsonDecode(object.toString()) as Map<String, dynamic>;
          final part = AdafruitPart.fromJson(raw);
          if (!RegExp(r'^[1-9][0-9]*$').hasMatch(part.id) ||
              part.itemName.trim().isEmpty) {
            throw const FormatException('Invalid product');
          }
          final data = {
            'product_id': part.id,
            'product_name': part.itemName,
            'product_manufacturer': part.manufacturer,
            'product_mpn': part.partNumber,
            'product_image': part.imageUrl,
          };
          insert.execute([
            part.id,
            part.itemName,
            '${part.id} ${part.itemName} ${part.manufacturer} ${part.partNumber} ${raw['product_model'] ?? ''}'
                .toLowerCase(),
            jsonEncode(data),
          ]);
          count++;
          expectValue = false;
        }
      }
    }
    if (!ended || depth != 0 || count == 0) {
      throw const FormatException('Incomplete catalog');
    }
    db.execute(
      "INSERT INTO catalog_meta(key,value) VALUES ('updated',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
      [DateTime.now().toUtc().toIso8601String()],
    );
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  } finally {
    insert.close();
    db.close();
  }
}
