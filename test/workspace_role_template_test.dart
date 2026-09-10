import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/workspace_role_template.dart';

void main() {
  test('presets require viewing and never enable destructive permissions', () {
    for (final preset in RoleTemplatePreset.values) {
      expect(preset.permissions, contains(WorkspacePermission.readInventory));
      expect(preset.permissions.any((p) => p.destructive), isFalse);
    }
    expect(RoleTemplatePreset.viewer.permissions.length, 1);
    expect(RoleTemplatePreset.builder.permissions, {
      WorkspacePermission.readInventory,
      WorkspacePermission.operateBuilds,
    });
  });

  test('templates are immutable and validate reserved names and required permissions', () {
    final permissions = RoleTemplatePreset.editor.permissions;
    final template = WorkspaceRoleTemplate(
      name: '  Stock assistant  ',
      permissions: permissions,
    );
    permissions.clear();
    expect(template.name, 'Stock assistant');
    expect(template.validationError, isNull);
    expect(template.permissions, isNotEmpty);
    for (final name in [
      '',
      ' OWNER ',
      'Admin',
      'manager',
      'editor',
      'builder',
      'x' * 61,
    ]) {
      expect(
        WorkspaceRoleTemplate(
          name: name,
          permissions: template.permissions,
        ).validationError,
        isNotNull,
      );
    }
    expect(
      WorkspaceRoleTemplate(name: 'Empty', permissions: {}).validationError,
      isNotNull,
    );
  });

  test(
    'unknown server permissions cannot be silently removed by an older editor',
    () {
      expect(
        () => WorkspaceRoleTemplate.fromJson({
          'id': 'id',
          'name': 'Future role',
          'permissions': ['inventory.read', 'future.operation'],
        }),
        throwsFormatException,
      );
      final restored = WorkspaceRoleTemplate.fromJson({
        'id': 'id',
        'name': 'Reader',
        'permissions': ['inventory.read'],
      });
      expect(restored.id, 'id');
      expect(restored.permissionIds, ['inventory.read']);
    },
  );
}
