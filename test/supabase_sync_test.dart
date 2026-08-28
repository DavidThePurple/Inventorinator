import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventorinator/supabase_sync.dart';

void main() {
  const config = SupabaseConfig(
    url: 'https://inventory.example',
    publishableKey: 'sb_publishable_test',
  );

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
    await service.removeDevice(session, 'device-id', lockOut: true);
  });
}
