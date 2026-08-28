import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;
import 'package:image/image.dart' as img;
import 'package:inventorinator/main.dart';
import 'package:inventorinator/cloud_sync_dialog.dart';
import 'package:inventorinator/label_ocr.dart';
import 'package:inventorinator/qr_scanner.dart';
import 'package:inventorinator/supabase_sync.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('pairing code dialog lays out its QR code', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PairingCodeDialog(
            payload: 'inventorinator:pair:test-payload',
            code: 'ABCDEF123456',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('ABCDEF123456'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new item history exposes retention choices', (tester) async {
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.byKey(const Key('addition-history')));
    await tester.pumpAndSettle();

    expect(find.text('New items'), findsWidgets);
    expect(find.byKey(const Key('history-limit')), findsOneWidget);
    expect(find.byKey(const Key('sync-chime-toggle')), findsOneWidget);
    expect(find.byKey(const Key('rename-device')), findsOneWidget);
    await tester.tap(find.byKey(const Key('history-limit')));
    await tester.pumpAndSettle();
    expect(find.text('20'), findsOneWidget);
    expect(find.text('2000'), findsOneWidget);
  });

  testWidgets('alerts expose separate per-device chime controls', (
    tester,
  ) async {
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.byKey(const Key('moisture-alerts')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('drying-complete-chime-toggle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('moisture-alert-chime-toggle')),
      findsOneWidget,
    );
  });

  testWidgets('scanner accepts a QR payload and opens its item', (
    tester,
  ) async {
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.byKey(const Key('open-scanner')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('manual-qr-code')),
      'inventorinator:item:INV-FIL-0001',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('INV-FIL-0001'), findsOneWidget);
    expect(find.byKey(const Key('download-qr')), findsOneWidget);
  });

  testWidgets('ingest scan opens Add Item with the product barcode', (
    tester,
  ) async {
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.byKey(const Key('open-scanner')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ingest'));
    await tester.pumpAndSettle();
    final captureMode = find.byKey(const Key('scan-capture-mode'));
    expect(captureMode, findsOneWidget);
    expect(find.byKey(const Key('capture-label-photo')), findsNothing);
    await tester.tap(find.text('OCR'));
    await tester.pump();
    expect(
      tester.widget<SegmentedButton<ScanCaptureMode>>(captureMode).selected,
      {ScanCaptureMode.ocr},
    );
    await tester.tap(find.text('Barcode'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('manual-qr-code')),
      '618996738298',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Add an item'), findsOneWidget);
    expect(find.byKey(const Key('search-product-web')), findsOneWidget);
    expect(find.byKey(const Key('search-provider')), findsOneWidget);
    expect(find.byKey(const Key('product-page-url')), findsOneWidget);
    expect(find.byKey(const Key('import-product-page')), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<InventoryType>>(
            find.byKey(const Key('item-type')),
          )
          .initialValue,
      InventoryType.other,
    );
    await tester.ensureVisible(find.byKey(const Key('search-provider')));
    await tester.tap(find.byKey(const Key('search-provider')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('custom-search-url')), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('item-barcode')))
          .controller!
          .text,
      '618996738298',
    );
    await tester.enterText(
      find.byKey(const Key('item-name')),
      'Purple Silk PLA',
    );
    await tester.ensureVisible(find.byKey(const Key('item-type')));
    await tester.tap(find.byKey(const Key('item-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filament').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drying-remaining')), findsNothing);
    expect(find.byKey(const Key('moisture-lifespan')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('moisture-lifespan')), '10');
    await tester.ensureVisible(find.byKey(const Key('moisture-time-unit')));
    await tester.tap(find.text('Hours'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('moisture-lifespan')))
          .controller!
          .text,
      '240',
    );
    await tester.tap(find.text('Days'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('moisture-lifespan')))
          .controller!
          .text,
      '10',
    );
    await tester.ensureVisible(find.byKey(const Key('moisture-alert-toggle')));
    await tester.tap(find.byKey(const Key('moisture-alert-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('moisture-alert-threshold')),
      '9',
    );
    await tester.enterText(find.byKey(const Key('item-cost')), '24.99');
    await tester.enterText(
      find.byKey(const Key('product-page-url')),
      'https://example.com/purple-silk-pla',
    );
    await tester.ensureVisible(find.byKey(const Key('save-item')));
    await tester.tap(find.byKey(const Key('save-item')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Purple Silk PLA'));
    final addedCard = find.ancestor(
      of: find.text('Purple Silk PLA'),
      matching: find.byType(InventoryCard),
    );
    final addedCardBounds = tester.getRect(addedCard);
    await tester.tapAt(addedCardBounds.topLeft + const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-product-source')), findsOneWidget);
    expect(find.text('https://example.com/purple-silk-pla'), findsOneWidget);
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 1000),
      3000,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-scanner')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ingest'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('manual-qr-code')),
      '618996738298',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('local-barcode-match')), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('item-name')))
          .controller!
          .text,
      'Purple Silk PLA',
    );
  });

  test(
    'ingest decoder reads a tilted alphanumeric Code 128 FNSKU',
    () async {
      const value = 'X004H331ET';
      const barcodeWidth = 900;
      const barcodeHeight = 120;
      final encoded = zxing.zx.encodeBarcode(
        contents: value,
        params: zxing.EncodeParams(
          format: zxing.Format.code128,
          width: barcodeWidth,
          height: barcodeHeight,
          margin: 24,
        ),
      );
      expect(encoded.isValid, isTrue);
      final barcode = img.Image.fromBytes(
        width: barcodeWidth,
        height: barcodeHeight,
        bytes: encoded.data!.buffer,
        numChannels: 1,
      )..backgroundColor = img.ColorRgb8(255, 255, 255);
      final tilted = img.copyRotate(barcode, angle: 8);
      final frame = img.Image(width: 1280, height: 720, numChannels: 3);
      img.fill(frame, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(
        frame,
        tilted,
        dstX: (frame.width - tilted.width) ~/ 2,
        dstY: (frame.height - tilted.height) ~/ 2,
      );

      expect(
        await compute(
          decodeProductBarcodeFrame,
          Uint8List.fromList(img.encodeJpg(frame, quality: 78)),
        ),
        value,
      );
    },
    skip: Platform.environment['INVENTORINATOR_NATIVE_DECODER_TEST'] != '1'
        ? 'Requires the built Linux ZXing native library.'
        : false,
  );

  test('autofocus sharpness score prefers crisp label edges', () {
    final sharp = img.Image(width: 240, height: 160, numChannels: 3);
    for (var y = 0; y < sharp.height; y++) {
      for (var x = 0; x < sharp.width; x++) {
        final light = ((x ~/ 8) + (y ~/ 8)).isEven;
        sharp.setPixel(
          x,
          y,
          light ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0),
        );
      }
    }
    final blurred = img.gaussianBlur(sharp.clone(), radius: 6);
    expect(
      focusSharpnessScore(Uint8List.fromList(img.encodeJpg(sharp))),
      greaterThan(
        focusSharpnessScore(Uint8List.fromList(img.encodeJpg(blurred))),
      ),
    );
  });

  test('label OCR text maps material settings into an item draft', () {
    final draft = parseProductLabelText('''
PolyLite PLA
Color: Hedgehog Makes Galaxy Red
Diameter: 1.75mm
Weight: 1kg
Print Temp: 190-220°C
Bed Temp: 30-60°C
Print Speed: Up to 200mm/s
Fan ON
''', Uint8List.fromList([1, 2, 3]));

    expect(draft.name, 'PolyLite PLA · Hedgehog Makes Galaxy Red');
    expect(draft.material, 'PLA');
    expect(draft.compatibility, '1.75mm, 1kg');
    expect(draft.printingInstructions, contains('Print Temp'));
    expect(draft.imageBytes, isNotEmpty);
  });

  test('label OCR repairs fuzzy filament names and type evidence', () {
    final draft = parseProductLabelText('''
PolyLite PIA
Color:
Hedgehog Makes Galaxy Red
Diameter: 175mm
Print Temp: 190-220°C
Bed Temp: 30-60°C
''', Uint8List.fromList([1]));

    expect(draft.material, 'PLA');
    expect(draft.filamentEvidence, isTrue);
    expect(draft.name, contains('PolyLite PLA'));
    expect(draft.name, contains('Hedgehog Makes Galaxy Red'));
    expect(draft.compatibility, '1.75mm');
  });

  test('label OCR recovers the observed PolyLite PLA title distortion', () {
    final draft = parseProductLabelText('''
POIYL item PILZ
Medgehog Makes Galaxy Red
Diameter 175mm
Print Temp 190-220°C
Bed Temp 30-60°C
''', Uint8List.fromList([1]));

    expect(draft.material, 'PLA');
    expect(draft.name, 'PolyLite PLA');
    expect(draft.filamentEvidence, isTrue);
  });

  test('label OCR parses the observed Kaaber TPU spool label', () {
    final draft = parseProductLabelText('''
Kaaber
3D PRINTER FILAMENT
(1.75mm)
TPU
Printing Temp:
210-230°C
Bed Temp:
20-60°C
Printing Speed:
20-40mm/s
Fan:
ON
''', Uint8List.fromList([1]));

    expect(draft.name, 'Kaaber TPU');
    expect(draft.brand, 'Kaaber');
    expect(draft.material, 'TPU');
    expect(draft.compatibility, '1.75mm');
    expect(draft.printingInstructions, contains('210-230°C'));
    expect(draft.printingInstructions, contains('20-40mm/s'));
  });

  test(
    'label OCR separates a fuzzy Cookiecad brand from its product title',
    () {
      final draft = parseProductLabelText('''
Conkiacad
1.75mm PETG Filament 1.0kg
Dark Magic
Made in China
Print Temperature: 220-240°C
Bed Temperature: 80°C
''', Uint8List.fromList([1]));

      expect(draft.brand, 'Cookiecad');
      expect(draft.name, 'Dark Magic PETG');
      expect(draft.material, 'PETG');
    },
  );

  test(
    'URL import keeps actionable instructions and rejects marketing copy',
    () {
      final instructions = extractProductInstructions(
        '''
      <html><body>
        <p>Beautiful vibrant colors perfect for a wide range of printers.</p>
        <table>
          <tr><th>Nozzle temperature</th><td>190–230°C</td></tr>
          <tr><th>Bed temperature</th><td>30–50°C</td></tr>
          <tr><th>Drying</th><td>55°C for 6 hours</td></tr>
        </table>
        <p>Storage: Keep sealed with desiccant in an airtight bag.</p>
        <p>Reusable spool coming soon. Sign up to download printable files.</p>
      </body></html>
      ''',
        structuredDescription: 'Next-generation PLA with exceptional printing quality. Print temperature 190-230°C.',
      );
      expect(instructions.printing, contains('190–230°C'));
      expect(instructions.printing, contains('30–50°C'));
      expect(instructions.drying, contains('55°C for 6 hours'));
      expect(instructions.storage, contains('sealed with desiccant'));
      expect(instructions.printing, isNot(contains('Next-generation')));
      expect(instructions.printing, isNot(contains('coming soon')));
    },
  );

  test('Amazon fallback extracts product data without JSON-LD', () {
    final product = extractFallbackProductMetadata('''
<html><head>
  <meta name="title" content="Amazon.com: Atomic Filament PLA Filament (Indigo Golden Sparkle v2) : Industrial &amp; Scientific">
  <meta name="description" content="PLA filament, 1.75mm, 1KG spool">
</head><body>
  <a id="bylineInfo">Visit the Atomic Filament Store</a>
  <span id="apex-pricetopay-accessibility-label" data-pricetopay-label="\$32.49"></span>
  <div id="landing-image-wrapper"><img src="https://m.media-amazon.com/product.jpg"></div>
</body></html>
''', Uri.parse('https://www.amazon.com/dp/B0BZWXV3C4'));

    expect(product?['name'], contains('Atomic Filament PLA'));
    expect(product?['name'], isNot(contains('Amazon.com')));
    expect((product?['brand'] as Map?)?['name'], 'Atomic Filament');
    expect((product?['offers'] as Map?)?['price'], '32.49');
    expect(product?['image'], 'https://m.media-amazon.com/product.jpg');
  });

  test('filament template detection preserves specific material families', () {
    expect(
      detectFilamentTemplate('Proto-pasta HTPLA')?.family,
      FilamentFamily.htpla,
    );
    expect(
      detectFilamentTemplate('Clear PCTG filament')?.family,
      FilamentFamily.pctg,
    );
    expect(detectFilamentTemplate('PA12 Nylon')?.family, FilamentFamily.nylon);
    expect(detectFilamentTemplate('replacement plate'), isNull);
  });

  test('product instructions win and canned data fills missing fields', () {
    final result = applyFilamentFallbacks((
      printing: 'Nozzle: 242°C',
      drying: '',
      storage: '',
    ), detectFilamentTemplate('Galaxy Black PETG'));
    expect(result.printing, 'Nozzle: 242°C');
    expect(result.drying, contains('55°C for 6 hours'));
    expect(result.storage, contains('desiccant'));
  });

  test('drying guidance parses into temperature and duration controls', () {
    expect(parseDryingSettings('Dry at 60°C for 4–6 hours.'), (
      temperatureC: 60,
      durationMinutes: 360,
    ));
    expect(parseDryingSettings('Dehydrate at 55 C for 90 minutes'), (
      temperatureC: 55,
      durationMinutes: 90,
    ));
  });

  test('rapidizer smart-matches misspelled and material type names', () {
    expect(smartMatchInventoryType('filamnet'), InventoryType.filament);
    expect(smartMatchInventoryType('fastner'), InventoryType.fastener);
    expect(smartMatchInventoryType('nozle'), InventoryType.nozzle);
    expect(smartMatchInventoryType('PETG'), InventoryType.filament);
    expect(smartMatchInventoryType('unrelated machinery'), isNull);
    final parsed = parseRapidizerText(
      'Blue PLA filamnet 2 19.99\nE3D V6 heat break 1 14.95',
    );
    expect(parsed.errors, isEmpty);
    expect(parsed.items.first.name, 'Blue PLA');
    expect(parsed.items.first.type, InventoryType.filament);
    expect(parsed.items.last.name, 'E3D V6');
    expect(parsed.items.last.type, InventoryType.heatBreak);
  });

  test('kit BOM survives database export and import', () {
    final inventoryItem = InventoryItem(
      id: 'INV-SCREW',
      name: 'M2x8 screw',
      type: InventoryType.other,
      compatibility: const ['Original Prusa i3 MK3S+'],
      added: DateTime(2026),
      cost: 0,
      color: Colors.blue,
      quantity: 42,
      quantityAlertThreshold: 50,
      imageBytes: Uint8List.fromList([1, 2, 3]),
      labelImageBytes: Uint8List.fromList([4, 5, 6]),
      catalogProductId: 'PROD-INSERT',
    );
    const product = CatalogProduct(
      id: 'PROD-INSERT',
      brandId: 'BR-CNC',
      category: InventoryType.other,
      name: 'M3 threaded insert',
    );
    const kit = KitRecord(
      id: 'KIT-1',
      name: 'Voron toolhead rebuild',
      sections: ['Toolhead', 'Frame'],
      bom: [
        KitBomEntry(
          id: 'BOM-TOOLHEAD',
          productId: 'PROD-INSERT',
          quantity: 8,
          section: 'Toolhead',
        ),
        KitBomEntry(
          id: 'BOM-FRAME',
          productId: 'PROD-INSERT',
          quantity: 4,
          section: 'Frame',
        ),
      ],
    );
    final build = BuildRecord(
      id: 'BUILD-1',
      kitId: 'KIT-1',
      name: 'Voron rebuild',
      createdAt: DateTime(2026),
      createdBy: 'Workshop desktop',
      ownerDeviceId: 'DEVICE-DESKTOP',
      ownerUserId: 'USER-1',
      shared: true,
      completedAt: DateTime(2026, 1, 2),
      lines: [
        const BuildLine(
          id: 'LINE-1',
          productId: 'PROD-INSERT',
          name: 'M3 threaded insert',
          section: 'Toolhead',
          requiredQuantity: 12,
          usedQuantity: 1,
          consumedInventoryIds: ['INV-SCREW'],
        ),
      ],
    );
    const machine = MachineRecord(
      id: 'MCH-1',
      name: 'Nut Buster',
      model: 'DIY',
      address: '',
      typeId: 'MT-PRESS',
      kitIds: {'KIT-1'},
    );
    final decoded = decodeWorkshopState(
      encodeWorkshopState(
        inventory: [inventoryItem],
        vendors: const [],
        brands: const [],
        products: const [product],
        kits: const [kit],
        builds: [build],
        machines: const [machine],
      ),
    );
    expect(decoded?.kits.single.name, 'Voron toolhead rebuild');
    expect(decoded?.kits.single.sections, ['Toolhead', 'Frame']);
    expect(decoded?.kits.single.bom, hasLength(2));
    expect(decoded?.kits.single.bom.map((line) => line.productId).toSet(), {
      'PROD-INSERT',
    });
    expect(
      decoded?.kits.single.bom
          .map((line) => line.quantity)
          .reduce((a, b) => a + b),
      12,
    );
    expect(decoded?.kits.single.bom.map((line) => line.section).toSet(), {
      'Toolhead',
      'Frame',
    });
    expect(decoded?.kits.single.bom.map((line) => line.id).toSet(), {
      'BOM-TOOLHEAD',
      'BOM-FRAME',
    });
    expect(decoded?.builds.single.lines.single.usedQuantity, 1);
    expect(decoded?.builds.single.lines.single.consumedInventoryIds, [
      'INV-SCREW',
    ]);
    expect(decoded?.builds.single.ownerDeviceId, 'DEVICE-DESKTOP');
    expect(decoded?.builds.single.ownerUserId, 'USER-1');
    expect(decoded?.builds.single.shared, isTrue);
    expect(decoded?.builds.single.completedAt, DateTime(2026, 1, 2));
    expect(decoded?.machines.single.kitIds, {'KIT-1'});
    expect(decoded?.inventory.single.quantity, 42);
    expect(decoded?.inventory.single.quantityAlertThreshold, 50);
    expect(decoded?.inventory.single.imageBytes, [1, 2, 3]);
    expect(decoded?.inventory.single.labelImageBytes, [4, 5, 6]);
    expect(decoded?.inventory.single.catalogProductId, 'PROD-INSERT');
  });

  test('workspace roles expose the intended permission boundaries', () {
    expect(WorkspaceRole.admin.canDeleteDatabase, isTrue);
    expect(WorkspaceRole.admin.canHardDeleteItems, isTrue);
    expect(WorkspaceRole.manager.canArchiveInventory, isTrue);
    expect(WorkspaceRole.manager.canHardDeleteItems, isFalse);
    expect(WorkspaceRole.editor.canEditInventory, isTrue);
    expect(WorkspaceRole.editor.canCreateInventory, isFalse);
    expect(WorkspaceRole.editor.canCreateBuilds, isTrue);
    expect(WorkspaceRole.editor.canShareBuilds, isTrue);
    expect(WorkspaceRole.builder.canEditInventory, isFalse);
    expect(WorkspaceRole.builder.canCreateBuilds, isFalse);
    expect(WorkspaceRole.builder.canShareBuilds, isFalse);
    expect(WorkspaceRole.builder.canOperateBuilds, isTrue);
    expect(WorkspaceRole.fromServer('owner'), WorkspaceRole.admin);
    expect(WorkspaceRole.fromServer('member'), WorkspaceRole.builder);
  });

  testWidgets('captured label stays separate from the product image', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddItemDialog(
            labelDraft: LabelOcrDraft(
              imageBytes: Uint8List.fromList(
                img.encodePng(img.Image(width: 1, height: 1)),
              ),
              name: 'Scanned PLA',
              material: 'PLA',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final productPicker = find.byKey(const Key('item-image-picker'));
    final labelPicker = find.byKey(const Key('label-image-picker'));
    final processLabel = find.byKey(const Key('process-label-image'));
    expect(
      find.descendant(of: productPicker, matching: find.byType(Image)),
      findsNothing,
    );
    expect(
      find.descendant(of: labelPicker, matching: find.byType(Image)),
      findsOneWidget,
    );
    expect(processLabel, findsOneWidget);
    expect(tester.widget<FilledButton>(processLabel).onPressed, isNotNull);
  });

  testWidgets('OCR brand absent from catalog uses the custom brand field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddItemDialog(
            vendors: starterVendors,
            brands: starterBrands,
            labelDraft: LabelOcrDraft(
              imageBytes: Uint8List.fromList(
                img.encodePng(img.Image(width: 1, height: 1)),
              ),
              name: 'Dark Magic PETG',
              material: 'PETG',
              brand: 'Cookiecad',
              filamentEvidence: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('brand-picker-null')), findsOneWidget);
    final field = tester.widget<TextFormField>(
      find.byKey(const Key('item-custom-brand')),
    );
    expect(field.controller?.text, 'Cookiecad');
  });

  testWidgets('Add Item stacks paired controls with mobile spacing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddItemDialog(
            vendors: starterVendors,
            brands: starterBrands,
            labelDraft: LabelOcrDraft(
              imageBytes: Uint8List.fromList(
                img.encodePng(img.Image(width: 1, height: 1)),
              ),
              name: 'Dark Magic PETG',
              material: 'PETG',
              filamentEvidence: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final quantity = tester.getRect(find.byKey(const Key('item-quantity')));
    final lowStock = tester.getRect(
      find.byKey(const Key('quantity-alert-threshold')),
    );
    final storage = tester.getRect(find.byKey(const Key('storage-location')));
    final deployment = tester.getRect(
      find.byKey(const Key('deployment-location')),
    );
    final dryingTemperature = tester.getRect(
      find.byKey(const Key('drying-temperature')),
    );
    final dryingDuration = tester.getRect(
      find.byKey(const Key('drying-duration')),
    );
    expect(lowStock.top, greaterThan(quantity.bottom));
    expect(deployment.top, greaterThan(storage.bottom));
    expect(dryingDuration.top, greaterThan(dryingTemperature.bottom));
    expect(tester.takeException(), isNull);
  });

  test('legacy hardware is migrated from Other to Fastener', () {
    const brand = BrandRecord(
      id: 'BR-HARDWARE',
      name: 'Hardware Co',
      vendorIds: {},
      categories: {InventoryType.other},
    );
    const product = CatalogProduct(
      id: 'PROD-M3X10',
      brandId: 'BR-HARDWARE',
      category: InventoryType.other,
      name: 'M3x10 screw',
    );
    final item = InventoryItem(
      id: 'INV-M3X10',
      name: 'M3x10 screw',
      type: InventoryType.other,
      compatibility: const [],
      added: DateTime(2026),
      cost: 0,
      color: Colors.grey,
    );
    final decoded = decodeWorkshopState(
      encodeWorkshopState(
        inventory: [item],
        vendors: const [],
        brands: const [brand],
        products: const [product],
      ),
    );
    expect(decoded?.inventory.single.type, InventoryType.fastener);
    expect(decoded?.products.single.category, InventoryType.fastener);
    expect(decoded?.brands.single.categories, contains(InventoryType.fastener));
  });

  test('filament spool size and AMS compatibility survive persistence', () {
    final item = InventoryItem(
      id: 'INV-BIG-SPOOL',
      name: 'Production PLA',
      type: InventoryType.filament,
      compatibility: const [],
      added: DateTime(2026),
      cost: 80,
      color: Colors.purple,
      spoolTypeId: 'SPOOL-5000G',
      amsCompatible: true,
    );
    final decoded = decodeWorkshopState(
      encodeWorkshopState(
        inventory: [item],
        vendors: const [],
        brands: const [],
        products: const [],
      ),
    )!;

    expect(decoded.inventory.single.spoolTypeId, 'SPOOL-5000G');
    expect(decoded.inventory.single.amsCompatible, isTrue);
    expect(decoded.spoolTypes.map((spool) => spool.label), contains('1 kg'));
  });

  test('item edit replaces a cloud-refreshed instance by stable ID', () {
    final dialogItem = InventoryItem(
      id: 'INV-EDIT',
      name: 'Old name',
      type: InventoryType.other,
      compatibility: const [],
      added: DateTime(2026),
      cost: 1,
      color: Colors.blue,
    );
    final inventory = <InventoryItem>[
      dialogItem.copyWith(), // A fresh instance created by cloud decoding.
    ];

    final replaced = replaceInventoryItemById(
      inventory,
      dialogItem.id,
      dialogItem.copyWith(name: 'Updated name'),
    );

    expect(replaced, isTrue);
    expect(inventory.single.name, 'Updated name');
  });

  testWidgets('filament editor exposes spool buttons and AMS toggle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddItemDialog(
            initialItem: InventoryItem(
              id: 'INV-FILAMENT',
              name: 'Large PLA',
              type: InventoryType.filament,
              compatibility: const [],
              added: DateTime(2026),
              cost: 30,
              color: Colors.purple,
              spoolTypeId: 'SPOOL-3000G',
              amsCompatible: true,
              moistureLifespanMinutes: 14400,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('spool-size-SPOOL-250G')), findsOneWidget);
    final selected = tester.widget<ChoiceChip>(
      find.byKey(const Key('spool-size-SPOOL-3000G')),
    );
    expect(selected.selected, isTrue);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('ams-compatible')))
          .value,
      isTrue,
    );
  });

  testWidgets('inventory cards show item quantity', (tester) async {
    final item = InventoryItem(
      id: 'INV-M2X8',
      name: 'M2x8 screw',
      type: InventoryType.other,
      compatibility: const [],
      added: DateTime(2026),
      cost: 0,
      color: Colors.blue,
      quantity: 18,
      quantityAlertThreshold: 20,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 260,
            child: InventoryCard(item: item, onOpen: () {}, onAction: (_) {}),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('item-quantity-INV-M2X8')), findsOneWidget);
    expect(find.text('×18'), findsOneWidget);
    expect(find.text('LOW'), findsNWidgets(2));
    expect(find.byTooltip('Low stock'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            widget.icon == Icons.warning_amber_rounded &&
            widget.key == null,
      ),
      findsNWidgets(2),
    );
  });

  test('moisture remaining sort puts urgent filament first', () {
    final now = DateTime(2026, 8, 26, 12);
    InventoryItem filament(String id, String name, int daysSinceDrying) =>
        InventoryItem(
          id: id,
          name: name,
          type: InventoryType.filament,
          compatibility: const [],
          added: DateTime(2026),
          cost: 20,
          color: Colors.purple,
          moistureLifespanMinutes: 10 * 1440,
          lastDriedAt: now.subtract(Duration(days: daysSinceDrying)),
        );
    final items = [
      InventoryItem(
        id: 'OTHER',
        name: 'No moisture timer',
        type: InventoryType.nozzle,
        compatibility: const [],
        added: DateTime(2026),
        cost: 5,
        color: Colors.blue,
      ),
      filament('FRESH', 'Fresh', 1),
      filament('WET', 'Wet', 11),
      filament('SOON', 'Soon', 9),
    ]..sort((a, b) => compareMoistureRemaining(a, b, now: now));

    expect(items.map((item) => item.id), ['WET', 'SOON', 'FRESH', 'OTHER']);
  });

  testWidgets('remote quantity changes fire a southeast card animation', (
    tester,
  ) async {
    final original = InventoryItem(
      id: 'INV-REMOTE-QTY',
      name: 'Remote screws',
      type: InventoryType.fastener,
      compatibility: const [],
      added: DateTime(2026),
      cost: 1,
      color: Colors.amber,
      quantity: 10,
    );
    final changed = original.copyWith(quantity: 7);
    final added = original.copyWith(id: 'INV-NEW', quantity: 3);
    expect(remoteQuantityChangedItemIds([original], [changed, added]), {
      'INV-REMOTE-QTY',
    });
    final stockOriginal = original.copyWith(quantityAlertThreshold: 5);
    final stockLow = stockOriginal.copyWith(quantity: 4);
    expect(lowStockEnteredItemIds([stockOriginal], [stockLow]), {
      'INV-REMOTE-QTY',
    });

    Widget card(InventoryItem item, int trigger) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 260,
          child: InventoryCard(
            item: item,
            quantitySyncVersion: trigger,
            onOpen: () {},
            onAction: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpWidget(card(original, 0));
    final arrow = find.byKey(const Key('remote-quantity-arrow-INV-REMOTE-QTY'));
    expect(arrow, findsOneWidget);
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(of: arrow, matching: find.byType(Opacity)).first,
          )
          .opacity,
      0,
    );

    await tester.pumpWidget(card(changed, 1));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byIcon(Icons.south_east_rounded), findsOneWidget);
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(of: arrow, matching: find.byType(Opacity)).first,
          )
          .opacity,
      greaterThan(0),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(of: arrow, matching: find.byType(Opacity)).first,
          )
          .opacity,
      0,
    );
  });

  testWidgets('debug panel triggers low-stock and moisture card effects', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());

    await tester.tap(find.byKey(const Key('debug-panel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('debug-item')), findsOneWidget);
    expect(find.byKey(const Key('debug-quantity-sync')), findsOneWidget);
    expect(find.byKey(const Key('debug-low-stock')), findsOneWidget);
    expect(find.byKey(const Key('debug-moisture-wave')), findsOneWidget);
    expect(find.byKey(const Key('animation-duration')), findsNothing);
    expect(find.byKey(const Key('animation-recurrence')), findsNothing);
    final targetItemId = tester
        .widget<DropdownButtonFormField<String>>(
          find.byKey(const Key('debug-item')),
        )
        .initialValue!;

    await tester.tap(find.byKey(const Key('debug-low-stock')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final lowPulse = find.byKey(Key('low-stock-pulse-$targetItemId'));
    expect(lowPulse, findsOneWidget);
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(of: lowPulse, matching: find.byType(Opacity)).first,
          )
          .opacity,
      greaterThan(0),
    );
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('debug-panel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('debug-moisture-wave')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final moistureWave = find.byKey(Key('moisture-wave-$targetItemId'));
    expect(moistureWave, findsOneWidget);
    expect(
      tester
          .widget<Opacity>(
            find
                .ancestor(of: moistureWave, matching: find.byType(Opacity))
                .first,
          )
          .opacity,
      greaterThan(0),
    );
  });

  testWidgets('animation controls live outside the debug panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());

    await tester.tap(find.byKey(const Key('animation-controls')));
    await tester.pumpAndSettle();
    expect(find.text('Animation controls'), findsOneWidget);
    expect(find.byKey(const Key('animation-duration')), findsOneWidget);
    expect(find.byKey(const Key('animation-recurrence')), findsOneWidget);
    expect(find.byKey(const Key('debug-item')), findsNothing);
  });

  testWidgets('visible low-stock alerts recur on their configured timer', (
    tester,
  ) async {
    final item = InventoryItem(
      id: 'LOW-RECUR',
      name: 'Low recurring stock',
      type: InventoryType.fastener,
      compatibility: const [],
      added: DateTime(2026),
      cost: 1,
      color: Colors.amber,
      quantity: 1,
      quantityAlertThreshold: 2,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 260,
            child: InventoryCard(
              item: item,
              animationDurationPercent: 25,
              animationRecurrenceSeconds: 3,
              onOpen: () {},
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    final pulse = find.byKey(const Key('low-stock-pulse-LOW-RECUR'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(of: pulse, matching: find.byType(Opacity)).first,
          )
          .opacity,
      greaterThan(0),
    );
    await tester.pump(const Duration(milliseconds: 200));
    var recurred = false;
    for (var frame = 0; frame < 14; frame++) {
      await tester.pump(const Duration(milliseconds: 250));
      final opacity = tester
          .widget<Opacity>(
            find.ancestor(of: pulse, matching: find.byType(Opacity)).first,
          )
          .opacity;
      if (frame > 3 && opacity > 0) recurred = true;
    }
    expect(recurred, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('moisture droplets travel vertically down the card', (
    tester,
  ) async {
    final now = DateTime.now();
    final item = InventoryItem(
      id: 'WET-DROP',
      name: 'Wet filament',
      type: InventoryType.filament,
      compatibility: const [],
      added: DateTime(2026),
      cost: 20,
      color: Colors.blue,
      moistureLifespanMinutes: 60,
      lastDriedAt: now.subtract(const Duration(hours: 2)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 260,
            child: InventoryCard(
              item: item,
              animationRecurrenceSeconds: 0,
              onOpen: () {},
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    final drop = find.byKey(const Key('moisture-wave-WET-DROP'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    final first =
        tester
                .widget<Align>(
                  find.ancestor(of: drop, matching: find.byType(Align)).first,
                )
                .alignment
            as Alignment;
    await tester.pump(const Duration(milliseconds: 300));
    final second =
        tester
                .widget<Align>(
                  find.ancestor(of: drop, matching: find.byType(Align)).first,
                )
                .alignment
            as Alignment;
    expect(second.x, first.x);
    expect(second.y, greaterThan(first.y));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('compatibility search ignores spaces and punctuation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.enterText(find.byType(TextField), 'E3DV6');
    await tester.pump();
    expect(find.text('Copper heater block'), findsOneWidget);
    expect(find.text('V6 sock — 3 pack'), findsOneWidget);
    expect(find.text('Bone White PLA'), findsNothing);
  });

  testWidgets('older PLA imports expose all filament lifecycle fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddItemDialog(
            initialItem: InventoryItem(
              id: 'old-pla',
              name: 'Panchroma Matte PLA',
              type: InventoryType.other,
              compatibility: const [],
              added: DateTime(2026),
              cost: 20,
              color: Colors.purple,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drying-temperature')), findsOneWidget);
    expect(find.byKey(const Key('drying-duration')), findsOneWidget);
    expect(find.byKey(const Key('moisture-lifespan')), findsOneWidget);
    expect(find.byKey(const Key('moisture-alert-toggle')), findsOneWidget);
  });

  testWidgets('pagination happens after global search and sorting', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final inventory = List.generate(
      30,
      (index) => InventoryItem(
        id: 'PAGE-$index',
        name: 'Page item $index',
        type: InventoryType.other,
        compatibility: const [],
        added: DateTime(2026, 1, 1).add(Duration(days: index)),
        cost: index.toDouble(),
        color: Colors.purple,
      ),
    );
    await tester.pumpWidget(
      InventorinatorApp(
        persistedState: encodeWorkshopState(
          inventory: inventory,
          vendors: const [],
          brands: const [],
          products: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-size-slider')), findsOneWidget);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -3000),
      3000,
    );
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 3 · 30 results'), findsOneWidget);
    expect(find.text('Page item 29'), findsNothing);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 3000),
      3000,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Page item 29');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(InventoryCard),
        matching: find.text('Page item 29'),
      ),
      findsOneWidget,
    );
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -3000),
      3000,
    );
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 1 · 1 results'), findsOneWidget);
  });

  testWidgets(
    'main filters expose catalog kits, machines, printers, and tools',
    (tester) async {
      final state = encodeWorkshopState(
        inventory: sampleInventory,
        vendors: starterVendors,
        brands: starterBrands,
        products: starterProducts,
        machineTypes: const [
          MachineTypeRecord(id: 'TYPE-PRINTER', name: 'Printer'),
          MachineTypeRecord(id: 'TYPE-TOOL', name: 'Tool'),
        ],
        machines: const [
          MachineRecord(
            id: 'MACHINE-PRUSA',
            name: 'Prusa MK3S+',
            model: 'MK3S+',
            address: 'prusa.local',
            typeId: 'TYPE-PRINTER',
          ),
          MachineRecord(
            id: 'MACHINE-PRESS',
            name: 'Nut Buster',
            model: 'Heat insert press',
            address: '',
            typeId: 'TYPE-TOOL',
          ),
        ],
        kits: const [
          KitRecord(
            id: 'KIT-PRUSA',
            name: 'Prusa assembly kit',
            bom: [KitBomEntry(productId: 'KIT-HOTEND', quantity: 2)],
          ),
          KitRecord(id: 'KIT-HOTEND', name: 'Hotend kit', bom: []),
        ],
      );
      await tester.pumpWidget(InventorinatorApp(persistedState: state));

      for (final name in CatalogViewFilter.values) {
        expect(find.byKey(Key('catalog-filter-${name.name}')), findsOneWidget);
      }

      await tester.ensureVisible(find.byKey(const Key('catalog-filter-kits')));
      await tester.tap(find.byKey(const Key('catalog-filter-kits')));
      await tester.pumpAndSettle();
      expect(find.text('Prusa assembly kit'), findsOneWidget);
      await tester.tap(find.text('Prusa assembly kit'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kit-details-title')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('kit-detail-line-KIT-HOTEND')),
          matching: find.text('Hotend kit'),
        ),
        findsOneWidget,
      );
      expect(find.text('× 2'), findsOneWidget);
      expect(find.byKey(const Key('new-kit-name')), findsNothing);
      await tester.tap(find.byKey(const Key('kit-detail-line-KIT-HOTEND')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kit-details-title')), findsNWidgets(2));
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog).last,
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('Prusa assembly kit'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit kit / BOM'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Assembling BOM…'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Kit / BOM'), findsOneWidget);
      expect(find.byKey(const Key('new-kit-name')), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('catalog-filter-printers')));
      await tester.pumpAndSettle();
      expect(find.text('Prusa MK3S+'), findsOneWidget);
      expect(find.text('Nut Buster'), findsNothing);

      await tester.tap(find.byKey(const Key('catalog-filter-tools')));
      await tester.pumpAndSettle();
      expect(find.text('Nut Buster'), findsOneWidget);
      expect(find.text('Prusa MK3S+'), findsNothing);
    },
  );

  testWidgets('mobile inventory controls do not overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.pump();

    expect(find.byKey(const Key('page-size-slider')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('switches between grid and one-column list', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    expect(find.byType(InventoryCard), findsWidgets);
    await tester.tap(find.byIcon(Icons.view_agenda_outlined));
    await tester.pump();
    expect(find.byType(InventoryRow), findsWidgets);
  });
  testWidgets('adds a validated inventory item', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-product-web')), findsOneWidget);
    expect(find.byKey(const Key('product-page-url')), findsOneWidget);
    expect(find.byKey(const Key('import-product-page')), findsOneWidget);
    expect(find.byKey(const Key('item-barcode')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('item-name')), 'Ruby ABS');
    await tester.enterText(
      find.byKey(const Key('item-compatibility')),
      'E3D V6, 1.75 mm',
    );
    await tester.enterText(find.byKey(const Key('item-cost')), '29.50');
    await tester.ensureVisible(find.byKey(const Key('save-item')));
    await tester.tap(find.byKey(const Key('save-item')));
    await tester.pumpAndSettle();
    expect(find.text('Ruby ABS'), findsOneWidget);
    expect(find.text('8 items'), findsOneWidget);
  });
  testWidgets('rapidizer creates every populated line with corrected types', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = encodeWorkshopState(
      inventory: const [],
      vendors: const [],
      brands: const [],
      products: const [],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.tap(find.byKey(const Key('open-rapidizer')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('rapidizer-input')), findsOneWidget);
    expect(find.byKey(const Key('rapid-name-0')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('rapidizer-input')),
      'Blue PLA filamnet 2 19.99\nM3 nut fastner 12 0.08',
    );
    await tester.tap(find.byKey(const Key('rapidize-items')));
    await tester.pumpAndSettle();

    expect(find.text('Blue PLA'), findsOneWidget);
    expect(find.text('M3 nut'), findsOneWidget);
    expect(find.text('2 items RAPIDIZED!'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);
    expect(find.text('×12'), findsOneWidget);
  });
  testWidgets('catalog selection fills and creates an inventory item', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filament').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('brand-picker-null')));
    await tester.pumpAndSettle();
    expect(find.text('E3D'), findsNothing);
    await tester.tap(find.text('Polymaker').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-vendor')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Printed Solid').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('product-PROD-POLYLITE-PLA')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('moisture-lifespan')), '10');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('item-name')))
          .controller!
          .text,
      'PolyLite PLA',
    );
    await tester.ensureVisible(find.byKey(const Key('save-item')));
    await tester.tap(find.byKey(const Key('save-item')));
    await tester.pumpAndSettle();
    expect(find.text('PolyLite PLA'), findsOneWidget);
  });
  testWidgets('catalog manager adds a vendor', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('new-vendor-name')),
      'Maker Supply',
    );
    await tester.tap(find.byKey(const Key('add-vendor')));
    await tester.pumpAndSettle();
    expect(find.text('Maker Supply'), findsOneWidget);
  });

  testWidgets('catalog adds a custom spool size', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('catalog-spool-types-section')),
    );
    await tester.tap(find.byKey(const Key('catalog-spool-types-section')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-spool-label')), '2.5 kg');
    await tester.enterText(find.byKey(const Key('new-spool-weight')), '2500');
    await tester.tap(find.byKey(const Key('add-spool-type')));
    await tester.pumpAndSettle();

    expect(find.text('2.5 kg'), findsWidgets);
  });

  testWidgets('catalog adds machine types and machines', (tester) async {
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-machines-section')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('new-machine-type-name')),
      'Heat Insert Press',
    );
    await tester.ensureVisible(find.byKey(const Key('add-machine-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-machine-type')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('new-machine-name')),
      'Nut Buster',
    );
    await tester.ensureVisible(find.byKey(const Key('add-machine')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-machine')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nut Buster'), findsOneWidget);
  });
  testWidgets('catalog edits an existing kit without changing its identity', (
    tester,
  ) async {
    const product = CatalogProduct(
      id: 'PROD-SCREW',
      brandId: 'BR-HARDWARE',
      category: InventoryType.fastener,
      name: 'M3x10 screw',
    );
    const kit = KitRecord(
      id: 'KIT-ORIGINAL',
      name: 'Original kit name',
      bom: [KitBomEntry(productId: 'PROD-SCREW', quantity: 4)],
    );
    final state = encodeWorkshopState(
      inventory: const [],
      vendors: const [],
      brands: const [],
      products: const [product],
      kits: const [kit],
    );

    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -1400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('catalog-kits-section')));
    await tester.tap(find.byKey(const Key('catalog-kits-section')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kit-editor-footer')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('edit-kit-KIT-ORIGINAL')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-kit-KIT-ORIGINAL')));
    await tester.pumpAndSettle();

    expect(find.text('Update kit'), findsOneWidget);
    expect(find.byKey(const Key('kit-bom-name-PROD-SCREW')), findsOneWidget);
    expect(
      find.byKey(const Key('kit-bom-quantity-PROD-SCREW')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('delete-kit-bom-PROD-SCREW')), findsOneWidget);
    expect(find.byKey(const Key('kit-section-Unassigned')), findsOneWidget);
    expect(find.byKey(const Key('kit-bom-section-PROD-SCREW')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('kit-bom-name-PROD-SCREW')),
      'M3x10 frame screw',
    );
    await tester.enterText(
      find.byKey(const Key('kit-bom-quantity-PROD-SCREW')),
      '8',
    );
    await tester.enterText(
      find.byKey(const Key('new-kit-name')),
      'Updated kit name',
    );
    await tester.tap(find.byKey(const Key('save-kit')));
    await tester.pumpAndSettle();

    expect(find.text('Updated kit name'), findsOneWidget);
    expect(find.byKey(const Key('edit-kit-KIT-ORIGINAL')), findsOneWidget);
    expect(find.text('Update kit'), findsNothing);
  });
  testWidgets('kit BOM picker creates and selects a new catalog item', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = encodeWorkshopState(
      inventory: const [],
      vendors: const [],
      brands: const [],
      products: const [],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -1400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('catalog-kits-section')));
    await tester.tap(find.byKey(const Key('catalog-kits-section')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-kit-section')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('kit-section-name')),
      'Fasteners',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('add-kit-bom-line')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-kit-bom-line')));
    await tester.pumpAndSettle();

    expect(find.text('Create new catalog item…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('create-kit-product')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('quick-product-name')),
      'Custom M4 bolt',
    );
    await tester.enterText(find.byKey(const Key('quick-product-cost')), '0.25');
    await tester.tap(find.byKey(const Key('create-quick-product')));
    await tester.pumpAndSettle();

    expect(find.text('Custom M4 bolt'), findsOneWidget);
    expect(find.byKey(const Key('add-kit-bom-line')), findsOneWidget);
  });

  testWidgets('build queue consumes lines and keeps the full kit beside it', (
    tester,
  ) async {
    const kit = KitRecord(
      id: 'KIT-BUILD',
      name: 'Printer rebuild',
      bom: [
        KitBomEntry(
          productId: 'PROD-SCREW',
          quantity: 2,
          name: 'M3 screw',
          section: 'X-axis',
        ),
      ],
    );
    final build = BuildRecord(
      id: 'BUILD-1',
      kitId: kit.id,
      name: 'Printer rebuild build',
      createdAt: DateTime(2026),
      createdBy: 'Test device',
      lines: [
        const BuildLine(
          id: 'LINE-1',
          productId: 'PROD-SCREW',
          name: 'M3 screw',
          section: 'X-axis',
          requiredQuantity: 2,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: BuildQueueDialog(
            build: build,
            kit: kit,
            kits: const [kit],
            products: const [],
            availableQuantity: (_, _) => 2,
            onAdjust: (lineId, use) async {
              final line = build.lines.single;
              build.lines[0] = line.copyWith(
                usedQuantity: line.usedQuantity + (use ? 1 : -1),
              );
              return true;
            },
            canUse: true,
            canShare: true,
            onSharedChanged: (shared) async {
              build.shared = shared;
              return true;
            },
            onCompletedChanged: (completed) async {
              build.completedAt = completed ? DateTime(2026) : null;
              return true;
            },
          ),
        ),
      ),
    );
    expect(find.text('Use 1'), findsOneWidget);
    expect(find.byKey(const Key('build-section-X-axis')), findsOneWidget);
    await tester.tap(find.text('Use 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 / 2 used'), findsOneWidget);

    expect(find.text('Unshared'), findsOneWidget);
    await tester.tap(find.byKey(const Key('share-build')));
    await tester.pumpAndSettle();
    expect(find.text('Shared'), findsOneWidget);

    await tester.tap(find.text('Use 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const Key('build-completion-confetti')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.textContaining('2 / 2 used'), findsOneWidget);
    await tester.tap(find.byKey(const Key('complete-build')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const Key('build-completion-confetti')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Reopen'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toggle-build-kit-panel')));
    await tester.pumpAndSettle();
    expect(find.text('Full kit'), findsNothing);
    expect(find.text('Hide kit'), findsOneWidget);
    expect(find.text('M3 screw'), findsNWidgets(2));
    expect(find.textContaining('X-axis'), findsWidgets);
  });

  testWidgets('kit and build views expose missing stock in red cards', (
    tester,
  ) async {
    const kit = KitRecord(
      id: 'KIT-SHORT',
      name: 'Short kit',
      bom: [
        KitBomEntry(
          productId: 'PROD-BOLT',
          quantity: 3,
          name: 'M4 bolt',
          section: 'Frame',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: KitDetailsDialog(
            kit: kit,
            kits: const [kit],
            products: const [],
            availableQuantity: (_, _) => 1,
            onBuild: (_) {},
            canBuild: false,
            buildDisabledReason: 'Role cannot create builds.',
          ),
        ),
      ),
    );

    expect(find.textContaining('Missing 2'), findsOneWidget);
    expect(
      tester
          .widget<Card>(find.byKey(const Key('kit-detail-line-PROD-BOLT')))
          .color,
      const Color(0xff351a22),
    );
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('build-kit'))).onPressed,
      isNull,
    );
    expect(find.byKey(const Key('build-disabled-reason')), findsOneWidget);

    final build = BuildRecord(
      id: 'BUILD-SHORT',
      kitId: kit.id,
      name: 'Short kit build',
      createdAt: DateTime(2026),
      createdBy: 'Test device',
      lines: const [
        BuildLine(
          id: 'LINE-SHORT',
          productId: 'PROD-BOLT',
          name: 'M4 bolt',
          section: 'Frame',
          requiredQuantity: 3,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: BuildQueueDialog(
            build: build,
            kit: kit,
            kits: const [kit],
            products: const [],
            availableQuantity: (_, _) => 1,
            onAdjust: (_, _) async => false,
            canUse: true,
            canShare: false,
            onSharedChanged: (_) async => false,
            onCompletedChanged: (_) async => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('2 missing'), findsOneWidget);
    expect(
      tester
          .widget<Card>(find.byKey(const Key('build-stock-LINE-SHORT')))
          .color,
      const Color(0xff351a22),
    );
  });

  testWidgets('vendor can be created as a linked brand identity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('new-vendor-name')),
      'Prusa Research',
    );
    await tester.tap(find.byKey(const Key('vendor-is-brand')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('vendor-brand-category-filament')));
    await tester.tap(find.byKey(const Key('add-vendor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filament').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('brand-picker-null')));
    await tester.pumpAndSettle();
    expect(find.text('Prusa Research'), findsOneWidget);
  });
  testWidgets('deployed items use a padlock status icon', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(2));
  });
  testWidgets('active drying uses time-until-dry status', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == 'Time until dry',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CircularProgressIndicator &&
            widget.color == const Color(0xff9c83ff),
      ),
      findsOneWidget,
    );
    expect(find.text('82m'), findsOneWidget);
  });
  test('drying countdown derives remaining time from its start timestamp', () {
    final started = DateTime(2026, 8, 25, 12);
    final item = sampleInventory.first.copyWith(
      dryingRemaining: 300,
      dryingStartedAt: started,
    );
    expect(
      dryingMinutesRemaining(
        item,
        now: started.add(const Duration(minutes: 61)),
      ),
      239,
    );
  });
  test('ready moisture countdown empties toward wet', () {
    final driedAt = DateTime(2026, 8, 25, 12);
    final item = sampleInventory.first.copyWith(
      filamentStatus: FilamentStatus.ready,
      moistureLifespanMinutes: 10 * 24 * 60,
      lastDriedAt: driedAt,
    );
    expect(moistureLifeProgress(item, now: driedAt), 1);
    expect(
      moistureLifeProgress(item, now: driedAt.add(const Duration(days: 9))),
      closeTo(.1, .0001),
    );
    expect(
      moistureLifeProgress(item, now: driedAt.add(const Duration(days: 10))),
      0,
    );
  });
  testWidgets('flyout owns Drying and Deployed status toggles', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.text('Galaxy Black PETG'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('status-drying')))
          .selected,
      isTrue,
    );
    expect(find.text('Ready'), findsWidgets);
    expect(find.text('Wet'), findsOneWidget);
    expect(find.text('Drying time remaining'), findsOneWidget);
    await tester.tap(find.byKey(const Key('status-deployed')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('status-deployed')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('status-drying')))
          .selected,
      isFalse,
    );
    expect(find.text('Deployment location'), findsOneWidget);
    expect(find.text('Time since dried'), findsOneWidget);
    expect(find.text('Drying time remaining'), findsNothing);
  });
  testWidgets('non-filament flyout hides filament drying statuses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.text('ObXidian 0.4 mm'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('status-drying')), findsNothing);
    expect(find.text('Wet'), findsNothing);
    expect(find.byKey(const Key('item-deployed')), findsOneWidget);
  });
  testWidgets('left click opens QR and instruction panel', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.text('Galaxy Black PETG'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('INV-FIL-0001'), findsOneWidget);
    expect(find.byKey(const Key('download-qr')), findsOneWidget);
    expect(find.text('Vendor'), findsOneWidget);
    expect(find.text('Printing instructions'), findsOneWidget);
    expect(find.text('Drying profile'), findsOneWidget);
    expect(find.text('Drying temperature'), findsOneWidget);
    expect(find.text('Drying duration'), findsOneWidget);
    expect(find.text('Storage'), findsOneWidget);
  });
  test('QR download filename includes the item name and stable ID', () {
    expect(
      qrDownloadFileName(sampleInventory.first),
      'Galaxy-Black-PETG_INV-FIL-0001_QR.png',
    );
  });
  testWidgets('drying instructions toggle from Celsius to Fahrenheit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.text('Galaxy Black PETG'));
    await tester.pumpAndSettle();
    expect(find.textContaining('65°C'), findsWidgets);
    await tester.ensureVisible(find.text('°F'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('°F'));
    await tester.pumpAndSettle();
    expect(find.textContaining('149°F'), findsWidgets);
    expect(find.textContaining('65°C'), findsNothing);
  });
  testWidgets('right click exposes and runs item actions', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(
      find.text('ObXidian 0.4 mm'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Reset dry timer'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(find.text('ObXidian 0.4 mm copy'), findsOneWidget);
  });
  testWidgets('archived view can restore archived items', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.text('Brass 0.6 mm'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Brass 0.6 mm'), findsNothing);
    await tester.tap(find.byKey(const Key('archived-view')));
    await tester.pumpAndSettle();
    expect(find.text('Brass 0.6 mm'), findsOneWidget);
    expect(find.text('1 archived'), findsOneWidget);
    await tester.tap(find.text('Brass 0.6 mm'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Restore'), findsOneWidget);
  });

  testWidgets('depleted items retain a distinct restorable archive state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.text('Galaxy Black PETG'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('mark-depleted')));
    await tester.tap(find.byKey(const Key('mark-depleted')));
    await tester.pumpAndSettle();

    expect(find.text('Galaxy Black PETG'), findsNothing);
    await tester.tap(find.byKey(const Key('archived-view')));
    await tester.pumpAndSettle();
    expect(find.text('Galaxy Black PETG'), findsOneWidget);
    expect(find.text('Depleted'), findsOneWidget);

    await tester.tap(find.text('Galaxy Black PETG'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('restore-item')));
    await tester.tap(find.byKey(const Key('restore-item')));
    await tester.pumpAndSettle();
    expect(find.text('Galaxy Black PETG'), findsNothing);
  });

  test('custom item types and contextual values survive persistence', () {
    const customType = CustomItemTypeRecord(
      id: 'TYPE-SOAP',
      name: 'Soap batch',
      contextualFields: ['Cure time', 'Mold'],
    );
    final item = sampleInventory.first.copyWith(
      type: InventoryType.custom,
      customTypeId: customType.id,
      customTypeName: customType.name,
      customFieldValues: const {'Cure time': '6 weeks', 'Mold': 'Loaf 2'},
    );
    final decoded = decodeWorkshopState(
      encodeWorkshopState(
        inventory: [item],
        vendors: const [],
        brands: const [],
        products: const [],
        customItemTypes: const [customType],
      ),
    );

    expect(decoded?.customItemTypes.single.name, 'Soap batch');
    expect(decoded?.inventory.single.typeLabel, 'Soap batch');
    expect(decoded?.inventory.single.customFieldValues['Cure time'], '6 weeks');
  });

  testWidgets('custom item type shows only its contextual fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const customType = CustomItemTypeRecord(
      id: 'TYPE-SOAP',
      name: 'Soap batch',
      contextualFields: ['Cure time', 'Mold'],
    );
    final item = sampleInventory.first.copyWith(
      type: InventoryType.custom,
      customTypeId: customType.id,
      customTypeName: customType.name,
      customFieldValues: const {'Cure time': '6 weeks', 'Mold': 'Loaf 2'},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddItemDialog(
            initialItem: item,
            customItemTypes: const [customType],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('custom-item-type')), findsOneWidget);
    expect(find.byKey(const Key('custom-field-curetime')), findsOneWidget);
    expect(find.byKey(const Key('custom-field-mold')), findsOneWidget);
    expect(find.byKey(const Key('printing-instructions')), findsNothing);
    expect(find.byKey(const Key('drying-temperature')), findsNothing);
  });

  testWidgets('printed parts get printing but not drying instructions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddItemDialog(
            initialItem: sampleInventory.first.copyWith(
              type: InventoryType.printedPart,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('printing-instructions')), findsOneWidget);
    expect(find.byKey(const Key('drying-temperature')), findsNothing);
    expect(find.byKey(const Key('moisture-lifespan')), findsNothing);
  });
}
