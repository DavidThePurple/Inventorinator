import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventorinator/local_database.dart';
import 'package:inventorinator/main.dart';
import 'package:inventorinator/supabase_sync.dart';
import 'package:inventorinator/workshop_delta.dart';

// Roadmap requirement ("State-safe delayed writes"): create an item,
// immediately change one of its fields while that item's initial upload is
// still in flight, let the delayed upload response and a later download both
// land out of order, and prove the newest visible value never rolls back.
//
// This drives the real LocalDatabase outbox and a real SupabaseSyncService
// HTTP round trip (via a MockClient with a deliberately held-open response),
// rather than the widget tree -- local persistence is already proven
// synchronous elsewhere, so the property worth proving end-to-end here is
// specifically about the network round trip and the outbox/ack mechanism.
void main() {
  const config = SupabaseConfig(
    url: 'https://inventory.example',
    publishableKey: 'sb_publishable_test',
    workspaceId: 'WORKSPACE-RACE',
  );
  final session = SupabaseSession(
    accessToken: 'access-race',
    refreshToken: 'refresh-race',
    userId: 'USER-RACE',
  );

  test(
    'a status change made while the create-upload is in flight is never '
    'lost to an out-of-order acknowledgement or a stale download',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'inventorinator-sync-race-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final database = await LocalDatabase.open(
        overridePath: '${directory.path}/inventory.sqlite3',
      );
      addTearDown(database.close);

      // "Creates an item" -- seed local state and its matching outbox entry,
      // exactly what _persistChangedEntities does synchronously right after
      // Add Item returns.
      database.saveState(
        '{"schemaVersion":8,"inventory":[],"vendors":[],"brands":[],'
        '"products":[]}',
      );
      final baseFields = {
        'id': 'INV-RACE',
        'name': 'Race PLA',
        'type': 'filament',
        'compatibility': <String>[],
        'added': DateTime.utc(2026).toIso8601String(),
        'cost': 10,
        'color': 0xff000000,
      };
      database.saveEntityPayloadAndQueue('inventory', 'INV-RACE', {
        ...baseFields,
        'filamentStatus': 'ready',
      });
      final uploadingBatch = database.loadPendingWorkshopChanges();
      expect(uploadingBatch, hasLength(1));

      final releaseUploadResponse = Completer<void>();
      var uploadRequestCount = 0;
      final service = SupabaseSyncService(
        config,
        client: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/apply_inventorinator_entity_changes');
          uploadRequestCount++;
          await releaseUploadResponse.future;
          return http.Response(jsonEncode(1), 200);
        }),
      );

      // Start the create-upload but do not await it yet -- this is "the
      // initial ... write is delayed".
      final uploadFuture = service.uploadChanges(
        session,
        uploadingBatch.map((entry) => entry.change),
        deviceId: 'DEVICE-RACE',
      );
      // uploadChanges encodes the request body via Isolate.run before the
      // HTTP call is dispatched -- give that real isolate round trip time to
      // actually happen before checking the mock received the request.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(uploadRequestCount, 1);

      // "Immediately changes its status ... while the initial ... write is
      // delayed": a second local edit lands on the same entity before the
      // first upload's response ever arrives.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      database.saveEntityPayloadAndQueue('inventory', 'INV-RACE', {
        ...baseFields,
        'filamentStatus': 'deployed',
      });
      expect(
        decodeWorkshopState(database.loadState())!.inventory.single
            .filamentStatus,
        FilamentStatus.deployed,
      );

      // Now the delayed upload response ("remote acknowledgement") lands.
      releaseUploadResponse.complete();
      await uploadFuture;
      database.acknowledgePendingWorkshopChanges(uploadingBatch);

      // The stale ack must not discard the newer edit -- it's still queued.
      final stillPending = database.loadPendingWorkshopChanges();
      expect(stillPending, hasLength(1));
      expect(stillPending.single.change.fields['filamentStatus'], 'deployed');
      expect(
        decodeWorkshopState(database.loadState())!.inventory.single
            .filamentStatus,
        FilamentStatus.deployed,
      );

      // A slower device's download of the *original* create (its own stale
      // view, arriving after our newer local edit) must not roll anything
      // back either, once merged against what's still in the outbox.
      final staleRemoteEcho = [
        WorkshopEntityChange(
          entityType: 'inventory',
          entityId: 'INV-RACE',
          fields: {...baseFields, 'filamentStatus': 'ready'},
          revision: 1,
        ),
      ];
      final merged = mergeRemoteChangesWithPending(
        staleRemoteEcho,
        stillPending.map((entry) => entry.change),
      );
      expect(merged.changes.single.fields['filamentStatus'], 'deployed');
      expect(merged.conflicts, hasLength(1));
      expect(merged.conflicts.single.field, 'filamentStatus');
      database.applyRemoteWorkshopChanges(merged.changes);

      // The newest visible value never rolled back, on disk or in memory.
      expect(
        decodeWorkshopState(database.loadState())!.inventory.single
            .filamentStatus,
        FilamentStatus.deployed,
      );
    },
  );

  test(
    'location, lifecycle, and detail edits survive delayed create uploads',
    () async {
      const scenarios = [
        (
          field: 'storageLocationId',
          remoteValue: 'LOC-REMOTE',
          localValue: 'LOC-LOCAL',
        ),
        (field: 'archived', remoteValue: false, localValue: true),
        (
          field: 'name',
          remoteValue: 'Remote name',
          localValue: 'Renamed locally',
        ),
      ];

      for (final scenario in scenarios) {
        final directory = await Directory.systemTemp.createTemp(
          'inventorinator-sync-race-${scenario.field}-',
        );
        final database = await LocalDatabase.open(
          overridePath: '${directory.path}/inventory.sqlite3',
        );
        try {
          database.saveState(
            '{"schemaVersion":8,"inventory":[],"vendors":[],'
            '"brands":[],"products":[]}',
          );
          final baseFields = <String, dynamic>{
            'id': 'INV-RACE',
            'name': 'Race PLA',
            'type': 'filament',
            'compatibility': <String>[],
            'added': DateTime.utc(2026).toIso8601String(),
            'cost': 10,
            'color': 0xff000000,
            scenario.field: scenario.remoteValue,
          };
          database.saveEntityPayloadAndQueue(
            'inventory',
            'INV-RACE',
            baseFields,
          );
          final uploadingBatch = database.loadPendingWorkshopChanges();
          final releaseUploadResponse = Completer<void>();
          final service = SupabaseSyncService(
            config,
            client: MockClient((request) async {
              await releaseUploadResponse.future;
              return http.Response(jsonEncode(1), 200);
            }),
          );
          final uploadFuture = service.uploadChanges(
            session,
            uploadingBatch.map((entry) => entry.change),
            deviceId: 'DEVICE-RACE',
          );
          await Future<void>.delayed(const Duration(milliseconds: 200));

          database.saveEntityPayloadAndQueue('inventory', 'INV-RACE', {
            ...baseFields,
            scenario.field: scenario.localValue,
          });
          releaseUploadResponse.complete();
          await uploadFuture;
          database.acknowledgePendingWorkshopChanges(uploadingBatch);

          final pending = database.loadPendingWorkshopChanges();
          expect(pending, hasLength(1));
          expect(pending.single.change.fields[scenario.field], scenario.localValue);

          final merged = mergeRemoteChangesWithPending(
            [
              WorkshopEntityChange(
                entityType: 'inventory',
                entityId: 'INV-RACE',
                fields: baseFields,
                revision: 1,
              ),
            ],
            pending.map((entry) => entry.change),
          );
          expect(
            merged.changes.single.fields[scenario.field],
            scenario.localValue,
          );
          database.applyRemoteWorkshopChanges(merged.changes);
          final restored =
              jsonDecode(database.loadState()!) as Map<String, dynamic>;
          final restoredItem =
              (restored['inventory'] as List<dynamic>).single
                  as Map<String, dynamic>;
          expect(
            restoredItem[scenario.field],
            scenario.localValue,
          );
        } finally {
          database.close();
          await directory.delete(recursive: true);
        }
      }
    },
  );
}
