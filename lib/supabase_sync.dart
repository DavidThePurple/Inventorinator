import 'dart:convert';

import 'package:http/http.dart' as http;

const requiredInventorinatorSchemaVersion = 11;

bool canManageWorkspaceDevices(String? role) =>
    role == 'owner' || role == 'admin' || role == 'manager';

bool canRemoveWorkspaceDevices(String? role) => role == 'owner';

String visibleSyncErrorForRole(Object error, String? role) {
  if (error is SupabaseSyncException && error.isInvalidRefreshToken) {
    return canManageWorkspaceDevices(role)
        ? 'This device’s Remote Sync session expired. Pair it again to manage access.'
        : '';
  }
  return error.toString();
}

enum WorkspaceRole {
  admin,
  manager,
  editor,
  builder;

  static WorkspaceRole fromServer(String? value) => switch (value) {
    'owner' || 'admin' => WorkspaceRole.admin,
    'manager' => WorkspaceRole.manager,
    'editor' => WorkspaceRole.editor,
    _ => WorkspaceRole.builder,
  };

  bool get canDeleteDatabase => this == WorkspaceRole.admin;
  bool get canHardDeleteItems => this == WorkspaceRole.admin;
  bool get canCreateInventory =>
      this == WorkspaceRole.admin || this == WorkspaceRole.manager;
  bool get canEditInventory => this != WorkspaceRole.builder;
  bool get canArchiveInventory =>
      this == WorkspaceRole.admin || this == WorkspaceRole.manager;
  bool get canManageCatalog =>
      this == WorkspaceRole.admin || this == WorkspaceRole.manager;
  bool get canCreateBuilds => this != WorkspaceRole.builder;
  bool get canShareBuilds => this != WorkspaceRole.builder;
  bool get canOperateBuilds => true;
}

class SupabaseConfig {
  const SupabaseConfig({
    required this.url,
    required this.publishableKey,
    this.syncMode = '',
    this.email = '',
    this.userId,
    this.workspaceId,
    this.workspaceRole,
    this.accessToken,
    this.accessTokenExpiresAt,
    this.refreshToken,
    this.lastSyncedAt,
    this.lastSyncedStateJson,
  });

  final String url;
  final String publishableKey;
  final String syncMode;
  final String email;
  final String? userId;
  final String? workspaceId;
  final String? workspaceRole;
  final String? accessToken;
  final DateTime? accessTokenExpiresAt;
  final String? refreshToken;
  final DateTime? lastSyncedAt;
  final String? lastSyncedStateJson;

  bool get isConfigured {
    final server = Uri.tryParse(url);
    return server != null &&
        {'http', 'https'}.contains(server.scheme) &&
        server.host.isNotEmpty &&
        publishableKey.isNotEmpty;
  }

  bool get hasSession => userId != null && refreshToken != null;

  SupabaseSession? get cachedSession {
    final access = accessToken;
    final refresh = refreshToken;
    final user = userId;
    final expires = accessTokenExpiresAt;
    if (access == null ||
        refresh == null ||
        user == null ||
        expires == null ||
        !expires.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 1)),
        )) {
      return null;
    }
    return SupabaseSession(
      accessToken: access,
      refreshToken: refresh,
      userId: user,
      expiresAt: expires,
    );
  }

  SupabaseConfig copyWith({
    String? url,
    String? publishableKey,
    String? syncMode,
    String? email,
    String? userId,
    String? workspaceId,
    String? workspaceRole,
    String? accessToken,
    DateTime? accessTokenExpiresAt,
    String? refreshToken,
    DateTime? lastSyncedAt,
    String? lastSyncedStateJson,
  }) => SupabaseConfig(
    url: url ?? this.url,
    publishableKey: publishableKey ?? this.publishableKey,
    syncMode: syncMode ?? this.syncMode,
    email: email ?? this.email,
    userId: userId ?? this.userId,
    workspaceId: workspaceId ?? this.workspaceId,
    workspaceRole: workspaceRole ?? this.workspaceRole,
    accessToken: accessToken ?? this.accessToken,
    accessTokenExpiresAt: accessTokenExpiresAt ?? this.accessTokenExpiresAt,
    refreshToken: refreshToken ?? this.refreshToken,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    lastSyncedStateJson: lastSyncedStateJson ?? this.lastSyncedStateJson,
  );

  Map<String, Object?> toJson() => {
    'url': url,
    'publishableKey': publishableKey,
    'syncMode': syncMode,
    'email': email,
    'userId': userId,
    'workspaceId': workspaceId,
    'workspaceRole': workspaceRole,
    'accessToken': accessToken,
    'accessTokenExpiresAt': accessTokenExpiresAt?.toIso8601String(),
    'refreshToken': refreshToken,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    'lastSyncedStateJson': lastSyncedStateJson,
  };

  factory SupabaseConfig.fromJson(Map<String, dynamic> json) => SupabaseConfig(
    url: json['url'] as String? ?? '',
    publishableKey: json['publishableKey'] as String? ?? '',
    syncMode: json['syncMode'] as String? ?? '',
    email: json['email'] as String? ?? '',
    userId: json['userId'] as String?,
    workspaceId: json['workspaceId'] as String?,
    workspaceRole: json['workspaceRole'] as String?,
    accessToken: json['accessToken'] as String?,
    accessTokenExpiresAt: json['accessTokenExpiresAt'] == null
        ? null
        : DateTime.parse(json['accessTokenExpiresAt'] as String).toUtc(),
    refreshToken: json['refreshToken'] as String?,
    lastSyncedAt: json['lastSyncedAt'] == null
        ? null
        : DateTime.parse(json['lastSyncedAt'] as String),
    lastSyncedStateJson: json['lastSyncedStateJson'] as String?,
  );
}

class SupabaseSession {
  const SupabaseSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    this.expiresAt,
  });
  final String accessToken;
  final String refreshToken;
  final String userId;
  final DateTime? expiresAt;
}

class CloudWorkshopState {
  const CloudWorkshopState({required this.stateJson, required this.updatedAt});
  final String stateJson;
  final DateTime updatedAt;
}

class WorkspaceRecovery {
  const WorkspaceRecovery({required this.workspaceId, required this.key});
  final String workspaceId;
  final String key;

  factory WorkspaceRecovery.fromRpc(Object? value) {
    final result = value as Map<String, dynamic>;
    return WorkspaceRecovery(
      workspaceId: result['workspace_id'] as String,
      key: result['recovery_key'] as String,
    );
  }
}

class WorkspaceDevice {
  const WorkspaceDevice({
    required this.userId,
    required this.name,
    required this.role,
    required this.joinedAt,
    required this.lastSeenAt,
  });
  final String userId;
  final String name;
  final String role;
  final DateTime joinedAt;
  final DateTime lastSeenAt;
}

class SupabaseSyncException implements Exception {
  const SupabaseSyncException(this.message);
  final String message;

  bool get isInvalidRefreshToken {
    final normalized = message.toLowerCase();
    return normalized.contains('refresh token') &&
        (normalized.contains('already used') ||
            normalized.contains('invalid') ||
            normalized.contains('expired') ||
            normalized.contains('not found'));
  }

  @override
  String toString() => message;
}

class SupabaseSyncService {
  SupabaseSyncService(this.config, {http.Client? client})
    : _client = client ?? http.Client();

  final SupabaseConfig config;
  final http.Client _client;
  static const _requestTimeout = Duration(seconds: 20);

  Future<http.Response> _request(Future<http.Response> request) =>
      request.timeout(
        _requestTimeout,
        onTimeout: () => throw const SupabaseSyncException(
          'The sync server did not respond within 20 seconds.',
        ),
      );

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(config.url.replaceFirst(RegExp(r'/$'), ''));
    return base.replace(path: '${base.path}$path', queryParameters: query);
  }

  Map<String, String> get _baseHeaders => {
    'apikey': config.publishableKey,
    'Content-Type': 'application/json',
  };

  Future<void> verifyServer() async {
    final response = await _request(
      _client.get(_uri('/auth/v1/health'), headers: _baseHeaders),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SupabaseSyncException(_message(response));
    }
  }

  Future<SupabaseSession> signIn(String email, String password) async {
    final response = await _request(
      _client.post(
        _uri('/auth/v1/token', {'grant_type': 'password'}),
        headers: _baseHeaders,
        body: jsonEncode({'email': email.trim(), 'password': password}),
      ),
    );
    return _sessionFromResponse(response);
  }

  Future<SupabaseSession> signInAnonymously() async {
    final response = await _request(
      _client.post(_uri('/auth/v1/signup'), headers: _baseHeaders, body: '{}'),
    );
    return _sessionFromResponse(response);
  }

  Future<void> signUp(String email, String password) async {
    final response = await _request(
      _client.post(
        _uri('/auth/v1/signup'),
        headers: _baseHeaders,
        body: jsonEncode({'email': email.trim(), 'password': password}),
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SupabaseSyncException(_message(response));
    }
  }

  Future<SupabaseSession> refresh() async {
    final token = config.refreshToken;
    if (token == null) {
      throw const SupabaseSyncException('Sign in before syncing.');
    }
    final response = await _request(
      _client.post(
        _uri('/auth/v1/token', {'grant_type': 'refresh_token'}),
        headers: _baseHeaders,
        body: jsonEncode({'refresh_token': token}),
      ),
    );
    return _sessionFromResponse(response);
  }

  SupabaseSession _sessionFromResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SupabaseSyncException(_message(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final user = body['user'] as Map<String, dynamic>?;
    final expiresAtSeconds = body['expires_at'] as num?;
    final expiresInSeconds = body['expires_in'] as num?;
    final expiresAt = expiresAtSeconds != null
        ? DateTime.fromMillisecondsSinceEpoch(
            expiresAtSeconds.toInt() * 1000,
            isUtc: true,
          )
        : DateTime.now().toUtc().add(
            Duration(seconds: expiresInSeconds?.toInt() ?? 3600),
          );
    return SupabaseSession(
      accessToken: body['access_token'] as String,
      refreshToken: body['refresh_token'] as String,
      userId: user?['id'] as String,
      expiresAt: expiresAt,
    );
  }

  Future<CloudWorkshopState?> download(SupabaseSession session) async {
    final workspaceId = config.workspaceId;
    if (workspaceId == null) {
      throw const SupabaseSyncException('Connect this device before syncing.');
    }
    final response = await _request(
      _client.get(
        _uri('/rest/v1/workshop_states', {
          'select': 'state_json,updated_at',
          'workspace_id': 'eq.$workspaceId',
        }),
        headers: {
          ..._baseHeaders,
          'Authorization': 'Bearer ${session.accessToken}',
        },
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SupabaseSyncException(_message(response));
    }
    final rows = jsonDecode(response.body) as List<dynamic>;
    if (rows.isEmpty) return null;
    final row = rows.single as Map<String, dynamic>;
    return CloudWorkshopState(
      stateJson: jsonEncode(row['state_json']),
      updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
    );
  }

  Future<DateTime?> latestUpdatedAt(SupabaseSession session) async {
    final workspaceId = config.workspaceId;
    if (workspaceId == null) {
      throw const SupabaseSyncException('Connect this device before syncing.');
    }
    final response = await _request(
      _client.get(
        _uri('/rest/v1/workshop_states', {
          'select': 'updated_at',
          'workspace_id': 'eq.$workspaceId',
        }),
        headers: {
          ..._baseHeaders,
          'Authorization': 'Bearer ${session.accessToken}',
        },
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SupabaseSyncException(_message(response));
    }
    final rows = jsonDecode(response.body) as List<dynamic>;
    if (rows.isEmpty) return null;
    final row = rows.single as Map<String, dynamic>;
    return DateTime.parse(row['updated_at'] as String).toUtc();
  }

  Future<int> schemaVersion(SupabaseSession session) async {
    final response = await _request(
      _client.get(
        _uri('/rest/v1/inventorinator_schema', {
          'select': 'version',
          'singleton': 'eq.true',
        }),
        headers: {
          ..._baseHeaders,
          'Authorization': 'Bearer ${session.accessToken}',
        },
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const SupabaseSyncException(
        'This server needs the Inventorinator connector installed or updated.',
      );
    }
    final rows = jsonDecode(response.body) as List<dynamic>;
    if (rows.isEmpty) {
      throw const SupabaseSyncException(
        'This server needs the Inventorinator connector installed.',
      );
    }
    return (rows.single as Map<String, dynamic>)['version'] as int;
  }

  Future<int> requireCurrentSchema(SupabaseSession session) async {
    final version = await schemaVersion(session);
    if (version < requiredInventorinatorSchemaVersion) {
      throw SupabaseSyncException(
        'This server uses Inventorinator schema v$version; '
        'v$requiredInventorinatorSchemaVersion is required. '
        'Update and restart the Inventorinator server connector.',
      );
    }
    return version;
  }

  Future<DateTime> upload(
    SupabaseSession session,
    String stateJson, {
    List<Map<String, Object?>> auditEvents = const [],
  }) async {
    final workspaceId = config.workspaceId;
    if (workspaceId == null) {
      throw const SupabaseSyncException('Connect this device before syncing.');
    }
    final response = await _request(
      _client.post(
        _uri('/rest/v1/rpc/save_inventorinator_workshop_state'),
        headers: {
          ..._baseHeaders,
          'Authorization': 'Bearer ${session.accessToken}',
        },
        body: jsonEncode({
          'target_workspace': workspaceId,
          'next_state': jsonDecode(stateJson),
          'audit_events': auditEvents,
        }),
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SupabaseSyncException(_message(response));
    }
    return DateTime.parse(jsonDecode(response.body) as String).toUtc();
  }

  Future<String> createWorkspace(SupabaseSession session) async {
    final result = await _rpc(session, 'create_inventorinator_workspace', {});
    return result as String;
  }

  Future<WorkspaceRecovery> createWorkspaceWithRecovery(
    SupabaseSession session,
  ) async => WorkspaceRecovery.fromRpc(
    await _rpc(session, 'create_inventorinator_workspace_with_recovery', {}),
  );

  Future<WorkspaceRecovery> recoverWorkspace(
    SupabaseSession session, {
    required String workspaceId,
    required String recoveryKey,
    required String deviceName,
  }) async => WorkspaceRecovery.fromRpc(
    await _rpc(session, 'recover_inventorinator_workspace', {
      'target_workspace': workspaceId,
      'recovery_key': recoveryKey,
      'target_device_name': deviceName,
    }),
  );

  Future<String> rotateRecoveryKey(SupabaseSession session) async {
    final result = await _rpc(session, 'rotate_inventorinator_recovery_key', {
      'target_workspace': config.workspaceId,
    });
    return result as String;
  }

  Future<String?> ensureRecoveryKey(SupabaseSession session) async {
    final result = await _rpc(session, 'ensure_inventorinator_recovery_key', {
      'target_workspace': config.workspaceId,
    });
    return result as String?;
  }

  Future<String> createPairingCode(SupabaseSession session) async {
    final workspaceId = config.workspaceId;
    if (workspaceId == null) {
      throw const SupabaseSyncException('Connect this device first.');
    }
    final result = await _rpc(session, 'create_inventorinator_pairing_code', {
      'target_workspace': workspaceId,
    });
    return result as String;
  }

  Future<String> redeemPairingCode(SupabaseSession session, String code) async {
    final result = await _rpc(session, 'redeem_inventorinator_pairing_code', {
      'pairing_code': code.trim().toUpperCase(),
    });
    return result as String;
  }

  Future<void> registerDevice(SupabaseSession session, String name) async {
    await _rpc(session, 'register_inventorinator_device', {
      'target_workspace': config.workspaceId,
      'target_name': name,
    });
  }

  Future<String> currentRole(SupabaseSession session) async {
    final result = await _rpc(session, 'get_inventorinator_role', {
      'target_workspace': config.workspaceId,
    });
    return result as String;
  }

  Future<List<WorkspaceDevice>> listDevices(SupabaseSession session) async {
    final result = await _rpc(session, 'list_inventorinator_devices', {
      'target_workspace': config.workspaceId,
    });
    return (result as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(
          (row) => WorkspaceDevice(
            userId: row['user_id'] as String,
            name: row['device_name'] as String,
            role: row['role'] as String,
            joinedAt: DateTime.parse(row['joined_at'] as String),
            lastSeenAt: DateTime.parse(row['last_seen_at'] as String),
          ),
        )
        .toList();
  }

  Future<void> setDeviceRole(
    SupabaseSession session,
    String userId,
    String role,
  ) => _rpc(session, 'set_inventorinator_device_role', {
    'target_workspace': config.workspaceId,
    'target_user': userId,
    'target_role': role,
  });

  Future<void> removeDevice(
    SupabaseSession session,
    String userId, {
    required bool lockOut,
  }) => _rpc(session, 'remove_inventorinator_device', {
    'target_workspace': config.workspaceId,
    'target_user': userId,
    'lock_out': lockOut,
  });

  Future<Object?> _rpc(
    SupabaseSession session,
    String function,
    Map<String, Object?> parameters,
  ) async {
    final response = await _request(
      _client.post(
        _uri('/rest/v1/rpc/$function'),
        headers: {
          ..._baseHeaders,
          'Authorization': 'Bearer ${session.accessToken}',
        },
        body: jsonEncode(parameters),
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SupabaseSyncException(_message(response));
    }
    final body = response.body.trim();
    return body.isEmpty ? null : jsonDecode(body);
  }

  String _message(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['msg'] as String? ??
          body['message'] as String? ??
          body['error_description'] as String? ??
          'Supabase request failed (${response.statusCode}).';
    } catch (_) {
      return 'Supabase request failed (${response.statusCode}).';
    }
  }
}
