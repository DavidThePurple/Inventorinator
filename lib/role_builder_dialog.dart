import 'package:flutter/material.dart';

import 'workspace_role_template.dart';

class RoleBuilderDialog extends StatefulWidget {
  const RoleBuilderDialog({
    super.key,
    required this.load,
    required this.save,
    required this.delete,
    this.localOnly = false,
  });

  final Future<List<WorkspaceRoleTemplate>> Function() load;
  final Future<void> Function(WorkspaceRoleTemplate) save;
  final Future<void> Function(String) delete;
  final bool localOnly;

  @override
  State<RoleBuilderDialog> createState() => _RoleBuilderDialogState();
}

class _RoleBuilderDialogState extends State<RoleBuilderDialog> {
  List<WorkspaceRoleTemplate> _templates = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final templates = await widget.load();
      if (mounted) setState(() => _templates = templates);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([
    WorkspaceRoleTemplate? template,
    bool copy = false,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          RoleTemplateEditor(initial: template, copy: copy, save: widget.save),
    );
    if (saved == true && mounted) await _refresh();
  }

  Future<void> _delete(WorkspaceRoleTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${template.name}?'),
        content: const Text(
          'This removes the saved template. Device access is unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete template'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.delete(template.id!);
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: Text(
      widget.localOnly ? 'Role builder · local drafts' : 'Role builder',
    ),
    content: SizedBox(
      width: 620,
      height: MediaQuery.sizeOf(context).height * .6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.localOnly
                ? 'Saved only on this device. No network needed. These drafts are not uploaded and do not change anyone’s access.'
                : 'Create roles, then assign them in Roles & device access on server v25 or newer. Duplicate assigned roles before editing them.',
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: _busy ? null : _refresh,
              child: const Text('Retry'),
            ),
          ],
          Expanded(
            child: _templates.isEmpty && !_busy && _error == null
                ? const Center(
                    child: Text(
                      'No templates yet. Start with a preset and adjust its permissions.',
                    ),
                  )
                : ListView(
                    children: [
                      for (final template in _templates)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  template.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                if (template.description.isNotEmpty)
                                  Text(template.description),
                                Text(
                                  '${template.permissions.length} permissions · Unassigned template',
                                ),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _edit(template),
                                      child: const Text('Edit'),
                                    ),
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _edit(template, true),
                                      child: const Text('Duplicate'),
                                    ),
                                    TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _delete(template),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton.icon(
        key: const Key('new-role-template'),
        onPressed: _busy || _error != null ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('New template'),
      ),
    ],
  );
}

class RoleTemplateEditor extends StatefulWidget {
  const RoleTemplateEditor({
    super.key,
    this.initial,
    this.copy = false,
    required this.save,
  });
  final WorkspaceRoleTemplate? initial;
  final bool copy;
  final Future<void> Function(WorkspaceRoleTemplate) save;

  @override
  State<RoleTemplateEditor> createState() => _RoleTemplateEditorState();
}

class _RoleTemplateEditorState extends State<RoleTemplateEditor> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late Set<WorkspacePermission> _permissions;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.initial == null
          ? ''
          : '${widget.initial!.name}${widget.copy ? ' copy' : ''}',
    );
    _description = TextEditingController(
      text: widget.initial?.description ?? '',
    );
    _permissions = {...?widget.initial?.permissions};
    if (_permissions.isEmpty) {
      _permissions = RoleTemplatePreset.viewer.permissions;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final template = WorkspaceRoleTemplate(
      id: widget.copy ? null : widget.initial?.id,
      name: _name.text,
      description: _description.text,
      permissions: _permissions,
    );
    setState(() => _error = template.validationError);
    if (_error != null) return;
    setState(() => _saving = true);
    try {
      await widget.save(template);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(
        widget.initial == null || widget.copy
            ? 'New role template'
            : 'Edit role template',
      ),
      content: SizedBox(
        width: 620,
        height: MediaQuery.sizeOf(context).height * .65,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Draft permissions only. Saving does not grant access.',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('role-template-name'),
                controller: _name,
                enabled: !_saving,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'Role name',
                  hintText: 'e.g. Filament librarian',
                ),
              ),
              TextField(
                controller: _description,
                minLines: 1,
                maxLines: 3,
                enabled: !_saving,
                maxLength: 240,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
              ),
              const Text('Start from a preset'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final preset in RoleTemplatePreset.values)
                    ActionChip(
                      label: Text(preset.label),
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _permissions = preset.permissions;
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              for (final group
                  in WorkspacePermission.values
                      .map((p) => p.group)
                      .toSet()) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    group,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final permission in WorkspacePermission.values.where(
                  (p) => p.group == group,
                ))
                  CheckboxListTile(
                    key: Key('permission-${permission.id}'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(permission.label),
                    subtitle: Text(
                      '${permission.description}${permission == WorkspacePermission.readInventory ? ' Required for every template.' : ''}',
                    ),
                    secondary: permission.destructive
                        ? const Tooltip(
                            message: 'Destructive operation',
                            child: Icon(Icons.warning_amber_rounded),
                          )
                        : null,
                    value: _permissions.contains(permission),
                    onChanged:
                        _saving ||
                            permission == WorkspacePermission.readInventory
                        ? null
                        : (enabled) => setState(() {
                            if (enabled == true) {
                              _permissions.add(permission);
                            } else {
                              _permissions.remove(permission);
                            }
                          }),
                  ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Ownership, recovery, device removal and role-template management remain owner-only.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_error != null)
          SizedBox(
            width: double.infinity,
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('save-role-template'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save template'),
        ),
      ],
    ),
  );
}
