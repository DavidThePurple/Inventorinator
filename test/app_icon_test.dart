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

  test('Android uses the transparent launcher raster without a system plate', () {
    // Samsung launchers can turn an adaptive icon with a transparent
    // background into an opaque square. Keep the manifest on the transparent
    // raster and deliberately omit adaptive resources.
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, isNot(contains('android:roundIcon')));
    expect(
      File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml')
          .existsSync(),
      isFalse,
    );
    expect(
      File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml')
          .existsSync(),
      isFalse,
    );
  });
}
