import 'dart:math' as math;

/// Timer estimates, not a measurement of moisture or a heater setting.
/// The weight adjustment is an application heuristic; see docs/filament-drying.md.
int defaultFilamentDryingMinutes({
  required String material,
  double? weightGrams,
}) {
  final text = material.toUpperCase();
  bool token(String pattern) =>
      RegExp('(?:^|[^A-Z0-9])(?:$pattern)(?:[^A-Z0-9]|\$)').hasMatch(text);
  final base = token('NYLON|PA(?:6|11|12|66|HT)?|PPA')
      ? 720
      : token('PVA|BVOH')
      ? 480
      : token('ASA')
      ? 240
      : token('PC|POLYCARBONATE')
      ? 300
      : 360; // PLA, HTPLA, PETG, PCTG, ABS, TPU and unknown materials.
  final grams = weightGrams != null && weightGrams.isFinite && weightGrams > 0
      ? weightGrams
      : 1000.0;
  final factor = math.max(0.75, math.sqrt(grams / 1000));
  return (base * factor / 15).ceil() * 15;
}
