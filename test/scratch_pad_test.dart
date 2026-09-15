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

  testWidgets('fenced code follows the active theme palette', (tester) async {
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
    final colors = Theme.of(context).colorScheme;
    expect(
      spans.any(
        (span) => span.text == 'if' && span.style?.color == colors.primary,
      ),
      isTrue,
    );
    expect(
      spans.any(
        (span) => span.text == 'Then' && span.style?.color == colors.secondary,
      ),
      isTrue,
    );
    expect(
      spans.any(
        (span) =>
            span.style?.backgroundColor ==
            Color.alphaBlend(
              colors.primary.withValues(alpha: .16),
              colors.surfaceContainerHigh,
            ),
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

  test(
    'image previews reserve their configured height without changing source',
    () {
      const source = 'Keep\n![Cone](https://example.com/cone.png)\nRemove me';
      final controller = MarkdownEditingController(text: source)
        ..selection = TextSelection.collapsed(offset: 0);

      expect(controller.text, contains('\u200B\n'));
      expect(controller.sourceText, source);
      final removed = controller.text.replaceFirst('Remove me', '');
      controller.value = controller.value.copyWith(
        text: removed,
        selection: TextSelection.collapsed(offset: removed.length),
        composing: TextRange.empty,
      );
      controller.updateFocusedLineFromSelection();

      expect(controller.text, contains('\u200B\n'));
      expect(controller.sourceText, source.replaceFirst('Remove me', ''));
      expect(controller.selection.extentOffset, removed.length);
      controller.dispose();
    },
  );

  test('moving the selection onto an image activates its source line', () {
    const image = '![Cone](https://example.com/cone.png)';
    final controller = MarkdownEditingController(text: 'Before\n$image\nAfter')
      ..focusedLine = 2;

    controller.selection = const TextSelection.collapsed(offset: 9);

    expect(controller.focusedLine, 1);
    controller.dispose();
  });

  test('tapping a preview reveals its existing Markdown source', () {
    const image = '![Cone](https://example.com/cone.png)';
    final controller = MarkdownEditingController(text: 'Before\n$image\nAfter');

    controller.revealImage('https://example.com/cone.png');

    expect(controller.focusedLine, 1);
    expect(controller.selection.extentOffset, controller.text.indexOf(image));
    expect(controller.sourceText, 'Before\n$image\nAfter');
    controller.dispose();
  });

  test('one Return after an image moves to the next source line', () {
    const image = '![Cone](https://example.com/cone.png)';
    final controller = MarkdownEditingController(text: '$image\nAfter');
    controller.revealImage('https://example.com/cone.png');
    final imageEnd = controller.text.indexOf(image) + image.length;

    controller.value = controller.value.copyWith(
      text:
          '${controller.text.substring(0, imageEnd)}\n${controller.text.substring(imageEnd)}',
      selection: TextSelection.collapsed(offset: imageEnd + 1),
      composing: TextRange.empty,
    );

    expect(controller.sourceText, '$image\n\nAfter');
    expect(controller.focusedLine, 1);
    expect(
      controller.selection.extentOffset,
      controller.text.indexOf('\n\nAfter') + 1,
    );
    controller.dispose();
  });

  test('caret skips every virtual line reserved for an image preview', () {
    const image = '![Cone](https://example.com/cone.png)';
    final controller = MarkdownEditingController(text: '$image\nAfter');
    final imageEnd = controller.text.indexOf(image) + image.length;
    final nextLine = controller.text.indexOf('\nAfter') + 1;

    for (var offset = imageEnd + 1; offset < nextLine; offset++) {
      controller.selection = TextSelection.collapsed(offset: offset);
      expect(controller.selection.extentOffset, nextLine);
    }

    controller.value = controller.value.copyWith(
      text:
          '${controller.text.substring(0, nextLine)}a${controller.text.substring(nextLine)}',
      selection: TextSelection.collapsed(offset: nextLine + 1),
      composing: TextRange.empty,
    );
    expect(controller.sourceText, '$image\naAfter');
    controller.dispose();
  });

  test('vertical navigation treats an image preview as one block', () {
    const image = '![Cone](https://example.com/cone.png)';
    final controller = MarkdownEditingController(text: '$image\nAfter');
    controller.revealImage('https://example.com/cone.png');

    expect(controller.movePastImage(down: true), isTrue);
    expect(controller.focusedLine, 1);
    expect(controller.selection.extentOffset, controller.text.indexOf('After'));
    expect(controller.movePastImage(down: false), isTrue);
    expect(controller.focusedLine, 0);
    controller.dispose();
  });

  testWidgets('an image previews while its next line is being edited', (
    tester,
  ) async {
    const image = '![Cone](https://example.com/cone.png)';
    const source = 'Before\n$image\nAfter';
    final controller = MarkdownEditingController(text: source)..focusedLine = 0;
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
    expect(span.toPlainText(), isNot(contains(image)));
    controller.dispose();
  });

  testWidgets('source-mode editors keep image Markdown as an ordinary line', (
    tester,
  ) async {
    const image = '![Cone](https://example.com/cone.png)';
    final controller = MarkdownEditingController(
      text: 'Before\n$image\nAfter',
      renderImages: false,
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
    expect(span.toPlainText(), contains(image));
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
