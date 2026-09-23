import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/label_ocr.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory appDir;

  setUp(() {
    appDir = Directory.systemTemp.createTempSync('inventorinator-win-ocr-');
  });

  tearDown(() => appDir.deleteSync(recursive: true));

  String bundleRoot() => p.join(appDir.path, 'data', 'ocr', 'windows_x64');

  void install({bool engine = true, bool language = true}) {
    Directory(p.join(bundleRoot(), 'tessdata')).createSync(recursive: true);
    if (engine) File(p.join(bundleRoot(), 'tesseract.exe')).createSync();
    if (language) {
      File(p.join(bundleRoot(), 'tessdata', 'eng.traineddata')).createSync();
    }
  }

  test('finds the engine and language data installed beside the app', () {
    install();

    final (executable, tessdata) = locateBundledWindowsTesseract(
      p.join(appDir.path, 'Inventorinator.exe'),
    );

    expect(executable, p.join(bundleRoot(), 'tesseract.exe'));
    expect(tessdata, p.join(bundleRoot(), 'tessdata'));
  });

  test('reports a missing engine like the Linux bundle does', () {
    install(engine: false);

    expect(
      () => locateBundledWindowsTesseract(
        p.join(appDir.path, 'Inventorinator.exe'),
      ),
      throwsA(
        isA<LabelOcrUnavailable>().having(
          (error) => error.message,
          'message',
          contains('bundled Windows OCR engine is not installed'),
        ),
      ),
    );
  });

  test('reports missing English language data', () {
    install(language: false);

    expect(
      () => locateBundledWindowsTesseract(
        p.join(appDir.path, 'Inventorinator.exe'),
      ),
      throwsA(isA<LabelOcrUnavailable>()),
    );
  });
}
