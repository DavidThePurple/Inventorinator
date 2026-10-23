import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:sqlite3/sqlite3.dart';

const _guideRoot = 'https://ldomotion.com/guides/';
const _productGuide = 'https://ldomotion.com/p/assembly/Positron-V32';

class _GuidePart {
  const _GuidePart(this.name, this.quantity, this.guide, {this.guideText});

  final String name;
  final double quantity;
  final String guide;
  final String? guideText;

  String get printedGuideText => guideText ?? '$name x${quantity.toInt()}';
  String get productId =>
      'PROD-POSITRON-V32-PRINTED-${name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '')}';
}

const _parts = <_GuidePart>[
  _GuidePart('Extruder Main Body', 1, '1---positron-v32---extruder'),
  _GuidePart('Extruder Motor Plate', 1, '1---positron-v32---extruder'),
  _GuidePart('Extruder Bottom Plate', 1, '1---positron-v32---extruder'),
  _GuidePart('Extruder Guidler', 1, '1---positron-v32---extruder'),
  _GuidePart('Z Top Stopper', 1, '2---positron-v32---z-column'),
  _GuidePart('Z PCB Spacer', 1, '2---positron-v32---z-column'),
  _GuidePart('Z Belt Tensioner Block', 1, '2---positron-v32---z-column'),
  _GuidePart('Z Tension Arm', 1, '2---positron-v32---z-column'),
  _GuidePart('Z Tension Pivot', 1, '2---positron-v32---z-column'),
  _GuidePart('Z Tension Stop', 1, '2---positron-v32---z-column'),
  _GuidePart('Z Tension Plug', 1, '2---positron-v32---z-column'),
  _GuidePart('Edge Connector Alignment Tool', 1, '2---positron-v32---z-column'),
  _GuidePart('Z Rail Alignment Jig', 2, '2---positron-v32---z-column'),
  _GuidePart('Bed Cable Guide', 1, '2---positron-v32---z-column'),
  _GuidePart(
    'Z Tension Arm (5 mm ball plunger variant)',
    1,
    '2---positron-v32---z-column',
    guideText: 'Tension Arm (updated version for ball plunger) x1',
  ),
  _GuidePart(
    'Z Drive Main Body',
    1,
    '3---positron-v32---z-drive',
    guideText: 'Z Drive Main Body x1 (Remember to remove the printed support.)',
  ),
  _GuidePart('Z Drive Outer Housing', 1, '3---positron-v32---z-drive'),
  _GuidePart('Z Motor Bracket', 1, '3---positron-v32---z-drive'),
  _GuidePart(
    'Bed Spring Retainer Ring',
    2,
    '4---positron-v32---bed-v-holder',
    guideText:
        'Bed Spring Retainer Ring x2 (Remember to remove the printed support.)',
  ),
  _GuidePart('Touch Enclosure', 1, '5---positron-v32---touch-panel'),
  _GuidePart('Cover Stand', 1, '5---positron-v32---touch-panel'),
  _GuidePart('Back Plate', 1, '5---positron-v32---touch-panel'),
  _GuidePart('Toolhead Belt Retainer Block', 1, '6---positron-v32---toolhead'),
  _GuidePart('Spool Holder Part A', 2, '7---positron-v32---spool-holder'),
  _GuidePart('Spool Holder Part B', 2, '7---positron-v32---spool-holder'),
  _GuidePart('Spool Holder Part C', 2, '7---positron-v32---spool-holder'),
  _GuidePart('AB Pulley Alignment Tool', 1, '8---positron-v32---base-plate'),
  _GuidePart('Switch PCB Mount', 1, '8---positron-v32---base-plate'),
  _GuidePart('Light Bar Bracket Front', 1, '8---positron-v32---base-plate'),
  _GuidePart('Light Bar Bracket Rear', 1, '8---positron-v32---base-plate'),
  _GuidePart('Side Panel Back Left', 1, '8---positron-v32---base-plate'),
  _GuidePart('Side Panel Back Right', 1, '8---positron-v32---base-plate'),
  _GuidePart('Side Panel Front Left', 1, '8---positron-v32---base-plate'),
  _GuidePart('Side Panel Front Right', 1, '8---positron-v32---base-plate'),
  _GuidePart(
    'Fish Bone Grill Large (or Slanted Grill Large)',
    2,
    '8---positron-v32---base-plate',
    guideText: 'Fish Bone Grill Large x2 or Slanted Grill Large x2',
  ),
  _GuidePart(
    'Fish Bone Grill Small (or Slanted Grill Small)',
    2,
    '8---positron-v32---base-plate',
    guideText: 'Fish Bone Grill Small x2 or Slanted Grill Small x2',
  ),
  _GuidePart('Front Bumper', 1, '8---positron-v32---base-plate'),
  _GuidePart('Rear Cable Panel', 1, '8---positron-v32---base-plate'),
  _GuidePart('Mid Panel Right', 1, '8---positron-v32---base-plate'),
  _GuidePart('Mid Panel Left', 1, '8---positron-v32---base-plate'),
  _GuidePart('LED Cluster Retainer', 1, '8---positron-v32---base-plate'),
  _GuidePart('Panel Cornerstone Left', 1, '8---positron-v32---base-plate'),
  _GuidePart('Panel Cornerstone Right', 1, '8---positron-v32---base-plate'),
  _GuidePart('Rear Idler Tensioner Block', 1, '8---positron-v32---base-plate'),
  _GuidePart('Part Fan Enclosure', 1, '9---positron-v32---final-assembly'),
  _GuidePart('Bowden Guide', 1, '9---positron-v32---final-assembly'),
  _GuidePart('Toolboard Cover', 1, '9---positron-v32---final-assembly'),
];

void main(List<String> args) async {
  final arguments = [...args];
  final dryRun = arguments.remove('--dry-run');
  final verifyImages = arguments.remove('--verify-images');
  final hydrateThumbnails = arguments.remove('--hydrate-thumbnails');
  final zeroInventory = arguments.remove('--zero-inventory');
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/import_positron_v32_printed_parts.dart [--dry-run|--zero-inventory] DB_PATH',
    );
    exitCode = 64;
    return;
  }
  final databasePath = arguments.single;
  final db = sqlite3.open(
    databasePath,
    mode: dryRun || verifyImages ? OpenMode.readOnly : OpenMode.readWrite,
  );
  try {
    final kits = db
        .select(
          "SELECT entity_id, payload_json FROM entity_state WHERE entity_type = 'kits'",
        )
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row['payload_json'] as String) as Map,
          ),
        )
        .toList();
    final matches = kits
        .where(
          (kit) =>
              (kit['name'] as String? ?? '').toLowerCase().contains('positron'),
        )
        .toList();
    if (matches.length != 1) {
      stderr.writeln(
        'Expected one Positron kit; found ${matches.length}: ${matches.map((kit) => '${kit['id']} (${kit['name']})').join(', ')}',
      );
      exitCode = 2;
      return;
    }
    final kit = matches.single;
    final bom = (kit['bom'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final existingProductIds = bom.map((line) => line['productId']).toSet();
    final missing = _parts
        .where((part) => !existingProductIds.contains(part.productId))
        .toList();
    stdout.writeln(
      'Kit ${kit['id']} (${kit['name']}): ${bom.length} current BOM lines.',
    );
    stdout.writeln('${missing.length} official printed parts to add.');
    for (final part in missing) {
      stdout.writeln('  ${part.quantity}x ${part.name}');
    }
    if (hydrateThumbnails) {
      await _backupDatabase(db, databasePath);
      final restored = _hydrateThumbnails(db, _parts);
      stdout.writeln('Stored $restored Positron card thumbnails.');
      return;
    }
    if (zeroInventory) {
      await _backupDatabase(db, databasePath);
      final reset = _zeroInventory(db, _parts);
      stdout.writeln(
        'Set $reset Positron printed-part inventory quantities to 0.',
      );
      return;
    }
    if (dryRun) {
      final importedProductIds = _parts.map((part) => part.productId).toSet();
      final productCount =
          db
                  .select(
                    "SELECT count(*) AS count FROM entity_state WHERE entity_type = 'products' AND entity_id LIKE 'PROD-POSITRON-V32-PRINTED-%'",
                  )
                  .single['count']
              as int;
      final inventoryIds = _parts
          .map(
            (part) =>
                'INV-POSITRON-V32-PRINTED-${part.productId.substring('PROD-POSITRON-V32-PRINTED-'.length)}',
          )
          .toList();
      final imageCount = inventoryIds.isEmpty
          ? 0
          : db
                    .select(
                      'SELECT count(*) AS count FROM inventory_images WHERE entity_id IN (${List.filled(inventoryIds.length, '?').join(', ')}) AND image_bytes IS NOT NULL',
                      inventoryIds,
                    )
                    .single['count']
                as int;
      final typedInventoryCount = inventoryIds.isEmpty
          ? 0
          : db
                    .select(
                      "SELECT count(*) AS count FROM entity_state WHERE entity_type = 'inventory' AND entity_id IN (${List.filled(inventoryIds.length, '?').join(', ')}) AND json_extract(payload_json, '\$.type') = 'printedPart'",
                      inventoryIds,
                    )
                    .single['count']
                as int;
      final typedProductCount =
          db
                  .select(
                    "SELECT count(*) AS count FROM entity_state WHERE entity_type = 'products' AND entity_id LIKE 'PROD-POSITRON-V32-PRINTED-%' AND json_extract(payload_json, '\$.category') = 'printedPart'",
                  )
                  .single['count']
              as int;
      final zeroQuantityCount = inventoryIds.isEmpty
          ? 0
          : db
                    .select(
                      "SELECT count(*) AS count FROM entity_state WHERE entity_type = 'inventory' AND entity_id IN (${List.filled(inventoryIds.length, '?').join(', ')}) AND coalesce(json_extract(payload_json, '\$.quantity'), 1) = 0",
                      inventoryIds,
                    )
                    .single['count']
                as int;
      if (productCount != importedProductIds.length ||
          imageCount != importedProductIds.length ||
          typedInventoryCount != importedProductIds.length ||
          typedProductCount != importedProductIds.length ||
          zeroQuantityCount != importedProductIds.length) {
        throw StateError(
          'Expected ${importedProductIds.length} typed zero-quantity product records, typed inventory records, and images; found $typedProductCount products, $typedInventoryCount inventory records, $zeroQuantityCount zero-quantity records, and $imageCount images.',
        );
      }
      final thumbnailCount = inventoryIds.isEmpty
          ? 0
          : db
                    .select(
                      "SELECT count(*) AS count FROM entity_state WHERE entity_type = 'inventory' AND entity_id IN (${List.filled(inventoryIds.length, '?').join(', ')}) AND json_type(payload_json, '\$.thumbnail') IS NOT NULL",
                      inventoryIds,
                    )
                    .single['count']
                as int;
      if (thumbnailCount != importedProductIds.length) {
        throw StateError(
          'Expected ${importedProductIds.length} photo-card thumbnails; found $thumbnailCount.',
        );
      }
      stdout.writeln(
        'Verified $productCount printed-part records, $typedInventoryCount Printed part inventory types, $zeroQuantityCount zero-quantity inventory records, $imageCount stored images, and $thumbnailCount photo-card thumbnails.',
      );
      return;
    }

    final images = await _loadImages(missing);
    if (verifyImages) {
      stdout.writeln('Verified ${images.length} official guide images.');
      return;
    }
    await _backupDatabase(db, databasePath);
    _import(db, kit, missing, images);
    stdout.writeln(
      'Imported ${missing.length} Positron V3.2 printed parts, their images, and ${missing.length} kit BOM lines.',
    );
  } finally {
    db.close();
  }
}

Future<Map<String, Uint8List>> _loadImages(List<_GuidePart> parts) async {
  final byGuide = <String, List<_GuidePart>>{};
  for (final part in parts) {
    byGuide.putIfAbsent(part.guide, () => []).add(part);
  }
  final client = HttpClient();
  try {
    final images = <String, Uint8List>{};
    for (final entry in byGuide.entries) {
      final page = await _getText(client, Uri.parse('$_guideRoot${entry.key}'));
      for (final part in entry.value) {
        final imageUrl = _guideImageUrl(page, part);
        images[part.productId] = Uint8List.fromList(
          await _getBytes(client, Uri.parse(imageUrl)),
        );
        stdout.writeln('Fetched image: ${part.name}');
      }
    }
    return images;
  } finally {
    client.close(force: true);
  }
}

String _guideImageUrl(String page, _GuidePart part) {
  final expression = RegExp(
    r'\\"text\\":\\"' +
        RegExp.escape(part.printedGuideText) +
        r'\\".*?\\"url\\":\\"(https:[^\"]+?)\\"',
    dotAll: true,
  );
  final match = expression.firstMatch(page);
  if (match == null) {
    throw StateError(
      'Could not find the official guide image for ${part.name}.',
    );
  }
  return match.group(1)!.replaceAll(r'\/', '/');
}

Future<String> _getText(HttpClient client, Uri url) async {
  final response = await (await client.getUrl(url)).close();
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('GET $url returned ${response.statusCode}.');
  }
  return utf8.decode(
    await response.fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk)),
  );
}

Future<List<int>> _getBytes(HttpClient client, Uri url) async {
  final response = await (await client.getUrl(url)).close();
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('GET $url returned ${response.statusCode}.');
  }
  return response.fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
}

Future<void> _backupDatabase(Database db, String path) async {
  final integrity = db.select('PRAGMA integrity_check').single.values.single;
  if (integrity != 'ok') {
    throw StateError('Database integrity check failed: $integrity');
  }
  db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  final backup =
      '$path.pre-positron-v32-printed-parts-${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.bak';
  await File(path).copy(backup);
  stdout.writeln('Backup: $backup');
}

void _import(
  Database db,
  Map<String, dynamic> kit,
  List<_GuidePart> parts,
  Map<String, Uint8List> images,
) {
  final now = DateTime.now().toUtc().toIso8601String();
  final kitId = kit['id'] as String;
  final products = _entityPayloads(db, 'products');
  final productById = {
    for (final product in products) product['id'] as String: product,
  };
  final existingBom = (kit['bom'] as List<dynamic>? ?? const [])
      .cast<Map<String, dynamic>>();
  final firstCatalogProduct = existingBom
      .map((line) => productById[line['productId']])
      .whereType<Map<String, dynamic>>()
      .firstOrNull;
  final brandId = firstCatalogProduct?['brandId'] as String? ?? 'BR-LDO-MOTION';
  final machineIds = _entityPayloads(db, 'machines')
      .where(
        (machine) =>
            ((machine['kitIds'] as List<dynamic>? ?? const []).contains(kitId)),
      )
      .map((machine) => machine['id'] as String)
      .toList();
  final brand = _entityPayloads(
    db,
    'brands',
  ).where((value) => value['id'] == brandId).firstOrNull;

  db.execute('BEGIN IMMEDIATE');
  try {
    if (brand == null) {
      const vendorId = 'VEN-LDO-MOTION';
      if (_entityPayloads(
        db,
        'vendors',
      ).every((value) => value['id'] != vendorId)) {
        _queue(db, 'vendors', vendorId, {
          'id': vendorId,
          'name': 'LDO Motion',
          'isBrand': true,
          'logo': null,
          'archived': false,
        }, now);
      }
      _queue(db, 'brands', brandId, {
        'id': brandId,
        'name': 'LDO Motion',
        'vendorIds': [vendorId],
        'categories': ['printedPart'],
        'logo': null,
        'archived': false,
      }, now);
    }

    final nextBom = [...existingBom];
    final sections = <String>[
      ...((kit['sections'] as List<dynamic>? ?? const []).cast<String>()),
    ];
    for (final part in parts) {
      final image = images[part.productId]!;
      final thumbnail = _createThumbnail(image);
      final imageUrl = _guideImageUrlFor(part);
      final section = _sectionFor(part.guide);
      if (!sections.contains(section)) sections.add(section);
      _queue(db, 'products', part.productId, {
        'id': part.productId,
        'brandId': brandId,
        'category': 'printedPart',
        'name': part.name,
        'defaultCost': 0,
        'dryingMinutes': null,
        'printingInstructions':
            'Positron V3.2 printed part. Required quantity: ${part.quantity.toInt()}. See the official LDO assembly guide.',
        'dryingInstructions': '',
        'storageInstructions': 'Keep labeled with the LDO Positron V3.2 kit.',
        'sourceUrls': [_productGuide, imageUrl],
        'image': base64Encode(image),
      }, now);
      final inventoryId =
          'INV-POSITRON-V32-PRINTED-${part.productId.substring('PROD-POSITRON-V32-PRINTED-'.length)}';
      final inventory = _inventoryPayload(
        id: inventoryId,
        name: part.name,
        quantity: 0,
        productId: part.productId,
        machineIds: machineIds,
        now: now,
        image: image,
        thumbnail: thumbnail,
      );
      _queue(db, 'inventory', inventoryId, inventory, now);
      db.execute(
        '''INSERT INTO inventory_images(entity_id, image_bytes, label_image_bytes)
           VALUES (?, ?, NULL)
           ON CONFLICT(entity_id) DO UPDATE SET image_bytes = excluded.image_bytes''',
        [inventoryId, image],
      );
      nextBom.add({
        'id': '$kitId-PRINTED-${part.productId}',
        'productId': part.productId,
        'quantity': part.quantity,
        'name': part.name,
        'section': section,
      });
    }
    final sourceUrls = <String>[
      ...((kit['sourceUrls'] as List<dynamic>? ?? const []).cast<String>()),
    ];
    if (!sourceUrls.contains(_productGuide)) sourceUrls.add(_productGuide);
    _queue(db, 'kits', kitId, {
      'bom': nextBom,
      'sections': sections,
      'sourceUrls': sourceUrls,
    }, now);
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

List<Map<String, dynamic>> _entityPayloads(Database db, String type) => db
    .select('SELECT payload_json FROM entity_state WHERE entity_type = ?', [
      type,
    ])
    .map(
      (row) => Map<String, dynamic>.from(
        jsonDecode(row['payload_json'] as String) as Map,
      ),
    )
    .toList();

Map<String, dynamic> _inventoryPayload({
  required String id,
  required String name,
  required double quantity,
  required String productId,
  required List<String> machineIds,
  required String now,
  required Uint8List image,
  required Uint8List thumbnail,
}) => {
  'id': id,
  'name': name,
  'type': 'printedPart',
  'compatibility': ['LDO Positron V3.2 (Rev.A)'],
  'purposeTags': [],
  'styleEntries': [],
  'added': now,
  'cost': 0,
  'color': 4281545523,
  'itemColorName': '',
  'itemColorLabel': '',
  'quantity': quantity,
  'quantityAlertThreshold': null,
  'dryingMinutes': null,
  'dryingRemaining': null,
  'dryingStartedAt': null,
  'moistureLifespanMinutes': null,
  'moistureTimeUnit': 'days',
  'moistureAlertEnabled': false,
  'moistureAlertThresholdMinutes': null,
  'deployed': false,
  'vendor': 'LDO Motion',
  'printingInstructions':
      'Positron V3.2 printed part. Required quantity: ${quantity.toInt()}. See the official LDO assembly guide.',
  'dryingInstructions': '',
  'storageInstructions': 'Keep labeled with the LDO Positron V3.2 kit.',
  'archived': false,
  'archiveDisposition': 'archived',
  'filamentStatus': 'ready',
  'brand': 'LDO Motion',
  'storageLocation': '',
  'storageLocationId': '',
  'locationHistory': [],
  'deploymentLocation': '',
  'lastDriedAt': null,
  'image': base64Encode(image),
  'thumbnail': base64Encode(thumbnail),
  'labelImage': null,
  'barcode': '',
  'productUrl': _productGuide,
  'compatibleMachineIds': machineIds,
  'spoolTypeId': '',
  'filamentWeightGrams': null,
  'amsCompatible': false,
  'spoolTareWeightGrams': null,
  'spoolOuterDiameterMm': null,
  'spoolWidthMm': null,
  'spoolHoleDiameterMm': null,
  'refill': false,
  'masterSpool': '',
  'catalogProductId': productId,
  'customTypeId': '',
  'customTypeName': '',
  'customFieldValues': {},
  'materialId': '',
  'materialName': '',
  'spoolMaterialId': '',
  'spoolMaterialName': '',
  'masterSpoolMaterialId': '',
  'masterSpoolMaterialName': '',
};

void _queue(
  Database db,
  String type,
  String id,
  Map<String, dynamic> fields,
  String now,
) {
  final entity = db.select(
    'SELECT payload_json, remote_revision FROM entity_state WHERE entity_type = ? AND entity_id = ?',
    [type, id],
  );
  final previous = entity.isEmpty
      ? <String, dynamic>{}
      : Map<String, dynamic>.from(
          jsonDecode(entity.single['payload_json'] as String) as Map,
        );
  final next = {...previous, ...fields};
  next['id'] = id;
  if (type == 'inventory') {
    next
      ..remove('image')
      ..remove('labelImage');
  }
  final queued = db.select(
    'SELECT fields_json, deleted, base_json FROM sync_outbox WHERE entity_type = ? AND entity_id = ?',
    [type, id],
  );
  final outgoing = queued.isNotEmpty && queued.single['deleted'] != 1
      ? Map<String, dynamic>.from(
          jsonDecode(queued.single['fields_json'] as String) as Map,
        )
      : <String, dynamic>{};
  outgoing.addAll(fields);
  final base = queued.isNotEmpty
      ? Map<String, dynamic>.from(
          jsonDecode(queued.single['base_json'] as String) as Map,
        )
      : <String, dynamic>{};
  final remoteRevision = entity.isEmpty
      ? null
      : entity.single['remote_revision'] as int?;
  if (remoteRevision != null) {
    base.putIfAbsent('(remoteRevision)', () => remoteRevision);
  }
  for (final key in fields.keys) {
    if (type == 'inventory' && key == 'modifiedAt') continue;
    base.putIfAbsent(key, () => previous[key]);
  }
  final revisionRow = db.select(
    'SELECT next_revision FROM sync_local_revisions WHERE id = 1',
  );
  final localRevision = revisionRow.isEmpty
      ? 1
      : revisionRow.single['next_revision'] as int;
  db.execute(
    'INSERT INTO sync_local_revisions(id, next_revision) VALUES(1, ?) ON CONFLICT(id) DO UPDATE SET next_revision = excluded.next_revision',
    [localRevision + 1],
  );
  db.execute(
    '''INSERT INTO entity_state(entity_type, entity_id, payload_json, remote_revision)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(entity_type, entity_id) DO UPDATE SET payload_json = excluded.payload_json''',
    [type, id, jsonEncode(next), remoteRevision],
  );
  db.execute(
    '''INSERT INTO sync_outbox(entity_type, entity_id, fields_json, deleted, created_at, local_revision, base_json)
       VALUES (?, ?, ?, 0, ?, ?, ?)
       ON CONFLICT(entity_type, entity_id) DO UPDATE SET
         fields_json = excluded.fields_json, deleted = 0, created_at = excluded.created_at,
         local_revision = excluded.local_revision, base_json = excluded.base_json''',
    [type, id, jsonEncode(outgoing), now, localRevision, jsonEncode(base)],
  );
}

Uint8List _createThumbnail(Uint8List source) {
  try {
    final decoded = img.decodeImage(source);
    if (decoded == null) return source;
    const maximumEdge = 360;
    final scale = maximumEdge / math.max(decoded.width, decoded.height);
    final resized = scale < 1
        ? img.copyResize(
            decoded,
            width: math.max(1, (decoded.width * scale).round()),
            height: math.max(1, (decoded.height * scale).round()),
            interpolation: img.Interpolation.average,
          )
        : decoded;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  } catch (_) {
    // Flutter's image codec can render a few WebP alpha encodings that the
    // lightweight thumbnail decoder cannot. Keep the original instead of
    // silently withholding a photo card.
    return source;
  }
}

int _hydrateThumbnails(Database db, Iterable<_GuidePart> parts) {
  final now = DateTime.now().toUtc().toIso8601String();
  var hydrated = 0;
  db.execute('BEGIN IMMEDIATE');
  try {
    for (final part in parts) {
      final suffix = part.productId.substring(
        'PROD-POSITRON-V32-PRINTED-'.length,
      );
      final inventoryId = 'INV-POSITRON-V32-PRINTED-$suffix';
      final source = db.select(
        'SELECT image_bytes FROM inventory_images WHERE entity_id = ?',
        [inventoryId],
      );
      if (source.isEmpty || source.single['image_bytes'] == null) {
        throw StateError('Missing full image for ${part.name}.');
      }
      final thumbnail = _createThumbnail(
        source.single['image_bytes'] as Uint8List,
      );
      _queue(db, 'inventory', inventoryId, {
        'thumbnail': base64Encode(thumbnail),
      }, now);
      hydrated++;
    }
    db.execute('COMMIT');
    return hydrated;
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

int _zeroInventory(Database db, Iterable<_GuidePart> parts) {
  final now = DateTime.now().toUtc().toIso8601String();
  var reset = 0;
  db.execute('BEGIN IMMEDIATE');
  try {
    for (final part in parts) {
      final suffix = part.productId.substring(
        'PROD-POSITRON-V32-PRINTED-'.length,
      );
      final inventoryId = 'INV-POSITRON-V32-PRINTED-$suffix';
      final row = db.select(
        'SELECT payload_json FROM entity_state WHERE entity_type = ? AND entity_id = ?',
        ['inventory', inventoryId],
      );
      if (row.isEmpty) {
        throw StateError('Missing imported inventory record for ${part.name}.');
      }
      final payload = Map<String, dynamic>.from(
        jsonDecode(row.single['payload_json'] as String) as Map,
      );
      if ((payload['quantity'] as num?)?.toDouble() == 0) continue;
      _queue(db, 'inventory', inventoryId, {'quantity': 0}, now);
      reset++;
    }
    db.execute('COMMIT');
    return reset;
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

String _guideImageUrlFor(_GuidePart part) =>
    '$_guideRoot${part.guide}#${Uri.encodeComponent(part.printedGuideText)}';

String _sectionFor(String guide) => switch (guide) {
  '1---positron-v32---extruder' => 'Printed parts — Extruder',
  '2---positron-v32---z-column' => 'Printed parts — Z Column',
  '3---positron-v32---z-drive' => 'Printed parts — Z Drive',
  '4---positron-v32---bed-v-holder' => 'Printed parts — Bed V Holder',
  '5---positron-v32---touch-panel' => 'Printed parts — Touch Panel',
  '6---positron-v32---toolhead' => 'Printed parts — Toolhead',
  '7---positron-v32---spool-holder' => 'Printed parts — Spool Holder',
  '8---positron-v32---base-plate' => 'Printed parts — Base Plate',
  _ => 'Printed parts — Final Assembly',
};
