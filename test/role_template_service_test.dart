import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventorinator/supabase_sync.dart';
import 'package:inventorinator/workspace_role_template.dart';

void main() {
  const session = SupabaseSession(
    accessToken: 'access',
    refreshToken: 'refresh',
    userId: 'user',
  );
  const config = SupabaseConfig(
    url: 'https://inventory.example',
    publishableKey: 'public',
    workspaceId: 'workspace',
  );
  test(
    'role template RPCs preserve workspace, identity and permission IDs',
    () async {
      final paths = <String>[];
      final service = SupabaseSyncService(
        config,
        client: MockClient((request) async {
          if (request.url.path.endsWith('inventorinator_schema')) {
            return http.Response('[{"version":24}]', 200);
          }
          paths.add(request.url.path);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['target_workspace'], 'workspace');
          if (request.url.path.endsWith('list_inventorinator_role_templates')) {
            return http.Response(
              jsonEncode([
                {
                  'id': 'template',
                  'name': 'Reader',
                  'description': '',
                  'permissions': ['inventory.read'],
                },
              ]),
              200,
            );
          }
          expect(body['target_id'], 'template');
          if (request.url.path.endsWith('save_inventorinator_role_template')) {
            expect(body['target_name'], 'Reader');
            expect(body['target_permissions'], ['inventory.read']);
            return http.Response('"template"', 200);
          }
          return http.Response('', 204);
        }),
      );
      final templates = await service.listRoleTemplates(session);
      expect(
        await service.saveRoleTemplate(session, templates.single),
        'template',
      );
      await service.deleteRoleTemplate(session, templates.single.id!);
      expect(paths.length, 3);
    },
  );
  test(
    'server owner denial is surfaced instead of accepting a local draft',
    () async {
      final service = SupabaseSyncService(
        config,
        client: MockClient(
          (request) async => request.url.path.endsWith('inventorinator_schema')
              ? http.Response('[{"version":24}]', 200)
              : http.Response(
                  '{"message":"Only the owner can manage role templates"}',
                  403,
                ),
        ),
      );
      await expectLater(
        service.saveRoleTemplate(
          session,
          WorkspaceRoleTemplate(
            name: 'Reader',
            permissions: RoleTemplatePreset.viewer.permissions,
          ),
        ),
        throwsA(isA<SupabaseSyncException>()),
      );
    },
  );
}
