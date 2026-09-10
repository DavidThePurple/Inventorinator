import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/local_role_drafts.dart';
import 'package:inventorinator/workspace_role_template.dart';

void main() {
  test(
    'offline drafts survive restart, are scoped and never become synced roles',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'role-drafts-test-',
      );
      final path = '${directory.path}/inventory.sqlite3';
      var database = await LocalDatabase.open(overridePath: path);
      var store = LocalRoleDrafts(database, scope: 'workspace-a');
      store.save(
        WorkspaceRoleTemplate(
          name: 'Reader',
          permissions: RoleTemplatePreset.viewer.permissions,
        ),
      );
      expect(database.loadSyncConfig(), isNull);
      expect(LocalRoleDrafts(database, scope: 'workspace-b').load(), isEmpty);
      expect(
        () => store.save(
          WorkspaceRoleTemplate(
            name: ' reader ',
            permissions: RoleTemplatePreset.viewer.permissions,
          ),
        ),
        throwsFormatException,
      );
      database.close();
      database = await LocalDatabase.open(overridePath: path);
      store = LocalRoleDrafts(database, scope: 'workspace-a');
      expect(store.load().single.name, 'Reader');
      store.delete(store.load().single.id!);
      expect(store.load(), isEmpty);
      database.close();
      directory.deleteSync(recursive: true);
    },
  );
}
