import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/scratch_pad.dart';
import 'package:markdown_editor_live/markdown_editor_live.dart';

void main() {
  test('Scratch Pad encoding preserves a device-local newest-first list', () {
    final older = ScratchPadNote(
      id: 'older',
      title: 'Older',
      body: 'First note',
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final newer = ScratchPadNote(
      id: 'newer',
      title: 'Newer',
      body: 'Second note',
      updatedAt: DateTime.utc(2026, 1, 2),
    );

    final encoded = encodeScratchPadNotes([older, newer]);
    expect((jsonDecode(encoded) as List).first['id'], 'newer');
    expect(decodeScratchPadNotes(encoded).map((note) => note.id), [
      'newer',
      'older',
    ]);
  });

  test('malformed local Scratch Pad data safely reads as an empty list', () {
    expect(decodeScratchPadNotes('{not-json'), isEmpty);
  });

  testWidgets('unfocused blockquotes render with a quote rail', (tester) async {
    final controller = MarkdownEditingController(text: '> Quoted text\nContinues here');
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      })),
    );

    final span = controller.buildTextSpan(
      context: context,
      style: const TextStyle(),
      withComposing: false,
    );
    expect(span.toPlainText(), contains('▌ Quoted text\n▌ Continues here'));
    controller.dispose();
  });
}
