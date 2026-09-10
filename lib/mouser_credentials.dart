import 'dart:convert';

import 'local_database.dart';

class MouserCredentials {
  const MouserCredentials({this.apiKey = ''});
  final String apiKey;
  bool get configured => apiKey.isNotEmpty;
  Map<String, dynamic> toJson() => {'api_key': apiKey};
  factory MouserCredentials.fromJson(Map<String, dynamic> json) =>
      MouserCredentials(apiKey: json['api_key'] as String? ?? '');
}

String mouserScope(String url, String? workspaceId) => workspaceId == null
    ? 'local'
    : '${url.trim().replaceFirst(RegExp(r'/+$'), '')}|$workspaceId';

class StoredMouserCredentials {
  const StoredMouserCredentials(this.credentials, this.revision, this.pending);
  final MouserCredentials credentials;
  final int revision;
  final bool pending;
}

/// Device-private preferences are excluded from portable inventory exports.
class MouserCredentialStore {
  MouserCredentialStore(this.database, this.scope);
  final LocalDatabase database;
  final String scope;
  String get _key =>
      'mouser_credentials:${base64Url.encode(utf8.encode(scope))}';
  StoredMouserCredentials? read() {
    final raw = database.loadStringPreference(_key, fallback: '');
    if (raw.isEmpty) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return StoredMouserCredentials(
      MouserCredentials.fromJson(json),
      json['revision'] as int,
      json['pending'] == true,
    );
  }

  void save(MouserCredentials credentials, {required bool pending}) {
    _write(credentials, (read()?.revision ?? 0) + 1, pending);
  }

  bool acknowledge(int revision) {
    final current = read();
    if (current == null || current.revision != revision) return false;
    _write(current.credentials, revision, false);
    return true;
  }

  bool restore(MouserCredentials credentials, int? expectedRevision) {
    final current = read();
    if (current?.revision != expectedRevision || current?.pending == true) {
      return false;
    }
    save(credentials, pending: false);
    return true;
  }

  void _write(MouserCredentials credentials, int revision, bool pending) {
    database.saveStringPreference(
      _key,
      jsonEncode({
        ...credentials.toJson(),
        'revision': revision,
        'pending': pending,
      }),
    );
  }
}
