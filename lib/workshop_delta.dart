import 'dart:convert';

const workshopEntityCollections = <String>{
  'inventory',
  'customItemTypes',
  'machineTypes',
  'machines',
  'kits',
  'builds',
  'locations',
  'shoppingList',
  'auditLog',
  'vendors',
  'brands',
  'spoolTypes',
  'materials',
  'products',
  'additionHistory',
};

const workshopMetadataEntityType = 'workshopMetadata';
const workshopMetadataEntityId = 'singleton';

class WorkshopEntityChange {
  const WorkshopEntityChange({
    required this.entityType,
    required this.entityId,
    required this.fields,
    this.deleted = false,
    this.revision,
  });

  final String entityType;
  final String entityId;
  final Map<String, dynamic> fields;
  final bool deleted;
  final int? revision;

  Map<String, dynamic> toJson() => {
    'entityType': entityType,
    'entityId': entityId,
    'fields': fields,
    'deleted': deleted,
    if (revision != null) 'revision': revision,
  };

  factory WorkshopEntityChange.fromJson(Map<String, dynamic> json) =>
      WorkshopEntityChange(
        entityType: json['entityType'] as String,
        entityId: json['entityId'] as String,
        fields: Map<String, dynamic>.from(
          json['fields'] as Map<String, dynamic>? ?? const {},
        ),
        deleted: json['deleted'] as bool? ?? false,
        revision: (json['revision'] as num?)?.toInt(),
      );
}

Map<String, dynamic> _metadata(Map<String, dynamic> root) => {
  for (final entry in root.entries)
    if (!workshopEntityCollections.contains(entry.key)) entry.key: entry.value,
};

Map<String, Map<String, dynamic>> _indexedCollection(
  Map<String, dynamic> root,
  String type,
) => {
  for (final value in (root[type] as List<dynamic>? ?? const []))
    if (value is Map<String, dynamic> && value['id'] is String)
      value['id'] as String: Map<String, dynamic>.from(value),
};

bool _sameJson(Object? left, Object? right) =>
    jsonEncode(left) == jsonEncode(right);

Map<String, dynamic> _changedFields(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) => {
  for (final entry in after.entries)
    if (!before.containsKey(entry.key) ||
        !_sameJson(before[entry.key], entry.value))
      entry.key: entry.value,
  for (final key in before.keys)
    if (!after.containsKey(key)) key: null,
};

Map<String, dynamic> changedWorkshopEntityFields(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) => _changedFields(before, after);

List<WorkshopEntityChange> diffWorkshopStates(
  String? previousStateJson,
  String currentStateJson,
) {
  final before = previousStateJson == null || previousStateJson.isEmpty
      ? <String, dynamic>{}
      : Map<String, dynamic>.from(jsonDecode(previousStateJson) as Map);
  final after = Map<String, dynamic>.from(jsonDecode(currentStateJson) as Map);
  final changes = <WorkshopEntityChange>[];

  for (final type in workshopEntityCollections) {
    final oldRows = _indexedCollection(before, type);
    final newRows = _indexedCollection(after, type);
    for (final entry in newRows.entries) {
      final old = oldRows[entry.key];
      final fields = old == null
          ? entry.value
          : _changedFields(old, entry.value);
      if (fields.isNotEmpty) {
        changes.add(
          WorkshopEntityChange(
            entityType: type,
            entityId: entry.key,
            fields: fields,
          ),
        );
      }
    }
    for (final id in oldRows.keys.where((id) => !newRows.containsKey(id))) {
      changes.add(
        WorkshopEntityChange(
          entityType: type,
          entityId: id,
          fields: const {},
          deleted: true,
        ),
      );
    }
  }

  final metadataFields = _changedFields(_metadata(before), _metadata(after));
  if (metadataFields.isNotEmpty) {
    changes.add(
      WorkshopEntityChange(
        entityType: workshopMetadataEntityType,
        entityId: workshopMetadataEntityId,
        fields: metadataFields,
      ),
    );
  }
  return changes;
}

String applyWorkshopEntityChanges(
  String currentStateJson,
  Iterable<WorkshopEntityChange> changes,
) {
  final root = Map<String, dynamic>.from(jsonDecode(currentStateJson) as Map);
  for (final change in changes) {
    if (change.entityType == workshopMetadataEntityType) {
      if (change.deleted) continue;
      for (final entry in change.fields.entries) {
        if (entry.value == null) {
          root.remove(entry.key);
        } else {
          root[entry.key] = entry.value;
        }
      }
      continue;
    }
    if (!workshopEntityCollections.contains(change.entityType)) continue;
    final rows = (root[change.entityType] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
    final index = rows.indexWhere((row) => row['id'] == change.entityId);
    if (change.deleted) {
      if (index >= 0) rows.removeAt(index);
    } else if (index >= 0) {
      final updated = {...rows[index]};
      for (final entry in change.fields.entries) {
        if (entry.value == null) {
          updated.remove(entry.key);
        } else {
          updated[entry.key] = entry.value;
        }
      }
      updated['id'] = change.entityId;
      rows[index] = updated;
    } else {
      rows.add({'id': change.entityId, ...change.fields});
    }
    root[change.entityType] = rows;
  }
  return jsonEncode(root);
}
