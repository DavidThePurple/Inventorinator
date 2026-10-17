import 'dart:convert';

import 'package:http/http.dart' as http;

/// Per-device connection details for a future optional Nextcloud library.
///
/// An app password is deliberately kept out of [toJson] so ordinary state
/// exports and remote sync never leak a Nextcloud credential.
class NextcloudConfig {
  const NextcloudConfig({
    required this.serverUrl,
    required this.username,
    this.libraryFolder = 'Inventorinator',
    this.appPassword = '',
  });

  final String serverUrl;
  final String username;
  final String libraryFolder;
  final String appPassword;

  bool get isConfigured =>
      Uri.tryParse(serverUrl)?.hasScheme == true && username.trim().isNotEmpty;

  Uri get davRoot {
    final server = Uri.parse(serverUrl.trim());
    final base = server.path.endsWith('/')
        ? server.path.substring(0, server.path.length - 1)
        : server.path;
    return server.replace(
      path:
          '$base/remote.php/dav/files/${Uri.encodeComponent(username.trim())}/${Uri.encodeComponent(libraryFolder.trim())}',
    );
  }

  Map<String, dynamic> toJson() => {
    'serverUrl': serverUrl,
    'username': username,
    'libraryFolder': libraryFolder,
  };

  factory NextcloudConfig.fromJson(Map<String, dynamic> json) =>
      NextcloudConfig(
        serverUrl: json['serverUrl'] as String? ?? '',
        username: json['username'] as String? ?? '',
        libraryFolder: json['libraryFolder'] as String? ?? 'Inventorinator',
      );
}

class NextcloudConnectionResult {
  const NextcloudConnectionResult({
    required this.connected,
    required this.message,
    this.statusCode,
  });

  final bool connected;
  final String message;
  final int? statusCode;
}

/// Small WebDAV boundary used by the later file browser and printed-parts queue.
/// It establishes the Nextcloud-specific endpoint and safe app-password auth
/// without coupling the eventual UI to raw HTTP calls.
class NextcloudClient {
  NextcloudClient(this.config, {http.Client? client})
    : _client = client ?? http.Client();

  final NextcloudConfig config;
  final http.Client _client;

  Future<NextcloudConnectionResult> checkConnection() async {
    if (!config.isConfigured || config.appPassword.trim().isEmpty) {
      return const NextcloudConnectionResult(
        connected: false,
        message: 'Add a server, user name, and Nextcloud app password first.',
      );
    }
    try {
      final response = await _client
          .send(
            http.Request('PROPFIND', config.davRoot)
              ..headers.addAll({
                'Authorization':
                    'Basic ${base64Encode(utf8.encode('${config.username}:${config.appPassword}'))}',
                'Depth': '0',
              }),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 207 || response.statusCode == 200) {
        return NextcloudConnectionResult(
          connected: true,
          message: 'Connected to ${config.libraryFolder}.',
          statusCode: response.statusCode,
        );
      }
      return NextcloudConnectionResult(
        connected: false,
        message: response.statusCode == 401 || response.statusCode == 403
            ? 'Nextcloud rejected that app password.'
            : 'Nextcloud returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    } catch (_) {
      return const NextcloudConnectionResult(
        connected: false,
        message: 'Could not reach the Nextcloud WebDAV endpoint.',
      );
    }
  }

  void dispose() => _client.close();
}
