import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/import_batches.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/workshop_delta.dart';
import 'package:inventorinator/sync_conflicts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalDatabase db;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('import-undo-');
    db = await LocalDatabase.open(overridePath: '${dir.path}/db');
  });
  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });
  Map<String, dynamic> item(String id) => {
    'id': id,
    'name': 'Part $id',
    'quantity': 2,
    'image': base64Encode([1, 2, 3]),
    'labelImage': null,
  };
  test(
    'batch and undo survive restart, isolate scopes and leave unrelated stock',
    () async {
      final store = ImportBatchStore(db, 'local');
      final id = store.commit('parts.csv', [item('a'), item('b')]);
      db.applyAndQueueWorkshopChanges([
        WorkshopEntityChange(
          entityType: 'inventory',
          entityId: 'other',
          fields: item('other'),
        ),
      ]);
      db.close();
      db = await LocalDatabase.open(overridePath: '${dir.path}/db');
      expect(ImportBatchStore(db, 'remote').list(), isEmpty);
      final reopened = ImportBatchStore(db, 'local');
      expect(reopened.list().single['fileName'], 'parts.csv');
      final result = reopened.undo(id);
      expect(result.changes, hasLength(2));
      expect(db.readEntityPayload('inventory', 'a'), isNull);
      expect(db.readEntityPayload('inventory', 'other'), isNotNull);
      final deletes = db
          .loadPendingWorkshopChanges()
          .where((p) => p.change.deleted)
          .toList();
      expect(deletes, hasLength(2));
      expect(deletes.first.change.baseFields?['(importUndo)'], true);
      db.close();
      db = await LocalDatabase.open(overridePath: '${dir.path}/db');
      expect(ImportBatchStore(db, 'local').undo(id).changes, isEmpty);
      expect(db.readEntityPayload('inventory', 'a'), isNull);
    },
  );
  test('later quantity, image, and reference changes are protected', () {
    final store = ImportBatchStore(db, 'local');
    final id = store.commit('parts.json', [
      for (final id in ['a', 'b', 'c', 'd']) item(id),
    ]);
    db.applyAndQueueWorkshopChanges([
      const WorkshopEntityChange(
        entityType: 'inventory',
        entityId: 'a',
        fields: {'quantity': 1},
      ),
      WorkshopEntityChange(
        entityType: 'inventory',
        entityId: 'b',
        fields: {
          'image': base64Encode([4, 5]),
        },
      ),
      const WorkshopEntityChange(
        entityType: 'builds',
        entityId: 'build',
        fields: {
          'lines': [
            {
              'consumedInventoryIds': ['c'],
            },
          ],
        },
      ),
    ]);
    final result = store.undo(id);
    expect(result.protected, 3);
    expect(result.changes.single.entityId, 'd');
    for (final id in ['a', 'b', 'c']) {
      expect(db.readEntityPayload('inventory', id), isNotNull);
    }
  });
  test(
    'guarded remote conflicts stay held and never become ordinary deletes',
    () {
      final store = ImportBatchStore(db, 'local');
      final id = store.commit('parts.csv', [item('a')]);
      // Simulate a successful first upload before undo.
      db.acknowledgePendingWorkshopChanges(db.loadPendingWorkshopChanges());
      store.undo(id);
      final pending = db.loadPendingWorkshopChanges();
      final merge = mergeRemoteChangesWithPending([
        WorkshopEntityChange(
          entityType: 'inventory',
          entityId: 'a',
          fields: {...item('a'), 'quantity': 9},
        ),
      ], pending.map((p) => p.change));
      expect(merge.conflicts.single.field, '(deleted)');
      final conflicts = SyncConflictStore(db, 'workspace')
        ..record(merge.conflicts);
      expect(conflicts.readyForUpload(pending), isEmpty);
      expect(conflicts.load(), hasLength(1));
      final decoded = WorkshopEntityChange.fromJson(
        pending.single.change.toJson(),
      );
      expect(decoded.baseFields?['(importUndo)'], true);
    },
  );
  test(
    'old servers hold only guarded undo and duplicate commit cannot overwrite',
    () {
      final store = ImportBatchStore(db, 'local');
      final id = store.commit('a.csv', [item('a')]);
      expect(() => store.commit('b.csv', [item('a')]), throwsStateError);
      expect(store.list(), hasLength(1));
      store.undo(id);
      db.applyAndQueueWorkshopChanges([
        WorkshopEntityChange(
          entityType: 'inventory',
          entityId: 'other',
          fields: item('other'),
        ),
      ]);
      final ready = SyncConflictStore(
        db,
        'workspace',
      ).readyForUpload(db.loadPendingWorkshopChanges(), serverSchema: 29);
      expect(ready.single.change.entityId, 'other');
    },
  );

  test('server echo without null fields does not conflict with undo', () {
    final store = ImportBatchStore(db, 'local');
    final id = store.commit('parts.csv', [item('a')]);
    store.undo(id);
    final remote = item('a')..remove('labelImage');
    final merged = mergeRemoteChangesWithPending([
      WorkshopEntityChange(
        entityType: 'inventory',
        entityId: 'a',
        fields: remote,
      ),
    ], db.loadPendingWorkshopChanges().map((p) => p.change));
    expect(merged.conflicts, isEmpty);
  });
}
