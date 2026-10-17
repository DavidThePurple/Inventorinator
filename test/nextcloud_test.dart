import 'package:inventorinator/nextcloud.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds an encoded Nextcloud WebDAV library URL', () {
    const config = NextcloudConfig(
      serverUrl: 'https://cloud.example.test/nextcloud/',
      username: 'David Smith',
      libraryFolder: 'Print library',
    );

    expect(
      config.davRoot.toString(),
      'https://cloud.example.test/nextcloud/remote.php/dav/files/David%20Smith/Print%20library',
    );
    expect(config.toJson().containsKey('appPassword'), isFalse);
  });
}
