import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/filament_drying.dart';
import 'package:inventorinator/main.dart';
import 'package:inventorinator/supabase_sync.dart';

InventoryItem spool({
  int? duration,
  double? weight,
  String material = 'PETG',
}) => InventoryItem(
  id: 'test-spool',
  name: 'Test spool',
  type: InventoryType.filament,
  compatibility: const [],
  added: DateTime.utc(2026),
  cost: 0,
  color: Colors.blue,
  dryingMinutes: duration,
  materialName: material,
  filamentWeightGrams: weight,
);

void main() {
  test('material defaults, blend aliases and missing weight', () {
    expect(defaultFilamentDryingMinutes(material: 'PLA'), 360);
    expect(defaultFilamentDryingMinutes(material: 'ASA'), 240);
    expect(defaultFilamentDryingMinutes(material: 'PA6-CF'), 720);
    expect(defaultFilamentDryingMinutes(material: 'PVA'), 480);
    expect(defaultFilamentDryingMinutes(material: 'PC'), 300);
    expect(defaultFilamentDryingMinutes(material: 'Custom blend'), 360);
    for (final weight in [
      null,
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      1000.0,
    ]) {
      expect(
        defaultFilamentDryingMinutes(material: 'PETG', weightGrams: weight),
        360,
      );
    }
  });
  test('per-spool weight changes estimates while overrides remain exact', () {
    expect(filamentDryingDuration(spool(weight: 500)), 270);
    expect(filamentDryingDuration(spool(weight: 2000)), 510);
    expect(filamentDryingDuration(spool(duration: 123, weight: 2000)), 123);
    expect(filamentDryingDuration(spool().copyWith(quantity: 8)), 360);
    expect(filamentDryingDuration(spool(), requireManual: true), isNull);
    expect(
      filamentDryingDuration(spool(duration: 90), requireManual: true),
      90,
    );
    expect(
      filamentDryingDuration(spool().copyWith(type: InventoryType.printedPart)),
      isNull,
    );
  });
  test('workspace policy defaults off and survives persistence', () {
    const config = SupabaseConfig(url: '', publishableKey: '');
    expect(config.requireManualDryingTimes, isFalse);
    expect(
      SupabaseConfig.fromJson(
        config.copyWith(requireManualDryingTimes: true).toJson(),
      ).requireManualDryingTimes,
      isTrue,
    );
  });
  test('automatic cycle keeps its original duration when weight changes', () {
    final start = DateTime.utc(2026);
    final running = spool().copyWith(
      filamentStatus: FilamentStatus.drying,
      dryingRemaining: 360,
      dryingStartedAt: start,
      filamentWeightGrams: 2000,
    );
    expect(
      dryingMinutesRemaining(
        running,
        now: start.add(const Duration(minutes: 60)),
      ),
      300,
    );
  });
  for (final manual in [false, true]) {
    testWidgets('start drying without override, Owner policy $manual', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      InventoryItem? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ItemDetailsPanel(
              item: spool(),
              onChanged: (value) => result = value,
              requireManualDryingTimes: manual,
              machines: const [],
              machineTypes: const [],
              spoolTypes: starterSpoolTypes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('status-drying')));
      await tester.tap(find.byKey(const Key('status-drying')));
      await tester.pumpAndSettle();
      if (manual) {
        expect(result, isNull);
        expect(find.textContaining('Owner requires'), findsOneWidget);
      } else {
        expect(result?.filamentStatus, FilamentStatus.drying);
        expect(result?.dryingRemaining, 360);
        expect(result?.dryingMinutes, isNull);
        expect(result?.dryingStartedAt, isNotNull);
      }
    });
  }
}
