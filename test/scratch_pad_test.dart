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

  test('Scratch Pad encoding preserves explicit workspace sharing', () {
    final note = ScratchPadNote(
      id: 'shared-note',
      title: 'Shared note',
      body: 'Visible to the workshop',
      updatedAt: DateTime.utc(2026, 9, 12),
      isShared: true,
    );

    expect(
      decodeScratchPadNotes(encodeScratchPadNotes([note])).single.isShared,
      isTrue,
    );
  });

  test('malformed local Scratch Pad data safely reads as an empty list', () {
    expect(decodeScratchPadNotes('{not-json'), isEmpty);
  });

  test('Markdown source is not rewritten before editing', () {
    const source = '> quote\nprint("not quoted")';
    expect(scratchPadRenderMarkdown(source), source);
  });

  testWidgets('unfocused blockquotes render with a quote rail', (tester) async {
    final controller = MarkdownEditingController(
      text: '> Quoted text\n> Continues here',
    );
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    final span = controller.buildTextSpan(
      context: context,
      style: const TextStyle(),
      withComposing: false,
    );
    expect(span.toPlainText(), contains('▌ Quoted text\n▌ Continues here'));
    controller.dispose();
  });

  testWidgets('an unprefixed line terminates a blockquote', (tester) async {
    final controller = MarkdownEditingController(
      text: '> Quoted text\n~~~dart\nfinal value = 1;\n~~~',
    );
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    final span = controller.buildTextSpan(
      context: context,
      style: const TextStyle(),
      withComposing: false,
    );
    expect(span.toPlainText(), contains('▌ Quoted text\n~~~dart'));
    expect(span.toPlainText(), isNot(contains('▌ ~~~dart')));
    controller.dispose();
  });

  testWidgets('escaped Markdown markers stay literal', (tester) async {
    final controller = MarkdownEditingController(
      text: r'\*literal asterisks\*',
    );
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    final span = controller.buildTextSpan(
      context: context,
      style: const TextStyle(),
      withComposing: false,
    );
    final escapedSlash = _textSpans(span)
        .firstWhere((candidate) => candidate.text == r'\');
    expect(escapedSlash.style?.fontSize, 0);
    expect(
      _textSpans(span)
          .where((candidate) => candidate.text == 'literal asterisks')
          .single
          .style
          ?.fontStyle,
      isNot(FontStyle.italic),
    );
    controller.dispose();
  });

  testWidgets('a cursor inside a tilde fenced block reveals both fences', (
    tester,
  ) async {
    const source = '~~~dart\nfinal value = 1;\n~~~';
    final controller = MarkdownEditingController(text: source)
      ..selection = const TextSelection.collapsed(offset: 10)
      ..updateFocusedLineFromSelection();
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    final span = controller.buildTextSpan(
      context: context,
      style: const TextStyle(),
      withComposing: false,
    );
    final fences = _textSpans(span)
        .where((candidate) => candidate.text?.startsWith('~~~') == true)
        .toList();
    expect(fences, hasLength(2));
    expect(fences.every((candidate) => candidate.style?.fontSize != 0), isTrue);
    controller.dispose();
  });

  testWidgets('fenced code uses the dark workshop palette', (tester) async {
    final controller = MarkdownEditingController(
      text: '~~~dart\nif (this) Then(42);\n~~~',
    );
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    final spans = _textSpans(
      controller.buildTextSpan(
        context: context,
        style: const TextStyle(),
        withComposing: false,
      ),
    ).toList();
    expect(
      spans.any(
        (span) =>
            span.text == 'if' && span.style?.color == const Color(0xFF71C7EC),
      ),
      isTrue,
    );
    expect(
      spans.any(
        (span) =>
            span.text == 'Then' && span.style?.color == const Color(0xFFE6C27A),
      ),
      isTrue,
    );
    expect(
      spans.any(
        (span) => span.style?.backgroundColor == const Color(0xFF21142F),
      ),
      isTrue,
    );
    controller.dispose();
  });

  testWidgets('unfocused task lists render checked and unchecked boxes', (
    tester,
  ) async {
    final controller = MarkdownEditingController(
      text: '- [ ] Still open\n- [x] Finished',
    );
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    final span = controller.buildTextSpan(
      context: context,
      style: const TextStyle(),
      withComposing: false,
    );
    final visible = _textSpans(span)
        .map((candidate) => candidate.text)
        .whereType<String>()
        .join();
    expect(visible, contains('☐ '));
    expect(visible, contains('☒ '));
    expect(visible.length, '- [ ] Still open\n- [x] Finished'.length);
    controller.dispose();
  });

  testWidgets('focused task lists keep their raw marker on the same line', (
    tester,
  ) async {
    final controller = MarkdownEditingController(text: '- [ ] Do this')
      ..focusedLine = 0;
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    final visible = _textSpans(
      controller.buildTextSpan(
        context: context,
        style: const TextStyle(),
        withComposing: false,
      ),
    ).map((candidate) => candidate.text).whereType<String>().join();
    expect(visible, contains('- [ ] Do this'));
    expect(visible, isNot(contains('☐')));
    controller.dispose();
  });

  test('typing Markdown markers preserves the caret offset', () {
    final controller = MarkdownEditingController()
      ..selection = const TextSelection.collapsed(offset: 0);
    const source = '''Inline `code`
~~~dart
final answer = 42;
~~~
\\*literal asterisks\\*
- [ ] Task
> Quote
Plain text''';

    for (final rune in source.runes) {
      final character = String.fromCharCode(rune);
      final value = controller.value;
      final offset = value.selection.extentOffset;
      controller.value = value.copyWith(
        text:
            '${value.text.substring(0, offset)}$character${value.text.substring(offset)}',
        selection: TextSelection.collapsed(offset: offset + character.length),
        composing: TextRange.empty,
      );
      controller.updateFocusedLineFromSelection();
      expect(controller.selection.extentOffset, offset + character.length);
    }

    expect(controller.sourceText, source);
    expect(controller.selection.extentOffset, source.length);
    controller.dispose();
  });

  test('image previews never inject source characters while editing', () {
    const source = 'Keep\n![Cone](https://example.com/cone.png)\nRemove me';
    final controller = MarkdownEditingController(text: source)
      ..selection = TextSelection.collapsed(offset: source.length);

    expect(controller.text, source);
    final removed = source.replaceFirst('Remove me', '');
    controller.value = controller.value.copyWith(
      text: removed,
      selection: TextSelection.collapsed(offset: removed.length),
      composing: TextRange.empty,
    );
    controller.updateFocusedLineFromSelection();

    expect(controller.text, removed);
    expect(controller.sourceText, removed);
    expect(controller.selection.extentOffset, removed.length);
    controller.dispose();
  });

  test('pressing return continues a numbered list', () {
    final controller = MarkdownEditingController(text: '1. First item')
      ..selection = const TextSelection.collapsed(offset: 13);
    controller.value = controller.value.copyWith(
      text: '1. First item\n',
      selection: const TextSelection.collapsed(offset: 14),
      composing: TextRange.empty,
    );

    expect(controller.sourceText, '1. First item\n2. ');
    expect(controller.selection.extentOffset, 17);
    controller.dispose();
  });
}

Iterable<TextSpan> _textSpans(InlineSpan span) sync* {
  if (span case TextSpan textSpan) {
    yield textSpan;
    for (final child in textSpan.children ?? const <InlineSpan>[]) {
      yield* _textSpans(child);
    }
  }
}
