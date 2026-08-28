import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

bool isFastener(String name) =>
    !name.toLowerCase().contains('printed part') &&
    RegExp(
      r'\b(screws?|bolts?|nuts?|washers?|spacers?|rivets?|clips?|zip[ -]?ties?|threaded inserts?)\b',
      caseSensitive: false,
    ).hasMatch(name);

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/migrate_fasteners.dart <database>');
    exitCode = 64;
    return;
  }

  final database = sqlite3.open(args.single);
  try {
    final rows = database.select('SELECT state_json FROM app_state WHERE id=1');
    if (rows.isEmpty) throw StateError('Inventorinator state is empty.');
    final root =
        jsonDecode(rows.first['state_json'] as String) as Map<String, dynamic>;
    final inventory = (root['inventory'] as List<dynamic>? ?? const []);
    final products = (root['products'] as List<dynamic>? ?? const []);
    final brands = (root['brands'] as List<dynamic>? ?? const []);

    var inventoryChanged = 0;
    for (final row in inventory.cast<Map<String, dynamic>>()) {
      if (row['type'] == 'other' && isFastener(row['name'] as String)) {
        row['type'] = 'fastener';
        inventoryChanged++;
      } else if (row['type'] == 'fastener' &&
          (row['name'] as String).toLowerCase().contains('printed part')) {
        row['type'] = 'other';
        inventoryChanged--;
      }
    }

    var productsChanged = 0;
    final fastenerBrandIds = <String>{};
    for (final row in products.cast<Map<String, dynamic>>()) {
      if (row['category'] == 'other' && isFastener(row['name'] as String)) {
        row['category'] = 'fastener';
        productsChanged++;
      } else if (row['category'] == 'fastener' &&
          (row['name'] as String).toLowerCase().contains('printed part')) {
        row['category'] = 'other';
        productsChanged--;
      }
      if (row['category'] == 'fastener') {
        fastenerBrandIds.add(row['brandId'] as String);
      }
    }

    for (final row in brands.cast<Map<String, dynamic>>()) {
      if (!fastenerBrandIds.contains(row['id'])) continue;
      final categories = (row['categories'] as List<dynamic>).cast<String>();
      if (!categories.contains('fastener')) categories.add('fastener');
    }

    final updatedAt = DateTime.now().toUtc().toIso8601String();
    database.execute('BEGIN IMMEDIATE');
    try {
      database.execute(
        'UPDATE app_state SET state_json=?, updated_at=? WHERE id=1',
        [jsonEncode(root), updatedAt],
      );
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
    stdout.writeln(
      'Migrated $inventoryChanged inventory items and $productsChanged products to Fasteners.',
    );
  } finally {
    database.close();
  }
}
