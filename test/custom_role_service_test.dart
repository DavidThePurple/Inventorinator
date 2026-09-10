import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventorinator/supabase_sync.dart';
void main() {
  const session = SupabaseSession(accessToken:'access',refreshToken:'refresh',userId:'user');
  const config = SupabaseConfig(url:'https://inventory.example',publishableKey:'public',workspaceId:'workspace');
  test('loads server effective permissions without inheriting Builder access', () async {
    final service = SupabaseSyncService(config,client:MockClient((r) async {
      if(r.url.path.endsWith('inventorinator_schema')) return http.Response('[{"version":25}]',200);
      if(r.url.path.endsWith('get_inventorinator_role')) return http.Response('"builder"',200);
      expect(r.url.path.endsWith('get_inventorinator_effective_role'),true);
      return http.Response('{"role":"builder","templateId":"reader","name":"Read only","permissions":["inventory.read"]}',200);
    }));
    final role = WorkspaceRole.fromServer(await service.currentRole(session));
    expect(role.name,'Read only'); expect(role.canOperateBuilds,false); expect(role.canEditInventory,false);
  });
  test('custom assignment uses dedicated RPC and workspace scope', () async {
    final service = SupabaseSyncService(config,client:MockClient((r) async {
      if(r.url.path.endsWith('inventorinator_schema')) return http.Response('[{"version":25}]',200);
      expect(r.url.path.endsWith('assign_inventorinator_custom_role'),true);
      expect(jsonDecode(r.body),{'target_workspace':'workspace','target_user':'other','target_template':'reader'});
      return http.Response('',204);
    }));
    await service.setDeviceRole(session,'other','template:reader');
  });
}
