import 'dart:convert';
import 'dart:ui' show ImageFilter, PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_editor_live/markdown_editor_live.dart';

const scratchPadNotesPreferenceKey = 'scratch_pad_notes_v1';

Map<String, int> decodeScratchPadOwnerRevisions(String raw) {
  try {
    return (jsonDecode(raw) as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, (value as num).toInt()),
    );
  } catch (_) {
    return {};
  }
}

String scratchPadRenderMarkdown(String source) => source;

enum _ScratchPadViewMode { cover, twoColumn, oneColumn, horizontal }

typedef ScratchPadButtonSurfaceBuilder = Widget Function({
  required Set<WidgetState> states,
  required Widget child,
  bool joined,
});

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
    this.sourceUserId,
    this.ownerRevision = 0,
    this.ownerDeleted = false,
    this.isArchived = false,
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
  final String? sourceUserId;
  final int ownerRevision;
  final bool ownerDeleted;
  final bool isArchived;
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
    sourceUserId: sourceUserId,
    ownerRevision: ownerRevision,
    ownerDeleted: ownerDeleted,
    isArchived: isArchived,
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
    'ownerRevision': ownerRevision,
    'ownerDeleted': ownerDeleted,
    'isArchived': isArchived,
    if (sourceDeviceName != null) 'sourceDeviceName': sourceDeviceName,
    if (sourceUserId != null) 'sourceUserId': sourceUserId,
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
    sourceDeviceName: json['sourceDeviceName'] as String?,
    sourceUserId: json['sourceUserId'] as String?,
    ownerRevision: (json['ownerRevision'] as num?)?.toInt() ?? 0,
    ownerDeleted: json['ownerDeleted'] == true,
    isArchived: json['isArchived'] == true,
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
        sourceUserId: json['source_user_id'] as String?,
        ownerRevision: (json['owner_revision'] as num?)?.toInt() ?? 0,
        ownerDeleted: json['owner_deleted'] == true,
        isArchived: json['transferred_at'] != null,
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

// Recovery is additive. A differing local revision stays under its original ID;
// retain the recovered revision separately rather than silently overwriting it.
List<ScratchPadNote> mergeRecoveredScratchPadNotes(
  List<ScratchPadNote> local,
  List<ScratchPadNote> recovered, {
  Map<String, int>? ownerRevisions,
}) {
  final result = {for (final note in local) note.id: note};
  for (final note in recovered) {
    final existing = result[note.id];
    if (note.ownerRevision > 0) {
      final seen = ownerRevisions == null
          ? (existing?.ownerRevision ?? 0)
          : (ownerRevisions[note.id] ?? 0);
      ownerRevisions?[note.id] = note.ownerRevision > seen
          ? note.ownerRevision
          : seen;
      if (note.ownerDeleted) {
        result.remove(note.id);
        continue;
      }
      if ((existing != null &&
              existing.ownerRevision >= note.ownerRevision &&
              seen >= note.ownerRevision) ||
          (existing == null && seen >= note.ownerRevision)) {
        continue;
      }
      result[note.id] = ScratchPadNote(
        id: note.id,
        title: note.title,
        body: note.body,
        updatedAt: note.updatedAt,
        isShared: note.isShared,
        ownerRevision: note.ownerRevision,
        subjectKind: note.subjectKind,
        subjectId: note.subjectId,
        subjectLabel: note.subjectLabel,
      );
      continue;
    }
    var id = note.id;
    if (existing != null) {
      if (existing.title == note.title &&
          existing.body == note.body &&
          existing.isShared == note.isShared &&
          existing.subjectKind == note.subjectKind &&
          existing.subjectId == note.subjectId &&
          existing.subjectLabel == note.subjectLabel) {
        continue;
      }
      final prefix = id.length > 80 ? id.substring(0, 80) : id;
      id = '${prefix}_recovered_${note.updatedAt.microsecondsSinceEpoch}';
      if (result.containsKey(id)) continue;
    }
    result[id] = ScratchPadNote(
      id: id,
      title: note.title,
      body: note.body,
      updatedAt: note.updatedAt,
      isShared: note.isShared,
      subjectKind: note.subjectKind,
      subjectId: note.subjectId,
      subjectLabel: note.subjectLabel,
    );
  }
  return result.values.toList();
}

class ScratchPadDialog extends StatefulWidget {
  const ScratchPadDialog({
    super.key,
    required this.notes,
    required this.onChanged,
    this.sharedNotes = const [],
    this.reviewNotes = const [],
    this.backupMessage,
    this.onRestoreNote,
    this.onManageNote,
    this.reloadManagedNotes,
    this.subjects = const [],
    this.localDeviceName = 'This device',
    this.scrollbarThickness = 10,
    required this.buttonSurfaceBuilder,
  });

  final List<ScratchPadNote> Function()? reloadManagedNotes;
  final List<ScratchPadNote> notes;
  final ValueChanged<List<ScratchPadNote>> onChanged;
  final List<ScratchPadNote> sharedNotes;
  final List<ScratchPadNote> reviewNotes;
  final String? backupMessage;
  final Future<bool> Function(ScratchPadNote)? onRestoreNote;
  final Future<bool> Function(ScratchPadNote, ScratchPadNote?)? onManageNote;
  final List<ScratchPadSubject> subjects;
  final String localDeviceName;
  final double scrollbarThickness;
  final ScratchPadButtonSurfaceBuilder buttonSurfaceBuilder;

  @override
  State<ScratchPadDialog> createState() => _ScratchPadDialogState();
}

class _ScratchPadDialogState extends State<ScratchPadDialog> {
  late List<ScratchPadNote> notes;
  String? _deviceFilter;
  final Set<ScratchPadNote> _restoredNotes = {};
  List<ScratchPadNote>? _managedNotes;
  var _viewMode = _ScratchPadViewMode.twoColumn;

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

  Future<void> _manageNote(
    ScratchPadNote note,
    BuildContext noteContext, {
    required bool delete,
  }) async {
    ScratchPadNote? replacement;
    if (delete) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete note from its device?'),
          content: Text(
            'Delete “${note.title}”? The author’s device will remove it on its next sync.',
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
      if (confirmed != true) return;
    } else {
      replacement = await showDialog<ScratchPadNote>(
        context: context,
        builder: (_) => _ScratchPadEditor(
          note: note,
          subjects: widget.subjects,
          ownerEditing: true,
        ),
      );
      if (replacement == null) return;
    }
    if (await widget.onManageNote!(note, replacement) && mounted) {
      setState(() {
        _restoredNotes.add(note);
        _managedNotes = widget.reloadManagedNotes?.call();
      });
      if (noteContext.mounted) Navigator.pop(noteContext);
    }
  }

  Future<void> _viewSharedNote(ScratchPadNote note) => showDialog<void>(
    context: context,
    builder: (noteContext) => _ScratchPadReadOnlyNote(
      note: note,
      onOwnerEdit: widget.onManageNote != null && note.sourceUserId != null
          ? () => _manageNote(note, noteContext, delete: false)
          : null,
      onOwnerDelete: widget.onManageNote != null && note.sourceUserId != null
          ? () => _manageNote(note, noteContext, delete: true)
          : null,
      onRestore:
          (widget.reviewNotes.contains(note) || note.isArchived) &&
              note.sourceUserId != null &&
              widget.onRestoreNote != null
          ? () async {
              if (await widget.onRestoreNote!(note) && mounted) {
                setState(() => _restoredNotes.add(note));
                if (noteContext.mounted) Navigator.pop(noteContext);
              }
            }
          : null,
    ),
  );

  static const _localFilter = '__local__';

  String _remoteDeviceName(ScratchPadNote note) {
    final name = note.sourceDeviceName?.trim() ?? '';
    return name.isEmpty ? 'Another device' : name;
  }

  Map<String, List<ScratchPadNote>> _notesByRemoteDevice() {
    final byDevice = <String, List<ScratchPadNote>>{};
    for (final note
        in _managedNotes ?? [...widget.sharedNotes, ...widget.reviewNotes]) {
      if (_restoredNotes.contains(note)) continue;
      byDevice.putIfAbsent(_remoteDeviceName(note), () => []).add(note);
    }
    return byDevice;
  }

  Widget _deviceFilters(List<String> remoteDevices) => SingleChildScrollView(
    key: const Key('scratch-pad-device-filters'),
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        _ScratchPadJewelButton(
          key: const Key('scratch-pad-filter-all'),
          selected: _deviceFilter == null,
          onPressed: () => setState(() => _deviceFilter = null),
          icon: const Icon(Icons.done_rounded, size: 16),
          label: const Text('All devices'),
          surfaceBuilder: widget.buttonSurfaceBuilder,
        ),
        const SizedBox(width: 8),
        _ScratchPadJewelButton(
          key: const Key('scratch-pad-filter-local'),
          selected: _deviceFilter == _localFilter,
          onPressed: () => setState(() => _deviceFilter = _localFilter),
          icon: const Icon(Icons.devices_outlined, size: 16),
          label: Text(widget.localDeviceName),
          surfaceBuilder: widget.buttonSurfaceBuilder,
        ),
        for (final device in remoteDevices) ...[
          const SizedBox(width: 8),
          _ScratchPadJewelButton(
            key: Key('scratch-pad-filter-$device'),
            selected: _deviceFilter == device,
            onPressed: () => setState(() => _deviceFilter = device),
            icon: const Icon(Icons.devices_other_outlined, size: 16),
            label: Text(device),
            surfaceBuilder: widget.buttonSurfaceBuilder,
          ),
        ],
      ],
    ),
  );

  Widget _viewModeControls() => _ScratchPadPickleBar(
    key: const Key('scratch-pad-view-controls'),
    surfaceBuilder: widget.buttonSurfaceBuilder,
    items: [
      _ScratchPadPickleItem(
        icon: _layoutAssetIcon('assets/icons/scratch-pad-full-grid.png'),
        tooltip: 'Full-cover grid',
        selected: _viewMode == _ScratchPadViewMode.cover,
        onPressed: () => setState(() => _viewMode = _ScratchPadViewMode.cover),
      ),
      _ScratchPadPickleItem(
        icon: _layoutAssetIcon('assets/icons/scratch-pad-two-columns.png'),
        tooltip: 'Two-column grid',
        selected: _viewMode == _ScratchPadViewMode.twoColumn,
        onPressed: () =>
            setState(() => _viewMode = _ScratchPadViewMode.twoColumn),
      ),
      _ScratchPadPickleItem(
        icon: _layoutAssetIcon('assets/icons/scratch-pad-one-column.png'),
        tooltip: 'One-column strip',
        selected: _viewMode == _ScratchPadViewMode.oneColumn,
        onPressed: () =>
            setState(() => _viewMode = _ScratchPadViewMode.oneColumn),
      ),
      _ScratchPadPickleItem(
        icon: _layoutAssetIcon('assets/icons/scratch-pad-timeline.png'),
        tooltip: 'Horizontal note strip',
        selected: _viewMode == _ScratchPadViewMode.horizontal,
        onPressed: () =>
            setState(() => _viewMode = _ScratchPadViewMode.horizontal),
      ),
    ],
  );

  Widget _layoutAssetIcon(String asset) =>
      ImageIcon(AssetImage(asset), size: 20);

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      extendBody: true,
      appBar: AppBar(title: const Text('Scratch Pad')),
      bottomNavigationBar: _viewMode == _ScratchPadViewMode.horizontal
          ? null
          : _ScratchPadHoverActionStrip(
              onAddNote: _edit,
              surfaceBuilder: widget.buttonSurfaceBuilder,
            ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = (constraints.maxWidth - 32)
              .clamp(0.0, double.infinity)
              .toDouble();
          final (contentWidth, columns) = switch (_viewMode) {
            _ScratchPadViewMode.cover => (
              availableWidth,
              (availableWidth / 300).floor().clamp(1, 6),
            ),
            _ScratchPadViewMode.twoColumn => (
              availableWidth.clamp(0.0, 1180.0).toDouble(),
              availableWidth >= 720 ? 2 : 1,
            ),
            _ScratchPadViewMode.oneColumn => (
              availableWidth.clamp(0.0, 760.0).toDouble(),
              1,
            ),
            _ScratchPadViewMode.horizontal => (availableWidth, 1),
          };
          final remoteByDevice = _notesByRemoteDevice();
          final remoteDevices = remoteByDevice.keys.toList()..sort();
          final showLocal =
              _deviceFilter == null || _deviceFilter == _localFilter;
          final horizontalTimeline =
              _viewMode == _ScratchPadViewMode.horizontal;
          final controls = Align(
            alignment: Alignment.centerRight,
            child: _viewModeControls(),
          );
          final sectionHeader = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Local Notes',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              _deviceFilters(remoteDevices),
              if (widget.backupMessage case final message?) ...[
                const SizedBox(height: 6),
                Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          );
          if (horizontalTimeline) {
            return Center(
              child: SizedBox(
                width: contentWidth,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      controls,
                      const SizedBox(height: 6),
                      sectionHeader,
                      const SizedBox(height: 14),
                      Expanded(
                        child: _noteTimeline(
                          localNotes: showLocal ? notes : const [],
                          remoteByDevice: remoteByDevice,
                          remoteDevices: remoteDevices,
                          scrollbarThickness: widget.scrollbarThickness,
                          bottomOverlay: _ScratchPadHoverActionStrip(
                            onAddNote: _edit,
                            surfaceBuilder: widget.buttonSurfaceBuilder,
                            overlay: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return Center(
            child: SizedBox(
              width: contentWidth,
              child: ListView(
                key: const Key('scratch-pad-note-list'),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
                children: [
                  controls,
                  const SizedBox(height: 6),
                  sectionHeader,
                  const SizedBox(height: 14),
                  if (showLocal && notes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(child: Text('No work notes yet.')),
                    ),
                  if (showLocal && notes.isNotEmpty)
                    _noteCollection(notes, columns: columns, editable: true),
                  for (final device in remoteDevices)
                    if (_deviceFilter == null || _deviceFilter == device) ...[
                      const SizedBox(height: 24),
                      Text(
                        widget.onManageNote == null
                            ? 'Shared from $device'
                            : 'Notes from $device',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _noteCollection(
                        remoteByDevice[device]!,
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

  Widget _noteCollection(
    List<ScratchPadNote> source, {
    required int columns,
    required bool editable,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: source.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: columns == 1
            ? 1.7
            : columns >= 3
            ? 1.18
            : 1.45,
      ),
      itemBuilder: (context, index) =>
          _noteTile(source[index], editable: editable),
    );
  }

  Widget _noteTimeline({
    required List<ScratchPadNote> localNotes,
    required Map<String, List<ScratchPadNote>> remoteByDevice,
    required List<String> remoteDevices,
    required double scrollbarThickness,
    required Widget bottomOverlay,
  }) {
    final segments = <_ScratchPadTimelineSegment>[
      if (localNotes.isNotEmpty)
        _ScratchPadTimelineSegment(
          key: 'local',
          title: 'Local Notes',
          icon: Icons.devices_outlined,
          notes: localNotes,
          editable: true,
        ),
      for (final device in remoteDevices)
        if (_deviceFilter == null || _deviceFilter == device)
          _ScratchPadTimelineSegment(
            key: device,
            title: widget.onManageNote == null
                ? 'Shared from $device'
                : 'Notes from $device',
            icon: Icons.devices_other_outlined,
            notes: remoteByDevice[device]!,
            editable: false,
          ),
    ];
    return _ScratchPadHorizontalTimeline(
      segments: segments,
      scrollbarThickness: scrollbarThickness,
      bottomOverlay: bottomOverlay,
      itemBuilder: (note, editable) => _noteTile(note, editable: editable),
    );
  }

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

class _ScratchPadTimelineSegment {
  const _ScratchPadTimelineSegment({
    required this.key,
    required this.title,
    required this.icon,
    required this.notes,
    required this.editable,
  });

  final String key;
  final String title;
  final IconData icon;
  final List<ScratchPadNote> notes;
  final bool editable;
}

class _ScratchPadHorizontalTimeline extends StatefulWidget {
  const _ScratchPadHorizontalTimeline({
    required this.segments,
    required this.itemBuilder,
    required this.scrollbarThickness,
    required this.bottomOverlay,
  });

  final List<_ScratchPadTimelineSegment> segments;
  final Widget Function(ScratchPadNote note, bool editable) itemBuilder;
  final double scrollbarThickness;
  final Widget bottomOverlay;

  @override
  State<_ScratchPadHorizontalTimeline> createState() =>
      _ScratchPadHorizontalTimelineState();
}

class _ScratchPadHorizontalTimelineState
    extends State<_ScratchPadHorizontalTimeline> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // The timeline owns the remaining page height.  Its cards scale from
      // that height rather than being trapped in a short nested viewport.
      final cardWidth = (constraints.maxHeight * .72).clamp(300.0, 560.0);
      final headerWidth = (cardWidth * .45).clamp(148.0, 236.0);
      final colors = Theme.of(context).colorScheme;
      return ScrollbarTheme(
        data: ScrollbarThemeData(
          thickness: WidgetStatePropertyAll(widget.scrollbarThickness),
          radius: Radius.circular(widget.scrollbarThickness / 2),
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => Color.alphaBlend(
              colors.primary.withValues(
                alpha: states.contains(WidgetState.hovered) ? .90 : .68,
              ),
              colors.surfaceContainerHigh,
            ),
          ),
          trackColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
          trackBorderColor: WidgetStatePropertyAll(colors.outlineVariant),
        ),
        child: Scrollbar(
          controller: _controller,
          thickness: widget.scrollbarThickness,
          radius: Radius.circular(widget.scrollbarThickness / 2),
          thumbVisibility: true,
          trackVisibility: true,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  // Desktop timelines should pan with a held primary mouse
                  // button, just like a canvas, without requiring the thumb.
                  dragDevices: const {
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.touch,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: SingleChildScrollView(
                  key: const Key('scratch-pad-horizontal-strip'),
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final segment in widget.segments) ...[
                          _ScratchPadTimelineHeader(
                            segment: segment,
                            width: headerWidth,
                          ),
                          const SizedBox(width: 12),
                          for (final note in segment.notes) ...[
                            SizedBox(
                              width: cardWidth,
                              child: widget.itemBuilder(note, segment.editable),
                            ),
                            const SizedBox(width: 12),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: widget.scrollbarThickness + 6,
                child: widget.bottomOverlay,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ScratchPadTimelineHeader extends StatelessWidget {
  const _ScratchPadTimelineHeader({required this.segment, required this.width});
  final _ScratchPadTimelineSegment segment;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ScratchPadDottedDividerPainter(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(segment.icon),
                const SizedBox(height: 10),
                Text(
                  segment.title,
                  key: Key('scratch-pad-timeline-${segment.key}'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ScratchPadPickleItem {
  const _ScratchPadPickleItem({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final Widget icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;
}

class _ScratchPadPickleBar extends StatelessWidget {
  const _ScratchPadPickleBar({
    required this.items,
    required this.surfaceBuilder,
    super.key,
  });
  final List<_ScratchPadPickleItem> items;
  final ScratchPadButtonSurfaceBuilder surfaceBuilder;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        boxShadow: const [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0)
                SizedBox(
                  height: 40,
                  width: 1,
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              _ScratchPadPickleSegment(
                item: items[index],
                surfaceBuilder: surfaceBuilder,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScratchPadPickleSegment extends StatefulWidget {
  const _ScratchPadPickleSegment({
    required this.item,
    required this.surfaceBuilder,
  });
  final _ScratchPadPickleItem item;
  final ScratchPadButtonSurfaceBuilder surfaceBuilder;

  @override
  State<_ScratchPadPickleSegment> createState() =>
      _ScratchPadPickleSegmentState();
}

class _ScratchPadPickleSegmentState extends State<_ScratchPadPickleSegment> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.item.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: widget.surfaceBuilder(
          joined: true,
          states: {
            if (hovered) WidgetState.hovered,
            if (widget.item.selected) WidgetState.selected,
          },
          child: InkWell(
            onTap: widget.item.onPressed,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(child: widget.item.icon),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScratchPadJewelButton extends StatefulWidget {
  const _ScratchPadJewelButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.surfaceBuilder,
    this.selected = false,
    super.key,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final Widget label;
  final ScratchPadButtonSurfaceBuilder surfaceBuilder;
  final bool selected;

  @override
  State<_ScratchPadJewelButton> createState() => _ScratchPadJewelButtonState();
}

class _ScratchPadJewelButtonState extends State<_ScratchPadJewelButton> {
  bool hovered = false;
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => pressed = true),
        onTapCancel: () => setState(() => pressed = false),
        onTapUp: (_) => setState(() => pressed = false),
        child: widget.surfaceBuilder(
          states: {
            if (hovered) WidgetState.hovered,
            if (pressed) WidgetState.pressed,
            if (widget.selected) WidgetState.selected,
          },
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [widget.icon, const SizedBox(width: 7), widget.label],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScratchPadHoverActionStrip extends StatelessWidget {
  const _ScratchPadHoverActionStrip({
    required this.onAddNote,
    required this.surfaceBuilder,
    this.overlay = false,
  });

  final VoidCallback onAddNote;
  final ScratchPadButtonSurfaceBuilder surfaceBuilder;
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strip = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: .42),
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(15),
            ),
            child: SizedBox(
              height: 56,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ScratchPadJewelButton(
                    onPressed: onAddNote,
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('Add note'),
                    surfaceBuilder: surfaceBuilder,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return overlay ? strip : SafeArea(top: false, child: strip);
  }
}

class _ScratchPadReadOnlyNote extends StatelessWidget {
  const _ScratchPadReadOnlyNote({
    required this.note,
    this.onRestore,
    this.onOwnerEdit,
    this.onOwnerDelete,
  });
  final VoidCallback? onRestore;
  final VoidCallback? onOwnerEdit;
  final VoidCallback? onOwnerDelete;
  final ScratchPadNote note;

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(note.title),
        actions: [
          if (onOwnerEdit != null)
            IconButton(
              tooltip: 'Edit as Owner',
              onPressed: onOwnerEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (onOwnerDelete != null)
            IconButton(
              tooltip: 'Delete as Owner',
              onPressed: onOwnerDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          if (onRestore != null)
            TextButton(
              onPressed: onRestore,
              child: const Text('Restore to device'),
            ),
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

class _ScratchPadDottedDividerPainter extends CustomPainter {
  const _ScratchPadDottedDividerPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .78)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var y = 8.0; y < size.height; y += 8) {
      canvas.drawLine(Offset(1, y), Offset(1, y + 2), paint);
    }
  }

  @override
  bool shouldRepaint(_ScratchPadDottedDividerPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ScratchPadMarkdownPreview extends StatelessWidget {
  const _ScratchPadMarkdownPreview({required this.markdown});

  final String markdown;
  static final _imagePattern = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)');

  @override
  Widget build(BuildContext context) {
    final source = scratchPadRenderMarkdown(markdown);
    final children = <Widget>[];
    var cursor = 0;
    for (final match in _imagePattern.allMatches(source)) {
      final before = source.substring(cursor, match.start);
      if (before.isNotEmpty) {
        children.add(_ScratchPadMarkdownText(markdown: before));
      }
      children.add(
        _ScratchPadMarkdownImage(
          altText: match.group(1) ?? '',
          source: match.group(2) ?? '',
        ),
      );
      cursor = match.end;
    }
    final after = source.substring(cursor);
    if (after.isNotEmpty || children.isEmpty) {
      children.add(_ScratchPadMarkdownText(markdown: after));
    }
    return SizedBox(
      width: double.infinity,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
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

class _ScratchPadMarkdownText extends StatefulWidget {
  const _ScratchPadMarkdownText({required this.markdown});
  final String markdown;

  @override
  State<_ScratchPadMarkdownText> createState() =>
      _ScratchPadMarkdownTextState();
}

class _ScratchPadMarkdownTextState extends State<_ScratchPadMarkdownText> {
  late final MarkdownEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = MarkdownEditingController(text: widget.markdown);
  }

  @override
  void didUpdateWidget(covariant _ScratchPadMarkdownText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdown != widget.markdown) {
      controller.text = widget.markdown;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    return RichText(
      text: controller.buildTextSpan(
        context: context,
        style: style,
        withComposing: false,
      ),
      softWrap: true,
    );
  }
}

class _ScratchPadMarkdownImage extends StatelessWidget {
  const _ScratchPadMarkdownImage({required this.source, required this.altText});
  final String source;
  final String altText;

  @override
  Widget build(BuildContext context) {
    final image = source.startsWith('asset://')
        ? Image.asset(
            source.replaceFirst('asset://', ''),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _fallback(context),
          )
        : source.startsWith('http://') || source.startsWith('https://')
        ? Image.network(
            source,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _fallback(context),
          )
        : _fallback(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(width: 128, height: 128, child: ClipRect(child: image)),
    );
  }

  Widget _fallback(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(altText.isEmpty ? 'Image unavailable' : altText),
      ),
    ),
  );
}

class _ScratchPadEditor extends StatefulWidget {
  const _ScratchPadEditor({
    this.note,
    this.subjects = const [],
    this.ownerEditing = false,
  });
  final bool ownerEditing;
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
                  subtitle: const Text(
                    'The workspace Owner can read, edit, or delete backed-up notes, even when sharing is off.',
                  ),
                  value: isShared,
                  onChanged: widget.ownerEditing
                      ? null
                      : (value) => setState(() => isShared = value),
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
                  child: Focus(
                    onKeyEvent: (_, event) {
                      if (event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }
                      final down =
                          event.logicalKey == LogicalKeyboardKey.arrowDown;
                      final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
                      if ((down || up) && body.movePastImage(down: down)) {
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
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
                              ownerRevision: widget.note?.ownerRevision ?? 0,
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
