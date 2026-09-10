import 'dart:convert';

import 'local_database.dart';
import 'workspace_role_template.dart';

/// Local design drafts only; never consulted by authorization or sync.
class LocalRoleDrafts {
  LocalRoleDrafts(this.database, {required String scope})
    : _key = 'local_role_drafts:${base64Url.encode(utf8.encode(scope))}';
  final LocalDatabase database;
  final String _key;
  List<WorkspaceRoleTemplate> load() {
    final json = jsonDecode(
      database.loadStringPreference(_key, fallback: '[]'),
    );
    if (json is! List) {
      throw const FormatException('Local role drafts could not be read.');
    }
    return json
        .map(
          (row) => WorkspaceRoleTemplate.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  void save(WorkspaceRoleTemplate template) {
    final error = template.validationError;
    if (error != null) throw FormatException(error);
    final drafts = load();
    if (drafts.any(
      (d) =>
          d.id != template.id &&
          d.name.toLowerCase() == template.name.toLowerCase(),
    )) {
      throw const FormatException(
        'A local draft with that name already exists.',
      );
    }
    final id = template.id ?? 'local-${DateTime.now().microsecondsSinceEpoch}';
    final saved = WorkspaceRoleTemplate(
      id: id,
      name: template.name,
      description: template.description,
      permissions: template.permissions,
    );
    if (template.id != null && !drafts.any((d) => d.id == id)) {
      throw const FormatException('Local role draft no longer exists.');
    }
    _write([...drafts.where((d) => d.id != id), saved]);
  }

  void delete(String id) => _write(load().where((d) => d.id != id).toList());
  void _write(List<WorkspaceRoleTemplate> drafts) {
    drafts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    database.saveStringPreference(
      _key,
      jsonEncode(drafts.map((d) => d.toJson()).toList()),
    );
  }
}
