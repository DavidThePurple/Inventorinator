import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/scratch_pad.dart';

ScratchPadNote note(
  String id, {
  String? sourceDeviceName,
  bool shared = false,
}) => ScratchPadNote(
  id: id,
  title: id,
  body: 'Note $id',
  updatedAt: DateTime.utc(2026),
  isShared: shared,
  sourceDeviceName: sourceDeviceName,
);

void main() {
  test('cached shared notes retain their source device name', () {
    final restored = decodeScratchPadNotes(
      encodeScratchPadNotes([
        note('Shared note', sourceDeviceName: 'Workshop tablet', shared: true),
      ]),
    );

    expect(restored.single.sourceDeviceName, 'Workshop tablet');
  });

  testWidgets('groups shared notes by device and filters the note grid', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScratchPadDialog(
          notes: [note('Local note')],
          sharedNotes: [
            note(
              'Tablet note',
              sourceDeviceName: 'Workshop tablet',
              shared: true,
            ),
            note(
              'Desktop note',
              sourceDeviceName: 'Linux desktop',
              shared: true,
            ),
          ],
          localDeviceName: 'Linux desktop',
          buttonSurfaceBuilder: ({
            required states,
            required child,
            joined = false,
          }) => child,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Local Notes'), findsOneWidget);
    expect(find.textContaining('Saved on this device first'), findsNothing);
    expect(find.byKey(const Key('scratch-pad-view-controls')), findsOneWidget);
    expect(find.byKey(const Key('scratch-pad-device-filters')), findsOneWidget);
    expect(find.byTooltip('Full-cover grid'), findsOneWidget);
    expect(find.byTooltip('Two-column grid'), findsOneWidget);
    expect(find.byTooltip('One-column strip'), findsOneWidget);
    expect(find.byTooltip('Horizontal note strip'), findsOneWidget);

    await tester.tap(find.byTooltip('Horizontal note strip'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('scratch-pad-horizontal-strip')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('scratch-pad-timeline-local')), findsOneWidget);
    expect(
      find.byKey(const Key('scratch-pad-timeline-Linux desktop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('scratch-pad-timeline-Workshop tablet')),
      findsOneWidget,
    );

    await tester.drag(
      find.byKey(const Key('scratch-pad-device-filters')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('scratch-pad-filter-Workshop tablet')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shared from Workshop tablet'), findsOneWidget);
    expect(find.text('Tablet note'), findsOneWidget);
    expect(find.text('Desktop note'), findsNothing);
    expect(find.text('Local note'), findsNothing);
    expect(find.byKey(const Key('scratch-pad-timeline-local')), findsNothing);
    expect(
      find.byKey(const Key('scratch-pad-timeline-Linux desktop')),
      findsNothing,
    );
  });
}
