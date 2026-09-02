import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/main.dart';

void main() {
  test('recognizes Android internal identifiers as placeholder names', () {
    expect(isGenericAndroidDeviceName('sdk_gphone64_x86_64'), isTrue);
    expect(isGenericAndroidDeviceName('sdk gphone64 x86 64'), isTrue);
    expect(isGenericAndroidDeviceName('generic_x86_64'), isTrue);
    expect(isGenericAndroidDeviceName('Android SDK built for x86'), isTrue);
    expect(isGenericAndroidDeviceName('Android device'), isTrue);
  });

  test('preserves useful or user-edited device names', () {
    expect(isGenericAndroidDeviceName('David\'s Pixel 9 Pro'), isFalse);
    expect(isGenericAndroidDeviceName('Workshop tablet'), isFalse);
  });
}
