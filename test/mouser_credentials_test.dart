import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventorinator/supabase_sync.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/mouser_credentials.dart';

void main() {
  test(
    'remote credentials use scoped owner RPCs and clear explicitly',
    () async {
      const session = SupabaseSession(
        accessToken: 'access',
        refreshToken: 'refresh',
        userId: 'owner',
      );
      var writes = 0;
      final service = SupabaseSyncService(
        const SupabaseConfig(
          url: 'https://inventory.example',
          publishableKey: 'public',
          workspaceId: 'workspace',
        ),
        client: MockClient((request) async {
          if (request.url.path.endsWith('inventorinator_schema')) {
            return http.Response('[{"version":24}]', 200);
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['target_workspace'], 'workspace');
          if (request.url.path.endsWith(
            'get_inventorinator_mouser_credentials',
          )) {
            return http.Response(jsonEncode({'api_key': 'secret'}), 200);
          }
          expect(
            request.url.path,
            endsWith('set_inventorinator_mouser_credentials'),
          );
          expect(body['target_api_key'], writes++ == 0 ? 'secret' : null);
          return http.Response('', 204);
        }),
      );
      final credentials = await service.getMouserCredentials(session);
      expect(credentials.apiKey, 'secret');
      await service.setMouserCredentials(session, credentials);
      await service.setMouserCredentials(session, const MouserCredentials());
      expect(writes, 2);
    },
  );
  test(
    'credentials survive reopen, isolate workspaces, and stay out of exports',
    () async {
      final dir = Directory.systemTemp.createTempSync('dk-persistence-');
      final path = '${dir.path}/db.sqlite3';
      var db = await LocalDatabase.open(overridePath: path);
      const value = MouserCredentials(apiKey: 'fixture-secret-never-export');
      MouserCredentialStore(db, 'workspace-a').save(value, pending: true);
      db.close();
      db = await LocalDatabase.open(overridePath: path);
      try {
        final store = MouserCredentialStore(db, 'workspace-a');
        expect(store.read()!.credentials.apiKey, value.apiKey);
        expect(store.read()!.pending, isTrue);
        expect(MouserCredentialStore(db, 'workspace-b').read(), isNull);
        final exported = await db.exportPortableDatabase();
        expect(latin1.decode(exported), isNot(contains(value.apiKey)));
        final old = store.read()!;
        store.save(const MouserCredentials(), pending: true);
        expect(store.acknowledge(old.revision), isFalse);
        expect(store.restore(value, old.revision), isFalse);
        expect(store.read()!.credentials.configured, isFalse);
        expect(store.acknowledge(store.read()!.revision), isTrue);
        expect(store.read()!.pending, isFalse);
      } finally {
        db.close();
        dir.deleteSync(recursive: true);
      }
    },
  );
}
