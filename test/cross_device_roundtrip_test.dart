import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/main.dart';
import 'package:inventorinator/workshop_merge.dart';

void main() {
  String completeState() => encodeWorkshopState(
    inventory: [
      InventoryItem(
        id: 'INV-FILAMENT',
        name: 'Galaxy PETG',
        type: InventoryType.filament,
        compatibility: const ['FDM', 'MK3S+'],
        added: DateTime.utc(2026, 8, 28),
        cost: 24.99,
        color: Colors.purple,
        quantity: 2,
        quantityAlertThreshold: 1,
        moistureLifespanMinutes: 1440,
        moistureAlertEnabled: true,
        moistureAlertThresholdMinutes: 120,
        printingInstructions: 'Nozzle 235 C',
        dryingInstructions: 'Dry 65 C for 6 hours',
        storageInstructions: 'Seal with desiccant',
        brand: 'Test Brand',
        vendor: 'Test Vendor',
        storageLocation: 'Dry box',
        storageLocationId: 'LOCATION-DRY-BOX',
        imageBytes: Uint8List.fromList(const [1, 2, 3]),
        labelImageBytes: Uint8List.fromList(const [4, 5, 6]),
        compatibleMachineIds: const ['MACHINE-1'],
        spoolTypeId: 'SPOOL-2500G',
        amsCompatible: true,
        spoolTareWeightGrams: 242,
        spoolOuterDiameterMm: 200,
        spoolWidthMm: 68,
        spoolHoleDiameterMm: 55,
        refill: true,
        masterSpool: 'Reusable spool',
        catalogProductId: 'PRODUCT-1',
      ),
      InventoryItem(
        id: 'INV-PART',
        name: 'Fan shroud',
        type: InventoryType.printedPart,
        compatibility: const ['PETG', 'MACHINE-1'],
        added: DateTime.utc(2026, 8, 28),
        cost: 0,
        color: Colors.blue,
        quantity: 0,
      ),
      InventoryItem(
        id: 'INV-SOAP',
        name: 'Lavender soap',
        type: InventoryType.custom,
        compatibility: const [],
        added: DateTime.utc(2026, 8, 28),
        cost: 3,
        color: Colors.pink,
        customTypeId: 'TYPE-SOAP',
        customTypeName: 'Soap batch',
        customFieldValues: const {'Cure time': '28 days'},
      ),
    ],
    vendors: const [VendorRecord(id: 'VENDOR-1', name: 'Test Vendor')],
    brands: const [
      BrandRecord(
        id: 'BRAND-1',
        name: 'Test Brand',
        vendorIds: {'VENDOR-1'},
        categories: {InventoryType.filament},
      ),
    ],
    spoolTypes: const [
      SpoolTypeRecord(id: 'SPOOL-2500G', label: '2.5 kg', weightGrams: 2500),
    ],
    customItemTypes: const [
      CustomItemTypeRecord(
        id: 'TYPE-SOAP',
        name: 'Soap batch',
        contextualFields: ['Cure time'],
      ),
    ],
    typeLabelOverrides: const {
      'item:filament': 'Feedstock',
      'catalog:kits': 'Assemblies',
    },
    products: const [
      CatalogProduct(
        id: 'PRODUCT-1',
        brandId: 'BRAND-1',
        category: InventoryType.filament,
        name: 'Galaxy PETG',
      ),
    ],
    machineTypes: const [
      MachineTypeRecord(id: 'MACHINE-TYPE-1', name: 'FDM printer'),
    ],
    machines: const [
      MachineRecord(
        id: 'MACHINE-1',
        name: 'Icarus',
        model: 'MK3S+',
        address: 'icarus.local',
        typeId: 'MACHINE-TYPE-1',
        kitIds: {'KIT-1'},
      ),
    ],
    kits: const [
      KitRecord(
        id: 'KIT-1',
        name: 'Printer kit',
        sections: ['Extruder'],
        bom: [
          KitBomEntry(
            id: 'KIT-LINE-1',
            productId: 'PRODUCT-1',
            quantity: 1,
            section: 'Extruder',
          ),
        ],
      ),
    ],
    builds: [
      BuildRecord(
        id: 'BUILD-1',
        kitId: 'KIT-1',
        name: 'Shared printer build',
        createdAt: DateTime.utc(2026, 8, 28),
        createdBy: 'Linux desktop',
        ownerDeviceId: 'DEVICE-LINUX',
        ownerUserId: 'USER-OWNER',
        shared: true,
        lines: const [
          BuildLine(
            id: 'BUILD-LINE-1',
            productId: 'PRODUCT-1',
            name: 'Galaxy PETG',
            section: 'Extruder',
            requiredQuantity: 1,
          ),
        ],
      ),
    ],
    locations: const [
      StockLocationRecord(id: 'LOCATION-WORKSHOP', name: 'Workshop'),
      StockLocationRecord(
        id: 'LOCATION-DRY-BOX',
        name: 'Dry box',
        parentId: 'LOCATION-WORKSHOP',
      ),
    ],
    shoppingList: const [
      ShoppingListEntry(
        id: 'SHOP-1',
        name: 'Galaxy PETG',
        productId: 'PRODUCT-1',
        quantityNeeded: 3,
        quantityOrdered: 3,
        kitId: 'KIT-1',
        bomLineId: 'KIT-LINE-1',
        status: ShoppingListStatus.ordered,
      ),
    ],
    auditLog: [
      AuditEntry(
        id: 'AUDIT-1',
        timestamp: DateTime.utc(2026, 8, 28),
        actor: 'Linux desktop',
        action: 'create',
        entityType: 'build',
        entityId: 'BUILD-1',
        changes: const {'shared': 'true'},
      ),
    ],
    additionHistory: [
      AdditionHistoryEntry(
        id: 'ADD-1',
        itemId: 'INV-FILAMENT',
        name: 'Galaxy PETG',
        type: InventoryType.filament,
        addedAt: DateTime.utc(2026, 8, 28),
        deviceName: 'Linux desktop',
      ),
    ],
    historyLimit: 500,
  );

  void expectCompleteState(String source) {
    final restored = decodeWorkshopState(source)!;
    final filament = restored.inventory.firstWhere(
      (item) => item.id == 'INV-FILAMENT',
    );
    final printedPart = restored.inventory.firstWhere(
      (item) => item.id == 'INV-PART',
    );
    final soap = restored.inventory.firstWhere((item) => item.id == 'INV-SOAP');

    expect(restored.typeLabelOverrides['item:filament'], 'Feedstock');
    expect(restored.spoolTypes.single.label, '2.5 kg');
    expect(restored.customItemTypes.single.name, 'Soap batch');
    expect(soap.customFieldValues['Cure time'], '28 days');
    expect(filament.spoolTypeId, 'SPOOL-2500G');
    expect(filament.amsCompatible, isTrue);
    expect(filament.spoolHoleDiameterMm, 55);
    expect(filament.refill, isTrue);
    expect(filament.imageBytes, orderedEquals(const [1, 2, 3]));
    expect(filament.labelImageBytes, orderedEquals(const [4, 5, 6]));
    expect(filament.storageLocationId, 'LOCATION-DRY-BOX');
    expect(printedPart.quantity, 0);
    expect(printedPart.compatibility, contains('PETG'));
    expect(restored.machines.single.kitIds, contains('KIT-1'));
    expect(restored.kits.single.sections, ['Extruder']);
    expect(restored.builds.single.shared, isTrue);
    expect(restored.builds.single.ownerUserId, 'USER-OWNER');
    expect(restored.locations.last.parentId, 'LOCATION-WORKSHOP');
    expect(restored.shoppingList.single.status, ShoppingListStatus.ordered);
    expect(restored.auditLog.single.entityId, 'BUILD-1');
    expect(restored.additionHistory.single.deviceName, 'Linux desktop');
    expect(restored.historyLimit, 500);
  }

  test('complete workshop document survives encode and decode', () {
    expectCompleteState(completeState());
  });

  test('two devices merge disjoint new-feature edits without data loss', () {
    final base = jsonDecode(completeState()) as Map<String, dynamic>;
    final linux = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
    final android = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;

    (linux['typeLabelOverrides'] as Map<String, dynamic>)['item:filament'] =
        'Polymer';
    (linux['spoolTypes'] as List).add({
      'id': 'SPOOL-10000G',
      'label': '10 kg',
      'weightGrams': 10000,
    });
    ((android['inventory'] as List).first as Map<String, dynamic>)['quantity'] =
        3;
    (android['customItemTypes'] as List).add({
      'id': 'TYPE-ICE-CREAM',
      'name': 'Ice cream batch',
      'contextualFields': ['Freeze time'],
    });

    final merged = mergeWorkshopStates(
      jsonEncode(base),
      jsonEncode(linux),
      jsonEncode(android),
    );
    final restored = decodeWorkshopState(merged)!;

    expect(restored.typeLabelOverrides['item:filament'], 'Polymer');
    expect(restored.spoolTypes.map((spool) => spool.label), contains('10 kg'));
    expect(restored.inventory.first.quantity, 3);
    expect(
      restored.customItemTypes.map((type) => type.name),
      contains('Ice cream batch'),
    );
    expect(restored.builds.single.name, 'Shared printer build');
    expect(restored.kits.single.sections, ['Extruder']);
  });

  test('portable SQLite export restores the complete workshop', () async {
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-cross-device-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final linux = await LocalDatabase.open(
      overridePath: '${directory.path}/linux.sqlite3',
    );
    final android = await LocalDatabase.open(
      overridePath: '${directory.path}/android.sqlite3',
    );
    addTearDown(linux.close);
    addTearDown(android.close);

    linux.saveState(completeState());
    final portable = await linux.exportPortableDatabase();
    final imported = await android.importPortableDatabase(portable);

    expectCompleteState(imported);
    expectCompleteState(android.loadState()!);
  });
}
