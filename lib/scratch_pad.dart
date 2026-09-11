import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:markdown_editor_live/markdown_editor_live.dart';

const scratchPadNotesPreferenceKey = 'scratch_pad_notes_v1';

String scratchPadRenderMarkdown(String source) {
  final rendered = <String>[];
  var continuingQuote = false;
  for (final line in source.split('\n')) {
    if (line.trim().isEmpty) {
      continuingQuote = false;
      rendered.add(line);
    } else if (line.trimLeft().startsWith('>')) {
      continuingQuote = true;
      rendered.add(line);
    } else if (continuingQuote) {
      rendered.add('> $line');
    } else {
      rendered.add(line);
    }
  }
  return rendered.join('\n');
}


class ScratchPadNote {
  const ScratchPadNote({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;

  ScratchPadNote copyWith({String? title, String? body, DateTime? updatedAt}) =>
      ScratchPadNote(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory ScratchPadNote.fromJson(Map<String, dynamic> json) => ScratchPadNote(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Untitled note',
    body: json['body'] as String? ?? '',
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );

  factory ScratchPadNote.fromRemoteJson(Map<String, dynamic> json) =>
      ScratchPadNote(
        id: json['note_id'] as String,
        title: json['title'] as String? ?? 'Untitled note',
        body: json['body'] as String? ?? '',
        updatedAt:
            DateTime.tryParse(json['updated_at'] as String? ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}

List<ScratchPadNote> decodeScratchPadNotes(String raw) {
  try {
    final notes = (jsonDecode(raw) as List)
        .whereType<Map>()
        .map((row) => ScratchPadNote.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  } catch (_) {
    return const [];
  }
}

String encodeScratchPadNotes(Iterable<ScratchPadNote> notes) {
  final ordered = notes.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return jsonEncode(ordered.map((note) => note.toJson()).toList());
}

class ScratchPadDialog extends StatefulWidget {
  const ScratchPadDialog({
    super.key,
    required this.notes,
    required this.onChanged,
    this.reviewNotes = const [],
    this.backupMessage,
  });

  final List<ScratchPadNote> notes;
  final ValueChanged<List<ScratchPadNote>> onChanged;
  final List<ScratchPadNote> reviewNotes;
  final String? backupMessage;

  @override
  State<ScratchPadDialog> createState() => _ScratchPadDialogState();
}

class _ScratchPadDialogState extends State<ScratchPadDialog> {
  late List<ScratchPadNote> notes;

  @override
  void initState() {
    super.initState();
    notes = [...widget.notes];
  }

  void _persist() {
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    widget.onChanged(List<ScratchPadNote>.unmodifiable(notes));
  }

  Future<void> _edit([ScratchPadNote? note]) async {
    final saved = await showDialog<ScratchPadNote>(
      context: context,
      builder: (_) => _ScratchPadEditor(note: note),
    );
    if (saved == null || !mounted) return;
    setState(() {
      final index = notes.indexWhere((value) => value.id == saved.id);
      if (index < 0) {
        notes.add(saved);
      } else {
        notes[index] = saved;
      }
      _persist();
    });
  }

  Future<void> _delete(ScratchPadNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text(
          '“${note.title}” will be removed from this device and its next remote backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      notes.removeWhere((value) => value.id == note.id);
      _persist();
    });
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Scratch Pad'),
        actions: [
          IconButton(
            key: const Key('add-scratch-pad-note'),
            tooltip: 'Add note',
            onPressed: _edit,
            icon: const Icon(Icons.note_add_outlined),
          ),
          IconButton(
            tooltip: 'Close Scratch Pad',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: const Text('Add note'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = (constraints.maxWidth - 32).clamp(0.0, 1180.0);
          final columns = contentWidth >= 720 ? 2 : 1;
          return Center(
          child: SizedBox(
            width: contentWidth,
            child: ListView(
              key: const Key('scratch-pad-note-list'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
              children: [
          Text(
            'Saved on this device first. Remote Sync backs up these notes when available.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (widget.backupMessage case final message?) ...[
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 14),
          if (notes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: Text('No work notes yet.')),
            ),
          if (notes.isNotEmpty) _noteGrid(notes, columns: columns, editable: true),
          if (widget.reviewNotes.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Notes from removed devices',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _noteGrid(widget.reviewNotes, columns: columns, editable: false),
          ],
              ],
            ),
          ),
        );
        },
      ),
    ),
  );

  Widget _noteGrid(List<ScratchPadNote> source, {required int columns, required bool editable}) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: source.length,
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: columns == 1 ? 1.7 : 1.45,
    ),
    itemBuilder: (context, index) => _noteTile(source[index], editable: editable),
  );

  Widget _noteTile(ScratchPadNote note, {required bool editable}) => Card(
    key: Key('scratch-pad-note-${note.id}'),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: editable ? () => _edit(note) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(note.title, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (editable)
                  IconButton(tooltip: 'Delete note', onPressed: () => _delete(note), icon: const Icon(Icons.delete_outline))
                else
                  const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.history_rounded)),
              ],
            ),
            const Divider(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: _ScratchPadMarkdownPreview(
                  markdown: note.body.isEmpty ? '_Empty note_' : note.body,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ScratchPadMarkdownPreview extends StatefulWidget {
  const _ScratchPadMarkdownPreview({required this.markdown});

  final String markdown;

  @override
  State<_ScratchPadMarkdownPreview> createState() =>
      _ScratchPadMarkdownPreviewState();
}

class _ScratchPadMarkdownPreviewState extends State<_ScratchPadMarkdownPreview> {
  late final MarkdownEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = MarkdownEditingController(
      text: scratchPadRenderMarkdown(widget.markdown),
      imageHeightLines: 5,
    );
  }

  @override
  void didUpdateWidget(covariant _ScratchPadMarkdownPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdown != widget.markdown) {
      controller.text = scratchPadRenderMarkdown(widget.markdown);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: TextField(
      controller: controller,
      readOnly: true,
      showCursor: false,
      enableInteractiveSelection: false,
      minLines: 1,
      maxLines: null,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: const InputDecoration.collapsed(hintText: ''),
    ),
  );
}

class _ScratchPadEditor extends StatefulWidget {
  const _ScratchPadEditor({this.note});
  final ScratchPadNote? note;
  @override
  State<_ScratchPadEditor> createState() => _ScratchPadEditorState();
}

class _ScratchPadEditorState extends State<_ScratchPadEditor> {
  late final title = TextEditingController(text: widget.note?.title ?? '');
  late final body = MarkdownEditingController(
    text: scratchPadRenderMarkdown(widget.note?.body ?? ''),
    imageHeightLines: 5,
  );
  late final bodyFocus = FocusNode()..addListener(_handleMarkdownFocus);

  void _handleMarkdownFocus() {
    if (!bodyFocus.hasFocus) {
      body.focusedLine = null;
    }
  }

  void _revealMarkdownAtCursor([String? _]) => body.updateFocusedLineFromSelection();

  @override
  void dispose() {
    bodyFocus
      ..removeListener(_handleMarkdownFocus)
      ..dispose();
    title.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final editorHeight = (screen.height - 260).clamp(220.0, 520.0).toDouble();
    return AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    constraints: const BoxConstraints(maxWidth: 960),
    title: Text(widget.note == null ? 'New note' : 'Edit note'),
    content: SizedBox(
      width: 860,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: title,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: editorHeight,
            child: TextField(
              controller: body,
              focusNode: bodyFocus,
              onTap: _revealMarkdownAtCursor,
              onChanged: _revealMarkdownAtCursor,
              expands: true,
              minLines: null,
              maxLines: null,
              maxLength: 12000,
              autofocus: widget.note == null,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              style: Theme.of(context).textTheme.bodyLarge,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'Write Markdown…',
              alignLabelWithHint: true,
            ),
          ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final text = body.text.trim();
          if (text.isEmpty) return;
          Navigator.pop(
            context,
            ScratchPadNote(
              id:
                  widget.note?.id ??
                  'note-${DateTime.now().microsecondsSinceEpoch}',
              title: title.text.trim().isEmpty
                  ? 'Untitled note'
                  : title.text.trim(),
              body: text,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
  }
}
