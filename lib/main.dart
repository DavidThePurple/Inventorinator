import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'local_database.dart';
import 'label_ocr.dart';
import 'qr_scanner.dart';
import 'cloud_sync_dialog.dart';
import 'supabase_sync.dart';
import 'sync_onboarding_dialog.dart';
import 'workshop_merge.dart';

String _normalizedStockName(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await LocalDatabase.open();
  runApp(
    InventorinatorApp(database: database, persistedState: database.loadState()),
  );
}

enum InventoryType {
  other,
  fastener,
  filament,
  printedPart,
  resin,
  nozzle,
  heatBreak,
  heatBlock,
  sock,
  custom,
}

extension InventoryTypeContext on InventoryType {
  bool get supportsDrying => this == InventoryType.filament;
  bool get supportsPrinting =>
      this == InventoryType.filament || this == InventoryType.printedPart;
  bool get supportsFilamentLifecycle => this == InventoryType.filament;
}

enum InventorySort { type, age, cost, dryingTime, moistureRemaining }

enum CatalogViewFilter { kits, builds, machines, printers, tools }

enum FilamentStatus { ready, deployed, drying, queuedForDrying }

enum ArchiveDisposition { archived, depleted, destroyed }

enum ProductSearchProvider { google, bing, duckDuckGo, brave, custom }

enum MoistureTimeUnit { hours, days }

String _searchProviderLabel(ProductSearchProvider provider) =>
    switch (provider) {
      ProductSearchProvider.google => 'Google',
      ProductSearchProvider.bing => 'Bing',
      ProductSearchProvider.duckDuckGo => 'DuckDuckGo',
      ProductSearchProvider.brave => 'Brave Search',
      ProductSearchProvider.custom => 'Custom',
    };

enum ItemAction { resetDryTimer, edit, duplicate, archive, delete }

enum DebugCardEffect { remoteQuantity, lowStock, moistureThreshold }

class VendorRecord {
  const VendorRecord({
    required this.id,
    required this.name,
    this.isBrand = false,
    this.logoBytes,
  });
  final String id;
  final String name;
  final bool isBrand;
  final Uint8List? logoBytes;
}

class BrandRecord {
  const BrandRecord({
    required this.id,
    required this.name,
    required this.vendorIds,
    required this.categories,
    this.logoBytes,
  });
  final String id;
  final String name;
  final Set<String> vendorIds;
  final Set<InventoryType> categories;
  final Uint8List? logoBytes;
}

class SpoolTypeRecord {
  const SpoolTypeRecord({
    required this.id,
    required this.label,
    required this.weightGrams,
  });
  final String id;
  final String label;
  final int weightGrams;
}

class CustomItemTypeRecord {
  const CustomItemTypeRecord({
    required this.id,
    required this.name,
    this.contextualFields = const [],
  });
  final String id;
  final String name;
  final List<String> contextualFields;
}

const defaultSpoolTypeId = 'SPOOL-1000G';
const starterSpoolTypes = <SpoolTypeRecord>[
  SpoolTypeRecord(id: 'SPOOL-250G', label: '.250 kg', weightGrams: 250),
  SpoolTypeRecord(id: 'SPOOL-500G', label: '.5 kg', weightGrams: 500),
  SpoolTypeRecord(id: 'SPOOL-750G', label: '.750 kg', weightGrams: 750),
  SpoolTypeRecord(id: defaultSpoolTypeId, label: '1 kg', weightGrams: 1000),
  SpoolTypeRecord(id: 'SPOOL-3000G', label: '3 kg', weightGrams: 3000),
  SpoolTypeRecord(id: 'SPOOL-5000G', label: '5 kg', weightGrams: 5000),
];

class MachineTypeRecord {
  const MachineTypeRecord({
    required this.id,
    required this.name,
    this.parentId,
  });
  final String id;
  final String name;
  final String? parentId;
}

class MachineRecord {
  const MachineRecord({
    required this.id,
    required this.name,
    required this.model,
    required this.address,
    required this.typeId,
    this.kitIds = const {},
  });
  final String id;
  final String name;
  final String model;
  final String address;
  final String typeId;
  final Set<String> kitIds;
}

class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.brandId,
    required this.category,
    required this.name,
    this.defaultCost = 0,
    this.dryingMinutes,
    this.printingInstructions = '',
    this.dryingInstructions = '',
    this.storageInstructions = '',
    this.imageBytes,
  });
  final String id;
  final String brandId;
  final InventoryType category;
  final String name;
  final double defaultCost;
  final int? dryingMinutes;
  final String printingInstructions;
  final String dryingInstructions;
  final String storageInstructions;
  final Uint8List? imageBytes;
}

class KitBomEntry {
  const KitBomEntry({
    this.id = '',
    required this.productId,
    required this.quantity,
    this.name,
    this.section = 'Unassigned',
  });
  final String id;
  final String productId;
  final double quantity;
  final String? name;
  final String section;
}

class KitRecord {
  const KitRecord({
    required this.id,
    required this.name,
    required this.bom,
    this.sections = const [],
  });
  final String id;
  final String name;
  final List<KitBomEntry> bom;
  final List<String> sections;
}

class BuildLine {
  const BuildLine({
    required this.id,
    required this.productId,
    required this.name,
    required this.section,
    required this.requiredQuantity,
    this.usedQuantity = 0,
    this.consumedInventoryIds = const [],
  });
  final String id;
  final String productId;
  final String name;
  final String section;
  final double requiredQuantity;
  final double usedQuantity;
  final List<String> consumedInventoryIds;

  BuildLine copyWith({
    double? usedQuantity,
    List<String>? consumedInventoryIds,
  }) => BuildLine(
    id: id,
    productId: productId,
    name: name,
    section: section,
    requiredQuantity: requiredQuantity,
    usedQuantity: usedQuantity ?? this.usedQuantity,
    consumedInventoryIds: consumedInventoryIds ?? this.consumedInventoryIds,
  );
}

class _LineStockStatus {
  const _LineStockStatus({required this.available, required this.missing});

  final double available;
  final double missing;

  bool get isMissing => missing > 0.0001;
}

class BuildRecord {
  BuildRecord({
    required this.id,
    required this.kitId,
    required this.name,
    required this.createdAt,
    required this.createdBy,
    required this.lines,
    this.ownerDeviceId = '',
    this.ownerUserId,
    this.shared = false,
    this.completedAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;
  final String id;
  final String kitId;
  final String name;
  final DateTime createdAt;
  final String createdBy;
  final List<BuildLine> lines;
  final String ownerDeviceId;
  final String? ownerUserId;
  bool shared;
  DateTime? completedAt;
  DateTime updatedAt;
}

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.timestamp,
    required this.actor,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.changes,
  });
  final String id;
  final DateTime timestamp;
  final String actor;
  final String action;
  final String entityType;
  final String entityId;
  final Map<String, String> changes;
}

class RapidItemDraft {
  const RapidItemDraft({
    required this.name,
    required this.type,
    required this.quantity,
    required this.price,
  });
  final String name;
  final InventoryType type;
  final double quantity;
  final double price;
}

class RapidizerParseResult {
  const RapidizerParseResult({required this.items, required this.errors});
  final List<RapidItemDraft> items;
  final List<String> errors;
  bool get isValid => items.isNotEmpty && errors.isEmpty;
}

class AdditionHistoryEntry {
  const AdditionHistoryEntry({
    required this.id,
    required this.itemId,
    required this.name,
    required this.type,
    required this.addedAt,
    required this.deviceName,
  });
  final String id;
  final String itemId;
  final String name;
  final InventoryType type;
  final DateTime addedAt;
  final String deviceName;

  factory AdditionHistoryEntry.fromItem(
    InventoryItem item, {
    String deviceName = 'Unknown device (predates tracking)',
  }) => AdditionHistoryEntry(
    id: 'ADD-${item.id}',
    itemId: item.id,
    name: item.name,
    type: item.type,
    addedAt: item.added,
    deviceName: deviceName,
  );
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.type,
    required this.compatibility,
    required this.added,
    required this.cost,
    required this.color,
    this.quantity = 1,
    this.quantityAlertThreshold,
    this.dryingMinutes,
    this.dryingRemaining,
    this.dryingStartedAt,
    this.moistureLifespanMinutes,
    this.moistureTimeUnit = MoistureTimeUnit.days,
    this.moistureAlertEnabled = false,
    this.moistureAlertThresholdMinutes,
    this.deployed = false,
    this.vendor = '',
    this.printingInstructions = '',
    this.dryingInstructions = '',
    this.storageInstructions = '',
    this.archived = false,
    this.archiveDisposition = ArchiveDisposition.archived,
    this.filamentStatus = FilamentStatus.ready,
    this.brand = '',
    this.storageLocation = '',
    this.deploymentLocation = '',
    this.lastDriedAt,
    this.imageBytes,
    this.labelImageBytes,
    this.barcode = '',
    this.productUrl = '',
    this.compatibleMachineIds = const [],
    this.spoolTypeId = defaultSpoolTypeId,
    this.amsCompatible = false,
    this.catalogProductId,
    this.customTypeId = '',
    this.customTypeName = '',
    this.customFieldValues = const {},
  });
  final String id;
  final String name;
  final InventoryType type;
  final List<String> compatibility;
  final DateTime added;
  final double cost;
  final Color color;
  final double quantity;
  final double? quantityAlertThreshold;
  final int? dryingMinutes;
  final int? dryingRemaining;
  final DateTime? dryingStartedAt;
  final int? moistureLifespanMinutes;
  final MoistureTimeUnit moistureTimeUnit;
  final bool moistureAlertEnabled;
  final int? moistureAlertThresholdMinutes;
  final bool deployed;
  final String vendor;
  final String printingInstructions;
  final String dryingInstructions;
  final String storageInstructions;
  final bool archived;
  final ArchiveDisposition archiveDisposition;
  final FilamentStatus filamentStatus;
  final String brand;
  final String storageLocation;
  final String deploymentLocation;
  final DateTime? lastDriedAt;
  final Uint8List? imageBytes;
  final Uint8List? labelImageBytes;
  final String barcode;
  final String productUrl;
  final List<String> compatibleMachineIds;
  final String spoolTypeId;
  final bool amsCompatible;
  final String? catalogProductId;
  final String customTypeId;
  final String customTypeName;
  final Map<String, String> customFieldValues;

  InventoryItem copyWith({
    String? id,
    String? name,
    InventoryType? type,
    List<String>? compatibility,
    DateTime? added,
    double? cost,
    Color? color,
    double? quantity,
    double? quantityAlertThreshold,
    int? dryingMinutes,
    int? dryingRemaining,
    DateTime? dryingStartedAt,
    int? moistureLifespanMinutes,
    MoistureTimeUnit? moistureTimeUnit,
    bool? moistureAlertEnabled,
    int? moistureAlertThresholdMinutes,
    bool? deployed,
    String? vendor,
    String? printingInstructions,
    String? dryingInstructions,
    String? storageInstructions,
    bool? archived,
    ArchiveDisposition? archiveDisposition,
    FilamentStatus? filamentStatus,
    String? brand,
    String? storageLocation,
    String? deploymentLocation,
    DateTime? lastDriedAt,
    Uint8List? imageBytes,
    Uint8List? labelImageBytes,
    String? barcode,
    String? productUrl,
    List<String>? compatibleMachineIds,
    String? spoolTypeId,
    bool? amsCompatible,
    String? catalogProductId,
    String? customTypeId,
    String? customTypeName,
    Map<String, String>? customFieldValues,
  }) => InventoryItem(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    compatibility: compatibility ?? this.compatibility,
    added: added ?? this.added,
    cost: cost ?? this.cost,
    color: color ?? this.color,
    quantity: quantity ?? this.quantity,
    quantityAlertThreshold:
        quantityAlertThreshold ?? this.quantityAlertThreshold,
    dryingMinutes: dryingMinutes ?? this.dryingMinutes,
    dryingRemaining: dryingRemaining ?? this.dryingRemaining,
    dryingStartedAt: dryingStartedAt ?? this.dryingStartedAt,
    moistureLifespanMinutes:
        moistureLifespanMinutes ?? this.moistureLifespanMinutes,
    moistureTimeUnit: moistureTimeUnit ?? this.moistureTimeUnit,
    moistureAlertEnabled: moistureAlertEnabled ?? this.moistureAlertEnabled,
    moistureAlertThresholdMinutes:
        moistureAlertThresholdMinutes ?? this.moistureAlertThresholdMinutes,
    deployed: deployed ?? this.deployed,
    vendor: vendor ?? this.vendor,
    printingInstructions: printingInstructions ?? this.printingInstructions,
    dryingInstructions: dryingInstructions ?? this.dryingInstructions,
    storageInstructions: storageInstructions ?? this.storageInstructions,
    archived: archived ?? this.archived,
    archiveDisposition: archiveDisposition ?? this.archiveDisposition,
    filamentStatus: filamentStatus ?? this.filamentStatus,
    brand: brand ?? this.brand,
    storageLocation: storageLocation ?? this.storageLocation,
    deploymentLocation: deploymentLocation ?? this.deploymentLocation,
    lastDriedAt: lastDriedAt ?? this.lastDriedAt,
    imageBytes: imageBytes ?? this.imageBytes,
    labelImageBytes: labelImageBytes ?? this.labelImageBytes,
    barcode: barcode ?? this.barcode,
    productUrl: productUrl ?? this.productUrl,
    compatibleMachineIds: compatibleMachineIds ?? this.compatibleMachineIds,
    spoolTypeId: spoolTypeId ?? this.spoolTypeId,
    amsCompatible: amsCompatible ?? this.amsCompatible,
    catalogProductId: catalogProductId ?? this.catalogProductId,
    customTypeId: customTypeId ?? this.customTypeId,
    customTypeName: customTypeName ?? this.customTypeName,
    customFieldValues: customFieldValues ?? this.customFieldValues,
  );
  String get typeLabel =>
      type == InventoryType.custom && customTypeName.isNotEmpty
      ? customTypeName
      : switch (type) {
          InventoryType.other => 'Other',
          InventoryType.fastener => 'Fastener',
          InventoryType.filament => 'Filament',
          InventoryType.printedPart => 'Printed part',
          InventoryType.resin => 'Resin',
          InventoryType.nozzle => 'Nozzle',
          InventoryType.heatBreak => 'Heat break',
          InventoryType.heatBlock => 'Heat block',
          InventoryType.sock => 'Silicone sock',
          InventoryType.custom => 'Custom',
        };
  IconData get icon => switch (type) {
    InventoryType.other => Icons.inventory_2_outlined,
    InventoryType.fastener => Icons.hardware_rounded,
    InventoryType.filament => Icons.donut_large_rounded,
    InventoryType.printedPart => Icons.view_in_ar_outlined,
    InventoryType.resin => Icons.opacity_rounded,
    InventoryType.nozzle => Icons.change_history_rounded,
    InventoryType.heatBreak => Icons.compress_rounded,
    InventoryType.heatBlock => Icons.view_in_ar_rounded,
    InventoryType.sock => Icons.shield_outlined,
    InventoryType.custom => Icons.tune_rounded,
  };
}

bool replaceInventoryItemById(
  List<InventoryItem> inventory,
  String itemId,
  InventoryItem replacement,
) {
  final index = inventory.indexWhere((candidate) => candidate.id == itemId);
  if (index < 0) return false;
  inventory[index] = replacement;
  return true;
}

final sampleInventory = <InventoryItem>[
  InventoryItem(
    id: 'INV-FIL-0001',
    name: 'Galaxy Black PETG',
    type: InventoryType.filament,
    compatibility: const ['1.75 mm', 'E3D V6'],
    added: DateTime(2026, 7, 2),
    cost: 24.99,
    color: const Color(0xff7455ff),
    dryingMinutes: 360,
    dryingRemaining: 82,
    filamentStatus: FilamentStatus.drying,
    brand: 'Polymaker',
    storageLocation: 'Dry box 1',
    lastDriedAt: DateTime(2026, 8, 12),
    vendor: 'Polymaker',
    printingInstructions:
        'Nozzle 230–250°C · Bed 70–80°C. Use moderate cooling.',
    dryingInstructions: 'Dry at 65°C for 6 hours before demanding prints.',
    storageInstructions: 'Store sealed with fresh desiccant below 20% RH.',
  ),
  InventoryItem(
    id: 'INV-NOZ-0001',
    name: 'ObXidian 0.4 mm',
    type: InventoryType.nozzle,
    compatibility: const ['E3D V6', 'Revo'],
    added: DateTime(2026, 4, 18),
    cost: 44.90,
    color: const Color(0xffffb13b),
    deployed: true,
    vendor: 'E3D',
    printingInstructions:
        'Suitable for abrasive polymers. Verify Z offset after installation.',
    storageInstructions:
        'Clean cold and store in the labeled nozzle organizer.',
  ),
  InventoryItem(
    id: 'INV-HBR-0001',
    name: 'Titanium heat break',
    type: InventoryType.heatBreak,
    compatibility: const ['E3D V6'],
    added: DateTime(2025, 11, 9),
    cost: 17.50,
    color: const Color(0xff45d2bd),
    deployed: true,
    vendor: 'E3D',
    printingInstructions:
        'Apply thermal compound only to the cold-side threads.',
    storageInstructions: 'Protect the thin throat from impact and bending.',
  ),
  InventoryItem(
    id: 'INV-HBL-0001',
    name: 'Copper heater block',
    type: InventoryType.heatBlock,
    compatibility: const ['E3D V6', '24 V'],
    added: DateTime(2026, 6, 21),
    cost: 21.00,
    color: const Color(0xffff6b6b),
    vendor: 'E3D',
    printingInstructions:
        'Hot-tighten the nozzle against the heat break, not the block.',
    storageInstructions: 'Keep heater and thermistor bores clean and capped.',
  ),
  InventoryItem(
    id: 'INV-SCK-0001',
    name: 'V6 sock — 3 pack',
    type: InventoryType.sock,
    compatibility: const ['E3D V6'],
    added: DateTime(2026, 8, 4),
    cost: 8.99,
    color: const Color(0xff55a8ff),
    vendor: 'E3D',
    storageInstructions: 'Store flat; discard if torn or contaminated.',
  ),
  InventoryItem(
    id: 'INV-FIL-0002',
    name: 'Bone White PLA',
    type: InventoryType.filament,
    compatibility: const ['1.75 mm'],
    added: DateTime(2026, 8, 11),
    cost: 19.95,
    color: const Color(0xffd5cbb7),
    dryingMinutes: 240,
    dryingRemaining: 0,
    filamentStatus: FilamentStatus.ready,
    brand: 'Overture',
    storageLocation: 'Shelf A · Bin 3',
    lastDriedAt: DateTime(2026, 8, 21),
    vendor: 'Overture',
    printingInstructions: 'Nozzle 190–220°C · Bed 45–60°C.',
    dryingInstructions: 'Dry at 50°C for 4 hours when brittle or stringing.',
    storageInstructions: 'Store sealed with desiccant below 20% RH.',
  ),
  InventoryItem(
    id: 'INV-NOZ-0002',
    name: 'Brass 0.6 mm',
    type: InventoryType.nozzle,
    compatibility: const ['E3D V6'],
    added: DateTime(2024, 9, 14),
    cost: 7.49,
    color: const Color(0xffd59a3a),
    vendor: 'Generic',
    printingInstructions:
        'Use for non-abrasive materials. Hot-tighten after installation.',
    storageInstructions: 'Clean and return to the 0.6 mm compartment.',
  ),
];

final starterVendors = <VendorRecord>[
  const VendorRecord(id: 'VEN-POLYMAKER', name: 'Polymaker', isBrand: true),
  const VendorRecord(
    id: 'VEN-PRINTED-SOLID',
    name: 'Printed Solid',
    isBrand: true,
  ),
  const VendorRecord(
    id: 'VEN-MATTERHACKERS',
    name: 'MatterHackers',
    isBrand: true,
  ),
  const VendorRecord(id: 'VEN-AMAZON', name: 'Amazon'),
  const VendorRecord(id: 'VEN-EBAY', name: 'eBay'),
];

final starterBrands = <BrandRecord>[
  const BrandRecord(
    id: 'BR-POLYMAKER',
    name: 'Polymaker',
    vendorIds: {'VEN-POLYMAKER', 'VEN-PRINTED-SOLID', 'VEN-MATTERHACKERS'},
    categories: {InventoryType.filament},
  ),
  const BrandRecord(
    id: 'BR-PRINTED-SOLID',
    name: 'Printed Solid',
    vendorIds: {'VEN-PRINTED-SOLID'},
    categories: {InventoryType.filament},
  ),
  const BrandRecord(
    id: 'BR-MATTERHACKERS',
    name: 'MatterHackers',
    vendorIds: {'VEN-MATTERHACKERS'},
    categories: {InventoryType.filament, InventoryType.resin},
  ),
  const BrandRecord(
    id: 'BR-E3D',
    name: 'E3D',
    vendorIds: {'VEN-PRINTED-SOLID'},
    categories: {
      InventoryType.nozzle,
      InventoryType.heatBreak,
      InventoryType.heatBlock,
      InventoryType.sock,
    },
  ),
];

final starterProducts = <CatalogProduct>[
  const CatalogProduct(
    id: 'PROD-POLYLITE-PLA',
    brandId: 'BR-POLYMAKER',
    category: InventoryType.filament,
    name: 'PolyLite PLA',
    defaultCost: 24.99,
    dryingMinutes: 360,
    printingInstructions: 'Nozzle 190–230°C · Bed 25–60°C.',
    dryingInstructions: 'Dry at 55°C for 6 hours.',
    storageInstructions: 'Store sealed with desiccant below 20% RH.',
  ),
  const CatalogProduct(
    id: 'PROD-E3D-OBXIDIAN-04',
    brandId: 'BR-E3D',
    category: InventoryType.nozzle,
    name: 'ObXidian 0.4 mm',
    defaultCost: 44.90,
    printingInstructions: 'Suitable for abrasive polymers. Verify Z offset.',
    storageInstructions: 'Clean cold and store in the nozzle organizer.',
  ),
];

int _nextInventoryId = 1;
String _newInventoryId() =>
    'INV-${DateTime.now().microsecondsSinceEpoch}-${_nextInventoryId++}';

typedef WorkshopState = ({
  List<InventoryItem> inventory,
  List<VendorRecord> vendors,
  List<BrandRecord> brands,
  List<SpoolTypeRecord> spoolTypes,
  List<CustomItemTypeRecord> customItemTypes,
  List<CatalogProduct> products,
  List<MachineTypeRecord> machineTypes,
  List<MachineRecord> machines,
  List<KitRecord> kits,
  List<BuildRecord> builds,
  List<AuditEntry> auditLog,
  List<AdditionHistoryEntry> additionHistory,
  int historyLimit,
});

String? _bytesToJson(Uint8List? bytes) =>
    bytes == null ? null : base64Encode(bytes);
Uint8List? _bytesFromJson(Object? value) =>
    value is String && value.isNotEmpty ? base64Decode(value) : null;

bool _looksLikeFastener(String name) =>
    !name.toLowerCase().contains('printed part') &&
    RegExp(
      r'\b(screws?|bolts?|nuts?|washers?|spacers?|rivets?|clips?|zip[ -]?ties?|threaded inserts?)\b',
      caseSensitive: false,
    ).hasMatch(name);

InventoryType _migratedInventoryType(String storedType, String name) {
  final type = InventoryType.values.byName(storedType);
  if (type == InventoryType.other &&
      name.toLowerCase().contains('printed part')) {
    return InventoryType.printedPart;
  }
  return type == InventoryType.other && _looksLikeFastener(name)
      ? InventoryType.fastener
      : type;
}

String encodeWorkshopState({
  required List<InventoryItem> inventory,
  required List<VendorRecord> vendors,
  required List<BrandRecord> brands,
  List<SpoolTypeRecord> spoolTypes = starterSpoolTypes,
  List<CustomItemTypeRecord> customItemTypes = const [],
  required List<CatalogProduct> products,
  List<MachineTypeRecord> machineTypes = const [],
  List<MachineRecord> machines = const [],
  List<KitRecord> kits = const [],
  List<BuildRecord> builds = const [],
  List<AuditEntry> auditLog = const [],
  List<AdditionHistoryEntry> additionHistory = const [],
  int historyLimit = 100,
}) => jsonEncode({
  'schemaVersion': 3,
  'inventory': inventory
      .map(
        (item) => {
          'id': item.id,
          'name': item.name,
          'type': item.type.name,
          'compatibility': item.compatibility,
          'added': item.added.toIso8601String(),
          'cost': item.cost,
          'color': item.color.toARGB32(),
          'quantity': item.quantity,
          'quantityAlertThreshold': item.quantityAlertThreshold,
          'dryingMinutes': item.dryingMinutes,
          'dryingRemaining': item.dryingRemaining,
          'dryingStartedAt': item.dryingStartedAt?.toIso8601String(),
          'moistureLifespanMinutes': item.moistureLifespanMinutes,
          'moistureTimeUnit': item.moistureTimeUnit.name,
          'moistureAlertEnabled': item.moistureAlertEnabled,
          'moistureAlertThresholdMinutes': item.moistureAlertThresholdMinutes,
          'deployed': item.deployed,
          'vendor': item.vendor,
          'printingInstructions': item.printingInstructions,
          'dryingInstructions': item.dryingInstructions,
          'storageInstructions': item.storageInstructions,
          'archived': item.archived,
          'archiveDisposition': item.archiveDisposition.name,
          'filamentStatus': item.filamentStatus.name,
          'brand': item.brand,
          'storageLocation': item.storageLocation,
          'deploymentLocation': item.deploymentLocation,
          'lastDriedAt': item.lastDriedAt?.toIso8601String(),
          'image': _bytesToJson(item.imageBytes),
          'labelImage': _bytesToJson(item.labelImageBytes),
          'barcode': item.barcode,
          'productUrl': item.productUrl,
          'compatibleMachineIds': item.compatibleMachineIds,
          'spoolTypeId': item.spoolTypeId,
          'amsCompatible': item.amsCompatible,
          'catalogProductId': item.catalogProductId,
          'customTypeId': item.customTypeId,
          'customTypeName': item.customTypeName,
          'customFieldValues': item.customFieldValues,
        },
      )
      .toList(),
  'customItemTypes': customItemTypes
      .map(
        (type) => {
          'id': type.id,
          'name': type.name,
          'contextualFields': type.contextualFields,
        },
      )
      .toList(),
  'machineTypes': machineTypes
      .map(
        (type) => {'id': type.id, 'name': type.name, 'parentId': type.parentId},
      )
      .toList(),
  'machines': machines
      .map(
        (machine) => {
          'id': machine.id,
          'name': machine.name,
          'model': machine.model,
          'address': machine.address,
          'typeId': machine.typeId,
          'kitIds': machine.kitIds.toList(),
        },
      )
      .toList(),
  'kits': kits
      .map(
        (kit) => {
          'id': kit.id,
          'name': kit.name,
          'sections': kit.sections,
          'bom': kit.bom
              .map(
                (entry) => {
                  'id': entry.id,
                  'productId': entry.productId,
                  'quantity': entry.quantity,
                  if (entry.name != null) 'name': entry.name,
                  'section': entry.section,
                },
              )
              .toList(),
        },
      )
      .toList(),
  'builds': builds
      .map(
        (build) => {
          'id': build.id,
          'kitId': build.kitId,
          'name': build.name,
          'createdAt': build.createdAt.toIso8601String(),
          'createdBy': build.createdBy,
          'ownerDeviceId': build.ownerDeviceId,
          if (build.ownerUserId != null) 'ownerUserId': build.ownerUserId,
          'shared': build.shared,
          if (build.completedAt != null)
            'completedAt': build.completedAt!.toIso8601String(),
          'updatedAt': build.updatedAt.toIso8601String(),
          'lines': build.lines
              .map(
                (line) => {
                  'id': line.id,
                  'productId': line.productId,
                  'name': line.name,
                  'section': line.section,
                  'requiredQuantity': line.requiredQuantity,
                  'usedQuantity': line.usedQuantity,
                  'consumedInventoryIds': line.consumedInventoryIds,
                },
              )
              .toList(),
        },
      )
      .toList(),
  'auditLog': auditLog
      .map(
        (entry) => {
          'id': entry.id,
          'timestamp': entry.timestamp.toIso8601String(),
          'actor': entry.actor,
          'action': entry.action,
          'entityType': entry.entityType,
          'entityId': entry.entityId,
          'changes': entry.changes,
        },
      )
      .toList(),
  'vendors': vendors
      .map(
        (vendor) => {
          'id': vendor.id,
          'name': vendor.name,
          'isBrand': vendor.isBrand,
          'logo': _bytesToJson(vendor.logoBytes),
        },
      )
      .toList(),
  'brands': brands
      .map(
        (brand) => {
          'id': brand.id,
          'name': brand.name,
          'vendorIds': brand.vendorIds.toList(),
          'categories': brand.categories.map((type) => type.name).toList(),
          'logo': _bytesToJson(brand.logoBytes),
        },
      )
      .toList(),
  'spoolTypes': spoolTypes
      .map(
        (spool) => {
          'id': spool.id,
          'label': spool.label,
          'weightGrams': spool.weightGrams,
        },
      )
      .toList(),
  'products': products
      .map(
        (product) => {
          'id': product.id,
          'brandId': product.brandId,
          'category': product.category.name,
          'name': product.name,
          'defaultCost': product.defaultCost,
          'dryingMinutes': product.dryingMinutes,
          'printingInstructions': product.printingInstructions,
          'dryingInstructions': product.dryingInstructions,
          'storageInstructions': product.storageInstructions,
          'image': _bytesToJson(product.imageBytes),
        },
      )
      .toList(),
  'additionHistory': additionHistory
      .map(
        (entry) => {
          'id': entry.id,
          'itemId': entry.itemId,
          'name': entry.name,
          'type': entry.type.name,
          'addedAt': entry.addedAt.toIso8601String(),
          'deviceName': entry.deviceName,
        },
      )
      .toList(),
  'historyLimit': historyLimit,
});

WorkshopState? decodeWorkshopState(String? source) {
  if (source == null || source.isEmpty) return null;
  try {
    final root = jsonDecode(source) as Map<String, dynamic>;
    final inventory = (root['inventory'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (item) => InventoryItem(
            id: item['id'] as String,
            name: item['name'] as String,
            type: _migratedInventoryType(
              item['type'] as String,
              item['name'] as String,
            ),
            compatibility: (item['compatibility'] as List).cast<String>(),
            added: DateTime.parse(item['added'] as String),
            cost: (item['cost'] as num).toDouble(),
            color: Color(item['color'] as int),
            quantity: (item['quantity'] as num?)?.toDouble() ?? 1,
            quantityAlertThreshold: (item['quantityAlertThreshold'] as num?)
                ?.toDouble(),
            dryingMinutes: item['dryingMinutes'] as int?,
            dryingRemaining: item['dryingRemaining'] as int?,
            dryingStartedAt: item['dryingStartedAt'] == null
                ? null
                : DateTime.parse(item['dryingStartedAt'] as String),
            moistureLifespanMinutes:
                item['moistureLifespanMinutes'] as int? ??
                ((item['moistureLifespanDays'] as int?) == null
                    ? null
                    : (item['moistureLifespanDays'] as int) * 1440),
            moistureTimeUnit: MoistureTimeUnit.values.byName(
              item['moistureTimeUnit'] as String? ?? 'days',
            ),
            moistureAlertEnabled:
                item['moistureAlertEnabled'] as bool? ?? false,
            moistureAlertThresholdMinutes:
                item['moistureAlertThresholdMinutes'] as int? ??
                ((item['moistureAlertThresholdDays'] as int?) == null
                    ? null
                    : (item['moistureAlertThresholdDays'] as int) * 1440),
            deployed: item['deployed'] as bool? ?? false,
            vendor: item['vendor'] as String? ?? '',
            printingInstructions: item['printingInstructions'] as String? ?? '',
            dryingInstructions: item['dryingInstructions'] as String? ?? '',
            storageInstructions: item['storageInstructions'] as String? ?? '',
            archived: item['archived'] as bool? ?? false,
            archiveDisposition: ArchiveDisposition.values.byName(
              item['archiveDisposition'] as String? ?? 'archived',
            ),
            filamentStatus: FilamentStatus.values.byName(
              item['filamentStatus'] as String? ?? 'ready',
            ),
            brand: item['brand'] as String? ?? '',
            storageLocation: item['storageLocation'] as String? ?? '',
            deploymentLocation: item['deploymentLocation'] as String? ?? '',
            lastDriedAt: item['lastDriedAt'] == null
                ? null
                : DateTime.parse(item['lastDriedAt'] as String),
            imageBytes: _bytesFromJson(item['image']),
            labelImageBytes: _bytesFromJson(item['labelImage']),
            barcode: item['barcode'] as String? ?? '',
            productUrl: item['productUrl'] as String? ?? '',
            compatibleMachineIds:
                (item['compatibleMachineIds'] as List<dynamic>? ?? const [])
                    .cast<String>(),
            spoolTypeId: item['spoolTypeId'] as String? ?? defaultSpoolTypeId,
            amsCompatible: item['amsCompatible'] as bool? ?? false,
            catalogProductId: item['catalogProductId'] as String?,
            customTypeId: item['customTypeId'] as String? ?? '',
            customTypeName: item['customTypeName'] as String? ?? '',
            customFieldValues:
                (item['customFieldValues'] as Map<String, dynamic>? ?? const {})
                    .map((key, value) => MapEntry(key, value.toString())),
          ),
        )
        .toList();
    final customItemTypes =
        (root['customItemTypes'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(
              (type) => CustomItemTypeRecord(
                id: type['id'] as String,
                name: type['name'] as String,
                contextualFields:
                    (type['contextualFields'] as List<dynamic>? ?? const [])
                        .cast<String>(),
              ),
            )
            .toList();
    final vendors = (root['vendors'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (vendor) => VendorRecord(
            id: vendor['id'] as String,
            name: vendor['name'] as String,
            isBrand: vendor['isBrand'] as bool? ?? false,
            logoBytes: _bytesFromJson(vendor['logo']),
          ),
        )
        .toList();
    final brands = (root['brands'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (brand) => BrandRecord(
            id: brand['id'] as String,
            name: brand['name'] as String,
            vendorIds: (brand['vendorIds'] as List).cast<String>().toSet(),
            categories: (brand['categories'] as List)
                .cast<String>()
                .map(InventoryType.values.byName)
                .toSet(),
            logoBytes: _bytesFromJson(brand['logo']),
          ),
        )
        .toList();
    final products = (root['products'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (product) => CatalogProduct(
            id: product['id'] as String,
            brandId: product['brandId'] as String,
            category: _migratedInventoryType(
              product['category'] as String,
              product['name'] as String,
            ),
            name: product['name'] as String,
            defaultCost: (product['defaultCost'] as num).toDouble(),
            dryingMinutes: product['dryingMinutes'] as int?,
            printingInstructions:
                product['printingInstructions'] as String? ?? '',
            dryingInstructions: product['dryingInstructions'] as String? ?? '',
            storageInstructions:
                product['storageInstructions'] as String? ?? '',
            imageBytes: _bytesFromJson(product['image']),
          ),
        )
        .toList();
    final spoolTypes =
        (root['spoolTypes'] as List<dynamic>? ??
                starterSpoolTypes
                    .map(
                      (spool) => {
                        'id': spool.id,
                        'label': spool.label,
                        'weightGrams': spool.weightGrams,
                      },
                    )
                    .toList())
            .cast<Map<String, dynamic>>()
            .map(
              (spool) => SpoolTypeRecord(
                id: spool['id'] as String,
                label: spool['label'] as String,
                weightGrams: spool['weightGrams'] as int,
              ),
            )
            .toList();
    for (var index = 0; index < brands.length; index++) {
      final brand = brands[index];
      final sellsFasteners = products.any(
        (product) =>
            product.brandId == brand.id &&
            product.category == InventoryType.fastener,
      );
      if (sellsFasteners &&
          !brand.categories.contains(InventoryType.fastener)) {
        brands[index] = BrandRecord(
          id: brand.id,
          name: brand.name,
          vendorIds: brand.vendorIds,
          categories: {...brand.categories, InventoryType.fastener},
          logoBytes: brand.logoBytes,
        );
      }
    }
    final machineTypes = (root['machineTypes'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (type) => MachineTypeRecord(
            id: type['id'] as String,
            name: type['name'] as String,
            parentId: type['parentId'] as String?,
          ),
        )
        .toList();
    final machines = (root['machines'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (machine) => MachineRecord(
            id: machine['id'] as String,
            name: machine['name'] as String,
            model: machine['model'] as String? ?? '',
            address: machine['address'] as String? ?? '',
            typeId: machine['typeId'] as String,
            kitIds: (machine['kitIds'] as List<dynamic>? ?? const [])
                .cast<String>()
                .toSet(),
          ),
        )
        .toList();
    final kits = (root['kits'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (kit) => KitRecord(
            id: kit['id'] as String,
            name: kit['name'] as String,
            sections: (kit['sections'] as List<dynamic>? ?? const [])
                .cast<String>(),
            bom: [
              for (final (index, entry)
                  in (kit['bom'] as List<dynamic>? ?? const [])
                      .cast<Map<String, dynamic>>()
                      .indexed)
                KitBomEntry(
                  id: entry['id'] as String? ?? '${kit['id']}-LINE-$index',
                  productId: entry['productId'] as String,
                  quantity: (entry['quantity'] as num).toDouble(),
                  name: entry['name'] as String?,
                  section: entry['section'] as String? ?? 'Unassigned',
                ),
            ],
          ),
        )
        .toList();
    final builds = (root['builds'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (build) => BuildRecord(
            id: build['id'] as String,
            kitId: build['kitId'] as String,
            name: build['name'] as String,
            createdAt: DateTime.parse(build['createdAt'] as String),
            createdBy: build['createdBy'] as String? ?? 'Unknown device',
            ownerDeviceId: build['ownerDeviceId'] as String? ?? '',
            ownerUserId: build['ownerUserId'] as String?,
            shared: build['shared'] as bool? ?? true,
            completedAt: build['completedAt'] == null
                ? null
                : DateTime.parse(build['completedAt'] as String),
            updatedAt: build['updatedAt'] == null
                ? null
                : DateTime.parse(build['updatedAt'] as String),
            lines: (build['lines'] as List<dynamic>? ?? const [])
                .cast<Map<String, dynamic>>()
                .map(
                  (line) => BuildLine(
                    id: line['id'] as String,
                    productId: line['productId'] as String,
                    name: line['name'] as String,
                    section: line['section'] as String? ?? 'Unassigned',
                    requiredQuantity: (line['requiredQuantity'] as num)
                        .toDouble(),
                    usedQuantity:
                        (line['usedQuantity'] as num?)?.toDouble() ?? 0,
                    consumedInventoryIds:
                        (line['consumedInventoryIds'] as List<dynamic>? ??
                                const [])
                            .cast<String>(),
                  ),
                )
                .toList(),
          ),
        )
        .toList();
    final auditLog = (root['auditLog'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (entry) => AuditEntry(
            id: entry['id'] as String,
            timestamp: DateTime.parse(entry['timestamp'] as String),
            actor: entry['actor'] as String? ?? 'Unknown device',
            action: entry['action'] as String,
            entityType: entry['entityType'] as String,
            entityId: entry['entityId'] as String? ?? '',
            changes: (entry['changes'] as Map<String, dynamic>? ?? const {})
                .map((key, value) => MapEntry(key, value.toString())),
          ),
        )
        .toList();
    final additionHistory = root['additionHistory'] == null
        ? inventory.map(AdditionHistoryEntry.fromItem).toList()
        : (root['additionHistory'] as List)
              .cast<Map<String, dynamic>>()
              .map(
                (entry) => AdditionHistoryEntry(
                  id: entry['id'] as String,
                  itemId: entry['itemId'] as String,
                  name: entry['name'] as String,
                  type: InventoryType.values.byName(entry['type'] as String),
                  addedAt: DateTime.parse(entry['addedAt'] as String),
                  deviceName: switch (entry['deviceName'] as String?) {
                    null ||
                    'Earlier inventory' => 'Unknown device (predates tracking)',
                    final value => value,
                  },
                ),
              )
              .toList();
    return (
      inventory: inventory,
      vendors: vendors,
      brands: brands,
      spoolTypes: spoolTypes,
      customItemTypes: customItemTypes,
      products: products,
      machineTypes: machineTypes,
      machines: machines,
      kits: kits,
      builds: builds,
      auditLog: auditLog,
      additionHistory: additionHistory,
      historyLimit: root['historyLimit'] as int? ?? 100,
    );
  } catch (exception) {
    debugPrint('Could not restore Inventorinator database: $exception');
    return null;
  }
}

class InventorinatorApp extends StatelessWidget {
  const InventorinatorApp({super.key, this.database, this.persistedState});
  final LocalDatabase? database;
  final String? persistedState;
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff8e75ff),
      brightness: Brightness.dark,
      surface: const Color(0xff171b25),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Inventorinator',
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xff0d1017),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xff0f131c),
          labelStyle: const TextStyle(
            color: Color(0xffb9c0d0),
            fontWeight: FontWeight.w600,
          ),
          floatingLabelStyle: const TextStyle(
            color: Color(0xffc9bcff),
            fontWeight: FontWeight.w700,
          ),
          hintStyle: const TextStyle(color: Color(0xff687185)),
          helperStyle: const TextStyle(color: Color(0xff929aac)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xff394155)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xff394155)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xff9f8aff), width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xffff6b7a)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xffff6b7a), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xff171b25),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xff272d3b)),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xff171b25),
          elevation: 20,
          shadowColor: const Color(0xff8e75ff).withValues(alpha: .28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: const Color(0xff8e75ff).withValues(alpha: .28),
            ),
          ),
        ),
      ),
      home: InventoryHome(database: database, persistedState: persistedState),
    );
  }
}

class InventoryHome extends StatefulWidget {
  const InventoryHome({super.key, this.database, this.persistedState});
  final LocalDatabase? database;
  final String? persistedState;
  @override
  State<InventoryHome> createState() => _InventoryHomeState();
}

class _InventoryHomeState extends State<InventoryHome> {
  late final List<InventoryItem> inventory;
  late final List<VendorRecord> vendors;
  late final List<BrandRecord> brands;
  late final List<SpoolTypeRecord> spoolTypes;
  late final List<CustomItemTypeRecord> customItemTypes;
  late final List<CatalogProduct> products;
  late final List<MachineTypeRecord> machineTypes;
  late final List<MachineRecord> machines;
  late final List<KitRecord> kits;
  late final List<BuildRecord> builds;
  late final List<AuditEntry> auditLog;
  late final List<AdditionHistoryEntry> additionHistory;
  late int historyLimit;
  late bool syncChimeEnabled;
  late bool dryingCompleteChimeEnabled;
  late bool moistureAlertChimeEnabled;
  late int animationDurationPercent;
  late int animationRecurrenceSeconds;
  late final Set<String> _moistureAlertChimedCycles;
  late String deviceName;
  late String deviceId;
  String? currentUserId;
  bool gridView = true;
  bool archivedOnly = false;
  CatalogViewFilter? catalogFilter;
  String query = '';
  InventoryType? type;
  InventorySort sort = InventorySort.type;
  static const _pageSizes = [12, 25, 100, 250, 1000];
  int pageSizeIndex = 0;
  int currentPage = 0;
  int pageMotionDirection = 1;
  int pageAnimationKey = 0;
  final ScrollController inventoryScrollController = ScrollController();
  Timer? _syncDebounce;
  Timer? _syncPoll;
  Timer? _clockTick;
  bool _syncing = false;
  String? _lastSyncConflict;
  bool _applyingCloudState = false;
  final List<Map<String, Object?>> _pendingAuditEvents = [];
  WorkspaceRole currentRole = WorkspaceRole.admin;
  bool workspaceOwner = true;
  final Map<String, int> _remoteQuantityAnimationVersions = {};
  final Map<String, int> _lowStockAnimationVersions = {};
  final Map<String, int> _moistureAnimationVersions = {};
  final Set<String> _moistureAnimationCycles = {};
  static const _audioChannel = MethodChannel('inventorinator/audio');
  static const _deviceChannel = MethodChannel('inventorinator/device');

  @override
  void initState() {
    super.initState();
    final syncConfigSource = widget.database?.loadSyncConfig();
    if (syncConfigSource != null) {
      try {
        final config = SupabaseConfig.fromJson(
          jsonDecode(syncConfigSource) as Map<String, dynamic>,
        );
        if (config.syncMode == 'supabase') {
          currentRole = WorkspaceRole.fromServer(config.workspaceRole);
          workspaceOwner = config.workspaceRole == 'owner';
          currentUserId = config.userId;
        }
      } catch (_) {
        // A malformed sync preference must not prevent local inventory access.
      }
    }
    final restored = decodeWorkshopState(widget.persistedState);
    inventory = restored?.inventory ?? [...sampleInventory];
    final initializedDryingTimers = _initializeDryingTimers();
    vendors = restored?.vendors ?? [...starterVendors];
    brands = restored?.brands ?? [...starterBrands];
    spoolTypes = restored?.spoolTypes ?? [...starterSpoolTypes];
    customItemTypes = restored?.customItemTypes ?? [];
    products = restored?.products ?? [...starterProducts];
    machineTypes = restored?.machineTypes ?? [];
    machines = restored?.machines ?? [];
    kits = restored?.kits ?? [];
    builds = restored?.builds ?? [];
    auditLog = restored?.auditLog ?? [];
    additionHistory =
        restored?.additionHistory ??
        inventory.map(AdditionHistoryEntry.fromItem).toList();
    historyLimit = restored?.historyLimit ?? 100;
    final initializedKitSections = _initializeKitSections();
    syncChimeEnabled =
        widget.database?.loadBoolPreference(
          'sync_chime_enabled',
          fallback: true,
        ) ??
        true;
    dryingCompleteChimeEnabled =
        widget.database?.loadBoolPreference(
          'drying_complete_chime_enabled',
          fallback: true,
        ) ??
        true;
    moistureAlertChimeEnabled =
        widget.database?.loadBoolPreference(
          'moisture_alert_chime_enabled',
          fallback: true,
        ) ??
        true;
    animationDurationPercent =
        (int.tryParse(
                  widget.database?.loadStringPreference(
                        'animation_duration_percent',
                        fallback: '100',
                      ) ??
                      '100',
                ) ??
                100)
            .clamp(25, 200);
    final savedRecurrenceSeconds =
        int.tryParse(
          widget.database?.loadStringPreference(
                'animation_recurrence_seconds',
                fallback: '5',
              ) ??
              '5',
        ) ??
        5;
    animationRecurrenceSeconds =
        const {0, 3, 5, 10, 30}.contains(savedRecurrenceSeconds)
        ? savedRecurrenceSeconds
        : 5;
    try {
      _moistureAlertChimedCycles = {
        ...((jsonDecode(
          widget.database?.loadStringPreference(
                'moisture_alert_chimed_cycles',
                fallback: '[]',
              ) ??
              '[]',
        ) as List).cast<String>()),
      };
    } catch (_) {
      _moistureAlertChimedCycles = <String>{};
    }
    final hostName = Platform.localHostname.trim();
    final defaultDeviceName = hostName.isNotEmpty && hostName != 'localhost'
        ? hostName
        : Platform.isAndroid
        ? 'Android device'
        : 'This device';
    deviceName =
        widget.database?.loadStringPreference(
          'device_name',
          fallback: defaultDeviceName,
        ) ??
        defaultDeviceName;
    deviceId =
        widget.database?.loadStringPreference('device_id', fallback: '') ?? '';
    if (deviceId.isEmpty) {
      deviceId = 'DEVICE-${DateTime.now().microsecondsSinceEpoch}';
      widget.database?.saveStringPreference('device_id', deviceId);
    }
    if (const {
      'Unnamed device',
      'Android device',
      'This device',
    }.contains(deviceName)) {
      deviceName = defaultDeviceName;
    }
    widget.database?.saveStringPreference('device_name', deviceName);
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadAndroidDeviceName(),
      );
    }
    _trimAdditionHistory();
    _clockTick = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _advanceDryingTimers(),
    );
    if (initializedDryingTimers || initializedKitSections) _persist();
    if (widget.database != null && widget.persistedState == null) _persist();
    if (_needsSyncOnboarding) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openSyncOnboarding(),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoSync());
    }
  }

  Future<void> _loadAndroidDeviceName() async {
    if (!const {
      'Unnamed device',
      'Android device',
      'This device',
    }.contains(deviceName)) {
      return;
    }
    try {
      final resolved = (await _deviceChannel.invokeMethod<String>(
        'getDeviceName',
      ))?.trim();
      if (resolved == null || resolved.isEmpty || !mounted) return;
      setState(() => deviceName = resolved);
      widget.database?.saveStringPreference('device_name', resolved);
      unawaited(_syncAutomatically());
    } catch (error) {
      debugPrint('Could not read Android device name: $error');
    }
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    _syncPoll?.cancel();
    _clockTick?.cancel();
    inventoryScrollController.dispose();
    super.dispose();
  }

  bool _initializeDryingTimers() {
    var changed = false;
    final now = DateTime.now();
    for (var index = 0; index < inventory.length; index++) {
      final item = inventory[index];
      if (item.type == InventoryType.filament &&
          item.filamentStatus == FilamentStatus.drying &&
          item.dryingStartedAt == null) {
        inventory[index] = item.copyWith(dryingStartedAt: now);
        changed = true;
      }
    }
    return changed;
  }

  bool _initializeKitSections() {
    final kitIndex = kits.indexWhere(
      (kit) =>
          kit.id == 'KIT-ORIGINAL-PRUSA-I3-MK3S-PLUS' &&
          kit.bom.isNotEmpty &&
          kit.bom.every((line) => line.section == 'Unassigned'),
    );
    if (kitIndex < 0) return false;

    final kit = kits[kitIndex];
    const allocations = <String, List<(String, double)>>{
      'PROD-MK3S-LM8UU-LINEAR-BEARING': [
        ('Y-axis & Frame', 3),
        ('X-axis', 4),
        ('Extruder', 3),
      ],
      'PROD-MK3S-GT2-16-TOOTH-PULLEY': [('Y-axis & Frame', 1), ('X-axis', 1)],
      'PROD-MK3S-623H-IDLER-BEARING': [('Y-axis & Frame', 1), ('X-axis', 1)],
      'PROD-MK3S-M3X10-SCREW': [
        ('Y-axis & Frame', 22),
        ('Z-axis', 18),
        ('Extruder', 11),
        ('LCD', 6),
        ('Heatbed & PSU', 7),
        ('Electronics', 14),
      ],
      'PROD-MK3S-M3X18-SCREW': [
        ('Y-axis & Frame', 1),
        ('X-axis', 4),
        ('Z-axis', 4),
        ('Extruder', 1),
      ],
      'PROD-MK3S-M3X30-SCREW': [('Y-axis & Frame', 1), ('X-axis', 1)],
      'PROD-MK3S-M3X40-SCREW': [('Extruder', 6), ('Electronics', 1)],
      'PROD-MK3S-M3-SQUARE-NUT': [
        ('Y-axis & Frame', 12),
        ('X-axis', 1),
        ('Extruder', 8),
        ('LCD', 4),
        ('Electronics', 5),
      ],
      'PROD-MK3S-M3-HEX-NUT': [
        ('Y-axis & Frame', 6),
        ('Z-axis', 4),
        ('Extruder', 8),
        ('Heatbed & PSU', 2),
        ('Electronics', 4),
      ],
      'PROD-MK3S-M3-NYLOC-NUT': [
        ('Y-axis & Frame', 2),
        ('X-axis', 1),
        ('Heatbed & PSU', 3),
      ],
      'PROD-MK3S-TEXTILE-SLEEVE-5X300-MM': [
        ('Heatbed & PSU', 1),
        ('Electronics', 1),
      ],
      'PROD-MK3S-ZIP-TIE': [('Extruder', 7), ('Electronics', 1)],
    };
    const sectionOrder = [
      'Y-axis & Frame',
      'X-axis',
      'Z-axis',
      'Extruder',
      'LCD',
      'Heatbed & PSU',
      'Electronics',
      'Accessories',
      'Unassigned',
    ];
    final segmented = <KitBomEntry>[];
    for (final source in kit.bom) {
      final split = allocations[source.productId];
      if (split != null) {
        for (final (section, quantity) in split) {
          segmented.add(
            KitBomEntry(
              id: '${kit.id}-${source.productId}-$section',
              productId: source.productId,
              quantity: quantity,
              name: source.name,
              section: section,
            ),
          );
        }
        continue;
      }
      segmented.add(
        KitBomEntry(
          id: source.id.isEmpty ? '${kit.id}-${source.productId}' : source.id,
          productId: source.productId,
          quantity: source.quantity,
          name: source.name,
          section: _prusaMk3sSection(source.productId),
        ),
      );
    }
    segmented.sort(
      (left, right) => sectionOrder
          .indexOf(left.section)
          .compareTo(sectionOrder.indexOf(right.section)),
    );
    kits[kitIndex] = KitRecord(
      id: kit.id,
      name: kit.name,
      bom: segmented,
      sections: sectionOrder
          .where((section) => segmented.any((line) => line.section == section))
          .toList(),
    );
    return true;
  }

  String _prusaMk3sSection(String id) {
    if (id.contains('DOUBLE-SPOOL-HOLDER')) return 'Accessories';
    if (id.contains('EINSY') ||
        id.contains('EXTRUDER-CABLE-CLIP') ||
        id.contains('PSU-COVER')) {
      return 'Electronics';
    }
    if (id.contains('LCD') || id.endsWith('-SD-CARD')) return 'LCD';
    if (id.contains('HEATBED') ||
        id.contains('POWER-SUPPLY') ||
        id.contains('PSU-POWER') ||
        id.contains('POWER-PANIC') ||
        id.contains('REMOVABLE-SPRING')) {
      return 'Heatbed & PSU';
    }
    if (id.contains('EXTRUDER') ||
        id.contains('X-CARRIAGE') ||
        id.contains('ADAPTER-PRINTER') ||
        id.contains('-FS-') ||
        id.contains('FAN-SHROUD') ||
        id.contains('HOTEND') ||
        id.contains('NOZZLE') ||
        id.contains('BONDTECH') ||
        id.contains('FILAMENT-SENSOR') ||
        id.contains('MAGNET-') ||
        id.contains('IR-FILAMENT') ||
        id.contains('SUPERPINDA') ||
        id.contains('PRINT-FAN') ||
        id.contains('CABLE-HOLDER') ||
        id.contains('NYLON-FILAMENT') ||
        id.contains('M2X8') ||
        id.contains('M3X14') ||
        id.contains('M3X20') ||
        id.contains('TEXTILE-SLEEVE-13')) {
      return 'Extruder';
    }
    if (id.contains('Z-AXIS') ||
        id.contains('Z-SCREW') ||
        id.contains('TRAPEZOIDAL') ||
        id.contains('SMOOTH-ROD-320')) {
      return 'Z-axis';
    }
    if (id.contains('X-END') ||
        id.contains('X-AXIS') ||
        id.contains('SMOOTH-ROD-370')) {
      return 'X-axis';
    }
    if (id.contains('ALUMINUM') ||
        id.contains('Y-') ||
        id.contains('ANTIVIBRATION') ||
        id.contains('SMOOTH-ROD-330') ||
        id.contains('M3X6') ||
        id.contains('M5X16') ||
        id.contains('M3-ELASTIC')) {
      return 'Y-axis & Frame';
    }
    if (id.contains('M3X12') ||
        id.contains('M4X10') ||
        id.contains('M3-WASHER') ||
        id.contains('HEATBED-SPACER')) {
      return 'Heatbed & PSU';
    }
    return 'Unassigned';
  }

  void _advanceDryingTimers() {
    if (!mounted) return;
    var completed = false;
    final now = DateTime.now();
    setState(() {
      for (var index = 0; index < inventory.length; index++) {
        final item = inventory[index];
        if (item.filamentStatus != FilamentStatus.drying ||
            _dryingTimeRemaining(item, now: now) > Duration.zero) {
          continue;
        }
        inventory[index] = item.copyWith(
          filamentStatus: FilamentStatus.ready,
          dryingRemaining: 0,
          lastDriedAt: now,
          deployed: false,
        );
        completed = true;
      }
    });
    if (completed) {
      _persist();
      unawaited(_playDryingCompleteChime());
    }
    _checkMoistureThresholdAnimations();
    _checkMoistureAlertChimes();
  }

  void _checkMoistureThresholdAnimations() {
    final triggeredIds = <String>[];
    for (final item in _moistureAlerts) {
      final cycle =
          '${item.id}:${item.lastDriedAt?.toIso8601String()}:${item.moistureAlertThresholdMinutes}';
      if (_moistureAnimationCycles.add(cycle)) triggeredIds.add(item.id);
    }
    if (triggeredIds.isEmpty || !mounted) return;
    setState(() {
      for (final id in triggeredIds) {
        _moistureAnimationVersions[id] =
            (_moistureAnimationVersions[id] ?? 0) + 1;
      }
    });
    if (_moistureAnimationCycles.length > 200) {
      final currentCycles = inventory
          .where((item) => item.type == InventoryType.filament)
          .map(
            (item) =>
                '${item.id}:${item.lastDriedAt?.toIso8601String()}:${item.moistureAlertThresholdMinutes}',
          )
          .toSet();
      _moistureAnimationCycles.retainAll(currentCycles);
    }
  }

  void _checkMoistureAlertChimes() {
    if (!moistureAlertChimeEnabled) return;
    var changed = false;
    for (final item in _moistureAlerts) {
      final cycle =
          '${item.id}:${item.lastDriedAt?.toIso8601String()}:${item.moistureAlertThresholdMinutes}';
      if (_moistureAlertChimedCycles.add(cycle)) changed = true;
    }
    if (!changed) return;
    if (_moistureAlertChimedCycles.length > 200) {
      final current = inventory
          .where((item) => item.type == InventoryType.filament)
          .map(
            (item) =>
                '${item.id}:${item.lastDriedAt?.toIso8601String()}:${item.moistureAlertThresholdMinutes}',
          )
          .toSet();
      _moistureAlertChimedCycles.retainAll(current);
    }
    widget.database?.saveStringPreference(
      'moisture_alert_chimed_cycles',
      jsonEncode(_moistureAlertChimedCycles.toList()),
    );
    unawaited(_playMoistureAlertChime());
  }

  void _startAutoSync() {
    _syncPoll?.cancel();
    _syncAutomatically();
    _syncPoll = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _syncAutomatically(),
    );
  }

  bool get _needsSyncOnboarding {
    final source = widget.database?.loadSyncConfig();
    if (source == null) return widget.database != null;
    try {
      return (jsonDecode(source) as Map<String, dynamic>)['syncMode'] == null ||
          (jsonDecode(source) as Map<String, dynamic>)['syncMode'] == '';
    } catch (_) {
      return true;
    }
  }

  String _normalized(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  String _machineTypePath(String typeId, [Set<String>? visited]) {
    final seen = visited ?? <String>{};
    if (!seen.add(typeId)) return '';
    final type = machineTypes.where((value) => value.id == typeId).firstOrNull;
    if (type == null) return '';
    if (type.parentId == null) return type.name;
    final parent = _machineTypePath(type.parentId!, seen);
    return parent.isEmpty ? type.name : '$parent ${type.name}';
  }

  bool _isPrinter(MachineRecord machine) =>
      _normalized(_machineTypePath(machine.typeId)).contains('printer') ||
      const {'fdm', 'sla', 'uv', 'uvdtf', 'paperprinter'}.any(
        (word) => _normalized(_machineTypePath(machine.typeId)).contains(word),
      );

  List<Object> get visibleCatalogRecords {
    final selected = catalogFilter;
    if (selected == null) return const [];
    final needle = _normalized(query);
    if (selected == CatalogViewFilter.kits) {
      final result = kits
          .where((kit) {
            final productNames = kit.bom
                .map(
                  (entry) => products
                      .where((product) => product.id == entry.productId)
                      .firstOrNull
                      ?.name,
                )
                .whereType<String>()
                .join(' ');
            return needle.isEmpty ||
                _normalized('${kit.name} $productNames').contains(needle);
          })
          .cast<Object>()
          .toList();
      result.sort(
        (a, b) => (a as KitRecord).name.compareTo((b as KitRecord).name),
      );
      return result;
    }
    if (selected == CatalogViewFilter.builds) {
      final result = builds
          .where(
            (build) =>
                _canViewBuild(build) &&
                (needle.isEmpty ||
                    _normalized(
                      '${build.name} ${build.lines.map((line) => '${line.name} ${line.section}').join(' ')}',
                    ).contains(needle)),
          )
          .cast<Object>()
          .toList();
      result.sort(
        (a, b) => (b as BuildRecord).createdAt.compareTo(
          (a as BuildRecord).createdAt,
        ),
      );
      return result;
    }
    final result = machines
        .where((machine) {
          final printer = _isPrinter(machine);
          if (selected == CatalogViewFilter.printers && !printer) return false;
          if (selected == CatalogViewFilter.tools && printer) return false;
          final kitNames = kits
              .where((kit) => machine.kitIds.contains(kit.id))
              .map((kit) => kit.name)
              .join(' ');
          final searchable = _normalized(
            '${machine.name} ${machine.model} ${machine.address} '
            '${_machineTypePath(machine.typeId)} $kitNames',
          );
          return needle.isEmpty || searchable.contains(needle);
        })
        .cast<Object>()
        .toList();
    result.sort(
      (a, b) => (a as MachineRecord).name.compareTo((b as MachineRecord).name),
    );
    return result;
  }

  String _spoolSizeLabel(InventoryItem item) =>
      item.type != InventoryType.filament
      ? ''
      : spoolTypes
                .where((spool) => spool.id == item.spoolTypeId)
                .firstOrNull
                ?.label ??
            '1 kg';

  List<InventoryItem> get visibleItems {
    final needle = _normalized(query);
    final now = DateTime.now();
    final result = inventory.where((item) {
      final searchable = _normalized(
        '${item.name} ${item.typeLabel} ${item.compatibility.join(' ')} ${item.barcode} '
        '${item.customFieldValues.entries.map((entry) => '${entry.key} ${entry.value}').join(' ')} '
        '${_spoolSizeLabel(item)} ${item.amsCompatible ? 'AMS compatible' : ''} '
        '${machines.where((machine) => item.compatibleMachineIds.contains(machine.id)).map((machine) => '${machine.name} ${machine.model} ${_machineTypePath(machine.typeId)}').join(' ')}',
      );
      return item.archived == archivedOnly &&
          (type == null || item.type == type) &&
          (needle.isEmpty || searchable.contains(needle));
    }).toList();
    result.sort(
      (a, b) => switch (sort) {
        InventorySort.type => a.typeLabel.compareTo(b.typeLabel),
        InventorySort.age => a.added.compareTo(b.added),
        InventorySort.cost => b.cost.compareTo(a.cost),
        InventorySort.dryingTime => (b.dryingMinutes ?? -1).compareTo(
          a.dryingMinutes ?? -1,
        ),
        InventorySort.moistureRemaining => compareMoistureRemaining(
          a,
          b,
          now: now,
        ),
      },
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final allItems = visibleItems;
    final allCatalogRecords = visibleCatalogRecords;
    final showingCatalog = catalogFilter != null;
    final resultCount = showingCatalog
        ? allCatalogRecords.length
        : allItems.length;
    final pageSize = _pageSizes[pageSizeIndex];
    final pageCount = resultCount == 0 ? 1 : (resultCount / pageSize).ceil();
    final page = currentPage.clamp(0, pageCount - 1);
    final start = page * pageSize;
    final items = allItems.skip(start).take(pageSize).toList();
    final catalogRecords = allCatalogRecords
        .skip(start)
        .take(pageSize)
        .toList();
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          controller: inventoryScrollController,
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
              sliver: resultCount == 0
                  ? const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text('Nothing matches those filters.'),
                      ),
                    )
                  : showingCatalog
                  ? gridView
                        ? SliverLayoutBuilder(
                            builder: (context, constraints) {
                              final count = constraints.crossAxisExtent >= 1050
                                  ? 4
                                  : constraints.crossAxisExtent >= 720
                                  ? 3
                                  : constraints.crossAxisExtent >= 470
                                  ? 2
                                  : 1;
                              return SliverGrid.builder(
                                itemCount: catalogRecords.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: count,
                                      mainAxisSpacing: 14,
                                      crossAxisSpacing: 14,
                                      mainAxisExtent: 220,
                                    ),
                                itemBuilder: (_, index) => PageItemEntrance(
                                  pageKey: pageAnimationKey,
                                  index: index,
                                  direction: pageMotionDirection,
                                  child: _catalogRecordCard(
                                    catalogRecords[index],
                                  ),
                                ),
                              );
                            },
                          )
                        : SliverList.separated(
                            itemCount: catalogRecords.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, index) => PageItemEntrance(
                              pageKey: pageAnimationKey,
                              index: index,
                              direction: pageMotionDirection,
                              child: _catalogRecordCard(
                                catalogRecords[index],
                                list: true,
                              ),
                            ),
                          )
                  : gridView
                  ? SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final count = constraints.crossAxisExtent >= 1050
                            ? 4
                            : constraints.crossAxisExtent >= 720
                            ? 3
                            : constraints.crossAxisExtent >= 470
                            ? 2
                            : 1;
                        return SliverGrid.builder(
                          itemCount: items.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: count,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                mainAxisExtent: 252,
                              ),
                          itemBuilder: (_, index) => PageItemEntrance(
                            pageKey: pageAnimationKey,
                            index: index,
                            direction: pageMotionDirection,
                            child: InventoryCard(
                              item: items[index],
                              spoolSizeLabel: _spoolSizeLabel(items[index]),
                              quantitySyncVersion:
                                  _remoteQuantityAnimationVersions[items[index]
                                      .id] ??
                                  0,
                              lowStockAnimationVersion:
                                  _lowStockAnimationVersions[items[index].id] ??
                                  0,
                              moistureAnimationVersion:
                                  _moistureAnimationVersions[items[index].id] ??
                                  0,
                              animationDurationPercent:
                                  animationDurationPercent,
                              animationRecurrenceSeconds:
                                  animationRecurrenceSeconds,
                              canEdit: currentRole.canEditInventory,
                              canCreate: currentRole.canCreateInventory,
                              canArchive: currentRole.canArchiveInventory,
                              canDelete: currentRole.canHardDeleteItems,
                              onOpen: () => _openDetails(items[index]),
                              onAction: (action) =>
                                  _handleAction(items[index], action),
                            ),
                          ),
                        );
                      },
                    )
                  : SliverList.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, index) => PageItemEntrance(
                        pageKey: pageAnimationKey,
                        index: index,
                        direction: pageMotionDirection,
                        child: InventoryRow(
                          item: items[index],
                          spoolSizeLabel: _spoolSizeLabel(items[index]),
                          quantitySyncVersion:
                              _remoteQuantityAnimationVersions[items[index]
                                  .id] ??
                              0,
                          lowStockAnimationVersion:
                              _lowStockAnimationVersions[items[index].id] ?? 0,
                          moistureAnimationVersion:
                              _moistureAnimationVersions[items[index].id] ?? 0,
                          animationDurationPercent: animationDurationPercent,
                          animationRecurrenceSeconds:
                              animationRecurrenceSeconds,
                          canEdit: currentRole.canEditInventory,
                          canCreate: currentRole.canCreateInventory,
                          canArchive: currentRole.canArchiveInventory,
                          canDelete: currentRole.canHardDeleteItems,
                          onOpen: () => _openDetails(items[index]),
                          onAction: (action) =>
                              _handleAction(items[index], action),
                        ),
                      ),
                    ),
            ),
            if (resultCount > 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                  child: _pageNavigation(page, pageCount, resultCount),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: currentRole.canCreateInventory ? _addItem : null,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add item'),
      ),
    );
  }

  Future<void> _addItem({
    String initialBarcode = '',
    InventoryItem? productTemplate,
    LabelOcrDraft? labelDraft,
  }) async {
    if (!currentRole.canCreateInventory) {
      _showPermissionDenied('Your role cannot add inventory items.');
      return;
    }
    final item = await showDialog<InventoryItem>(
      context: context,
      builder: (_) => AddItemDialog(
        vendors: vendors,
        brands: brands,
        products: products,
        initialBarcode: initialBarcode,
        productTemplate: productTemplate,
        labelDraft: labelDraft,
        machineTypes: machineTypes,
        machines: machines,
        spoolTypes: spoolTypes,
        customItemTypes: customItemTypes,
      ),
    );
    if (item != null && mounted) {
      setState(() {
        inventory.add(item);
        _recordAddition(item);
        _recordAudit('create', 'inventory', item.id, {'name': item.name});
      });
      _persist();
    }
  }

  Future<void> _openRapidizer() async {
    if (!currentRole.canCreateInventory) {
      _showPermissionDenied('Your role cannot add inventory items.');
      return;
    }
    final drafts = await showDialog<List<RapidItemDraft>>(
      context: context,
      builder: (_) => const RapidizerDialog(),
    );
    if (drafts == null || drafts.isEmpty || !mounted) return;
    final now = DateTime.now();
    final items = drafts
        .map(
          (draft) => InventoryItem(
            id: _newInventoryId(),
            name: draft.name,
            type: draft.type,
            compatibility: const [],
            added: now,
            cost: draft.price,
            quantity: draft.quantity,
            color: _typeColor(draft.type),
          ),
        )
        .toList();
    setState(() {
      inventory.addAll(items);
      for (final item in items) {
        _recordAddition(item);
      }
    });
    _persist();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${items.length} items RAPIDIZED!')));
  }

  Future<void> _openDetails(InventoryItem item) => showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close item details',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.centerRight,
      child: ItemDetailsPanel(
        item: item,
        machines: machines,
        machineTypes: machineTypes,
        spoolTypes: spoolTypes,
        onChanged: _updateItemById,
        canEdit: currentRole.canEditInventory,
        canArchive: currentRole.canArchiveInventory,
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(.12, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );

  Future<void> _handleAction(InventoryItem item, ItemAction action) async {
    final allowed = switch (action) {
      ItemAction.delete => currentRole.canHardDeleteItems,
      ItemAction.duplicate => currentRole.canCreateInventory,
      ItemAction.archive => currentRole.canArchiveInventory,
      ItemAction.edit ||
      ItemAction.resetDryTimer => currentRole.canEditInventory,
    };
    if (!allowed) {
      _showPermissionDenied('Your role cannot perform that action.');
      return;
    }
    switch (action) {
      case ItemAction.resetDryTimer:
        if (item.dryingMinutes == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This item has no drying timer.')),
          );
          return;
        }
        _replaceItem(
          item,
          item.copyWith(
            dryingRemaining: item.dryingMinutes,
            dryingStartedAt: DateTime.now(),
            filamentStatus: FilamentStatus.drying,
            deployed: false,
          ),
        );
      case ItemAction.edit:
        final edited = await showDialog<InventoryItem>(
          context: context,
          builder: (_) => AddItemDialog(
            initialItem: item,
            vendors: vendors,
            brands: brands,
            spoolTypes: spoolTypes,
            customItemTypes: customItemTypes,
            products: products,
            machineTypes: machineTypes,
            machines: machines,
          ),
        );
        if (edited != null) _replaceItem(item, edited);
      case ItemAction.duplicate:
        setState(() {
          final duplicate = item.copyWith(
            id: _newInventoryId(),
            name: '${item.name} copy',
            added: DateTime.now(),
            archived: false,
          );
          inventory.add(duplicate);
          _recordAddition(duplicate);
          _recordAudit('duplicate', 'inventory', duplicate.id, {
            'source': item.id,
            'name': duplicate.name,
          });
        });
        _persist();
      case ItemAction.archive:
        _replaceItem(
          item,
          item.copyWith(
            archived: !item.archived,
            archiveDisposition: ArchiveDisposition.archived,
          ),
        );
      case ItemAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete item?'),
            content: Text('Permanently delete “${item.name}”?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          setState(() {
            inventory.remove(item);
            _recordAudit('delete', 'inventory', item.id, {'name': item.name});
          });
          _persist();
        }
    }
  }

  void _showPermissionDenied(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _replaceItem(InventoryItem oldItem, InventoryItem newItem) {
    if (!mounted) return;
    final enteredLowStock = !_isLowStock(oldItem) && _isLowStock(newItem);
    setState(() {
      // A cloud poll can rebuild the inventory with fresh object instances
      // while an Edit dialog is open. Match the stable ID so Save still
      // updates the current in-memory item instead of silently doing nothing.
      replaceInventoryItemById(inventory, oldItem.id, newItem);
      final changes = <String, String>{};
      if (oldItem.name != newItem.name) {
        changes['name'] = '${oldItem.name} → ${newItem.name}';
      }
      if (oldItem.quantity != newItem.quantity) {
        changes['quantity'] =
            '${_formatBomQuantity(oldItem.quantity)} → ${_formatBomQuantity(newItem.quantity)}';
      }
      if (oldItem.archived != newItem.archived ||
          oldItem.archiveDisposition != newItem.archiveDisposition) {
        changes['status'] = newItem.archived
            ? newItem.archiveDisposition.name
            : 'active';
      }
      if (changes.isNotEmpty) {
        _recordAudit('edit', 'inventory', newItem.id, changes);
      }
      if (enteredLowStock) {
        _lowStockAnimationVersions[newItem.id] =
            (_lowStockAnimationVersions[newItem.id] ?? 0) + 1;
      }
    });
    _persist();
    _checkMoistureThresholdAnimations();
  }

  void _updateItemById(InventoryItem item) {
    if (!mounted) return;
    if (!currentRole.canEditInventory) {
      _showPermissionDenied('Your role is view/build only.');
      return;
    }
    final previous = inventory
        .where((candidate) => candidate.id == item.id)
        .firstOrNull;
    final enteredLowStock =
        previous != null && !_isLowStock(previous) && _isLowStock(item);
    setState(() {
      final index = inventory.indexWhere(
        (candidate) => candidate.id == item.id,
      );
      if (index >= 0) inventory[index] = item;
      if (previous != null) {
        final changes = <String, String>{};
        if (previous.name != item.name) {
          changes['name'] = '${previous.name} → ${item.name}';
        }
        if (previous.quantity != item.quantity) {
          changes['quantity'] =
              '${_formatBomQuantity(previous.quantity)} → ${_formatBomQuantity(item.quantity)}';
        }
        if (previous.filamentStatus != item.filamentStatus) {
          changes['status'] =
              '${previous.filamentStatus.name} → ${item.filamentStatus.name}';
        }
        if (changes.isNotEmpty) {
          _recordAudit('edit', 'inventory', item.id, changes);
        }
      }
      if (enteredLowStock) {
        _lowStockAnimationVersions[item.id] =
            (_lowStockAnimationVersions[item.id] ?? 0) + 1;
      }
    });
    _persist();
    _checkMoistureThresholdAnimations();
  }

  Future<void> _openCatalog({String? initialKitId}) => showDialog<void>(
    context: context,
    builder: (_) => CatalogManagerDialog(
      vendors: vendors,
      brands: brands,
      spoolTypes: spoolTypes,
      customItemTypes: customItemTypes,
      products: products,
      machineTypes: machineTypes,
      machines: machines,
      kits: kits,
      initialKitId: initialKitId,
      onVendorAdded: (vendor) {
        setState(() => vendors.add(vendor));
        _persist();
      },
      onBrandAdded: (brand) {
        setState(() => brands.add(brand));
        _persist();
      },
      onSpoolTypeAdded: (spoolType) {
        setState(() => spoolTypes.add(spoolType));
        _persist();
      },
      onCustomItemTypeAdded: (customType) {
        setState(() => customItemTypes.add(customType));
        _persist();
      },
      onProductAdded: (product) {
        setState(() => products.add(product));
        _persist();
      },
      onMachineTypeAdded: (machineType) {
        setState(() => machineTypes.add(machineType));
        _persist();
      },
      onMachineAdded: (machine) {
        setState(() => machines.add(machine));
        _persist();
      },
      onKitAdded: (kit) {
        setState(() => kits.add(kit));
        _persist();
      },
      onKitUpdated: (kit) {
        setState(() {
          final index = kits.indexWhere((candidate) => candidate.id == kit.id);
          if (index >= 0) kits[index] = kit;
        });
        _persist();
      },
    ),
  );

  Future<void> _openKitDetails(KitRecord kit) => showDialog<void>(
    context: context,
    builder: (_) => KitDetailsDialog(
      kit: kit,
      kits: kits,
      products: products,
      availableQuantity: _availableInventoryQuantity,
      onBuild: _createBuild,
      canBuild: currentRole.canCreateBuilds,
      buildDisabledReason: currentRole.canCreateBuilds
          ? null
          : _buildDisabledReason,
    ),
  );

  String get _buildDisabledReason {
    final source = widget.database?.loadSyncConfig();
    if (source != null) {
      try {
        final config = SupabaseConfig.fromJson(
          jsonDecode(source) as Map<String, dynamic>,
        );
        if (config.syncMode == 'supabase' && config.workspaceRole == null) {
          return 'Build unavailable: the cloud role has not loaded. Update the server role migration, then sync again.';
        }
      } catch (_) {
        // Fall through to the normal role explanation.
      }
    }
    return 'Your workspace role can use shared builds, but cannot create one.';
  }

  Future<void> _openKitEditor(KitRecord kit) =>
      _openCatalog(initialKitId: kit.id);

  String _kitLineName(KitBomEntry line) =>
      line.name ??
      products
          .where((product) => product.id == line.productId)
          .firstOrNull
          ?.name ??
      kits.where((kit) => kit.id == line.productId).firstOrNull?.name ??
      'Missing item';

  double _availableInventoryQuantity(String productId, String name) => inventory
      .where(
        (item) =>
            !item.archived &&
            item.quantity > 0 &&
            (item.catalogProductId == productId ||
                _normalized(item.name) == _normalized(name)),
      )
      .fold(0, (total, item) => total + item.quantity);

  void _createBuild(KitRecord kit) {
    if (!currentRole.canCreateBuilds) {
      _showPermissionDenied(
        'Your role can use shared builds but cannot create them.',
      );
      return;
    }
    final lines = <BuildLine>[];
    void expand(KitRecord source, String sectionPrefix, Set<String> path) {
      if (!path.add(source.id)) return;
      for (final line in source.bom) {
        final section = [sectionPrefix, line.section]
            .where((value) => value.isNotEmpty && value != 'Unassigned')
            .join(' / ');
        final nested = kits
            .where((candidate) => candidate.id == line.productId)
            .firstOrNull;
        if (nested != null) {
          expand(nested, section.isEmpty ? nested.name : section, {...path});
        } else {
          lines.add(
            BuildLine(
              id: 'BLDLINE-${DateTime.now().microsecondsSinceEpoch}-${lines.length}',
              productId: line.productId,
              name: _kitLineName(line),
              section: section.isEmpty ? 'Unassigned' : section,
              requiredQuantity: line.quantity,
            ),
          );
        }
      }
    }

    expand(kit, '', <String>{});
    final build = BuildRecord(
      id: 'BUILD-${DateTime.now().microsecondsSinceEpoch}',
      kitId: kit.id,
      name: '${kit.name} build',
      createdAt: DateTime.now(),
      createdBy: deviceName,
      ownerDeviceId: deviceId,
      ownerUserId: currentUserId,
      lines: lines,
    );
    setState(() {
      builds.insert(0, build);
      _recordAudit('create', 'build', build.id, {
        'kit': kit.name,
        'lines': lines.length.toString(),
      });
    });
    _persist();
    Navigator.of(context).pop();
    unawaited(_openBuildQueue(build, kit));
  }

  Future<void> _openBuildQueue(BuildRecord build, KitRecord kit) =>
      showDialog<void>(
        context: context,
        builder: (_) => BuildQueueDialog(
          build: build,
          kit: kit,
          kits: kits,
          products: products,
          availableQuantity: _availableInventoryQuantity,
          onAdjust: (lineId, use) => _adjustBuildInventory(build, lineId, use),
          canUse: currentRole.canOperateBuilds && _canOperateBuild(build),
          canShare:
              currentRole.canShareBuilds &&
              (_ownsBuild(build) || currentRole == WorkspaceRole.admin),
          onSharedChanged: (shared) => _setBuildShared(build, shared),
          onCompletedChanged: (completed) =>
              _setBuildCompleted(build, completed),
        ),
      );

  bool _ownsBuild(BuildRecord build) =>
      build.ownerDeviceId.isEmpty || build.ownerDeviceId == deviceId;

  bool _canViewBuild(BuildRecord build) =>
      build.shared || _ownsBuild(build) || currentRole == WorkspaceRole.admin;

  bool _canOperateBuild(BuildRecord build) =>
      build.shared || _ownsBuild(build) || currentRole == WorkspaceRole.admin;

  Future<bool> _setBuildShared(BuildRecord build, bool shared) async {
    if (!currentRole.canShareBuilds ||
        (!_ownsBuild(build) && currentRole != WorkspaceRole.admin)) {
      _showPermissionDenied('Only this build’s owner can change sharing.');
      return false;
    }
    setState(() {
      build.shared = shared;
      build.updatedAt = DateTime.now();
      _recordAudit(shared ? 'share' : 'unshare', 'build', build.id, {
        'shared': shared.toString(),
      });
    });
    _persist();
    return true;
  }

  Future<bool> _setBuildCompleted(BuildRecord build, bool completed) async {
    if (!currentRole.canOperateBuilds || !_canOperateBuild(build)) {
      _showPermissionDenied('This private build belongs to another device.');
      return false;
    }
    final allUsed = build.lines.every(
      (line) => line.usedQuantity >= line.requiredQuantity,
    );
    if (completed && !allUsed) {
      _showPermissionDenied(
        'Complete every component before closing the build.',
      );
      return false;
    }
    setState(() {
      build.completedAt = completed ? DateTime.now() : null;
      build.updatedAt = DateTime.now();
      _recordAudit(completed ? 'complete' : 'reopen', 'build', build.id, {});
    });
    _persist();
    return true;
  }

  Future<bool> _adjustBuildInventory(
    BuildRecord build,
    String lineId,
    bool use,
  ) async {
    if (!currentRole.canOperateBuilds || !_canOperateBuild(build)) {
      _showPermissionDenied('This private build belongs to another device.');
      return false;
    }
    if (build.completedAt != null) return false;
    final lineIndex = build.lines.indexWhere((line) => line.id == lineId);
    if (lineIndex < 0) return false;
    final line = build.lines[lineIndex];
    if (use && line.usedQuantity >= line.requiredQuantity) return false;
    if (!use && line.usedQuantity <= 0) return false;

    InventoryItem? item;
    if (use) {
      item = inventory
          .where(
            (candidate) =>
                !candidate.archived &&
                candidate.quantity > 0 &&
                (candidate.catalogProductId == line.productId ||
                    _normalized(candidate.name) == _normalized(line.name)),
          )
          .firstOrNull;
      if (item == null) {
        _showPermissionDenied('No available inventory for ${line.name}.');
        return false;
      }
    } else {
      final consumedId = line.consumedInventoryIds.lastOrNull;
      item = inventory
          .where((candidate) => candidate.id == consumedId)
          .firstOrNull;
      if (item == null) return false;
    }

    final amount = use
        ? (line.requiredQuantity - line.usedQuantity).clamp(0, 1).toDouble()
        : line.usedQuantity.clamp(0, 1).toDouble();
    final consumed = [...line.consumedInventoryIds];
    if (use) {
      consumed.add(item.id);
    } else if (consumed.isNotEmpty) {
      consumed.removeLast();
    }
    setState(() {
      replaceInventoryItemById(
        inventory,
        item!.id,
        item.copyWith(quantity: item.quantity + (use ? -amount : amount)),
      );
      build.lines[lineIndex] = line.copyWith(
        usedQuantity: line.usedQuantity + (use ? amount : -amount),
        consumedInventoryIds: consumed,
      );
      build.updatedAt = DateTime.now();
      _recordAudit(use ? 'use' : 'unuse', 'build', build.id, {
        'line': line.name,
        'inventoryId': item.id,
        'quantity': amount.toString(),
      });
    });
    _persist();
    return true;
  }

  Future<void> _showKitContextMenu(KitRecord kit, Offset position) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit kit / BOM'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
    if (action == 'edit' && mounted) await _openKitEditor(kit);
  }

  Future<void> _openScanner() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventoryQrScanner(
          onCode: (code, mode, imageBytes) =>
              unawaited(_handleScannedCode(code, mode, imageBytes)),
          onLabelCapture: _ingestCapturedLabel,
        ),
      ),
    );
  }

  List<InventoryItem> get _moistureAlerts =>
      inventory.where((item) {
        if (item.archived ||
            item.type != InventoryType.filament ||
            !item.moistureAlertEnabled ||
            item.moistureAlertThresholdMinutes == null) {
          return false;
        }
        final remaining = _moistureRemaining(item);
        return remaining != null &&
            remaining <= Duration(minutes: item.moistureAlertThresholdMinutes!);
      }).toList()..sort((a, b) {
        final left = _moistureRemaining(a) ?? Duration.zero;
        final right = _moistureRemaining(b) ?? Duration.zero;
        return left.compareTo(right);
      });

  List<InventoryItem> get _quantityAlerts =>
      inventory
          .where(
            (item) =>
                !item.archived &&
                item.quantityAlertThreshold != null &&
                item.quantity <= item.quantityAlertThreshold!,
          )
          .toList()
        ..sort((a, b) => a.quantity.compareTo(b.quantity));

  int get _inventoryAlertCount => {
    ..._moistureAlerts.map((item) => item.id),
    ..._quantityAlerts.map((item) => item.id),
  }.length;

  Future<void> _openDebugPanel() async {
    final result = await showDialog<({String itemId, DebugCardEffect effect})>(
      context: context,
      builder: (_) => DebugPanelDialog(items: visibleItems),
    );
    if (result == null || !mounted) return;
    setState(() {
      final versions = switch (result.effect) {
        DebugCardEffect.remoteQuantity => _remoteQuantityAnimationVersions,
        DebugCardEffect.lowStock => _lowStockAnimationVersions,
        DebugCardEffect.moistureThreshold => _moistureAnimationVersions,
      };
      versions[result.itemId] = (versions[result.itemId] ?? 0) + 1;
    });
  }

  Future<void> _openAnimationControls() => showDialog<void>(
    context: context,
    builder: (_) => AnimationControlsDialog(
      animationDurationPercent: animationDurationPercent,
      animationRecurrenceSeconds: animationRecurrenceSeconds,
      onSettingsChanged: _updateAnimationSettings,
    ),
  );

  void _updateAnimationSettings(int durationPercent, int recurrenceSeconds) {
    setState(() {
      animationDurationPercent = durationPercent;
      animationRecurrenceSeconds = recurrenceSeconds;
    });
    widget.database?.saveStringPreference(
      'animation_duration_percent',
      '$durationPercent',
    );
    widget.database?.saveStringPreference(
      'animation_recurrence_seconds',
      '$recurrenceSeconds',
    );
  }

  Future<void> _openMoistureAlerts() => showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final moistureAlerts = _moistureAlerts;
        final quantityAlerts = _quantityAlerts;
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.notifications_outlined),
              SizedBox(width: 10),
              Text('Inventory alerts'),
            ],
          ),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(
              children: [
                SwitchListTile(
                  key: const Key('drying-complete-chime-toggle'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Drying-complete chime'),
                  subtitle: const Text(
                    'This setting applies only to this device.',
                  ),
                  value: dryingCompleteChimeEnabled,
                  onChanged: (value) {
                    setState(() => dryingCompleteChimeEnabled = value);
                    setDialogState(() {});
                    widget.database?.saveBoolPreference(
                      'drying_complete_chime_enabled',
                      value,
                    );
                  },
                ),
                SwitchListTile(
                  key: const Key('moisture-alert-chime-toggle'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Moisture-threshold chime'),
                  subtitle: const Text(
                    'Plays once per filament and drying cycle.',
                  ),
                  value: moistureAlertChimeEnabled,
                  onChanged: (value) {
                    setState(() => moistureAlertChimeEnabled = value);
                    setDialogState(() {});
                    widget.database?.saveBoolPreference(
                      'moisture_alert_chime_enabled',
                      value,
                    );
                  },
                ),
                const Divider(),
                Expanded(
                  child: moistureAlerts.isEmpty && quantityAlerts.isEmpty
                      ? const Center(child: Text('No inventory alerts.'))
                      : ListView(
                          children: [
                            if (quantityAlerts.isNotEmpty) ...[
                              const ListTile(
                                dense: true,
                                title: Text(
                                  'LOW STOCK',
                                  style: TextStyle(
                                    color: Color(0xffffa552),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              ...quantityAlerts.map(
                                (item) => ListTile(
                                  leading: const Icon(
                                    Icons.inventory_2_outlined,
                                    color: Color(0xffffa552),
                                  ),
                                  title: Text(item.name),
                                  subtitle: Text(
                                    '${_formatBomQuantity(item.quantity)} remaining · alert at ${_formatBomQuantity(item.quantityAlertThreshold!)}',
                                  ),
                                  onTap: () {
                                    Navigator.pop(dialogContext);
                                    _openDetails(item);
                                  },
                                ),
                              ),
                            ],
                            if (moistureAlerts.isNotEmpty) ...[
                              const ListTile(
                                dense: true,
                                title: Text(
                                  'MOISTURE',
                                  style: TextStyle(
                                    color: Color(0xff9c83ff),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              ...moistureAlerts.map((item) {
                                final remaining = _moistureRemaining(item)!;
                                return ListTile(
                                  leading: Icon(
                                    Icons.water_drop_rounded,
                                    color: remaining <= Duration.zero
                                        ? const Color(0xffff6b6b)
                                        : const Color(0xffffa552),
                                  ),
                                  title: Text(item.name),
                                  subtitle: Text(_moistureRemainingLabel(item)),
                                  onTap: () {
                                    Navigator.pop(dialogContext);
                                    _openDetails(item);
                                  },
                                );
                              }),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ),
  );

  Future<void> _openAdditionHistory() => showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.new_releases_outlined),
            SizedBox(width: 10),
            Text('New items'),
          ],
        ),
        content: SizedBox(
          width: 520,
          height: 520,
          child: Column(
            children: [
              Row(
                children: [
                  Text('${additionHistory.length} additions preserved'),
                  const Spacer(),
                  const Text('Keep'),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    key: const Key('history-limit'),
                    value: historyLimit,
                    items: const [20, 50, 100, 500, 2000]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        historyLimit = value;
                        _trimAdditionHistory();
                      });
                      setDialogState(() {});
                      _persist();
                    },
                  ),
                ],
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.devices_outlined),
                title: const Text('This device'),
                subtitle: Text(deviceName),
                trailing: IconButton(
                  key: const Key('rename-device'),
                  tooltip: 'Rename this device',
                  onPressed: () async {
                    if (await _renameThisDevice()) setDialogState(() {});
                  },
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
              SwitchListTile(
                key: const Key('sync-chime-toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Chime for remotely added items'),
                subtitle: const Text(
                  'This setting applies only to this device.',
                ),
                value: syncChimeEnabled,
                onChanged: (value) {
                  setState(() => syncChimeEnabled = value);
                  setDialogState(() {});
                  widget.database?.saveBoolPreference(
                    'sync_chime_enabled',
                    value,
                  );
                },
              ),
              const Divider(),
              Expanded(
                child: additionHistory.isEmpty
                    ? const Center(child: Text('No additions recorded yet.'))
                    : ListView.separated(
                        itemCount: additionHistory.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = additionHistory[index];
                          final local = entry.addedAt.toLocal();
                          final when =
                              '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
                              '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
                          return ListTile(
                            leading: const Icon(Icons.add_circle_outline),
                            title: Text(entry.name),
                            subtitle: Text(
                              '${_typeLabel(entry.type)} · ${entry.deviceName} · $when',
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );

  Future<bool> _renameThisDevice() async {
    final controller = TextEditingController(text: deviceName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name this device'),
        content: TextField(
          key: const Key('device-name'),
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            hintText: 'Workshop desktop, Pixel, Laptop…',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    final cleaned = name?.trim();
    if (cleaned == null || cleaned.isEmpty || !mounted) return false;
    setState(() => deviceName = cleaned);
    widget.database?.saveStringPreference('device_name', cleaned);
    return true;
  }

  void _persist() {
    widget.database?.saveState(_currentStateJson());
    if (!_applyingCloudState) {
      _syncDebounce?.cancel();
      _syncDebounce = Timer(
        const Duration(milliseconds: 700),
        _syncAutomatically,
      );
    }
  }

  String _currentStateJson() => encodeWorkshopState(
    inventory: inventory,
    vendors: vendors,
    brands: brands,
    spoolTypes: spoolTypes,
    customItemTypes: customItemTypes,
    products: products,
    machineTypes: machineTypes,
    machines: machines,
    kits: kits,
    builds: builds,
    auditLog: auditLog,
    additionHistory: additionHistory,
    historyLimit: historyLimit,
  );

  void _recordAddition(InventoryItem item) {
    additionHistory.removeWhere((entry) => entry.itemId == item.id);
    additionHistory.add(
      AdditionHistoryEntry.fromItem(item, deviceName: deviceName),
    );
    _trimAdditionHistory();
  }

  void _recordAudit(
    String action,
    String entityType,
    String entityId,
    Map<String, String> changes,
  ) {
    final entry = AuditEntry(
      id: 'AUD-${DateTime.now().microsecondsSinceEpoch}',
      timestamp: DateTime.now(),
      actor: deviceName,
      action: action,
      entityType: entityType,
      entityId: entityId,
      changes: changes,
    );
    auditLog.insert(0, entry);
    if (auditLog.length > 2000) auditLog.removeRange(2000, auditLog.length);
    _pendingAuditEvents.add({
      'action': action,
      'entityType': entityType,
      'entityId': entityId,
      'changes': changes,
    });
  }

  void _trimAdditionHistory() {
    additionHistory.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    if (additionHistory.length > historyLimit) {
      additionHistory.removeRange(historyLimit, additionHistory.length);
    }
  }

  void _applyCloudState(String source) {
    final restored = decodeWorkshopState(source);
    if (restored == null) {
      throw const FormatException('The cloud inventory could not be read.');
    }
    _applyingCloudState = true;
    var initializedKitSections = false;
    setState(() {
      inventory
        ..clear()
        ..addAll(restored.inventory);
      _initializeDryingTimers();
      vendors
        ..clear()
        ..addAll(restored.vendors);
      brands
        ..clear()
        ..addAll(restored.brands);
      spoolTypes
        ..clear()
        ..addAll(restored.spoolTypes);
      customItemTypes
        ..clear()
        ..addAll(restored.customItemTypes);
      products
        ..clear()
        ..addAll(restored.products);
      machineTypes
        ..clear()
        ..addAll(restored.machineTypes);
      machines
        ..clear()
        ..addAll(restored.machines);
      kits
        ..clear()
        ..addAll(restored.kits);
      initializedKitSections = _initializeKitSections();
      builds
        ..clear()
        ..addAll(restored.builds);
      auditLog
        ..clear()
        ..addAll(restored.auditLog);
      additionHistory
        ..clear()
        ..addAll(restored.additionHistory);
      historyLimit = restored.historyLimit;
      _trimAdditionHistory();
    });
    _persist();
    _applyingCloudState = false;
    if (initializedKitSections) unawaited(_syncAutomatically());
  }

  void _applyRemoteCloudState(String source) {
    final before = jsonDecode(_currentStateJson()) as Map<String, dynamic>;
    final after = jsonDecode(source) as Map<String, dynamic>;
    final incoming = decodeWorkshopState(source);
    final quantityChanges = incoming == null
        ? const <String>{}
        : remoteQuantityChangedItemIds(inventory, incoming.inventory);
    final lowStockEntries = incoming == null
        ? const <String>{}
        : lowStockEnteredItemIds(inventory, incoming.inventory);
    final inventoryChanged = !_sameJson(
      before['inventory'],
      after['inventory'],
    );
    _applyCloudState(source);
    if ((quantityChanges.isNotEmpty || lowStockEntries.isNotEmpty) && mounted) {
      setState(() {
        for (final id in quantityChanges) {
          _remoteQuantityAnimationVersions[id] =
              (_remoteQuantityAnimationVersions[id] ?? 0) + 1;
        }
        for (final id in lowStockEntries) {
          _lowStockAnimationVersions[id] =
              (_lowStockAnimationVersions[id] ?? 0) + 1;
        }
      });
    }
    _checkMoistureThresholdAnimations();
    if (inventoryChanged) unawaited(_playSyncChime());
  }

  Future<void> _playSyncChime() async {
    if (!syncChimeEnabled) return;
    try {
      if (Platform.isAndroid || Platform.isWindows) {
        await _audioChannel.invokeMethod<void>('playSyncChime');
        return;
      }
      if (Platform.isLinux) {
        final executableDirectory = File(Platform.resolvedExecutable)
            .parent
            .path;
        final sound =
            '$executableDirectory/data/flutter_assets/assets/audio/transhuman_sync.wav';
        final result = await Process.run('/usr/bin/paplay', [sound]);
        if (result.exitCode == 0) return;
      }
      await SystemSound.play(SystemSoundType.alert);
    } catch (error) {
      debugPrint('Could not play sync chime: $error');
    }
  }

  Future<void> _playDryingCompleteChime() async {
    if (!dryingCompleteChimeEnabled) return;
    try {
      if (Platform.isAndroid || Platform.isWindows) {
        await _audioChannel.invokeMethod<void>('playDryingCompleteChime');
        return;
      }
      if (Platform.isLinux) {
        final executableDirectory = File(Platform.resolvedExecutable)
            .parent
            .path;
        final sound =
            '$executableDirectory/data/flutter_assets/assets/audio/drying_complete.wav';
        final result = await Process.run('/usr/bin/paplay', [sound]);
        if (result.exitCode == 0) return;
      }
      await SystemSound.play(SystemSoundType.alert);
    } catch (error) {
      debugPrint('Could not play drying-complete chime: $error');
    }
  }

  Future<void> _playMoistureAlertChime() async {
    if (!moistureAlertChimeEnabled) return;
    try {
      if (Platform.isAndroid || Platform.isWindows) {
        await _audioChannel.invokeMethod<void>('playMoistureAlertChime');
        return;
      }
      if (Platform.isLinux) {
        final executableDirectory = File(Platform.resolvedExecutable)
            .parent
            .path;
        final sound =
            '$executableDirectory/data/flutter_assets/assets/audio/moisture_alert.wav';
        final result = await Process.run('/usr/bin/paplay', [sound]);
        if (result.exitCode == 0) return;
      }
      await SystemSound.play(SystemSoundType.alert);
    } catch (error) {
      debugPrint('Could not play moisture-alert chime: $error');
    }
  }

  Object? _sortedJson(Object? value) {
    if (value is List) return value.map(_sortedJson).toList();
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _sortedJson(value[key])};
    }
    return value;
  }

  String _canonicalJson(String source) =>
      jsonEncode(_sortedJson(jsonDecode(source)));

  bool _sameJson(Object? a, Object? b) =>
      jsonEncode(_sortedJson(a)) == jsonEncode(_sortedJson(b));

  Future<void> _syncAutomatically() async {
    final database = widget.database;
    if (database == null || _syncing) return;
    final saved = database.loadSyncConfig();
    if (saved == null) return;
    late SupabaseConfig config;
    try {
      config = SupabaseConfig.fromJson(
        jsonDecode(saved) as Map<String, dynamic>,
      );
    } catch (_) {
      return;
    }
    if (config.syncMode != 'supabase' ||
        !config.isConfigured ||
        !config.hasSession ||
        config.workspaceId == null) {
      return;
    }
    _syncing = true;
    try {
      final session = await SupabaseSyncService(config).refresh();
      config = config.copyWith(
        userId: session.userId,
        refreshToken: session.refreshToken,
      );
      // Supabase rotates refresh tokens. Persist the replacement before doing
      // any other network work so an interruption cannot strand this device.
      database.saveSyncConfig(jsonEncode(config.toJson()));
      var service = SupabaseSyncService(config);
      await service.requireCurrentSchema(session);
      try {
        final role = await service.currentRole(session);
        config = config.copyWith(workspaceRole: role);
        database.saveSyncConfig(jsonEncode(config.toJson()));
        if (mounted) {
          setState(() {
            currentRole = WorkspaceRole.fromServer(role);
            workspaceOwner = role == 'owner';
            currentUserId = session.userId;
          });
        }
        service = SupabaseSyncService(config);
      } catch (error) {
        debugPrint('Could not refresh workspace role: $error');
      }
      // Device registration only updates the friendly name and last-seen
      // metadata. It must never prevent the actual inventory from syncing if
      // an older server is missing the device-roles RPC or PostgREST has a
      // temporarily stale schema cache.
      try {
        await service.registerDevice(session, deviceName);
      } catch (error) {
        debugPrint('Device registration failed; continuing sync: $error');
      }
      final cloud = await service.download(session);
      final local = _canonicalJson(_currentStateJson());
      if (cloud == null) {
        final updated = await service.upload(
          session,
          local,
          auditEvents: _pendingAuditEvents,
        );
        config = config.copyWith(
          lastSyncedAt: updated,
          lastSyncedStateJson: local,
        );
      } else {
        final remote = _canonicalJson(cloud.stateJson);
        final previous = config.lastSyncedStateJson == null
            ? remote
            : _canonicalJson(config.lastSyncedStateJson!);
        final merged = mergeWorkshopStates(previous, local, remote);
        if (merged != local && mounted) _applyRemoteCloudState(merged);
        if (merged != remote) {
          final updated = await service.upload(
            session,
            merged,
            auditEvents: _pendingAuditEvents,
          );
          config = config.copyWith(lastSyncedAt: updated);
        } else {
          config = config.copyWith(lastSyncedAt: cloud.updatedAt);
        }
        config = config.copyWith(lastSyncedStateJson: merged);
      }
      database.saveSyncConfig(jsonEncode(config.toJson()));
      _pendingAuditEvents.clear();
      _lastSyncConflict = null;
    } on WorkshopMergeConflict catch (error) {
      if (mounted && _lastSyncConflict != error.path) {
        _lastSyncConflict = error.path;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sync paused: ${error.toString()} Open Cloud sync to choose which version to keep.',
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (error) {
      debugPrint('Automatic sync failed: $error');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _openCloudSync() async {
    final database = widget.database;
    if (database == null) return;
    final source = database.loadSyncConfig();
    if (source == null ||
        SupabaseConfig.fromJson(jsonDecode(source) as Map<String, dynamic>)
                .syncMode !=
            'supabase') {
      await _openSyncOnboarding();
      return;
    }
    _syncDebounce?.cancel();
    _syncPoll?.cancel();
    await showDialog<void>(
      context: context,
      builder: (_) => CloudSyncDialog(
        database: database,
        localStateJson: _currentStateJson(),
        onCloudState: _applyRemoteCloudState,
      ),
    );
    _startAutoSync();
  }

  Future<void> _openSyncOnboarding() async {
    final database = widget.database;
    if (database == null || !mounted) return;
    final choice = await showDialog<SyncOnboardingChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SyncOnboardingDialog(),
    );
    if (choice == null) return;
    final config = choice.config;
    if (config == null) {
      database.saveSyncConfig(
        jsonEncode(
          const SupabaseConfig(
            syncMode: 'local',
            url: '',
            publishableKey: '',
          ).toJson(),
        ),
      );
      return;
    }
    database.saveSyncConfig(jsonEncode(config.toJson()));
    if (mounted) {
      await _openCloudSync();
      _startAutoSync();
    }
  }

  Future<void> _openDatabaseSettings() async {
    final database = widget.database;
    if (database == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Local database'),
        content: SelectableText(
          'Inventorinator saves every inventory and catalog change automatically.\n\n${database.path}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          OutlinedButton.icon(
            key: const Key('import-database'),
            onPressed: () {
              Navigator.pop(dialogContext);
              _importDatabase();
            },
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('Import'),
          ),
          OutlinedButton.icon(
            key: const Key('export-database'),
            onPressed: () {
              Navigator.pop(dialogContext);
              _exportDatabase();
            },
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Export'),
          ),
          FilledButton.icon(
            key: const Key('delete-database'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: currentRole.canDeleteDatabase
                ? () async {
                    Navigator.pop(dialogContext);
                    await _confirmDeleteDatabase();
                  }
                : null,
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Delete database'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportDatabase() async {
    final database = widget.database;
    if (database == null) return;
    try {
      final bytes = await database.exportPortableDatabase();
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final destination = await FilePicker.saveFile(
        dialogTitle: 'Export Inventorinator database',
        fileName: 'inventorinator-$date.sqlite3',
        bytes: bytes,
        mimeType: 'application/vnd.sqlite3',
      );
      if (destination != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SQLite database exported.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Database export failed: $error')));
    }
  }

  Future<void> _importDatabase() async {
    final database = widget.database;
    if (database == null) return;
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Import Inventorinator database',
      type: FileType.custom,
      allowedExtensions: const ['sqlite3', 'sqlite', 'db'],
    );
    if (picked == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import this database?'),
        content: const Text(
          'This replaces the inventory on this device. Its Supabase connection stays intact, so imported items may synchronize to paired devices.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-import-database'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Import and replace'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final bytes = await picked.readAsBytes();
      final state = await database.importPortableDatabase(bytes);
      _applyCloudState(state);
      _syncDebounce?.cancel();
      _syncDebounce = Timer(
        const Duration(milliseconds: 700),
        _syncAutomatically,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SQLite database imported.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Database import failed: $error')));
    }
  }

  Future<void> _confirmDeleteDatabase() async {
    if (!currentRole.canDeleteDatabase) {
      _showPermissionDenied('Only an Admin can delete the database.');
      return;
    }
    final firstConfirmation = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete the entire database?'),
        content: const Text(
          'This permanently removes inventory, archives, brands, vendors, products, images, barcodes, and instructions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('continue-delete-database'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('I understand, continue'),
          ),
        ],
      ),
    );
    if (firstConfirmation != true || !mounted) return;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Final confirmation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Type delete to permanently erase the database.'),
              const SizedBox(height: 14),
              TextField(
                key: const Key('delete-database-confirmation'),
                controller: controller,
                autofocus: true,
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm-delete-database'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: controller.text == 'delete'
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Delete everything'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed != true || !mounted) return;
    await widget.database!.deleteAndRecreate();
    if (!mounted) return;
    setState(() {
      inventory.clear();
      vendors.clear();
      brands.clear();
      products.clear();
      machineTypes.clear();
      machines.clear();
      kits.clear();
      additionHistory.clear();
      archivedOnly = false;
      type = null;
    });
    _persist();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Local database permanently deleted.')),
    );
  }

  Future<void> _handleScannedCode(
    String rawCode,
    ScanMode mode,
    Uint8List? imageBytes,
  ) async {
    final value = rawCode.trim();
    if (mode == ScanMode.ingest) {
      if (imageBytes != null) {
        final knownProduct = inventory
            .where((item) => item.barcode == value)
            .firstOrNull;
        Navigator.of(context).pop();
        await _addItem(
          initialBarcode: value,
          productTemplate: knownProduct,
          labelDraft: LabelOcrDraft(imageBytes: imageBytes),
        );
      } else {
        final knownProduct = inventory
            .where((item) => item.barcode == value)
            .firstOrNull;
        Navigator.of(context).pop();
        await _addItem(initialBarcode: value, productTemplate: knownProduct);
      }
      return;
    }
    final id = value.startsWith('inventorinator:item:')
        ? value.substring('inventorinator:item:'.length)
        : value;
    InventoryItem? match;
    for (final candidate in inventory) {
      if (candidate.id.toLowerCase() == id.toLowerCase()) {
        match = candidate;
        break;
      }
    }
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No inventory item matches “$id”.')),
      );
      return;
    }
    Navigator.of(context).pop();
    _openDetails(match);
  }

  Future<void> _ingestCapturedLabel(
    Uint8List imageBytes, {
    String barcode = '',
  }) async {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    LabelOcrDraft draft;
    try {
      draft = await recognizeProductLabel(imageBytes);
    } on LabelOcrUnavailable catch (error) {
      draft = LabelOcrDraft(imageBytes: imageBytes);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      draft = LabelOcrDraft(imageBytes: imageBytes);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Label OCR failed: $error')));
      }
    }
    if (!mounted) return;
    final knownProduct = inventory
        .where((item) => barcode.isNotEmpty && item.barcode == barcode)
        .firstOrNull;
    await _addItem(
      initialBarcode: barcode,
      productTemplate: knownProduct,
      labelDraft: draft,
    );
  }

  Widget _header() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 920;
      final narrow = constraints.maxWidth < 600;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 20,
          20,
          compact ? 12 : 20,
          14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (compact) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _scanButton(),
                    const SizedBox(width: 8),
                    _rapidizerButton(),
                    const SizedBox(width: 8),
                    ..._centerHeaderActions(),
                    const SizedBox(width: 8),
                    ..._databaseHeaderActions(),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _headerIdentity(showText: !narrow, compactLogo: narrow),
                  SizedBox(width: narrow ? 4 : 12),
                  _catalogButton(),
                  const Spacer(),
                  _viewToggle(),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  _scanButton(),
                  const SizedBox(width: 8),
                  _rapidizerButton(),
                  Expanded(
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _centerHeaderActions(),
                      ),
                    ),
                  ),
                  ..._databaseHeaderActions(),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _headerIdentity(),
                  const SizedBox(width: 16),
                  _catalogButton(),
                  const Spacer(),
                  _viewToggle(),
                ],
              ),
            ],
            const SizedBox(height: 22),
            TextField(
              onChanged: (value) => setState(() {
                query = value;
                currentPage = 0;
              }),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: compact
                    ? 'Search inventory…'
                    : 'Search items, types, compatibility…  Try “E3DV6”',
                suffixIcon: const Icon(Icons.tune_rounded),
              ),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _typeChip(null, 'Everything'),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      key: const Key('archived-view'),
                      avatar: const Icon(Icons.archive_outlined, size: 18),
                      label: const Text('Archived'),
                      selected: archivedOnly,
                      onSelected: (selected) => setState(() {
                        archivedOnly = selected;
                        catalogFilter = null;
                        if (selected) type = null;
                        currentPage = 0;
                      }),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                    ),
                  ),
                  _catalogFilterChip(
                    CatalogViewFilter.kits,
                    'Kits',
                    Icons.inventory_2_outlined,
                  ),
                  _catalogFilterChip(
                    CatalogViewFilter.builds,
                    'Builds',
                    Icons.construction_rounded,
                  ),
                  _catalogFilterChip(
                    CatalogViewFilter.machines,
                    'Machines',
                    Icons.precision_manufacturing_outlined,
                  ),
                  _catalogFilterChip(
                    CatalogViewFilter.printers,
                    'Printers',
                    Icons.print_outlined,
                  ),
                  _catalogFilterChip(
                    CatalogViewFilter.tools,
                    'Tools',
                    Icons.handyman_outlined,
                  ),
                  ...InventoryType.values.map(
                    (value) => _typeChip(value, _typeLabel(value)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (compact) ...[
              Row(
                children: [
                  _resultCount(),
                  const Spacer(),
                  if (catalogFilter == null) _sortControl(),
                ],
              ),
              const SizedBox(height: 4),
              _pageSizeControl(expandSlider: true),
            ] else
              Row(
                children: [
                  _resultCount(),
                  const Spacer(),
                  if (catalogFilter == null) ...[
                    _sortControl(showLabel: true),
                    const SizedBox(width: 12),
                  ],
                  _pageSizeControl(),
                ],
              ),
          ],
        ),
      );
    },
  );

  Widget _resultCount() => Text(
    catalogFilter == null
        ? archivedOnly
              ? '${visibleItems.length} archived'
              : '${visibleItems.length} items'
        : '${visibleCatalogRecords.length} ${switch (catalogFilter!) {
            CatalogViewFilter.kits => 'kits',
            CatalogViewFilter.builds => 'builds',
            CatalogViewFilter.machines => 'machines',
            CatalogViewFilter.printers => 'printers',
            CatalogViewFilter.tools => 'tools',
          }}',
    style: const TextStyle(
      color: Color(0xff9da5b7),
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _sortControl({bool showLabel = false}) {
    final dropdown = DropdownButton<InventorySort>(
      value: sort,
      isExpanded: !showLabel,
      underline: const SizedBox(),
      borderRadius: BorderRadius.circular(16),
      items: const [
        DropdownMenuItem(value: InventorySort.type, child: Text('Type')),
        DropdownMenuItem(value: InventorySort.age, child: Text('Age')),
        DropdownMenuItem(value: InventorySort.cost, child: Text('Cost')),
        DropdownMenuItem(
          value: InventorySort.dryingTime,
          child: Text('Drying time'),
        ),
        DropdownMenuItem(
          value: InventorySort.moistureRemaining,
          child: Text('Moisture remaining'),
        ),
      ],
      onChanged: (value) => setState(() {
        sort = value!;
        currentPage = 0;
      }),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel) ...[
          const Text(
            'Sort',
            style: TextStyle(color: Color(0xff7f8798), fontSize: 12),
          ),
          const SizedBox(width: 8),
          dropdown,
        ] else
          SizedBox(width: 140, child: dropdown),
      ],
    );
  }

  Widget _pageSizeControl({bool expandSlider = false}) {
    final slider = Slider(
      key: const Key('page-size-slider'),
      value: pageSizeIndex.toDouble(),
      min: 0,
      max: (_pageSizes.length - 1).toDouble(),
      divisions: _pageSizes.length - 1,
      label: '${_pageSizes[pageSizeIndex]}',
      onChanged: (value) => setState(() {
        pageSizeIndex = value.round();
        currentPage = 0;
      }),
    );
    return Row(
      mainAxisSize: expandSlider ? MainAxisSize.max : MainAxisSize.min,
      children: [
        const Text(
          'Page size',
          style: TextStyle(color: Color(0xff7f8798), fontSize: 12),
        ),
        if (expandSlider)
          Expanded(child: slider)
        else
          SizedBox(width: 190, child: slider),
        SizedBox(
          width: 38,
          child: Text(
            '${_pageSizes[pageSizeIndex]}',
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _headerIdentity({bool showText = true, bool compactLogo = false}) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: compactLogo ? 58 : 75,
            height: compactLogo ? 50 : 62,
            child: Image.asset(
              'assets/images/inventorinator-raygun-v2.png',
              key: const Key('inventorinator-logo'),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          if (showText) ...[
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INVENTORINATOR',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    fontSize: 17,
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Take over '),
                      TextSpan(
                        text: 'the world',
                        style: TextStyle(
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      TextSpan(text: ' the shop!'),
                    ],
                  ),
                  style: TextStyle(color: Color(0xff8f96a7), fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      );

  Widget _scanButton() => OutlinedButton.icon(
    key: const Key('open-scanner'),
    onPressed: _openScanner,
    icon: const Icon(Icons.qr_code_scanner_rounded),
    label: const Text('Scan'),
  );

  Widget _rapidizerButton() => OutlinedButton.icon(
    key: const Key('open-rapidizer'),
    onPressed: _openRapidizer,
    icon: const Icon(Icons.bolt_rounded),
    label: const Text('Rapidizer'),
  );

  List<Widget> _centerHeaderActions() => [
    OutlinedButton.icon(
      key: const Key('moisture-alerts'),
      onPressed: _openMoistureAlerts,
      icon: Badge.count(
        count: _inventoryAlertCount,
        isLabelVisible: _inventoryAlertCount > 0,
        child: const Icon(Icons.notifications_outlined),
      ),
      label: const Text('Alerts'),
    ),
    const SizedBox(width: 8),
    OutlinedButton.icon(
      key: const Key('addition-history'),
      onPressed: _openAdditionHistory,
      icon: const Icon(Icons.new_releases_outlined),
      label: const Text('New items'),
    ),
  ];

  List<Widget> _databaseHeaderActions() => [
    IconButton.outlined(
      key: const Key('database-settings'),
      tooltip: 'Local database',
      onPressed: widget.database == null ? null : _openDatabaseSettings,
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.storage_rounded),
    ),
    const SizedBox(width: 5),
    IconButton.outlined(
      key: const Key('cloud-sync'),
      tooltip: 'Cloud sync',
      onPressed: widget.database == null ? null : _openCloudSync,
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.cloud_sync_outlined),
    ),
    const SizedBox(width: 5),
    IconButton.outlined(
      key: const Key('animation-controls'),
      tooltip: 'Animation controls',
      onPressed: _openAnimationControls,
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.animation_rounded),
    ),
    const SizedBox(width: 5),
    IconButton.outlined(
      key: const Key('debug-panel'),
      tooltip: 'Debug effects',
      onPressed: _openDebugPanel,
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.bug_report_outlined),
    ),
    const SizedBox(width: 5),
    IconButton.outlined(
      key: const Key('audit-log'),
      tooltip: 'Change log',
      onPressed: _openAuditLog,
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.history_rounded),
    ),
  ];

  Future<void> _openAuditLog() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Change log'),
      content: SizedBox(
        width: 680,
        height: 560,
        child: auditLog.isEmpty
            ? const Center(child: Text('No recorded changes yet.'))
            : ListView.separated(
                itemCount: auditLog.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = auditLog[index];
                  return ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(
                      '${entry.action.toUpperCase()} · ${entry.entityType}',
                    ),
                    subtitle: Text(
                      '${entry.actor} · ${entry.timestamp.toLocal()}\n${entry.changes.entries.map((change) => '${change.key}: ${change.value}').join(' · ')}',
                    ),
                    isThreeLine: true,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Widget _catalogButton() => OutlinedButton.icon(
    key: const Key('open-catalog'),
    onPressed: currentRole.canManageCatalog ? _openCatalog : null,
    icon: const Icon(Icons.category_outlined),
    label: const Text('Catalog'),
  );

  Widget _viewToggle() => SegmentedButton<bool>(
    segments: const [
      ButtonSegment(
        value: false,
        icon: Icon(Icons.view_agenda_outlined),
        tooltip: 'List view',
      ),
      ButtonSegment(
        value: true,
        icon: Icon(Icons.grid_view_rounded),
        tooltip: 'Grid view',
      ),
    ],
    selected: {gridView},
    showSelectedIcon: false,
    onSelectionChanged: (value) => setState(() => gridView = value.first),
  );
  Widget _typeChip(InventoryType? value, String label) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      label: Text(label),
      selected:
          catalogFilter == null &&
          type == value &&
          (value != null || !archivedOnly),
      onSelected: (_) => setState(() {
        type = value;
        catalogFilter = null;
        archivedOnly = false;
        currentPage = 0;
      }),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    ),
  );

  Widget _catalogFilterChip(
    CatalogViewFilter value,
    String label,
    IconData icon,
  ) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      key: Key('catalog-filter-${value.name}'),
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: catalogFilter == value,
      onSelected: (_) => setState(() {
        catalogFilter = value;
        type = null;
        archivedOnly = false;
        currentPage = 0;
      }),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    ),
  );

  Widget _catalogRecordCard(Object record, {bool list = false}) {
    late final IconData icon;
    late final Color accent;
    late final String category;
    late final String title;
    late final String subtitle;
    late final String detail;
    if (record is KitRecord) {
      final totalUnits = record.bom.fold<double>(
        0,
        (total, entry) => total + entry.quantity,
      );
      final totalLabel = totalUnits == totalUnits.roundToDouble()
          ? totalUnits.toInt().toString()
          : totalUnits.toStringAsFixed(2);
      final machineCount = machines
          .where((machine) => machine.kitIds.contains(record.id))
          .length;
      icon = Icons.inventory_2_outlined;
      accent = const Color(0xffa987ff);
      category = 'KIT';
      title = record.name;
      subtitle = '${record.bom.length} BOM lines · $totalLabel units';
      detail = machineCount == 0
          ? 'Not assigned to a machine'
          : '$machineCount compatible ${machineCount == 1 ? 'machine' : 'machines'}';
    } else if (record is BuildRecord) {
      final used = record.lines.fold<double>(
        0,
        (total, line) => total + line.usedQuantity,
      );
      final required = record.lines.fold<double>(
        0,
        (total, line) => total + line.requiredQuantity,
      );
      icon = Icons.construction_rounded;
      accent = const Color(0xffffb34d);
      category = 'BUILD';
      title = record.name;
      subtitle =
          '${record.lines.length} lines · ${_formatBomQuantity(used)} / ${_formatBomQuantity(required)} used';
      detail = [
        record.completedAt == null ? 'Active' : 'Completed',
        record.shared ? 'Shared' : 'Unshared',
        'Created by ${record.createdBy}',
      ].join(' · ');
    } else {
      final machine = record as MachineRecord;
      final printer = _isPrinter(machine);
      icon = printer ? Icons.print_outlined : Icons.handyman_outlined;
      accent = printer ? const Color(0xff42d8c7) : const Color(0xffffb34d);
      category = printer ? 'PRINTER' : 'TOOL';
      title = machine.name;
      subtitle = [
        machine.model,
        _machineTypePath(machine.typeId),
      ].where((value) => value.trim().isNotEmpty).join(' · ');
      detail = machine.address.trim().isEmpty
          ? machine.kitIds.isEmpty
                ? 'No address or kit assigned'
                : '${machine.kitIds.length} associated ${machine.kitIds.length == 1 ? 'kit' : 'kits'}'
          : machine.address;
    }
    final content = list
        ? ListTile(
            leading: Icon(icon, color: accent),
            title: Text(title),
            subtitle: Text('$category · $subtitle\n$detail'),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right_rounded),
          )
        : Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: accent, size: 30),
                const Spacer(),
                Text(
                  category,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xffa4abba)),
                ),
                const SizedBox(height: 8),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff7f8798),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: record is KitRecord
            ? () => _openKitDetails(record)
            : record is BuildRecord
            ? () {
                final kit = kits
                    .where((candidate) => candidate.id == record.kitId)
                    .firstOrNull;
                if (kit != null) _openBuildQueue(record, kit);
              }
            : _openCatalog,
        onSecondaryTapDown: record is KitRecord
            ? (details) => _showKitContextMenu(record, details.globalPosition)
            : null,
        onLongPress: record is KitRecord ? () => _openKitEditor(record) : null,
        child: content,
      ),
    );
  }

  Widget _pageNavigation(int page, int pageCount, int totalItems) {
    final first = (page - 2).clamp(0, (pageCount - 5).clamp(0, pageCount));
    final last = (first + 5).clamp(0, pageCount);
    return Column(
      children: [
        Text(
          'Page ${page + 1} of $pageCount · $totalItems results',
          style: const TextStyle(color: Color(0xff929aac), fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          children: [
            IconButton.outlined(
              key: const Key('previous-page'),
              onPressed: page == 0 ? null : () => _changePage(page - 1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            for (var index = first; index < last; index++)
              index == page
                  ? IconButton.filled(
                      key: Key('page-${index + 1}'),
                      onPressed: null,
                      icon: Text('${index + 1}'),
                    )
                  : IconButton.outlined(
                      key: Key('page-${index + 1}'),
                      onPressed: () => _changePage(index),
                      icon: Text('${index + 1}'),
                    ),
            IconButton.outlined(
              key: const Key('next-page'),
              onPressed: page >= pageCount - 1
                  ? null
                  : () => _changePage(page + 1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ],
    );
  }

  void _changePage(int nextPage) {
    if (nextPage == currentPage) return;
    setState(() {
      pageMotionDirection = nextPage > currentPage ? 1 : -1;
      currentPage = nextPage;
      pageAnimationKey++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!inventoryScrollController.hasClients) return;
      inventoryScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }
}

class PageItemEntrance extends StatelessWidget {
  const PageItemEntrance({
    super.key,
    required this.pageKey,
    required this.index,
    required this.direction,
    required this.child,
  });
  final int pageKey;
  final int index;
  final int direction;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey('page-$pageKey-item-$index'),
    tween: Tween(begin: 0, end: 1),
    duration: Duration(milliseconds: 300 + (index.clamp(0, 12) * 24)),
    curve: Curves.easeOutBack,
    builder: (context, value, child) => Opacity(
      opacity: value.clamp(0, 1),
      child: Transform.translate(
        offset: Offset(direction * (1 - value) * 34, (1 - value) * 10),
        child: Transform.scale(
          scale: .97 + (.03 * value),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    ),
    child: child,
  );
}

class KitDetailsDialog extends StatelessWidget {
  const KitDetailsDialog({
    super.key,
    required this.kit,
    required this.kits,
    required this.products,
    required this.availableQuantity,
    required this.onBuild,
    this.canBuild = true,
    this.buildDisabledReason,
  });

  final KitRecord kit;
  final List<KitRecord> kits;
  final List<CatalogProduct> products;
  final double Function(String productId, String name) availableQuantity;
  final ValueChanged<KitRecord> onBuild;
  final bool canBuild;
  final String? buildDisabledReason;

  String _lineName(KitBomEntry line) =>
      line.name ??
      products
          .where((product) => product.id == line.productId)
          .firstOrNull
          ?.name ??
      kits.where((kit) => kit.id == line.productId).firstOrNull?.name ??
      'Missing item';

  Map<int, _LineStockStatus> _stockStatus() {
    final reserved = <String, double>{};
    final result = <int, _LineStockStatus>{};
    for (var index = 0; index < kit.bom.length; index++) {
      final line = kit.bom[index];
      if (kits.any((candidate) => candidate.id == line.productId)) continue;
      final name = _lineName(line);
      final key = line.productId.isEmpty
          ? 'name:${_normalizedStockName(name)}'
          : 'product:${line.productId}';
      final totalAvailable = availableQuantity(line.productId, name);
      final remaining = (totalAvailable - (reserved[key] ?? 0)).clamp(
        0,
        line.quantity,
      );
      reserved[key] = (reserved[key] ?? 0) + line.quantity;
      result[index] = _LineStockStatus(
        available: remaining.toDouble(),
        missing: (line.quantity - remaining).clamp(0, line.quantity).toDouble(),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final stock = _stockStatus();
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 860),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 14, 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    color: Color(0xffa987ff),
                    size: 30,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          kit.name,
                          key: const Key('kit-details-title'),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${kit.bom.length} BOM items',
                          style: const TextStyle(color: Color(0xff929aac)),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: canBuild
                        ? 'Create a new build'
                        : buildDisabledReason ?? 'You cannot create builds.',
                    child: FilledButton.icon(
                      key: const Key('build-kit'),
                      onPressed: canBuild ? () => onBuild(kit) : null,
                      icon: const Icon(Icons.construction_rounded),
                      label: const Text('Build'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (!canBuild)
              Container(
                key: const Key('build-disabled-reason'),
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xff332817),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xffa8782a)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.admin_panel_settings_outlined,
                      color: Color(0xffffc15c),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        buildDisabledReason ?? 'You cannot create builds.',
                        style: const TextStyle(color: Color(0xffffd79a)),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            if (kit.bom.isEmpty)
              const Expanded(
                child: Center(child: Text('This kit has no BOM items.')),
              )
            else
              Expanded(
                child: ListView.separated(
                  key: const Key('kit-details-list'),
                  padding: const EdgeInsets.all(10),
                  itemCount: kit.bom.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final line = kit.bom[index];
                    final lineStock = stock[index];
                    final missing = lineStock?.isMissing ?? false;
                    final nestedKit = kits
                        .where((candidate) => candidate.id == line.productId)
                        .firstOrNull;
                    final duplicate =
                        kit.bom
                            .where(
                              (candidate) =>
                                  candidate.productId == line.productId,
                            )
                            .length >
                        1;
                    return Card(
                      key: Key(
                        duplicate
                            ? 'kit-detail-line-${line.productId}-$index'
                            : 'kit-detail-line-${line.productId}',
                      ),
                      color: missing ? const Color(0xff351a22) : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: missing
                              ? const Color(0xffe45f72)
                              : const Color(0xff30384a),
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          missing
                              ? Icons.error_outline_rounded
                              : nestedKit == null
                              ? Icons.inventory_2_outlined
                              : Icons.account_tree_outlined,
                          color: missing
                              ? const Color(0xffff7b8e)
                              : nestedKit == null
                              ? const Color(0xff929aac)
                              : const Color(0xffa987ff),
                        ),
                        title: Text(_lineName(line)),
                        subtitle: nestedKit == null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (line.section != 'Unassigned')
                                    Text(line.section),
                                  Text(
                                    'Required ${_formatBomQuantity(line.quantity)} · Available ${_formatBomQuantity(lineStock?.available ?? 0)}${missing ? ' · Missing ${_formatBomQuantity(lineStock!.missing)}' : ''}',
                                    key: Key('kit-stock-$index'),
                                    style: TextStyle(
                                      color: missing
                                          ? const Color(0xffff9cab)
                                          : const Color(0xff929aac),
                                      fontWeight: missing
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              )
                            : Text('Kit · Open BOM · ${line.section}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '× ${_formatBomQuantity(line.quantity)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (nestedKit != null) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ],
                        ),
                        onTap: nestedKit == null
                            ? null
                            : () => showDialog<void>(
                                context: context,
                                builder: (_) => KitDetailsDialog(
                                  kit: nestedKit,
                                  kits: kits,
                                  products: products,
                                  availableQuantity: availableQuantity,
                                  onBuild: onBuild,
                                  canBuild: canBuild,
                                  buildDisabledReason: buildDisabledReason,
                                ),
                              ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BuildQueueDialog extends StatefulWidget {
  const BuildQueueDialog({
    super.key,
    required this.build,
    required this.kit,
    required this.kits,
    required this.products,
    required this.availableQuantity,
    required this.onAdjust,
    required this.canUse,
    required this.canShare,
    required this.onSharedChanged,
    required this.onCompletedChanged,
  });
  final BuildRecord build;
  final KitRecord kit;
  final List<KitRecord> kits;
  final List<CatalogProduct> products;
  final double Function(String productId, String name) availableQuantity;
  final Future<bool> Function(String lineId, bool use) onAdjust;
  final bool canUse;
  final bool canShare;
  final Future<bool> Function(bool shared) onSharedChanged;
  final Future<bool> Function(bool completed) onCompletedChanged;

  @override
  State<BuildQueueDialog> createState() => _BuildQueueDialogState();
}

class _BuildQueueDialogState extends State<BuildQueueDialog> {
  bool showKit = false;

  String _kitLineName(KitBomEntry line) =>
      line.name ??
      widget.products
          .where((product) => product.id == line.productId)
          .firstOrNull
          ?.name ??
      widget.kits.where((kit) => kit.id == line.productId).firstOrNull?.name ??
      'Missing item';

  Map<String, _LineStockStatus> _stockStatus() {
    final reserved = <String, double>{};
    final result = <String, _LineStockStatus>{};
    for (final line in widget.build.lines) {
      final needed = (line.requiredQuantity - line.usedQuantity).clamp(
        0,
        line.requiredQuantity,
      );
      final key = line.productId.isEmpty
          ? 'name:${_normalizedStockName(line.name)}'
          : 'product:${line.productId}';
      final totalAvailable = widget.availableQuantity(
        line.productId,
        line.name,
      );
      final available = (totalAvailable - (reserved[key] ?? 0)).clamp(
        0,
        needed,
      );
      reserved[key] = (reserved[key] ?? 0) + needed;
      result[line.id] = _LineStockStatus(
        available: available.toDouble(),
        missing: (needed - available).clamp(0, needed).toDouble(),
      );
    }
    return result;
  }

  Map<int, _LineStockStatus> _kitStockStatus() {
    final reserved = <String, double>{};
    final result = <int, _LineStockStatus>{};
    for (var index = 0; index < widget.kit.bom.length; index++) {
      final line = widget.kit.bom[index];
      final name = _kitLineName(line);
      final key = line.productId.isEmpty
          ? 'name:${_normalizedStockName(name)}'
          : 'product:${line.productId}';
      final totalAvailable = widget.availableQuantity(line.productId, name);
      final available = (totalAvailable - (reserved[key] ?? 0)).clamp(
        0,
        line.quantity,
      );
      reserved[key] = (reserved[key] ?? 0) + line.quantity;
      result[index] = _LineStockStatus(
        available: available.toDouble(),
        missing: (line.quantity - available).clamp(0, line.quantity).toDouble(),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<BuildLine>>{};
    for (final line in widget.build.lines) {
      grouped.putIfAbsent(line.section, () => []).add(line);
    }
    final allLinesUsed = widget.build.lines.every(
      (line) => line.usedQuantity >= line.requiredQuantity,
    );
    final completed = widget.build.completedAt != null;
    final stock = _stockStatus();
    final kitStock = _kitStockStatus();
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 900),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 16, 12, 12),
                    child: _buildHeader(allLinesUsed, completed),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        ...grouped.entries.map(
                          (section) => _buildSection(section, stock),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: showKit ? 360 : 0,
              decoration: const BoxDecoration(
                color: Color(0xff111620),
                border: Border(left: BorderSide(color: Color(0xff333b4d))),
              ),
              child: showKit
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            widget.kit.name,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: widget.kit.bom.length,
                            itemBuilder: (context, index) {
                              final line = widget.kit.bom[index];
                              final name = _kitLineName(line);
                              final lineStock = kitStock[index]!;
                              final available = lineStock.available;
                              final missing = lineStock.missing;
                              return Card(
                                color: missing > 0.0001
                                    ? const Color(0xff351a22)
                                    : null,
                                child: ListTile(
                                  dense: true,
                                  leading: missing > 0.0001
                                      ? const Icon(
                                          Icons.error_outline_rounded,
                                          color: Color(0xffff7b8e),
                                        )
                                      : null,
                                  title: Text(name),
                                  subtitle: Text(
                                    '${line.section}\nRequired ${_formatBomQuantity(line.quantity)} · Available ${_formatBomQuantity(available.clamp(0, line.quantity))}${missing > 0.0001 ? ' · Missing ${_formatBomQuantity(missing)}' : ''}',
                                  ),
                                  trailing: Text(
                                    '× ${_formatBomQuantity(line.quantity)}',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool allLinesUsed, bool completed) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.build.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          Text(
            'Build queue · ${widget.build.createdBy}',
            style: const TextStyle(color: Color(0xff929aac)),
          ),
        ],
      );
      final actions = <Widget>[
        FilterChip(
          key: const Key('share-build'),
          selected: widget.build.shared,
          onSelected: widget.canShare
              ? (value) async {
                  if (await widget.onSharedChanged(value) && mounted) {
                    setState(() {});
                  }
                }
              : null,
          avatar: Icon(
            widget.build.shared
                ? Icons.groups_rounded
                : Icons.lock_outline_rounded,
            size: 18,
          ),
          label: Text(widget.build.shared ? 'Shared' : 'Unshared'),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          key: const Key('complete-build'),
          onPressed: widget.canUse && (completed || allLinesUsed)
              ? () async {
                  if (await widget.onCompletedChanged(!completed) && mounted) {
                    setState(() {});
                  }
                }
              : null,
          icon: Icon(completed ? Icons.replay_rounded : Icons.task_alt_rounded),
          label: Text(completed ? 'Reopen' : 'Complete'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          key: const Key('toggle-build-kit-panel'),
          onPressed: () => setState(() => showKit = !showKit),
          icon: Icon(
            showKit
                ? Icons.close_fullscreen_rounded
                : Icons.view_sidebar_outlined,
          ),
          label: Text(showKit ? 'Hide kit' : 'Full kit'),
        ),
      ];
      final close = IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close_rounded),
      );
      if (constraints.maxWidth < 720) {
        return Column(
          children: [
            Row(
              children: [
                const Icon(
                  Icons.construction_rounded,
                  color: Color(0xffa987ff),
                ),
                const SizedBox(width: 10),
                Expanded(child: title),
                close,
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: actions),
            ),
          ],
        );
      }
      return Row(
        children: [
          const Icon(Icons.construction_rounded, color: Color(0xffa987ff)),
          const SizedBox(width: 10),
          Expanded(child: title),
          ...actions,
          const SizedBox(width: 8),
          close,
        ],
      );
    },
  );

  Widget _buildSection(
    MapEntry<String, List<BuildLine>> section,
    Map<String, _LineStockStatus> stock,
  ) {
    final used = section.value.fold<double>(
      0,
      (total, line) => total + line.usedQuantity,
    );
    final required = section.value.fold<double>(
      0,
      (total, line) => total + line.requiredQuantity,
    );
    final complete = used >= required;
    return Container(
      key: Key('build-section-${section.key}'),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xff131824),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: complete
              ? const Color(0xff42d8c7).withValues(alpha: .72)
              : const Color(0xff5f527f),
          width: 1.3,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
            child: Row(
              children: [
                Icon(
                  complete
                      ? Icons.check_circle_rounded
                      : Icons.account_tree_outlined,
                  color: complete
                      ? const Color(0xff42d8c7)
                      : const Color(0xffa987ff),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.key.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xffc8bbff),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                Text(
                  '${_formatBomQuantity(used)} / ${_formatBomQuantity(required)}',
                  style: const TextStyle(
                    color: Color(0xff929aac),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: section.value
                  .map((line) => _buildLine(line, stock[line.id]!))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLine(BuildLine line, _LineStockStatus stock) {
    final complete = line.usedQuantity >= line.requiredQuantity;
    final multiple = line.requiredQuantity > 1;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: complete ? .42 : 1,
      child: Card(
        key: Key('build-stock-${line.id}'),
        color: stock.isMissing ? const Color(0xff351a22) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: stock.isMissing
                ? const Color(0xffe45f72)
                : const Color(0xff30384a),
          ),
        ),
        child: ListTile(
          leading: Icon(
            complete
                ? Icons.check_circle_rounded
                : stock.isMissing
                ? Icons.error_outline_rounded
                : Icons.radio_button_unchecked,
            color: complete
                ? const Color(0xff42d8c7)
                : stock.isMissing
                ? const Color(0xffff7b8e)
                : null,
          ),
          title: Text(line.name),
          subtitle: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      '${_formatBomQuantity(line.usedQuantity)} / ${_formatBomQuantity(line.requiredQuantity)} used · ${_formatBomQuantity(stock.available)} available',
                ),
                if (stock.isMissing)
                  TextSpan(
                    text: ' · ${_formatBomQuantity(stock.missing)} missing',
                    style: const TextStyle(
                      color: Color(0xffff9cab),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          trailing: Wrap(
            spacing: 6,
            children: [
              OutlinedButton(
                onPressed:
                    !widget.canUse ||
                        widget.build.completedAt != null ||
                        line.usedQuantity <= 0
                    ? null
                    : () async {
                        if (await widget.onAdjust(line.id, false) && mounted) {
                          setState(() {});
                        }
                      },
                child: const Text('Unuse'),
              ),
              FilledButton(
                onPressed:
                    !widget.canUse ||
                        widget.build.completedAt != null ||
                        complete ||
                        stock.available <= 0
                    ? null
                    : () async {
                        if (await widget.onAdjust(line.id, true) && mounted) {
                          setState(() {});
                        }
                      },
                child: Text(multiple ? 'Use 1' : 'Use'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CatalogManagerDialog extends StatefulWidget {
  const CatalogManagerDialog({
    super.key,
    required this.vendors,
    required this.brands,
    required this.spoolTypes,
    required this.customItemTypes,
    required this.products,
    required this.machineTypes,
    required this.machines,
    required this.kits,
    required this.onVendorAdded,
    required this.onBrandAdded,
    required this.onSpoolTypeAdded,
    required this.onCustomItemTypeAdded,
    required this.onProductAdded,
    required this.onMachineTypeAdded,
    required this.onMachineAdded,
    required this.onKitAdded,
    required this.onKitUpdated,
    this.initialKitId,
  });
  final List<VendorRecord> vendors;
  final List<BrandRecord> brands;
  final List<SpoolTypeRecord> spoolTypes;
  final List<CustomItemTypeRecord> customItemTypes;
  final List<CatalogProduct> products;
  final List<MachineTypeRecord> machineTypes;
  final List<MachineRecord> machines;
  final List<KitRecord> kits;
  final ValueChanged<VendorRecord> onVendorAdded;
  final ValueChanged<BrandRecord> onBrandAdded;
  final ValueChanged<SpoolTypeRecord> onSpoolTypeAdded;
  final ValueChanged<CustomItemTypeRecord> onCustomItemTypeAdded;
  final ValueChanged<CatalogProduct> onProductAdded;
  final ValueChanged<MachineTypeRecord> onMachineTypeAdded;
  final ValueChanged<MachineRecord> onMachineAdded;
  final ValueChanged<KitRecord> onKitAdded;
  final ValueChanged<KitRecord> onKitUpdated;
  final String? initialKitId;

  @override
  State<CatalogManagerDialog> createState() => _CatalogManagerDialogState();
}

class _CatalogManagerDialogState extends State<CatalogManagerDialog> {
  final vendorName = TextEditingController();
  final brandName = TextEditingController();
  final spoolLabel = TextEditingController();
  final spoolWeightGrams = TextEditingController();
  final customTypeName = TextEditingController();
  final customTypeFields = TextEditingController();
  final productName = TextEditingController();
  final productCost = TextEditingController();
  final productDrying = TextEditingController();
  final printing = TextEditingController();
  final drying = TextEditingController();
  final storage = TextEditingController();
  final machineTypeName = TextEditingController();
  final machineName = TextEditingController();
  final machineModel = TextEditingController();
  final machineAddress = TextEditingController();
  final kitName = TextEditingController();
  late final List<VendorRecord> vendors = [...widget.vendors];
  late final List<BrandRecord> brands = [...widget.brands];
  late final List<SpoolTypeRecord> spoolTypes = [...widget.spoolTypes];
  late final List<CustomItemTypeRecord> customItemTypes = [
    ...widget.customItemTypes,
  ];
  late final List<CatalogProduct> products = [...widget.products];
  late final List<MachineTypeRecord> machineTypes = [...widget.machineTypes];
  late final List<MachineRecord> machines = [...widget.machines];
  late final List<KitRecord> kits = [...widget.kits];
  final List<KitBomEntry> draftBom = [];
  final List<String> draftSections = [];
  String? editingKitId;
  String? machineTypeParentId;
  String? selectedMachineTypeId;
  final Set<String> selectedMachineKitIds = {};
  String? brandVendorId;
  String? productBrandId;
  final Set<InventoryType> brandCategories = {};
  final Set<InventoryType> vendorBrandCategories = {};
  InventoryType? productCategory;
  bool vendorAlsoBrand = false;
  bool kitSectionExpanded = false;
  bool loadingInitialKit = false;
  Uint8List? vendorLogo;
  Uint8List? brandLogo;
  Uint8List? productImage;

  bool get kitOnly => widget.initialKitId != null;

  @override
  void initState() {
    super.initState();
    if (kitOnly) {
      kitSectionExpanded = true;
      loadingInitialKit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 180));
        if (!mounted) return;
        final initialKit = widget.kits
            .where((kit) => kit.id == widget.initialKitId)
            .firstOrNull;
        setState(() {
          if (initialKit != null) {
            editingKitId = initialKit.id;
            kitName.text = initialKit.name;
            draftBom.addAll(initialKit.bom);
            draftSections.addAll(_sectionsForKit(initialKit));
          }
          loadingInitialKit = false;
        });
      });
    }
  }

  @override
  void dispose() {
    vendorName.dispose();
    brandName.dispose();
    spoolLabel.dispose();
    spoolWeightGrams.dispose();
    customTypeName.dispose();
    customTypeFields.dispose();
    productName.dispose();
    productCost.dispose();
    productDrying.dispose();
    printing.dispose();
    drying.dispose();
    storage.dispose();
    machineTypeName.dispose();
    machineName.dispose();
    machineModel.dispose();
    machineAddress.dispose();
    kitName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 860),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kitOnly ? 'Kit / BOM' : 'Product catalog',
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        kitOnly ? 'Edit this kit and its bill of materials' : 'Sources, makers, and reusable product definitions',
                        style: const TextStyle(color: Color(0xff929aac)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: kitOnly
                ? loadingInitialKit
                      ? const _KitBomLoadingState()
                      : _kitOnlyBomList()
                : ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      ExpansionTile(
                        key: const Key('catalog-item-types-section'),
                        leading: const Icon(Icons.tune_rounded),
                        title: Text(
                          'Item types (${InventoryType.values.length - 1 + customItemTypes.length})',
                        ),
                        subtitle: const Text(
                          'Built-in behavior and your own contextual fields',
                        ),
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final type in InventoryType.values.where(
                                (type) => type != InventoryType.custom,
                              ))
                                Chip(
                                  avatar: Icon(_typeIcon(type), size: 18),
                                  label: Text(_typeLabel(type)),
                                ),
                              for (final type in customItemTypes)
                                Chip(
                                  avatar: const Icon(
                                    Icons.tune_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    type.contextualFields.isEmpty
                                        ? type.name
                                        : '${type.name} · ${type.contextualFields.join(', ')}',
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('new-custom-type-name'),
                            controller: customTypeName,
                            decoration: const InputDecoration(
                              labelText: 'New item type',
                              hintText: 'Soap batch',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            key: const Key('new-custom-type-fields'),
                            controller: customTypeFields,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Contextual fields',
                              hintText: 'Cure time, Mold, Fragrance',
                              helperText: 'Separate field names with commas or new lines',
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              key: const Key('add-custom-type'),
                              onPressed: _addCustomItemType,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add type'),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                      ExpansionTile(
                        key: const Key('catalog-vendors-section'),
                        initiallyExpanded: true,
                        leading: const Icon(Icons.storefront_outlined),
                        title: Text('Vendors (${vendors.length})'),
                        subtitle: const Text('Where products are purchased'),
                        children: [
                          Wrap(
                            spacing: 8,
                            children: vendors
                                .map(
                                  (vendor) => Chip(
                                    avatar: _LogoAvatar(
                                      bytes: vendor.logoBytes,
                                      fallbackIcon: Icons.storefront_outlined,
                                    ),
                                    label: Text(vendor.name),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: 220,
                                child: TextField(
                                  key: const Key('new-vendor-name'),
                                  controller: vendorName,
                                  decoration: const InputDecoration(
                                    labelText: 'New vendor',
                                    hintText: 'Printed Solid',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton(
                                key: const Key('add-vendor'),
                                onPressed: _addVendor,
                                child: const Text('Add'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _ImagePickerButton(
                            key: const Key('vendor-logo-picker'),
                            label: 'Vendor logo',
                            bytes: vendorLogo,
                            fallbackIcon: Icons.storefront_outlined,
                            onChanged: (bytes) =>
                                setState(() => vendorLogo = bytes),
                          ),
                          SwitchListTile(
                            key: const Key('vendor-is-brand'),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('This vendor is also a brand'),
                            subtitle: const Text(
                              'Use one identity when the maker also sells directly',
                            ),
                            value: vendorAlsoBrand,
                            onChanged: (value) => setState(() {
                              vendorAlsoBrand = value;
                              if (!value) vendorBrandCategories.clear();
                            }),
                          ),
                          if (vendorAlsoBrand)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: InventoryType.values
                                  .where((type) => type != InventoryType.custom)
                                  .map(
                                    (category) => FilterChip(
                                      key: Key(
                                        'vendor-brand-category-${category.name}',
                                      ),
                                      label: Text(_typeLabel(category)),
                                      selected: vendorBrandCategories.contains(
                                        category,
                                      ),
                                      onSelected: (selected) => setState(() {
                                        selected
                                            ? vendorBrandCategories.add(
                                                category,
                                              )
                                            : vendorBrandCategories.remove(
                                                category,
                                              );
                                      }),
                                    ),
                                  )
                                  .toList(),
                            ),
                          const SizedBox(height: 16),
                        ],
                      ),
                      ExpansionTile(
                        key: const Key('catalog-brands-section'),
                        leading: const Icon(Icons.sell_outlined),
                        title: Text('Brands (${brands.length})'),
                        subtitle: const Text(
                          'Link a maker to vendors and categories',
                        ),
                        children: [
                          TextField(
                            key: const Key('new-brand-name'),
                            controller: brandName,
                            decoration: const InputDecoration(
                              labelText: 'Brand name',
                            ),
                          ),
                          const SizedBox(height: 10),
                          _ImagePickerButton(
                            key: const Key('brand-logo-picker'),
                            label: 'Brand logo',
                            bytes: brandLogo,
                            fallbackIcon: Icons.sell_outlined,
                            onChanged: (bytes) =>
                                setState(() => brandLogo = bytes),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            key: const Key('brand-vendor'),
                            initialValue: brandVendorId,
                            decoration: const InputDecoration(
                              labelText: 'Vendor',
                            ),
                            items: vendors
                                .map(
                                  (vendor) => DropdownMenuItem(
                                    value: vendor.id,
                                    child: Text(vendor.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => brandVendorId = value),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: InventoryType.values
                                .where((type) => type != InventoryType.custom)
                                .map(
                                  (category) => FilterChip(
                                    key: Key('brand-category-${category.name}'),
                                    label: Text(_typeLabel(category)),
                                    selected: brandCategories.contains(
                                      category,
                                    ),
                                    onSelected: (selected) => setState(() {
                                      selected
                                          ? brandCategories.add(category)
                                          : brandCategories.remove(category);
                                    }),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              key: const Key('add-brand'),
                              onPressed: _addBrand,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add brand'),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                      ExpansionTile(
                        key: const Key('catalog-spool-types-section'),
                        leading: const Icon(Icons.donut_large_rounded),
                        title: Text('Spool sizes (${spoolTypes.length})'),
                        subtitle: const Text(
                          'Reusable filament package weights',
                        ),
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: spoolTypes
                                .map(
                                  (spool) => Chip(
                                    avatar: const Icon(
                                      Icons.scale_outlined,
                                      size: 18,
                                    ),
                                    label: Text(spool.label),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const Key('new-spool-label'),
                                  controller: spoolLabel,
                                  decoration: const InputDecoration(
                                    labelText: 'Button label',
                                    hintText: '2.5 kg',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 200,
                                child: TextField(
                                  key: const Key('new-spool-weight'),
                                  controller: spoolWeightGrams,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Filament weight',
                                    suffixText: 'g',
                                  ),
                                ),
                              ),
                              FilledButton(
                                key: const Key('add-spool-type'),
                                onPressed: _addSpoolType,
                                child: const Text('Add'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                      ExpansionTile(
                        key: const Key('catalog-machines-section'),
                        leading: const Icon(
                          Icons.precision_manufacturing_outlined,
                        ),
                        title: Text('Machines (${machines.length})'),
                        subtitle: const Text(
                          'Equipment and compatible machine types',
                        ),
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: machines.map((machine) {
                              final type = machineTypes
                                  .where((value) => value.id == machine.typeId)
                                  .firstOrNull;
                              final kitNames = kits
                                  .where(
                                    (kit) => machine.kitIds.contains(kit.id),
                                  )
                                  .map((kit) => kit.name)
                                  .join(', ');
                              return Chip(
                                avatar: const Icon(
                                  Icons.memory_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  '${machine.name} · ${type?.name ?? 'Unknown type'}${kitNames.isEmpty ? '' : ' · $kitNames'}',
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('new-machine-type-name'),
                            controller: machineTypeName,
                            decoration: const InputDecoration(
                              labelText: 'New machine type',
                              hintText: 'Printer, FDM, Heat Insert Press…',
                            ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String?>(
                            key: const Key('machine-type-parent'),
                            initialValue: machineTypeParentId,
                            decoration: const InputDecoration(
                              labelText: 'Parent type (optional)',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('No parent'),
                              ),
                              ...machineTypes.map(
                                (type) => DropdownMenuItem<String?>(
                                  value: type.id,
                                  child: Text(type.name),
                                ),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => machineTypeParentId = value),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              key: const Key('add-machine-type'),
                              onPressed: _addMachineType,
                              child: const Text('Add type'),
                            ),
                          ),
                          const Divider(),
                          DropdownButtonFormField<String>(
                            key: const Key('machine-type'),
                            initialValue: selectedMachineTypeId,
                            decoration: const InputDecoration(
                              labelText: 'Machine type',
                            ),
                            items: machineTypes
                                .map(
                                  (type) => DropdownMenuItem(
                                    value: type.id,
                                    child: Text(type.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => selectedMachineTypeId = value),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            key: const Key('new-machine-name'),
                            controller: machineName,
                            decoration: const InputDecoration(
                              labelText: 'Name',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: machineModel,
                            decoration: const InputDecoration(
                              labelText: 'Model',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: machineAddress,
                            decoration: const InputDecoration(
                              labelText: 'Hostname / IP',
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Associated kits',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (kits.isEmpty)
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Define a kit below before associating it.',
                                style: TextStyle(color: Color(0xff929aac)),
                              ),
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: kits
                                  .map(
                                    (kit) => FilterChip(
                                      key: Key('machine-kit-${kit.id}'),
                                      label: Text(kit.name),
                                      selected: selectedMachineKitIds.contains(
                                        kit.id,
                                      ),
                                      onSelected: (selected) => setState(() {
                                        selected
                                            ? selectedMachineKitIds.add(kit.id)
                                            : selectedMachineKitIds.remove(
                                                kit.id,
                                              );
                                      }),
                                    ),
                                  )
                                  .toList(),
                            ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              key: const Key('add-machine'),
                              onPressed: _addMachine,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add machine'),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                      ExpansionTile(
                        key: const Key('catalog-products-section'),
                        leading: const Icon(Icons.category_outlined),
                        title: Text('Products and types (${products.length})'),
                        subtitle: const Text(
                          'Reusable defaults such as PLA or Tough Resin',
                        ),
                        children: [
                          DropdownButtonFormField<String>(
                            key: const Key('product-brand'),
                            initialValue: productBrandId,
                            decoration: const InputDecoration(
                              labelText: 'Brand',
                            ),
                            items: brands
                                .map(
                                  (brand) => DropdownMenuItem(
                                    value: brand.id,
                                    child: Text(brand.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => setState(() {
                              productBrandId = value;
                              productCategory = null;
                            }),
                          ),
                          if (_productBrand != null) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              children: _productBrand!.categories
                                  .map(
                                    (category) => ChoiceChip(
                                      key: Key(
                                        'product-category-${category.name}',
                                      ),
                                      label: Text(_typeLabel(category)),
                                      selected: productCategory == category,
                                      onSelected: (_) => setState(
                                        () => productCategory = category,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('new-product-name'),
                            controller: productName,
                            decoration: const InputDecoration(
                              labelText: 'Product / type name',
                              hintText: 'PolyLite PLA Pro',
                            ),
                          ),
                          const SizedBox(height: 10),
                          _ImagePickerButton(
                            key: const Key('product-image-picker'),
                            label: 'Product icon / image',
                            bytes: productImage,
                            fallbackIcon: Icons.inventory_2_outlined,
                            onChanged: (bytes) =>
                                setState(() => productImage = bytes),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: productCost,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Default cost',
                                    prefixText: r'$ ',
                                  ),
                                ),
                              ),
                              if (productCategory?.supportsDrying == true) ...[
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: productDrying,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Drying duration',
                                      suffixText: 'min',
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (productCategory?.supportsPrinting == true) ...[
                            const SizedBox(height: 10),
                            TextField(
                              controller: printing,
                              decoration: const InputDecoration(
                                labelText: 'Printing instructions',
                              ),
                            ),
                          ],
                          if (productCategory?.supportsDrying == true) ...[
                            const SizedBox(height: 10),
                            TextField(
                              controller: drying,
                              decoration: const InputDecoration(
                                labelText: 'Drying instructions',
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          TextField(
                            controller: storage,
                            decoration: const InputDecoration(
                              labelText: 'Storage instructions',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              key: const Key('add-product'),
                              onPressed: _addProduct,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add product type'),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                      ExpansionTile(
                        key: const Key('catalog-kits-section'),
                        onExpansionChanged: (expanded) =>
                            setState(() => kitSectionExpanded = expanded),
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text('Kits (${kits.length})'),
                        subtitle: const Text('Reusable bills of materials'),
                        children: _kitEditorWidgets(includeKitList: true),
                      ),
                    ],
                  ),
          ),
          if (kitSectionExpanded && !loadingInitialKit)
            Container(
              key: const Key('kit-editor-footer'),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      editingKitId == null
                          ? 'New kit · ${draftSections.length} sections · ${draftBom.length} BOM items'
                          : 'Editing kit · ${draftSections.length} sections · ${draftBom.length} BOM items',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (editingKitId != null) ...[
                    TextButton(
                      key: const Key('cancel-kit-edit'),
                      onPressed: _clearKitEditor,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton.icon(
                    key: const Key('save-kit'),
                    onPressed: _saveKit,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      editingKitId == null ? 'Save kit' : 'Update kit',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _kitOnlyBomList() => ListView(
    key: const Key('kit-bom-list'),
    padding: const EdgeInsets.all(18),
    children: [
      TextField(
        key: const Key('new-kit-name'),
        controller: kitName,
        decoration: const InputDecoration(labelText: 'Kit name'),
      ),
      const SizedBox(height: 18),
      _kitSectionsEditor(),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const Key('add-kit-section'),
          onPressed: _addKitSection,
          icon: const Icon(Icons.dashboard_customize_outlined),
          label: const Text('Add component section'),
        ),
      ),
      const SizedBox(height: 18),
    ],
  );

  Widget _kitSectionsEditor() {
    if (draftSections.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: Text(
          'No component sections yet. Add one, then fill it with BOM items.',
          style: TextStyle(color: Color(0xff929aac)),
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < draftSections.length; index++)
          _kitSectionCard(index),
      ],
    );
  }

  Widget _kitSectionCard(int sectionIndex) {
    final section = draftSections[sectionIndex];
    final lines = draftBom
        .where((line) => line.section == section)
        .toList(growable: false);
    return Padding(
      key: ValueKey('kit-section-$section'),
      padding: const EdgeInsets.only(bottom: 18),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: section,
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.account_tree_outlined,
                  color: Color(0xffa987ff),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${lines.length} ${lines.length == 1 ? 'item' : 'items'}',
                    style: const TextStyle(
                      color: Color(0xff929aac),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  key: Key('rename-kit-section-$sectionIndex'),
                  tooltip: 'Rename section',
                  onPressed: () => _renameKitSection(sectionIndex),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  key: Key('delete-kit-section-$sectionIndex'),
                  tooltip: lines.isEmpty
                      ? 'Delete section'
                      : 'Remove its items before deleting this section',
                  onPressed: lines.isEmpty
                      ? () =>
                            setState(() => draftSections.removeAt(sectionIndex))
                      : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            if (lines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'This section is empty.',
                  style: TextStyle(color: Color(0xff687185)),
                ),
              )
            else
              ReorderableListView.builder(
                key: Key('kit-section-list-$sectionIndex'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: lines.length,
                onReorderItem: (oldIndex, newIndex) =>
                    _reorderSectionBom(section, oldIndex, newIndex),
                itemBuilder: (context, localIndex) {
                  final line = lines[localIndex];
                  final globalIndex = draftBom.indexWhere(
                    (candidate) => candidate.id == line.id,
                  );
                  return _kitBomRow(globalIndex, localIndex);
                },
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: sectionIndex == 0
                    ? const Key('add-kit-bom-line')
                    : Key('add-kit-bom-line-$sectionIndex'),
                onPressed: () => _chooseKitProduct(section: section),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add item to this section'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kitBomRow(int index, int localIndex) {
    final line = draftBom[index];
    final duplicate =
        draftBom
            .where((candidate) => candidate.productId == line.productId)
            .length >
        1;
    final rowKey = duplicate ? line.id : line.productId;
    return Padding(
      key: ValueKey('kit-bom-row-$rowKey'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: localIndex,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.drag_indicator_rounded),
            ),
          ),
          Expanded(
            child: TextFormField(
              key: Key('kit-bom-name-$rowKey'),
              initialValue: _bomEntryName(line),
              decoration: const InputDecoration(labelText: 'Item name'),
              onChanged: (value) => _renameDraftBomLine(index, value),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: TextFormField(
              key: Key('kit-bom-quantity-$rowKey'),
              initialValue: _formatBomQuantity(line.quantity),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Qty'),
              onChanged: (value) => _setDraftBomQuantity(index, value),
            ),
          ),
          if (draftSections.length > 1)
            PopupMenuButton<String>(
              key: Key('move-kit-bom-$rowKey'),
              tooltip: 'Move to another section',
              icon: const Icon(Icons.drive_file_move_outline),
              itemBuilder: (_) => draftSections
                  .where((candidate) => candidate != line.section)
                  .map(
                    (candidate) =>
                        PopupMenuItem(value: candidate, child: Text(candidate)),
                  )
                  .toList(),
              onSelected: (section) => _moveDraftBomLine(index, section),
            ),
          IconButton(
            key: Key('delete-kit-bom-$rowKey'),
            tooltip: 'Remove from kit',
            onPressed: () => setState(() => draftBom.removeAt(index)),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }

  List<Widget> _kitEditorWidgets({required bool includeKitList}) => [
    if (includeKitList) ...[
      ...kits.map(
        (kit) => ListTile(
          key: Key('kit-summary-${kit.id}'),
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text(kit.name),
          subtitle: Text('${kit.bom.length} BOM lines'),
          trailing: IconButton(
            key: Key('edit-kit-${kit.id}'),
            tooltip: 'Edit kit',
            onPressed: () => _startEditingKit(kit),
            icon: const Icon(Icons.edit_outlined),
          ),
        ),
      ),
      const Divider(height: 24),
    ],
    TextField(
      key: const Key('new-kit-name'),
      controller: kitName,
      decoration: InputDecoration(
        labelText: editingKitId == null ? 'Kit name' : 'Editing kit name',
      ),
    ),
    const SizedBox(height: 12),
    _kitSectionsEditor(),
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const Key('add-kit-section'),
        onPressed: _addKitSection,
        icon: const Icon(Icons.dashboard_customize_outlined),
        label: const Text('Add component section'),
      ),
    ),
    const SizedBox(height: 16),
  ];

  BrandRecord? get _productBrand =>
      brands.where((brand) => brand.id == productBrandId).firstOrNull;

  void _addVendor() {
    final name = vendorName.text.trim();
    if (name.isEmpty) return;
    if (vendorAlsoBrand && vendorBrandCategories.isEmpty) return;
    final vendor = VendorRecord(
      id: _newCatalogId('VEN'),
      name: name,
      isBrand: vendorAlsoBrand,
      logoBytes: vendorLogo,
    );
    final linkedBrand = vendorAlsoBrand
        ? BrandRecord(
            id: _newCatalogId('BR'),
            name: name,
            vendorIds: {vendor.id},
            categories: {...vendorBrandCategories},
            logoBytes: vendorLogo,
          )
        : null;
    setState(() {
      vendors.add(vendor);
      if (linkedBrand != null) brands.add(linkedBrand);
      vendorName.clear();
      vendorLogo = null;
      vendorAlsoBrand = false;
      vendorBrandCategories.clear();
    });
    widget.onVendorAdded(vendor);
    if (linkedBrand != null) widget.onBrandAdded(linkedBrand);
  }

  void _addBrand() {
    final name = brandName.text.trim();
    if (name.isEmpty || brandVendorId == null || brandCategories.isEmpty) {
      return;
    }
    final brand = BrandRecord(
      id: _newCatalogId('BR'),
      name: name,
      vendorIds: {brandVendorId!},
      categories: {...brandCategories},
      logoBytes: brandLogo,
    );
    setState(() {
      brands.add(brand);
      brandName.clear();
      brandLogo = null;
      brandCategories.clear();
    });
    widget.onBrandAdded(brand);
  }

  void _addSpoolType() {
    final label = spoolLabel.text.trim();
    final grams = int.tryParse(spoolWeightGrams.text.trim());
    if (label.isEmpty || grams == null || grams <= 0) return;
    final spool = SpoolTypeRecord(
      id: _newCatalogId('SPOOL'),
      label: label,
      weightGrams: grams,
    );
    setState(() {
      spoolTypes.add(spool);
      spoolTypes.sort((a, b) => a.weightGrams.compareTo(b.weightGrams));
      spoolLabel.clear();
      spoolWeightGrams.clear();
    });
    widget.onSpoolTypeAdded(spool);
  }

  void _addCustomItemType() {
    final name = customTypeName.text.trim();
    if (name.isEmpty ||
        customItemTypes.any(
          (type) => type.name.toLowerCase() == name.toLowerCase(),
        )) {
      return;
    }
    final fields = customTypeFields.text
        .split(RegExp(r'[,\n]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    final customType = CustomItemTypeRecord(
      id: _newCatalogId('TYPE'),
      name: name,
      contextualFields: fields,
    );
    setState(() {
      customItemTypes.add(customType);
      customItemTypes.sort((a, b) => a.name.compareTo(b.name));
      customTypeName.clear();
      customTypeFields.clear();
    });
    widget.onCustomItemTypeAdded(customType);
  }

  void _addProduct() {
    final name = productName.text.trim();
    if (name.isEmpty || productBrandId == null || productCategory == null) {
      return;
    }
    final product = CatalogProduct(
      id: _newCatalogId('PROD'),
      brandId: productBrandId!,
      category: productCategory!,
      name: name,
      defaultCost: double.tryParse(productCost.text) ?? 0,
      dryingMinutes: productCategory!.supportsDrying
          ? int.tryParse(productDrying.text)
          : null,
      printingInstructions: productCategory!.supportsPrinting
          ? printing.text.trim()
          : '',
      dryingInstructions: productCategory!.supportsDrying
          ? drying.text.trim()
          : '',
      storageInstructions: storage.text.trim(),
      imageBytes: productImage,
    );
    setState(() {
      products.add(product);
      productName.clear();
      productCost.clear();
      productDrying.clear();
      printing.clear();
      drying.clear();
      storage.clear();
      productImage = null;
    });
    widget.onProductAdded(product);
  }

  void _addMachineType() {
    final name = machineTypeName.text.trim();
    if (name.isEmpty) return;
    final type = MachineTypeRecord(
      id: _newCatalogId('MT'),
      name: name,
      parentId: machineTypeParentId,
    );
    setState(() {
      machineTypes.add(type);
      machineTypeName.clear();
      machineTypeParentId = null;
      selectedMachineTypeId ??= type.id;
    });
    widget.onMachineTypeAdded(type);
  }

  void _addMachine() {
    final name = machineName.text.trim();
    if (name.isEmpty || selectedMachineTypeId == null) return;
    final machine = MachineRecord(
      id: _newCatalogId('MCH'),
      name: name,
      model: machineModel.text.trim(),
      address: machineAddress.text.trim(),
      typeId: selectedMachineTypeId!,
      kitIds: {...selectedMachineKitIds},
    );
    setState(() {
      machines.add(machine);
      machineName.clear();
      machineModel.clear();
      machineAddress.clear();
      selectedMachineKitIds.clear();
    });
    widget.onMachineAdded(machine);
  }

  String _bomEntryName(KitBomEntry line) =>
      line.name ??
      products
          .where((product) => product.id == line.productId)
          .firstOrNull
          ?.name ??
      kits.where((kit) => kit.id == line.productId).firstOrNull?.name ??
      'Missing item';

  bool _kitContainsKit(String kitId, String targetId, [Set<String>? visited]) {
    final checked = visited ?? <String>{};
    if (!checked.add(kitId)) return false;
    final kit = kits.where((candidate) => candidate.id == kitId).firstOrNull;
    if (kit == null) return false;
    return kit.bom.any(
      (line) =>
          line.productId == targetId ||
          _kitContainsKit(line.productId, targetId, checked),
    );
  }

  Future<void> _chooseKitProduct({String? section}) async {
    const createProduct = '__create_product__';
    var query = '';
    final productId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final matches = products
              .where(
                (product) =>
                    product.name.toLowerCase().contains(query.toLowerCase()),
              )
              .toList();
          final kitMatches = kits
              .where(
                (kit) =>
                    kit.id != editingKitId &&
                    (editingKitId == null ||
                        !_kitContainsKit(kit.id, editingKitId!)) &&
                    kit.name.toLowerCase().contains(query.toLowerCase()),
              )
              .toList();
          return AlertDialog(
            title: const Text('Add BOM item'),
            content: SizedBox(
              width: 520,
              height: 480,
              child: Column(
                children: [
                  TextField(
                    key: const Key('kit-product-search'),
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      labelText: 'Search products or kits',
                    ),
                    onChanged: (value) => setDialogState(() => query = value),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    key: const Key('create-kit-product'),
                    leading: const Icon(Icons.add_circle_outline_rounded),
                    title: const Text('Create new catalog item…'),
                    onTap: () => Navigator.of(dialogContext).pop(createProduct),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: kitMatches.length + matches.length,
                      itemBuilder: (context, index) {
                        if (index < kitMatches.length) {
                          final kit = kitMatches[index];
                          return ListTile(
                            leading: const Icon(Icons.account_tree_outlined),
                            title: Text(kit.name),
                            subtitle: Text('Kit · ${kit.bom.length} BOM items'),
                            onTap: () =>
                                Navigator.of(dialogContext).pop(kit.id),
                          );
                        }
                        final product = matches[index - kitMatches.length];
                        return ListTile(
                          title: Text(product.name),
                          subtitle: Text(_typeLabel(product.category)),
                          onTap: () =>
                              Navigator.of(dialogContext).pop(product.id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (productId == null || !mounted) return;

    String? selectedId;
    if (productId == createProduct) {
      final product = await showDialog<CatalogProduct>(
        context: context,
        builder: (_) => const QuickCatalogProductDialog(),
      );
      if (product == null || !mounted) return;
      setState(() => products.add(product));
      widget.onProductAdded(product);
      selectedId = product.id;
    } else {
      final exists =
          products.any((product) => product.id == productId) ||
          kits.any((kit) => kit.id == productId);
      if (exists) selectedId = productId;
    }
    if (selectedId == null || !mounted) return;

    final targetSection = section ?? draftSections.firstOrNull ?? 'Unassigned';
    setState(() {
      if (!draftSections.contains(targetSection)) {
        draftSections.add(targetSection);
      }
      draftBom.add(
        KitBomEntry(
          id: 'BOM-${DateTime.now().microsecondsSinceEpoch}',
          productId: selectedId!,
          quantity: 1,
          section: targetSection,
        ),
      );
    });
  }

  void _renameDraftBomLine(int index, String value) {
    if (index >= draftBom.length) return;
    final line = draftBom[index];
    draftBom[index] = KitBomEntry(
      id: line.id,
      productId: line.productId,
      quantity: line.quantity,
      name: value,
      section: line.section,
    );
  }

  void _setDraftBomQuantity(int index, String value) {
    final quantity = double.tryParse(value);
    if (index >= draftBom.length || quantity == null || quantity <= 0) return;
    final line = draftBom[index];
    draftBom[index] = KitBomEntry(
      id: line.id,
      productId: line.productId,
      quantity: quantity,
      name: line.name,
      section: line.section,
    );
  }

  void _moveDraftBomLine(int index, String section) {
    if (index >= draftBom.length) return;
    final line = draftBom[index];
    setState(() {
      draftBom[index] = KitBomEntry(
        id: line.id,
        productId: line.productId,
        quantity: line.quantity,
        name: line.name,
        section: section,
      );
    });
  }

  void _reorderSectionBom(String section, int oldIndex, int newIndex) {
    setState(() {
      final lines = draftBom.where((line) => line.section == section).toList();
      if (newIndex > oldIndex) newIndex--;
      final line = lines.removeAt(oldIndex);
      lines.insert(newIndex, line);
      var cursor = 0;
      for (var index = 0; index < draftBom.length; index++) {
        if (draftBom[index].section == section) {
          draftBom[index] = lines[cursor++];
        }
      }
    });
  }

  List<String> _sectionsForKit(KitRecord kit) {
    final result = <String>[];
    for (final section in [
      ...kit.sections,
      ...kit.bom.map((line) => line.section),
    ]) {
      final cleaned = section.trim().isEmpty ? 'Unassigned' : section.trim();
      if (!result.contains(cleaned)) result.add(cleaned);
    }
    return result;
  }

  Future<String?> _promptKitSectionName({
    required String title,
    String initialValue = '',
  }) async {
    var value = initialValue;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          key: const Key('kit-section-name'),
          initialValue: initialValue,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Section name',
            hintText: 'Extruder, Heatbed, Electronics…',
          ),
          onChanged: (next) => value = next,
          onFieldSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, value),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result?.trim();
  }

  Future<void> _addKitSection() async {
    final name = await _promptKitSectionName(title: 'Add component section');
    if (!mounted || name == null || name.isEmpty) return;
    if (draftSections.any(
      (section) => section.toLowerCase() == name.toLowerCase(),
    )) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('That section exists.')));
      return;
    }
    setState(() => draftSections.add(name));
  }

  Future<void> _renameKitSection(int sectionIndex) async {
    if (sectionIndex >= draftSections.length) return;
    final previous = draftSections[sectionIndex];
    final name = await _promptKitSectionName(
      title: 'Rename component section',
      initialValue: previous,
    );
    if (!mounted || name == null || name.isEmpty || name == previous) return;
    if (draftSections.any(
      (section) =>
          section != previous && section.toLowerCase() == name.toLowerCase(),
    )) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('That section exists.')));
      return;
    }
    setState(() {
      draftSections[sectionIndex] = name;
      for (var index = 0; index < draftBom.length; index++) {
        final line = draftBom[index];
        if (line.section != previous) continue;
        draftBom[index] = KitBomEntry(
          id: line.id,
          productId: line.productId,
          quantity: line.quantity,
          name: line.name,
          section: name,
        );
      }
    });
  }

  void _startEditingKit(KitRecord kit) {
    setState(() {
      editingKitId = kit.id;
      kitName.text = kit.name;
      draftBom
        ..clear()
        ..addAll(kit.bom);
      draftSections
        ..clear()
        ..addAll(_sectionsForKit(kit));
    });
  }

  void _clearKitEditor() {
    setState(() {
      editingKitId = null;
      kitName.clear();
      draftBom.clear();
      draftSections.clear();
    });
  }

  void _saveKit() {
    final name = kitName.text.trim();
    if (name.isEmpty) return;
    final editedKitId = editingKitId;
    final kit = KitRecord(
      id: editedKitId ?? _newCatalogId('KIT'),
      name: name,
      bom: List.unmodifiable(draftBom),
      sections: List.unmodifiable(draftSections),
    );
    setState(() {
      if (editedKitId == null) {
        kits.add(kit);
      } else {
        final index = kits.indexWhere(
          (candidate) => candidate.id == editedKitId,
        );
        if (index >= 0) kits[index] = kit;
      }
      editingKitId = null;
      kitName.clear();
      draftBom.clear();
      draftSections.clear();
    });
    if (editedKitId == null) {
      widget.onKitAdded(kit);
    } else {
      widget.onKitUpdated(kit);
    }
    if (kitOnly && mounted) Navigator.of(context).pop();
  }
}

class _KitBomLoadingState extends StatelessWidget {
  const _KitBomLoadingState();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 86,
          height: 86,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xffa987ff).withValues(alpha: .1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x553f24a8),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                color: Color(0xffa987ff),
                strokeWidth: 4,
              ),
              Icon(
                Icons.inventory_2_outlined,
                color: Color(0xffd2c3ff),
                size: 25,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Assembling BOM…',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        const Text(
          'Loading kit items',
          style: TextStyle(color: Color(0xff929aac)),
        ),
      ],
    ),
  );
}

class QuickCatalogProductDialog extends StatefulWidget {
  const QuickCatalogProductDialog({super.key});

  @override
  State<QuickCatalogProductDialog> createState() =>
      _QuickCatalogProductDialogState();
}

class _QuickCatalogProductDialogState extends State<QuickCatalogProductDialog> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final cost = TextEditingController(text: '0.00');
  InventoryType type = InventoryType.other;

  @override
  void dispose() {
    name.dispose();
    cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add BOM item'),
    content: Form(
      key: formKey,
      child: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('quick-product-name'),
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter an item name'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<InventoryType>(
              key: const Key('quick-product-type'),
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: InventoryType.values
                  .where((type) => type != InventoryType.custom)
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_typeLabel(value)),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => type = value!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('quick-product-cost'),
              controller: cost,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Default price'),
              validator: (value) {
                final parsed = double.tryParse(value ?? '');
                return parsed == null || parsed < 0
                    ? 'Enter a valid price'
                    : null;
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        key: const Key('create-quick-product'),
        onPressed: _save,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create item'),
      ),
    ],
  );

  void _save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      CatalogProduct(
        id: _newCatalogId('PROD'),
        brandId: '',
        category: type,
        name: name.text.trim(),
        defaultCost: double.parse(cost.text),
      ),
    );
  }
}

class RapidizerDialog extends StatefulWidget {
  const RapidizerDialog({super.key});

  @override
  State<RapidizerDialog> createState() => _RapidizerDialogState();
}

class _RapidizerDialogState extends State<RapidizerDialog> {
  final input = TextEditingController();
  List<String> errors = const [];

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt_rounded, color: Color(0xffb8a6ff)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RAPIDIZER',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      Text(
                        'One text field. Spaces separate fields; line breaks create items.',
                        style: TextStyle(color: Color(0xff929aac)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                key: const Key('rapidizer-input'),
                controller: input,
                autofocus: true,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontFamily: 'monospace', height: 1.55),
                decoration: const InputDecoration(
                  alignLabelWithHint: true,
                  labelText: 'Name  Type  Quantity  Price',
                  hintText: 'Blue PLA Filament 2 19.99\nM3x10 socket screw Fastener 25 0.08\nE3D V6 heat break HeatBreak 1 14.95',
                  helperText: 'Names may contain spaces. Type is detected immediately before quantity and price.',
                ),
                onChanged: (_) {
                  if (errors.isNotEmpty) setState(() => errors = const []);
                },
              ),
            ),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...errors
                  .take(4)
                  .map(
                    (error) => Text(
                      error,
                      style: const TextStyle(color: Color(0xffff6b7a)),
                    ),
                  ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'FORMAT: Name Type Quantity Price',
                    style: TextStyle(
                      color: Color(0xff929aac),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('rapidize-items'),
                  onPressed: _rapidize,
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('RAPIDIZE!'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  void _rapidize() {
    final result = parseRapidizerText(input.text);
    if (!result.isValid) {
      setState(
        () => errors = result.errors.isEmpty
            ? const ['Enter at least one item.']
            : result.errors,
      );
      return;
    }
    Navigator.pop(context, result.items);
  }
}

class AnimationControlsDialog extends StatefulWidget {
  const AnimationControlsDialog({
    super.key,
    required this.animationDurationPercent,
    required this.animationRecurrenceSeconds,
    required this.onSettingsChanged,
  });
  final int animationDurationPercent;
  final int animationRecurrenceSeconds;
  final void Function(int durationPercent, int recurrenceSeconds)
  onSettingsChanged;

  @override
  State<AnimationControlsDialog> createState() =>
      _AnimationControlsDialogState();
}

class _AnimationControlsDialogState extends State<AnimationControlsDialog> {
  late int durationPercent = widget.animationDurationPercent;
  late int recurrenceSeconds = widget.animationRecurrenceSeconds;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.animation_rounded),
        SizedBox(width: 10),
        Text('Animation controls'),
      ],
    ),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Animation duration · $durationPercent%'),
          Slider(
            key: const Key('animation-duration'),
            value: durationPercent.toDouble(),
            min: 25,
            max: 200,
            divisions: 7,
            label: '$durationPercent%',
            onChanged: (value) {
              setState(() => durationPercent = value.round());
              widget.onSettingsChanged(durationPercent, recurrenceSeconds);
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: const Key('animation-recurrence'),
            initialValue: recurrenceSeconds,
            decoration: const InputDecoration(
              labelText: 'Repeat alerts while visible',
            ),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Never')),
              DropdownMenuItem(value: 3, child: Text('Every 3 seconds')),
              DropdownMenuItem(value: 5, child: Text('Every 5 seconds')),
              DropdownMenuItem(value: 10, child: Text('Every 10 seconds')),
              DropdownMenuItem(value: 30, child: Text('Every 30 seconds')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => recurrenceSeconds = value);
              widget.onSettingsChanged(durationPercent, recurrenceSeconds);
            },
          ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}

class DebugPanelDialog extends StatefulWidget {
  const DebugPanelDialog({super.key, required this.items});
  final List<InventoryItem> items;

  @override
  State<DebugPanelDialog> createState() => _DebugPanelDialogState();
}

class _DebugPanelDialogState extends State<DebugPanelDialog> {
  String? selectedItemId;

  @override
  void initState() {
    super.initState();
    selectedItemId = widget.items.firstOrNull?.id;
  }

  InventoryItem? get selectedItem =>
      widget.items.where((item) => item.id == selectedItemId).firstOrNull;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.bug_report_outlined),
        SizedBox(width: 10),
        Text('Debug effects'),
      ],
    ),
    content: SizedBox(
      width: 520,
      child: widget.items.isEmpty
          ? const Text('No items are visible under the current filters.')
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('debug-item'),
                  initialValue: selectedItemId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Target item'),
                  items: widget.items
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            item.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => selectedItemId = value),
                ),
                const SizedBox(height: 14),
                const Text(
                  'The panel closes before playing the effect.',
                  style: TextStyle(color: Color(0xff929aac)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('debug-quantity-sync'),
                  onPressed: () => _play(DebugCardEffect.remoteQuantity),
                  icon: const Icon(Icons.south_east_rounded),
                  label: const Text('Supabase quantity arrow'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('debug-low-stock'),
                  onPressed: () => _play(DebugCardEffect.lowStock),
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('Low-stock warning pulse'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('debug-moisture-wave'),
                  onPressed: selectedItem?.type == InventoryType.filament
                      ? () => _play(DebugCardEffect.moistureThreshold)
                      : null,
                  icon: const Icon(Icons.water_drop_rounded),
                  label: const Text('Moisture droplet wave'),
                ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );

  void _play(DebugCardEffect effect) {
    final itemId = selectedItemId;
    if (itemId == null) return;
    Navigator.pop(context, (itemId: itemId, effect: effect));
  }
}

String _formatBomQuantity(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

String _newCatalogId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';

class _ImagePickerButton extends StatelessWidget {
  const _ImagePickerButton({
    super.key,
    required this.label,
    required this.bytes,
    required this.fallbackIcon,
    required this.onChanged,
  });
  final String label;
  final Uint8List? bytes;
  final IconData fallbackIcon;
  final ValueChanged<Uint8List?> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox.square(
          dimension: 44,
          child: bytes == null
              ? ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(fallbackIcon),
                )
              : Image.memory(bytes!, fit: BoxFit.cover),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () async {
            final picked = await _pickImageBytes();
            if (picked != null) onChanged(picked);
          },
          icon: const Icon(Icons.image_outlined),
          label: Text(
            bytes == null ? 'Choose $label' : 'Replace $label',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      if (bytes != null)
        IconButton(
          tooltip: 'Remove image',
          onPressed: () => onChanged(null),
          icon: const Icon(Icons.close_rounded),
        ),
    ],
  );
}

class _LogoAvatar extends StatelessWidget {
  const _LogoAvatar({required this.bytes, required this.fallbackIcon});
  final Uint8List? bytes;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox.square(
      dimension: 22,
      child: bytes == null
          ? Icon(fallbackIcon, size: 18)
          : Image.memory(bytes!, fit: BoxFit.cover),
    ),
  );
}

Future<Uint8List?> _pickImageBytes() async {
  final result = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
  );
  return result?.readAsBytes();
}

Map<String, dynamic>? _findProductJson(Object? value) {
  if (value is List) {
    for (final entry in value) {
      final product = _findProductJson(entry);
      if (product != null) return product;
    }
  }
  if (value is Map) {
    final map = value.map((key, item) => MapEntry(key.toString(), item));
    final type = map['@type'];
    if (type == 'Product' || (type is List && type.contains('Product'))) {
      return map;
    }
    for (final entry in map.values) {
      final product = _findProductJson(entry);
      if (product != null) return product;
    }
  }
  return null;
}

Map<String, dynamic>? extractFallbackProductMetadata(String html, Uri uri) {
  final document = html_parser.parse(html);
  final bodyText = document.body?.text.toLowerCase() ?? '';
  if (bodyText.contains('enter the characters you see below') ||
      bodyText.contains('sorry, we just need to make sure you')) {
    return null;
  }

  String? attribute(String selector, String name) =>
      document.querySelector(selector)?.attributes[name]?.trim();
  String? text(String selector) {
    final value = document
        .querySelector(selector)
        ?.text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return value?.isEmpty == true ? null : value;
  }

  var name =
      text('#title') ??
      text('#productTitle') ??
      attribute('meta[property="og:title"]', 'content') ??
      attribute('meta[name="title"]', 'content') ??
      text('title');
  if (name == null || name.isEmpty) return null;
  if (uri.host.contains('amazon.')) {
    name = name.replaceFirst(RegExp(r'^Amazon\.[^:]+:\s*'), '');
    name = name.replaceFirst(RegExp(r'\s*:\s*[^:]+(?:&|and)\s*[^:]+\s*$'), '');
  }

  var brand =
      text('#bylineInfo') ??
      attribute('meta[property="product:brand"]', 'content');
  brand = brand
      ?.replaceFirst(RegExp(r'^Visit the\s+', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s+Store$', caseSensitive: false), '')
      .trim();

  final priceCandidates = [
    text('#apex-pricetopay-accessibility-label'),
    text('.a-price .a-offscreen'),
    attribute('[data-pricetopay-label]', 'data-pricetopay-label'),
    attribute('meta[property="product:price:amount"]', 'content'),
  ];
  String? price;
  for (final candidate in priceCandidates.whereType<String>()) {
    price = RegExp(r'\d+(?:[.,]\d{2})?')
        .firstMatch(candidate.replaceAll(',', ''))
        ?.group(0);
    if (price != null) break;
  }

  final image =
      attribute('#landingImage', 'data-old-hi') ??
      attribute('#landingImage', 'src') ??
      attribute('#landing-image', 'src') ??
      attribute('#landing-image-wrapper img', 'src') ??
      attribute('meta[property="og:image"]', 'content') ??
      attribute('meta[name="twitter:image"]', 'content');
  final description = [
    attribute('meta[name="description"]', 'content'),
    text('#feature-bullets'),
    text('#productFactsDesktopExpander'),
    text('#productDescription'),
  ].whereType<String>().where((value) => value.isNotEmpty).join('\n');

  return <String, dynamic>{
    '@type': 'Product',
    'name': name,
    if (brand?.isNotEmpty == true) 'brand': {'name': brand},
    if (price != null) 'offers': {'price': price},
    'image': ?image,
    if (description.isNotEmpty) 'description': description,
  };
}

void _collectImageUrls(Object? value, List<String> output) {
  if (value is String && value.trim().isNotEmpty) {
    output.add(value.trim());
    return;
  }
  if (value is List) {
    for (final entry in value) {
      _collectImageUrls(entry, output);
    }
    return;
  }
  if (value is Map) {
    for (final key in const ['url', 'contentUrl', '@id']) {
      _collectImageUrls(value[key], output);
    }
  }
}

typedef ImportedProductInstructions = ({
  String printing,
  String drying,
  String storage,
});

enum FilamentFamily { pla, htpla, petg, pctg, nylon, abs, asa, tpu }

typedef FilamentInstructionTemplate = ({
  FilamentFamily family,
  String label,
  String printing,
  String drying,
  String storage,
});

typedef DryingSettings = ({int? temperatureC, int? durationMinutes});

DryingSettings parseDryingSettings(String text) {
  final temperature = RegExp(
    r'(\d{2,3})\s*°?\s*C\b',
    caseSensitive: false,
  ).firstMatch(text);
  final duration = RegExp(
    r'(\d+(?:\.\d+)?)(?:\s*[-–]\s*(\d+(?:\.\d+)?))?\s*(hours?|hrs?|minutes?|mins?)\b',
    caseSensitive: false,
  ).firstMatch(text);
  final amount = double.tryParse(
    duration?.group(2) ?? duration?.group(1) ?? '',
  );
  final unit = duration?.group(3)?.toLowerCase() ?? '';
  return (
    temperatureC: int.tryParse(temperature?.group(1) ?? ''),
    durationMinutes: amount == null
        ? null
        : (amount * (unit.startsWith('h') ? 60 : 1)).round(),
  );
}

const _filamentTemplates = <FilamentFamily, FilamentInstructionTemplate>{
  FilamentFamily.pla: (
    family: FilamentFamily.pla,
    label: 'PLA',
    printing: 'Generic PLA starting profile: nozzle 185–235°C; bed 50–60°C. A heated enclosure is normally unnecessary. Verify the spool manufacturer’s settings.',
    drying: 'Generic PLA drying profile: 45°C for 6 hours. Do not exceed the spool manufacturer’s limit.',
    storage: 'Store sealed with fresh desiccant in a cool, dry place.',
  ),
  FilamentFamily.htpla: (
    family: FilamentFamily.htpla,
    label: 'HTPLA',
    printing: 'Generic HTPLA starting profile: nozzle 195–225°C; bed 50–60°C. Heat treatment/annealing is a separate process; follow the manufacturer’s procedure.',
    drying: 'Generic HTPLA drying profile: 45°C for 6 hours. Do not confuse drying with annealing.',
    storage: 'Store sealed with fresh desiccant in a cool, dry place.',
  ),
  FilamentFamily.petg: (
    family: FilamentFamily.petg,
    label: 'PETG',
    printing: 'Generic PETG starting profile: nozzle 215–270°C; bed 70–90°C. Use an appropriate release layer on surfaces where PETG may bond too strongly.',
    drying: 'Generic PETG drying profile: 55°C for 6 hours.',
    storage: 'Store sealed with fresh desiccant; use a dry box in humid environments.',
  ),
  FilamentFamily.pctg: (
    family: FilamentFamily.pctg,
    label: 'PCTG',
    printing: 'Generic PCTG starting profile: nozzle 250–270°C; bed 90–110°C. Verify the spool manufacturer’s settings.',
    drying: 'Generic PCTG drying profile: 60°C for 4–6 hours; use the manufacturer’s value when available.',
    storage: 'Store sealed with fresh desiccant; use a dry box in humid environments.',
  ),
  FilamentFamily.nylon: (
    family: FilamentFamily.nylon,
    label: 'Nylon',
    printing: 'Generic Nylon/PA starting profile: nozzle 240–285°C; bed 70–115°C; enclosure recommended. Print from a dry box when possible.',
    drying: 'Generic Nylon/PA drying profile: 70°C for 8–12 hours. PA blends vary widely, so prefer the manufacturer’s value.',
    storage: 'Highly moisture-sensitive: keep sealed with fresh desiccant or continuously in a dry box.',
  ),
  FilamentFamily.abs: (
    family: FilamentFamily.abs,
    label: 'ABS',
    printing: 'Generic ABS starting profile: nozzle 230–255°C; bed 95–110°C; enclosure recommended and part cooling low/off. Provide suitable ventilation.',
    drying: 'Generic ABS drying profile: 65°C for 4–6 hours; use the manufacturer’s value when available.',
    storage: 'Store sealed with desiccant in a cool, dry place.',
  ),
  FilamentFamily.asa: (
    family: FilamentFamily.asa,
    label: 'ASA',
    printing: 'Generic ASA starting profile: nozzle 220–275°C; bed 90–110°C; enclosure recommended. Provide suitable ventilation.',
    drying: 'Generic ASA drying profile: 80°C for 4 hours.',
    storage: 'Store sealed with desiccant in a cool, dry place.',
  ),
  FilamentFamily.tpu: (
    family: FilamentFamily.tpu,
    label: 'TPU',
    printing: 'Generic TPU starting profile: nozzle 220–260°C; bed 40–85°C. Print slowly with a constrained filament path and minimal retraction.',
    drying: 'Generic TPU drying profile: 60°C for 4–6 hours.',
    storage:
        'Moisture-sensitive: keep sealed with fresh desiccant or in a dry box.',
  ),
};

FilamentInstructionTemplate? detectFilamentTemplate(String text) {
  final value = text.toUpperCase();
  bool token(String pattern) =>
      RegExp('(?:^|[^A-Z0-9])$pattern(?:[^A-Z0-9]|\$)').hasMatch(value);
  final family = token('HT[ -]?PLA')
      ? FilamentFamily.htpla
      : token('PCTG')
      ? FilamentFamily.pctg
      : token('PETG')
      ? FilamentFamily.petg
      : token('NYLON') || token('PA(?:6|11|12|66)?')
      ? FilamentFamily.nylon
      : token('ASA')
      ? FilamentFamily.asa
      : token('ABS')
      ? FilamentFamily.abs
      : token('TPU')
      ? FilamentFamily.tpu
      : token('PLA')
      ? FilamentFamily.pla
      : null;
  return family == null ? null : _filamentTemplates[family];
}

ImportedProductInstructions applyFilamentFallbacks(
  ImportedProductInstructions extracted,
  FilamentInstructionTemplate? fallback,
) => fallback == null
    ? extracted
    : (
        printing: extracted.printing.isNotEmpty
            ? extracted.printing
            : fallback.printing,
        drying: extracted.drying.isNotEmpty
            ? extracted.drying
            : fallback.drying,
        storage: extracted.storage.isNotEmpty
            ? extracted.storage
            : fallback.storage,
      );

ImportedProductInstructions extractProductInstructions(
  String html, {
  String? structuredDescription,
}) {
  final document = html_parser.parse(html);
  final candidates = <String>[
    if (structuredDescription?.trim().isNotEmpty == true)
      structuredDescription!.trim(),
    ...document
        .querySelectorAll(
          'table tr, dl dt, dl dd, li, p, [class*="spec"], [class*="instruction"]',
        )
        .map((element) => element.text),
  ];
  final printing = <String>[];
  final drying = <String>[];
  final storage = <String>[];
  final seen = <String>{};
  final actionableValue = RegExp(
    r'\d+(?:\.\d+)?\s*(?:[-–—]\s*\d+(?:\.\d+)?)?\s*(?:°\s*[cf]|[cf]\b|mm/s|mm|%|hours?|hrs?|minutes?|mins?)',
    caseSensitive: false,
  );
  final printingTopic = RegExp(
    r'\b(?:nozzle|hotend|bed\s*temp(?:erature)?|print(?:ing)?\s*(?:temp(?:erature)?|speed)|fan\s*(?:speed)?|flow\s*rate|layer\s*height|extrusion\s*temp(?:erature)?)',
    caseSensitive: false,
  );
  final dryingTopic = RegExp(
    r'\b(?:dry|drying|dehydrate|dehydrator)\w*',
    caseSensitive: false,
  );
  final storageTopic = RegExp(
    r'\b(?:store|storage|humidity|desiccant|dry\s*box|airtight|sealed\s*bag)\b',
    caseSensitive: false,
  );
  final marketing = RegExp(
    r'\b(?:coming soon|sign up|download|special thanks|perfect for|beautiful|vibrant|rebranded|wide range|exceptional|next-generation|great color|community contributors?)\b',
    caseSensitive: false,
  );

  void add(List<String> target, String value) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty ||
        cleaned.length > 320 ||
        marketing.hasMatch(cleaned)) {
      return;
    }
    final key = cleaned.toLowerCase();
    if (seen.add(key) && target.length < 10) target.add(cleaned);
  }

  for (final candidate in candidates) {
    final pieces = candidate
        .replaceAllMapped(RegExp(r'([.!?])\s+'), (match) => '${match[1]}\n')
        .split(RegExp(r'[\r\n]+'));
    for (final piece in pieces) {
      final value = piece.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (value.isEmpty || marketing.hasMatch(value)) continue;
      final hasValue =
          actionableValue.hasMatch(value) || RegExp(r'\d').hasMatch(value);
      if (printingTopic.hasMatch(value) && hasValue) add(printing, value);
      if (dryingTopic.hasMatch(value) && hasValue) add(drying, value);
      if (storageTopic.hasMatch(value) &&
          (hasValue ||
              RegExp(
                r'\b(?:keep|use|place|avoid|recommended|recommend)\b',
                caseSensitive: false,
              ).hasMatch(value))) {
        add(storage, value);
      }
    }
  }
  return (
    printing: printing.join('\n'),
    drying: drying.join('\n'),
    storage: storage.join('\n'),
  );
}

class AddItemDialog extends StatefulWidget {
  const AddItemDialog({
    super.key,
    this.initialItem,
    this.vendors = const [],
    this.brands = const [],
    this.spoolTypes = starterSpoolTypes,
    this.customItemTypes = const [],
    this.products = const [],
    this.machineTypes = const [],
    this.machines = const [],
    this.initialBarcode = '',
    this.productTemplate,
    this.labelDraft,
  });
  final InventoryItem? initialItem;
  final List<VendorRecord> vendors;
  final List<BrandRecord> brands;
  final List<SpoolTypeRecord> spoolTypes;
  final List<CustomItemTypeRecord> customItemTypes;
  final List<CatalogProduct> products;
  final List<MachineTypeRecord> machineTypes;
  final List<MachineRecord> machines;
  final String initialBarcode;
  final InventoryItem? productTemplate;
  final LabelOcrDraft? labelDraft;

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  static const _webRequestTimeout = Duration(seconds: 20);
  static const _maximumProductPageBytes = 8 * 1024 * 1024;
  static const _maximumProductImageBytes = 12 * 1024 * 1024;
  final formKey = GlobalKey<FormState>();
  late final TextEditingController nameController;
  late final TextEditingController compatibilityController;
  late final TextEditingController costController;
  late final TextEditingController quantityController;
  late final TextEditingController quantityAlertThresholdController;
  late final TextEditingController dryingController;
  late final TextEditingController dryingTemperatureController;
  late final TextEditingController moistureLifespanController;
  late final TextEditingController moistureAlertThresholdController;
  late final TextEditingController vendorController;
  late final TextEditingController brandController;
  late final TextEditingController storageLocationController;
  late final TextEditingController deploymentLocationController;
  late final TextEditingController printingController;
  late final TextEditingController dryingInstructionsController;
  late final TextEditingController storageController;
  late final TextEditingController barcodeController;
  late final TextEditingController productUrlController;
  late final TextEditingController customSearchController;
  late InventoryType type;
  late bool deployed;
  late bool drying;
  late bool moistureAlertEnabled;
  late MoistureTimeUnit moistureTimeUnit;
  String? vendorId;
  String? brandId;
  String? productId;
  late String spoolTypeId;
  late bool amsCompatible;
  Uint8List? itemImage;
  Uint8List? labelImage;
  bool importingProductPage = false;
  bool processingLabel = false;
  ProductSearchProvider searchProvider = ProductSearchProvider.google;
  late final Set<String> compatibleMachineIds;
  String? customTypeId;
  final Map<String, TextEditingController> customFieldControllers = {};

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem ?? widget.productTemplate;
    final label = widget.labelDraft;
    moistureTimeUnit = item?.moistureTimeUnit ?? MoistureTimeUnit.days;
    nameController = TextEditingController(
      text: item?.name.isNotEmpty == true ? item!.name : label?.name,
    );
    compatibilityController = TextEditingController(
      text: item?.compatibility.isNotEmpty == true
          ? item!.compatibility.join(', ')
          : label?.compatibility,
    );
    costController = TextEditingController(text: item?.cost.toStringAsFixed(2));
    quantityController = TextEditingController(
      text: _formatBomQuantity(item?.quantity ?? 1),
    );
    quantityAlertThresholdController = TextEditingController(
      text: item?.quantityAlertThreshold == null
          ? ''
          : _formatBomQuantity(item!.quantityAlertThreshold!),
    );
    dryingController = TextEditingController(
      text: item?.dryingMinutes?.toString(),
    );
    final existingDrying = parseDryingSettings(item?.dryingInstructions ?? '');
    dryingTemperatureController = TextEditingController(
      text: existingDrying.temperatureC?.toString() ?? '',
    );
    moistureLifespanController = TextEditingController(
      text: _formatDurationAmount(
        item?.moistureLifespanMinutes,
        moistureTimeUnit,
      ),
    );
    moistureAlertThresholdController = TextEditingController(
      text: _formatDurationAmount(
        item?.moistureAlertThresholdMinutes,
        moistureTimeUnit,
      ),
    );
    vendorController = TextEditingController(text: item?.vendor);
    brandController = TextEditingController(
      text: item?.brand.isNotEmpty == true ? item!.brand : label?.brand,
    );
    storageLocationController = TextEditingController(
      text: widget.initialItem?.storageLocation,
    );
    deploymentLocationController = TextEditingController(
      text: widget.initialItem?.deploymentLocation,
    );
    printingController = TextEditingController(
      text: item?.printingInstructions.isNotEmpty == true
          ? item!.printingInstructions
          : label?.printingInstructions,
    );
    dryingInstructionsController = TextEditingController(
      text: item?.dryingInstructions,
    );
    storageController = TextEditingController(text: item?.storageInstructions);
    barcodeController = TextEditingController(
      text: item?.barcode.isNotEmpty == true
          ? item!.barcode
          : widget.initialBarcode,
    );
    productUrlController = TextEditingController(text: item?.productUrl);
    customSearchController = TextEditingController(
      text: 'https://www.google.com/search?q={query}',
    );
    // Recover older URL imports that were saved as Other despite an explicit
    // filament family in their product data.
    final inferredFilament = detectFilamentTemplate(
      '${item?.name ?? ''}\n${item?.printingInstructions ?? ''}\n${item?.dryingInstructions ?? ''}\n${label?.material ?? ''}',
    );
    final labelLooksLikeFilament = label?.filamentEvidence ?? false;
    type =
        item?.type == InventoryType.other &&
            (inferredFilament != null || labelLooksLikeFilament)
        ? InventoryType.filament
        : item?.type ??
              (labelLooksLikeFilament
                  ? InventoryType.filament
                  : InventoryType.other);
    customTypeId = item?.customTypeId.isNotEmpty == true
        ? item!.customTypeId
        : null;
    _configureCustomFields(item?.customFieldValues ?? const {});
    deployed = widget.initialItem?.deployed ?? false;
    drying = widget.initialItem?.filamentStatus == FilamentStatus.drying;
    moistureAlertEnabled = item?.moistureAlertEnabled ?? false;
    vendorId = widget.vendors
        .where((vendor) => vendor.name == item?.vendor)
        .firstOrNull
        ?.id;
    brandId = widget.brands
        .where((brand) => brand.name == item?.brand)
        .firstOrNull
        ?.id;
    productId = item?.catalogProductId;
    if (!widget.brands.any(
      (brand) => brand.id == brandId && brand.categories.contains(type),
    )) {
      brandId = null;
    }
    spoolTypeId = item?.spoolTypeId ?? defaultSpoolTypeId;
    if (!widget.spoolTypes.any((spool) => spool.id == spoolTypeId)) {
      spoolTypeId = widget.spoolTypes.firstOrNull?.id ?? defaultSpoolTypeId;
    }
    amsCompatible = item?.amsCompatible ?? false;
    itemImage = item?.imageBytes;
    labelImage = item?.labelImageBytes ?? label?.imageBytes;
    compatibleMachineIds = {...?item?.compatibleMachineIds};
    if (item == null && inferredFilament != null) {
      final settings = parseDryingSettings(inferredFilament.drying);
      dryingTemperatureController.text =
          settings.temperatureC?.toString() ?? '';
      dryingController.text = settings.durationMinutes?.toString() ?? '';
      if (printingController.text.isEmpty) {
        printingController.text = inferredFilament.printing;
      }
      storageController.text = inferredFilament.storage;
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    compatibilityController.dispose();
    costController.dispose();
    quantityController.dispose();
    quantityAlertThresholdController.dispose();
    dryingController.dispose();
    dryingTemperatureController.dispose();
    moistureLifespanController.dispose();
    moistureAlertThresholdController.dispose();
    vendorController.dispose();
    brandController.dispose();
    storageLocationController.dispose();
    deploymentLocationController.dispose();
    printingController.dispose();
    dryingInstructionsController.dispose();
    storageController.dispose();
    barcodeController.dispose();
    productUrlController.dispose();
    customSearchController.dispose();
    for (final controller in customFieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _responsiveFieldPair(bool compact, Widget first, Widget second) =>
      compact
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 16), second],
        )
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 8 : 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 820),
        child: SizedBox(
          width: 560,
          height: 820,
          child: Form(
            key: formKey,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 24,
                    compact ? 14 : 20,
                    compact ? 8 : 16,
                    compact ? 12 : 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.initialItem == null
                                  ? 'Add an item'
                                  : 'Edit item',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Text(
                              'Give the workshop something new to track.',
                              style: TextStyle(color: Color(0xff929aac)),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        key: const Key('save-item'),
                        onPressed: _save,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save'),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(compact ? 16 : 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _responsiveFieldPair(
                          compact,
                          TextFormField(
                            key: const Key('item-quantity'),
                            controller: quantityController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Quantity',
                              prefixText: '× ',
                              hintText: '1',
                            ),
                            validator: (value) {
                              final quantity = double.tryParse(value ?? '');
                              return quantity == null || quantity <= 0
                                  ? 'Enter a quantity'
                                  : null;
                            },
                          ),
                          TextFormField(
                            key: const Key('quantity-alert-threshold'),
                            controller: quantityAlertThresholdController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Low-stock alert at',
                              hintText: 'Optional',
                              helperText: 'Blank disables the alert',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return null;
                              }
                              final threshold = double.tryParse(value);
                              return threshold == null || threshold < 0
                                  ? 'Enter a valid threshold'
                                  : null;
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (widget.productTemplate != null) ...[
                          Container(
                            key: const Key('local-barcode-match'),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xff45d2bd)
                                  .withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.offline_bolt_rounded,
                                  color: Color(0xff45d2bd),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Known barcode — product details filled from your inventory.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        DropdownButtonFormField<InventoryType>(
                          key: const Key('item-type'),
                          initialValue: type,
                          decoration: const InputDecoration(labelText: 'Type'),
                          items: InventoryType.values
                              .where(
                                (value) =>
                                    value != InventoryType.custom ||
                                    widget.customItemTypes.isNotEmpty,
                              )
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(_typeLabel(value)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) _setType(value);
                          },
                        ),
                        if (type == InventoryType.custom) ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            key: const Key('custom-item-type'),
                            initialValue: customTypeId,
                            decoration: const InputDecoration(
                              labelText: 'Custom type',
                            ),
                            items: widget.customItemTypes
                                .map(
                                  (customType) => DropdownMenuItem(
                                    value: customType.id,
                                    child: Text(customType.name),
                                  ),
                                )
                                .toList(),
                            validator: (value) => value == null
                                ? 'Choose a custom item type'
                                : null,
                            onChanged: (value) => setState(() {
                              customTypeId = value;
                              _configureCustomFields();
                            }),
                          ),
                          for (final field
                              in _selectedCustomType?.contextualFields ??
                                  const <String>[]) ...[
                            const SizedBox(height: 14),
                            TextFormField(
                              key: Key(
                                'custom-field-${_normalizeTypeName(field)}',
                              ),
                              controller: customFieldControllers[field],
                              decoration: InputDecoration(labelText: field),
                            ),
                          ],
                        ],
                        const SizedBox(height: 16),
                        if (widget.brands.isNotEmpty) ...[
                          const Text(
                            'Brand',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          DropdownMenu<String>(
                            key: ValueKey('brand-picker-$brandId'),
                            expandedInsets: EdgeInsets.zero,
                            initialSelection: brandId ?? '__custom_brand__',
                            enableFilter: true,
                            enableSearch: true,
                            requestFocusOnTap: true,
                            leadingIcon: const Icon(Icons.search_rounded),
                            label: const Text('Search brands'),
                            dropdownMenuEntries: [
                              ...([
                                ..._availableBrands,
                              ]..sort((a, b) => a.name.compareTo(b.name))).map(
                                (brand) => DropdownMenuEntry(
                                  value: brand.id,
                                  label: brand.name,
                                  leadingIcon: _LogoAvatar(
                                    bytes: brand.logoBytes,
                                    fallbackIcon: Icons.sell_outlined,
                                  ),
                                ),
                              ),
                              const DropdownMenuEntry(
                                value: '__custom_brand__',
                                label: 'Custom / new',
                                leadingIcon: Icon(Icons.add_rounded),
                              ),
                            ],
                            onSelected: (value) => setState(() {
                              productId = null;
                              if (value == '__custom_brand__' ||
                                  value == null) {
                                brandId = null;
                                brandController.clear();
                                return;
                              }
                              final brand = widget.brands.firstWhere(
                                (candidate) => candidate.id == value,
                              );
                              brandId = brand.id;
                              brandController.text = brand.name;
                              if (!brand.vendorIds.contains(vendorId)) {
                                vendorId = null;
                                vendorController.clear();
                              }
                            }),
                          ),
                          if (brandId == null) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const Key('item-custom-brand'),
                              controller: brandController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Custom / new brand',
                                hintText: 'Cookiecad, Overture, Kaaber…',
                                helperText: 'Use when the brand is not in your catalog yet',
                              ),
                            ),
                          ],
                          if (brandId != null) ...[
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              key: const Key('catalog-vendor'),
                              initialValue: vendorId,
                              decoration: const InputDecoration(
                                labelText: 'Vendor',
                                helperText: 'Where this brand is purchased',
                              ),
                              items: _availableVendors
                                  .map(
                                    (vendor) => DropdownMenuItem(
                                      value: vendor.id,
                                      child: Row(
                                        children: [
                                          _LogoAvatar(
                                            bytes: vendor.logoBytes,
                                            fallbackIcon:
                                                Icons.storefront_outlined,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(vendor.name),
                                          if (vendor.isBrand) ...[
                                            const SizedBox(width: 8),
                                            const Icon(
                                              Icons.link_rounded,
                                              size: 16,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(() {
                                vendorId = value;
                                vendorController.text = widget.vendors
                                    .firstWhere((vendor) => vendor.id == value)
                                    .name;
                              }),
                            ),
                          ],
                          if (brandId != null) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Product / type',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            if (_availableProducts.length > 8)
                              DropdownButtonFormField<String>(
                                key: const Key('large-product-picker'),
                                initialValue: productId,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'Choose a product',
                                  helperText:
                                      '${_availableProducts.length} products in this category',
                                ),
                                items:
                                    ([..._availableProducts]..sort(
                                          (a, b) => a.name.compareTo(b.name),
                                        ))
                                        .map(
                                          (product) => DropdownMenuItem(
                                            value: product.id,
                                            child: Row(
                                              children: [
                                                _LogoAvatar(
                                                  bytes: product.imageBytes,
                                                  fallbackIcon: _typeIcon(
                                                    product.category,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    product.name,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (id) {
                                  final product = _availableProducts
                                      .where((value) => value.id == id)
                                      .firstOrNull;
                                  if (product != null) _selectProduct(product);
                                },
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _availableProducts
                                    .map(
                                      (product) => ChoiceChip(
                                        key: Key('product-${product.id}'),
                                        avatar: _LogoAvatar(
                                          bytes: product.imageBytes,
                                          fallbackIcon: _typeIcon(
                                            product.category,
                                          ),
                                        ),
                                        label: Text(product.name),
                                        selected: productId == product.id,
                                        onSelected: (_) =>
                                            _selectProduct(product),
                                      ),
                                    )
                                    .toList(),
                              ),
                          ],
                          const SizedBox(height: 20),
                        ],
                        TextFormField(
                          key: const Key('item-name'),
                          controller: nameController,
                          autofocus: true,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Item name',
                            hintText: 'Hardened steel 0.4 mm',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter an item name'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('item-barcode'),
                          controller: barcodeController,
                          decoration: const InputDecoration(
                            labelText: 'Product barcode (optional)',
                            helperText: 'UPC / EAN shared by this product; the item gets its own QR',
                            prefixIcon: Icon(Icons.barcode_reader),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Flex(
                          direction: compact ? Axis.vertical : Axis.horizontal,
                          crossAxisAlignment: compact
                              ? CrossAxisAlignment.stretch
                              : CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: compact ? double.infinity : 160,
                              child:
                                  DropdownButtonFormField<
                                    ProductSearchProvider
                                  >(
                                    key: const Key('search-provider'),
                                    initialValue: searchProvider,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Search with',
                                    ),
                                    items: ProductSearchProvider.values
                                        .map(
                                          (provider) => DropdownMenuItem(
                                            value: provider,
                                            child: Text(
                                              _searchProviderLabel(provider),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (provider) => setState(
                                      () => searchProvider = provider!,
                                    ),
                                  ),
                            ),
                            SizedBox(
                              width: compact ? 0 : 10,
                              height: compact ? 12 : 0,
                            ),
                            OutlinedButton.icon(
                              key: const Key('search-product-web'),
                              onPressed: _searchProductOnWeb,
                              icon: const Icon(Icons.travel_explore_rounded),
                              label: const Text('Search web'),
                            ),
                            SizedBox(
                              width: compact ? 0 : 10,
                              height: compact ? 8 : 0,
                            ),
                            if (compact)
                              const Text(
                                'Choose the correct product page, then paste its address below.',
                                style: TextStyle(
                                  color: Color(0xff929aac),
                                  fontSize: 12,
                                ),
                              )
                            else
                              const Expanded(
                                child: Text(
                                  'Choose the correct product page, then paste its address below.',
                                  style: TextStyle(
                                    color: Color(0xff929aac),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (searchProvider == ProductSearchProvider.custom) ...[
                          const SizedBox(height: 10),
                          TextFormField(
                            key: const Key('custom-search-url'),
                            controller: customSearchController,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'Custom search URL',
                              hintText: 'https://search.example/?q={query}',
                              helperText: 'Use {query} where the product search should go.',
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Flex(
                          direction: compact ? Axis.vertical : Axis.horizontal,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (compact)
                              TextFormField(
                                key: const Key('product-page-url'),
                                controller: productUrlController,
                                keyboardType: TextInputType.url,
                                decoration: const InputDecoration(
                                  labelText: 'Product page URL',
                                  hintText: 'https://vendor.example/product…',
                                ),
                              )
                            else
                              Expanded(
                                child: TextFormField(
                                  key: const Key('product-page-url'),
                                  controller: productUrlController,
                                  keyboardType: TextInputType.url,
                                  decoration: const InputDecoration(
                                    labelText: 'Product page URL',
                                    hintText: 'https://vendor.example/product…',
                                  ),
                                ),
                              ),
                            SizedBox(
                              width: compact ? 0 : 10,
                              height: compact ? 12 : 0,
                            ),
                            FilledButton.icon(
                              key: const Key('import-product-page'),
                              onPressed: importingProductPage
                                  ? null
                                  : _importProductPage,
                              icon: importingProductPage
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.download_rounded),
                              label: const Text('Import'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _ImagePickerButton(
                          key: const Key('item-image-picker'),
                          label: 'Item icon / image',
                          bytes: itemImage,
                          fallbackIcon: _typeIcon(type),
                          onChanged: (bytes) =>
                              setState(() => itemImage = bytes),
                        ),
                        const SizedBox(height: 10),
                        _ImagePickerButton(
                          key: const Key('label-image-picker'),
                          label: 'Label image',
                          bytes: labelImage,
                          fallbackIcon: Icons.document_scanner_outlined,
                          onChanged: (bytes) =>
                              setState(() => labelImage = bytes),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            key: const Key('process-label-image'),
                            onPressed: labelImage == null || processingLabel
                                ? null
                                : _processLabelImage,
                            icon: processingLabel
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.document_scanner_outlined),
                            label: Text(
                              processingLabel
                                  ? 'Reading label…'
                                  : 'Process label',
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (type == InventoryType.filament) ...[
                          const SizedBox(height: 14),
                          const Text(
                            'Spool size',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: widget.spoolTypes
                                .map(
                                  (spool) => ChoiceChip(
                                    key: Key('spool-size-${spool.id}'),
                                    label: Text(spool.label),
                                    selected: spoolTypeId == spool.id,
                                    onSelected: (_) =>
                                        setState(() => spoolTypeId = spool.id),
                                  ),
                                )
                                .toList(),
                          ),
                          SwitchListTile(
                            key: const Key('ams-compatible'),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('AMS compatible'),
                            subtitle: const Text(
                              'Spool dimensions and material can be used in an automatic material system.',
                            ),
                            value: amsCompatible,
                            onChanged: (value) =>
                                setState(() => amsCompatible = value),
                          ),
                        ],
                        if (widget.machines.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            key: const Key('compatible-machine-dropdown'),
                            decoration: const InputDecoration(
                              labelText: 'Add compatible machine',
                            ),
                            items: widget.machines
                                .where(
                                  (machine) => !compatibleMachineIds.contains(
                                    machine.id,
                                  ),
                                )
                                .map((machine) {
                                  final type = widget.machineTypes
                                      .where(
                                        (value) => value.id == machine.typeId,
                                      )
                                      .firstOrNull;
                                  return DropdownMenuItem(
                                    value: machine.id,
                                    child: Text(
                                      type == null
                                          ? machine.name
                                          : '${machine.name} · ${type.name}',
                                    ),
                                  );
                                })
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => compatibleMachineIds.add(value));
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: widget.machines
                                .where(
                                  (machine) =>
                                      compatibleMachineIds.contains(machine.id),
                                )
                                .map((machine) {
                                  final type = widget.machineTypes
                                      .where(
                                        (value) => value.id == machine.typeId,
                                      )
                                      .firstOrNull;
                                  return InputChip(
                                    key: Key(
                                      'compatible-machine-${machine.id}',
                                    ),
                                    label: Text(
                                      type == null
                                          ? machine.name
                                          : '${machine.name} · ${type.name}',
                                    ),
                                    onDeleted: () => setState(
                                      () => compatibleMachineIds.remove(
                                        machine.id,
                                      ),
                                    ),
                                  );
                                })
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('item-compatibility'),
                          controller: compatibilityController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Compatibility / tags',
                            hintText: 'E3D V6, 1.75 mm, 24 V',
                            helperText: 'Separate tags with commas',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('item-cost'),
                          controller: costController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Cost',
                            prefixText: r'$ ',
                            hintText: '0.00',
                          ),
                          validator: (value) {
                            final cost = double.tryParse(value ?? '');
                            return cost == null || cost < 0
                                ? 'Enter a valid cost'
                                : null;
                          },
                        ),
                        if (widget.vendors.isEmpty) ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const Key('item-vendor'),
                            controller: vendorController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Vendor',
                              hintText: 'E3D, Polymaker, local supplier…',
                            ),
                          ),
                        ],
                        if (type == InventoryType.filament) ...[
                          if (widget.brands.isEmpty) ...[
                            const SizedBox(height: 14),
                            TextFormField(
                              key: const Key('item-brand'),
                              controller: brandController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Brand',
                                hintText: 'Polymaker, Overture, Prusament…',
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          _responsiveFieldPair(
                            compact,
                            TextFormField(
                              key: const Key('storage-location'),
                              controller: storageLocationController,
                              decoration: const InputDecoration(
                                labelText: 'Storage location',
                              ),
                            ),
                            TextFormField(
                              key: const Key('deployment-location'),
                              controller: deploymentLocationController,
                              decoration: const InputDecoration(
                                labelText: 'Deployment location',
                              ),
                            ),
                          ),
                        ],
                        if (type == InventoryType.filament) ...[
                          const SizedBox(height: 14),
                          _responsiveFieldPair(
                            compact,
                            TextFormField(
                              key: const Key('drying-temperature'),
                              controller: dryingTemperatureController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Drying temperature',
                                suffixText: '°C',
                              ),
                            ),
                            TextFormField(
                              key: const Key('drying-duration'),
                              controller: dryingController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Drying duration',
                                suffixText: 'min',
                              ),
                              validator: (value) {
                                if (!drying) return null;
                                final minutes = int.tryParse(value ?? '');
                                return minutes == null || minutes <= 0
                                    ? 'Required while drying'
                                    : null;
                              },
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const Key('moisture-lifespan'),
                            controller: moistureLifespanController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Moisture lifespan',
                              suffixText: moistureTimeUnit.name,
                              helperText: 'Time from dry to too wet to print',
                            ),
                            validator: (value) {
                              final amount = double.tryParse(value ?? '');
                              return amount == null || amount <= 0
                                  ? 'Enter a lifespan'
                                  : null;
                            },
                          ),
                          const SizedBox(height: 10),
                          SegmentedButton<MoistureTimeUnit>(
                            key: const Key('moisture-time-unit'),
                            segments: const [
                              ButtonSegment(
                                value: MoistureTimeUnit.hours,
                                label: Text('Hours'),
                              ),
                              ButtonSegment(
                                value: MoistureTimeUnit.days,
                                label: Text('Days'),
                              ),
                            ],
                            selected: {moistureTimeUnit},
                            onSelectionChanged: (selection) =>
                                _setMoistureTimeUnit(selection.first),
                          ),
                          SwitchListTile(
                            key: const Key('moisture-alert-toggle'),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Moisture alert'),
                            subtitle: const Text(
                              'Show this filament in the notification list near expiry.',
                            ),
                            value: moistureAlertEnabled,
                            onChanged: (value) =>
                                setState(() => moistureAlertEnabled = value),
                          ),
                          if (moistureAlertEnabled)
                            TextFormField(
                              key: const Key('moisture-alert-threshold'),
                              controller: moistureAlertThresholdController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: 'Alert when time remaining reaches',
                                suffixText: moistureTimeUnit.name,
                              ),
                              validator: (value) {
                                final threshold = double.tryParse(value ?? '');
                                final lifespan = double.tryParse(
                                  moistureLifespanController.text,
                                );
                                if (threshold == null || threshold < 0) {
                                  return 'Enter an alert threshold';
                                }
                                if (lifespan != null && threshold > lifespan) {
                                  return 'Cannot exceed moisture lifespan';
                                }
                                return null;
                              },
                            ),
                        ],
                        if (type.supportsPrinting) ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const Key('printing-instructions'),
                            controller: printingController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Printing instructions',
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('storage-instructions'),
                          controller: storageController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Storage instructions',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setMoistureTimeUnit(MoistureTimeUnit next) {
    if (next == moistureTimeUnit) return;
    final lifespanMinutes = _minutesFromAmount(
      double.tryParse(moistureLifespanController.text),
      moistureTimeUnit,
    );
    final thresholdMinutes = _minutesFromAmount(
      double.tryParse(moistureAlertThresholdController.text),
      moistureTimeUnit,
    );
    setState(() {
      moistureTimeUnit = next;
      moistureLifespanController.text =
          _formatDurationAmount(lifespanMinutes, next) ?? '';
      moistureAlertThresholdController.text =
          _formatDurationAmount(thresholdMinutes, next) ?? '';
    });
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    final compatibility = compatibilityController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    Navigator.pop(
      context,
      InventoryItem(
        id: widget.initialItem?.id ?? _newInventoryId(),
        name: nameController.text.trim(),
        type: type,
        compatibility: compatibility,
        added: widget.initialItem?.added ?? DateTime.now(),
        cost: double.parse(costController.text),
        quantity: double.parse(quantityController.text),
        quantityAlertThreshold: double.tryParse(
          quantityAlertThresholdController.text,
        ),
        color: _typeColor(type),
        dryingMinutes: type == InventoryType.filament
            ? int.tryParse(dryingController.text)
            : null,
        dryingRemaining: type == InventoryType.filament
            ? drying
                  ? widget.initialItem?.dryingRemaining ??
                        int.tryParse(dryingController.text)
                  : 0
            : null,
        dryingStartedAt: type == InventoryType.filament && drying
            ? widget.initialItem?.dryingStartedAt ?? DateTime.now()
            : null,
        moistureLifespanMinutes: type == InventoryType.filament
            ? _minutesFromAmount(
                double.tryParse(moistureLifespanController.text),
                moistureTimeUnit,
              )
            : null,
        moistureTimeUnit: moistureTimeUnit,
        moistureAlertEnabled:
            type == InventoryType.filament && moistureAlertEnabled,
        moistureAlertThresholdMinutes:
            type == InventoryType.filament && moistureAlertEnabled
            ? _minutesFromAmount(
                double.tryParse(moistureAlertThresholdController.text),
                moistureTimeUnit,
              )
            : null,
        deployed: deployed,
        vendor: vendorController.text.trim(),
        printingInstructions: type.supportsPrinting
            ? printingController.text.trim()
            : '',
        dryingInstructions:
            type.supportsDrying &&
                dryingTemperatureController.text.trim().isNotEmpty
            ? 'Dry at ${dryingTemperatureController.text.trim()}°C for ${dryingController.text.trim()} minutes.'
            : type.supportsDrying
            ? dryingInstructionsController.text.trim()
            : '',
        storageInstructions: storageController.text.trim(),
        archived: widget.initialItem?.archived ?? false,
        filamentStatus:
            widget.initialItem?.filamentStatus ?? FilamentStatus.ready,
        brand: brandController.text.trim(),
        storageLocation: storageLocationController.text.trim(),
        deploymentLocation: deploymentLocationController.text.trim(),
        lastDriedAt:
            widget.initialItem?.lastDriedAt ??
            (type == InventoryType.filament ? DateTime.now() : null),
        imageBytes: itemImage,
        labelImageBytes: labelImage,
        barcode: barcodeController.text.trim(),
        productUrl: productUrlController.text.trim(),
        compatibleMachineIds: compatibleMachineIds.toList(),
        spoolTypeId: type == InventoryType.filament
            ? spoolTypeId
            : defaultSpoolTypeId,
        amsCompatible: type == InventoryType.filament && amsCompatible,
        catalogProductId: productId,
        customTypeId: type == InventoryType.custom ? customTypeId ?? '' : '',
        customTypeName: type == InventoryType.custom
            ? _selectedCustomType?.name ?? ''
            : '',
        customFieldValues: type == InventoryType.custom
            ? {
                for (final entry in customFieldControllers.entries)
                  entry.key: entry.value.text.trim(),
              }
            : const {},
      ),
    );
  }

  Future<void> _processLabelImage() async {
    final bytes = labelImage;
    if (bytes == null || processingLabel) return;
    setState(() => processingLabel = true);
    try {
      final draft = await recognizeProductLabel(bytes);
      if (!mounted) return;
      final template = detectFilamentTemplate(
        '${draft.material}\n${draft.name}\n${draft.rawText}',
      );
      var filled = 0;
      setState(() {
        if (draft.name.isNotEmpty) {
          nameController.text = draft.name;
          filled++;
        }
        if (draft.brand.isNotEmpty) {
          brandController.text = draft.brand;
          brandId = widget.brands
              .where(
                (brand) =>
                    brand.name.toLowerCase() == draft.brand.toLowerCase(),
              )
              .firstOrNull
              ?.id;
          filled++;
        }
        if (draft.compatibility.isNotEmpty) {
          compatibilityController.text = draft.compatibility;
          filled++;
        }
        if (draft.printingInstructions.isNotEmpty) {
          printingController.text = draft.printingInstructions;
          filled++;
        }
        if (template != null || draft.filamentEvidence) {
          type = InventoryType.filament;
        }
        if (template != null) {
          final settings = parseDryingSettings(template.drying);
          if (dryingTemperatureController.text.isEmpty &&
              settings.temperatureC != null) {
            dryingTemperatureController.text = settings.temperatureC.toString();
            filled++;
          }
          if (dryingController.text.isEmpty &&
              settings.durationMinutes != null) {
            dryingController.text = settings.durationMinutes.toString();
            filled++;
          }
          if (printingController.text.isEmpty && template.printing.isNotEmpty) {
            printingController.text = template.printing;
            filled++;
          }
          if (storageController.text.isEmpty && template.storage.isNotEmpty) {
            storageController.text = template.storage;
            filled++;
          }
        }
        processingLabel = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            filled == 0
                ? 'Text was detected, but no item fields could be identified.'
                : 'Label processed — $filled fields filled. Review before saving.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => processingLabel = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not process label: $error')),
      );
    }
  }

  Future<void> _searchProductOnWeb() async {
    final barcode = barcodeController.text.trim();
    final name = nameController.text.trim();
    if (barcode.isEmpty && name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter an item name or barcode before searching.'),
        ),
      );
      return;
    }
    final query = barcode.isNotEmpty ? '"$barcode" product' : '"$name" product';
    final template = switch (searchProvider) {
      ProductSearchProvider.google => 'https://www.google.com/search?q={query}',
      ProductSearchProvider.bing => 'https://www.bing.com/search?q={query}',
      ProductSearchProvider.duckDuckGo => 'https://duckduckgo.com/?q={query}',
      ProductSearchProvider.brave =>
        'https://search.brave.com/search?q={query}',
      ProductSearchProvider.custom => customSearchController.text.trim(),
    };
    if (!template.contains('{query}')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Custom search URL must contain {query}.'),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(
      template.replaceAll('{query}', Uri.encodeQueryComponent(query)),
    );
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid HTTP or HTTPS search URL.'),
        ),
      );
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the web browser.')),
      );
    }
  }

  Future<void> _importProductPage() async {
    final uri = Uri.tryParse(productUrlController.text.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !{'http', 'https'}.contains(uri.scheme)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paste a valid HTTP or HTTPS product URL.'),
        ),
      );
      return;
    }
    setState(() => importingProductPage = true);
    try {
      final response = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36',
              'Accept': 'text/html,application/xhtml+xml',
              'Accept-Language': 'en-US,en;q=0.9',
            },
          )
          .timeout(_webRequestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('page returned HTTP ${response.statusCode}');
      }
      if (response.bodyBytes.length > _maximumProductPageBytes) {
        throw Exception('product page is larger than 8 MB');
      }
      final document = html_parser.parse(response.body);
      Map<String, dynamic>? product;
      for (final script in document.querySelectorAll(
        'script[type="application/ld+json"]',
      )) {
        try {
          product ??= _findProductJson(jsonDecode(script.text));
        } catch (_) {
          // Some sites include malformed analytics JSON-LD; keep looking.
        }
      }
      product ??= extractFallbackProductMetadata(response.body, uri);
      if (product == null) {
        throw Exception('this page does not expose structured product details');
      }
      final brandValue = product['brand'];
      final brand = brandValue is Map
          ? brandValue['name']?.toString()
          : brandValue?.toString();
      final offers = product['offers'];
      final offer = offers is List
          ? offers.whereType<Map>().firstOrNull
          : offers is Map
          ? offers
          : null;
      final imageUrls = <String>[];
      _collectImageUrls(product['image'], imageUrls);
      for (final selector in const [
        'meta[property="og:image"]',
        'meta[name="twitter:image"]',
        'link[rel="image_src"]',
      ]) {
        final element = document.querySelector(selector);
        final candidate =
            element?.attributes['content'] ?? element?.attributes['href'];
        if (candidate != null) imageUrls.add(candidate);
      }
      Uint8List? downloadedImage;
      for (final imageUrl in imageUrls.toSet()) {
        try {
          final imageUri = uri.resolve(imageUrl);
          if (!{'http', 'https'}.contains(imageUri.scheme)) continue;
          final imageResponse = await http
              .get(
                imageUri,
                headers: {
                  'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36',
                  'Accept': 'image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8',
                  'Referer': uri.toString(),
                },
              )
              .timeout(_webRequestTimeout);
          final contentType = imageResponse.headers['content-type'] ?? '';
          if (imageResponse.statusCode == 200 &&
              imageResponse.bodyBytes.isNotEmpty &&
              imageResponse.bodyBytes.length <= _maximumProductImageBytes &&
              contentType.startsWith('image/') &&
              !contentType.contains('svg')) {
            downloadedImage = imageResponse.bodyBytes;
            break;
          }
        } catch (_) {
          // Product sites often advertise several CDN variants; try the next.
        }
      }
      if (!mounted) return;
      final description = product['description']?.toString();
      final extractedInstructions = extractProductInstructions(
        response.body,
        structuredDescription: description,
      );
      final productName = product['name']?.toString() ?? '';
      final template = detectFilamentTemplate(
        '$productName\n${description ?? ''}\n${document.body?.text ?? ''}',
      );
      final instructions = applyFilamentFallbacks(
        extractedInstructions,
        template,
      );
      setState(() {
        nameController.text =
            product!['name']?.toString() ?? nameController.text;
        brandController.text = brand ?? brandController.text;
        brandId = widget.brands
            .where((entry) => entry.name.toLowerCase() == brand?.toLowerCase())
            .firstOrNull
            ?.id;
        vendorController.text = uri.host.replaceFirst(RegExp(r'^www\.'), '');
        final price = offer?['price']?.toString();
        if (price != null && double.tryParse(price) != null) {
          costController.text = price;
        }
        if (printingController.text.isEmpty &&
            instructions.printing.isNotEmpty) {
          printingController.text = instructions.printing;
        }
        if (instructions.drying.isNotEmpty) {
          final settings = parseDryingSettings(instructions.drying);
          if (dryingTemperatureController.text.isEmpty &&
              settings.temperatureC != null) {
            dryingTemperatureController.text = settings.temperatureC.toString();
          }
          if (dryingController.text.isEmpty &&
              settings.durationMinutes != null) {
            dryingController.text = settings.durationMinutes.toString();
          }
          dryingInstructionsController.text = instructions.drying;
        }
        if (storageController.text.isEmpty && instructions.storage.isNotEmpty) {
          storageController.text = instructions.storage;
        }
        if (template != null) type = InventoryType.filament;
        itemImage = downloadedImage ?? itemImage;
        importingProductPage = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            downloadedImage == null
                ? 'Product details imported; no usable image was exposed.'
                : 'Product details and image imported. Review before saving.',
          ),
        ),
      );
    } catch (exception) {
      if (!mounted) return;
      setState(() => importingProductPage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not import product: $exception')),
      );
    }
  }

  List<VendorRecord> get _availableVendors => widget.vendors
      .where((vendor) => _selectedBrand?.vendorIds.contains(vendor.id) ?? false)
      .toList();

  List<BrandRecord> get _availableBrands =>
      widget.brands.where((brand) => brand.categories.contains(type)).toList();

  CustomItemTypeRecord? get _selectedCustomType => widget.customItemTypes
      .where((customType) => customType.id == customTypeId)
      .firstOrNull;

  void _configureCustomFields([Map<String, String> values = const {}]) {
    for (final controller in customFieldControllers.values) {
      controller.dispose();
    }
    customFieldControllers.clear();
    for (final field
        in _selectedCustomType?.contextualFields ?? const <String>[]) {
      customFieldControllers[field] = TextEditingController(
        text: values[field] ?? '',
      );
    }
  }

  BrandRecord? get _selectedBrand =>
      widget.brands.where((brand) => brand.id == brandId).firstOrNull;

  List<CatalogProduct> get _availableProducts => widget.products
      .where(
        (product) => product.brandId == brandId && product.category == type,
      )
      .toList();

  void _setType(InventoryType next) {
    setState(() {
      type = next;
      if (next != InventoryType.custom) {
        customTypeId = null;
        _configureCustomFields();
      } else if (customTypeId == null && widget.customItemTypes.length == 1) {
        customTypeId = widget.customItemTypes.single.id;
        _configureCustomFields();
      }
      productId = null;
      if (_selectedBrand?.categories.contains(next) != true) {
        brandId = null;
        brandController.clear();
        vendorId = null;
        vendorController.clear();
      }
    });
  }

  void _selectProduct(CatalogProduct product) {
    setState(() {
      productId = product.id;
      type = product.category;
      nameController.text = product.name;
      costController.text = product.defaultCost.toStringAsFixed(2);
      dryingController.text = product.dryingMinutes?.toString() ?? '';
      printingController.text = product.printingInstructions;
      dryingInstructionsController.text = product.dryingInstructions;
      final settings = parseDryingSettings(product.dryingInstructions);
      dryingTemperatureController.text =
          settings.temperatureC?.toString() ?? '';
      if (dryingController.text.isEmpty && settings.durationMinutes != null) {
        dryingController.text = settings.durationMinutes.toString();
      }
      storageController.text = product.storageInstructions;
      itemImage = product.imageBytes;
    });
  }
}

String _typeLabel(InventoryType type) => switch (type) {
  InventoryType.other => 'Other',
  InventoryType.fastener => 'Fasteners',
  InventoryType.filament => 'Filament',
  InventoryType.printedPart => 'Printed parts',
  InventoryType.resin => 'Resin',
  InventoryType.nozzle => 'Nozzle',
  InventoryType.heatBreak => 'Heat break',
  InventoryType.heatBlock => 'Heat block',
  InventoryType.sock => 'Silicone sock',
  InventoryType.custom => 'Custom',
};

InventoryType? smartMatchInventoryType(String input) {
  final needle = _normalizeTypeName(input);
  if (needle.isEmpty) return null;
  const aliases = <InventoryType, List<String>>{
    InventoryType.other: ['other', 'misc', 'miscellaneous'],
    InventoryType.fastener: [
      'fastener',
      'fasteners',
      'screw',
      'screws',
      'bolt',
      'bolts',
      'nut',
      'nuts',
      'washer',
      'washers',
    ],
    InventoryType.filament: [
      'filament',
      'filaments',
      'pla',
      'htpla',
      'petg',
      'pctg',
      'nylon',
      'abs',
      'asa',
      'tpu',
    ],
    InventoryType.printedPart: [
      'printed part',
      'printed parts',
      '3d printed part',
      'print',
    ],
    InventoryType.resin: ['resin', 'resins', 'sla resin'],
    InventoryType.nozzle: ['nozzle', 'nozzles'],
    InventoryType.heatBreak: ['heat break', 'heatbreak', 'heat breaks'],
    InventoryType.heatBlock: ['heat block', 'heatblock', 'heater block'],
    InventoryType.sock: ['silicone sock', 'sock', 'socks'],
  };
  for (final entry in aliases.entries) {
    if (entry.value.any((alias) => _normalizeTypeName(alias) == needle)) {
      return entry.key;
    }
  }
  InventoryType? bestType;
  var bestDistance = 1 << 20;
  var tied = false;
  for (final entry in aliases.entries) {
    for (final alias in entry.value) {
      final normalizedAlias = _normalizeTypeName(alias);
      final distance = _levenshteinDistance(needle, normalizedAlias);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestType = entry.key;
        tied = false;
      } else if (distance == bestDistance && bestType != entry.key) {
        tied = true;
      }
    }
  }
  final allowedDistance = needle.length <= 4
      ? 1
      : needle.length <= 7
      ? 2
      : 3;
  return !tied && bestDistance <= allowedDistance ? bestType : null;
}

RapidizerParseResult parseRapidizerText(String input) {
  final items = <RapidItemDraft>[];
  final errors = <String>[];
  final lines = input.split(RegExp(r'\r?\n'));
  for (var index = 0; index < lines.length; index++) {
    final rawLine = lines[index].trim();
    if (rawLine.isEmpty) continue;
    final tokens = rawLine.split(RegExp(r'\s+'));
    if (tokens.length < 4) {
      errors.add('Line ${index + 1}: use Name Type Quantity Price.');
      continue;
    }
    final quantity = double.tryParse(
      _rapidNumberToken(tokens[tokens.length - 2]),
    );
    final price = double.tryParse(_rapidNumberToken(tokens.last));
    if (quantity == null || quantity <= 0) {
      errors.add(
        'Line ${index + 1}: invalid quantity “${tokens[tokens.length - 2]}”.',
      );
      continue;
    }
    if (price == null || price < 0) {
      errors.add('Line ${index + 1}: invalid price “${tokens.last}”.');
      continue;
    }
    final body = tokens.sublist(0, tokens.length - 2);
    InventoryType? type;
    var typeWordCount = 0;
    final maximumTypeWords = body.length > 3 ? 3 : body.length - 1;
    for (var count = 1; count <= maximumTypeWords; count++) {
      final candidate = body.sublist(body.length - count).join(' ');
      final match = smartMatchInventoryType(candidate);
      if (match != null) {
        type = match;
        typeWordCount = count;
        break;
      }
    }
    if (type == null) {
      errors.add(
        'Line ${index + 1}: could not recognize the type before quantity.',
      );
      continue;
    }
    var name = body.sublist(0, body.length - typeWordCount).join(' ').trim();
    if (name.length >= 2 &&
        ((name.startsWith('"') && name.endsWith('"')) ||
            (name.startsWith("'") && name.endsWith("'")))) {
      name = name.substring(1, name.length - 1).trim();
    }
    if (name.isEmpty) {
      errors.add('Line ${index + 1}: item name is missing.');
      continue;
    }
    items.add(
      RapidItemDraft(name: name, type: type, quantity: quantity, price: price),
    );
  }
  return RapidizerParseResult(items: items, errors: errors);
}

String _rapidNumberToken(String value) => value
    .replaceAll(RegExp(r'[$,]'), '')
    .replaceFirst(RegExp(r'^[xX]'), '')
    .replaceFirst(RegExp(r'[xX]$'), '');

String _normalizeTypeName(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

int _levenshteinDistance(String left, String right) {
  if (left == right) return 0;
  if (left.isEmpty) return right.length;
  if (right.isEmpty) return left.length;
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var leftIndex = 0; leftIndex < left.length; leftIndex++) {
    final current = List<int>.filled(right.length + 1, 0);
    current[0] = leftIndex + 1;
    for (var rightIndex = 0; rightIndex < right.length; rightIndex++) {
      final substitution =
          previous[rightIndex] +
          (left.codeUnitAt(leftIndex) == right.codeUnitAt(rightIndex) ? 0 : 1);
      current[rightIndex + 1] = [
        current[rightIndex] + 1,
        previous[rightIndex + 1] + 1,
        substitution,
      ].reduce((a, b) => a < b ? a : b);
    }
    previous = current;
  }
  return previous.last;
}

IconData _typeIcon(InventoryType type) => switch (type) {
  InventoryType.other => Icons.inventory_2_outlined,
  InventoryType.fastener => Icons.hardware_rounded,
  InventoryType.filament => Icons.donut_large_rounded,
  InventoryType.printedPart => Icons.view_in_ar_outlined,
  InventoryType.resin => Icons.opacity_rounded,
  InventoryType.nozzle => Icons.change_history_rounded,
  InventoryType.heatBreak => Icons.compress_rounded,
  InventoryType.heatBlock => Icons.view_in_ar_rounded,
  InventoryType.sock => Icons.shield_outlined,
  InventoryType.custom => Icons.tune_rounded,
};

Color _typeColor(InventoryType type) => switch (type) {
  InventoryType.other => const Color(0xff929aac),
  InventoryType.fastener => const Color(0xffc8a96b),
  InventoryType.filament => const Color(0xff7455ff),
  InventoryType.printedPart => const Color(0xffa987ff),
  InventoryType.resin => const Color(0xffd15cff),
  InventoryType.nozzle => const Color(0xffffb13b),
  InventoryType.heatBreak => const Color(0xff45d2bd),
  InventoryType.heatBlock => const Color(0xffff6b6b),
  InventoryType.sock => const Color(0xff55a8ff),
  InventoryType.custom => const Color(0xff9aa4b8),
};

class _ItemVisual extends StatelessWidget {
  const _ItemVisual({required this.item, required this.size});
  final InventoryItem item;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .3),
    child: SizedBox.square(
      dimension: size,
      child: item.imageBytes == null
          ? ColoredBox(
              color: item.color.withValues(alpha: .16),
              child: Icon(item.icon, color: item.color),
            )
          : Image.memory(item.imageBytes!, fit: BoxFit.cover),
    ),
  );
}

class _ArchiveBadge extends StatelessWidget {
  const _ArchiveBadge({required this.item});
  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (item.archiveDisposition) {
      ArchiveDisposition.archived => (
        'Archived',
        Icons.archive_outlined,
        const Color(0xff929aac),
      ),
      ArchiveDisposition.depleted => (
        'Depleted',
        Icons.hourglass_empty_rounded,
        const Color(0xffffa552),
      ),
      ArchiveDisposition.destroyed => (
        'Destroyed',
        Icons.broken_image_outlined,
        const Color(0xffff6b6b),
      ),
    };
    return Chip(
      key: Key('archive-${item.archiveDisposition.name}-${item.id}'),
      avatar: Icon(icon, size: 17, color: color),
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: .55)),
      backgroundColor: color.withValues(alpha: .12),
      visualDensity: VisualDensity.compact,
    );
  }
}

class ItemDetailsPanel extends StatefulWidget {
  const ItemDetailsPanel({
    super.key,
    required this.item,
    required this.onChanged,
    required this.machines,
    required this.machineTypes,
    required this.spoolTypes,
    this.canEdit = true,
    this.canArchive = true,
  });
  final InventoryItem item;
  final ValueChanged<InventoryItem> onChanged;
  final List<MachineRecord> machines;
  final List<MachineTypeRecord> machineTypes;
  final List<SpoolTypeRecord> spoolTypes;
  final bool canEdit;
  final bool canArchive;

  @override
  State<ItemDetailsPanel> createState() => _ItemDetailsPanelState();
}

class _ItemDetailsPanelState extends State<ItemDetailsPanel> {
  bool useFahrenheit = false;
  late InventoryItem item;

  @override
  void initState() {
    super.initState();
    item = widget.item;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveDrying = _effectiveDryingInstructions(item);
    final dryingSettings = parseDryingSettings(effectiveDrying);
    final dryingDuration = item.dryingMinutes ?? dryingSettings.durationMinutes;
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff191d29), Color(0xff10141d)],
          ),
          border: Border(
            left: BorderSide(
              color: const Color(0xff8e75ff).withValues(alpha: .55),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xff6f54ff).withValues(alpha: .22),
              blurRadius: 36,
              spreadRadius: 2,
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            width: 520,
            height: double.infinity,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.imageBytes != null)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.memory(
                            item.imageBytes!,
                            key: const Key('sidebar-product-image'),
                            width: double.infinity,
                            fit: BoxFit.fitWidth,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xff0d1017)
                                  .withValues(alpha: .82),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        _ItemVisual(item: item, size: 52),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  const SizedBox(height: 24),
                  Text(
                    item.typeLabel.toUpperCase(),
                    style: TextStyle(
                      color: item.color,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.compatibility.join('  •  '),
                    style: const TextStyle(color: Color(0xff929aac)),
                  ),
                  if (item.compatibleMachineIds.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Compatible machines',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.machines
                          .where(
                            (machine) =>
                                item.compatibleMachineIds.contains(machine.id),
                          )
                          .map((machine) {
                            final type = widget.machineTypes
                                .where((value) => value.id == machine.typeId)
                                .firstOrNull;
                            return Chip(
                              avatar: const Icon(
                                Icons.memory_rounded,
                                size: 18,
                              ),
                              label: Text(
                                type == null
                                    ? machine.name
                                    : '${machine.name} · ${type.name}',
                              ),
                            );
                          })
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 22),
                  const Text(
                    'Status',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  if (item.type == InventoryType.filament)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _statusChip(
                          FilamentStatus.ready,
                          'Ready',
                          Icons.check_rounded,
                          const Color(0xff45d2bd),
                        ),
                        _statusChip(
                          FilamentStatus.deployed,
                          'Deployed',
                          Icons.lock_outline_rounded,
                          const Color(0xff55a8ff),
                        ),
                        _statusChip(
                          FilamentStatus.drying,
                          'Drying',
                          Icons.water_drop_outlined,
                          const Color(0xff9c83ff),
                        ),
                        _statusChip(
                          FilamentStatus.queuedForDrying,
                          'Wet',
                          Icons.water_drop_rounded,
                          const Color(0xffffa552),
                        ),
                      ],
                    )
                  else
                    FilterChip(
                      key: const Key('item-deployed'),
                      avatar: const Icon(Icons.lock_outline_rounded, size: 18),
                      label: const Text('Deployed'),
                      selected: item.deployed,
                      selectedColor: const Color(0xff55a8ff)
                          .withValues(alpha: .28),
                      onSelected: widget.canEdit ? _setDeployed : null,
                    ),
                  if (_isLowStock(item)) ...[
                    const SizedBox(height: 10),
                    Chip(
                      key: const Key('low-stock-status'),
                      avatar: const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xffffa552),
                        size: 18,
                      ),
                      label: Text(
                        'Low stock · ${_formatBomQuantity(item.quantity)} remaining',
                      ),
                      side: const BorderSide(color: Color(0xffffa552)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: QrImageView(
                      data: 'inventorinator:item:${item.id}',
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    item.id,
                    style: const TextStyle(
                      color: Color(0xff929aac),
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    key: const Key('download-qr'),
                    onPressed: () => _downloadQr(context, item),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Download labeled QR'),
                  ),
                  const SizedBox(height: 28),
                  _DetailSection(
                    icon: Icons.numbers_rounded,
                    title: 'Quantity',
                    text: _formatBomQuantity(item.quantity),
                  ),
                  if (item.quantityAlertThreshold != null)
                    _DetailSection(
                      icon: Icons.notification_important_outlined,
                      title: 'Low-stock alert threshold',
                      text: _formatBomQuantity(item.quantityAlertThreshold!),
                    ),
                  if (item.barcode.isNotEmpty)
                    _DetailSection(
                      icon: Icons.barcode_reader,
                      title: 'Product barcode',
                      text: item.barcode,
                    ),
                  if (item.productUrl.isNotEmpty)
                    _ProductSourceSection(url: item.productUrl),
                  if (item.labelImageBytes != null) ...[
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Icon(
                          Icons.document_scanner_outlined,
                          color: Color(0xff8e75ff),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Label',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(
                        item.labelImageBytes!,
                        key: const Key('sidebar-label-image'),
                        width: double.infinity,
                        fit: BoxFit.fitWidth,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  _DetailSection(
                    icon: Icons.storefront_outlined,
                    title: 'Vendor',
                    text: item.vendor,
                  ),
                  if (item.type == InventoryType.filament)
                    _DetailSection(
                      icon: Icons.sell_outlined,
                      title: 'Brand',
                      text: item.brand,
                    ),
                  if (item.type == InventoryType.filament)
                    _DetailSection(
                      icon: Icons.scale_outlined,
                      title: 'Spool size',
                      text:
                          widget.spoolTypes
                              .where((spool) => spool.id == item.spoolTypeId)
                              .firstOrNull
                              ?.label ??
                          '1 kg',
                    ),
                  if (item.type == InventoryType.filament)
                    _DetailSection(
                      icon: item.amsCompatible
                          ? Icons.check_circle_outline_rounded
                          : Icons.block_rounded,
                      title: 'AMS compatibility',
                      text: item.amsCompatible
                          ? 'Compatible'
                          : 'Not marked compatible',
                    ),
                  if (item.type == InventoryType.filament &&
                      item.filamentStatus == FilamentStatus.deployed)
                    _DetailSection(
                      icon: Icons.precision_manufacturing_outlined,
                      title: 'Deployment location',
                      text: item.deploymentLocation,
                    ),
                  if (item.type == InventoryType.filament &&
                      (item.filamentStatus == FilamentStatus.ready ||
                          item.filamentStatus ==
                              FilamentStatus.queuedForDrying))
                    _DetailSection(
                      icon: Icons.shelves,
                      title: 'Storage location',
                      text: item.storageLocation,
                    ),
                  if (item.type == InventoryType.filament &&
                      (item.filamentStatus == FilamentStatus.ready ||
                          item.filamentStatus == FilamentStatus.deployed))
                    _DetailSection(
                      icon: Icons.history_rounded,
                      title: 'Time since dried',
                      text: _timeSinceDried(item.lastDriedAt),
                    ),
                  if (item.type == InventoryType.filament)
                    _DetailSection(
                      icon: Icons.hourglass_bottom_rounded,
                      title: 'Moisture lifespan',
                      text: item.moistureLifespanMinutes == null
                          ? 'Not configured — edit this filament to start the countdown'
                          : _moistureLifespanLabel(item),
                    ),
                  if (item.type == InventoryType.filament &&
                      (item.filamentStatus == FilamentStatus.ready ||
                          item.filamentStatus == FilamentStatus.deployed))
                    _DetailSection(
                      icon: Icons.water_drop_outlined,
                      title: 'Moisture life remaining',
                      text: _moistureRemainingLabel(item),
                    ),
                  if (item.type == InventoryType.filament &&
                      item.filamentStatus == FilamentStatus.drying)
                    _DetailSection(
                      icon: Icons.timer_outlined,
                      title: 'Drying time remaining',
                      text: '${dryingMinutesRemaining(item)} minutes',
                    ),
                  if (item.type.supportsPrinting)
                    _DetailSection(
                      icon: Icons.print_outlined,
                      title: 'Printing instructions',
                      text: item.printingInstructions,
                    ),
                  if (item.type == InventoryType.filament) ...[
                    Row(
                      children: [
                        const Text(
                          'Drying profile',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        SegmentedButton<bool>(
                          key: const Key('temperature-unit-toggle'),
                          segments: const [
                            ButtonSegment(value: false, label: Text('°C')),
                            ButtonSegment(value: true, label: Text('°F')),
                          ],
                          selected: {useFahrenheit},
                          showSelectedIcon: false,
                          onSelectionChanged: (selection) =>
                              setState(() => useFahrenheit = selection.first),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _DetailSection(
                      icon: Icons.thermostat_rounded,
                      title: 'Drying temperature',
                      text: dryingSettings.temperatureC == null
                          ? 'Not configured'
                          : _dryingTemperatureLabel(
                              dryingSettings.temperatureC!,
                              useFahrenheit,
                            ),
                    ),
                    _DetailSection(
                      icon: Icons.timer_outlined,
                      title: 'Drying duration',
                      text: dryingDuration == null
                          ? 'Not configured'
                          : _dryingDurationLabel(dryingDuration),
                    ),
                  ],
                  if (item.type == InventoryType.custom)
                    for (final field in item.customFieldValues.entries)
                      _DetailSection(
                        icon: Icons.tune_rounded,
                        title: field.key,
                        text: field.value.isEmpty
                            ? 'Not configured'
                            : field.value,
                      ),
                  _DetailSection(
                    icon: Icons.inventory_2_outlined,
                    title: 'Storage',
                    text: item.storageInstructions,
                  ),
                  if (widget.canArchive) ...[
                    const Divider(height: 40),
                    const Text(
                      'Inventory lifecycle',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Retired items remain in Archived so their QR code, history, and salvage potential are preserved.',
                      style: const TextStyle(
                        color: Color(0xff929aac),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (item.archived) ...[
                      _ArchiveBadge(item: item),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const Key('restore-item'),
                        onPressed: () => _setArchiveDisposition(null),
                        icon: const Icon(Icons.unarchive_outlined),
                        label: const Text('Restore to inventory'),
                      ),
                    ] else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton.icon(
                            key: const Key('mark-depleted'),
                            onPressed: () => _setArchiveDisposition(
                              ArchiveDisposition.depleted,
                            ),
                            icon: const Icon(Icons.hourglass_empty_rounded),
                            label: const Text('Mark depleted'),
                          ),
                          OutlinedButton.icon(
                            key: const Key('mark-destroyed'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xffff6b6b),
                            ),
                            onPressed: () => _setArchiveDisposition(
                              ArchiveDisposition.destroyed,
                            ),
                            icon: const Icon(Icons.broken_image_outlined),
                            label: const Text('Mark destroyed'),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setDeployed(bool selected) {
    _commit(
      item.copyWith(
        deployed: selected,
        dryingRemaining: selected ? 0 : item.dryingRemaining,
      ),
    );
  }

  Widget _statusChip(
    FilamentStatus status,
    String label,
    IconData icon,
    Color color,
  ) => FilterChip(
    key: Key('status-${status.name}'),
    avatar: Icon(icon, size: 18),
    label: Text(label),
    selected: item.filamentStatus == status,
    selectedColor: color.withValues(alpha: .28),
    onSelected: widget.canEdit ? (_) => _setFilamentStatus(status) : null,
  );

  void _setFilamentStatus(FilamentStatus status) {
    final duration = item.dryingMinutes;
    if (status == FilamentStatus.drying &&
        (duration == null || duration <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a drying duration in Edit before starting.'),
        ),
      );
      return;
    }
    _commit(
      item.copyWith(
        filamentStatus: status,
        deployed: status == FilamentStatus.deployed,
        dryingRemaining: status == FilamentStatus.drying ? duration : 0,
        dryingStartedAt: status == FilamentStatus.drying
            ? DateTime.now()
            : item.dryingStartedAt,
        lastDriedAt:
            status == FilamentStatus.ready &&
                item.filamentStatus == FilamentStatus.drying
            ? DateTime.now()
            : item.lastDriedAt,
      ),
    );
  }

  void _commit(InventoryItem updated) {
    setState(() => item = updated);
    widget.onChanged(updated);
  }

  void _setArchiveDisposition(ArchiveDisposition? disposition) {
    _commit(
      item.copyWith(
        archived: disposition != null,
        archiveDisposition: disposition ?? ArchiveDisposition.archived,
        deployed: disposition == null ? item.deployed : false,
      ),
    );
    Navigator.pop(context);
  }
}

String _effectiveDryingInstructions(InventoryItem item) {
  if (item.dryingInstructions.trim().isNotEmpty) {
    return item.dryingInstructions.trim();
  }
  return detectFilamentTemplate(
        '${item.name}\n${item.brand}\n${item.printingInstructions}',
      )?.drying ??
      '';
}

String _dryingTemperatureLabel(int celsius, bool useFahrenheit) {
  if (!useFahrenheit) return '$celsius°C';
  return '${((celsius * 9 / 5) + 32).round()}°F';
}

String _dryingDurationLabel(int minutes) {
  if (minutes < 60) return '$minutes minutes';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours hours' : '$hours h $remainder min';
}

String _timeSinceDried(DateTime? lastDriedAt) {
  if (lastDriedAt == null) return 'Never recorded';
  final elapsed = DateTime.now().difference(lastDriedAt);
  if (elapsed.inDays > 0) return '${elapsed.inDays} days';
  if (elapsed.inHours > 0) return '${elapsed.inHours} hours';
  return '${elapsed.inMinutes} minutes';
}

Duration _dryingTimeRemaining(InventoryItem item, {DateTime? now}) {
  final baselineMinutes = item.dryingRemaining ?? item.dryingMinutes ?? 0;
  final startedAt = item.dryingStartedAt;
  if (startedAt == null) return Duration(minutes: baselineMinutes);
  final remaining =
      Duration(minutes: baselineMinutes) -
      (now ?? DateTime.now()).difference(startedAt);
  return remaining.isNegative ? Duration.zero : remaining;
}

int dryingMinutesRemaining(InventoryItem item, {DateTime? now}) {
  final remaining = _dryingTimeRemaining(item, now: now);
  if (remaining <= Duration.zero) return 0;
  return (remaining.inSeconds / 60).ceil();
}

int? _minutesFromAmount(double? amount, MoistureTimeUnit unit) {
  if (amount == null) return null;
  return (amount * (unit == MoistureTimeUnit.days ? 1440 : 60)).round();
}

double? _durationAmount(int? minutes, MoistureTimeUnit unit) {
  if (minutes == null) return null;
  return minutes / (unit == MoistureTimeUnit.days ? 1440 : 60);
}

String? _formatDurationAmount(int? minutes, MoistureTimeUnit unit) {
  final amount = _durationAmount(minutes, unit);
  if (amount == null) return null;
  return amount == amount.roundToDouble()
      ? amount.toInt().toString()
      : amount.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}

String _moistureLifespanLabel(InventoryItem item) {
  final amount = _formatDurationAmount(
    item.moistureLifespanMinutes,
    item.moistureTimeUnit,
  );
  return '$amount ${item.moistureTimeUnit.name}';
}

Duration? _moistureRemaining(InventoryItem item, {DateTime? now}) {
  final lifespan = item.moistureLifespanMinutes;
  final lastDried = item.lastDriedAt;
  if (lifespan == null || lifespan <= 0 || lastDried == null) return null;
  return Duration(minutes: lifespan) -
      (now ?? DateTime.now()).difference(lastDried);
}

int compareMoistureRemaining(
  InventoryItem left,
  InventoryItem right, {
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final leftRemaining = left.type == InventoryType.filament
      ? _moistureRemaining(left, now: reference)
      : null;
  final rightRemaining = right.type == InventoryType.filament
      ? _moistureRemaining(right, now: reference)
      : null;
  if (leftRemaining == null && rightRemaining == null) {
    return left.name.compareTo(right.name);
  }
  if (leftRemaining == null) return 1;
  if (rightRemaining == null) return -1;
  final remainingOrder = leftRemaining.compareTo(rightRemaining);
  return remainingOrder != 0 ? remainingOrder : left.name.compareTo(right.name);
}

String _moistureRemainingLabel(InventoryItem item, {DateTime? now}) {
  final remaining = _moistureRemaining(item, now: now);
  if (remaining == null) return 'Dry date not recorded';
  if (remaining <= Duration.zero) {
    final overdueHours = -remaining.inHours;
    if (overdueHours < 24) return 'Needs Drying';
    return '${(overdueHours / 24).ceil()} days past moisture limit';
  }
  if (remaining.inHours < 24) return '${remaining.inHours + 1} hours remaining';
  return '${(remaining.inHours / 24).ceil()} days remaining';
}

String _moistureRingText(Duration remaining) {
  if (remaining <= Duration.zero) return 'WET';
  if (remaining.inHours < 24) return '${remaining.inHours + 1}H';
  return '${(remaining.inHours / 24).ceil()}D';
}

double moistureLifeProgress(InventoryItem item, {DateTime? now}) {
  final remaining = _moistureRemaining(item, now: now);
  final lifespan = item.moistureLifespanMinutes;
  if (remaining == null || lifespan == null || lifespan <= 0) return 1;
  return (remaining.inSeconds / Duration(minutes: lifespan).inSeconds).clamp(
    0.0,
    1.0,
  );
}

String qrDownloadFileName(InventoryItem item) {
  final safeName = item.name
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return '${safeName.isEmpty ? 'Inventory-Item' : safeName}_${item.id}_QR.png';
}

Future<void> _downloadQr(BuildContext context, InventoryItem item) async {
  const width = 1200.0;
  const height = 1400.0;
  const qrSize = 1040.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);
  canvas.save();
  canvas.translate(80, 80);
  QrPainter(
    data: 'inventorinator:item:${item.id}',
    version: QrVersions.auto,
    gapless: true,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Colors.black,
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Colors.black,
    ),
  ).paint(canvas, const Size.square(qrSize));
  canvas.restore();
  final title = TextPainter(
    text: TextSpan(
      text: item.name,
      style: const TextStyle(
        color: Colors.black,
        fontSize: 54,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: 1040);
  title.paint(canvas, Offset((width - title.width) / 2, 1160));
  final id = TextPainter(
    text: TextSpan(
      text: item.id,
      style: const TextStyle(
        color: Color(0xff333333),
        fontSize: 34,
        fontFamily: 'monospace',
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 1040);
  id.paint(canvas, Offset((width - id.width) / 2, 1240));
  final image = await recorder.endRecording().toImage(
    width.toInt(),
    height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null || !context.mounted) return;
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Save QR for ${item.name}',
    fileName: qrDownloadFileName(item),
    bytes: data.buffer.asUint8List(),
    mimeType: 'image/png',
  );
  if (uri != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ${qrDownloadFileName(item)}')),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xff8e75ff)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(
                text.isEmpty ? 'No instructions recorded.' : text,
                style: const TextStyle(color: Color(0xffa2a9b9), height: 1.45),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ProductSourceSection extends StatelessWidget {
  const _ProductSourceSection({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.link_rounded, color: Color(0xff8e75ff)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Product source',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              InkWell(
                key: const Key('open-product-source'),
                onTap: () {
                  final uri = Uri.tryParse(url);
                  if (uri != null) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Text(
                  url,
                  style: const TextStyle(
                    color: Color(0xff8e75ff),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ItemContextRegion extends StatelessWidget {
  const ItemContextRegion({
    super.key,
    required this.item,
    required this.onAction,
    this.spoolSizeLabel = '',
    this.canEdit = true,
    this.canCreate = true,
    this.canArchive = true,
    this.canDelete = true,
    required this.child,
  });
  final InventoryItem item;
  final ValueChanged<ItemAction> onAction;
  final String spoolSizeLabel;
  final bool canEdit;
  final bool canCreate;
  final bool canArchive;
  final bool canDelete;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onSecondaryTapDown: (details) =>
        _showActions(context, details.globalPosition),
    onLongPressStart: (details) =>
        _showActions(context, details.globalPosition),
    child: child,
  );

  Future<void> _showActions(BuildContext context, Offset position) async {
    final action = await showMenu<ItemAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        if (canEdit)
          const PopupMenuItem(
            value: ItemAction.resetDryTimer,
            child: ListTile(
              leading: Icon(Icons.restart_alt_rounded),
              title: Text('Reset dry timer'),
            ),
          ),
        if (canEdit)
          const PopupMenuItem(
            value: ItemAction.edit,
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('Edit'),
            ),
          ),
        if (canCreate)
          const PopupMenuItem(
            value: ItemAction.duplicate,
            child: ListTile(
              leading: Icon(Icons.copy_rounded),
              title: Text('Duplicate'),
            ),
          ),
        if (canArchive)
          PopupMenuItem(
            value: ItemAction.archive,
            child: ListTile(
              leading: Icon(
                item.archived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
              title: Text(item.archived ? 'Restore' : 'Archive'),
            ),
          ),
        if (canDelete) const PopupMenuDivider(),
        if (canDelete)
          const PopupMenuItem(
            value: ItemAction.delete,
            child: ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ),
      ],
    );
    if (action != null) onAction(action);
  }
}

class _QuantityBadge extends StatelessWidget {
  const _QuantityBadge({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final lowStock = _isLowStock(item);
    final accent = lowStock ? const Color(0xffffa552) : item.color;
    return Container(
      key: Key('item-quantity-${item.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: lowStock ? .22 : .14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: .65)),
        boxShadow: lowStock
            ? [BoxShadow(color: accent.withValues(alpha: .2), blurRadius: 14)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lowStock) ...[
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xffffa552),
              size: 17,
            ),
            const SizedBox(width: 5),
          ],
          Text(
            '×${_formatBomQuantity(item.quantity)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (lowStock) ...[
            const SizedBox(width: 6),
            const Text(
              'LOW',
              style: TextStyle(
                color: Color(0xffffa552),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

bool _isLowStock(InventoryItem item) =>
    !item.archived &&
    item.quantityAlertThreshold != null &&
    item.quantity <= item.quantityAlertThreshold!;

Set<String> remoteQuantityChangedItemIds(
  Iterable<InventoryItem> current,
  Iterable<InventoryItem> incoming,
) {
  final currentById = {for (final item in current) item.id: item};
  return incoming
      .where(
        (item) =>
            currentById.containsKey(item.id) &&
            currentById[item.id]!.quantity != item.quantity,
      )
      .map((item) => item.id)
      .toSet();
}

Set<String> lowStockEnteredItemIds(
  Iterable<InventoryItem> current,
  Iterable<InventoryItem> incoming,
) {
  final currentById = {for (final item in current) item.id: item};
  return incoming
      .where(
        (item) =>
            currentById.containsKey(item.id) &&
            !_isLowStock(currentById[item.id]!) &&
            _isLowStock(item),
      )
      .map((item) => item.id)
      .toSet();
}

Duration _scaledAnimationDuration(int milliseconds, int percent) => Duration(
  milliseconds: (milliseconds * percent.clamp(25, 200) / 100).round(),
);

bool _isEffectWidgetVisible(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.attached) return false;
  final origin = renderObject.localToGlobal(Offset.zero);
  final bounds = origin & renderObject.size;
  return bounds.overlaps(Offset.zero & MediaQuery.sizeOf(context));
}

bool _hasMoistureVisualAlert(InventoryItem item, {DateTime? now}) {
  if (item.archived ||
      item.type != InventoryType.filament ||
      item.filamentStatus == FilamentStatus.drying) {
    return false;
  }
  final remaining = _moistureRemaining(item, now: now);
  if (remaining == null) return false;
  if (remaining <= Duration.zero) return true;
  return item.moistureAlertEnabled &&
      item.moistureAlertThresholdMinutes != null &&
      remaining <= Duration(minutes: item.moistureAlertThresholdMinutes!);
}

class RemoteQuantityChangeEffect extends StatefulWidget {
  const RemoteQuantityChangeEffect({
    super.key,
    required this.itemId,
    required this.trigger,
    required this.durationPercent,
    required this.child,
  });
  final String itemId;
  final int trigger;
  final int durationPercent;
  final Widget child;

  @override
  State<RemoteQuantityChangeEffect> createState() =>
      _RemoteQuantityChangeEffectState();
}

class _RemoteQuantityChangeEffectState extends State<RemoteQuantityChangeEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: _scaledAnimationDuration(1700, widget.durationPercent),
  );

  @override
  void didUpdateWidget(covariant RemoteQuantityChangeEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.durationPercent != oldWidget.durationPercent) {
      controller.duration = _scaledAnimationDuration(
        1700,
        widget.durationPercent,
      );
    }
    if (widget.trigger > 0 && widget.trigger != oldWidget.trigger) {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        final travel = Curves.easeInOutCubic.transform(controller.value);
        final opacity = controller.value < .22
            ? controller.value / .22
            : (1 - controller.value) / .78;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: (.24 * opacity).clamp(0, 1),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-1.8 + travel, -1.8 + travel),
                        end: Alignment(.2 + travel, .2 + travel),
                        colors: const [
                          Color(0xff7455ff),
                          Color(0xff45d2bd),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: (.48 * opacity).clamp(0, 1),
                  child: Align(
                    alignment: Alignment(
                      -1.45 + (2.9 * travel),
                      -1.45 + (2.9 * travel),
                    ),
                    child: Transform.scale(
                      scale: .72 + (.28 * travel),
                      child: Icon(
                        Icons.south_east_rounded,
                        key: Key('remote-quantity-arrow-${widget.itemId}'),
                        size: 108,
                        color: Colors.white,
                        shadows: const [
                          Shadow(color: Color(0xff45d2bd), blurRadius: 22),
                          Shadow(color: Color(0xff7455ff), blurRadius: 34),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            child!,
          ],
        );
      },
    ),
  );
}

class LowStockPulseEffect extends StatefulWidget {
  const LowStockPulseEffect({
    super.key,
    required this.itemId,
    required this.trigger,
    required this.active,
    required this.durationPercent,
    required this.recurrenceSeconds,
    required this.child,
  });
  final String itemId;
  final int trigger;
  final bool active;
  final int durationPercent;
  final int recurrenceSeconds;
  final Widget child;

  @override
  State<LowStockPulseEffect> createState() => _LowStockPulseEffectState();
}

class _LowStockPulseEffectState extends State<LowStockPulseEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: _scaledAnimationDuration(1450, widget.durationPercent),
  );
  Timer? visibilityTimer;
  Timer? recurrenceTimer;
  bool wasVisible = false;

  @override
  void initState() {
    super.initState();
    if (widget.trigger > 0) controller.forward(from: 0);
    _restartVisibilityTimer();
  }

  @override
  void didUpdateWidget(covariant LowStockPulseEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.durationPercent != oldWidget.durationPercent) {
      controller.duration = _scaledAnimationDuration(
        1450,
        widget.durationPercent,
      );
    }
    if (widget.active != oldWidget.active ||
        widget.recurrenceSeconds != oldWidget.recurrenceSeconds) {
      _restartVisibilityTimer();
    }
    if (widget.trigger > 0 && widget.trigger != oldWidget.trigger) {
      controller.forward(from: 0);
    }
  }

  void _restartVisibilityTimer() {
    visibilityTimer?.cancel();
    recurrenceTimer?.cancel();
    wasVisible = false;
    if (!widget.active) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
    visibilityTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _checkVisibility(),
    );
    if (widget.recurrenceSeconds > 0) {
      recurrenceTimer = Timer.periodic(
        Duration(seconds: widget.recurrenceSeconds),
        (_) => _playIfVisible(),
      );
    }
  }

  void _checkVisibility() {
    if (!mounted || !widget.active) return;
    final visible = _isEffectWidgetVisible(context);
    if (visible && !wasVisible && !controller.isAnimating) {
      controller.forward(from: 0);
    }
    wasVisible = visible;
  }

  void _playIfVisible() {
    if (mounted &&
        widget.active &&
        _isEffectWidgetVisible(context) &&
        !controller.isAnimating) {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    visibilityTimer?.cancel();
    recurrenceTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        final pulse = controller.value < .35
            ? controller.value / .35
            : (1 - controller.value) / .65;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: (.34 * pulse).clamp(0, 1),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [Color(0xffffc857), Color(0xffff8a3d)],
                        radius: 1.15,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: (.52 * pulse).clamp(0, 1),
                  child: Transform.scale(
                    scale: .72 + (.42 * pulse),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      key: Key('low-stock-pulse-${widget.itemId}'),
                      size: 112,
                      color: Colors.white,
                      shadows: const [
                        Shadow(color: Color(0xffffc857), blurRadius: 30),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            child!,
          ],
        );
      },
    ),
  );
}

class MoistureDropletWaveEffect extends StatefulWidget {
  const MoistureDropletWaveEffect({
    super.key,
    required this.itemId,
    required this.trigger,
    required this.active,
    required this.durationPercent,
    required this.recurrenceSeconds,
    required this.child,
  });
  final String itemId;
  final int trigger;
  final bool active;
  final int durationPercent;
  final int recurrenceSeconds;
  final Widget child;

  @override
  State<MoistureDropletWaveEffect> createState() =>
      _MoistureDropletWaveEffectState();
}

class _MoistureDropletWaveEffectState extends State<MoistureDropletWaveEffect>
    with SingleTickerProviderStateMixin {
  static const horizontalPositions = [-.72, -.2, .38, .76, -.48, .08, .58];
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: _scaledAnimationDuration(2300, widget.durationPercent),
  );
  Timer? visibilityTimer;
  Timer? recurrenceTimer;
  bool wasVisible = false;

  @override
  void initState() {
    super.initState();
    if (widget.trigger > 0) controller.forward(from: 0);
    _restartVisibilityTimer();
  }

  @override
  void didUpdateWidget(covariant MoistureDropletWaveEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.durationPercent != oldWidget.durationPercent) {
      controller.duration = _scaledAnimationDuration(
        2300,
        widget.durationPercent,
      );
    }
    if (widget.active != oldWidget.active ||
        widget.recurrenceSeconds != oldWidget.recurrenceSeconds) {
      _restartVisibilityTimer();
    }
    if (widget.trigger > 0 && widget.trigger != oldWidget.trigger) {
      controller.forward(from: 0);
    }
  }

  void _restartVisibilityTimer() {
    visibilityTimer?.cancel();
    recurrenceTimer?.cancel();
    wasVisible = false;
    if (!widget.active) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
    visibilityTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _checkVisibility(),
    );
    if (widget.recurrenceSeconds > 0) {
      recurrenceTimer = Timer.periodic(
        Duration(seconds: widget.recurrenceSeconds),
        (_) => _playIfVisible(),
      );
    }
  }

  void _checkVisibility() {
    if (!mounted || !widget.active) return;
    final visible = _isEffectWidgetVisible(context);
    if (visible && !wasVisible && !controller.isAnimating) {
      controller.forward(from: 0);
    }
    wasVisible = visible;
  }

  void _playIfVisible() {
    if (mounted &&
        widget.active &&
        _isEffectWidgetVisible(context) &&
        !controller.isAnimating) {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    visibilityTimer?.cancel();
    recurrenceTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        final wash = controller.value < .3
            ? controller.value / .3
            : (1 - controller.value) / .7;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: (.2 * wash).clamp(0, 1),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xff55a8ff), Color(0xff45d2bd)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            for (var index = 0; index < horizontalPositions.length; index++)
              _droplet(index),
            child!,
          ],
        );
      },
    ),
  );

  Widget _droplet(int index) {
    final phase = ((controller.value * 1.65) - (index * .11)).clamp(0.0, 1.0);
    final visibility = phase < .22 ? phase / .22 : (1 - phase) / .78;
    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: (.72 * visibility).clamp(0, 1),
          child: Align(
            alignment: Alignment(
              horizontalPositions[index],
              -1.35 + (2.7 * Curves.easeIn.transform(phase)),
            ),
            child: Icon(
              Icons.water_drop_rounded,
              key: index == 0 ? Key('moisture-wave-${widget.itemId}') : null,
              size: 22 + ((index % 3) * 8),
              color: index.isEven
                  ? const Color(0xff78c7ff)
                  : const Color(0xff45d2bd),
              shadows: const [Shadow(color: Color(0xff55a8ff), blurRadius: 18)],
            ),
          ),
        ),
      ),
    );
  }
}

class ItemCardEffects extends StatelessWidget {
  const ItemCardEffects({
    super.key,
    required this.itemId,
    required this.quantitySyncVersion,
    required this.lowStockVersion,
    required this.moistureVersion,
    required this.lowStockActive,
    required this.moistureActive,
    required this.durationPercent,
    required this.recurrenceSeconds,
    required this.child,
  });
  final String itemId;
  final int quantitySyncVersion;
  final int lowStockVersion;
  final int moistureVersion;
  final bool lowStockActive;
  final bool moistureActive;
  final int durationPercent;
  final int recurrenceSeconds;
  final Widget child;

  @override
  Widget build(BuildContext context) => MoistureDropletWaveEffect(
    itemId: itemId,
    trigger: moistureVersion,
    active: moistureActive,
    durationPercent: durationPercent,
    recurrenceSeconds: recurrenceSeconds,
    child: LowStockPulseEffect(
      itemId: itemId,
      trigger: lowStockVersion,
      active: lowStockActive,
      durationPercent: durationPercent,
      recurrenceSeconds: recurrenceSeconds,
      child: RemoteQuantityChangeEffect(
        itemId: itemId,
        trigger: quantitySyncVersion,
        durationPercent: durationPercent,
        child: child,
      ),
    ),
  );
}

class InventoryCard extends StatelessWidget {
  const InventoryCard({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onAction,
    this.spoolSizeLabel = '',
    this.quantitySyncVersion = 0,
    this.lowStockAnimationVersion = 0,
    this.moistureAnimationVersion = 0,
    this.animationDurationPercent = 100,
    this.animationRecurrenceSeconds = 5,
    this.canEdit = true,
    this.canCreate = true,
    this.canArchive = true,
    this.canDelete = true,
  });
  final InventoryItem item;
  final VoidCallback onOpen;
  final ValueChanged<ItemAction> onAction;
  final String spoolSizeLabel;
  final int quantitySyncVersion;
  final int lowStockAnimationVersion;
  final int moistureAnimationVersion;
  final int animationDurationPercent;
  final int animationRecurrenceSeconds;
  final bool canEdit;
  final bool canCreate;
  final bool canArchive;
  final bool canDelete;
  @override
  Widget build(BuildContext context) => ItemContextRegion(
    item: item,
    onAction: onAction,
    canEdit: canEdit,
    canCreate: canCreate,
    canArchive: canArchive,
    canDelete: canDelete,
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: ItemCardEffects(
          itemId: item.id,
          quantitySyncVersion: quantitySyncVersion,
          lowStockVersion: lowStockAnimationVersion,
          moistureVersion: moistureAnimationVersion,
          lowStockActive: !item.archived && _isLowStock(item),
          moistureActive: _hasMoistureVisualAlert(item),
          durationPercent: animationDurationPercent,
          recurrenceSeconds: animationRecurrenceSeconds,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _QuantityBadge(item: item),
                    const Spacer(),
                    if (item.archived)
                      _ArchiveBadge(item: item)
                    else
                      CountdownRing(item: item),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.typeLabel.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: item.color,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '\$${item.cost.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    if (spoolSizeLabel.isNotEmpty) spoolSizeLabel,
                    ...item.compatibility,
                  ].join('  •  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff929aac),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _ItemVisual(item: item, size: 38),
                    const Spacer(),
                    Text(
                      _age(item.added),
                      style: const TextStyle(
                        color: Color(0xff7f8798),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class InventoryRow extends StatelessWidget {
  const InventoryRow({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onAction,
    this.spoolSizeLabel = '',
    this.quantitySyncVersion = 0,
    this.lowStockAnimationVersion = 0,
    this.moistureAnimationVersion = 0,
    this.animationDurationPercent = 100,
    this.animationRecurrenceSeconds = 5,
    this.canEdit = true,
    this.canCreate = true,
    this.canArchive = true,
    this.canDelete = true,
  });
  final InventoryItem item;
  final VoidCallback onOpen;
  final ValueChanged<ItemAction> onAction;
  final String spoolSizeLabel;
  final int quantitySyncVersion;
  final int lowStockAnimationVersion;
  final int moistureAnimationVersion;
  final int animationDurationPercent;
  final int animationRecurrenceSeconds;
  final bool canEdit;
  final bool canCreate;
  final bool canArchive;
  final bool canDelete;
  @override
  Widget build(BuildContext context) => ItemContextRegion(
    item: item,
    onAction: onAction,
    canEdit: canEdit,
    canCreate: canCreate,
    canArchive: canArchive,
    canDelete: canDelete,
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onOpen,
        child: ItemCardEffects(
          itemId: item.id,
          quantitySyncVersion: quantitySyncVersion,
          lowStockVersion: lowStockAnimationVersion,
          moistureVersion: moistureAnimationVersion,
          lowStockActive: !item.archived && _isLowStock(item),
          moistureActive: _hasMoistureVisualAlert(item),
          durationPercent: animationDurationPercent,
          recurrenceSeconds: animationRecurrenceSeconds,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 86),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _ItemVisual(item: item, size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          [
                            item.typeLabel,
                            if (spoolSizeLabel.isNotEmpty) spoolSizeLabel,
                            ...item.compatibility,
                          ].join('  •  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff929aac),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _QuantityBadge(item: item),
                  const SizedBox(width: 12),
                  if (item.archived) ...[
                    _ArchiveBadge(item: item),
                    const SizedBox(width: 12),
                  ],
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${item.cost.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _age(item.added),
                        style: const TextStyle(
                          color: Color(0xff7f8798),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  CountdownRing(item: item, compact: true),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class CountdownRing extends StatelessWidget {
  const CountdownRing({super.key, required this.item, this.compact = false});
  final InventoryItem item;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final dryingRemaining = _dryingTimeRemaining(item);
    final remaining = dryingMinutesRemaining(item);
    final total = item.dryingMinutes;
    final filament = item.type == InventoryType.filament;
    final lowStock = _isLowStock(item);
    final moistureRemaining = _moistureRemaining(item);
    final active =
        filament &&
        item.filamentStatus == FilamentStatus.drying &&
        remaining > 0 &&
        total != null &&
        total > 0;
    final deployed = filament
        ? item.filamentStatus == FilamentStatus.deployed
        : item.deployed;
    final queued =
        filament &&
        (item.filamentStatus == FilamentStatus.queuedForDrying ||
            moistureRemaining != null && moistureRemaining <= Duration.zero);
    final moistureAlert =
        !queued &&
        item.moistureAlertEnabled &&
        item.moistureAlertThresholdMinutes != null &&
        moistureRemaining != null &&
        moistureRemaining <=
            Duration(minutes: item.moistureAlertThresholdMinutes!);
    final progress = active
        ? (1 - (dryingRemaining.inSeconds / (total * 60))).clamp(0.0, 1.0)
        : moistureRemaining != null
        ? moistureLifeProgress(item)
        : 1.0;
    final size = compact ? 46.0 : 58.0;
    final statusColor = active
        ? const Color(0xff9c83ff)
        : queued
        ? const Color(0xffffa552)
        : moistureAlert
        ? const Color(0xffffc857)
        : deployed
        ? const Color(0xff55a8ff)
        : lowStock
        ? const Color(0xffffc857)
        : const Color(0xff45d2bd);
    final moistureLabel = _moistureRemainingLabel(item);
    final statusLabel = active
        ? 'Time until dry'
        : queued
        ? 'Wet'
        : deployed
        ? moistureRemaining == null
              ? 'Deployed'
              : 'Deployed · $moistureLabel'
        : lowStock
        ? 'Low stock'
        : moistureRemaining == null
        ? 'Ready'
        : moistureLabel;
    return Semantics(
      label: statusLabel,
      value: active ? '$remaining minutes' : moistureLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: statusLabel,
        child: TweenAnimationBuilder<double>(
          key: ValueKey(
            '${item.id}-${item.filamentStatus.name}-$lowStock-$remaining-${moistureRemaining?.inMinutes}',
          ),
          tween: Tween(begin: 0, end: progress),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          builder: (context, animatedProgress, child) => Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: .22),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.square(
                  dimension: size,
                  child: CircularProgressIndicator(
                    value: animatedProgress,
                    strokeWidth: compact ? 4 : 5,
                    backgroundColor: const Color(0xff292f3d),
                    color: statusColor,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      active
                          ? Icons.water_drop_outlined
                          : queued
                          ? Icons.water_drop_rounded
                          : deployed
                          ? Icons.lock_outline_rounded
                          : lowStock
                          ? Icons.warning_amber_rounded
                          : Icons.check_rounded,
                      size: deployed
                          ? compact
                                ? 18
                                : 21
                          : compact
                          ? 14
                          : 16,
                      color: statusColor,
                    ),
                    if (!compact)
                      Text(
                        active
                            ? '${remaining}m'
                            : queued
                            ? 'WET'
                            : moistureRemaining != null
                            ? _moistureRingText(moistureRemaining)
                            : deployed
                            ? 'DEPLOYED'
                            : lowStock
                            ? 'LOW'
                            : 'READY',
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _age(DateTime added) {
  final days = DateTime(2026, 8, 25).difference(added).inDays;
  if (days < 30) return '${days}d old';
  if (days < 365) return '${days ~/ 30}mo old';
  return '${(days / 365).toStringAsFixed(1)}y old';
}
