import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

String _normalized(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

const _typeColors = <String, int>{
  'other': 0xff929aac,
  'fastener': 0xffc8a96b,
  'filament': 0xff7455ff,
  'printedPart': 0xffa987ff,
  'resin': 0xffd15cff,
  'nozzle': 0xffffb13b,
  'heatBreak': 0xff45d2bd,
  'heatBlock': 0xffff6b6b,
  'sock': 0xff55a8ff,
  'custom': 0xff9aa4b8,
};

void main(List<String> args) {
  if (args.length != 2 || args.first != '--apply') {
    stderr.writeln(
      'Usage: dart run tool/materialize_bom_inventory.dart --apply DB_PATH',
    );
    exitCode = 64;
    return;
  }

  final database = sqlite3.open(args.last);
  try {
    final rows = database.select('SELECT state_json FROM app_state WHERE id=1');
    if (rows.isEmpty) throw StateError('Inventorinator state is empty.');
    final root =
        jsonDecode(rows.first['state_json'] as String) as Map<String, dynamic>;
    final inventory = (root['inventory'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    final products = (root['products'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    final kits = (root['kits'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    final brands = (root['brands'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    final machines = (root['machines'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();

    final productsById = {
      for (final product in products) product['id']: product,
    };
    final brandsById = {for (final brand in brands) brand['id']: brand};
    final kitNamesByProduct = <String, Set<String>>{};
    final kitIdsByProduct = <String, Set<String>>{};
    for (final kit in kits) {
      for (final line in (kit['bom'] as List<dynamic>? ?? const [])) {
        final productId = (line as Map<String, dynamic>)['productId'] as String;
        if (!productsById.containsKey(productId)) continue;
        kitNamesByProduct
            .putIfAbsent(productId, () => {})
            .add(kit['name'] as String);
        kitIdsByProduct
            .putIfAbsent(productId, () => {})
            .add(kit['id'] as String);
      }
    }

    final existingProductIds = inventory
        .map((item) => item['catalogProductId'])
        .whereType<String>()
        .toSet();
    final existingNamesByType = {
      for (final item in inventory)
        '${item['type']}:${_normalized(item['name'] as String)}',
    };
    final now = DateTime.now().toUtc();
    var added = 0;
    for (final entry in kitNamesByProduct.entries) {
      final product = productsById[entry.key]!;
      final type = product['category'] as String? ?? 'other';
      if (existingProductIds.contains(entry.key) ||
          existingNamesByType.contains(
            '$type:${_normalized(product['name'] as String)}',
          )) {
        continue;
      }
      final brand = brandsById[product['brandId']];
      final sourceUrls = (product['sourceUrls'] as List<dynamic>? ?? const [])
          .cast<String>();
      final compatibleMachineIds = machines
          .where((machine) {
            final machineKitIds =
                (machine['kitIds'] as List<dynamic>? ?? const [])
                    .cast<String>();
            return machineKitIds.any(kitIdsByProduct[entry.key]!.contains);
          })
          .map((machine) => machine['id'] as String)
          .toList();
      inventory.add({
        'id': 'INV-BOM-${entry.key.replaceFirst(RegExp(r'^PROD-'), '')}',
        'name': product['name'],
        'type': type,
        'compatibility': entry.value.toList()..sort(),
        'added': now.add(Duration(microseconds: added)).toIso8601String(),
        'cost': (product['defaultCost'] as num?)?.toDouble() ?? 0.0,
        'color': _typeColors[type] ?? _typeColors['other'],
        'quantity': 0.0,
        'vendor': '',
        'printingInstructions': product['printingInstructions'] ?? '',
        'dryingInstructions': product['dryingInstructions'] ?? '',
        'storageInstructions': product['storageInstructions'] ?? '',
        'archived': false,
        'archiveDisposition': 'archived',
        'filamentStatus': 'ready',
        'brand': brand?['name'] ?? '',
        'image': product['image'],
        'productUrl': sourceUrls.isEmpty ? '' : sourceUrls.first,
        'compatibleMachineIds': compatibleMachineIds,
        'catalogProductId': entry.key,
      });
      added++;
    }

    if (added == 0) {
      stdout.writeln('No missing BOM inventory items.');
      return;
    }
    database.execute('BEGIN IMMEDIATE');
    try {
      database.execute(
        'UPDATE app_state SET state_json = ?, updated_at = ? WHERE id = 1',
        [jsonEncode(root), DateTime.now().toUtc().toIso8601String()],
      );
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
    stdout.writeln('Added $added distinct BOM parts at quantity 0.');
  } finally {
    database.close();
  }
}
