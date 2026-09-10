import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/sync_conflicts.dart';
import 'package:inventorinator/workshop_delta.dart';
import 'package:inventorinator/workshop_reports.dart';
import 'package:inventorinator/supabase_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'custom permissions fail closed and do not inherit Builder operations',
    () {
      final role = WorkspaceRole.fromServer(
        'custom:${jsonEncode({
          'name': 'Reader',
          'permissions': ['inventory.read'],
        })}',
      );
      expect(role.canOperateBuilds, false);
      expect(role.canCreateInventory, false);
      expect(role.canEditInventory, false);
      expect(role.canDeleteDatabase, false);
      expect(WorkspaceRole.fromServer('custom:broken').canOperateBuilds, false);
      final editor = WorkspaceRole.fromServer(
        'custom:${jsonEncode({
          'name': 'Editor',
          'permissions': ['inventory.read', 'inventory.edit'],
        })}',
      );
      expect(editor.canEditInventory, true);
      expect(editor.canArchiveInventory, false);
    },
  );
  test(
    'conflicts survive restart, retain both values and isolate workspaces',
    () async {
      final dir = Directory.systemTemp.createTempSync('conflict-review-');
      final path = '${dir.path}/db.sqlite';
      var db = await LocalDatabase.open(overridePath: path);
      final merge = mergeRemoteChangesWithPending(
        [
          const WorkshopEntityChange(
            entityType: 'inventory',
            entityId: 'a',
            fields: {'name': 'Remote', 'quantity': 3},
          ),
        ],
        [
          const WorkshopEntityChange(
            entityType: 'inventory',
            entityId: 'a',
            fields: {'name': 'Local'},
          ),
        ],
      );
      var store = SyncConflictStore(db, 'a');
      store.record(merge.conflicts);
      expect(merge.changes.single.fields, {'name': 'Local', 'quantity': 3});
      expect(store.blocks(merge.changes.single), true);
      expect(
        store.blocks(
          const WorkshopEntityChange(
            entityType: 'inventory',
            entityId: 'b',
            fields: {},
          ),
        ),
        false,
      );
      expect(SyncConflictStore(db, 'b').load(), isEmpty);
      db.close();
      db = await LocalDatabase.open(overridePath: path);
      store = SyncConflictStore(db, 'a');
      expect(store.load().single['remote'], 'Remote');
      expect(store.load().single['local'], 'Local');
      store.save([]);
      expect(store.blocks(merge.changes.single), false);
      db.close();
      dir.deleteSync(recursive: true);
    },
  );
  test('remote deletion cannot erase pending local edits', () {
    final merge = mergeRemoteChangesWithPending(
      [
        const WorkshopEntityChange(
          entityType: 'inventory',
          entityId: 'a',
          fields: {},
          deleted: true,
        ),
      ],
      [
        const WorkshopEntityChange(
          entityType: 'inventory',
          entityId: 'a',
          fields: {'name': 'Local'},
        ),
      ],
    );
    expect(merge.conflicts.single.field, '(remote deleted)');
    expect(merge.changes.single.deleted, false);
  });
  test('unrelated remote changes do not create false conflicts', () async {
    final dir = Directory.systemTemp.createTempSync('baseline-test-');
    final db = await LocalDatabase.open(overridePath: '${dir.path}/db');
    db.applyRemoteWorkshopChanges([
      const WorkshopEntityChange(
        entityType: 'inventory',
        entityId: 'a',
        fields: {'name': 'Original', 'quantity': 1},
      ),
    ]);
    db.applyAndQueueWorkshopChanges([
      const WorkshopEntityChange(
        entityType: 'inventory',
        entityId: 'a',
        fields: {'name': 'Local'},
      ),
    ]);
    final pending = db.loadPendingWorkshopChanges();
    expect(pending.single.change.baseFields!['name'], 'Original');
    final merged = mergeRemoteChangesWithPending([
      const WorkshopEntityChange(
        entityType: 'inventory',
        entityId: 'a',
        fields: {'name': 'Original', 'quantity': 2},
      ),
    ], pending.map((p) => p.change));
    expect(merged.conflicts, isEmpty);
    expect(merged.changes.single.fields, {'name': 'Local', 'quantity': 2});
    db.applyAndQueueWorkshopChanges([
      const WorkshopEntityChange(
        entityType: 'inventory',
        entityId: 'a',
        fields: {'name': 'Newer'},
      ),
    ]);
    db.acknowledgePendingWorkshopChanges(pending);
    expect(
      db.loadPendingWorkshopChanges().single.change.baseFields!['name'],
      'Local',
    );
    expect(
      db.loadPendingWorkshopChanges().single.change.fields['name'],
      'Newer',
    );
    db.close();
    dir.deleteSync(recursive: true);
  });
  test('operators upload build progress and stock in one transaction', () {
    final changes = [
      const WorkshopEntityChange(
        entityType: 'inventory',
        entityId: 'a',
        fields: {'quantity': 1},
      ),
      const WorkshopEntityChange(
        entityType: 'auditLog',
        entityId: 'a',
        fields: {},
      ),
      const WorkshopEntityChange(
        entityType: 'builds',
        entityId: 'b',
        fields: {'lines': []},
      ),
    ];
    final batches = workshopUploadBatches(
      changes,
      (c) => c,
      atomicBuilds: true,
    );
    expect(batches.first.map((c) => c.entityType), ['inventory', 'builds']);
    expect(batches.last.single.entityType, 'auditLog');
  });
  test('report range includes entire end day and excludes missing dates', () {
    final report = WorkshopReport(
      'Usage',
      ['Item'],
      [
        ReportRow(['match'], date: DateTime(2026, 9, 10, 23, 59)),
        ReportRow(['match'], date: DateTime(2026, 9, 11)),
        const ReportRow(['match']),
      ],
    );
    expect(
      filterReport(
        report,
        'MATCH',
        DateTimeRange(start: DateTime(2026, 9, 10), end: DateTime(2026, 9, 10)),
      ).length,
      1,
    );
  });
  test('multi-page printable report with Unicode and long item names', () async {
    final bytes = await generateReportPdf({
      'font': File('assets/fonts/DejaVuSans.ttf').readAsBytesSync(),
      'title': 'Kit: Sensor workstation — α2',
      'note': 'One kit; reserved stock excluded. 240 lines. Units: pieces.',
      'columns': <String>['Done', 'Part', 'Required', 'Available', 'Shortage'],
      'rows': List.generate(
        240,
        (i) => <String>[
          '☐',
          'Part $i — M3 socket-head fastener / temperature sensor with a long descriptive manufacturer name',
          '12',
          '8',
          '4',
        ],
      ),
    });
    expect(utf8.decode(bytes.take(4).toList()), '%PDF');
    File('/tmp/inventorinator-report-validation.pdf').writeAsBytesSync(bytes);
  });
}
