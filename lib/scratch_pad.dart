import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:markdown_editor_live/markdown_editor_live.dart';

const scratchPadNotesPreferenceKey = 'scratch_pad_notes_v1';

String scratchPadRenderMarkdown(String source) => source;

class ScratchPadSubject {
  const ScratchPadSubject({
    required this.kind,
    required this.id,
    required this.label,
  });

  final String kind;
  final String id;
  final String label;
}

class ScratchPadNote {
  const ScratchPadNote({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
    this.isShared = false,
    this.sourceDeviceName,
    this.subjectKind,
    this.subjectId,
    this.subjectLabel,
  });

  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;
  final bool isShared;
  final String? sourceDeviceName;
  final String? subjectKind;
  final String? subjectId;
  final String? subjectLabel;

  ScratchPadSubject? get subject =>
      subjectKind == null || subjectId == null || subjectLabel == null
      ? null
      : ScratchPadSubject(
          kind: subjectKind!,
          id: subjectId!,
          label: subjectLabel!,
        );

  ScratchPadNote copyWith({
    String? title,
    String? body,
    DateTime? updatedAt,
    bool? isShared,
    ScratchPadSubject? subject,
  }) => ScratchPadNote(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    updatedAt: updatedAt ?? this.updatedAt,
    isShared: isShared ?? this.isShared,
    sourceDeviceName: sourceDeviceName,
    subjectKind: subject?.kind ?? subjectKind,
    subjectId: subject?.id ?? subjectId,
    subjectLabel: subject?.label ?? subjectLabel,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'isShared': isShared,
    if (subject != null) 'subjectKind': subject!.kind,
    if (subject != null) 'subjectId': subject!.id,
    if (subject != null) 'subjectLabel': subject!.label,
  };

  factory ScratchPadNote.fromJson(Map<String, dynamic> json) => ScratchPadNote(
    id: json['id'] as String,
    title: json['title'] as String? ?? 'Untitled note',
    body: json['body'] as String? ?? '',
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    isShared: json['isShared'] == true,
    subjectKind: json['subjectKind'] as String?,
    subjectId: json['subjectId'] as String?,
    subjectLabel: json['subjectLabel'] as String?,
  );

  factory ScratchPadNote.fromRemoteJson(Map<String, dynamic> json) =>
      ScratchPadNote(
        id: json['note_id'] as String,
        title: json['title'] as String? ?? 'Untitled note',
        body: json['body'] as String? ?? '',
        updatedAt:
            DateTime.tryParse(json['updated_at'] as String? ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        isShared: json['is_shared'] == true,
        sourceDeviceName: json['source_device_name'] as String?,
        subjectKind: json['subject_kind'] as String?,
        subjectId: json['subject_id'] as String?,
        subjectLabel: json['subject_label'] as String?,
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
    this.sharedNotes = const [],
    this.reviewNotes = const [],
    this.backupMessage,
    this.subjects = const [],
  });

  final List<ScratchPadNote> notes;
  final ValueChanged<List<ScratchPadNote>> onChanged;
  final List<ScratchPadNote> sharedNotes;
  final List<ScratchPadNote> reviewNotes;
  final String? backupMessage;
  final List<ScratchPadSubject> subjects;

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
      builder: (_) => _ScratchPadEditor(note: note, subjects: widget.subjects),
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

  Future<void> _viewSharedNote(ScratchPadNote note) => showDialog<void>(
    context: context,
    builder: (_) => _ScratchPadReadOnlyNote(note: note),
  );

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Scratch Pad'),
        actions: [
          IconButton(
            tooltip: 'Close Scratch Pad',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.note_add_outlined),
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (notes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(child: Text('No work notes yet.')),
                    ),
                  if (notes.isNotEmpty)
                    _noteGrid(notes, columns: columns, editable: true),
                  if (widget.sharedNotes.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Shared with workspace',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _noteGrid(
                      widget.sharedNotes,
                      columns: columns,
                      editable: false,
                    ),
                  ],
                  if (widget.reviewNotes.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Notes from removed devices',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _noteGrid(
                      widget.reviewNotes,
                      columns: columns,
                      editable: false,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _noteGrid(
    List<ScratchPadNote> source, {
    required int columns,
    required bool editable,
  }) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: source.length,
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: columns == 1 ? 1.7 : 1.45,
    ),
    itemBuilder: (context, index) =>
        _noteTile(source[index], editable: editable),
  );

  Widget _noteTile(ScratchPadNote note, {required bool editable}) => Card(
    key: Key('scratch-pad-note-${note.id}'),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: InkWell(
      onTap: () => editable ? _edit(note) : _viewSharedNote(note),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (note.isShared)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.people_outline, size: 18),
                  ),
                if (editable)
                  IconButton(
                    tooltip: 'Delete note',
                    onPressed: () => _delete(note),
                    icon: const Icon(Icons.delete_outline),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      note.sourceDeviceName == null
                          ? Icons.people_outline
                          : Icons.devices_other_outlined,
                    ),
                  ),
              ],
            ),
            const Divider(height: 12),
            if (note.subject case final subject?) ...[
              _ScratchPadSubjectChip(subject: subject),
              const SizedBox(height: 8),
            ],
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

class _ScratchPadReadOnlyNote extends StatelessWidget {
  const _ScratchPadReadOnlyNote({required this.note});
  final ScratchPadNote note;

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(note.title),
        actions: [
          IconButton(
            tooltip: 'Close note',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
              children: [
                if (note.subject case final subject?) ...[
                  _ScratchPadSubjectChip(subject: subject),
                  const SizedBox(height: 18),
                ],
                _ScratchPadMarkdownPreview(
                  markdown: note.body.isEmpty ? '_Empty note_' : note.body,
                ),
              ],
            ),
          ),
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

class _ScratchPadSubjectChip extends StatelessWidget {
  const _ScratchPadSubjectChip({required this.subject});
  final ScratchPadSubject subject;

  IconData get _icon => switch (subject.kind) {
    'Item' => Icons.inventory_2_outlined,
    'Location' => Icons.warehouse_outlined,
    'Brand' => Icons.sell_outlined,
    'Vendor' => Icons.storefront_outlined,
    'Material' => Icons.category_outlined,
    'Machine' => Icons.precision_manufacturing_outlined,
    'Kit' => Icons.inventory_2_outlined,
    'Build' => Icons.construction_outlined,
    _ => Icons.link_outlined,
  };

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(_icon, size: 16),
    label: Text(
      '${subject.kind} · ${subject.label}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    visualDensity: VisualDensity.compact,
  );
}

class _ScratchPadMarkdownPreviewState
    extends State<_ScratchPadMarkdownPreview> {
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
  const _ScratchPadEditor({this.note, this.subjects = const []});
  final ScratchPadNote? note;
  final List<ScratchPadSubject> subjects;
  @override
  State<_ScratchPadEditor> createState() => _ScratchPadEditorState();
}

class _ScratchPadEditorState extends State<_ScratchPadEditor> {
  bool fullscreen = false;
  late final title = TextEditingController(text: widget.note?.title ?? '');
  late final body = MarkdownEditingController(
    text: scratchPadRenderMarkdown(widget.note?.body ?? ''),
    imageHeightLines: 5,
  );
  late final bodyFocus = FocusNode()..addListener(_handleMarkdownFocus);
  late bool isShared = widget.note?.isShared ?? false;
  late ScratchPadSubject? subject = widget.note?.subject;

  @override
  void initState() {
    super.initState();
    body.addListener(_revealMarkdownAtCursor);
  }

  void _handleMarkdownFocus() {
    if (!bodyFocus.hasFocus) {
      body.focusedLine = null;
    } else {
      body.updateFocusedLineFromSelection();
    }
  }

  void _revealMarkdownAtCursor([String? _]) =>
      body.updateFocusedLineFromSelection();

  Future<void> _pickSubject() async {
    var query = '';
    final selected = await showDialog<ScratchPadSubject?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final needle = query.trim().toLowerCase();
          final matches = widget.subjects
              .where(
                (entry) =>
                    needle.isEmpty ||
                    '${entry.kind} ${entry.label}'.toLowerCase().contains(
                      needle,
                    ),
              )
              .toList();
          return AlertDialog(
            title: const Text('What is this note about?'),
            content: SizedBox(
              width: 520,
              height: 460,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search items, locations, brands, vendors…',
                    ),
                    onChanged: (value) => setDialogState(() => query = value),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: matches.isEmpty
                        ? const Center(child: Text('No matching records.'))
                        : ListView.builder(
                            itemCount: matches.length,
                            itemBuilder: (context, index) {
                              final entry = matches[index];
                              return ListTile(
                                leading: const Icon(Icons.link_outlined),
                                title: Text(entry.label),
                                subtitle: Text(entry.kind),
                                onTap: () =>
                                    Navigator.pop(dialogContext, entry),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              if (subject != null)
                TextButton(
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    const ScratchPadSubject(kind: '', id: '', label: ''),
                  ),
                  child: const Text('Clear link'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => subject = selected.kind.isEmpty ? null : selected);
  }

  @override
  void dispose() {
    body.removeListener(_revealMarkdownAtCursor);
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
    final dialogHeight = fullscreen
        ? screen.height
        : (screen.height - 48).clamp(420.0, 760.0).toDouble();
    return Dialog(
      insetPadding: fullscreen
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: fullscreen
            ? const BoxConstraints()
            : const BoxConstraints(maxWidth: 960),
        child: SizedBox(
          width: fullscreen ? screen.width : 860,
          height: dialogHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.note == null ? 'New note' : 'Edit note',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: fullscreen ? 'Exit full screen' : 'Full screen',
                      onPressed: () => setState(() => fullscreen = !fullscreen),
                      icon: _ScratchPadFullscreenIcon(expanded: fullscreen),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: title,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Share with workspace'),
                  value: isShared,
                  onChanged: (value) => setState(() => isShared = value),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link_outlined),
                  title: const Text('About'),
                  subtitle: subject == null
                      ? const Text('Not linked to a workshop record')
                      : _ScratchPadSubjectChip(subject: subject!),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _pickSubject,
                ),
                const SizedBox(height: 8),
                Expanded(
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
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
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
                              isShared: isShared,
                              subjectKind: subject?.kind,
                              subjectId: subject?.id,
                              subjectLabel: subject?.label,
                            ),
                          );
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScratchPadFullscreenIcon extends StatelessWidget {
  const _ScratchPadFullscreenIcon({required this.expanded});
  final bool expanded;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 22,
    child: CustomPaint(
      painter: _ScratchPadFullscreenPainter(
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface,
        expanded,
      ),
    ),
  );
}

class _ScratchPadFullscreenPainter extends CustomPainter {
  const _ScratchPadFullscreenPainter(this.color, this.expanded);
  final Color color;
  final bool expanded;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final d = expanded ? 6.0 : 2.5;
    final e = expanded ? 2.5 : 6.0;
    for (final (origin, x, y) in [
      (Offset(d, d), 1.0, 1.0),
      (Offset(size.width - d, d), -1.0, 1.0),
      (Offset(d, size.height - d), 1.0, -1.0),
      (Offset(size.width - d, size.height - d), -1.0, -1.0),
    ]) {
      canvas.drawLine(origin, Offset(origin.dx + (x * e), origin.dy), pen);
      canvas.drawLine(origin, Offset(origin.dx, origin.dy + (y * e)), pen);
    }
  }

  @override
  bool shouldRepaint(_ScratchPadFullscreenPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.expanded != expanded;
}
