import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventorinator/supabase_sync.dart';
import 'package:inventorinator/workshop_delta.dart';

void main() {
  const config = SupabaseConfig(
    url: 'https://inventory.example',
    publishableKey: 'sb_publishable_test',
  );

  test('sync configuration only accepts HTTP(S) server addresses', () {
    expect(config.isConfigured, isTrue);
    expect(
      config.copyWith(url: 'http://192.168.1.230:8010').isConfigured,
      isTrue,
    );
    expect(
      config.copyWith(url: 'ftp://inventory.example').isConfigured,
      isFalse,
    );
    expect(config.copyWith(url: 'not a server').isConfigured, isFalse);
    expect(config.copyWith(publishableKey: '').isConfigured, isFalse);
  });

  test('sync configuration preserves role, session, and merge checkpoint', () {
    final expires = DateTime.now().toUtc().add(const Duration(hours: 2));
    final configured = config.copyWith(
      userId: 'user-id',
      workspaceId: 'workspace-id',
      workspaceRole: 'manager',
      accessToken: 'access-token',
      accessTokenExpiresAt: expires,
      refreshToken: 'refresh-token',
      lastSyncedAt: DateTime.utc(2026, 8, 28),
      lastSyncedStateJson: '{"inventory":[]}',
    );

    final restored = SupabaseConfig.fromJson(configured.toJson());
    expect(restored.workspaceRole, 'manager');
    expect(restored.workspaceId, 'workspace-id');
    expect(restored.accessToken, 'access-token');
    expect(restored.accessTokenExpiresAt, expires);
    expect(restored.cachedSession?.accessToken, 'access-token');
    expect(restored.lastSyncedAt, DateTime.utc(2026, 8, 28));
    expect(restored.lastSyncedStateJson, '{"inventory":[]}');
  });

  test('device management hierarchy and session errors are role-aware', () {
    expect(canManageWorkspaceDevices('owner'), isTrue);
    expect(canManageWorkspaceDevices('admin'), isTrue);
    expect(canManageWorkspaceDevices('manager'), isTrue);
    expect(canManageWorkspaceDevices('editor'), isFalse);
    expect(canManageWorkspaceDevices('builder'), isFalse);
    expect(canRemoveWorkspaceDevices('owner'), isTrue);
    expect(canRemoveWorkspaceDevices('admin'), isFalse);

    const expired = SupabaseSyncException(
      'Invalid Refresh Token: Already Used',
    );
    expect(visibleSyncErrorForRole(expired, 'editor'), isEmpty);
    expect(visibleSyncErrorForRole(expired, 'builder'), isEmpty);
    expect(
      visibleSyncErrorForRole(expired, 'admin'),
      contains('session expired'),
    );
    expect(visibleSyncErrorForRole(expired, 'admin'), isNot(contains('Token')));
  });

  test(
    'server and publishable key are verified before authentication',
    () async {
      final service = SupabaseSyncService(
        config,
        client: MockClient((request) async {
          expect(request.url.path, '/auth/v1/health');
          expect(request.headers['apikey'], 'sb_publishable_test');
          return http.Response('{"version":"test"}', 200);
        }),
      );

      await service.verifyServer();
    },
  );

  test(
    'sign in returns a reusable session without exposing the password',
    () async {
      final service = SupabaseSyncService(
        config,
        client: MockClient((request) async {
          expect(request.url.path, '/auth/v1/token');
          expect(request.url.queryParameters['grant_type'], 'password');
          expect(request.headers['apikey'], 'sb_publishable_test');
          expect(jsonDecode(request.body), {
            'email': 'maker@example.com',
            'password': 'workshop-password',
          });
          return http.Response(
            jsonEncode({
              'access_token': 'access',
              'refresh_token': 'refresh',
              'user': {'id': 'user-id'},
            }),
            200,
          );
        }),
      );

      final session = await service.signIn(
        'maker@example.com',
        'workshop-password',
      );
      expect(session.userId, 'user-id');
      expect(session.refreshToken, 'refresh');
      expect(session.expiresAt, isNotNull);
    },
  );

  test('download returns the authenticated user workshop state', () async {
    final service = SupabaseSyncService(
      config.copyWith(workspaceId: 'workspace-id'),
      client: MockClient((request) async {
        expect(request.url.path, '/rest/v1/workshop_states');
        expect(request.url.queryParameters['workspace_id'], 'eq.workspace-id');
        expect(request.headers['authorization'], 'Bearer access');
        return http.Response(
          jsonEncode([
            {
              'state_json': {'inventory': []},
              'updated_at': '2026-08-25T12:00:00Z',
            },
          ]),
          200,
        );
      }),
    );

    final cloud = await service.download(
      const SupabaseSession(
        accessToken: 'access',
        refreshToken: 'refresh',
        userId: 'user-id',
      ),
    );
    expect(jsonDecode(cloud!.stateJson), {'inventory': []});
  });

  test('revision check downloads only the workshop timestamp', () async {
    final service = SupabaseSyncService(
      config.copyWith(workspaceId: 'workspace-id'),
      client: MockClient((request) async {
        expect(request.url.path, '/rest/v1/workshop_states');
        expect(request.url.queryParameters['select'], 'updated_at');
        expect(request.url.queryParameters['workspace_id'], 'eq.workspace-id');
        expect(request.headers['authorization'], 'Bearer access');
        return http.Response(
          jsonEncode([
            {'updated_at': '2026-08-31T12:34:56Z'},
          ]),
          200,
        );
      }),
    );

    final updatedAt = await service.latestUpdatedAt(
      const SupabaseSession(
        accessToken: 'access',
        refreshToken: 'refresh',
        userId: 'user-id',
      ),
    );
    expect(updatedAt, DateTime.utc(2026, 8, 31, 12, 34, 56));
  });

  test('uploads use the role-enforcing audited RPC', () async {
    final service = SupabaseSyncService(
      config.copyWith(workspaceId: 'workspace-id'),
      client: MockClient((request) async {
        expect(
          request.url.path,
          '/rest/v1/rpc/save_inventorinator_workshop_state',
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['target_workspace'], 'workspace-id');
        expect(body['next_state'], {'inventory': []});
        expect(body['audit_events'], [
          {'action': 'edit', 'entityType': 'inventory', 'entityId': 'INV-1'},
        ]);
        return http.Response(jsonEncode('2026-08-27T12:00:00Z'), 200);
      }),
    );
    final updated = await service.upload(
      const SupabaseSession(
        accessToken: 'access',
        refreshToken: 'refresh',
        userId: 'editor-id',
      ),
      '{"inventory":[]}',
      auditEvents: const [
        {'action': 'edit', 'entityType': 'inventory', 'entityId': 'INV-1'},
      ],
    );
    expect(updated, DateTime.utc(2026, 8, 27, 12));
  });

  test(
    'incremental download requests only rows after the local cursor',
    () async {
      final service = SupabaseSyncService(
        config.copyWith(workspaceId: 'workspace-id'),
        client: MockClient((request) async {
          expect(request.url.path, '/rest/v1/inventorinator_entities');
          expect(request.url.queryParameters['revision'], 'gt.41');
          return http.Response(
            jsonEncode([
              {
                'entity_type': 'inventory',
                'entity_id': 'INV-1',
                'payload': {'id': 'INV-1', 'quantity': 7},
                'deleted': false,
                'revision': 42,
              },
            ]),
            200,
          );
        }),
      );
      final batch = await service.downloadChanges(
        const SupabaseSession(
          accessToken: 'access',
          refreshToken: 'refresh',
          userId: 'user-id',
        ),
        afterRevision: 41,
      );
      expect(batch.revision, 42);
      expect(batch.changes.single.entityId, 'INV-1');
    },
  );

  test('incremental upload sends field patches and tombstones', () async {
    final service = SupabaseSyncService(
      config.copyWith(workspaceId: 'workspace-id'),
      client: MockClient((request) async {
        expect(
          request.url.path,
          '/rest/v1/rpc/apply_inventorinator_entity_changes',
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['source_device'], 'PHONE');
        expect(body['entity_changes'], [
          {
            'entityType': 'inventory',
            'entityId': 'INV-1',
            'fields': {'quantity': 7},
            'deleted': false,
          },
          {
            'entityType': 'inventory',
            'entityId': 'INV-2',
            'fields': <String, dynamic>{},
            'deleted': true,
          },
        ]);
        return http.Response('43', 200);
      }),
    );
    final revision = await service.uploadChanges(
      const SupabaseSession(
        accessToken: 'access',
        refreshToken: 'refresh',
        userId: 'user-id',
      ),
      const [
        WorkshopEntityChange(
          entityType: 'inventory',
          entityId: 'INV-1',
          fields: {'quantity': 7},
        ),
        WorkshopEntityChange(
          entityType: 'inventory',
          entityId: 'INV-2',
          fields: {},
          deleted: true,
        ),
      ],
      deviceId: 'PHONE',
    );
    expect(revision, 43);
  });

  test(
    'anonymous connection creates a session without personal data',
    () async {
      final service = SupabaseSyncService(
        config,
        client: MockClient((request) async {
          expect(request.url.path, '/auth/v1/signup');
          expect(jsonDecode(request.body), isEmpty);
          return http.Response(
            jsonEncode({
              'access_token': 'access',
              'refresh_token': 'refresh',
              'user': {'id': 'anonymous-user'},
            }),
            200,
          );
        }),
      );

      final session = await service.signInAnonymously();
      expect(session.userId, 'anonymous-user');
    },
  );

  test('owner recovery creates and transfers with a rotated key', () async {
    var calls = 0;
    final service = SupabaseSyncService(
      config,
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer access');
        calls++;
        if (request.url.path.endsWith(
          '/create_inventorinator_workspace_with_recovery',
        )) {
          expect(jsonDecode(request.body), isEmpty);
          return http.Response(
            jsonEncode({
              'workspace_id': 'workspace-id',
              'recovery_key': 'FIRST-KEY',
            }),
            200,
          );
        }
        expect(request.url.path, endsWith('/recover_inventorinator_workspace'));
        expect(jsonDecode(request.body), {
          'target_workspace': 'workspace-id',
          'recovery_key': 'FIRST-KEY',
          'target_device_name': 'Replacement laptop',
        });
        return http.Response(
          jsonEncode({
            'workspace_id': 'workspace-id',
            'recovery_key': 'ROTATED-KEY',
          }),
          200,
        );
      }),
    );
    const session = SupabaseSession(
      accessToken: 'access',
      refreshToken: 'refresh',
      userId: 'user-id',
    );

    final created = await service.createWorkspaceWithRecovery(session);
    expect(created.workspaceId, 'workspace-id');
    expect(created.key, 'FIRST-KEY');
    final recovered = await service.recoverWorkspace(
      session,
      workspaceId: created.workspaceId,
      recoveryKey: created.key,
      deviceName: 'Replacement laptop',
    );
    expect(recovered.key, 'ROTATED-KEY');
    expect(calls, 2);
  });

  test('owner can provision a missing recovery credential once', () async {
    final service = SupabaseSyncService(
      config.copyWith(workspaceId: 'workspace-id'),
      client: MockClient((request) async {
        expect(
          request.url.path,
          endsWith('/ensure_inventorinator_recovery_key'),
        );
        expect(jsonDecode(request.body), {'target_workspace': 'workspace-id'});
        return http.Response(jsonEncode('PROVISIONED-KEY'), 200);
      }),
    );

    expect(
      await service.ensureRecoveryKey(
        const SupabaseSession(
          accessToken: 'access',
          refreshToken: 'refresh',
          userId: 'owner-id',
        ),
      ),
      'PROVISIONED-KEY',
    );
  });

  test('schema version detects an installed connector', () async {
    final service = SupabaseSyncService(
      config,
      client: MockClient((request) async {
        expect(request.url.path, '/rest/v1/inventorinator_schema');
        return http.Response(
          jsonEncode([
            {'version': 1},
          ]),
          200,
        );
      }),
    );

    final version = await service.schemaVersion(
      const SupabaseSession(
        accessToken: 'access',
        refreshToken: 'refresh',
        userId: 'user-id',
      ),
    );
    expect(version, 1);
  });

  test('startup sync rejects an outdated server schema', () async {
    final service = SupabaseSyncService(
      config,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode([
            {'version': requiredInventorinatorSchemaVersion - 1},
          ]),
          200,
        ),
      ),
    );

    await expectLater(
      service.requireCurrentSchema(
        const SupabaseSession(
          accessToken: 'access',
          refreshToken: 'refresh',
          userId: 'user-id',
        ),
      ),
      throwsA(
        isA<SupabaseSyncException>().having(
          (error) => error.message,
          'message',
          contains('v$requiredInventorinatorSchemaVersion is required'),
        ),
      ),
    );
  });

  test('workspace device administration uses authenticated RPCs', () async {
    final service = SupabaseSyncService(
      config.copyWith(workspaceId: 'workspace-id'),
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer access');
        if (request.url.path.endsWith('/get_inventorinator_role')) {
          return http.Response(jsonEncode('owner'), 200);
        }
        if (request.url.path.endsWith('/list_inventorinator_devices')) {
          return http.Response(
            jsonEncode([
              {
                'user_id': 'device-id',
                'device_name': 'Workshop tablet',
                'role': 'member',
                'joined_at': '2026-08-25T12:00:00Z',
                'last_seen_at': '2026-08-25T12:05:00Z',
              },
            ]),
            200,
          );
        }
        if (request.url.path.endsWith('/set_inventorinator_device_role')) {
          expect(jsonDecode(request.body), {
            'target_workspace': 'workspace-id',
            'target_user': 'device-id',
            'target_role': 'editor',
          });
        }
        return http.Response('', 204);
      }),
    );
    const session = SupabaseSession(
      accessToken: 'access',
      refreshToken: 'refresh',
      userId: 'owner-id',
    );
    await service.registerDevice(session, 'Linux desktop');
    expect(await service.currentRole(session), 'owner');
    final devices = await service.listDevices(session);
    expect(devices.single.name, 'Workshop tablet');
    await service.setDeviceRole(session, 'device-id', 'editor');
    await service.removeDevice(session, 'device-id', lockOut: true);
  });

  test('invalid rotated refresh tokens are treated as fatal sessions', () {
    expect(
      const SupabaseSyncException('Invalid Refresh Token: Already Used')
          .isInvalidRefreshToken,
      isTrue,
    );
    expect(
      const SupabaseSyncException('Network connection failed')
          .isInvalidRefreshToken,
      isFalse,
    );
  });
}
