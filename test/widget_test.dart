import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventorinator/filament_colors.dart';
import 'package:inventorinator/kit_package.dart';
import 'package:inventorinator/main.dart';
import 'package:inventorinator/cloud_sync_dialog.dart';
import 'package:inventorinator/label_ocr.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/qr_scanner.dart';
import 'package:inventorinator/supabase_sync.dart';
import 'package:inventorinator/sync_onboarding_dialog.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('first-run Supabase setup exposes direct pairing QR', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SyncOnboardingDialog())),
    );
    await tester.tap(find.text('Join an existing inventory'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboarding-scan-pairing')), findsOneWidget);
    expect(find.text('Scan pairing QR'), findsOneWidget);
    expect(
      find.byKey(const Key('supabase-onboarding-pairing-key')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('onboarding-join-with-key')), findsOneWidget);
    expect(find.byKey(const Key('supabase-onboarding-key')), findsNothing);
  });

  testWidgets('first launch can start with an empty inventory', (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-empty-first-launch-',
    );
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      ),
    ))!;

    await tester.pumpWidget(InventorinatorApp(database: database));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Start your inventory'), findsOneWidget);
    expect(find.byKey(const Key('load-demo-inventory')), findsOneWidget);
    await tester.tap(find.byKey(const Key('start-empty-inventory')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('getting-started-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('getting-started-skip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This device only'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(decodeWorkshopState(database.loadState())!.inventory, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    database.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets('first launch can load the demo inventory', (tester) async {
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-demo-first-launch-',
    );
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      ),
    ))!;

    await tester.pumpWidget(InventorinatorApp(database: database));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('load-demo-inventory')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('getting-started-skip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This device only'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      decodeWorkshopState(database.loadState())!.inventory.length,
      sampleInventory.length,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    database.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets('Getting started is replayable and walks through core tasks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.byKey(const Key('getting-started-help')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('getting-started-dialog')), findsOneWidget);
    expect(find.text('Local inventory first'), findsOneWidget);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('getting-started-next')));
    await tester.pumpAndSettle();
    expect(find.text('Add and find items'), findsOneWidget);
    await tester.tap(find.byKey(const Key('getting-started-next')));
    await tester.pumpAndSettle();
    expect(find.text('Organize the Stockroom'), findsOneWidget);
    await tester.tap(find.byKey(const Key('getting-started-next')));
    await tester.pumpAndSettle();
    expect(find.text('Protect your inventory'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pairing code dialog lays out its QR code', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PairingCodeDialog(payload: 'inventorinator:pair:test-payload'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byKey(const Key('copy-pairing-key')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cloud sync lists remembered inventories without pairing', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-known-workspaces-',
    );
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      ),
    ))!;
    const workspaceId = '10000000-0000-0000-0000-000000000001';
    const active = SupabaseConfig(
      syncMode: 'supabase',
      url: 'https://supabase.example.test',
      publishableKey: 'publishable-key',
    );
    const remembered = SupabaseConfig(
      syncMode: 'supabase',
      url: 'https://supabase.example.test',
      publishableKey: 'publishable-key',
      userId: '20000000-0000-0000-0000-000000000001',
      workspaceId: workspaceId,
      workspaceRole: 'owner',
      refreshToken: 'refresh-token',
    );
    database.saveSyncConfig(jsonEncode(active.toJson()));
    database.saveStringPreference(
      'known_supabase_workspaces',
      jsonEncode([remembered.toJson()]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CloudSyncDialog(
          database: database,
          localStateJson: '{}',
          onCloudState: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Join existing inventory'), findsOneWidget);
    expect(find.byKey(const Key('known-workspace-$workspaceId')), findsNothing);
    await tester.tap(find.byKey(const Key('show-join-device')));
    await tester.pump();
    expect(
      find.byKey(const Key('known-workspace-$workspaceId')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('forget-workspace-$workspaceId')));
    await tester.pump();
    expect(find.byKey(const Key('known-workspace-$workspaceId')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    database.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets('owner refresh failure keeps existing roles button visible', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-owner-button-',
    );
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      ),
    ))!;
    const config = SupabaseConfig(
      syncMode: 'supabase',
      url: 'http://127.0.0.1:1',
      publishableKey: 'publishable-key',
      userId: '20000000-0000-0000-0000-000000000001',
      workspaceId: '10000000-0000-0000-0000-000000000001',
      workspaceRole: 'owner',
      refreshToken: 'expired-refresh-token',
    );
    database.saveSyncConfig(jsonEncode(config.toJson()));

    await tester.pumpWidget(
      MaterialApp(
        home: CloudSyncDialog(
          database: database,
          localStateJson: '{}',
          onCloudState: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('manage-devices')), findsOneWidget);
    expect(find.text('Roles & devices'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    database.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets('admin device exposes team management without owner recovery', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-admin-device-',
    );
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      ),
    ))!;
    final config = SupabaseConfig(
      syncMode: 'supabase',
      url: 'http://127.0.0.1:1',
      publishableKey: 'publishable-key',
      userId: '20000000-0000-0000-0000-000000000002',
      workspaceId: '10000000-0000-0000-0000-000000000001',
      workspaceRole: 'admin',
      accessToken: 'cached-access-token',
      accessTokenExpiresAt: DateTime.now().toUtc().add(
        const Duration(hours: 1),
      ),
      refreshToken: 'refresh-token',
    );
    database.saveSyncConfig(jsonEncode(config.toJson()));

    await tester.pumpWidget(
      MaterialApp(
        home: CloudSyncDialog(
          database: database,
          localStateJson: '{}',
          onCloudState: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('manage-devices')), findsOneWidget);
    expect(find.byKey(const Key('pair-device')), findsOneWidget);
    expect(find.byKey(const Key('replace-recovery-key')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    database.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets('remote sync actions stay compact in phone landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-sync-landscape-',
    );
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      ),
    ))!;
    final config = SupabaseConfig(
      syncMode: 'supabase',
      url: 'http://127.0.0.1:1',
      publishableKey: 'publishable-key',
      userId: '20000000-0000-0000-0000-000000000002',
      workspaceId: '10000000-0000-0000-0000-000000000001',
      workspaceRole: 'admin',
      accessToken: 'cached-access-token',
      accessTokenExpiresAt: DateTime.now().toUtc().add(
        const Duration(hours: 1),
      ),
      refreshToken: 'refresh-token',
    );
    database.saveSyncConfig(jsonEncode(config.toJson()));

    await tester.pumpWidget(
      MaterialApp(
        home: CloudSyncDialog(
          database: database,
          localStateJson: '{}',
          onCloudState: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('close-remote-sync')), findsOneWidget);
    expect(find.byKey(const Key('sync-now')), findsOneWidget);
    expect(find.byKey(const Key('manage-devices')), findsOneWidget);
    expect(find.byKey(const Key('pair-device')), findsOneWidget);
    final syncIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('sync-now')),
        matching: find.byIcon(Icons.sync_rounded),
      ),
    );
    expect(syncIcon.size, 32);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    database.close();
    directory.deleteSync(recursive: true);
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

  testWidgets('new item history shows color and storage location', (
    tester,
  ) async {
    final item = InventoryItem(
      id: 'INV-HISTORY-DETAILS',
      name: 'Ocean Blue PLA',
      type: InventoryType.filament,
      compatibility: const ['1.75 mm'],
      added: DateTime(2026, 9, 2, 12),
      cost: 22.50,
      color: const Color(0xff8e75ff),
      itemColorName: '#1769AA',
      itemColorLabel: 'Ocean blue',
      storageLocationId: 'LOC-RACK',
    );
    final state = encodeWorkshopState(
      inventory: [item],
      vendors: const [],
      brands: const [],
      products: const [],
      locations: const [
        StockLocationRecord(id: 'LOC-RACK', name: 'Filament rack'),
      ],
      additionHistory: [
        AdditionHistoryEntry.fromItem(item, deviceName: 'Workshop tablet'),
      ],
    );

    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.tap(find.byKey(const Key('addition-history')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('addition-color-INV-HISTORY-DETAILS')),
        matching: find.text('Ocean blue'),
      ),
      findsNothing,
    );
    expect(find.text('Ocean blue · '), findsOneWidget);
    expect(
      find.byKey(const Key('addition-color-swatch-INV-HISTORY-DETAILS')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('addition-color-hex-INV-HISTORY-DETAILS')),
      findsOneWidget,
    );
    expect(find.text('#1769AA'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('addition-location-INV-HISTORY-DETAILS')),
        matching: find.text('Filament rack'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('addition-entry-INV-HISTORY-DETAILS')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ItemDetailsPanel), findsOneWidget);
    expect(find.byKey(const Key('edit-item-top')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new item history keeps missing details explicit on Android', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final item = InventoryItem(
      id: 'INV-HISTORY-MISSING',
      name: 'Unsorted fasteners with a comfortably long item name',
      type: InventoryType.fastener,
      compatibility: const [],
      added: DateTime(2026, 9, 2, 12),
      cost: 0,
      color: const Color(0xff8e75ff),
    );
    final state = encodeWorkshopState(
      inventory: [item],
      vendors: const [],
      brands: const [],
      products: const [],
      additionHistory: [AdditionHistoryEntry.fromItem(item)],
    );

    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.tap(find.byKey(const Key('addition-history')));
    await tester.pumpAndSettle();

    expect(find.text('No color'), findsWidgets);
    expect(find.text('No location'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleted new item history explains why it cannot be opened', (
    tester,
  ) async {
    final deletedItem = InventoryItem(
      id: 'INV-HISTORY-DELETED',
      name: 'Deleted sample item',
      type: InventoryType.other,
      compatibility: const [],
      added: DateTime(2026, 9, 2, 12),
      cost: 0,
      color: const Color(0xff8e75ff),
    );
    final state = encodeWorkshopState(
      inventory: const [],
      vendors: const [],
      brands: const [],
      products: const [],
      additionHistory: [AdditionHistoryEntry.fromItem(deletedItem)],
    );

    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.tap(find.byKey(const Key('addition-history')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('addition-deleted-INV-HISTORY-DELETED')),
      findsOneWidget,
    );
    expect(find.text('Deleted'), findsOneWidget);
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const Key('addition-entry-INV-HISTORY-DELETED')),
          )
          .onTap,
      isNull,
    );
    expect(tester.takeException(), isNull);
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

  testWidgets('alerts clear individually and mark all as read persists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-read-alerts-',
    );
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      ),
    ))!;
    final first = sampleInventory.first.copyWith(
      id: 'ALERT-FIRST',
      name: 'First low stack',
      quantity: 2,
      quantityAlertThreshold: 5,
    );
    final second = sampleInventory[1].copyWith(
      id: 'ALERT-SECOND',
      name: 'Second low stack',
      quantity: 1,
      quantityAlertThreshold: 3,
    );
    database.saveState(
      encodeWorkshopState(
        inventory: [first, second],
        vendors: starterVendors,
        brands: starterBrands,
        products: starterProducts,
      ),
    );
    database.saveSyncConfig(
      jsonEncode(
        const SupabaseConfig(
          syncMode: 'local',
          url: '',
          publishableKey: '',
        ).toJson(),
      ),
    );

    Future<void> mountApp() => tester.pumpWidget(
      InventorinatorApp(
        key: UniqueKey(),
        database: database,
        persistedState: database.loadState(),
      ),
    );

    await mountApp();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('moisture-alerts')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quantity-alert-ALERT-FIRST')), findsOneWidget);
    expect(
      find.byKey(const Key('quantity-alert-ALERT-SECOND')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('quantity-alert-ALERT-FIRST')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sidebar-item-name')), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('moisture-alerts')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quantity-alert-ALERT-FIRST')), findsNothing);
    expect(
      find.byKey(const Key('quantity-alert-ALERT-SECOND')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('mark-all-alerts-read')));
    await tester.pumpAndSettle();
    expect(find.text('No unread inventory alerts.'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await mountApp();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('moisture-alerts')));
    await tester.pumpAndSettle();
    expect(find.text('No unread inventory alerts.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    database.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets('low-stock alerts can be disabled per device', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-low-stock-alert-pref-',
    );
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      ),
    ))!;
    final item = sampleInventory.first.copyWith(
      id: 'LOW-STOCK-PREF',
      quantity: 1,
      quantityAlertThreshold: 5,
    );
    final state = encodeWorkshopState(
      inventory: [item],
      vendors: starterVendors,
      brands: starterBrands,
      products: starterProducts,
    );
    database.saveState(state);
    database.saveSyncConfig(
      jsonEncode(
        const SupabaseConfig(
          syncMode: 'local',
          url: '',
          publishableKey: '',
        ).toJson(),
      ),
    );

    await tester.pumpWidget(
      InventorinatorApp(database: database, persistedState: state),
    );
    await tester.tap(find.byKey(const Key('personalization-settings')));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('low-stock-alerts-personalization'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      database.loadBoolPreference('low_stock_alerts_enabled', fallback: true),
      isFalse,
    );
    Navigator.of(tester.element(toggle)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('moisture-alerts')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('quantity-alert-LOW-STOCK-PREF')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    database.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets('scanner accepts a QR payload and opens its item', (
    tester,
  ) async {
    await tester.pumpWidget(const InventorinatorApp());
    await tester.ensureVisible(find.byKey(const Key('open-scanner')));
    await tester.pumpAndSettle();
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

  testWidgets('scanner accepts a location QR and opens its inventory', (
    tester,
  ) async {
    final state = encodeWorkshopState(
      inventory: const [],
      vendors: const [],
      brands: const [],
      products: const [],
      locations: const [
        StockLocationRecord(id: 'LOC-SCAN', name: 'Scan shelf'),
      ],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.ensureVisible(find.byKey(const Key('open-scanner')));
    await tester.tap(find.byKey(const Key('open-scanner')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('manual-qr-code')),
      'inventorinator:location:LOC-SCAN',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location-details-LOC-SCAN')), findsOneWidget);
    expect(find.text('Scan shelf'), findsOneWidget);
    expect(
      find.text('No inventory is assigned to this area yet.'),
      findsOneWidget,
    );
  });

  testWidgets('ingest scan opens Add Item with the product barcode', (
    tester,
  ) async {
    await tester.pumpWidget(const InventorinatorApp());
    await tester.ensureVisible(find.byKey(const Key('open-scanner')));
    await tester.pumpAndSettle();
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
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('item-type')),
          )
          .initialValue,
      'type:other',
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

    await tester.scrollUntilVisible(
      find.text('Purple Silk PLA'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
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

  test('Shopify URL import uses the lightweight product endpoint', () {
    expect(
      shopifyProductEndpoint(
        Uri.parse(
          'https://shop.polymaker.com/products/polymaker-pla-pro?variant=41550910652473',
        ),
      ).toString(),
      'https://shop.polymaker.com/products/polymaker-pla-pro.js',
    );
    expect(
      shopifyProductEndpoint(
        Uri.parse(
          'https://shop.polymaker.com/en-eu/collections/pla/products/polymaker-pla-pro?variant=7',
        ),
      ).toString(),
      'https://shop.polymaker.com/en-eu/products/polymaker-pla-pro.js',
    );
  });

  test('URL import caps and deduplicates product image requests', () {
    expect(
      limitedProductImageUrls([
        'https://cdn.example/first.png',
        'https://cdn.example/first.png',
        'https://cdn.example/second.png',
        'https://cdn.example/third.png',
      ]),
      ['https://cdn.example/first.png', 'https://cdn.example/second.png'],
    );
  });

  test('Shopify URL import selects the requested variant', () {
    final product = extractShopifyProductMetadata({
      'title': 'Polymaker PLA Pro',
      'vendor': 'Polymaker',
      'description': '<p>Nozzle temperature: 210-230°C</p>',
      'featured_image': '//cdn.example/default.png',
      'options': ['Color', 'Size'],
      'variants': [
        {
          'id': 10,
          'public_title': 'Black / 1kg',
          'price': 2399,
          'barcode': '111',
          'featured_image': {'src': 'https://cdn.example/black.png'},
        },
        {
          'id': 20,
          'public_title': 'Purple / 1kg',
          'price': 2499,
          'barcode': '222',
          'featured_image': {'src': 'https://cdn.example/purple.png'},
        },
      ],
    }, Uri.parse('https://shop.example/products/pla?variant=20'));

    expect(product?['name'], 'Polymaker PLA Pro — Purple / 1kg');
    expect((product?['brand'] as Map?)?['name'], 'Polymaker');
    expect((product?['offers'] as Map?)?['price'], '24.99');
    expect(product?['gtin13'], '222');
    expect(product?['image'], 'https://cdn.example/purple.png');
    expect(product?['color'], 'Purple');
  });

  test('URL import extracts explicit filament color names and hex values', () {
    final color = extractProductColorMetadata({
      '@type': 'Product',
      'color': 'Galaxy Purple',
      'additionalProperty': [
        {'name': 'Color Hex', 'colorHex': '7b4cff'},
      ],
    }, '<span data-color-hex="#112233"></span>');

    expect(color?.label, 'Galaxy Purple');
    expect(color?.hex, '#7B4CFF');
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
    expect(
      smartMatchInventoryType(
        'Feedstock',
        typeAliases: const {InventoryType.filament: 'Feedstock'},
      ),
      InventoryType.filament,
    );
    expect(smartMatchInventoryType('unrelated machinery'), isNull);
    final parsed = parseRapidizerText(
      'Blue PLA filamnet 2 19.99\nE3D V6 heat break 1 14.95',
    );
    expect(parsed.errors, isEmpty);
    expect(parsed.items.first.name, 'Blue PLA');
    expect(parsed.items.first.type, InventoryType.filament);
    expect(parsed.items.last.name, 'E3D V6');
    expect(parsed.items.last.type, InventoryType.heatBreak);
    final zeroStockPart = parseRapidizerText(
      'Replacement duct printed part 0 0',
    );
    expect(zeroStockPart.errors, isEmpty);
    expect(zeroStockPart.items.single.quantity, 0);
    final zeroStockNozzle = parseRapidizerText('Future nozzle nozzle 0 0');
    expect(zeroStockNozzle.errors, isEmpty);
    expect(zeroStockNozzle.items.single.quantity, 0);
    final compactFilament = parseRapidizerText('Blue PLA Filament 22.85');
    expect(compactFilament.errors, isEmpty);
    expect(compactFilament.items.single.name, 'Blue PLA');
    expect(compactFilament.items.single.type, InventoryType.filament);
    expect(compactFilament.items.single.materialName, 'PLA');
    expect(compactFilament.items.single.itemColorLabel, 'Blue');
    expect(compactFilament.items.single.itemColorName, '#4C93FF');
    expect(compactFilament.items.single.quantity, 1);
    expect(compactFilament.items.single.price, 22.85);
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
      sourceUrls: ['https://example.com/insert'],
    );
    final kit = KitRecord(
      id: 'KIT-1',
      name: 'Voron toolhead rebuild',
      imageBytes: Uint8List.fromList([7, 8, 9]),
      sections: ['Toolhead', 'Frame'],
      sourceUrls: ['https://example.com/kit'],
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
    final machine = MachineRecord(
      id: 'MCH-1',
      name: 'Nut Buster',
      model: 'DIY',
      address: '',
      typeId: 'MT-PRESS',
      kitIds: {'KIT-1'},
      sourceUrls: const ['https://example.com/machine'],
      imageBytes: Uint8List.fromList([10, 11, 12]),
    );
    final decoded = decodeWorkshopState(
      encodeWorkshopState(
        inventory: [inventoryItem],
        vendors: const [],
        brands: const [],
        products: const [product],
        kits: [kit],
        builds: [build],
        machines: [machine],
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
    expect(decoded?.machines.single.imageBytes, [10, 11, 12]);
    expect(decoded?.machines.single.sourceUrls, [
      'https://example.com/machine',
    ]);
    expect(decoded?.kits.single.imageBytes, [7, 8, 9]);
    expect(decoded?.kits.single.sourceUrls, ['https://example.com/kit']);
    expect(decoded?.products.single.sourceUrls, ['https://example.com/insert']);
    expect(decoded?.inventory.single.quantity, 42);
    expect(decoded?.inventory.single.quantityAlertThreshold, 50);
    expect(decoded?.inventory.single.imageBytes, [1, 2, 3]);
    expect(decoded?.inventory.single.labelImageBytes, [4, 5, 6]);
    expect(decoded?.inventory.single.catalogProductId, 'PROD-INSERT');
  });

  test('filament purpose tags survive export and import', () {
    final item = sampleInventory.first.copyWith(
      type: InventoryType.filament,
      purposeTags: const ['Coextruded', 'Beauty prints only'],
    );
    final decoded = decodeWorkshopState(
      encodeWorkshopState(
        inventory: [item],
        vendors: const [],
        brands: const [],
        products: const [],
      ),
    )!;

    expect(decoded.inventory.single.purposeTags, [
      'Coextruded',
      'Beauty prints only',
    ]);
  });

  test('filament style entries survive export and import', () {
    final item = sampleInventory.first.copyWith(
      type: InventoryType.filament,
      styleEntries: const [
        FilamentStyleEntry(style: 'glitter'),
        FilamentStyleEntry(
          style: 'coextruded',
          colors: ['#FF0000', '#00FF00', '#0000FF'],
        ),
      ],
    );
    final decoded = decodeWorkshopState(
      encodeWorkshopState(
        inventory: [item],
        vendors: const [],
        brands: const [],
        products: const [],
      ),
    )!;

    final styleEntries = decoded.inventory.single.styleEntries;
    expect(styleEntries, hasLength(2));
    expect(styleEntries[0].style, 'glitter');
    expect(styleEntries[0].colors, isEmpty);
    expect(styleEntries[1].style, 'coextruded');
    expect(styleEntries[1].colors, ['#FF0000', '#00FF00', '#0000FF']);
  });

  test('carbon fiber style entries keep their form on export and import', () {
    final item = sampleInventory.first.copyWith(
      type: InventoryType.filament,
      styleEntries: const [
        FilamentStyleEntry(style: 'carbonFiber', carbonFiberForm: 'ground'),
      ],
    );
    final decoded = decodeWorkshopState(
      encodeWorkshopState(
        inventory: [item],
        vendors: const [],
        brands: const [],
        products: const [],
      ),
    )!;

    expect(
      decoded.inventory.single.styleEntries.single.carbonFiberForm,
      'ground',
    );
  });

  test('gradient style entries keep their name on export and import', () {
    final item = sampleInventory.first.copyWith(
      type: InventoryType.filament,
      styleEntries: const [
        FilamentStyleEntry(
          style: 'gradient',
          colors: ['#FF0000', '#0000FF'],
          gradientName: 'Sunset Fade',
        ),
      ],
    );
    final decoded = decodeWorkshopState(
      encodeWorkshopState(
        inventory: [item],
        vendors: const [],
        brands: const [],
        products: const [],
      ),
    )!;

    final entry = decoded.inventory.single.styleEntries.single;
    expect(entry.gradientName, 'Sunset Fade');
    expect(entry.colors, ['#FF0000', '#0000FF']);
  });

  test('coextruded strand names survive export and import', () {
    final item = sampleInventory.first.copyWith(
      type: InventoryType.filament,
      styleEntries: const [
        FilamentStyleEntry(
          style: 'coextruded',
          colors: ['#000000', '#FFFFFF'],
          colorNames: ['Black', 'White'],
        ),
      ],
    );
    final decoded = decodeWorkshopState(
      encodeWorkshopState(
        inventory: [item],
        vendors: const [],
        brands: const [],
        products: const [],
      ),
    )!;

    final entry = decoded.inventory.single.styleEntries.single;
    expect(entry.colorNames, ['Black', 'White']);
    expect(entry.colorNameAt(0), 'Black');
    expect(entry.colorNameAt(1), 'White');
  });

  testWidgets(
    'coextruded item cards show a pie chicklet with names on hover only',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = encodeWorkshopState(
        inventory: [
          InventoryItem(
            id: 'INV-DUAL-PLA',
            name: 'Dual PLA',
            type: InventoryType.filament,
            compatibility: const [],
            added: DateTime(2026),
            cost: 24,
            color: const Color(0xff000000),
            styleEntries: const [
              FilamentStyleEntry(
                style: 'coextruded',
                colors: ['#000000', '#FFFFFF'],
                colorNames: ['Black', 'White'],
              ),
            ],
          ),
        ],
        vendors: const [],
        brands: const [],
        products: const [],
      );
      await tester.pumpWidget(InventorinatorApp(persistedState: state));
      await tester.pumpAndSettle();

      // The strand names never render as always-on card text -- only via
      // hover tooltip -- and the chicklet is the pie painter, not a flat
      // swatch or a linear-gradient one.
      expect(find.text('Black + White'), findsNothing);
      expect(find.text('Black'), findsNothing);
      expect(find.text('White'), findsNothing);
      expect(find.byTooltip('Black + White'), findsWidgets);
      final chicklet = tester.widget(
        find.byKey(const Key('item-color-swatch-INV-DUAL-PLA')),
      );
      expect(chicklet.runtimeType.toString(), contains('PieColorChicklet'));
    },
  );

  testWidgets(
    'gradient item cards show the name inline, same as a regular color',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = encodeWorkshopState(
        inventory: [
          InventoryItem(
            id: 'INV-SUNSET-PLA',
            name: 'Sunset PLA',
            type: InventoryType.filament,
            compatibility: const [],
            added: DateTime(2026),
            cost: 24,
            color: const Color(0xffff0000),
            styleEntries: const [
              FilamentStyleEntry(
                style: 'gradient',
                colors: ['#FF0000', '#0000FF'],
                gradientName: 'Sunset Fade',
              ),
            ],
          ),
        ],
        vendors: const [],
        brands: const [],
        products: const [],
      );
      await tester.pumpWidget(InventorinatorApp(persistedState: state));
      await tester.pumpAndSettle();

      // A gradient has one name -- it's shown inline next to the chicklet,
      // just like a plain color name, not hidden behind a hover tooltip.
      expect(find.text('Sunset Fade'), findsOneWidget);
      expect(find.byTooltip('Sunset Fade'), findsNothing);
    },
  );

  testWidgets(
    "a gradient name label doesn't push the material badge off the card's "
    'right edge',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = encodeWorkshopState(
        inventory: [
          InventoryItem(
            id: 'INV-NAMED',
            name: 'Named gradient',
            type: InventoryType.filament,
            compatibility: const [],
            added: DateTime(2026),
            cost: 24,
            color: const Color(0xffff0000),
            materialName: 'PLA',
            styleEntries: const [
              FilamentStyleEntry(
                style: 'gradient',
                colors: ['#FF0000', '#0000FF'],
                gradientName: 'Maui',
              ),
            ],
          ),
          InventoryItem(
            id: 'INV-UNNAMED',
            name: 'Unnamed gradient',
            type: InventoryType.filament,
            compatibility: const [],
            added: DateTime(2026),
            cost: 24,
            color: const Color(0xffff0000),
            materialName: 'PLA',
            styleEntries: const [
              FilamentStyleEntry(
                style: 'gradient',
                colors: ['#FF0000', '#0000FF'],
              ),
            ],
          ),
        ],
        vendors: const [],
        brands: const [],
        products: const [],
      );
      await tester.pumpWidget(InventorinatorApp(persistedState: state));
      await tester.pumpAndSettle();

      // Measure each badge's inset from its own card's right edge -- cards
      // can land in different grid columns, so compare offsets within each
      // card rather than raw screen coordinates. The "Maui" label must not
      // eat into the trailing space reserved for the badge.
      double insetFromCardRight(String itemId) {
        final card = find.byKey(Key('inventory-card-$itemId'));
        final badge = find.descendant(of: card, matching: find.text('PLA'));
        return tester.getTopRight(card).dx - tester.getTopRight(badge).dx;
      }

      expect(
        insetFromCardRight('INV-NAMED'),
        closeTo(insetFromCardRight('INV-UNNAMED'), 1),
      );
    },
  );

  testWidgets(
    'filament style editor supports coextruded colors and a second style',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const InventorinatorApp());
      await tester.tap(find.byKey(const Key('add-item')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filament').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-filament-style')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filament-style-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coextruded').last);
      await tester.pumpAndSettle();

      // Coextruded starts at two strands -- a single-strand coextrusion isn't
      // a real thing -- and has no gradient name field, that's gradient-only.
      expect(find.byKey(const Key('filament-style-count-0-1')), findsNothing);
      expect(find.byKey(const Key('filament-style-color-0-0')), findsOneWidget);
      expect(find.byKey(const Key('filament-style-color-0-1')), findsOneWidget);
      expect(find.byKey(const Key('filament-style-color-0-2')), findsNothing);
      expect(
        find.byKey(const Key('filament-style-gradient-name-0')),
        findsNothing,
      );

      // Each strand gets its own name slot alongside its chicklet.
      expect(
        find.byKey(const Key('filament-style-color-name-0-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('filament-style-color-name-0-1')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('filament-style-color-name-0-0')),
        'Black',
      );
      await tester.enterText(
        find.byKey(const Key('filament-style-color-name-0-1')),
        'White',
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('filament-style-count-0-3')),
      );
      await tester.tap(find.byKey(const Key('filament-style-count-0-3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('filament-style-color-0-2')), findsOneWidget);
      expect(
        find.byKey(const Key('filament-style-color-name-0-2')),
        findsOneWidget,
      );
      // Naming the third strand doesn't disturb the first two.
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('filament-style-color-name-0-0')),
            )
            .initialValue,
        'Black',
      );

      // A second style can be added and configured independently.
      await tester.tap(find.byKey(const Key('add-filament-style')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-filament-style')), findsNothing);
      await tester.tap(find.byKey(const Key('filament-style-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carbon Fiber').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('filament-style-carbon-form-1')),
        findsOneWidget,
      );
      // The first style's color count is unaffected by the second entry.
      expect(find.byKey(const Key('filament-style-color-0-2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('remove-filament-style-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-filament-style')), findsOneWidget);
      expect(find.byKey(const Key('filament-style-1')), findsNothing);
    },
  );

  testWidgets(
    'gradient style renders a live gradient preview with stop handles',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const InventorinatorApp());
      await tester.tap(find.byKey(const Key('add-item')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filament').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-filament-style')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filament-style-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gradient').last);
      await tester.pumpAndSettle();

      // The gradient name field only appears for the gradient style, above
      // the style dropdown itself.
      expect(
        find.byKey(const Key('filament-style-gradient-name-0')),
        findsOneWidget,
      );
      final nameTop = tester
          .getTopLeft(find.byKey(const Key('filament-style-gradient-name-0')))
          .dy;
      final dropdownTop = tester
          .getTopLeft(find.byKey(const Key('filament-style-0')))
          .dy;
      expect(nameTop, lessThan(dropdownTop));
      await tester.enterText(
        find.byKey(const Key('filament-style-gradient-name-0')),
        'Sunset Fade',
      );
      await tester.pumpAndSettle();

      // Gradient starts at two stops with a rendered blend, not bare chicklets.
      expect(find.byKey(const Key('filament-style-color-0-0')), findsOneWidget);
      expect(find.byKey(const Key('filament-style-color-0-1')), findsOneWidget);
      final container = tester
          .widgetList<Container>(find.byType(Container))
          .firstWhere(
            (widget) =>
                widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).gradient
                    is LinearGradient,
          );
      expect(
        ((container.decoration! as BoxDecoration).gradient! as LinearGradient)
            .colors,
        hasLength(2),
      );

      await tester.ensureVisible(
        find.byKey(const Key('filament-style-count-0-3')),
      );
      await tester.tap(find.byKey(const Key('filament-style-count-0-3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('filament-style-color-0-2')), findsOneWidget);
    },
  );

  testWidgets('kit package import plan creates zero stock and is idempotent', (
    tester,
  ) async {
    final package = parseInventorinatorKitPackage(
      File('examples/example.inventorinator-kit.json').readAsStringSync(),
    ).package!;
    final emptyState = encodeWorkshopState(
      inventory: const [],
      vendors: const [],
      brands: const [],
      products: const [],
      materials: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryHome(
          key: const ValueKey('empty-import-state'),
          persistedState: emptyState,
        ),
      ),
    );
    final dynamic homeState = tester.state(find.byType(InventoryHome));
    final dynamic firstPlan = homeState.createKitPackageImportPlan(package);

    expect(firstPlan.newInventoryItems, hasLength(2));
    expect(
      (firstPlan.newInventoryItems as List<InventoryItem>).every(
        (item) => item.quantity == 0,
      ),
      isTrue,
    );
    expect(firstPlan.products, hasLength(2));
    expect(firstPlan.kits.single.bom, hasLength(2));
    expect(firstPlan.kits.single.sections, ['Frame', 'Toolhead']);
    expect(firstPlan.kits.single.sourceUrls, isNotEmpty);
    expect(firstPlan.machines.single.kitIds, {firstPlan.kits.single.id});

    final importedState = encodeWorkshopState(
      inventory: (firstPlan.inventory as List<InventoryItem>),
      vendors: const [],
      brands: (firstPlan.brands as List<BrandRecord>),
      materials: (firstPlan.materials as List<MaterialRecord>),
      products: (firstPlan.products as List<CatalogProduct>),
      machineTypes: (firstPlan.machineTypes as List<MachineTypeRecord>),
      machines: (firstPlan.machines as List<MachineRecord>),
      kits: (firstPlan.kits as List<KitRecord>),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryHome(
          key: const ValueKey('populated-import-state'),
          persistedState: importedState,
        ),
      ),
    );
    final dynamic importedHomeState = tester.state(find.byType(InventoryHome));
    final dynamic secondPlan = importedHomeState.createKitPackageImportPlan(
      package,
    );

    expect(secondPlan.newInventoryItems, isEmpty);
    expect(secondPlan.newProductCount, 0);
    expect(secondPlan.products, hasLength(2));
    expect(secondPlan.kits, hasLength(1));
    expect(secondPlan.kitWillUpdate, isTrue);
  });

  testWidgets(
    'kit package import can map a differently named and typed BOM line to inventory',
    (tester) async {
      final package = parseInventorinatorKitPackage(
        File('examples/example.inventorinator-kit.json').readAsStringSync(),
      ).package!;
      final existingItem = InventoryItem(
        id: 'INV-EXISTING-SCREW',
        name: 'M3 x 10 SHCS',
        type: InventoryType.other,
        compatibility: const [],
        added: DateTime(2026, 8, 30),
        cost: .12,
        color: const Color(0xff8e75ff),
        quantity: 40,
      );
      final state = encodeWorkshopState(
        inventory: [existingItem],
        vendors: const [],
        brands: const [],
        products: const [],
        materials: const [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryHome(
            key: const ValueKey('manual-import-match-state'),
            persistedState: state,
          ),
        ),
      );
      final dynamic homeState = tester.state(find.byType(InventoryHome));
      final dynamic plan = homeState.createKitPackageImportPlan(
        package,
        inventoryMatchesByPartId: const {'m3x10-screw': 'INV-EXISTING-SCREW'},
      );

      expect(plan.newInventoryItems, hasLength(1));
      expect(plan.inventory, hasLength(2));
      final matched = (plan.inventory as List<InventoryItem>).singleWhere(
        (item) => item.id == existingItem.id,
      );
      expect(matched.name, existingItem.name);
      expect(matched.type, existingItem.type);
      expect(matched.quantity, 40);
      expect(matched.catalogProductId, isNotEmpty);
      expect(plan.matchedInventoryIdsByPartId['m3x10-screw'], existingItem.id);
      expect(plan.kits.single.bom.first.productId, matched.catalogProductId);
    },
  );

  testWidgets(
    'spreadsheet-style JSON creates ordinary inventory items and materials',
    (tester) async {
      final parsed = parseInventoryJson(
        jsonEncode({
          'items': [
            {
              'Item Name': 'Blue PLA Filament',
              'Item Type': 'Filament',
              'Qty': '0',
              'Unit Price': r'$22.85',
              'Material': 'PLA+',
              'Color Hex': '#287BDE',
              'Color Name': 'Ocean Blue',
              'Brand': 'Example Brand',
              'Vendor': 'Example Store',
              'Storage Location': 'Shelf A',
              'AMS Compatible': 'yes',
              'Compatible With': 'MK3S; XL',
            },
          ],
        }),
      );
      expect(parsed.errors, isEmpty);
      expect(parsed.items.single.name, 'Blue PLA Filament');
      expect(parsed.items.single.quantity, 0);
      expect(parsed.items.single.cost, 22.85);
      expect(parsed.items.single.compatibility, ['MK3S', 'XL']);
      expect(parsed.items.single.imageUrl, isEmpty);

      final emptyState = encodeWorkshopState(
        inventory: const [],
        vendors: const [],
        brands: const [],
        products: const [],
        materials: const [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryHome(
            key: const ValueKey('inventory-json-import-state'),
            persistedState: emptyState,
          ),
        ),
      );
      final dynamic homeState = tester.state(find.byType(InventoryHome));
      final dynamic prepared = homeState.prepareInventoryJsonImport(
        parsed.items,
      );
      expect(prepared.errors, isEmpty);
      expect(prepared.items, hasLength(1));
      expect(prepared.newMaterials, hasLength(1));
      expect(prepared.newVendors, hasLength(1));
      expect(prepared.newBrands, hasLength(1));
      expect(prepared.newBrands.single.vendorIds, {
        prepared.newVendors.single.id,
      });
      expect(prepared.newBrands.single.categories, {InventoryType.filament});
      final item = (prepared.items as List<InventoryItem>).single;
      expect(item.type, InventoryType.filament);
      expect(item.quantity, 0);
      expect(item.materialName, 'PLA+');
      expect(item.itemColorName, '#287BDE');
      expect(item.itemColorLabel, 'Ocean Blue');
      expect(item.amsCompatible, isTrue);
      expect(item.storageLocation, 'Shelf A');
    },
  );

  test('inventory JSON reports bad rows without importing partial data', () {
    final parsed = parseInventoryJson(
      '[{"name":"Valid"},{"name":"Broken","quantity":"lots"}]',
    );
    expect(parsed.items, hasLength(1));
    expect(parsed.errors.single, contains('Row 2'));
    expect(parsed.isValid, isFalse);
  });

  testWidgets(
    'Atomic Filament PLA example is accepted by the inventory importer',
    (tester) async {
      final parsed = parseInventoryJson(
        File('examples/atomic-filament-pla.inventory.json').readAsStringSync(),
      );

      expect(parsed.errors, isEmpty);
      expect(parsed.items, hasLength(75));
      expect(parsed.items.every((item) => item.typeName == 'Filament'), isTrue);
      expect(parsed.items.every((item) => item.quantity == 0), isTrue);
      expect(
        parsed.items.every((item) => item.brand == 'Atomic Filament'),
        isTrue,
      );
      expect(parsed.items.every((item) => item.amsCompatible), isTrue);
      expect(
        parsed.items.every(
          (item) => item.imageUrl.startsWith('https://cdn.shopify.com/'),
        ),
        isTrue,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: InventoryHome(
            key: const ValueKey('atomic-pla-json-import-state'),
            persistedState: encodeWorkshopState(
              inventory: const [],
              vendors: const [],
              brands: const [],
              products: const [],
              materials: const [],
            ),
          ),
        ),
      );
      final dynamic homeState = tester.state(find.byType(InventoryHome));
      final dynamic prepared = homeState.prepareInventoryJsonImport(
        parsed.items,
      );
      expect(prepared.errors, isEmpty);
      expect(prepared.items, hasLength(75));
      expect(prepared.newMaterials, hasLength(1));
      expect(prepared.newVendors, hasLength(1));
      expect(prepared.newVendors.single.name, 'Atomic Filament');
      expect(prepared.newVendors.single.isBrand, isTrue);
      expect(prepared.newBrands, hasLength(1));
      expect(prepared.newBrands.single.name, 'Atomic Filament');
      expect(prepared.newBrands.single.vendorIds, {
        prepared.newVendors.single.id,
      });
      expect(prepared.newBrands.single.categories, {InventoryType.filament});
    },
  );

  test(
    'inventory JSON downloads listed images and skips absent images',
    () async {
      final parsed = parseInventoryJson(
        jsonEncode({
          'items': [
            {
              'Item Name': 'With image',
              'Image URL': 'https://example.com/product.png',
            },
            {'Item Name': 'Without image'},
          ],
        }),
      );
      final sourceItems = [
        sampleInventory.first.copyWith(id: 'with-image', imageBytes: null),
        sampleInventory.first.copyWith(id: 'without-image', imageBytes: null),
      ];
      final pngBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );

      final images = await downloadInventoryJsonImages(
        sourceItems,
        parsed.items,
        client: MockClient(
          (_) async => http.Response.bytes(
            pngBytes,
            200,
            headers: {'content-type': 'image/png'},
          ),
        ),
      );

      expect(images.imported, 1);
      expect(images.failed, 0);
      expect(images.items.first.imageBytes, pngBytes);
      expect(images.items.first.thumbnailBytes, isNotEmpty);
      expect(images.items.last.imageBytes, isNull);
      expect(images.items.last.thumbnailBytes, isNull);
    },
  );

  test('inventory JSON rejects invalid image URLs', () {
    final parsed = parseInventoryJson(
      '[{"Item Name":"Broken photo","Image URL":"not a URL"}]',
    );

    expect(parsed.isValid, isFalse);
    expect(parsed.errors.single, contains('Image URL'));
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

    final itemName = tester.getRect(find.byKey(const Key('item-name')));
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
    expect(itemName.bottom, lessThan(quantity.top));
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

  test('filament spool profile survives persistence', () {
    final item = InventoryItem(
      id: 'INV-BIG-SPOOL',
      name: 'Production PLA',
      type: InventoryType.filament,
      compatibility: const [],
      added: DateTime(2026),
      cost: 80,
      color: Colors.purple,
      itemColorName: 'Purple',
      itemColorLabel: 'Royal Purple',
      spoolTypeId: 'SPOOL-5000G',
      amsCompatible: true,
      spoolTareWeightGrams: 248,
      spoolOuterDiameterMm: 200,
      spoolWidthMm: 68,
      spoolHoleDiameterMm: 55,
      refill: true,
      masterSpool: 'Polymaker MasterSpool',
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
    expect(decoded.inventory.single.itemColorName, 'Purple');
    expect(decoded.inventory.single.itemColorLabel, 'Royal Purple');
    expect(decoded.inventory.single.amsCompatible, isTrue);
    expect(decoded.inventory.single.spoolTareWeightGrams, 248);
    expect(decoded.inventory.single.spoolOuterDiameterMm, 200);
    expect(decoded.inventory.single.spoolWidthMm, 68);
    expect(decoded.inventory.single.spoolHoleDiameterMm, 55);
    expect(decoded.inventory.single.refill, isTrue);
    expect(decoded.inventory.single.masterSpool, 'Polymaker MasterSpool');
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

  testWidgets('filament editor exposes the physical spool profile', (
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
              spoolTareWeightGrams: 240,
              spoolOuterDiameterMm: 200,
              spoolWidthMm: 68,
              spoolHoleDiameterMm: 55,
              refill: true,
              masterSpool: 'Reusable spool',
              spoolMaterialId: 'MAT-SPOOL-CARDBOARD',
              spoolMaterialName: 'Cardboard',
              masterSpoolMaterialId: 'MAT-MASTER-PETG',
              masterSpoolMaterialName: 'PETG',
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
    expect(find.byKey(const Key('spool-tare-weight')), findsOneWidget);
    expect(find.byKey(const Key('spool-outer-diameter')), findsOneWidget);
    expect(find.byKey(const Key('spool-width')), findsOneWidget);
    expect(find.byKey(const Key('spool-hole-diameter')), findsOneWidget);
    expect(find.byKey(const Key('spool-material')), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('filament-refill')))
          .value,
      isTrue,
    );
    expect(find.byKey(const Key('master-spool')), findsOneWidget);
    expect(find.byKey(const Key('master-spool-material')), findsOneWidget);
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
      materialId: 'MAT-NOZ-HARDENED',
      materialName: 'Hardened steel',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 272,
            child: InventoryCard(item: item, onOpen: () {}, onAction: (_) {}),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('item-quantity-INV-M2X8')), findsOneWidget);
    final quantityBadge = tester.widget<Container>(
      find.byKey(const Key('item-quantity-INV-M2X8')),
    );
    expect(
      (quantityBadge.decoration! as BoxDecoration).color!.a,
      greaterThan(.8),
    );
    final card = find.byKey(const Key('inventory-card-INV-M2X8'));
    final timer = find.byKey(const Key('inventory-card-timer-INV-M2X8'));
    expect(timer, findsOneWidget);
    expect(tester.getCenter(timer).dy, lessThan(tester.getCenter(card).dy));
    expect(find.text('×18'), findsOneWidget);
    final typeRow = find.byKey(const Key('item-type-row-INV-M2X8'));
    final priceRow = find.byKey(const Key('item-price-row-INV-M2X8'));
    expect(typeRow, findsOneWidget);
    expect(priceRow, findsOneWidget);
    expect(
      tester.getCenter(typeRow).dy,
      lessThan(tester.getCenter(priceRow).dy),
    );
    final material = find.byKey(const Key('item-material-INV-M2X8'));
    expect(material, findsOneWidget);
    expect(
      tester.getCenter(material).dx,
      greaterThan(tester.getCenter(card).dx),
    );
    expect(
      tester.getCenter(material).dy,
      greaterThan(tester.getCenter(card).dy),
    );
    expect(
      tester.getRect(card).right - tester.getRect(material).right,
      lessThanOrEqualTo(22),
    );
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

  testWidgets('status indicator is hidden when quantity is zero', (
    tester,
  ) async {
    final item = sampleInventory.first.copyWith(quantity: 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 272,
            child: InventoryCard(
              item: item,
              showStatus: true,
              onOpen: () {},
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(Key('inventory-card-timer-${item.id}')), findsNothing);
  });

  testWidgets('card size slider resizes only the mosaic cards', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.pumpAndSettle();

    final firstCard = find.byType(InventoryCard).first;
    final initialHeight = tester.getSize(firstCard).height;
    final initialWidth = tester.getSize(firstCard).width;
    expect(initialHeight, closeTo(initialWidth, .1));
    expect(find.byKey(const Key('card-size-slider')), findsOneWidget);
    final slider = tester.widget<Slider>(
      find.byKey(const Key('card-size-slider')),
    );
    expect(slider.divisions, isNull);
    expect(slider.min, 75);
    expect(slider.max, 150);

    await tester.drag(
      find.byKey(const Key('card-size-slider')),
      const Offset(500, 0),
    );
    await tester.pump();
    expect(
      tester.widget<Slider>(find.byKey(const Key('card-size-slider'))).value,
      greaterThan(100),
    );
    final resizedCard = tester.getSize(firstCard);
    expect(resizedCard.height, greaterThan(initialHeight));
    expect(resizedCard.height, closeTo(resizedCard.width, .1));
    await tester.pump(const Duration(milliseconds: 1050));
    expect(tester.getSize(firstCard).height, closeTo(resizedCard.height, .1));

    await tester.tap(find.byIcon(Icons.view_agenda_outlined));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card-size-slider')), findsNothing);
  });

  testWidgets('smallest mosaic cards do not overflow', (tester) async {
    tester.view.physicalSize = const Size(412, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      InventorinatorApp(
        persistedState: encodeWorkshopState(
          inventory: const [],
          vendors: const [],
          brands: const [],
          products: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('card-size-slider')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('item color is only the no-image thumbnail', (tester) async {
    final item = InventoryItem(
      id: 'INV-WHITE-PLA',
      name: 'White PLA',
      type: InventoryType.filament,
      compatibility: const [],
      added: DateTime(2026),
      cost: 20,
      color: const Color(0xff7455ff),
      itemColorName: 'White',
    );
    Widget card(InventoryItem value) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 260,
          child: InventoryCard(item: value, onOpen: () {}, onAction: (_) {}),
        ),
      ),
    );

    await tester.pumpWidget(card(item));
    expect(
      find.byKey(const Key('item-color-swatch-INV-WHITE-PLA')),
      findsOneWidget,
    );
    final swatch = tester.widget<Container>(
      find.byKey(const Key('item-color-swatch-INV-WHITE-PLA')),
    );
    expect((swatch.decoration! as BoxDecoration).border, isNull);
    final quantityBadge = tester.widget<Container>(
      find.byKey(const Key('item-quantity-INV-WHITE-PLA')),
    );
    expect(
      ((quantityBadge.decoration! as BoxDecoration).border! as Border)
          .top
          .color,
      const Color(0xff686a76),
    );
    expect(
      tester.widget<Text>(find.text('FILAMENT')).style?.color,
      const Color(0xff9da5b7),
    );

    await tester.pumpWidget(
      card(
        item.copyWith(
          imageBytes: Uint8List.fromList(
            img.encodePng(img.Image(width: 1, height: 1)),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('item-product-image-INV-WHITE-PLA')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('item-color-swatch-INV-WHITE-PLA')),
      findsNothing,
    );

    final resin = item.copyWith(
      id: 'INV-PINK-RESIN',
      name: 'Prusa Pink',
      type: InventoryType.resin,
      color: itemColorPalette['Pink'],
      itemColorName: 'Pink',
    );
    await tester.pumpWidget(card(resin));
    await tester.pump();
    final resinSwatch = tester.widget<Container>(
      find.byKey(const Key('item-color-swatch-INV-PINK-RESIN')),
    );
    expect(
      (resinSwatch.decoration! as BoxDecoration).color,
      itemColorPalette['Pink'],
    );
    expect(
      tester.widget<Text>(find.text('RESIN')).style?.color,
      const Color(0xff9da5b7),
    );

    final hexItem = resin.copyWith(id: 'INV-HEX-RESIN', itemColorName: '#0F8');
    await tester.pumpWidget(card(hexItem));
    await tester.pump();
    final hexSwatch = tester.widget<Container>(
      find.byKey(const Key('item-color-swatch-INV-HEX-RESIN')),
    );
    expect(
      (hexSwatch.decoration! as BoxDecoration).color,
      const Color(0xff00ff88),
    );
  });

  testWidgets('item age renders only in the sidebar', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = encodeWorkshopState(
      inventory: [sampleInventory.first.copyWith(id: 'INV-AGE-BELOW')],
      vendors: const [],
      brands: const [],
      products: const [],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('inventory-card-age-INV-AGE-BELOW')),
      findsNothing,
    );

    await tester.tap(find.byIcon(Icons.view_agenda_outlined));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('inventory-row-age-INV-AGE-BELOW')),
      findsNothing,
    );

    await tester.tap(find.text(sampleInventory.first.name));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sidebar-added-to-inventory')), findsOneWidget);
  });

  test('legacy item names backfill color metadata once', () {
    final legacy = jsonDecode(
      encodeWorkshopState(
        inventory: [
          InventoryItem(
            id: 'INV-PINK-RESIN',
            name: 'Prusa Pink',
            type: InventoryType.resin,
            compatibility: const [],
            added: DateTime(2026),
            cost: 20,
            color: const Color(0xffd15cff),
          ),
        ],
        vendors: const [],
        brands: const [],
        products: const [],
      ),
    ) as Map<String, dynamic>;
    legacy['schemaVersion'] = 3;
    (legacy['inventory'] as List<dynamic>).single.remove('itemColorName');

    expect(
      decodeWorkshopState(jsonEncode(legacy))!.inventory.single.itemColorName,
      'Pink',
    );

    legacy['schemaVersion'] = 4;
    expect(
      decodeWorkshopState(jsonEncode(legacy))!.inventory.single.itemColorName,
      isEmpty,
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

  test('added date sort supports both directions with stable ties', () {
    final older = sampleInventory.first.copyWith(
      id: 'A',
      added: DateTime(2026, 1, 1),
    );
    final newer = sampleInventory.first.copyWith(
      id: 'B',
      added: DateTime(2026, 2, 1),
    );
    final newerTie = sampleInventory.first.copyWith(
      id: 'C',
      added: DateTime(2026, 2, 1),
    );
    final ascending = [newerTie, newer, older]
      ..sort(
        (left, right) => compareInventoryItems(
          left,
          right,
          sort: InventorySort.addedDate,
          ascending: true,
        ),
      );
    final descending = [older, newerTie, newer]
      ..sort(
        (left, right) => compareInventoryItems(
          left,
          right,
          sort: InventorySort.addedDate,
          ascending: false,
        ),
      );

    expect(ascending.map((item) => item.id), ['A', 'B', 'C']);
    expect(descending.map((item) => item.id), ['B', 'C', 'A']);
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
    expect(find.byKey(const Key('debug-new-item-glow')), findsOneWidget);
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

  testWidgets('personalization settings live outside the debug panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());

    await tester.tap(find.byKey(const Key('personalization-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Personalization settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.byKey(const Key('appearance-dark')), findsOneWidget);
    expect(find.byKey(const Key('appearance-light')), findsOneWidget);
    expect(find.text('Color'), findsOneWidget);
    expect(find.byKey(const Key('color-theme-darkPurple')), findsOneWidget);
    expect(find.byKey(const Key('color-theme-darkRed')), findsOneWidget);
    expect(find.byKey(const Key('color-theme-darkBlue')), findsOneWidget);
    expect(find.byKey(const Key('color-theme-darkGreen')), findsOneWidget);
    expect(find.byKey(const Key('color-theme-darkBlack')), findsOneWidget);
    expect(find.byKey(const Key('color-theme-darkBrown')), findsOneWidget);
    expect(find.byKey(const Key('color-theme-custom')), findsOneWidget);
    expect(
      find.byKey(const Key('personalization-notifications-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('personalization-sounds-section')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('alert-sounds-toggle')), findsOneWidget);
    expect(
      find.byKey(const Key('low-stock-alerts-personalization')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('hide-zero-personalization')), findsOneWidget);
    expect(find.byKey(const Key('sync-chime-personalization')), findsOneWidget);
    expect(
      find.byKey(const Key('drying-chime-personalization')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('moisture-chime-personalization')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('alert-sound-profile')), findsOneWidget);
    expect(find.byKey(const Key('alert-sound-volume')), findsOneWidget);
    expect(find.byKey(const Key('alert-sound-recurrence')), findsOneWidget);
    expect(find.byKey(const Key('preview-alert-sound')), findsOneWidget);
    expect(
      find.byKey(const Key('personalization-effects-section')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('card-effects-toggle')), findsOneWidget);
    expect(find.byKey(const Key('low-stock-effects-toggle')), findsOneWidget);
    expect(find.byKey(const Key('moisture-effects-toggle')), findsOneWidget);
    expect(find.byKey(const Key('remote-sync-effects-toggle')), findsOneWidget);
    expect(find.byKey(const Key('search-glow-toggle')), findsOneWidget);
    expect(find.byKey(const Key('new-item-glow-toggle')), findsOneWidget);
    final photoToggle = find.byKey(const Key('photo-cards-toggle'));
    expect(photoToggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(photoToggle).value, isFalse);
    expect(find.text('Performance'), findsOneWidget);
    expect(find.byKey(const Key('custom-icon-animation-mode')), findsOneWidget);
    expect(find.text('On hover or touch · Recommended'), findsOneWidget);
    expect(find.byKey(const Key('animation-duration')), findsOneWidget);
    expect(find.byKey(const Key('animation-recurrence')), findsOneWidget);
    expect(find.byKey(const Key('debug-item')), findsNothing);
  });

  testWidgets('personalization settings fit Android phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    expect(tester.takeException(), isNull, reason: 'initial 360px layout');

    await tester.drag(
      find.byKey(const Key('compact-header-actions')),
      const Offset(-320, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'scrolled header layout');
    await tester.tap(find.byKey(const Key('personalization-settings')));
    await tester.pumpAndSettle();

    expect(find.text('Personalization settings'), findsOneWidget);
    expect(find.byKey(const Key('custom-icon-animation-mode')), findsOneWidget);
    expect(find.byKey(const Key('animation-duration')), findsOneWidget);
    final layoutException = tester.takeException();
    expect(
      layoutException,
      isNull,
      reason: layoutException is FlutterError
          ? layoutException.toStringDeep()
          : '$layoutException',
    );
  });

  testWidgets('personalization can silence alert sounds on this device', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-alert-sounds-',
    );
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      ),
    ))!;
    database.saveState(
      encodeWorkshopState(
        inventory: const [],
        vendors: const [],
        brands: const [],
        products: const [],
      ),
    );
    database.saveSyncConfig(
      jsonEncode(
        const SupabaseConfig(
          syncMode: 'local',
          url: '',
          publishableKey: '',
        ).toJson(),
      ),
    );

    await tester.pumpWidget(InventorinatorApp(database: database));
    await tester.tap(find.byKey(const Key('personalization-settings')));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('alert-sounds-toggle'));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(
      database.loadBoolPreference('alert_sounds_enabled', fallback: true),
      isFalse,
    );
    expect(find.byKey(const Key('all-alert-sounds-muted')), findsOneWidget);

    for (final key in const [
      'sync-chime-personalization',
      'drying-chime-personalization',
      'moisture-chime-personalization',
    ]) {
      final toggle = find.byKey(Key(key));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }
    expect(
      database.loadBoolPreference('sync_chime_enabled', fallback: true),
      isFalse,
    );
    expect(
      database.loadBoolPreference(
        'drying_complete_chime_enabled',
        fallback: true,
      ),
      isFalse,
    );
    expect(
      database.loadBoolPreference(
        'moisture_alert_chime_enabled',
        fallback: true,
      ),
      isFalse,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    database.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets('color theme changes live and persists', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-color-theme-',
    );
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      ),
    ))!;
    database.saveState(
      encodeWorkshopState(
        inventory: const [],
        vendors: const [],
        brands: const [],
        products: const [],
      ),
    );
    database.saveSyncConfig(
      jsonEncode(
        const SupabaseConfig(
          syncMode: 'local',
          url: '',
          publishableKey: '',
        ).toJson(),
      ),
    );

    await tester.pumpWidget(
      InventorinatorApp(
        database: database,
        persistedState: database.loadState(),
      ),
    );
    await tester.tap(find.byKey(const Key('personalization-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearance-light')));
    await tester.pumpAndSettle();

    final lightApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final lightPurplePalette = InventorinatorColors.forTheme(
      AppColorTheme.darkPurple,
      brightness: AppBrightnessMode.light,
    );
    expect(lightApp.theme!.brightness, Brightness.light);
    expect(lightApp.theme!.scaffoldBackgroundColor, lightPurplePalette.canvas);
    expect(lightApp.theme!.colorScheme.onSurface, const Color(0xff211a2d));
    expect(
      database.loadStringPreference('app_brightness_mode', fallback: ''),
      AppBrightnessMode.light.name,
    );

    await tester.tap(find.byKey(const Key('color-theme-darkRed')));
    await tester.pumpAndSettle();

    final lightRedApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(lightRedApp.theme!.brightness, Brightness.light);
    expect(
      lightRedApp.theme!.scaffoldBackgroundColor,
      InventorinatorColors.forTheme(
        AppColorTheme.darkRed,
        brightness: AppBrightnessMode.light,
      ).canvas,
    );
    expect(
      database.loadStringPreference('app_color_theme', fallback: ''),
      AppColorTheme.darkRed.name,
    );
    expect(
      database.loadStringPreference('app_brightness_mode', fallback: ''),
      AppBrightnessMode.light.name,
    );

    await tester.tap(find.byKey(const Key('appearance-dark')));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.scaffoldBackgroundColor, const Color(0xff1b0c10));
    expect(app.theme!.colorScheme.primary, const Color(0xffff879a));
    expect(
      app.theme!.extension<InventorinatorColors>()!.surface,
      const Color(0xff27171b),
    );
    expect(
      database.loadStringPreference('app_color_theme', fallback: ''),
      AppColorTheme.darkRed.name,
    );

    await tester.tap(find.byKey(const Key('color-theme-custom')));
    await tester.pumpAndSettle();
    expect(find.text('Choose theme color'), findsOneWidget);
    expect(find.byKey(const Key('clear-item-color')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('item-color-picker-hex')),
      '#00AEEF',
    );
    await tester.tap(find.byKey(const Key('use-item-color')));
    await tester.pumpAndSettle();

    final customPalette = InventorinatorColors.fromCustomColor(
      const Color(0xff00aeef),
    );
    final customApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(customApp.theme!.scaffoldBackgroundColor, customPalette.canvas);
    expect(customApp.theme!.colorScheme.primary, customPalette.accent);
    expect(
      database.loadStringPreference('app_color_theme', fallback: ''),
      AppColorTheme.custom.name,
    );
    expect(
      database.loadStringPreference('app_custom_theme_color', fallback: ''),
      '#00AEEF',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    database.close();
    directory.deleteSync(recursive: true);
  });

  test('resting glass buttons derive their color from the active theme', () {
    final red = themedGlassRestingColors(
      InventorinatorColors.palettes[AppColorTheme.darkRed]!,
      light: false,
    );
    final blue = themedGlassRestingColors(
      InventorinatorColors.palettes[AppColorTheme.darkBlue]!,
      light: false,
    );

    expect(red, isNot(blue));
    expect(
      red.first,
      InventorinatorColors.palettes[AppColorTheme.darkRed]!.base.withValues(
        alpha: .34,
      ),
    );
    expect(
      blue.first,
      InventorinatorColors.palettes[AppColorTheme.darkBlue]!.base.withValues(
        alpha: .34,
      ),
    );
  });

  testWidgets('photo card mode uses a cached thumbnail as its background', (
    tester,
  ) async {
    final imageBytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 2)),
    );
    final item = sampleInventory.first.copyWith(
      id: 'INV-PHOTO-CARD',
      name: 'Cookiecad Blue Ombre TPU 95A',
      thumbnailBytes: imageBytes,
      clearImageBytes: true,
      itemColorName: '#7455FF',
      itemColorLabel: 'Blue Ombre',
      materialId: 'MAT-FIL-TPU',
      materialName: 'TPU',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 230,
            height: 286,
            child: InventoryCard(
              item: item,
              photoCard: true,
              onQuantityChanged: (_) {},
              onOpen: () {},
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('photo-card-INV-PHOTO-CARD')), findsOneWidget);
    expect(
      find.byKey(const Key('photo-card-background-INV-PHOTO-CARD')),
      findsOneWidget,
    );
    expect(find.text('Blue Ombre'), findsOneWidget);
    expect(find.text('TPU'), findsWidgets);
    expect(
      find.byKey(const Key('decrease-quantity-INV-PHOTO-CARD')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('increase-quantity-INV-PHOTO-CARD')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact square photo cards do not overflow', (tester) async {
    final thumbnail = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 2)),
    );
    final item = sampleInventory.first.copyWith(
      id: 'INV-COMPACT-PHOTO',
      name: 'Long multicolor filament product name',
      thumbnailBytes: thumbnail,
      clearImageBytes: true,
      itemColorName: '#7455FF',
      itemColorLabel: 'Blue Ombre',
      materialId: 'MAT-FIL-PLA',
      materialName: 'PLA',
      compatibility: const ['1 kg spool'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 200,
            child: InventoryCard(
              item: item,
              photoCard: true,
              onQuantityChanged: (_) {},
              onOpen: () {},
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('photo-card-INV-COMPACT-PHOTO')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('light appearance keeps the quantity badge dark grey', (
    tester,
  ) async {
    final item = sampleInventory.first.copyWith(id: 'INV-LIGHT-QUANTITY');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 300,
            child: InventoryCard(item: item, onOpen: () {}, onAction: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final badge = tester.widget<Container>(
      find.byKey(const Key('item-quantity-INV-LIGHT-QUANTITY')),
    );
    final decoration = badge.decoration! as BoxDecoration;
    expect(decoration.color!.computeLuminance(), lessThan(.08));
    final badgeText = find.descendant(
      of: find.byKey(const Key('item-quantity-INV-LIGHT-QUANTITY')),
      matching: find.byType(Text),
    );
    expect(tester.widget<Text>(badgeText).style!.color, Colors.white);
    final priceText = find.descendant(
      of: find.byKey(const Key('item-price-row-INV-LIGHT-QUANTITY')),
      matching: find.byType(Text),
    );
    expect(
      tester.widget<Text>(priceText).style!.color!.computeLuminance(),
      lessThan(.2),
    );
  });

  testWidgets('light appearance keeps dropdown text readable', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-light-dropdown-',
    );
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      ),
    ))!;
    database.saveState(
      encodeWorkshopState(
        inventory: sampleInventory,
        vendors: starterVendors,
        brands: starterBrands,
        products: starterProducts,
      ),
    );
    database.saveSyncConfig(
      jsonEncode(
        const SupabaseConfig(
          syncMode: 'local',
          url: '',
          publishableKey: '',
        ).toJson(),
      ),
    );
    database.saveStringPreference(
      'app_brightness_mode',
      AppBrightnessMode.light.name,
    );

    await tester.pumpWidget(
      InventorinatorApp(
        database: database,
        persistedState: database.loadState(),
      ),
    );
    await tester.tap(find.byKey(const Key('sort-menu')));
    await tester.pumpAndSettle();

    final quantityRow = find.byKey(const Key('context-action-sort-quantity'));
    final label = tester.widget<Text>(
      find.descendant(of: quantityRow, matching: find.text('Quantity')),
    );
    expect(label.style!.color, const Color(0xff211a2d));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      app.theme!.popupMenuTheme.color,
      InventorinatorColors.forTheme(
        AppColorTheme.darkPurple,
        brightness: AppBrightnessMode.light,
      ).panel,
    );

    await tester.pumpWidget(const SizedBox());
    database.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets('item card quantity controls update without opening the card', (
    tester,
  ) async {
    var item = sampleInventory.first.copyWith(
      id: 'INV-QUANTITY-CONTROLS',
      quantity: 2,
    );
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 260,
              height: 286,
              child: InventoryCard(
                item: item,
                onQuantityChanged: (delta) => setState(
                  () => item = item.copyWith(
                    quantity: (item.quantity + delta)
                        .clamp(0, double.infinity)
                        .toDouble(),
                  ),
                ),
                onOpen: () => opened = true,
                onAction: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const Key('increase-quantity-INV-QUANTITY-CONTROLS')),
    );
    await tester.pump();
    expect(find.text('×3'), findsOneWidget);
    expect(opened, isFalse);

    await tester.tap(
      find.byKey(const Key('decrease-quantity-INV-QUANTITY-CONTROLS')),
    );
    await tester.pump();
    expect(find.text('×2'), findsOneWidget);
    expect(opened, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid quantity taps commit once after the debounce window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-quantity-debounce-',
    );
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      ),
    ))!;
    final item = sampleInventory.first.copyWith(
      id: 'INV-DEBOUNCED-QUANTITY',
      quantity: 2,
    );
    database.saveState(
      encodeWorkshopState(
        inventory: [item],
        vendors: const [],
        brands: const [],
        products: const [],
      ),
    );
    database.saveSyncConfig(
      jsonEncode(
        const SupabaseConfig(
          syncMode: 'local',
          url: '',
          publishableKey: '',
        ).toJson(),
      ),
    );

    await tester.pumpWidget(
      InventorinatorApp(
        database: database,
        persistedState: database.loadState(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final increase = find.byKey(
      const Key('increase-quantity-INV-DEBOUNCED-QUANTITY'),
    );
    await tester.tap(increase);
    await tester.tap(increase);
    await tester.pump();

    expect(find.text('×4'), findsOneWidget);
    expect(find.byTooltip('Saving changes…'), findsOneWidget);
    expect(
      decodeWorkshopState(database.loadState())!.inventory.single.quantity,
      2,
    );

    await tester.pump(const Duration(milliseconds: 900));
    expect(
      decodeWorkshopState(database.loadState())!.inventory.single.quantity,
      2,
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.runAsync(() => database.waitForPendingWrites());
    final saved = decodeWorkshopState(database.loadState())!;
    expect(saved.inventory.single.quantity, 4);
    expect(find.byTooltip('Changes saved'), findsOneWidget);
    expect(saved.auditLog, hasLength(1));
    expect(saved.auditLog.single.changes['quantity'], '2 → 4');
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('local-save-feedback')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    database.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets(
    'a status change outside the quantity path also shows saved feedback',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final directory = Directory.systemTemp.createTempSync(
        'inventorinator-status-feedback-',
      );
      final database = (await tester.runAsync(
        () => LocalDatabase.open(
          overridePath: '${directory.path}/inventory.sqlite3',
        ),
      ))!;
      final item = sampleInventory.first.copyWith(
        id: 'INV-STATUS-FEEDBACK',
        type: InventoryType.filament,
        filamentStatus: FilamentStatus.ready,
      );
      database.saveState(
        encodeWorkshopState(
          inventory: [item],
          vendors: const [],
          brands: const [],
          products: const [],
        ),
      );
      database.saveSyncConfig(
        jsonEncode(
          const SupabaseConfig(
            syncMode: 'local',
            url: '',
            publishableKey: '',
          ).toJson(),
        ),
      );

      await tester.pumpWidget(
        InventorinatorApp(
          database: database,
          persistedState: database.loadState(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      // Let any startup-triggered save (e.g. one-time drying-timer setup)
      // finish its own feedback pulse before driving the real interaction.
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.text(item.name).first);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('local-save-feedback')), findsNothing);
      await tester.tap(find.byKey(const Key('status-deployed')));
      await tester.pump();
      await tester.runAsync(() => database.waitForPendingWrites());

      // The record write is deferred off the interaction callback, then the
      // indicator goes straight to "saved" once that queued commit lands.
      expect(
        decodeWorkshopState(database.loadState())!
            .inventory
            .single
            .filamentStatus,
        FilamentStatus.deployed,
      );
      expect(find.byTooltip('Changes saved'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('local-save-feedback')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      database.close();
      directory.deleteSync(recursive: true);
    },
  );

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
            height: 272,
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

  testWidgets('card effect layers are removed while inventory is scrolling', (
    tester,
  ) async {
    final scrolling = ValueNotifier(false);
    addTearDown(scrolling.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ItemCardEffects(
          itemId: 'SCROLL-EFFECTS',
          quantitySyncVersion: 1,
          lowStockVersion: 1,
          moistureVersion: 1,
          lowStockActive: true,
          moistureActive: true,
          durationPercent: 100,
          recurrenceSeconds: 5,
          scrollingListenable: scrolling,
          child: const SizedBox(width: 200, height: 200),
        ),
      ),
    );
    expect(find.byType(LowStockPulseEffect), findsOneWidget);
    expect(find.byType(MoistureDropletWaveEffect), findsOneWidget);
    expect(find.byType(RemoteQuantityChangeEffect), findsOneWidget);

    scrolling.value = true;
    await tester.pump();
    expect(find.byType(LowStockPulseEffect), findsNothing);
    expect(find.byType(MoistureDropletWaveEffect), findsNothing);
    expect(find.byType(RemoteQuantityChangeEffect), findsNothing);
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

  testWidgets('inventory search matches brand and vendor fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final item = sampleInventory.first.copyWith(
      id: 'brand-search-item',
      name: 'Purple filament',
      brand: 'Atomic Filament',
      vendor: 'Workshop Supply House',
    );
    final state = encodeWorkshopState(
      inventory: [item],
      vendors: const [],
      brands: const [],
      products: const [],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));

    final search = find.byKey(const Key('inventory-search'));
    await tester.enterText(search, 'Atomic Filament');
    await tester.pump();
    expect(find.text('Purple filament'), findsOneWidget);

    await tester.enterText(search, 'Workshop Supply House');
    await tester.pump();
    expect(find.text('Purple filament'), findsOneWidget);
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

  testWidgets('older filament can save a color without a moisture lifespan', (
    tester,
  ) async {
    InventoryItem? saved;
    final filament = InventoryItem(
      id: 'old-filament-no-lifespan',
      name: 'Bone White PLA',
      type: InventoryType.filament,
      compatibility: const [],
      added: DateTime(2026),
      cost: 20,
      color: Colors.purple,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<InventoryItem>(
                context: context,
                builder: (_) => AddItemDialog(initialItem: filament),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('item-color')));
    await tester.enterText(find.byKey(const Key('item-color-name')), 'White');
    await tester.enterText(find.byKey(const Key('item-color')), '#F5F7FC');
    await tester.tap(find.byKey(const Key('save-item')));
    await tester.pumpAndSettle();

    expect(saved?.itemColorName, '#F5F7FC');
    expect(saved?.itemColorLabel, 'White');
    expect(saved?.color, const Color(0xff7455ff));
    expect(saved?.moistureLifespanMinutes, isNull);
    expect(find.byKey(const Key('item-save-error')), findsNothing);
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
    final sortMenu = tester.widget<PopupMenuButton<InventorySort>>(
      find.byKey(const Key('sort-menu')),
    );
    expect(sortMenu.borderRadius, BorderRadius.circular(14));
    expect(sortMenu.clipBehavior, Clip.antiAlias);
    await tester.tap(find.byKey(const Key('sort-menu')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('context-action-sort-addedDate')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('context-action-sort-addedDate')));
    await tester.pumpAndSettle();
    expect(find.text('Added date'), findsOneWidget);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -3000),
      3000,
    );
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 3 · 30 results'), findsOneWidget);
    expect(find.text('Page item 0'), findsNothing);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 3000),
      3000,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Page item 0');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(InventoryCard),
        matching: find.text('Page item 0'),
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

  testWidgets('sorts inventory by quantity from highest to lowest', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = encodeWorkshopState(
      inventory: [
        InventoryItem(
          id: 'INV-LOW-QUANTITY',
          name: 'Low quantity',
          type: InventoryType.other,
          compatibility: const [],
          added: DateTime(2026),
          cost: 0,
          color: Colors.purple,
          quantity: 1,
        ),
        InventoryItem(
          id: 'INV-HIGH-QUANTITY',
          name: 'High quantity',
          type: InventoryType.other,
          compatibility: const [],
          added: DateTime(2026),
          cost: 0,
          color: Colors.purple,
          quantity: 20,
        ),
      ],
      vendors: const [],
      brands: const [],
      products: const [],
    );
    await tester.pumpWidget(
      MaterialApp(home: InventoryHome(persistedState: state)),
    );
    await tester.tap(find.byIcon(Icons.view_agenda_outlined));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sort-menu')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('context-action-sort-quantity')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('context-action-sort-quantity')));
    await tester.pumpAndSettle();

    expect(
      tester
          .getTopLeft(find.byKey(const Key('inventory-row-INV-HIGH-QUANTITY')))
          .dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('inventory-row-INV-LOW-QUANTITY')))
            .dy,
      ),
    );

    await tester.tap(find.byKey(const Key('sort-direction-toggle')));
    await tester.pumpAndSettle();
    expect(
      tester
          .getTopLeft(find.byKey(const Key('inventory-row-INV-LOW-QUANTITY')))
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const Key('inventory-row-INV-HIGH-QUANTITY')),
            )
            .dy,
      ),
    );
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
      await tester.ensureVisible(find.text('Types'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Types'));
      await tester.pumpAndSettle();

      for (final name in CatalogViewFilter.values) {
        expect(find.byKey(Key('catalog-filter-${name.name}')), findsOneWidget);
      }

      await tester.ensureVisible(find.byKey(const Key('catalog-filter-kits')));
      expect(
        find.byKey(const Key('catalog-filter-kits')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('catalog-filter-kits')));
      await tester.pumpAndSettle();
      expect(find.text('Prusa assembly kit'), findsOneWidget);
      await tester.ensureVisible(find.text('Prusa assembly kit'));
      await tester.pumpAndSettle();
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

      await tester.ensureVisible(find.text('Types'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Types'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('catalog-filter-printers')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catalog-filter-printers')));
      await tester.pumpAndSettle();
      expect(find.text('Prusa MK3S+'), findsOneWidget);
      expect(find.text('Nut Buster'), findsNothing);

      await tester.ensureVisible(find.text('Types'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Types'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('catalog-filter-tools')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catalog-filter-tools')));
      await tester.pumpAndSettle();
      expect(find.text('Nut Buster'), findsOneWidget);
      expect(find.text('Prusa MK3S+'), findsNothing);
    },
  );

  testWidgets('buildability reserves stock for active builds', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = encodeWorkshopState(
      inventory: [
        InventoryItem(
          id: 'INV-BOLT',
          name: 'M4 bolt',
          type: InventoryType.fastener,
          compatibility: const [],
          added: DateTime(2026),
          cost: 0,
          color: Colors.grey,
          quantity: 5,
          catalogProductId: 'PROD-BOLT',
        ),
      ],
      vendors: const [],
      brands: const [],
      products: const [],
      kits: const [
        KitRecord(
          id: 'KIT-BOLT',
          name: 'Bolt kit',
          bom: [
            KitBomEntry(
              id: 'KIT-BOLT-LINE',
              productId: 'PROD-BOLT',
              name: 'M4 bolt',
              quantity: 2,
            ),
          ],
        ),
      ],
      builds: [
        BuildRecord(
          id: 'BUILD-RESERVED',
          kitId: 'KIT-BOLT',
          name: 'Reserved build',
          createdAt: DateTime(2026),
          createdBy: 'Tester',
          lines: const [
            BuildLine(
              id: 'BUILD-LINE',
              productId: 'PROD-BOLT',
              name: 'M4 bolt',
              section: 'Main component',
              requiredQuantity: 2,
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.tap(find.text('Types'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-filter-kits')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-buildability')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('buildability-dialog')), findsOneWidget);
    expect(find.textContaining('Buildable ×1'), findsOneWidget);
    expect(find.textContaining('2 reserved'), findsOneWidget);
  });

  testWidgets('stockroom creates hierarchical-ready locations', (tester) async {
    tester.view.physicalSize = const Size(412, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      InventorinatorApp(
        persistedState: encodeWorkshopState(
          inventory: const [],
          vendors: const [],
          brands: const [],
          products: const [],
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-stockroom')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stockroom-dialog')), findsOneWidget);
    expect(find.byKey(const Key('close-stockroom')), findsOneWidget);
    expect(find.text('Close'), findsNothing);
    expect(find.text('Locations'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-location')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('new-location-name')),
      'Workshop',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-add-location')));
    await tester.pumpAndSettle();
    expect(find.text('Workshop'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byTooltip('Move items')).dx,
      lessThan(tester.getTopLeft(find.byTooltip('Rename Workshop')).dx),
    );
    expect(
      tester.getTopLeft(find.byTooltip('Rename Workshop')).dx,
      lessThan(tester.getTopLeft(find.byTooltip('Delete Workshop')).dx),
    );

    await tester.tap(find.byTooltip('Rename Workshop'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('rename-location-name')),
      'Main workshop',
    );
    await tester.tap(find.byKey(const Key('confirm-rename-location')));
    await tester.pumpAndSettle();
    expect(find.text('Main workshop'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete Main workshop'));
    await tester.pumpAndSettle();
    expect(find.text('This permanently removes the location.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete-location')));
    await tester.pumpAndSettle();
    expect(find.text('Main workshop'), findsNothing);
    expect(find.text('Add a shelf, cabinet, bin, or room.'), findsOneWidget);
  });

  testWidgets(
    'stockroom location cards remain readable at Android phone width',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        InventorinatorApp(
          persistedState: encodeWorkshopState(
            inventory: const [],
            vendors: const [],
            brands: const [],
            products: const [],
            locations: const [
              StockLocationRecord(id: 'LOC-AD5X', name: 'AD5X Rack'),
              StockLocationRecord(id: 'LOC-X1C', name: 'X1C Rack'),
            ],
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-stockroom')));
      await tester.pumpAndSettle();

      final card = find.byKey(const Key('location-LOC-AD5X'));
      final name = find.descendant(of: card, matching: find.text('AD5X Rack'));
      final count = find.descendant(of: card, matching: find.text('0 items'));
      final move = find.byKey(const Key('move-items-location-LOC-AD5X'));
      expect(tester.takeException(), isNull);
      expect(name, findsOneWidget);
      expect(tester.getSize(name).height, lessThan(30));
      expect(
        tester.getTopLeft(move).dy,
        greaterThan(tester.getBottomLeft(count).dy),
      );
    },
  );

  testWidgets('location QR sits above details at Android phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      InventorinatorApp(
        persistedState: encodeWorkshopState(
          inventory: const [],
          vendors: const [],
          brands: const [],
          products: const [],
          locations: const [
            StockLocationRecord(id: 'LOC-AD5X', name: 'AD5X Rack'),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-stockroom')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('location-LOC-AD5X')));
    await tester.pumpAndSettle();

    final qr = find.byKey(const Key('location-qr-LOC-AD5X'));
    final summary = find.byKey(const Key('location-summary-LOC-AD5X'));
    final download = find.byKey(const Key('download-location-qr-LOC-AD5X'));
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomLeft(qr).dy,
      lessThan(tester.getTopLeft(summary).dy),
    );
    expect(
      tester.getBottomLeft(summary).dy,
      lessThan(tester.getTopLeft(download).dy),
    );
  });

  testWidgets('location move search includes item brand names', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      InventorinatorApp(
        persistedState: encodeWorkshopState(
          inventory: sampleInventory,
          vendors: const [],
          brands: const [],
          products: const [],
          locations: const [
            StockLocationRecord(id: 'LOC-SEARCH', name: 'Workshop'),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-stockroom')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('move-items-location-LOC-SEARCH')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('move-location-search')),
      'Polymaker',
    );
    await tester.pump();

    expect(find.byKey(const Key('move-item-INV-FIL-0001')), findsOneWidget);
    expect(find.byKey(const Key('move-item-INV-NOZ-0001')), findsNothing);
  });

  testWidgets('deleting a location safely reparents children and items', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = encodeWorkshopState(
      inventory: [
        InventoryItem(
          id: 'INV-PARENT-LOCATION',
          name: 'Parent shelf item',
          type: InventoryType.other,
          compatibility: const [],
          added: DateTime(2026),
          cost: 1,
          color: Colors.grey,
          storageLocationId: 'LOC-PARENT',
          storageLocation: 'Workshop',
        ),
        InventoryItem(
          id: 'INV-CHILD-LOCATION',
          name: 'Child bin item',
          type: InventoryType.other,
          compatibility: const [],
          added: DateTime(2026),
          cost: 1,
          color: Colors.grey,
          storageLocationId: 'LOC-CHILD',
          storageLocation: 'Workshop / Bin 1',
        ),
      ],
      vendors: const [],
      brands: const [],
      products: const [],
      locations: const [
        StockLocationRecord(id: 'LOC-PARENT', name: 'Workshop'),
        StockLocationRecord(
          id: 'LOC-CHILD',
          name: 'Bin 1',
          parentId: 'LOC-PARENT',
        ),
      ],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.tap(find.byKey(const Key('open-stockroom')));
    await tester.pumpAndSettle();
    final moveItems = find.byKey(const Key('move-items-location-LOC-PARENT'));
    expect(
      find.descendant(
        of: moveItems,
        matching: find.byIcon(Icons.drive_file_move_outline),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: moveItems,
        matching: find.byIcon(Icons.qr_code_scanner_rounded),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('location-LOC-PARENT')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('location-details-LOC-PARENT')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('location-qr-image-LOC-PARENT')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('download-location-qr-LOC-PARENT')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('location-item-INV-PARENT-LOCATION')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('location-item-INV-CHILD-LOCATION')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('close-location-details')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-location-LOC-PARENT')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 directly stored item'), findsOneWidget);
    expect(find.textContaining('1 child location'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete-location')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location-LOC-PARENT')), findsNothing);
    expect(find.text('Bin 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('close-stockroom')));
    await tester.pumpAndSettle();

    final cards = tester.widgetList<InventoryCard>(find.byType(InventoryCard));
    final parentItem = cards
        .map((card) => card.item)
        .firstWhere((item) => item.id == 'INV-PARENT-LOCATION');
    final childItem = cards
        .map((card) => card.item)
        .firstWhere((item) => item.id == 'INV-CHILD-LOCATION');
    expect(parentItem.storageLocationId, isEmpty);
    expect(parentItem.storageLocation, isEmpty);
    expect(childItem.storageLocationId, 'LOC-CHILD');
    expect(childItem.storageLocation, 'Bin 1');
  });

  testWidgets('kit shortages flow into purchasing', (tester) async {
    const kit = KitRecord(
      id: 'KIT-SHOP',
      name: 'Shopping kit',
      bom: [
        KitBomEntry(
          id: 'KIT-SHOP-LINE',
          productId: 'PROD-BOLT',
          name: 'M4 bolt',
          quantity: 3,
        ),
      ],
    );
    double? shortage;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: KitDetailsDialog(
            kit: kit,
            kits: const [kit],
            products: const [],
            availableQuantity: (_, _) => 1,
            onAddShortage: (kit, line, missing) => shortage = missing,
            onBuild: (_) {},
          ),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('shop-kit-line-0')),
        matching: find.byKey(const Key('bom-shopping-cart-glyph')),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('shop-kit-line-0')));
    expect(shortage, 2);
  });

  testWidgets('receiving shopping stock increases inventory', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = encodeWorkshopState(
      inventory: [
        InventoryItem(
          id: 'INV-RECEIVE',
          name: 'M4 bolt',
          type: InventoryType.fastener,
          compatibility: const [],
          added: DateTime(2026),
          cost: 0,
          color: Colors.grey,
          quantity: 1,
          catalogProductId: 'PROD-BOLT',
        ),
      ],
      vendors: const [],
      brands: const [],
      products: const [],
      shoppingList: const [
        ShoppingListEntry(
          id: 'SHOP-RECEIVE',
          name: 'M4 bolt',
          productId: 'PROD-BOLT',
          quantityNeeded: 2,
        ),
      ],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.tap(find.byKey(const Key('open-stockroom')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shopping'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('remove-shopping-SHOP-RECEIVE')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('remove-shopping-SHOP-RECEIVE')),
        matching: find.byKey(const Key('remove-shopping-cart-glyph')),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Remove from shopping list'), findsOneWidget);
    await tester.tap(find.text('Receive'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-receive-shopping')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('close-stockroom')));
    await tester.pumpAndSettle();

    final card = tester.widget<InventoryCard>(find.byType(InventoryCard));
    expect(card.item.quantity, 3);
  });

  testWidgets(
    'type filters expand into a wrapped panel and search has no fake action',
    (tester) async {
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
      await tester.pumpAndSettle();

      final search = find.byKey(const Key('inventory-search'));
      expect(search, findsOneWidget);
      expect(
        find.descendant(of: search, matching: find.byIcon(Icons.tune_rounded)),
        findsNothing,
      );

      expect(find.byKey(const Key('type-filter-scroll')), findsNothing);
      final panel = find.byKey(const Key('type-filter-panel'));
      expect(panel, findsOneWidget);
      expect(find.byKey(const Key('active-type-indicator')), findsNothing);
      expect(
        tester.getTopLeft(search).dy,
        lessThan(tester.getTopLeft(panel).dy),
      );
      expect(
        (tester.getCenter(panel).dy -
                tester.getCenter(find.byKey(const Key('sort-menu'))).dy)
            .abs(),
        lessThanOrEqualTo(1),
      );
      final viewToggle = find.byKey(const Key('inventory-view-toggle'));
      expect(viewToggle, findsOneWidget);
      expect(
        (tester.getCenter(viewToggle).dy - tester.getCenter(panel).dy).abs(),
        lessThanOrEqualTo(1),
      );
      final finalType = find.widgetWithText(FilterChip, 'Silicone sock');
      expect(finalType.hitTestable(), findsNothing);

      await tester.tap(find.text('Types'));
      await tester.pumpAndSettle();
      final everythingChip = find.byKey(const Key('type-filter-everything'));
      final typeGlass = tester
          .widgetList<AnimatedContainer>(
            find.ancestor(
              of: everythingChip,
              matching: find.byType(AnimatedContainer),
            ),
          )
          .map((widget) => widget.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((decoration) => decoration.gradient != null);
      expect(typeGlass.borderRadius, BorderRadius.circular(10));
      expect(typeGlass.border, isA<Border>());
      await tester.dragUntilVisible(
        finalType,
        find.byKey(const Key('type-filter-options-scroll')),
        const Offset(0, -160),
      );
      await tester.drag(
        find.byKey(const Key('type-filter-options-scroll')),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(finalType).dy,
        greaterThan(
          tester.getTopLeft(find.widgetWithText(FilterChip, 'Everything')).dy,
        ),
      );
      await tester.tap(finalType);
      await tester.pumpAndSettle();
      expect(finalType.hitTestable(), findsNothing);
      expect(find.text('Silicone sock'), findsOneWidget);
      await tester.tap(find.text('Types'));
      await tester.pumpAndSettle();
      expect(finalType, findsOneWidget);
    },
  );

  testWidgets('Ctrl+F focuses and selects the inventory search', (
    tester,
  ) async {
    final state = encodeWorkshopState(
      inventory: const [],
      vendors: const [],
      brands: const [],
      products: const [],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.pumpAndSettle();

    final search = find.byKey(const Key('inventory-search'));
    await tester.enterText(search, 'Atomic PLA');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final field = tester.widget<TextField>(search);
    expect(field.focusNode?.hasFocus, isTrue);
    expect(
      field.controller?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 10),
    );
  });

  testWidgets('mobile inventory controls do not overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.pump();

    expect(find.byKey(const Key('page-size-slider')), findsOneWidget);
    expect(find.byKey(const Key('card-size-slider')), findsOneWidget);
    for (final sliderKey in const ['page-size-slider', 'card-size-slider']) {
      final sliderThemes = tester.widgetList<SliderTheme>(
        find.ancestor(
          of: find.byKey(Key(sliderKey)),
          matching: find.byType(SliderTheme),
        ),
      );
      expect(
        sliderThemes.any(
          (theme) =>
              theme.data.thumbShape?.getPreferredSize(true, false) ==
              const Size(92, 32),
        ),
        isTrue,
      );
    }
    expect(find.byKey(const Key('compact-header-actions')), findsOneWidget);
    expect(find.byKey(const Key('header-more-indicator')), findsOneWidget);
    expect(find.byKey(const Key('database-settings')), findsOneWidget);
    expect(find.byKey(const Key('cloud-sync')), findsOneWidget);
    final configGroup = find.byKey(const Key('config-action-group'));
    expect(configGroup, findsOneWidget);
    expect(
      find.descendant(of: configGroup, matching: find.byType(IconButton)),
      findsNWidgets(6),
    );
    expect(
      tester.getSize(find.byKey(const Key('personalization-settings'))),
      const Size.square(48),
    );
    expect(
      tester.getSize(find.byKey(const Key('config-action-group'))).height,
      tester.getSize(find.byKey(const Key('moisture-alerts'))).height,
    );
    expect(
      tester.getSize(find.byKey(const Key('config-action-group'))).height,
      tester.getSize(find.byKey(const Key('addition-history'))).height,
    );
    final bottomActions = find.byKey(const Key('bottom-quick-actions'));
    expect(bottomActions, findsOneWidget);
    final bottomActionKeys = [
      'open-catalog',
      'open-stockroom',
      'open-scanner',
      'add-item',
      'open-rapidizer',
      'open-filament-colors',
      'open-inventory-json-import',
    ];
    final actionTop = tester
        .getTopLeft(find.byKey(Key(bottomActionKeys.first)))
        .dy;
    for (final key in bottomActionKeys) {
      final action = find.byKey(Key(key));
      expect(
        find.descendant(of: bottomActions, matching: action),
        findsOneWidget,
      );
      final actionSize = tester.getSize(action);
      expect(actionSize.width, inInclusiveRange(40, 48));
      expect(actionSize.height, 44);
      expect(tester.getTopLeft(action).dy, actionTop);
    }
    expect(
      find.byKey(const Key('compact-bottom-action-group')),
      findsOneWidget,
    );
    final compactSurface = tester.getRect(
      find.byKey(const Key('bottom-action-surface')),
    );
    expect(
      tester.getRect(find.byKey(const Key('open-catalog'))).left,
      closeTo(compactSurface.left + 14, 1.1),
    );
    expect(
      tester.getRect(find.byKey(const Key('open-inventory-json-import'))).right,
      closeTo(compactSurface.right - 14, 1.1),
    );
    expect(
      find.descendant(of: bottomActions, matching: find.text('Catalog')),
      findsNothing,
    );
    final compactStockroom = find.byKey(const Key('open-stockroom'));
    final compactStockroomIcon = find.descendant(
      of: compactStockroom,
      matching: find.byIcon(Icons.warehouse_outlined),
    );
    final stockroomCenter = tester.getCenter(compactStockroom);
    final stockroomIconCenter = tester.getCenter(compactStockroomIcon);
    expect(stockroomIconCenter.dx, closeTo(stockroomCenter.dx - 2, .2));
    expect(stockroomIconCenter.dy, closeTo(stockroomCenter.dy, .2));
    expect(
      find.byKey(const Key('bottom-actions-more-indicator')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact desktop controls stay aligned and give sliders room', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(758, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.pumpAndSettle();

    final alerts = tester.getRect(find.byKey(const Key('moisture-alerts')));
    final config = tester.getRect(find.byKey(const Key('config-action-group')));
    expect(alerts.left, lessThan(60));
    expect(config.right, greaterThan(690));
    expect(
      tester.getSize(find.byKey(const Key('page-size-slider'))).width,
      greaterThan(200),
    );
    expect(
      tester.getSize(find.byKey(const Key('card-size-slider'))).width,
      greaterThan(200),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('local database uses action tiles on Android dimensions', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(600, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-local-database-tiles-',
    );
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      ),
    ))!;
    database.saveState(
      encodeWorkshopState(
        inventory: const [],
        vendors: const [],
        brands: const [],
        products: const [],
      ),
    );
    database.saveSyncConfig(
      jsonEncode(
        const SupabaseConfig(
          syncMode: 'local',
          url: '',
          publishableKey: '',
        ).toJson(),
      ),
    );

    await tester.pumpWidget(
      InventorinatorApp(
        database: database,
        persistedState: database.loadState(),
      ),
    );
    await tester.pump();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.colorScheme.primary, const Color(0xff9f8aff));
    expect(app.theme!.colorScheme.secondary, const Color(0xff45d2bd));
    expect(app.theme!.scaffoldBackgroundColor, const Color(0xff120d1c));
    await tester.tap(find.byKey(const Key('database-settings')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('close-local-database')), findsOneWidget);
    expect(find.byKey(const Key('import-database')), findsOneWidget);
    expect(find.byKey(const Key('export-database')), findsOneWidget);
    expect(find.byKey(const Key('delete-database')), findsOneWidget);
    final importIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('import-database')),
        matching: find.byIcon(Icons.file_upload_outlined),
      ),
    );
    expect(importIcon.size, 32);
    final glassLayers = tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byKey(const Key('import-database')),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>();
    expect(
      glassLayers.every((decoration) => decoration.boxShadow?.isEmpty ?? true),
      isTrue,
    );
    expect(
      glassLayers.any(
        (decoration) =>
            decoration.gradient is LinearGradient &&
            (decoration.gradient! as LinearGradient).colors.first ==
                InventorinatorColors.palettes[AppColorTheme.darkPurple]!.base
                    .withValues(alpha: .34),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
    database.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets('large quick actions and Catalog share the bottom action row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.pumpAndSettle();

    final actions = find.byKey(const Key('bottom-quick-actions'));
    expect(actions, findsOneWidget);
    final floatingActions = find.byKey(const Key('floating-header-actions'));
    expect(floatingActions, findsOneWidget);
    expect(
      tester.widget(find.byKey(const Key('floating-header-shell'))),
      isA<Padding>(),
    );
    expect(
      tester
          .widget<SliverPersistentHeader>(find.byType(SliverPersistentHeader))
          .pinned,
      isTrue,
    );
    for (final key in [
      'moisture-alerts',
      'addition-history',
      'config-action-group',
    ]) {
      expect(
        find.descendant(of: floatingActions, matching: find.byKey(Key(key))),
        findsOneWidget,
      );
    }
    for (final key in [
      'open-catalog',
      'open-stockroom',
      'open-scanner',
      'add-item',
      'open-rapidizer',
      'open-filament-colors',
      'open-inventory-json-import',
    ]) {
      expect(
        find.descendant(of: actions, matching: find.byKey(Key(key))),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: actions, matching: find.byType(OutlinedButton)),
      findsNWidgets(7),
    );
    final stockroomButton = find.byKey(const Key('open-stockroom'));
    final stockroomIcon = find.descendant(
      of: stockroomButton,
      matching: find.byIcon(Icons.warehouse_outlined),
    );
    final stockroomLabel = find.descendant(
      of: stockroomButton,
      matching: find.text('Stockroom'),
    );
    expect(
      tester.getRect(stockroomLabel).left - tester.getRect(stockroomIcon).right,
      12,
    );
    expect(
      tester.getSize(find.byKey(const Key('open-scanner'))).height,
      closeTo(
        tester.getSize(find.byKey(const Key('moisture-alerts'))).height,
        2,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('open-catalog'))).dx,
      lessThan(tester.getTopLeft(find.byKey(const Key('open-scanner'))).dx),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('open-scanner'))).dx,
      lessThan(tester.getTopLeft(find.byKey(const Key('add-item'))).dx),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('open-filament-colors'))).dx,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('open-inventory-json-import')))
            .dx,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('moisture-alerts'))).dx,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('database-settings'))).dx,
      ),
    );
    final titleBlock = find.byKey(const Key('app-title-block'));
    expect(
      tester.getTopLeft(titleBlock).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('moisture-alerts'))).dy),
    );
    expect(tester.getCenter(titleBlock).dx, closeTo(650, 1));
  });

  testWidgets('medium width collapses bottom actions before labels clip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1150, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('compact-bottom-action-group')),
      findsOneWidget,
    );
    final surfaceRect = tester.getRect(
      find.byKey(const Key('bottom-action-surface')),
    );
    expect(
      tester.getRect(find.byKey(const Key('open-catalog'))).left,
      closeTo(surfaceRect.left + 14, 1.1),
    );
    expect(
      tester.getRect(find.byKey(const Key('open-inventory-json-import'))).right,
      closeTo(surfaceRect.right - 14, 1.1),
    );
    for (final key in const [
      'open-filament-colors',
      'open-inventory-json-import',
    ]) {
      final actionRect = tester.getRect(find.byKey(Key(key)));
      expect(actionRect.width, greaterThan(48));
      expect(actionRect.width, lessThan(88));
      expect(actionRect.height, 44);
      expect(surfaceRect.contains(actionRect.topLeft), isTrue);
      expect(surfaceRect.contains(actionRect.bottomRight), isTrue);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile list rows give long item names a dedicated row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final item = InventoryItem(
      id: 'INV-MOBILE-LONG-NAME',
      name: 'Polymaker Panchroma Basic PLA Galaxy Red',
      type: InventoryType.filament,
      compatibility: const ['1.75 mm'],
      added: DateTime(2026),
      cost: 18.99,
      color: Colors.purple,
      itemColorName: 'Red',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: InventoryRow(
              item: item,
              spoolSizeLabel: '1 kg',
              onOpen: () {},
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('mobile-inventory-row-INV-MOBILE-LONG-NAME')),
      findsOneWidget,
    );
    final name = tester.widget<Text>(
      find.byKey(const Key('mobile-item-name-INV-MOBILE-LONG-NAME')),
    );
    expect(name.maxLines, 2);
    expect(name.overflow, TextOverflow.ellipsis);
    expect(
      tester
          .getSize(find.byKey(const Key('inventory-row-INV-MOBILE-LONG-NAME')))
          .height,
      lessThan(190),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating action rows clear while inventory scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bottom-action-overlay')), findsOneWidget);
    final bottomOverlay = find.byKey(const Key('bottom-action-overlay'));
    final bottomSurface = find.byKey(const Key('bottom-action-surface'));
    final topSurface = tester.widget<AnimatedContainer>(
      find.byKey(const Key('floating-header-actions')),
    );
    expect(
      tester.widget<AnimatedContainer>(bottomSurface).decoration,
      topSurface.decoration,
    );
    expect(
      tester.getBottomLeft(bottomSurface).dy,
      closeTo(tester.getBottomLeft(bottomOverlay).dy, 0.1),
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).bottomNavigationBar,
      isNull,
    );

    double opacity(String key) =>
        tester.widget<AnimatedOpacity>(find.byKey(Key(key))).opacity;

    expect(opacity('floating-header-visibility'), 1);
    expect(opacity('bottom-action-visibility'), 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, -250));
    await tester.pump();

    expect(opacity('floating-header-visibility'), 0);
    expect(opacity('bottom-action-visibility'), 0);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 250));
    expect(opacity('floating-header-visibility'), 0);
    expect(opacity('bottom-action-visibility'), 0);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(opacity('floating-header-visibility'), 1);
    expect(opacity('bottom-action-visibility'), 1);
  });

  testWidgets('desktop mouse wheel scroll uses an eased animation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.pumpAndSettle();

    final view = find.byKey(const Key('inventory-scroll-view'));
    final scrollable = find.descendant(
      of: view,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, 0);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(view),
        kind: PointerDeviceKind.mouse,
        scrollDelta: const Offset(0, 120),
      ),
    );
    expect(position.pixels, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(position.pixels, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 70));

    expect(position.pixels, greaterThan(0));
    expect(position.pixels, lessThan(120));
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(120, 1));
  });

  testWidgets('repeated desktop wheel input keeps continuous forward motion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.pumpAndSettle();

    final view = find.byKey(const Key('inventory-scroll-view'));
    final scrollable = find.descendant(
      of: view,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    final samples = <double>[];

    for (var pulse = 0; pulse < 6; pulse++) {
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(view),
          kind: PointerDeviceKind.mouse,
          scrollDelta: const Offset(0, 60),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      samples.add(position.pixels);
    }
    for (var frame = 0; frame < 45; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      samples.add(position.pixels);
    }

    final deltas = <double>[
      for (var index = 1; index < samples.length; index++)
        samples[index] - samples[index - 1],
    ];
    expect(deltas.every((delta) => delta >= 0), isTrue);
    expect(deltas.where((delta) => delta > .05).length, greaterThan(20));
    expect(position.pixels, closeTo(360, 5));
    await tester.pumpAndSettle();
  });

  testWidgets('delayed desktop frame does not jump through the wheel glide', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.pumpAndSettle();

    final view = find.byKey(const Key('inventory-scroll-view'));
    final scrollable = find.descendant(
      of: view,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    final position = tester.state<ScrollableState>(scrollable).position;

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(view),
        kind: PointerDeviceKind.mouse,
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(position.pixels, greaterThan(20));
    expect(position.pixels, lessThan(70));
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(120, 1));
  });

  testWidgets('switches between grid and one-column list', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    final toggle = tester.widget<SegmentedButton<bool>>(
      find.byKey(const Key('inventory-view-toggle')),
    );
    expect(
      toggle.style?.backgroundColor?.resolve(const {}),
      const Color(0xff1b1726),
    );
    expect(
      toggle.style?.foregroundColor?.resolve({WidgetState.selected}),
      const Color(0xff9f8aff),
    );
    expect(
      toggle.style?.side?.resolve(const {})?.color,
      const Color(0xff463955),
    );
    expect(find.byType(InventoryCard), findsWidgets);
    await tester.tap(find.byIcon(Icons.view_agenda_outlined));
    await tester.pump();
    expect(find.byType(InventoryRow), findsWidgets);
  });
  testWidgets('shift-click selects items and exposes bulk actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.drag(
      find.byKey(const Key('inventory-scroll-view')),
      const Offset(0, -150),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const Key('inventory-card-INV-FIL-0001')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.tap(find.byKey(const Key('inventory-card-INV-NOZ-0001')));
    await tester.pump();

    expect(find.byKey(const Key('bulk-edit-toolbar')), findsOneWidget);
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.byKey(const Key('bulk-create-kit')), findsOneWidget);
    expect(find.byKey(const Key('bulk-archive')), findsOneWidget);
    expect(find.byKey(const Key('bulk-delete')), findsOneWidget);
    expect(find.byKey(const Key('bulk-change-type')), findsOneWidget);

    await tester.tap(find.byKey(const Key('bulk-change-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bulk-type-fastener')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('inventory-card-INV-FIL-0001')),
        matching: find.text('FASTENERS'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('inventory-card-INV-NOZ-0001')),
        matching: find.text('FASTENERS'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('bulk-edit-toolbar')), findsNothing);
  });
  testWidgets('android long-press enters bulk selection mode', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());

    await tester.longPress(
      find.byKey(const Key('inventory-card-INV-FIL-0001')),
    );
    await tester.pump();

    expect(find.byKey(const Key('bulk-edit-toolbar')), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byKey(const Key('bulk-create-kit')), findsOneWidget);
    expect(find.byKey(const Key('bulk-archive')), findsOneWidget);
    expect(find.byKey(const Key('bulk-delete')), findsOneWidget);
    expect(find.byKey(const Key('bulk-change-type')), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('bulk archive and delete apply to every selected item', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.drag(
      find.byKey(const Key('inventory-scroll-view')),
      const Offset(0, -150),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const Key('inventory-card-INV-FIL-0001')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const Key('inventory-card-INV-NOZ-0001')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('bulk-archive')));
    await tester.pumpAndSettle();

    expect(find.text('Galaxy Black PETG'), findsNothing);
    expect(find.text('ObXidian 0.4 mm'), findsNothing);
    await tester.ensureVisible(find.text('Types'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Types'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archived-view')));
    await tester.pumpAndSettle();
    expect(find.text('Galaxy Black PETG'), findsOneWidget);
    expect(find.text('ObXidian 0.4 mm'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const Key('inventory-card-INV-FIL-0001')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const Key('inventory-card-INV-NOZ-0001')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('bulk-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 items?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-bulk-delete')));
    await tester.pumpAndSettle();

    expect(find.text('Galaxy Black PETG'), findsNothing);
    expect(find.text('ObXidian 0.4 mm'), findsNothing);
    expect(find.byKey(const Key('bulk-edit-toolbar')), findsNothing);
  });
  testWidgets('bulk kit draft defaults to one and accepts more inventory', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const Key('inventory-card-INV-FIL-0001')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const Key('inventory-card-INV-NOZ-0001')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('bulk-create-kit')));
    await tester.pumpAndSettle();

    expect(find.text('Kit / BOM'), findsOneWidget);
    expect(
      find.text('Create a kit and define its bill of materials'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('kit-section-Main component')), findsOneWidget);
    await tester.tap(find.byKey(const Key('save-kit')));
    await tester.pump();
    expect(find.text('Enter a kit name.'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('kit-bom-quantity-INV-FIL-0001')),
          )
          .initialValue,
      '1',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('kit-bom-quantity-INV-NOZ-0001')),
          )
          .initialValue,
      '1',
    );
    await tester.tap(find.byKey(const Key('add-kit-bom-line')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kit-inventory-item-INV-HBR-0001')));
    await tester.pumpAndSettle();
    expect(find.text('Titanium heat break'), findsWidgets);

    await tester.enterText(
      find.byKey(const Key('new-kit-name')),
      'Bulk test kit',
    );
    await tester.tap(find.byKey(const Key('save-kit')));
    await tester.pumpAndSettle();

    expect(find.text('Kit / BOM'), findsNothing);
    expect(find.byKey(const Key('bulk-edit-toolbar')), findsNothing);
  });
  testWidgets('adds a validated inventory item', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.byKey(const Key('add-item')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-product-web')), findsOneWidget);
    expect(find.byKey(const Key('product-page-url')), findsOneWidget);
    expect(find.byKey(const Key('import-product-page')), findsOneWidget);
    expect(find.byKey(const Key('item-barcode')), findsOneWidget);
    expect(find.byKey(const Key('barcode-image-picker')), findsOneWidget);
    expect(find.byKey(const Key('barcode-search-divider')), findsOneWidget);
    expect(find.byKey(const Key('search-url-divider')), findsOneWidget);
    expect(find.text('Search for a product'), findsOneWidget);
    expect(find.text('Import from a product URL'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('item-name')), 'Ruby ABS');
    await tester.enterText(
      find.byKey(const Key('item-compatibility')),
      'E3D V6, 1.75 mm',
    );
    await tester.enterText(find.byKey(const Key('item-cost')), '29.50');
    await tester.ensureVisible(find.byKey(const Key('item-color')));
    await tester.enterText(
      find.byKey(const Key('item-color-name')),
      'Ruby Red',
    );
    await tester.enterText(find.byKey(const Key('item-color')), '#D7263D');
    await tester.ensureVisible(find.byKey(const Key('save-item')));
    await tester.tap(find.byKey(const Key('save-item')));
    await tester.pumpAndSettle();
    expect(find.text('Ruby ABS'), findsOneWidget);
    expect(find.text('8 records'), findsOneWidget);
    await tester.tap(find.text('Colors'));
    await tester.pumpAndSettle();
    final colorGlass = tester
        .widgetList<AnimatedContainer>(
          find.ancestor(
            of: find.byKey(const Key('color-filter-all')),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.gradient != null);
    expect(colorGlass.borderRadius, BorderRadius.circular(10));
    expect(colorGlass.border, isA<Border>());
    expect(find.byKey(const Key('color-filter-#D7263D')), findsOneWidget);
    // The item card now also shows its color name next to the swatch, so
    // scope this to the color filter panel where the match must be unique.
    final colorFilterPanel = find.byKey(const Key('color-filter-panel'));
    expect(
      find.descendant(of: colorFilterPanel, matching: find.text('Ruby Red')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: colorFilterPanel, matching: find.text('#D7263D')),
      findsOneWidget,
    );
  });

  testWidgets('color filtering is constrained by the selected item type', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = encodeWorkshopState(
      inventory: [
        InventoryItem(
          id: 'INV-PURPLE-PLA',
          name: 'Purple PLA',
          type: InventoryType.filament,
          compatibility: const [],
          added: DateTime(2026),
          cost: 20,
          color: itemColorPalette['Purple']!,
          itemColorName: 'Purple',
        ),
        InventoryItem(
          id: 'INV-BLACK-PETG',
          name: 'Black PETG',
          type: InventoryType.filament,
          compatibility: const [],
          added: DateTime(2026),
          cost: 22,
          color: itemColorPalette['Black']!,
          itemColorName: 'Black',
        ),
        InventoryItem(
          id: 'INV-PURPLE-NOZZLE',
          name: 'Purple nozzle',
          type: InventoryType.nozzle,
          compatibility: const [],
          added: DateTime(2026),
          cost: 8,
          color: itemColorPalette['Purple']!,
          itemColorName: 'Purple',
        ),
        InventoryItem(
          id: 'INV-PINK-RESIN',
          name: 'Prusa Pink',
          type: InventoryType.resin,
          compatibility: const [],
          added: DateTime(2026),
          cost: 19,
          color: const Color(0xffd15cff),
          itemColorName: 'Pink',
        ),
      ],
      vendors: const [],
      brands: const [],
      products: const [],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Types'));
    await tester.pumpAndSettle();

    final filamentFilter = find.byKey(const Key('type-filter-filament'));
    await tester.ensureVisible(filamentFilter);
    await tester.pumpAndSettle();
    await tester.tap(filamentFilter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Colors'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('color-filter-Purple')), findsOneWidget);
    expect(find.byKey(const Key('color-filter-Black')), findsOneWidget);

    await tester.tap(find.byKey(const Key('color-filter-Purple')));
    await tester.pumpAndSettle();
    expect(find.text('Purple PLA'), findsOneWidget);
    expect(find.text('Black PETG'), findsNothing);
    expect(find.text('Purple nozzle'), findsNothing);

    await tester.ensureVisible(find.text('Types'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Types'));
    await tester.pumpAndSettle();
    final resinFilter = find.byKey(const Key('type-filter-resin'));
    await tester.ensureVisible(resinFilter);
    await tester.tap(resinFilter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Colors'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('color-filter-Pink')), findsOneWidget);
    expect(find.text('Prusa Pink'), findsOneWidget);
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
      'Purple PLA filamnet 2 19.99\nM3 nut fastner 12 0.08\nBlue PLA Filament 22.85',
    );
    await tester.tap(find.byKey(const Key('rapidize-items')));
    await tester.pumpAndSettle();

    expect(find.text('Purple PLA'), findsOneWidget);
    expect(find.text('Blue PLA'), findsOneWidget);
    expect(find.text('M3 nut'), findsOneWidget);
    expect(find.text('3 items RAPIDIZED!'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);
    expect(find.text('×12'), findsOneWidget);
    final bluePlaCard = tester
        .widgetList<InventoryCard>(find.byType(InventoryCard))
        .singleWhere((card) => card.item.name == 'Blue PLA');
    expect(bluePlaCard.item.quantity, 1);
    expect(bluePlaCard.item.materialName, 'PLA');
    expect(bluePlaCard.item.itemColorLabel, 'Blue');
  });
  testWidgets('catalog selection fills and creates an inventory item', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.byKey(const Key('add-item')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filament').last);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('add-item-form-scroll')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('brand-picker-null')));
    await tester.pumpAndSettle();
    expect(find.text('E3D'), findsNothing);
    await tester.tap(find.text('Polymaker').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('catalog-vendor')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('catalog-vendor')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Printed Solid').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('product-PROD-POLYLITE-PLA')),
    );
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
    await tester.tap(find.byKey(const Key('catalog-vendors-section')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('new-vendor-name')),
      'Maker Supply',
    );
    await tester.ensureVisible(find.byKey(const Key('add-vendor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-vendor')));
    await tester.pumpAndSettle();
    expect(find.text('Maker Supply'), findsOneWidget);
  });

  testWidgets('catalog creation forms precede existing records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = encodeWorkshopState(
      inventory: const [],
      vendors: const [VendorRecord(id: 'VEN-TEST', name: 'Test vendor')],
      brands: const [
        BrandRecord(
          id: 'BR-TEST',
          name: 'Test brand',
          vendorIds: {'VEN-TEST'},
          categories: {InventoryType.other},
        ),
      ],
      spoolTypes: const [
        SpoolTypeRecord(id: 'SPOOL-TEST', label: '1 kg', weightGrams: 1000),
      ],
      materials: const [
        MaterialRecord(
          id: 'MAT-TEST',
          name: 'Test material',
          typeKey: 'type:other',
        ),
      ],
      customItemTypes: const [
        CustomItemTypeRecord(id: 'TYPE-TEST', name: 'Test type'),
      ],
      products: const [],
      machineTypes: const [
        MachineTypeRecord(id: 'MACHINE-TYPE-TEST', name: 'Printer'),
      ],
      machines: const [
        MachineRecord(
          id: 'MACHINE-TEST',
          name: 'Test printer',
          model: '',
          address: '',
          typeId: 'MACHINE-TYPE-TEST',
        ),
      ],
      kits: const [KitRecord(id: 'KIT-TEST', name: 'Test kit', bom: [])],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();

    bool appearsBefore(Key first, Key second) {
      final elements = tester.allElements.toList();
      final firstIndex = elements.indexWhere(
        (element) => element.widget.key == first,
      );
      final secondIndex = elements.indexWhere(
        (element) => element.widget.key == second,
      );
      expect(firstIndex, isNonNegative, reason: '$first was not built');
      expect(secondIndex, isNonNegative, reason: '$second was not built');
      return firstIndex < secondIndex;
    }

    Future<void> toggleSection(Key key) async {
      final section = find.byKey(key);
      if (section.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          section,
          500,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('catalog-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
      }
      final header = find
          .descendant(of: section, matching: find.byType(ListTile))
          .first;
      await tester.ensureVisible(header);
      await tester.pumpAndSettle();
      await tester.tap(header);
      await tester.pumpAndSettle();
    }

    const sectionOrder = [
      Key('catalog-item-types-section'),
      Key('catalog-materials-section'),
      Key('catalog-machines-section'),
      Key('catalog-kits-section'),
      Key('catalog-spool-types-section'),
      Key('catalog-vendors-section'),
      Key('catalog-brands-section'),
      Key('catalog-products-section'),
    ];
    for (var index = 1; index < sectionOrder.length; index++) {
      expect(
        tester.getTopLeft(find.byKey(sectionOrder[index - 1])).dy,
        lessThan(tester.getTopLeft(find.byKey(sectionOrder[index])).dy),
      );
    }

    await toggleSection(const Key('catalog-item-types-section'));
    expect(
      appearsBefore(
        const Key('new-custom-type-name'),
        const Key('custom-type-row-TYPE-TEST'),
      ),
      isTrue,
    );
    await toggleSection(const Key('catalog-item-types-section'));

    await toggleSection(const Key('catalog-vendors-section'));
    expect(
      appearsBefore(
        const Key('new-vendor-name'),
        const Key('vendor-summary-VEN-TEST'),
      ),
      isTrue,
    );
    await toggleSection(const Key('catalog-vendors-section'));

    await toggleSection(const Key('catalog-brands-section'));
    expect(
      appearsBefore(
        const Key('new-brand-name'),
        const Key('brand-summary-BR-TEST'),
      ),
      isTrue,
    );
    await toggleSection(const Key('catalog-brands-section'));

    await toggleSection(const Key('catalog-spool-types-section'));
    expect(
      appearsBefore(
        const Key('new-spool-label'),
        const Key('spool-summary-SPOOL-TEST'),
      ),
      isTrue,
    );
    await toggleSection(const Key('catalog-spool-types-section'));

    await toggleSection(const Key('catalog-machines-section'));
    expect(
      appearsBefore(
        const Key('new-machine-name'),
        const Key('machine-summary-MACHINE-TEST'),
      ),
      isTrue,
    );
    await toggleSection(const Key('catalog-machines-section'));

    await toggleSection(const Key('catalog-kits-section'));
    expect(
      appearsBefore(
        const Key('new-kit-name'),
        const Key('kit-summary-KIT-TEST'),
      ),
      isTrue,
    );
    await toggleSection(const Key('catalog-kits-section'));

    await toggleSection(const Key('catalog-materials-section'));
    expect(
      appearsBefore(
        const Key('new-material-name'),
        const Key('material-row-MAT-TEST'),
      ),
      isTrue,
    );
    await toggleSection(const Key('catalog-materials-section'));
  });

  testWidgets('catalog adds a custom spool size', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();
    final spoolSection = find.byKey(const Key('catalog-spool-types-section'));
    await tester.scrollUntilVisible(
      spoolSection,
      500,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('catalog-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(spoolSection);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-spool-label')), '2.5 kg');
    await tester.enterText(find.byKey(const Key('new-spool-weight')), '2500');
    await tester.tap(find.byKey(const Key('add-spool-type')));
    await tester.pumpAndSettle();

    expect(find.text('2.5 kg'), findsWidgets);
  });

  testWidgets('catalog adds a type-specific material', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();
    final section = find.byKey(const Key('catalog-materials-section'));
    await tester.scrollUntilVisible(
      section,
      500,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('catalog-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(section);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-material-name')), 'PEEK');
    await tester.ensureVisible(find.byKey(const Key('add-material')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-material')));
    await tester.pumpAndSettle();

    expect(find.text('PEEK'), findsOneWidget);
    expect(find.textContaining('Filament · 0 items'), findsWidgets);
  });

  test('materials and item material assignments survive persistence', () {
    const customMaterial = MaterialRecord(
      id: 'MAT-FIL-PEEK',
      name: 'PEEK',
      typeKey: 'type:filament',
    );
    final item = sampleInventory.first.copyWith(
      materialId: customMaterial.id,
      materialName: customMaterial.name,
    );
    final decoded = decodeWorkshopState(
      encodeWorkshopState(
        inventory: [item],
        vendors: const [],
        brands: const [],
        materials: const [customMaterial],
        products: const [],
      ),
    )!;

    expect(decoded.materials.single.name, 'PEEK');
    expect(decoded.inventory.single.materialId, 'MAT-FIL-PEEK');
    expect(decoded.inventory.single.materialName, 'PEEK');
  });

  testWidgets('catalog adds machine types and machines', (tester) async {
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();
    final machineSection = find.byKey(const Key('catalog-machines-section'));
    await tester.scrollUntilVisible(
      machineSection,
      500,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('catalog-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(machineSection);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('machine-image-picker')), findsOneWidget);
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

    expect(find.textContaining('Nut Buster'), findsWidgets);
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
    expect(find.byKey(const Key('kit-image-picker')), findsOneWidget);
    expect(find.byKey(const Key('kit-bom-name-PROD-SCREW')), findsOneWidget);
    expect(
      find.byKey(const Key('kit-bom-quantity-PROD-SCREW')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('delete-kit-bom-PROD-SCREW')), findsOneWidget);
    expect(find.byKey(const Key('kit-section-Main component')), findsOneWidget);
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

    expect(find.text('Updated kit name'), findsWidgets);
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

  testWidgets(
    'Everything opens kits and preserved builds without a source kit',
    (tester) async {
      const kit = KitRecord(
        id: 'KIT-EVERYTHING',
        name: 'Everything test kit',
        bom: [],
        sections: ['Main component'],
      );
      final orphanBuild = BuildRecord(
        id: 'BUILD-ORPHAN',
        kitId: 'KIT-NO-LONGER-PRESENT',
        name: 'Preserved test build',
        createdAt: DateTime(2026),
        createdBy: 'Workshop phone',
        lines: const [
          BuildLine(
            id: 'LINE-1',
            productId: 'PROD-1',
            name: 'M3 screw',
            section: 'Main component',
            requiredQuantity: 2,
          ),
        ],
      );
      final state = encodeWorkshopState(
        inventory: const [],
        vendors: const [],
        brands: const [],
        products: const [],
        kits: const [kit],
        builds: [orphanBuild],
      );

      await tester.pumpWidget(InventorinatorApp(persistedState: state));
      expect(
        find.byKey(const Key('catalog-record-KIT-EVERYTHING')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('catalog-record-BUILD-ORPHAN')),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const Key('catalog-record-BUILD-ORPHAN')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catalog-record-BUILD-ORPHAN')));
      await tester.pumpAndSettle();
      expect(find.text('Full kit'), findsOneWidget);
      expect(find.text('M3 screw'), findsOneWidget);
    },
  );

  testWidgets('clicking a printer opens its details instead of the catalog', (
    tester,
  ) async {
    const machine = MachineRecord(
      id: 'MACHINE-DETAILS',
      name: 'Prusa MK3S+',
      model: 'MK3S+',
      address: 'prusa.local',
      typeId: 'TYPE-PRINTER',
    );
    final state = encodeWorkshopState(
      inventory: const [],
      vendors: const [],
      brands: const [],
      products: const [],
      machineTypes: const [
        MachineTypeRecord(id: 'TYPE-PRINTER', name: 'Printer'),
      ],
      machines: const [machine],
    );

    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.ensureVisible(
      find.byKey(const Key('catalog-record-MACHINE-DETAILS')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('catalog-record-MACHINE-DETAILS')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('machine-details-MACHINE-DETAILS')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('machine-address-MACHINE-DETAILS')),
      findsOneWidget,
    );
    expect(find.text('Product catalog'), findsNothing);
  });

  testWidgets('shift-click bulk-selects kits and printers together', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const kit = KitRecord(
      id: 'KIT-BULK-CATALOG',
      name: 'Bulk catalog kit',
      bom: [],
      sections: ['Main component'],
    );
    const printer = MachineRecord(
      id: 'MACHINE-BULK-CATALOG',
      name: 'Bulk catalog printer',
      model: 'Test printer',
      address: 'printer.local',
      typeId: 'TYPE-BULK-PRINTER',
    );
    final state = encodeWorkshopState(
      inventory: const [],
      vendors: const [],
      brands: const [],
      products: const [],
      kits: const [kit],
      machineTypes: const [
        MachineTypeRecord(id: 'TYPE-BULK-PRINTER', name: 'Printer'),
      ],
      machines: const [printer],
    );

    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const Key('catalog-record-KIT-BULK-CATALOG')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(find.byKey(const Key('bulk-catalog-toolbar')), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Bulk catalog kit'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('catalog-record-MACHINE-BULK-CATALOG')),
    );
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    expect(
      find.byKey(const Key('machine-details-MACHINE-BULK-CATALOG')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('clear-catalog-selection')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('catalog-record-MACHINE-BULK-CATALOG')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('machine-details-MACHINE-BULK-CATALOG')),
      findsOneWidget,
    );
  });

  testWidgets('shift-click bulk-selects builds without opening them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    BuildRecord build(String id) => BuildRecord(
      id: id,
      kitId: 'KIT-BULK-BUILDS',
      name: '$id test build',
      createdAt: DateTime(2026),
      createdBy: 'Test device',
      lines: const [],
    );
    final state = encodeWorkshopState(
      inventory: const [],
      vendors: const [],
      brands: const [],
      products: const [],
      builds: [build('BUILD-A'), build('BUILD-B')],
    );

    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const Key('catalog-record-BUILD-A')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(find.byKey(const Key('bulk-build-toolbar')), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Full kit'), findsNothing);

    await tester.tap(find.byKey(const Key('catalog-record-BUILD-B')));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('Full kit'), findsNothing);

    await tester.tap(find.byKey(const Key('clear-build-selection')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('catalog-record-BUILD-A')));
    await tester.pumpAndSettle();
    expect(find.text('Full kit'), findsOneWidget);
  });

  testWidgets('deleting a kit warns about unfinished builds', (tester) async {
    const kit = KitRecord(
      id: 'KIT-WITH-BUILDS',
      name: 'Printer kit',
      bom: [],
      sections: ['Main component'],
    );
    final activeBuild = BuildRecord(
      id: 'BUILD-ACTIVE',
      kitId: kit.id,
      name: 'Active printer build',
      createdAt: DateTime(2026),
      createdBy: 'Linux workstation',
      lines: const [],
    );
    final completedBuild = BuildRecord(
      id: 'BUILD-DONE',
      kitId: kit.id,
      name: 'Finished printer build',
      createdAt: DateTime(2026),
      createdBy: 'Linux workstation',
      lines: const [],
      completedAt: DateTime(2026, 1, 2),
    );
    final state = encodeWorkshopState(
      inventory: const [],
      vendors: const [],
      brands: const [],
      products: const [],
      kits: const [kit],
      builds: [activeBuild, completedBuild],
    );

    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.ensureVisible(
      find.byKey(const Key('catalog-record-KIT-WITH-BUILDS')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-record-KIT-WITH-BUILDS')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-kit')));
    await tester.pumpAndSettle();
    expect(find.text('You have 1 build in progress.'), findsOneWidget);
    expect(find.text('Delete Kit (permanent)'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kit-details-title')), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete-kit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-kit')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('catalog-record-KIT-WITH-BUILDS')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('catalog-record-BUILD-ACTIVE')),
      findsOneWidget,
    );
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

  testWidgets('kit details text remains readable at Android phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const kit = KitRecord(
      id: 'KIT-ANDROID-TEXT',
      name: 'Original Prusa XL five-head semi-assembled printer build',
      sourceUrls: ['https://example.com/source'],
      bom: [
        KitBomEntry(
          productId: 'PROD-ANDROID-TEXT',
          quantity: 12,
          name: 'Extra-long precision linear bearing carriage assembly',
          section: 'Main motion system and structural frame',
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
            inventory: const [],
            availableQuantity: (_, _) => 0,
            onMatchInventory: (kit, _, _) => kit,
            canMatchInventory: true,
            onAddShortage: (_, _, _) {},
            onBuild: (_) {},
            canDelete: true,
            onDelete: (_) async => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(kit.name), findsOneWidget);
    expect(
      find.text('Extra-long precision linear bearing carriage assembly'),
      findsOneWidget,
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
    await tester.tap(find.byKey(const Key('catalog-vendors-section')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('new-vendor-name')),
      'Prusa Research',
    );
    await tester.ensureVisible(find.byKey(const Key('vendor-is-brand')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vendor-is-brand')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('vendor-brand-category-filament')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vendor-brand-category-filament')));
    await tester.ensureVisible(find.byKey(const Key('add-vendor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-vendor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-item')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filament').last);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('add-item-form-scroll')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('brand-picker-null')));
    await tester.pumpAndSettle();
    expect(find.text('Prusa Research'), findsOneWidget);
  });
  testWidgets('deployed items use a padlock status icon', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      InventorinatorApp(
        persistedState: encodeWorkshopState(
          inventory: sampleInventory,
          vendors: starterVendors,
          brands: starterBrands,
          products: starterProducts,
          typeStatusSettings: const {
            'item:nozzle': true,
            'item:heatBreak': true,
          },
        ),
      ),
    );
    expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(2));
  });
  testWidgets('non-filament status defaults off and can be enabled by Type', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final filament = sampleInventory.first.copyWith(
      id: 'INV-STATUS-FILAMENT',
      name: 'Status filament',
      type: InventoryType.filament,
      quantity: 1,
    );
    final fastener = sampleInventory.first.copyWith(
      id: 'INV-STATUS-FASTENER',
      name: 'M3x6 status screw',
      type: InventoryType.fastener,
      quantity: 1,
      deployed: false,
      filamentStatus: FilamentStatus.ready,
    );
    await tester.pumpWidget(
      InventorinatorApp(
        persistedState: encodeWorkshopState(
          inventory: [filament, fastener],
          vendors: const [],
          brands: const [],
          products: const [],
        ),
      ),
    );

    expect(
      find.byKey(const Key('inventory-card-timer-INV-STATUS-FILAMENT')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('inventory-card-timer-INV-STATUS-FASTENER')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-item-types-section')));
    await tester.pumpAndSettle();
    final editFastener = find.byKey(
      const Key('edit-built-in-type-item:fastener'),
    );
    await tester.ensureVisible(editFastener);
    await tester.pumpAndSettle();
    await tester.tap(editFastener);
    await tester.pumpAndSettle();
    final statusSwitch = find.byKey(
      const Key('edit-built-in-type-shows-status'),
    );
    expect(tester.widget<SwitchListTile>(statusSwitch).value, isFalse);
    await tester.tap(statusSwitch);
    await tester.tap(find.byKey(const Key('save-built-in-type-name')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('inventory-card-timer-INV-STATUS-FASTENER')),
      findsOneWidget,
    );
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
  testWidgets('status ring does not replay when remounted by scrolling', (
    tester,
  ) async {
    final item = sampleInventory.first.copyWith(
      filamentStatus: FilamentStatus.ready,
      moistureLifespanMinutes: null,
      lastDriedAt: null,
    );

    Widget mountedRing() => MaterialApp(
      home: Scaffold(
        body: CountdownRing(
          key: ValueKey('status-ring-${item.id}'),
          item: item,
        ),
      ),
    );

    await tester.pumpWidget(mountedRing());
    var indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(mountedRing());
    indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, 1);
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
    expect(find.text('Dried'), findsOneWidget);
    expect(find.text('Time since dried'), findsNothing);
    final cost = find.byKey(const Key('sidebar-item-cost'));
    final dried = find.byKey(const Key('sidebar-item-dried'));
    expect(dried, findsOneWidget);
    expect(tester.getCenter(dried).dy, closeTo(tester.getCenter(cost).dy, 12));
    expect(find.text('Drying time remaining'), findsNothing);
  });
  testWidgets('non-filament flyout shows status only when Type opts in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.drag(
      find.byKey(const Key('inventory-scroll-view')),
      const Offset(0, -150),
    );
    await tester.pump();
    await tester.tap(find.text('ObXidian 0.4 mm'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('status-drying')), findsNothing);
    expect(find.text('Wet'), findsNothing);
    expect(find.byKey(const Key('item-deployed')), findsNothing);

    await tester.pumpWidget(
      InventorinatorApp(
        key: UniqueKey(),
        persistedState: encodeWorkshopState(
          inventory: sampleInventory,
          vendors: starterVendors,
          brands: starterBrands,
          products: starterProducts,
          typeStatusSettings: const {'item:nozzle': true},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('inventory-scroll-view')),
      const Offset(0, -150),
    );
    await tester.pump();
    await tester.tap(find.text('ObXidian 0.4 mm'));
    await tester.pumpAndSettle();
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
    final name = find.byKey(const Key('sidebar-item-name'));
    final quantity = find.byKey(const Key('sidebar-item-quantity'));
    final type = find.byKey(const Key('sidebar-type-indicator'));
    final status = find.byKey(const Key('sidebar-status-selector'));
    final cost = find.byKey(const Key('sidebar-item-cost'));
    expect(
      tester.getBottomLeft(type).dy,
      lessThan(tester.getTopLeft(status).dy),
    );
    expect(
      tester.getBottomLeft(status).dy,
      lessThan(tester.getTopLeft(name).dy),
    );
    expect(
      tester.getTopLeft(quantity).dy,
      closeTo(tester.getTopLeft(name).dy, 8),
    );
    expect(
      tester.getTopLeft(cost).dy,
      greaterThan(tester.getBottomLeft(name).dy),
    );
    final tabs = find.byKey(const Key('filament-details-tabs'));
    final storageLocation = find.byKey(const Key('sidebar-storage-location'));
    final moistureTracking = find.byKey(
      const Key('filament-moisture-tracking'),
    );
    expect(tabs, findsOneWidget);
    expect(storageLocation, findsOneWidget);
    expect(moistureTracking, findsOneWidget);
    expect(
      tester.getBottomLeft(storageLocation).dy,
      lessThan(tester.getTopLeft(moistureTracking).dy),
    );
    expect(
      tester.getBottomLeft(moistureTracking).dy,
      lessThanOrEqualTo(tester.getTopLeft(tabs).dy),
    );
    expect(find.text('Printing instructions'), findsOneWidget);
    expect(find.text('Drying instructions'), findsOneWidget);
    expect(
      find.text('Dry at 65°C for 6 hours before demanding prints.'),
      findsOneWidget,
    );
    expect(find.text('Drying profile'), findsOneWidget);
    expect(find.text('Drying temperature'), findsOneWidget);
    expect(find.text('Drying duration'), findsOneWidget);
    final tabContent = find.byKey(const Key('filament-details-tab-content'));
    expect(
      find.descendant(of: tabContent, matching: find.text('Storage')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tabContent, matching: find.text('Moisture lifespan')),
      findsNothing,
    );
    expect(find.text('Moisture lifespan'), findsOneWidget);
    expect(find.text('Vendor'), findsNothing);
    final spoolTab = find.byKey(const Key('filament-details-tab-spool'));
    await tester.ensureVisible(spoolTab);
    await tester.pumpAndSettle();
    await tester.tap(spoolTab);
    await tester.pumpAndSettle();
    expect(find.text('Spool dimensions'), findsOneWidget);
    expect(find.text('AMS compatibility'), findsOneWidget);
    expect(find.text('Printing instructions'), findsNothing);
    final brandTab = find.byKey(const Key('filament-details-tab-brand'));
    await tester.ensureVisible(brandTab);
    await tester.pumpAndSettle();
    await tester.tap(brandTab);
    await tester.pumpAndSettle();
    expect(find.text('Vendor'), findsOneWidget);
    expect(find.text('Brand'), findsNWidgets(2));
    expect(find.text('Storage'), findsNothing);
  });

  testWidgets('item sidebar edits and splits one into a new stack', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stack = sampleInventory.first.copyWith(
      id: 'INV-SPLIT-SOURCE',
      name: 'Ten spool stack',
      quantity: 10,
    );
    await tester.pumpWidget(
      InventorinatorApp(
        persistedState: encodeWorkshopState(
          inventory: [stack],
          vendors: starterVendors,
          brands: starterBrands,
          products: starterProducts,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ten spool stack'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-item-top')), findsOneWidget);
    final splitButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('split-one-item')),
    );
    expect(splitButton.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('split-one-item')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sidebar-item-quantity')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('sidebar-item-quantity')),
        matching: find.text('×1'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('split-one-item')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Ten spool stack'), findsNWidgets(2));
    expect(find.text('×9'), findsOneWidget);
    expect(find.text('×1'), findsOneWidget);

    await tester.tap(find.text('Ten spool stack').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-item-top')));
    await tester.pumpAndSettle();
    expect(find.text('Edit item'), findsOneWidget);
    expect(find.byKey(const Key('save-item')), findsOneWidget);
  });
  testWidgets('sidebar storage location opens its Stockroom location', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final item = sampleInventory.first.copyWith(
      storageLocationId: 'LOC-DRY-BOX',
      storageLocation: 'Workshop / Dry box 1',
    );
    await tester.pumpWidget(
      InventorinatorApp(
        persistedState: encodeWorkshopState(
          inventory: [item],
          vendors: const [],
          brands: const [],
          products: const [],
          locations: const [
            StockLocationRecord(id: 'LOC-WORKSHOP', name: 'Workshop'),
            StockLocationRecord(
              id: 'LOC-DRY-BOX',
              name: 'Dry box 1',
              parentId: 'LOC-WORKSHOP',
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Galaxy Black PETG'));
    await tester.pumpAndSettle();
    final storageLocation = find.byKey(const Key('sidebar-storage-location'));
    await tester.ensureVisible(storageLocation);
    expect(
      find.ancestor(of: storageLocation, matching: find.byType(Card)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: storageLocation,
        matching: find.byKey(const Key('sidebar-location-pin')),
      ),
      findsOneWidget,
    );
    await tester.tap(storageLocation);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('location-details-LOC-DRY-BOX')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('location-item-INV-FIL-0001')), findsOneWidget);
  });
  testWidgets('filament instructions tab fills missing canned guidance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final item = sampleInventory.first.copyWith(
      name: 'Fallback PLA',
      brand: '',
      printingInstructions: '',
      dryingInstructions: '',
      storageInstructions: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemDetailsPanel(
            item: item,
            onChanged: (_) {},
            machines: const [],
            machineTypes: const [],
            spoolTypes: starterSpoolTypes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Generic PLA starting profile'), findsOneWidget);
    expect(find.textContaining('Generic PLA drying profile'), findsOneWidget);
    expect(
      find.textContaining('Store sealed with fresh desiccant'),
      findsOneWidget,
    );
  });
  testWidgets('product source sits immediately before inventory lifecycle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final item = sampleInventory.first.copyWith(
      productUrl: 'https://example.com/filament',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemDetailsPanel(
            item: item,
            onChanged: (_) {},
            machines: const [],
            machineTypes: const [],
            spoolTypes: starterSpoolTypes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final source = find.byKey(const Key('open-product-source'));
    final lifecycle = find.text('Inventory lifecycle');
    expect(source, findsOneWidget);
    expect(lifecycle, findsOneWidget);
    expect(
      tester.getBottomLeft(source).dy,
      lessThan(tester.getTopLeft(lifecycle).dy),
    );
  });
  testWidgets('sidebar keeps color below QR when no product photo exists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final item = sampleInventory.first.copyWith(
      itemColorName: '#FFFFFF',
      itemColorLabel: 'White',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemDetailsPanel(
            item: item,
            onChanged: (_) {},
            machines: const [],
            machineTypes: const [],
            spoolTypes: starterSpoolTypes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sidebar-color-swatch')), findsOneWidget);
    expect(find.byKey(Key('item-color-swatch-${item.id}')), findsNothing);
    expect(find.byKey(const Key('sidebar-type-indicator')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('sidebar-color-detail'))).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const Key('sidebar-qr-code'))).dy,
      ),
    );
  });
  testWidgets('sidebar overlays color lower third on the product photo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final item = sampleInventory.first.copyWith(
      imageBytes: Uint8List.fromList(
        img.encodePng(img.Image(width: 320, height: 240)),
      ),
      itemColorName: '#E94F64',
      itemColorLabel: 'Galaxy Red',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemDetailsPanel(
            item: item,
            onChanged: (_) {},
            machines: const [],
            machineTypes: const [],
            spoolTypes: starterSpoolTypes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final photo = find.byKey(const Key('sidebar-product-image'));
    final titleOverlay = find.byKey(const Key('sidebar-item-title-overlay'));
    final lowerThird = find.byKey(const Key('sidebar-color-lower-third'));
    final photoStatus = find.byKey(const Key('sidebar-photo-status'));
    expect(titleOverlay, findsOneWidget);
    expect(photoStatus, findsOneWidget);
    expect(find.byKey(const Key('sidebar-item-heading')), findsNothing);
    expect(find.byKey(const Key('sidebar-item-name')), findsOneWidget);
    expect(find.byKey(const Key('sidebar-item-quantity')), findsOneWidget);
    expect(lowerThird, findsOneWidget);
    expect(find.byKey(const Key('sidebar-color-swatch')), findsOneWidget);
    expect(find.text('Galaxy Red'), findsOneWidget);
    expect(find.text('#E94F64'), findsOneWidget);
    final positioned = tester.widget<Positioned>(
      find.ancestor(of: lowerThird, matching: find.byType(Positioned)).first,
    );
    expect(positioned.left, 12);
    expect(positioned.right, 12);
    expect(positioned.bottom, 12);
    final titlePositioned = tester.widget<Positioned>(
      find.ancestor(of: titleOverlay, matching: find.byType(Positioned)).first,
    );
    expect(titlePositioned.left, 12);
    expect(titlePositioned.right, 82);
    expect(titlePositioned.top, 12);
    final statusPositioned = tester.widget<Positioned>(
      find.ancestor(of: photoStatus, matching: find.byType(Positioned)).first,
    );
    expect(statusPositioned.right, 12);
    expect(statusPositioned.top, 12);
    final statusBackground = tester.widget<Container>(photoStatus).decoration;
    expect(statusBackground, isA<BoxDecoration>());
    expect(
      (statusBackground! as BoxDecoration).color,
      const Color(0xff120d1c).withValues(alpha: .8),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('sidebar-qr-code'))).dy,
      greaterThan(tester.getBottomLeft(photo).dy),
    );
  });
  testWidgets('desktop item details panel can be resized and remembers width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.tap(find.text('Galaxy Black PETG'));
    await tester.pumpAndSettle();

    final panel = find.byType(ItemDetailsPanel);
    final initialWidth = tester.getSize(panel).width;
    expect(find.byKey(const Key('item-details-resize-handle')), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('item-details-resize-handle')),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();
    final resizedWidth = tester.getSize(panel).width;
    expect(resizedWidth, greaterThan(initialWidth + 100));

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('inventory-scroll-view')),
      const Offset(0, -150),
    );
    await tester.pump();
    await tester.tap(find.text('ObXidian 0.4 mm'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ItemDetailsPanel)).width, resizedWidth);
  });
  test('QR download filename includes the item name and stable ID', () {
    expect(
      qrDownloadFileName(sampleInventory.first),
      'Galaxy-Black-PETG_INV-FIL-0001_QR.png',
    );
  });
  test('location QR filename includes its path and stable ID', () {
    expect(
      locationQrDownloadFileName(
        const StockLocationRecord(id: 'LOC-A', name: 'Bin 1'),
        'Workshop / Bin 1',
      ),
      'Workshop-Bin-1_LOC-A_QR.png',
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
    expect(find.text('65°C'), findsOneWidget);
    await tester.ensureVisible(find.text('°F'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('°F'));
    await tester.pumpAndSettle();
    expect(find.textContaining('149°F'), findsWidgets);
    expect(find.text('65°C'), findsNothing);
    expect(
      find.text('Dry at 65°C for 6 hours before demanding prints.'),
      findsOneWidget,
    );
  });
  testWidgets('right click exposes and runs item actions', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.drag(
      find.byKey(const Key('inventory-scroll-view')),
      const Offset(0, -150),
    );
    await tester.pump();
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
    expect(find.byKey(const Key('context-action-edit')), findsOneWidget);
    expect(find.byKey(const Key('context-action-delete')), findsOneWidget);
    final popupTheme = PopupMenuTheme.of(
      tester.element(find.byKey(const Key('context-action-edit'))),
    );
    expect(popupTheme.color, const Color(0xff171220));
    expect(popupTheme.surfaceTintColor, Colors.transparent);
    final shape = popupTheme.shape! as RoundedRectangleBorder;
    expect(shape.side.color, const Color(0xff463955));
    expect(shape.borderRadius, BorderRadius.circular(18));
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(find.text('ObXidian 0.4 mm copy'), findsOneWidget);
  });

  testWidgets('all item types can be saved with zero stock', (tester) async {
    InventoryItem? saved;
    final part = InventoryItem(
      id: 'INV-PART-ZERO',
      name: 'Replacement duct',
      type: InventoryType.nozzle,
      compatibility: const ['PETG'],
      added: DateTime(2026),
      cost: 0,
      color: Colors.purple,
      quantity: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<InventoryItem>(
                context: context,
                builder: (_) => AddItemDialog(initialItem: part),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-item')));
    await tester.pumpAndSettle();

    expect(saved?.quantity, 0);
    expect(saved?.type, InventoryType.nozzle);
  });

  testWidgets('zero-quantity items can be hidden from inventory views', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = encodeWorkshopState(
      inventory: [
        InventoryItem(
          id: 'INV-ZERO',
          name: 'Unstocked nozzle',
          type: InventoryType.nozzle,
          compatibility: const [],
          added: DateTime(2026),
          cost: 0,
          color: Colors.purple,
          quantity: 0,
        ),
        InventoryItem(
          id: 'INV-STOCKED',
          name: 'Stocked nozzle',
          type: InventoryType.nozzle,
          compatibility: const [],
          added: DateTime(2026),
          cost: 0,
          color: Colors.purple,
          quantity: 1,
        ),
      ],
      vendors: const [],
      brands: const [],
      products: const [],
    );
    await tester.pumpWidget(
      MaterialApp(home: InventoryHome(persistedState: state)),
    );
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const Key('inventory-card-INV-ZERO')),
      find.byKey(const Key('inventory-scroll-view')),
      const Offset(0, -150),
    );

    expect(find.byKey(const Key('inventory-card-INV-ZERO')), findsOneWidget);
    expect(find.byKey(const Key('inventory-card-INV-STOCKED')), findsOneWidget);

    await tester.tap(find.byKey(const Key('hide-zero-quantity-items')));
    await tester.pump();

    expect(find.byKey(const Key('inventory-card-INV-ZERO')), findsNothing);
    expect(find.byKey(const Key('inventory-card-INV-STOCKED')), findsOneWidget);
  });

  testWidgets('zero-quantity visibility survives restart on this device', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync(
      'inventorinator-hide-zero-',
    );
    final database = (await tester.runAsync(
      () => LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      ),
    ))!;
    final state = encodeWorkshopState(
      inventory: [
        InventoryItem(
          id: 'INV-ZERO-PERSIST',
          name: 'Empty stack',
          type: InventoryType.other,
          compatibility: const [],
          added: DateTime(2026),
          cost: 0,
          color: Colors.purple,
          quantity: 0,
        ),
      ],
      vendors: const [],
      brands: const [],
      products: const [],
    );
    database.saveState(state);

    await tester.pumpWidget(
      InventorinatorApp(database: database, persistedState: state),
    );
    await tester.tap(find.byKey(const Key('personalization-settings')));
    await tester.pumpAndSettle();
    final preferenceToggle = find.byKey(const Key('hide-zero-personalization'));
    await tester.ensureVisible(preferenceToggle);
    await tester.tap(preferenceToggle);
    await tester.pumpAndSettle();
    expect(
      database.loadBoolPreference('hide_zero_quantity_items', fallback: false),
      isTrue,
    );
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('inventory-card-INV-ZERO-PERSIST')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(
      InventorinatorApp(database: database, persistedState: state),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('inventory-card-INV-ZERO-PERSIST')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox());
    database.close();
    directory.deleteSync(recursive: true);
  });

  testWidgets('printed part context menu finds compatible stocked filament', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = encodeWorkshopState(
      inventory: [
        InventoryItem(
          id: 'INV-PART',
          name: 'PETG fan duct',
          type: InventoryType.printedPart,
          compatibility: const ['PETG'],
          added: DateTime(2026),
          cost: 0,
          color: Colors.purple,
          quantity: 0,
        ),
        InventoryItem(
          id: 'INV-PETG',
          name: 'Galaxy PETG',
          type: InventoryType.filament,
          compatibility: const [],
          added: DateTime(2026),
          cost: 20,
          color: Colors.blue,
          quantity: 2,
        ),
        InventoryItem(
          id: 'INV-PLA',
          name: 'Bone White PLA',
          type: InventoryType.filament,
          compatibility: const [],
          added: DateTime(2026),
          cost: 20,
          color: Colors.white,
          quantity: 3,
        ),
      ],
      vendors: const [],
      brands: const [],
      products: const [],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.pumpAndSettle();

    await tester.tap(
      find.text('PETG fan duct'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Show compatible filaments'), findsOneWidget);
    await tester.tap(find.text('Show compatible filaments'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('compatible-filament-INV-PETG')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('compatible-filament-INV-PLA')), findsNothing);
  });

  testWidgets('archived view can restore archived items', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const InventorinatorApp());
    await tester.drag(
      find.byKey(const Key('inventory-scroll-view')),
      const Offset(0, -150),
    );
    await tester.pump();
    await tester.tap(find.text('Brass 0.6 mm'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Brass 0.6 mm'), findsNothing);
    await tester.tap(find.text('Types'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('archived-view')));
    await tester.pumpAndSettle();
    expect(find.text('Brass 0.6 mm'), findsOneWidget);
    expect(find.text('1 archived'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('inventory-scroll-view')),
      const Offset(0, -150),
    );
    await tester.pump();
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
    await tester.tap(find.text('Types'));
    await tester.pumpAndSettle();
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

  testWidgets('mark depleted follows the item type setting', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fastener = InventoryItem(
      id: 'INV-DEPLETION-SETTING',
      name: 'M4 test screw',
      type: InventoryType.fastener,
      compatibility: const [],
      added: DateTime(2026),
      cost: 0.25,
      color: Colors.grey,
    );
    String state({Map<String, bool> settings = const {}}) =>
        encodeWorkshopState(
          inventory: [fastener],
          vendors: const [],
          brands: const [],
          products: const [],
          typeDepletionSettings: settings,
        );

    await tester.pumpWidget(InventorinatorApp(persistedState: state()));
    await tester.tap(find.text('M4 test screw'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mark-depleted')), findsNothing);
    expect(find.byKey(const Key('mark-destroyed')), findsOneWidget);

    await tester.pumpWidget(
      InventorinatorApp(
        key: UniqueKey(),
        persistedState: state(settings: const {'item:fastener': true}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('M4 test screw'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mark-depleted')), findsOneWidget);
  });

  test('custom item types and contextual values survive persistence', () {
    const customType = CustomItemTypeRecord(
      id: 'TYPE-SOAP',
      name: 'Soap batch',
      contextualFields: ['Cure time', 'Mold'],
      iconKey: 'science',
      canMarkDepleted: true,
      showsStatus: true,
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
    expect(decoded?.customItemTypes.single.iconKey, 'science');
    expect(decoded?.customItemTypes.single.canMarkDepleted, isTrue);
    expect(decoded?.customItemTypes.single.showsStatus, isTrue);
    expect(decoded?.inventory.single.typeLabel, 'Soap batch');
    expect(decoded?.inventory.single.customFieldValues['Cure time'], '6 weeks');
  });

  testWidgets('kit view matches a missing BOM line to existing inventory', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final item = InventoryItem(
      id: 'INV-M4-BUTTON',
      name: 'M4 × 10 button-head screw',
      type: InventoryType.fastener,
      compatibility: [],
      added: DateTime(2026),
      cost: 0.12,
      color: Colors.grey,
      quantity: 4,
    );
    const kit = KitRecord(
      id: 'KIT-MATCH-MISSING',
      name: 'Imported frame kit',
      bom: [
        KitBomEntry(
          id: 'BOM-M4',
          productId: 'IMPORTED-M4-BOLT',
          quantity: 3,
          name: 'M4 frame bolt',
          section: 'Frame',
        ),
      ],
    );
    final state = encodeWorkshopState(
      inventory: [item],
      vendors: const [],
      brands: const [],
      products: const [],
      kits: const [kit],
    );

    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.tap(find.byKey(const Key('catalog-record-KIT-MATCH-MISSING')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Missing 3'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('match-kit-line-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('match-kit-line-0')));
    await tester.pumpAndSettle();
    expect(find.text('Match BOM item'), findsOneWidget);
    expect(find.byKey(const Key('bom-match-source-name')), findsOneWidget);
    expect(
      find.byKey(const Key('bom-match-item-INV-M4-BUTTON')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('bom-match-item-INV-M4-BUTTON')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kit-match-label-0')), findsOneWidget);
    expect(find.text('Matched to M4 × 10 button-head screw'), findsOneWidget);
    expect(find.textContaining('Available 3'), findsOneWidget);
    expect(find.textContaining('Missing'), findsNothing);
  });

  testWidgets('custom type image icons persist and render on item cards', (
    tester,
  ) async {
    const pngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
    const customType = CustomItemTypeRecord(
      id: 'TYPE-CUSTOM-ICON',
      name: 'Custom icon type',
      iconKey: 'custom-image:$pngBase64',
    );
    final item = sampleInventory.first.copyWith(
      id: 'INV-CUSTOM-ICON',
      name: 'Custom icon item',
      type: InventoryType.custom,
      itemColorName: '',
      customTypeId: customType.id,
      customTypeName: customType.name,
    );
    final state = encodeWorkshopState(
      inventory: [item],
      vendors: const [],
      brands: const [],
      products: const [],
      customItemTypes: const [customType],
    );
    final decoded = decodeWorkshopState(state)!;
    expect(decoded.customItemTypes.single.iconKey, customType.iconKey);

    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('item-type-image-INV-CUSTOM-ICON')),
      findsOneWidget,
    );
    final cardIconProvider = tester
        .widget<Image>(find.byKey(const Key('item-type-image-INV-CUSTOM-ICON')))
        .image;
    tester.widget<InventoryCard>(find.byType(InventoryCard)).onOpen();
    await tester.pumpAndSettle();
    final sidebarType = find.byKey(const Key('sidebar-type-indicator'));
    expect(sidebarType, findsOneWidget);
    expect(
      find.descendant(of: sidebarType, matching: find.byType(Image)),
      findsOneWidget,
    );
    final sidebarIcon = tester.widget<Image>(
      find.descendant(of: sidebarType, matching: find.byType(Image)),
    );
    expect(sidebarIcon.image, cardIconProvider);
    expect(sidebarIcon.gaplessPlayback, isTrue);
  });

  testWidgets('catalog Type editor accepts a pasted Base64 image icon', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const pngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
    final state = encodeWorkshopState(
      inventory: const [],
      vendors: const [],
      brands: const [],
      products: const [],
    );

    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-item-types-section')));
    await tester.pumpAndSettle();
    final nameField = find.byKey(const Key('new-custom-type-name'));
    expect(
      tester.getTopLeft(nameField).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const Key('built-in-type-row-catalog:kits')))
            .dy,
      ),
    );
    await tester.ensureVisible(nameField);
    await tester.pumpAndSettle();
    await tester.enterText(nameField, 'Base64 type');
    await tester.tap(find.byKey(const Key('choose-type-icon')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('type-icon-option-lucide:wrench')),
      findsNothing,
    );
    await tester.tap(find.text('Lucide'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('type-icon-search')), 'wrench');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('type-icon-option-lucide:wrench')),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('paste-type-icon-base64')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('type-icon-base64-input')),
      'data:image/png;base64,$pngBase64',
    );
    await tester.tap(find.byKey(const Key('apply-type-icon-base64')));
    await tester.pumpAndSettle();
    expect(find.text('Custom · Custom image'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('add-custom-type')));
    await tester.tap(find.byKey(const Key('add-custom-type')));
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.text('Base64 type'),
      matching: find.byType(ListTile),
    );
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.byType(Image)),
      findsOneWidget,
    );
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

    expect(find.byKey(const Key('custom-item-type')), findsNothing);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const Key('item-type')),
          )
          .initialValue,
      'custom:TYPE-SOAP',
    );
    await tester.tap(find.byKey(const Key('item-type')));
    await tester.pumpAndSettle();
    expect(find.text('Filament'), findsOneWidget);
    expect(find.text('Soap batch'), findsWidgets);
    await tester.tap(find.text('Soap batch').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('custom-field-curetime')), findsOneWidget);
    expect(find.byKey(const Key('custom-field-mold')), findsOneWidget);
    expect(find.byKey(const Key('item-color')), findsOneWidget);
    expect(find.byKey(const Key('printing-instructions')), findsNothing);
    expect(find.byKey(const Key('drying-temperature')), findsNothing);
  });

  testWidgets('custom item saves an optional color', (tester) async {
    const customType = CustomItemTypeRecord(
      id: 'TYPE-SOAP',
      name: 'Soap batch',
    );
    final item = sampleInventory.first.copyWith(
      type: InventoryType.custom,
      customTypeId: customType.id,
      customTypeName: customType.name,
      itemColorName: '',
    );
    InventoryItem? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<InventoryItem>(
                context: context,
                builder: (_) => AddItemDialog(
                  initialItem: item,
                  customItemTypes: const [customType],
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('item-color-name')));
    await tester.enterText(
      find.byKey(const Key('item-color-name')),
      'Workshop Blue',
    );
    await tester.ensureVisible(find.byKey(const Key('item-color')));
    await tester.tap(find.byKey(const Key('open-item-color-picker')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-color-picker-hex')), findsOneWidget);
    expect(find.byKey(const Key('item-color-picker-wheel')), findsOneWidget);
    expect(find.text('H  251°'), findsOneWidget);
    expect(find.text('S  54%'), findsOneWidget);
    expect(find.text('V  100%'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('item-color-preset-Blue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-color-preset-Blue')));
    await tester.ensureVisible(find.byKey(const Key('use-item-color')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('use-item-color')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('save-item')));
    await tester.tap(find.byKey(const Key('save-item')));
    await tester.pumpAndSettle();

    expect(saved?.type, InventoryType.custom);
    expect(saved?.customTypeId, customType.id);
    expect(saved?.itemColorName, '#4C93FF');
    expect(saved?.itemColorLabel, 'Workshop Blue');
  });

  testWidgets('item hex colors validate and save canonically', (tester) async {
    InventoryItem? saved;
    final item = sampleInventory.first.copyWith(itemColorName: '');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<InventoryItem>(
                context: context,
                builder: (_) => AddItemDialog(initialItem: item),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('item-color')));
    await tester.enterText(find.byKey(const Key('item-color')), '#f0a');
    await tester.ensureVisible(find.byKey(const Key('save-item')));
    await tester.tap(find.byKey(const Key('save-item')));
    await tester.pumpAndSettle();

    expect(saved?.itemColorName, '#FF00AA');
  });

  testWidgets('filament color search fills the color name and hex', (
    tester,
  ) async {
    final client = FilamentColorsClient(
      httpClient: MockClient(
        (_) async => http.Response('''
          {
            "results": [{
              "id": 1725,
              "manufacturer": {"name": "Polymaker"},
              "color_name": "Galaxy Black",
              "filament_type": {
                "name": "PolyLite PLA",
                "hot_end_temp": "190-230",
                "bed_temp": "50-60",
                "parent_type": {"name": "PLA"}
              },
              "hex_color": "#17181A",
              "mfr_purchase_link": "https://example.com/galaxy-black"
            }]
          }
        ''', 200),
      ),
    );
    final item = sampleInventory.first.copyWith(
      name: 'Galaxy Black PLA',
      brand: 'Polymaker',
      itemColorName: '',
      itemColorLabel: '',
      printingInstructions: '',
      storageInstructions: '',
      clearFilamentData: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddItemDialog(initialItem: item, filamentColorsClient: client),
        ),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('search-filament-colors')));
    await tester.tap(find.byKey(const Key('search-filament-colors')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('filament-colors-brand')))
          .controller
          ?.text,
      'Polymaker',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('filament-colors-material')))
          .controller
          ?.text,
      'PLA',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('filament-color-result-1725')),
        matching: find.text('Galaxy Black'),
      ),
      findsOneWidget,
    );
    expect(find.text('#17181A'), findsOneWidget);

    await tester.tap(find.byKey(const Key('filament-color-result-1725')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('item-color-name')))
          .controller
          ?.text,
      'Galaxy Black',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('item-color')))
          .controller
          ?.text,
      '#17181A',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('item-name')))
          .controller
          ?.text,
      'Polymaker PolyLite PLA Galaxy Black',
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(
              const ValueKey('item-material-type:filament-MAT-FIL-PLA'),
            ),
          )
          .initialValue,
      'MAT-FIL-PLA',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('printing-instructions')))
          .controller
          ?.text,
      'Nozzle 190-230°C · Bed 50-60°C',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('product-page-url')))
          .controller
          ?.text,
      'https://example.com/galaxy-black',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('drying-temperature')))
          .controller
          ?.text,
      isNotEmpty,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('drying-duration')))
          .controller
          ?.text,
      isNotEmpty,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('storage-instructions')))
          .controller
          ?.text,
      isNotEmpty,
    );
  });

  testWidgets('header FilamentColors search opens a populated add flow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = FilamentColorsClient(
      httpClient: MockClient(
        (_) async => http.Response('''
          {
            "results": [{
              "id": 1725,
              "manufacturer": {"name": "Polymaker"},
              "color_name": "Galaxy Black",
              "filament_type": {
                "name": "PolyLite PLA",
                "hot_end_temp": "190-230",
                "bed_temp": "50-60",
                "parent_type": {"name": "PLA"}
              },
              "hex_color": "#17181A",
              "mfr_purchase_link": "https://example.com/galaxy-black"
            }]
          }
        ''', 200),
      ),
    );
    await tester.pumpWidget(
      InventorinatorApp(
        persistedState: encodeWorkshopState(
          inventory: const [],
          vendors: const [],
          brands: const [],
          products: const [],
        ),
        filamentColorsClient: client,
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('open-filament-colors')));
    await tester.tap(find.byKey(const Key('open-filament-colors')));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a brand, material, or color to search.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('filament-colors-query')),
      'Galaxy Black',
    );
    await tester.tap(find.byKey(const Key('run-filament-colors-search')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filament-color-result-1725')));
    await tester.pumpAndSettle();

    expect(find.text('Add an item'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('item-name')))
          .controller
          ?.text,
      'Polymaker PolyLite PLA Galaxy Black',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('item-color')))
          .controller
          ?.text,
      '#17181A',
    );

    await tester.tap(find.byKey(const Key('save-item')));
    await tester.pumpAndSettle();
    expect(find.text('Polymaker PolyLite PLA Galaxy Black'), findsOneWidget);
  });

  testWidgets('catalog custom types become inventory filters', (tester) async {
    final state = encodeWorkshopState(
      inventory: const [],
      vendors: const [],
      brands: const [],
      products: const [],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-item-types-section')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('new-custom-type-name')),
      'Soap batch',
    );
    await tester.ensureVisible(
      find.byKey(const Key('new-custom-type-can-mark-depleted')),
    );
    tester
        .widget<SwitchListTile>(
          find.byKey(const Key('new-custom-type-can-mark-depleted')),
        )
        .onChanged!(true);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('add-custom-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-custom-type')));
    await tester.pumpAndSettle();
    expect(
      find.text('Item type · Can be marked depleted · 0 inventory items'),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Types'));
    await tester.pumpAndSettle();

    expect(find.text('Soap batch'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is FilterChip &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'custom-type-filter-',
            ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('item types can be renamed without a second filter segment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = encodeWorkshopState(
      inventory: [
        InventoryItem(
          id: 'INV-TYPE-RENAME',
          name: 'Test spool',
          type: InventoryType.filament,
          compatibility: const [],
          added: DateTime(2026),
          cost: 10,
          color: Colors.purple,
        ),
      ],
      vendors: const [],
      brands: const [],
      products: const [],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    expect(find.text('ITEM TYPES'), findsNothing);
    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-item-types-section')));
    await tester.pumpAndSettle();
    final editFilament = find.byKey(
      const Key('edit-built-in-type-item:filament'),
    );
    await tester.ensureVisible(editFilament);
    await tester.pumpAndSettle();
    await tester.tap(editFilament);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-built-in-type-name')),
      'Feedstock',
    );
    await tester.tap(find.byKey(const Key('choose-type-icon')).last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('type-icon-search')),
      'science',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Science'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-built-in-type-name')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Types'));
    await tester.pumpAndSettle();

    final feedstockFilter = find.widgetWithText(FilterChip, 'Feedstock');
    expect(feedstockFilter, findsOneWidget);
    expect(
      find.descendant(
        of: feedstockFilter,
        matching: find.byIcon(Icons.science_outlined),
      ),
      findsOneWidget,
    );
    expect(find.text('FEEDSTOCK'), findsOneWidget);
    expect(find.text('ITEM TYPES'), findsNothing);
  });

  test('renamed item types survive persistence', () {
    final decoded = decodeWorkshopState(
      encodeWorkshopState(
        inventory: const [],
        vendors: const [],
        brands: const [],
        products: const [],
        typeLabelOverrides: const {
          'item:filament': 'Feedstock',
          'catalog:kits': 'Assemblies',
        },
        typeIconOverrides: const {
          'item:filament': 'filament',
          'catalog:kits': 'kit',
        },
        typeDepletionSettings: const {
          'item:filament': false,
          'item:fastener': true,
        },
        typeStatusSettings: const {
          'item:filament': true,
          'item:fastener': true,
        },
      ),
    )!;

    expect(decoded.typeLabelOverrides['item:filament'], 'Feedstock');
    expect(decoded.typeLabelOverrides['catalog:kits'], 'Assemblies');
    expect(decoded.typeIconOverrides['item:filament'], 'filament');
    expect(decoded.typeIconOverrides['catalog:kits'], 'kit');
    expect(decoded.typeDepletionSettings['item:filament'], isFalse);
    expect(decoded.typeDepletionSettings['item:fastener'], isTrue);
    expect(decoded.typeStatusSettings['item:filament'], isTrue);
    expect(decoded.typeStatusSettings['item:fastener'], isTrue);
  });

  test('deleted item types survive persistence', () {
    final decoded = decodeWorkshopState(
      encodeWorkshopState(
        inventory: const [],
        vendors: const [],
        brands: const [],
        products: const [],
        deletedTypeKeys: const {'item:resin', 'catalog:tools'},
      ),
    )!;

    expect(
      decoded.deletedTypeKeys,
      containsAll(['item:resin', 'catalog:tools']),
    );
  });

  testWidgets('owner can delete a built-in item type', (tester) async {
    final state = encodeWorkshopState(
      inventory: [
        InventoryItem(
          id: 'INV-RESIN',
          name: 'Test resin',
          type: InventoryType.resin,
          compatibility: const [],
          added: DateTime(2026),
          cost: 10,
          color: Colors.purple,
        ),
      ],
      vendors: const [],
      brands: const [],
      products: const [],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-item-types-section')));
    await tester.pumpAndSettle();
    final deleteResin = find.byKey(
      const Key('delete-built-in-type-item:resin'),
    );
    await tester.ensureVisible(deleteResin);
    await tester.pumpAndSettle();
    await tester.tap(deleteResin);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-built-in-type')));
    await tester.pumpAndSettle();
    expect(deleteResin, findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, 'Resin'), findsNothing);
    expect(find.text('OTHER'), findsOneWidget);
  });

  testWidgets('recreated catalog type reconnects its existing records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = encodeWorkshopState(
      inventory: const [],
      vendors: const [],
      brands: const [],
      products: const [],
      kits: const [
        KitRecord(id: 'KIT-RECONNECT', name: 'Existing linked kit', bom: []),
      ],
      deletedTypeKeys: const {'catalog:kits'},
    );

    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    expect(find.text('Existing linked kit'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-item-types-section')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('built-in-type-row-catalog:kits')),
      findsNothing,
    );
    final link = find.byKey(const Key('new-type-record-link'));
    await tester.scrollUntilVisible(
      link,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('catalog-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reconnect Kits').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('new-custom-type-name')),
      'Assemblies',
    );
    await tester.tap(find.byKey(const Key('add-custom-type')));
    await tester.pumpAndSettle();

    final restoredRow = find.byKey(const Key('built-in-type-row-catalog:kits'));
    expect(restoredRow, findsOneWidget);
    expect(
      find.descendant(of: restoredRow, matching: find.text('Assemblies')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('type-filter-panel')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, 'Assemblies'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Assemblies'));
    await tester.pumpAndSettle();
    expect(find.text('Existing linked kit'), findsOneWidget);
  });

  testWidgets('custom type filters match only their own inventory items', (
    tester,
  ) async {
    const soapType = CustomItemTypeRecord(id: 'TYPE-SOAP', name: 'Soap batch');
    final state = encodeWorkshopState(
      inventory: [
        InventoryItem(
          id: 'INV-SOAP',
          name: 'Lavender soap',
          type: InventoryType.custom,
          compatibility: const [],
          added: DateTime(2026),
          cost: 4,
          color: const Color(0xff8e75ff),
          itemColorName: 'Lavender',
          customTypeId: soapType.id,
          customTypeName: soapType.name,
        ),
        InventoryItem(
          id: 'INV-PLA',
          name: 'Blue PLA',
          type: InventoryType.filament,
          compatibility: const [],
          added: DateTime(2026),
          cost: 20,
          color: const Color(0xff45d2bd),
        ),
      ],
      vendors: const [],
      brands: const [],
      products: const [],
      customItemTypes: const [soapType],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.tap(find.text('Types'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('custom-type-filter-TYPE-SOAP')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('custom-type-filter-TYPE-SOAP')));
    await tester.pumpAndSettle();

    expect(find.text('Lavender soap'), findsOneWidget);
    expect(find.text('Blue PLA'), findsNothing);
    await tester.ensureVisible(find.text('Colors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Colors'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('color-filter-Lavender')), findsOneWidget);
    expect(find.byKey(const Key('item-color-swatch-INV-SOAP')), findsOneWidget);
  });

  testWidgets('owner can edit and delete a custom inventory type', (
    tester,
  ) async {
    const soapType = CustomItemTypeRecord(
      id: 'TYPE-SOAP',
      name: 'Soap batch',
      contextualFields: ['Mold'],
    );
    final state = encodeWorkshopState(
      inventory: [
        InventoryItem(
          id: 'INV-SOAP',
          name: 'Lavender soap',
          type: InventoryType.custom,
          compatibility: const [],
          added: DateTime(2026),
          cost: 4,
          color: const Color(0xff8e75ff),
          customTypeId: soapType.id,
          customTypeName: soapType.name,
          customFieldValues: const {'Mold': 'Round'},
        ),
      ],
      vendors: const [],
      brands: const [],
      products: const [],
      customItemTypes: const [soapType],
    );
    await tester.pumpWidget(InventorinatorApp(persistedState: state));
    await tester.tap(find.byKey(const Key('open-catalog')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-item-types-section')));
    await tester.pumpAndSettle();

    final editSoap = find.byKey(const Key('edit-custom-type-TYPE-SOAP'));
    await tester.ensureVisible(editSoap);
    await tester.pumpAndSettle();
    await tester.tap(editSoap);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('edit-custom-type-name')),
      'Soap run',
    );
    final showStatus = find.byKey(const Key('edit-custom-type-shows-status'));
    expect(tester.widget<SwitchListTile>(showStatus).value, isFalse);
    await tester.tap(showStatus);
    await tester.tap(find.byKey(const Key('save-custom-type-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Soap run'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('custom-type-row-TYPE-SOAP')),
        matching: find.textContaining('Shows status'),
      ),
      findsOneWidget,
    );

    final deleteSoap = find.byKey(const Key('delete-custom-type-TYPE-SOAP'));
    await tester.ensureVisible(deleteSoap);
    await tester.pumpAndSettle();
    await tester.tap(deleteSoap);
    await tester.pumpAndSettle();
    expect(find.textContaining('will be changed to Other'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-delete-custom-type')));
    await tester.pumpAndSettle();
    expect(find.text('Soap run'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lavender soap'), findsOneWidget);
    expect(find.text('OTHER'), findsOneWidget);
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
