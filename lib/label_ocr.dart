import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

class LabelOcrUnavailable implements Exception {
  const LabelOcrUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

class LabelOcrDraft {
  const LabelOcrDraft({
    required this.imageBytes,
    this.rawText = '',
    this.name = '',
    this.compatibility = '',
    this.printingInstructions = '',
    this.material = '',
    this.brand = '',
    this.filamentEvidence = false,
  });

  final Uint8List imageBytes;
  final String rawText;
  final String name;
  final String compatibility;
  final String printingInstructions;
  final String material;
  final String brand;
  final bool filamentEvidence;
}

Future<LabelOcrDraft> recognizeProductLabel(Uint8List imageBytes) async {
  final text = Platform.isAndroid || Platform.isIOS
      ? await _recognizeMobile(imageBytes)
      : Platform.isLinux
      ? await _recognizeLinux(imageBytes)
      : throw const LabelOcrUnavailable(
          'On-device label OCR is not available on this platform yet.',
        );
  return parseProductLabelText(text, imageBytes);
}

Future<String> _recognizeMobile(Uint8List bytes) async {
  final directory = await Directory.systemTemp.createTemp(
    'inventorinator-ocr-',
  );
  final file = File('${directory.path}/label.jpg');
  try {
    await file.writeAsBytes(bytes, flush: true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      return result.text;
    } finally {
      await recognizer.close();
    }
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<String> _recognizeLinux(Uint8List bytes) async {
  final directory = await Directory.systemTemp.createTemp(
    'inventorinator-ocr-',
  );
  try {
    var executable = 'tesseract';
    Map<String, String>? environment;
    try {
      await Process.run(executable, ['--version']);
    } on ProcessException {
      final bundled = await _prepareBundledLinuxTesseract(directory);
      executable = bundled.$1;
      environment = {'TESSDATA_PREFIX': bundled.$2};
    }

    final decoded = img.decodeImage(bytes);
    final candidates = <({int angle, int pageMode, Uint8List bytes})>[
      // Product labels are often sparse islands of text on a large package.
      // Run both automatic-layout and sparse-text recognition on the original
      // frame before trying the rotated dense-block fallbacks.
      (angle: 0, pageMode: 3, bytes: bytes),
      (angle: 0, pageMode: 11, bytes: bytes),
      if (decoded != null) ...[
        (
          angle: 1001,
          pageMode: 8,
          bytes: Uint8List.fromList(
            img.encodeJpg(
              _enhanceOcrRegion(
                img.copyCrop(
                  decoded,
                  x: (decoded.width * .12).round(),
                  y: 0,
                  width: (decoded.width * .76).round(),
                  height: (decoded.height * .42).round(),
                ),
                4,
              ),
              quality: 95,
            ),
          ),
        ),
        (
          angle: 1000,
          pageMode: 11,
          bytes: Uint8List.fromList(
            img.encodeJpg(
              img.copyResize(
                img.adjustColor(
                  img.grayscale(
                    img.copyCrop(
                      decoded,
                      x: 0,
                      y: 0,
                      width: decoded.width,
                      height: (decoded.height * .6).round(),
                    ),
                  ),
                  contrast: 1.45,
                ),
                width: decoded.width * 2,
              ),
              quality: 94,
            ),
          ),
        ),
        for (final angle in const [-10, -20, 10, 20])
          (
            angle: angle,
            pageMode: 6,
            bytes: Uint8List.fromList(
              img.encodeJpg(img.copyRotate(decoded, angle: angle), quality: 92),
            ),
          ),
      ],
    ];
    var bestText = '';
    var bestScore = -1;
    final recognizedCandidates = <String>[];
    for (final candidate in candidates) {
      final file = File(
        '${directory.path}/label-${candidate.angle}-${candidate.pageMode}.jpg',
      );
      await file.writeAsBytes(candidate.bytes, flush: true);
      final result = await Process.run(executable, [
        file.path,
        'stdout',
        '-l',
        'eng',
        '--psm',
        '${candidate.pageMode}',
      ], environment: environment);
      if (result.exitCode != 0) continue;
      final text = result.stdout.toString();
      recognizedCandidates.add(text);
      final score = _labelTextScore(text);
      if (score > bestScore) {
        bestText = text;
        bestScore = score;
      }
    }
    if (bestText.trim().isEmpty) {
      throw const LabelOcrUnavailable(
        'No readable text was found. Fill the frame with the label and try again.',
      );
    }
    final titleCandidates = recognizedCandidates.where(
      (text) =>
          text != bestText &&
          (_containsApproximatePhrase(text, 'polylite', 3) ||
              _detectKnownBrand(text) != null ||
              RegExp(
                r'\b(?:PLA|PIA|P1A|PL4|PILZ|PILA|PLZ|PETG|PCTG|NYLON|ABS|ASA|TPU)\b',
                caseSensitive: false,
              ).hasMatch(text)),
    );
    return [bestText, ...titleCandidates].join('\n');
  } finally {
    await directory.delete(recursive: true);
  }
}

img.Image _enhanceOcrRegion(img.Image source, int scale) {
  var enhanced = img.copyResize(source, width: source.width * scale);
  enhanced = img.grayscale(enhanced);
  enhanced = img.normalize(enhanced, min: 0, max: 255);
  return img.convolution(
    enhanced,
    filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0],
  );
}

int _labelTextScore(String text) {
  final value = text.toLowerCase();
  const signals = {
    'pla': 8,
    'petg': 8,
    'nylon': 8,
    'abs': 8,
    'asa': 8,
    'tpu': 8,
    'color': 5,
    'diameter': 5,
    'print temp': 6,
    'bed temp': 6,
    'print speed': 6,
    'fan': 3,
    '1.75': 4,
    'kg': 3,
  };
  final structuredScore = signals.entries
      .where((entry) {
        final escaped = RegExp.escape(entry.key);
        return RegExp(r'\b' + escaped + r'\b').hasMatch(value);
      })
      .fold<int>(0, (score, entry) => score + entry.value);
  final titleScore = _containsApproximatePhrase(text, 'polylite', 3) ? 10 : 0;
  final fuzzyPlaScore =
      RegExp(
        r'\b(?:PIA|P1A|PL4|PILZ|PILA|PLZ)\b',
        caseSensitive: false,
      ).hasMatch(text)
      ? 8
      : 0;
  return structuredScore + titleScore + fuzzyPlaScore;
}

Future<(String, String)> _prepareBundledLinuxTesseract(
  Directory directory,
) async {
  const root = 'assets/ocr/linux_x64';
  final executable = File('${directory.path}/tesseract');
  final tessdata = Directory('${directory.path}/tessdata');
  await tessdata.create(recursive: true);
  final executableData = await rootBundle.load('$root/tesseract');
  final languageData = await rootBundle.load('$root/tessdata/eng.traineddata');
  await executable.writeAsBytes(
    executableData.buffer.asUint8List(),
    flush: true,
  );
  await File('${tessdata.path}/eng.traineddata')
      .writeAsBytes(languageData.buffer.asUint8List(), flush: true);
  final chmod = await Process.run('chmod', ['700', executable.path]);
  if (chmod.exitCode != 0) {
    throw LabelOcrUnavailable(
      'The bundled Linux OCR engine could not be started: ${chmod.stderr}',
    );
  }
  return (executable.path, tessdata.path);
}

LabelOcrDraft parseProductLabelText(String rawText, Uint8List imageBytes) {
  final lines = rawText
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.length > 1)
      .toList();
  final materialPatterns = <String, RegExp>{
    'HTPLA': RegExp(r'\bHT\s*P[L1I][A4]\b', caseSensitive: false),
    'PETG': RegExp(r'\bP[E3][T7][G6]\b', caseSensitive: false),
    'PCTG': RegExp(r'\bP[C(][T7][G6]\b', caseSensitive: false),
    'NYLON': RegExp(r'\bNYLON\b', caseSensitive: false),
    'ABS': RegExp(r'\bABS\b', caseSensitive: false),
    'ASA': RegExp(r'\bASA\b', caseSensitive: false),
    'TPU': RegExp(r'\bTPU\b', caseSensitive: false),
    'PLA': RegExp(
      r'\b(?:PLA|PIA|P1A|PL4|PILZ|PILA|PLZ)\b',
      caseSensitive: false,
    ),
  };
  final upper = rawText.toUpperCase();
  var material = '';
  RegExp? matchedMaterialPattern;
  for (final entry in materialPatterns.entries) {
    if (entry.value.hasMatch(upper)) {
      material = entry.key;
      matchedMaterialPattern = entry.value;
      break;
    }
  }
  String? materialLine;
  for (final line in lines) {
    if (matchedMaterialPattern?.hasMatch(line) ?? false) {
      materialLine = line;
      break;
    }
  }
  final color = _valueNearLabel(lines, const ['color', 'colour']);
  final isPolyLite = _containsApproximatePhrase(rawText, 'polylite', 3);
  final materialOnly =
      materialLine != null &&
      materialLine.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase() ==
          material;
  final detectedBrand =
      _detectKnownBrand(rawText) ??
      (materialOnly
          ? _likelyBrandBeforeMaterial(lines, lines.indexOf(materialLine))
          : null);
  final variant = materialLine == null
      ? null
      : _likelyVariantAfterMaterial(lines, lines.indexOf(materialLine));
  final likelyTitle = isPolyLite
      ? ['PolyLite', if (material.isNotEmpty) material].join(' ')
      : variant != null
      ? '$variant $material'
      : detectedBrand != null
      ? '$detectedBrand $material'
      : materialLine ?? _likelyProductTitle(lines);
  final nameParts = <String>[?likelyTitle];
  if (color.isNotEmpty &&
      !(likelyTitle?.toLowerCase().contains(color.toLowerCase()) ?? false)) {
    nameParts.add(color);
  }

  final compatibility = <String>[];
  final diameter = RegExp(
    r'\b\d{1,3}(?:\.\d+)?\s*mm\b',
    caseSensitive: false,
  ).firstMatch(rawText)?.group(0);
  final weight = RegExp(
    r'\b\d(?:\.\d+)?\s*kg\b',
    caseSensitive: false,
  ).firstMatch(rawText)?.group(0);
  if (diameter != null) {
    final compact = diameter.replaceAll(' ', '');
    compatibility.add(compact.toLowerCase() == '175mm' ? '1.75mm' : compact);
  }
  if (weight != null) compatibility.add(weight.replaceAll(' ', ''));

  final instructionLines = lines.where((line) {
    final value = line.toLowerCase();
    return value.contains('print temp') ||
        value.contains('printing temp') ||
        value.contains('bed temp') ||
        value.contains('print speed') ||
        value.contains('printing speed') ||
        value == 'fan on' ||
        value == 'fan off';
  }).toList();
  final temperatures = RegExp(
    r'\b\d{2,3}\s*[-–]\s*\d{2,3}\s*[^A-Za-z0-9]{0,3}c\b',
    caseSensitive: false,
  ).allMatches(rawText).map((match) => match.group(0)!.trim()).toList();
  final speed = RegExp(
    r'(?:up\s*to\s*)?\d{2,3}(?:\s*[-–]\s*\d{2,3})?\s*mm\s*/\s*s',
    caseSensitive: false,
  ).firstMatch(rawText)?.group(0);
  final fan = RegExp(
    r'\bfan\s*(?:on|off)\b',
    caseSensitive: false,
  ).firstMatch(rawText)?.group(0);
  final structuredInstructions = <String>[
    if (temperatures.isNotEmpty) 'Print Temp ${temperatures.first}',
    if (temperatures.length > 1) 'Bed Temp ${temperatures[1]}',
    if (speed != null) 'Print Speed $speed',
    ?fan,
  ];
  final instructions = structuredInstructions.isNotEmpty
      ? structuredInstructions.join(' · ')
      : instructionLines.join(' · ');
  final filamentEvidence =
      material.isNotEmpty ||
      RegExp(
        r'\bfilament\b|\bdiameter\b|\b1[.,]?75\s*mm\b',
        caseSensitive: false,
      ).hasMatch(rawText) ||
      (diameter != null && temperatures.isNotEmpty);

  return LabelOcrDraft(
    imageBytes: imageBytes,
    rawText: rawText.trim(),
    name: nameParts.join(' · '),
    compatibility: compatibility.join(', '),
    printingInstructions: instructions,
    material: material,
    brand: detectedBrand ?? '',
    filamentEvidence: filamentEvidence,
  );
}

String? _likelyBrandBeforeMaterial(List<String> lines, int materialIndex) {
  if (materialIndex <= 0) return null;
  final generic = RegExp(
    r'^(?:3d\s+printer\s+filament|printer\s+filament|filament|sku|color|colour|diameter|weight|printing?\s+temp|bed\s+temp|printing?\s+speed|fan)\b',
    caseSensitive: false,
  );
  for (var index = materialIndex - 1; index >= 0; index--) {
    final line = lines[index];
    if (generic.hasMatch(line) || RegExp(r'^\(?\d').hasMatch(line)) continue;
    if (line.length <= 40 &&
        RegExp(r'^[A-Za-z][A-Za-z0-9 .+&\-]{2,}$').hasMatch(line) &&
        _humanTextScore(line) >= 3) {
      return line;
    }
  }
  return null;
}

String? _detectKnownBrand(String rawText) {
  final words = rawText
      .toLowerCase()
      .split(RegExp(r'[^a-z]+'))
      .where((word) => word.isNotEmpty);
  if (words.any(
    (word) =>
        RegExp(r'^[a-z]{0,2}c.*(?:cad|ced)$').hasMatch(word) &&
        _editDistance(word, 'cookiecad') <= 5,
  )) {
    return 'Cookiecad';
  }
  const brands = {'Kaaber': 1, 'Polymaker': 2, 'MatterHackers': 2};
  for (final entry in brands.entries) {
    if (_containsApproximatePhrase(
      rawText,
      entry.key.toLowerCase(),
      entry.value,
    )) {
      return entry.key;
    }
  }
  return null;
}

String? _likelyVariantAfterMaterial(List<String> lines, int materialIndex) {
  if (materialIndex < 0) return null;
  final excluded = RegExp(
    r'^(?:made\s+in|sku|color|colour|diameter|weight|empty\s+spool|printing?\s+temp|bed\s+temp|printing?\s+speed|fan)\b',
    caseSensitive: false,
  );
  for (var index = materialIndex + 1; index < lines.length; index++) {
    final line = lines[index];
    if (excluded.hasMatch(line)) continue;
    if (RegExp(r'\d{2,3}\s*[-–~]|\d+\s*(?:mm|kg)').hasMatch(line)) {
      continue;
    }
    if (line.length <= 40 &&
        RegExp(r'^[A-Za-z][A-Za-z0-9 .+&\-]{2,}$').hasMatch(line) &&
        _humanTextScore(line) >= 6) {
      return line;
    }
  }
  return null;
}

String? _likelyProductTitle(List<String> lines) {
  final excluded = RegExp(
    r'^(?:sku|color|colour|diameter|weight|print temp|bed temp|print speed|fan)\b',
    caseSensitive: false,
  );
  final candidates = lines.where((line) {
    if (line.length < 3 || line.length > 70 || excluded.hasMatch(line)) {
      return false;
    }
    if (RegExp(r'\d{2,3}\s*[-–]|\d+\s*(?:mm|kg)|\|{2,}').hasMatch(line)) {
      return false;
    }
    final words = RegExp(r'[A-Za-z]{2,}').allMatches(line).length;
    return words >= 1 && words <= 7 && RegExp(r'[A-Za-z]{3,}').hasMatch(line);
  }).toList();
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => _titleScore(b).compareTo(_titleScore(a)));
  return _titleScore(candidates.first) >= 5 ? candidates.first : null;
}

int _titleScore(String value) {
  final lower = value.toLowerCase();
  var score = _humanTextScore(value);
  if (RegExp(r'poly|filament|p[l1i][a4]|petg|pctg|nylon|abs|asa|tpu')
      .hasMatch(lower)) {
    score += 12;
  }
  if (RegExp(r'\b(?:new|made in|rohs)\b').hasMatch(lower)) score -= 8;
  return score;
}

bool _containsApproximatePhrase(String source, String target, int maxDistance) {
  final words = source
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  for (var start = 0; start < words.length; start++) {
    var candidate = '';
    for (var count = 1; count <= 3 && start + count <= words.length; count++) {
      candidate += words[start + count - 1];
      if ((candidate.length - target.length).abs() <= maxDistance &&
          _editDistance(candidate, target) <= maxDistance) {
        return true;
      }
      if (candidate.length > target.length + maxDistance) break;
    }
  }
  return false;
}

int _editDistance(String left, String right) {
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var row = 1; row <= left.length; row++) {
    final current = List<int>.filled(right.length + 1, 0)..[0] = row;
    for (var column = 1; column <= right.length; column++) {
      final substitution =
          left.codeUnitAt(row - 1) == right.codeUnitAt(column - 1) ? 0 : 1;
      current[column] = [
        current[column - 1] + 1,
        previous[column] + 1,
        previous[column - 1] + substitution,
      ].reduce((a, b) => a < b ? a : b);
    }
    previous = current;
  }
  return previous.last;
}

String _valueNearLabel(List<String> lines, List<String> labels) {
  final fieldLabels = RegExp(
    r'^(?:sku|color|colour|diameter|weight|print temp|bed temp|print speed|fan)\b',
    caseSensitive: false,
  );
  final candidates = <String>[];
  for (var index = 0; index < lines.length; index++) {
    final lower = lines[index].toLowerCase();
    if (!labels.any((label) => lower.startsWith(label))) continue;
    final separator = lines[index].indexOf(':');
    if (separator >= 0) candidates.add(lines[index].substring(separator + 1));
    if (index + 1 < lines.length && !fieldLabels.hasMatch(lines[index + 1])) {
      candidates.add(lines[index + 1]);
    }
  }
  candidates.sort((a, b) => _humanTextScore(b).compareTo(_humanTextScore(a)));
  return candidates
      .firstWhere(
        (candidate) => _humanTextScore(candidate) >= 5,
        orElse: () => '',
      )
      .trim();
}

int _humanTextScore(String text) {
  if (text.length > 80) return -1;
  final words = RegExp(r'[A-Za-z]{2,}').allMatches(text).length;
  final noise = RegExp(r'[^A-Za-z0-9 .+&\-]').allMatches(text).length;
  return words * 3 - noise;
}
