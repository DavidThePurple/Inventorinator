import 'dart:convert';

import 'local_database.dart';

class DigiKeyCredentials {
  const DigiKeyCredentials({
    this.clientId = '',
    this.clientSecret = '',
    this.sandbox = false,
  });
  final String clientId, clientSecret;
  final bool sandbox;
  bool get configured => clientId.isNotEmpty && clientSecret.isNotEmpty;
  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'client_secret': clientSecret,
    'sandbox': sandbox,
  };
  factory DigiKeyCredentials.fromJson(Map<String, dynamic> json) =>
      DigiKeyCredentials(
        clientId: json['client_id'] as String? ?? '',
        clientSecret: json['client_secret'] as String? ?? '',
        sandbox: json['sandbox'] == true,
      );
}

String digiKeyScope(String url, String? workspaceId) => workspaceId == null
    ? 'local'
    : '${url.trim().replaceFirst(RegExp(r'/+$'), '')}|$workspaceId';

class StoredDigiKeyCredentials {
  const StoredDigiKeyCredentials(this.credentials, this.revision, this.pending);
  final DigiKeyCredentials credentials;
  final int revision;
  final bool pending;
}

/// Device-private preferences are excluded from portable inventory exports.
class DigiKeyCredentialStore {
  DigiKeyCredentialStore(this.database, this.scope);
  final LocalDatabase database;
  final String scope;
  String get _key =>
      'digikey_credentials:${base64Url.encode(utf8.encode(scope))}';
  StoredDigiKeyCredentials? read() {
    final raw = database.loadStringPreference(_key, fallback: '');
    if (raw.isEmpty) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return StoredDigiKeyCredentials(
      DigiKeyCredentials.fromJson(json),
      json['revision'] as int,
      json['pending'] == true,
    );
  }

  void save(DigiKeyCredentials credentials, {required bool pending}) {
    _write(credentials, (read()?.revision ?? 0) + 1, pending);
  }

  bool acknowledge(int revision) {
    final current = read();
    if (current == null || current.revision != revision) return false;
    _write(current.credentials, revision, false);
    return true;
  }

  bool restore(DigiKeyCredentials credentials, int? expectedRevision) {
    final current = read();
    if (current?.revision != expectedRevision || current?.pending == true) {
      return false;
    }
    save(credentials, pending: false);
    return true;
  }

  void _write(DigiKeyCredentials credentials, int revision, bool pending) {
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
