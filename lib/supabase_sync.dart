import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'workshop_delta.dart';
import 'workspace_role_template.dart';
import 'digikey_credentials.dart';
import 'mouser_credentials.dart';
import 'scratch_pad.dart';

// v22-v24 add optional services without changing the v21 inventory protocol.
const minimumInventorySchemaVersion = 21;
const latestInventorinatorSchemaVersion = 26;

String? normalizeWorkspaceRole(String? role) => role?.trim().toLowerCase();

bool canManageWorkspaceDevices(String? role) {
  if (role?.startsWith('custom:') == true) {
    return WorkspaceRole.fromServer(role).permissions
            ?.contains('devices.manage') ??
        false;
  }
  final normalized = normalizeWorkspaceRole(role);
  return normalized == 'owner' ||
      normalized == 'admin' ||
      normalized == 'manager';
}

bool canRemoveWorkspaceDevices(String? role) =>
    normalizeWorkspaceRole(role) == 'owner' || normalizeWorkspaceRole(role) == 'admin';

String visibleSyncErrorForRole(Object error, String? role) {
  if (error is SupabaseSyncException && error.isInvalidRefreshToken) {
    return canManageWorkspaceDevices(role)
        ? 'This device’s Remote Sync session expired. Pair it again to manage access.'
        : '';
  }
  return error.toString();
}

class WorkspaceRole {
  const WorkspaceRole._(this.name, [this.permissions]);
  static const admin = WorkspaceRole._('admin');
  static const manager = WorkspaceRole._('manager');
  static const editor = WorkspaceRole._('editor');
  static const builder = WorkspaceRole._('builder');
  final String name;
  final Set<String>? permissions;
  static WorkspaceRole fromServer(String? value) {
    if (value?.startsWith('custom:') == true) {
      try {
        final data = jsonDecode(value!.substring(7)) as Map<String, dynamic>;
        return WorkspaceRole._(
          data['name'] as String,
          (data['permissions'] as List).cast<String>().toSet(),
        );
      } catch (_) {
        return const WorkspaceRole._('Unavailable role', {});
      }
    }
    return switch (normalizeWorkspaceRole(value)) {
      'owner' || 'admin' => admin,
      'manager' => manager,
      'editor' => editor,
      _ => builder,
    };
  }

  bool allows(String id, bool builtin) => permissions?.contains(id) ?? builtin;
  bool get canDeleteDatabase => allows('database.delete', this == admin);
  bool get canHardDeleteItems => allows('inventory.delete', this == admin);
  bool get canCreateInventory =>
      allows('inventory.create', this == admin || this == manager);
  bool get canEditInventory => allows('inventory.edit', this != builder);
  bool get canArchiveInventory =>
      allows('inventory.archive', this == admin || this == manager);
  bool get canManageCatalog =>
      allows('catalog.manage', this == admin || this == manager);
  bool get canCreateBuilds => allows('builds.create', this != builder);
  bool get canShareBuilds => allows('builds.share', this != builder);
  bool get canOperateBuilds => allows('builds.operate', true);
  @override
  bool operator ==(Object other) =>
      other is WorkspaceRole &&
      other.name == name &&
      (other.permissions == null && permissions == null ||
          other.permissions != null &&
              permissions != null &&
              other.permissions!.length == permissions!.length &&
              other.permissions!.containsAll(permissions!));
  @override
  int get hashCode => Object.hash(
    name,
    permissions == null ? 0 : Object.hashAllUnordered(permissions!),
  );
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
    this.remotePurgeAfterDays,
    this.autoSyncEnabled = true,
    this.syncIntervalSeconds = 60,
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
  final int? remotePurgeAfterDays;
  final bool autoSyncEnabled;
  final int syncIntervalSeconds;

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
    int? remotePurgeAfterDays,
    bool? autoSyncEnabled,
    int? syncIntervalSeconds,
    bool clearLastSyncedStateJson = false,
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
    lastSyncedStateJson: clearLastSyncedStateJson
        ? null
        : lastSyncedStateJson ?? this.lastSyncedStateJson,
    remotePurgeAfterDays: remotePurgeAfterDays ?? this.remotePurgeAfterDays,
    autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
    syncIntervalSeconds: syncIntervalSeconds ?? this.syncIntervalSeconds,
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
    'remotePurgeAfterDays': remotePurgeAfterDays,
    'autoSyncEnabled': autoSyncEnabled,
    'syncIntervalSeconds': syncIntervalSeconds,
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
    remotePurgeAfterDays: (json['remotePurgeAfterDays'] as num?)?.toInt(),
    autoSyncEnabled: json['autoSyncEnabled'] as bool? ?? true,
    syncIntervalSeconds: (json['syncIntervalSeconds'] as num?)?.toInt() ?? 60,
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

class WorkshopChangeBatch {
  const WorkshopChangeBatch({required this.changes, required this.revision});

  final List<WorkshopEntityChange> changes;
  final int revision;
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

class SupabaseFeatureUnavailable extends SupabaseSyncException {
  const SupabaseFeatureUnavailable(super.message);
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

  bool get isWorkspaceAccessDenied =>
      message.toLowerCase().contains('workspace access denied') ||
      message.toLowerCase().contains('locked out of the workspace');

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

  Future<int> requireInventorySchema(SupabaseSession session) async {
    final version = await schemaVersion(session);
    if (version < minimumInventorySchemaVersion) {
      throw SupabaseSyncException(
        'This server uses Inventorinator schema v$version; '
        'v$minimumInventorySchemaVersion is required for inventory sync. '
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

  Future<WorkshopChangeBatch> downloadChanges(
    SupabaseSession session, {
    required int afterRevision,
  }) async {
    final workspaceId = config.workspaceId;
    if (workspaceId == null) {
      throw const SupabaseSyncException('Connect this device before syncing.');
    }
    final response = await _request(
      _client.get(
        _uri('/rest/v1/inventorinator_entities', {
          'select': 'entity_type,entity_id,payload,deleted,revision',
          'workspace_id': 'eq.$workspaceId',
          'revision': 'gt.$afterRevision',
          'order': 'revision.asc',
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
    final decodedBody = await Isolate.run(() => jsonDecode(response.body));
    final rows = (decodedBody as List<dynamic>).cast<Map<String, dynamic>>();
    var revision = afterRevision;
    final changes = <WorkshopEntityChange>[];
    for (final row in rows) {
      final rowRevision = (row['revision'] as num).toInt();
      if (rowRevision > revision) revision = rowRevision;
      changes.add(
        WorkshopEntityChange(
          entityType: row['entity_type'] as String,
          entityId: row['entity_id'] as String,
          fields: Map<String, dynamic>.from(
            row['payload'] as Map<String, dynamic>? ?? const {},
          ),
          deleted: row['deleted'] as bool? ?? false,
          revision: rowRevision,
        ),
      );
    }
    return WorkshopChangeBatch(changes: changes, revision: revision);
  }

  Future<int> uploadChanges(
    SupabaseSession session,
    Iterable<WorkshopEntityChange> changes, {
    required String deviceId,
    List<Map<String, Object?>> auditEvents = const [],
  }) async {
    final workspaceId = config.workspaceId;
    if (workspaceId == null) {
      throw const SupabaseSyncException('Connect this device before syncing.');
    }
    final requestPayload = {
      'target_workspace': workspaceId,
      'source_device': deviceId,
      'entity_changes': changes.map((change) => change.toJson()).toList(),
      'audit_events': auditEvents,
    };
    final requestBody = await Isolate.run(() => jsonEncode(requestPayload));
    final response = await _request(
      _client.post(
        _uri('/rest/v1/rpc/apply_inventorinator_entity_changes'),
        headers: {
          ..._baseHeaders,
          'Authorization': 'Bearer ${session.accessToken}',
        },
        body: requestBody,
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SupabaseSyncException(_message(response));
    }
    return (jsonDecode(response.body) as num).toInt();
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

  Future<String> redeemPairingCode(
    SupabaseSession session,
    String code, {
    String? deviceId,
  }) async {
    final result = await _rpc(session, 'redeem_inventorinator_pairing_code', {
      'pairing_code': code.trim().toUpperCase(),
      'device_identifier': deviceId,
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
    final role = result is String ? normalizeWorkspaceRole(result) : null;
    if (role == null || role.isEmpty) {
      // A removed member can arrive as a JSON null from older connector
      // versions instead of the newer explicit access-denied exception.
      throw const SupabaseSyncException('Workspace access denied');
    }
    // Only Builder memberships can carry custom definitions. Old servers keep
    // their built-in behavior; a failed modern lookup never widens access.
    if (role == 'builder' && await schemaVersion(session) >= 25) {
      final effective = await _rpc(
        session,
        'get_inventorinator_effective_role',
        {'target_workspace': config.workspaceId},
      );
      if (effective is Map && effective['templateId'] != null) {
        return 'custom:${jsonEncode(effective)}';
      }
    }
    return role;
  }

  Future<List<WorkspaceRoleTemplate>> listRoleTemplates(
    SupabaseSession session,
  ) async {
    final result = await _rpc(session, 'list_inventorinator_role_templates', {
      'target_workspace': config.workspaceId,
    });
    return (result as List)
        .map(
          (row) => WorkspaceRoleTemplate.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  Future<String> saveRoleTemplate(
    SupabaseSession session,
    WorkspaceRoleTemplate template,
  ) async {
    final error = template.validationError;
    if (error != null) throw SupabaseSyncException(error);
    final result = await _rpc(session, 'save_inventorinator_role_template', {
      'target_workspace': config.workspaceId,
      'target_id': template.id,
      'target_name': template.name,
      'target_description': template.description,
      'target_permissions': template.permissionIds,
    });
    return result as String;
  }

  Future<void> deleteRoleTemplate(SupabaseSession session, String id) => _rpc(
    session,
    'delete_inventorinator_role_template',
    {'target_workspace': config.workspaceId, 'target_id': id},
  );

  Future<DigiKeyCredentials> getDigiKeyCredentials(
    SupabaseSession session,
  ) async {
    final result = await _rpc(
      session,
      'get_inventorinator_digikey_credentials',
      {'target_workspace': config.workspaceId},
    );
    return result == null
        ? const DigiKeyCredentials()
        : DigiKeyCredentials.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<void> setDigiKeyCredentials(
    SupabaseSession session,
    DigiKeyCredentials credentials,
  ) => _rpc(session, 'set_inventorinator_digikey_credentials', {
    'target_workspace': config.workspaceId,
    'target_client_id': credentials.configured ? credentials.clientId : null,
    'target_client_secret': credentials.configured
        ? credentials.clientSecret
        : null,
    'target_sandbox': credentials.sandbox,
  });

  Future<MouserCredentials> getMouserCredentials(
    SupabaseSession session,
  ) async {
    final result = await _rpc(
      session,
      'get_inventorinator_mouser_credentials',
      {'target_workspace': config.workspaceId},
    );
    return result == null
        ? const MouserCredentials()
        : MouserCredentials.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<void> setMouserCredentials(
    SupabaseSession session,
    MouserCredentials credentials,
  ) => _rpc(session, 'set_inventorinator_mouser_credentials', {
    'target_workspace': config.workspaceId,

    'target_api_key': credentials.configured ? credentials.apiKey : null,
  });

  Future<int> remotePurgeAfterDays(SupabaseSession session) async {
    final result = await _rpc(session, 'get_inventorinator_remote_purge_days', {
      'target_workspace': config.workspaceId,
    });
    final days = result is num ? result.toInt() : int.tryParse('$result');
    if (days == null || days < 1 || days > 365) {
      throw const SupabaseSyncException(
        'The shared inventory returned an invalid offline purge policy.',
      );
    }
    return days;
  }

  Future<void> setRemotePurgeAfterDays(SupabaseSession session, int days) =>
      _rpc(session, 'set_inventorinator_remote_purge_days', {
        'target_workspace': config.workspaceId,
        'target_days': days,
      });

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
  ) => role.startsWith('template:')
      ? _rpc(session, 'assign_inventorinator_custom_role', {
          'target_workspace': config.workspaceId,
          'target_user': userId,
          'target_template': role.substring(9),
        })
      : _rpc(session, 'set_inventorinator_device_role', {
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

  Future<void> backupScratchPadNotes(SupabaseSession session, Iterable<ScratchPadNote> notes) => _rpc(session, 'backup_inventorinator_device_notes', {'target_workspace': config.workspaceId, 'target_notes': notes.map((note) => note.toJson()).toList()});
  Future<List<ScratchPadNote>> listRemovedDeviceNotes(SupabaseSession session) async {
    final result = await _rpc(session, 'list_inventorinator_removed_device_notes', {'target_workspace': config.workspaceId});
    return result is List ? result.whereType<Map>().map((row) => ScratchPadNote.fromRemoteJson(Map<String, dynamic>.from(row))).toList() : const [];
  }

  Future<Object?> _rpc(
    SupabaseSession session,
    String function,
    Map<String, Object?> parameters,
  ) async {
    final requirement = switch (function) {
      'assign_inventorinator_custom_role' => (25, 'Custom role assignment'),
      'list_inventorinator_role_templates' ||
      'save_inventorinator_role_template' ||
      'delete_inventorinator_role_template' => (22, 'Remote role templates'),
      'get_inventorinator_digikey_credentials' ||
      'set_inventorinator_digikey_credentials' => (
        23,
        'DigiKey credential sync',
      ),
      'get_inventorinator_mouser_credentials' ||
      'set_inventorinator_mouser_credentials' => (24, 'Mouser credential sync'),
      'backup_inventorinator_device_notes' || 'list_inventorinator_removed_device_notes' => (26, 'Scratch Pad backup'),
      _ => null,
    };
    if (requirement != null) {
      final version = await schemaVersion(session);
      if (version < requirement.$1) {
        throw SupabaseFeatureUnavailable(
          '${requirement.$2} needs server v${requirement.$1} '
          '(installed: v$version). Local changes are retained; update the server and retry.',
        );
      }
    }
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
