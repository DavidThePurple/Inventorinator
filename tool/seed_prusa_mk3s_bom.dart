import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

const sourceUrl =
    'https://help.prusa3d.com/manual/original-prusa-i3-mk3s-kit-assembly_1128';

bool isFastener(String name) =>
    !name.toLowerCase().contains('printed part') &&
    RegExp(
      r'\b(screws?|bolts?|nuts?|washers?|spacers?|rivets?|clips?|zip[ -]?ties?|threaded inserts?)\b',
      caseSensitive: false,
    ).hasMatch(name);

const bom = <String, num>{
  'Aluminum YZ frame': 1,
  'Aluminum extrusion': 4,
  'Y-axis front plate': 1,
  'Y-axis rear plate': 1,
  'Antivibration foot': 4,
  'Y-carriage': 1,
  'Y bearing clip': 3,
  'LM8UU linear bearing': 10,
  '8 mm smooth rod — 320 mm': 2,
  '8 mm smooth rod — 330 mm': 2,
  '8 mm smooth rod — 370 mm': 2,
  'X-axis stepper motor': 1,
  'Y-axis stepper motor': 1,
  'Z-axis stepper motor with leadscrew': 2,
  'Extruder stepper motor': 1,
  'GT2 16-tooth pulley': 2,
  'GT2 X-axis belt': 1,
  'GT2 Y-axis belt': 1,
  '623h idler bearing': 2,
  'Trapezoidal leadscrew nut': 2,
  'Y-belt-idler printed part': 1,
  'Y-belt-tensioner printed part': 1,
  'Y-motor-holder printed part': 1,
  'Y-belt-holder printed part': 1,
  'Y-rod-holder printed part': 4,
  'X-end-motor printed part': 1,
  'X-end-idler printed part': 1,
  'Z-axis-bottom-left printed part': 1,
  'Z-axis-bottom-right printed part': 1,
  'Z-axis-top-left printed part': 1,
  'Z-axis-top-right printed part': 1,
  'Z-screw-cover printed part': 2,
  'X-carriage printed part': 1,
  'X-carriage-back printed part': 1,
  'Extruder-body printed part': 1,
  'Adapter-printer printed part': 1,
  'FS-lever printed part': 1,
  'FS-cover printed part': 1,
  'Extruder-cover printed part': 1,
  'Extruder-idler printed part': 1,
  'Extruder-motor-plate printed part': 1,
  'Fan-shroud printed part': 1,
  'Cable-holder printed part': 1,
  'Extruder-cable-clip printed part': 1,
  'Heatbed-cable-clip printed part': 1,
  'Heatbed cable cover': 1,
  'Heatbed cable cover clip': 1,
  'LCD-cover printed part': 1,
  'LCD-knob printed part': 1,
  'LCD-support printed part': 2,
  'Einsy-base printed part': 1,
  'Einsy-door printed part': 1,
  'Einsy hinge': 2,
  'PSU cover': 1,
  'Double spool holder center': 1,
  'Double spool holder arm': 2,
  'E3D V6 MK3S+ hotend assembly': 1,
  '0.4 mm brass V6 nozzle': 1,
  'Bondtech drive gear set': 1,
  'Bondtech idler bearing': 2,
  'Bondtech idler shaft': 1,
  'Extruder idler spring': 1,
  'Steel filament-sensor ball': 1,
  'Magnet 10x6x2 mm': 1,
  'Magnet 20x6x2 mm': 1,
  'Prusa IR filament sensor': 1,
  'IR filament-sensor cable': 1,
  'SuperPINDA probe': 1,
  'Hotend fan': 1,
  'Print fan': 1,
  'EINSY RAMBo motherboard': 1,
  'MK3 LCD screen': 1,
  'LCD ribbon cable': 2,
  'MK52 24V heatbed': 1,
  'Removable spring-steel print sheet': 1,
  'Heatbed power cable': 1,
  'Heatbed thermistor': 1,
  '24V power supply': 1,
  'PSU power cable pair': 2,
  'Power panic cable': 1,
  'SD card': 1,
  'M2x8 screw': 1,
  'M3x6 screw': 6,
  'M3x10 screw': 78,
  'M3x12b screw': 9,
  'M3x14 or M3x16b fan screw': 3,
  'M3x18 screw': 7,
  'M3x20 or M3x22b fan screw': 3,
  'M3x30 screw': 2,
  'M3x40 screw': 7,
  'M4x10r dome-head screw': 2,
  'M5x16r screw': 32,
  'M3 square nut': 30,
  'M3 hex nut': 24,
  'M3 nyloc nut': 6,
  'M3 elastic nut for PSU': 2,
  'M3 washer 3.2x9x0.8 mm': 2,
  'Heatbed spacer 6x6x3 mm': 9,
  'Textile sleeve 5x300 mm': 2,
  'Textile sleeve 13x490 mm': 1,
  'Black nylon filament guide — 500 mm': 1,
  'Zip tie': 8,
};

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/seed_prusa_mk3s_bom.dart DB_PATH');
    exitCode = 64;
    return;
  }
  final database = sqlite3.open(args.single);
  try {
    final rows = database.select('SELECT state_json FROM app_state WHERE id=1');
    if (rows.isEmpty) throw StateError('Inventorinator state is empty.');
    final root =
        jsonDecode(rows.first['state_json'] as String) as Map<String, dynamic>;
    final inventory = (root['inventory'] as List<dynamic>? ?? <dynamic>[]);
    final vendors = (root['vendors'] as List<dynamic>? ?? <dynamic>[]);
    final brands = (root['brands'] as List<dynamic>? ?? <dynamic>[]);
    final products = (root['products'] as List<dynamic>? ?? <dynamic>[]);
    final machineTypes =
        (root['machineTypes'] as List<dynamic>? ?? <dynamic>[]);
    final machines = (root['machines'] as List<dynamic>? ?? <dynamic>[]);
    final kits = (root['kits'] as List<dynamic>? ?? <dynamic>[]);
    final history = (root['additionHistory'] as List<dynamic>? ?? <dynamic>[]);

    const vendorId = 'VEN-PRUSA-RESEARCH';
    const brandId = 'BR-PRUSA-RESEARCH';
    const kitId = 'KIT-ORIGINAL-PRUSA-I3-MK3S-PLUS';
    const machineId = 'MCH-ORIGINAL-PRUSA-I3-MK3S-PLUS';
    const printerTypeId = 'MT-PRINTER';
    const fdmTypeId = 'MT-FDM';
    final now = DateTime.now().toUtc();

    vendors.removeWhere((row) => row['id'] == vendorId);
    vendors.add({
      'id': vendorId,
      'name': 'Prusa Research',
      'isBrand': true,
      'logo': null,
    });
    brands.removeWhere((row) => row['id'] == brandId);
    brands.add({
      'id': brandId,
      'name': 'Prusa Research',
      'vendorIds': [vendorId],
      'categories': ['other', 'fastener', 'nozzle'],
      'logo': null,
    });
    machineTypes.removeWhere(
      (row) => row['id'] == printerTypeId || row['id'] == fdmTypeId,
    );
    machineTypes.addAll([
      {'id': printerTypeId, 'name': 'Printer', 'parentId': null},
      {'id': fdmTypeId, 'name': 'FDM', 'parentId': printerTypeId},
    ]);

    final bomLines = <Map<String, dynamic>>[];
    var offset = 0;
    for (final entry in bom.entries) {
      final slug = entry.key
          .toUpperCase()
          .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final productId = 'PROD-MK3S-$slug';
      final itemId = 'INV-MK3S-$slug';
      final category = entry.key.contains('nozzle')
          ? 'nozzle'
          : isFastener(entry.key)
          ? 'fastener'
          : 'other';
      products.removeWhere((row) => row['id'] == productId);
      products.add({
        'id': productId,
        'brandId': brandId,
        'category': category,
        'name': entry.key,
        'defaultCost': 0,
        'dryingMinutes': null,
        'printingInstructions': 'Original Prusa i3 MK3S+ assembly component.',
        'dryingInstructions': '',
        'storageInstructions': 'Keep labeled with the MK3S+ service parts.',
        'image': null,
      });
      bomLines.add({'productId': productId, 'quantity': entry.value});
      inventory.removeWhere((row) => row['id'] == itemId);
      final added = now.add(Duration(microseconds: offset++));
      inventory.add({
        'id': itemId,
        'name': entry.key,
        'type': category,
        'compatibility': ['Original Prusa i3 MK3S+'],
        'added': added.toIso8601String(),
        'cost': 0,
        'color': category == 'nozzle' ? 4291559424 : 4286612095,
        'quantity': entry.value,
        'dryingMinutes': null,
        'dryingRemaining': null,
        'dryingStartedAt': null,
        'moistureLifespanMinutes': null,
        'moistureTimeUnit': 'days',
        'moistureAlertEnabled': false,
        'moistureAlertThresholdMinutes': null,
        'deployed': false,
        'vendor': 'Prusa Research',
        'printingInstructions':
            'Required quantity: ${entry.value}. See the official MK3S+ v3.26 assembly manual.',
        'dryingInstructions': '',
        'storageInstructions': 'Keep labeled with the MK3S+ service parts.',
        'archived': false,
        'archiveDisposition': 'archived',
        'filamentStatus': 'ready',
        'brand': 'Prusa Research',
        'storageLocation': '',
        'deploymentLocation': '',
        'lastDriedAt': null,
        'image': null,
        'barcode': '',
        'productUrl': sourceUrl,
        'compatibleMachineIds': [machineId],
      });
      history.removeWhere((row) => row['itemId'] == itemId);
      history.add({
        'id': 'ADD-$itemId',
        'itemId': itemId,
        'name': entry.key,
        'type': category,
        'addedAt': added.toIso8601String(),
        'deviceName': 'Official Prusa BOM import',
      });
    }
    kits.removeWhere((row) => row['id'] == kitId);
    kits.add({
      'id': kitId,
      'name': 'Original Prusa i3 MK3S+ — official assembly BOM v3.26',
      'bom': bomLines,
    });
    machines.removeWhere((row) => row['id'] == machineId);
    machines.add({
      'id': machineId,
      'name': 'Original Prusa i3 MK3S+',
      'model': 'MK3S+',
      'address': '',
      'typeId': fdmTypeId,
      'kitIds': [kitId],
    });
    root
      ..['vendors'] = vendors
      ..['brands'] = brands
      ..['products'] = products
      ..['machineTypes'] = machineTypes
      ..['machines'] = machines
      ..['kits'] = kits
      ..['inventory'] = inventory
      ..['additionHistory'] = history;
    database.execute('BEGIN IMMEDIATE');
    try {
      database.execute(
        'UPDATE app_state SET state_json=?, updated_at=? WHERE id=1',
        [jsonEncode(root), now.toIso8601String()],
      );
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
    stdout.writeln(
      'Imported ${bom.length} inventory records and BOM lines; created one kit and one machine.',
    );
  } finally {
    database.close();
  }
}
