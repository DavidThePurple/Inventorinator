import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/main.dart';

void main() {
  test('spool usage records round-trip with gram totals and outcome', () {
    final record = SpoolUsageRecord(
      id: 'USAGE-1',
      spoolId: 'INV-1',
      recordedAt: DateTime.utc(2026, 9, 4),
      gramsUsed: 18.5,
      gramsWaste: 2.25,
      outcome: SpoolPrintOutcome.failed,
      project: 'Calibration cube',
      wasteReason: 'Warped first layer',
    );
    final restored = decodeWorkshopState(
      encodeWorkshopState(
        inventory: const [],
        vendors: const [],
        brands: const [],
        products: const [],
        spoolUsage: [record],
      ),
    );

    expect(restored, isNotNull);
    expect(restored!.spoolUsage.single.gramsUsed, 18.5);
    expect(restored.spoolUsage.single.gramsWaste, 2.25);
    expect(restored.spoolUsage.single.totalGrams, 20.75);
    expect(restored.spoolUsage.single.outcome, SpoolPrintOutcome.failed);
    expect(restored.spoolUsage.single.wasteReason, 'Warped first layer');
  });
}
