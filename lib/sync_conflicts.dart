import 'dart:convert';

import 'package:flutter/material.dart';

import 'local_database.dart';
import 'workshop_delta.dart';

/// Durable review queue. An unresolved entity is held in the sync outbox.
class SyncConflictStore {
  SyncConflictStore(this.database, this.workspace);
  final LocalDatabase database;
  final String workspace;
  String get _key => 'sync_conflicts:$workspace';
  List<Map<String, dynamic>> load() =>
      (jsonDecode(database.loadStringPreference(_key, fallback: '[]')) as List)
          .cast<Map<String, dynamic>>();
  void save(List<Map<String, dynamic>> rows) =>
      database.saveStringPreference(_key, jsonEncode(rows));
  void record(Iterable<WorkshopFieldConflict> conflicts) {
    final rows = load();
    for (final c in conflicts) {
      rows.removeWhere(
        (r) =>
            r['entityType'] == c.entityType &&
            r['entityId'] == c.entityId &&
            r['field'] == c.field,
      );
      rows.add({
        'entityType': c.entityType,
        'entityId': c.entityId,
        'field': c.field,
        'local': c.localValue,
        'remote': c.remoteValue,
        'detectedAt': DateTime.now().toUtc().toIso8601String(),
      });
    }
    save(rows);
  }

  List<PendingWorkshopChange> readyForUpload(List<PendingWorkshopChange> pending, {bool atomicBuilds = false}) {
    final rows = load();
    final blocked = rows.map((r) => '${r['entityType']}\u0000${r['entityId']}').toSet();
    final holdBuildTransaction = atomicBuilds && rows.any((r) => r['entityType'] == 'inventory' || r['entityType'] == 'builds');
    return pending.where((p) => !blocked.contains('${p.change.entityType}\u0000${p.change.entityId}') &&
      !(holdBuildTransaction && (p.change.entityType == 'inventory' || p.change.entityType == 'builds'))).toList();
  }
  bool blocks(WorkshopEntityChange change) => load().any(
    (r) =>
        r['entityType'] == change.entityType &&
        r['entityId'] == change.entityId,
  );
}

class SyncConflictDialog extends StatefulWidget {
  const SyncConflictDialog({
    super.key,
    required this.store,
    required this.resolve,
  });
  final SyncConflictStore store;
  final Future<void> Function(Map<String, dynamic> row, bool remote) resolve;
  @override
  State<SyncConflictDialog> createState() => _SyncConflictDialogState();
}

class _SyncConflictDialogState extends State<SyncConflictDialog> {
  bool busy = false;
  String? error;
  Future<void> choose(Map<String, dynamic> row, bool remote) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.resolve(row, remote);
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => busy = false);
  }

  String display(Object? value) {
    final text = value is String
        ? value
        : const JsonEncoder.withIndent('  ').convert(value);
    return text.length > 2000 ? '${text.substring(0, 2000)}…' : text;
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.store.load();
    return AlertDialog(
      title: Text('Sync conflicts (${rows.length})'),
      content: SizedBox(
        width: 640,
        height: MediaQuery.sizeOf(context).height * .6,
        child: Column(
          children: [
            const Text(
              'These records stay on this device until reviewed. Other records continue syncing.',
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('No conflicts to review.'))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '${row['entityType']} · ${row['entityId']} · ${row['field']}',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Local at conflict: ${display(row['local'])}',
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Remote at conflict: ${display(row['remote'])}',
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton(
                                      onPressed: busy
                                          ? null
                                          : () => choose(row, false),
                                      child: const Text('Keep current local'),
                                    ),
                                    FilledButton(
                                      onPressed: busy
                                          ? null
                                          : () => choose(row, true),
                                      child: const Text('Use remote value'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
