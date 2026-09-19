import 'dart:convert';

import 'import_record_equality.dart';

import 'local_database.dart';
import 'workshop_delta.dart';

class ImportBatchStore {
  ImportBatchStore(this.database, this.scope);
  final LocalDatabase database;
  final String scope;
  String get prefix => 'import_batches:${base64Url.encode(utf8.encode(scope))}';
  List<Map<String, dynamic>> list() =>
      (jsonDecode(
            database.loadStringPreference('$prefix:index', fallback: '[]'),
          ) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList()
          .reversed
          .toList();
  Map<String, dynamic>? load(String id) {
    final raw = database.loadStringPreference('$prefix:$id', fallback: '');
    return raw.isEmpty
        ? null
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  /// History and inventory rows are committed in the same local transaction.
  String commit(
    String fileName,
    List<Map<String, dynamic>> items, {
    Iterable<WorkshopEntityChange> catalog = const [],
  }) {
    final ids = <String>{};
    for (final item in items) {
      final id = item['id'] as String;
      if (!ids.add(id) || database.readEntityPayload('inventory', id) != null) {
        throw StateError(
          'Import would overwrite an existing item. Review again.',
        );
      }
    }
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final header = {
      'id': id,
      'fileName': fileName,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'count': items.length,
    };
    final index = list().reversed.toList()..add(header);
    database.applyAndQueueWorkshopChanges(
      [
        ...catalog,
        for (final item in items)
          WorkshopEntityChange(
            entityType: 'inventory',
            entityId: item['id'] as String,
            fields: item,
          ),
      ],
      localPreferences: {
        '$prefix:index': jsonEncode(index),
        '$prefix:$id': jsonEncode({
          ...header,
          'items': items,
          'undone': <String>[],
        }),
      },
    );
    return id;
  }

  /// Re-checks every record at commit time. Catalog entries and history remain.
  ({List<WorkshopEntityChange> changes, int protected, int missing}) undo(
    String id,
  ) {
    final batch = load(id);
    if (batch == null) {
      throw StateError('Import history is no longer available.');
    }
    final undone = Set<String>.from(batch['undone'] as List);
    final changes = <WorkshopEntityChange>[];
    var protected = 0;
    var missing = 0;
    for (final raw in batch['items'] as List) {
      final expected = Map<String, dynamic>.from(raw as Map);
      final itemId = expected['id'] as String;
      if (undone.contains(itemId)) continue;
      final current = database.readFullInventoryPayload(itemId);
      if (current == null) {
        missing++;
        undone.add(itemId);
        continue;
      }
      if (!sameImportRecord(current, expected) ||
          database.hasImportItemReferences(
            itemId,
            expected['name'] as String,
          )) {
        protected++;
        continue;
      }
      changes.add(
        WorkshopEntityChange(
          entityType: 'inventory',
          entityId: itemId,
          fields: const {},
          deleted: true,
          baseFields: {'(importUndo)': true, '(deleted)': expected},
        ),
      );
      undone.add(itemId);
    }
    database.applyAndQueueWorkshopChanges(
      changes,
      localPreferences: {
        '$prefix:$id': jsonEncode({...batch, 'undone': undone.toList()}),
      },
    );
    return (changes: changes, protected: protected, missing: missing);
  }
}
