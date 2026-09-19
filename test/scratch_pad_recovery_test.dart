import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/scratch_pad.dart';

void main() {
  final note = ScratchPadNote(
    id: 'note',
    title: 'Saved',
    body: 'Remote',
    updatedAt: DateTime.utc(2026),
    sourceDeviceName: 'VM1',
    sourceUserId: 'old',
    subjectKind: 'Item',
    subjectId: 'part',
    subjectLabel: 'Part',
  );
  test('recovered notes become editable local notes and retain links', () {
    final result = mergeRecoveredScratchPadNotes([], [note]);
    expect(result.single.sourceDeviceName, isNull);
    expect(result.single.subjectId, 'part');
    expect(result.single.isShared, isFalse);
    expect(mergeRecoveredScratchPadNotes(result, [note]), hasLength(1));
  });
  test(
    'recovery preserves different local edits and is repeatable after restart',
    () {
      final result = mergeRecoveredScratchPadNotes(
        [note.copyWith(body: 'Local')],
        [note],
      );
      expect(result, hasLength(2));
      expect(result.first.body, 'Local');
      expect(result.last.body, 'Remote');
      expect(
        mergeRecoveredScratchPadNotes(
          decodeScratchPadNotes(encodeScratchPadNotes(result)),
          [note],
        ),
        hasLength(2),
      );
    },
  );
  test('archive identity survives local cache serialization', () {
    expect(
      decodeScratchPadNotes(encodeScratchPadNotes([note])).single.sourceUserId,
      'old',
    );
  });
  testWidgets(
    'archived notes offer explicit restore and disappear after success',
    (tester) async {
      var restored = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ScratchPadDialog(
            notes: const [],
            reviewNotes: [note],
            onChanged: (_) {},
            onRestoreNote: (selected) async {
              expect(selected.sourceUserId, 'old');
              restored = true;
              return true;
            },
            buttonSurfaceBuilder: ({
              required states,
              required child,
              joined = false,
            }) => child,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scratch-pad-note-note')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore to device'));
      await tester.pumpAndSettle();
      expect(restored, isTrue);
      expect(find.byKey(const Key('scratch-pad-note-note')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'Owner revisions replace stale edits and survive restart without replay',
    () {
      final revisions = <String, int>{};
      final update = ScratchPadNote(
        id: 'note',
        title: 'Owner',
        body: 'Corrected',
        updatedAt: DateTime.utc(2026, 2),
        ownerRevision: 1,
      );
      final merged = mergeRecoveredScratchPadNotes(
        [note],
        [update],
        ownerRevisions: revisions,
      );
      expect(merged.single.body, 'Corrected');
      expect(merged.single.ownerRevision, 1);
      final edited = merged.single.copyWith(body: 'Later author edit');
      expect(
        mergeRecoveredScratchPadNotes(
          [edited],
          [update],
          ownerRevisions: revisions,
        ).single.body,
        'Later author edit',
      );
      expect(
        mergeRecoveredScratchPadNotes([], [update], ownerRevisions: revisions),
        isEmpty,
      );
      final deleted = ScratchPadNote(
        id: 'note',
        title: 'Owner',
        body: '',
        updatedAt: DateTime.utc(2026, 3),
        ownerRevision: 2,
        ownerDeleted: true,
      );
      expect(
        mergeRecoveredScratchPadNotes(
          [edited],
          [deleted],
          ownerRevisions: revisions,
        ),
        isEmpty,
      );
      expect(
        mergeRecoveredScratchPadNotes(
          [note],
          [deleted],
          ownerRevisions: revisions,
        ),
        isEmpty,
      );
      expect(
        decodeScratchPadNotes(encodeScratchPadNotes([edited]))
            .single
            .ownerRevision,
        1,
      );
    },
  );

  testWidgets(
    'Owner controls delete an archived note only after confirmation',
    (tester) async {
      var called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ScratchPadDialog(
            notes: const [],
            reviewNotes: [note],
            onChanged: (_) {},
            onManageNote: (original, replacement) async {
              expect(original.sourceUserId, 'old');
              expect(replacement, isNull);
              called = true;
              return true;
            },
            buttonSurfaceBuilder: ({
              required states,
              required child,
              joined = false,
            }) => child,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scratch-pad-note-note')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Edit as Owner'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete as Owner'));
      await tester.pumpAndSettle();
      expect(called, isFalse);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(called, isTrue);
      expect(find.byKey(const Key('scratch-pad-note-note')), findsNothing);
    },
  );

  testWidgets('ordinary shared-note readers do not get Owner controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScratchPadDialog(
          notes: const [],
          sharedNotes: [note],
          onChanged: (_) {},
          buttonSurfaceBuilder: ({
            required states,
            required child,
            joined = false,
          }) => child,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scratch-pad-note-note')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit as Owner'), findsNothing);
    expect(find.byTooltip('Delete as Owner'), findsNothing);
  });
}
