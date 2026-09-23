import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/main.dart';

void main() {
  var counter = 0;
  String newId(String prefix) => '$prefix-${++counter}';

  ({List<VendorRecord> vendors, List<BrandRecord> brands}) add({
    List<VendorRecord> vendors = const [],
    List<BrandRecord> brands = const [],
    String vendorName = '',
    String brandName = '',
    InventoryType type = InventoryType.filament,
  }) => withCatalogEntriesForItem(
    vendors: vendors,
    brands: brands,
    vendorName: vendorName,
    brandName: brandName,
    type: type,
    newId: newId,
  );

  setUp(() => counter = 0);

  group('withCatalogEntriesForItem', () {
    test('a new vendor joins the catalog', () {
      final result = add(vendorName: '  Acme Supply ');

      expect(result.vendors.single.name, 'Acme Supply');
      expect(result.vendors.single.isBrand, isFalse);
      expect(result.brands, isEmpty);
    });

    test('a new brand joins the catalog linked to its vendor and type', () {
      final result = add(
        vendorName: 'Acme Supply',
        brandName: 'Zebra Filaments',
        type: InventoryType.filament,
      );

      final vendor = result.vendors.single;
      final brand = result.brands.single;
      expect(brand.name, 'Zebra Filaments');
      expect(brand.vendorIds, {vendor.id});
      expect(brand.categories, {InventoryType.filament});
    });

    test('a brand without a vendor is still added', () {
      final result = add(brandName: 'Zebra Filaments');

      expect(result.vendors, isEmpty);
      expect(result.brands.single.vendorIds, isEmpty);
    });

    test('a vendor that is also the brand is marked as one', () {
      final result = add(vendorName: 'Polymaker', brandName: 'polymaker');

      expect(result.vendors.single.isBrand, isTrue);
      expect(result.brands.single.name, 'polymaker');
      expect(result.brands.single.vendorIds, {result.vendors.single.id});
    });

    test('existing records match loosely, so nothing is duplicated', () {
      const vendor = VendorRecord(id: 'EXISTING-VEN', name: 'Acme Supply');
      final brand = BrandRecord(
        id: 'EXISTING-BR',
        name: 'Zebra Filaments',
        vendorIds: const {'EXISTING-VEN'},
        categories: const {InventoryType.filament},
      );

      final result = add(
        vendors: const [vendor],
        brands: [brand],
        vendorName: 'ACME  supply',
        brandName: 'zebra-filaments',
      );

      expect(result.vendors, hasLength(1));
      expect(result.brands, hasLength(1));
      expect(identical(result.brands.single, brand), isTrue);
    });

    test('an existing brand gains the item vendor and type', () {
      final brand = BrandRecord(
        id: 'EXISTING-BR',
        name: 'Zebra Filaments',
        vendorIds: const {'EXISTING-VEN'},
        categories: const {InventoryType.filament},
      );

      final result = add(
        vendors: const [VendorRecord(id: 'EXISTING-VEN', name: 'Acme Supply')],
        brands: [brand],
        vendorName: 'New Shop',
        brandName: 'Zebra Filaments',
        type: InventoryType.nozzle,
      );

      expect(result.brands.single.id, 'EXISTING-BR');
      expect(result.brands.single.vendorIds, hasLength(2));
      expect(result.brands.single.categories, {
        InventoryType.filament,
        InventoryType.nozzle,
      });
    });

    test('empty names change nothing', () {
      final result = add(vendorName: '  ', brandName: '');

      expect(result.vendors, isEmpty);
      expect(result.brands, isEmpty);
    });

    test('does not modify the lists it was given', () {
      final vendors = <VendorRecord>[];

      add(vendors: vendors, vendorName: 'Acme Supply');

      expect(vendors, isEmpty);
    });
  });

  testWidgets('a brand typed into the item editor joins the catalog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-catalog-entities-',
    );
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      ),
    ))!;
    await tester.pumpWidget(InventorinatorApp(database: database));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // A fresh database starts with onboarding; take the empty local path.
    await tester.tap(find.byKey(const Key('start-empty-inventory')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('getting-started-skip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This device only'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('add-item')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('item-name')), 'Blue PLA');
    await tester.tap(find.byKey(const Key('item-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filament').last);
    await tester.pumpAndSettle();
    // The brand line for a brand that is not in the catalog yet.
    await tester.ensureVisible(find.byKey(const Key('item-custom-brand')));
    await tester.enterText(
      find.byKey(const Key('item-custom-brand')),
      'Zebra Filaments',
    );
    await tester.ensureVisible(find.byKey(const Key('save-item')));
    await tester.tap(find.byKey(const Key('save-item')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => database.waitForPendingWrites());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );

    final saved = decodeWorkshopState(database.loadState())!;
    expect(saved.inventory.map((item) => item.name), ['Blue PLA']);
    final added = saved.brands
        .where((brand) => brand.name == 'Zebra Filaments')
        .toList();
    expect(added, hasLength(1), reason: 'the new brand joins the catalog');
    expect(added.single.categories, {InventoryType.filament});

    await tester.pumpWidget(const SizedBox());
    database.close();
    directory.deleteSync(recursive: true);
  });
}
