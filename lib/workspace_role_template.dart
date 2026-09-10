/// Permissions enforced by server v25 when a template is assigned.
enum WorkspacePermission {
  readInventory(
    'inventory.read',
    'Inventory',
    'View inventory',
    'Browse the shared inventory and its details.',
  ),
  createInventory(
    'inventory.create',
    'Inventory',
    'Add inventory',
    'Create new inventory records.',
  ),
  editInventory(
    'inventory.edit',
    'Inventory',
    'Edit inventory',
    'Change item details, quantities, locations, drying and usage records.',
  ),
  archiveInventory(
    'inventory.archive',
    'Inventory',
    'Archive inventory',
    'Archive or restore inventory records without permanently deleting them.',
  ),
  deleteInventory(
    'inventory.delete',
    'Inventory',
    'Permanently delete items',
    'Remove inventory records permanently.',
    destructive: true,
  ),
  manageCatalog(
    'catalog.manage',
    'Catalog',
    'Manage catalog',
    'Create and edit kits, machines and other catalog records.',
  ),
  createBuilds(
    'builds.create',
    'Builds',
    'Create builds',
    'Create and configure build records.',
  ),
  shareBuilds(
    'builds.share',
    'Builds',
    'Share builds',
    'Make builds available to other workspace members.',
  ),
  operateBuilds(
    'builds.operate',
    'Builds',
    'Operate shared builds',
    'Progress shared builds and consume materials within build limits.',
  ),
  manageDevices(
    'devices.manage',
    'Workspace',
    'Manage devices',
    'List and pair devices; existing role-assignment limits still apply.',
  ),
  deleteDatabase(
    'database.delete',
    'Workspace',
    'Delete database',
    'Delete this device’s local database. Remote ownership is unchanged.',
    destructive: true,
  );

  const WorkspacePermission(
    this.id,
    this.group,
    this.label,
    this.description, {
    this.destructive = false,
  });

  final String id;
  final String group;
  final String label;
  final String description;
  final bool destructive;
}

class WorkspaceRoleTemplate {
  WorkspaceRoleTemplate({
    this.id,
    required String name,
    String description = '',
    required Set<WorkspacePermission> permissions,
  }) : name = name.trim(),
       description = description.trim(),
       permissions = Set.unmodifiable(permissions);

  final String? id;
  final String name;
  final String description;
  final Set<WorkspacePermission> permissions;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'permissions': permissionIds,
  };

  static const reservedNames = {
    'owner',
    'admin',
    'manager',
    'editor',
    'builder',
  };

  String? get validationError {
    if (name.isEmpty || name.runes.length > 60) {
      return 'Use a role name between 1 and 60 characters.';
    }
    if (reservedNames.contains(name.toLowerCase())) {
      return 'Choose a name different from the built-in roles.';
    }
    if (description.runes.length > 240) {
      return 'Keep the description within 240 characters.';
    }
    if (!permissions.contains(WorkspacePermission.readInventory)) {
      return 'Every role template must include View inventory.';
    }
    return null;
  }

  List<String> get permissionIds =>
      permissions.map((p) => p.id).toList()..sort();

  factory WorkspaceRoleTemplate.fromJson(Map<String, dynamic> json) {
    final ids = (json['permissions'] as List).cast<String>();
    final known = WorkspacePermission.values.map((p) => p.id).toSet();
    if (ids.any((id) => !known.contains(id))) {
      throw const FormatException('Update the app to edit these permissions.');
    }
    return WorkspaceRoleTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      permissions: WorkspacePermission.values
          .where((p) => ids.contains(p.id))
          .toSet(),
    );
  }
}

/// Copyable starting points, independent of live membership roles.
enum RoleTemplatePreset {
  viewer('View only'),
  builder('Build operator'),
  editor('Inventory editor'),
  manager('Workshop manager');

  const RoleTemplatePreset(this.label);
  final String label;

  Set<WorkspacePermission> get permissions => {
    WorkspacePermission.readInventory,
    if (this != viewer) WorkspacePermission.operateBuilds,
    if (this == editor || this == manager) ...{
      WorkspacePermission.editInventory,
      WorkspacePermission.createBuilds,
      WorkspacePermission.shareBuilds,
    },
    if (this == manager) ...{
      WorkspacePermission.createInventory,
      WorkspacePermission.archiveInventory,
      WorkspacePermission.manageCatalog,
      WorkspacePermission.manageDevices,
    },
  };
}
