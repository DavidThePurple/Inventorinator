import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void _expectTransparentCorner(String path) {
  final bytes = File(path).readAsBytesSync();
  final image = img.decodeImage(bytes);
  expect(image, isNotNull, reason: 'Could not decode $path');
  expect(
    image!.getPixel(0, 0).a,
    0,
    reason: '$path must keep the raygun on a transparent background.',
  );
}

void main() {
  test('every packaged launcher icon preserves raygun transparency', () {
    for (final path in [
      'assets/images/inventorinator-raygun-v2.png',
      'linux/packaging/app_icon_512.png',
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png',
      'windows/runner/resources/app_icon.ico',
    ]) {
      _expectTransparentCorner(path);
    }
  });

  test('Android uses a transparent adaptive launcher icon', () {
    for (final path in [
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml',
    ]) {
      final xml = File(path).readAsStringSync();
      expect(xml, contains('<adaptive-icon'));
      expect(xml, contains('@android:color/transparent'));
      expect(xml, contains('@mipmap/ic_launcher_foreground'));
    }
  });
}
