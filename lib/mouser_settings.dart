import 'dart:convert';

import 'package:flutter/material.dart';

import 'local_database.dart';
import 'mouser_credentials.dart';
import 'service_status.dart';
import 'supabase_sync.dart';

/// Cached credentials backed by device-private preferences.
class MouserSettings {
  static String statusKey = 'Mouser:local';
  static String apiKey = '';
  static bool get configured => apiKey.isNotEmpty;
  static void use(MouserCredentials value) {
    apiKey = value.apiKey;
  }

  static void load(LocalDatabase database) {
    final raw = database.loadSyncConfig();
    final json = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    final scope = mouserScope(
      json['url'] as String? ?? '',
      json['workspaceId'] as String?,
    );
    statusKey = 'Mouser:$scope';
    use(
      MouserCredentialStore(database, scope).read()?.credentials ??
          const MouserCredentials(),
    );
  }

  static void clear() {
    apiKey = '';
  }
}

class MouserSettingsPanel extends StatefulWidget {
  const MouserSettingsPanel({super.key, required this.store, this.syncRemote});
  final MouserCredentialStore store;
  final Future<void> Function()? syncRemote;
  @override
  State<MouserSettingsPanel> createState() => _MouserSettingsPanelState();
}

class _MouserSettingsPanelState extends State<MouserSettingsPanel> {
  final _secret = TextEditingController(text: MouserSettings.apiKey);
  String _message = '';
  bool _busy = false;
  bool _edited = false;
  @override
  void initState() {
    super.initState();
    _reload();
    if (widget.syncRemote != null) _sync();
  }

  @override
  void didUpdateWidget(covariant MouserSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncRemote == null && widget.syncRemote != null) _sync();
  }

  void _reload() {
    final value = widget.store.read()?.credentials ?? const MouserCredentials();
    MouserSettings.statusKey = 'Mouser:${widget.store.scope}';
    MouserSettings.use(value);
    _secret.text = value.apiKey;
  }

  Future<void> _sync() async {
    if (_busy || widget.syncRemote == null) return;
    setState(() => _busy = true);
    try {
      await widget.syncRemote!();
      if (!mounted) return;
      setState(() {
        if (!_edited) _reload();
        ServiceStatus.refresh();
        _message = 'Saved locally and remotely.';
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is SupabaseFeatureUnavailable
              ? error.message
              : widget.store.read()?.pending == true
              ? 'Saved locally. Remote update pending; retry when connected.'
              : 'Remote settings unavailable. Local settings are ready.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save(MouserCredentials value) {
    widget.store.save(value, pending: widget.syncRemote != null);
    ServiceStatus.set(
      'Mouser:${widget.store.scope}',
      ConnectionStateLed.unchecked,
    );
    MouserSettings.statusKey = 'Mouser:${widget.store.scope}';
    MouserSettings.use(value);
    setState(() {
      _edited = false;
      _message = 'Saved locally.';
    });
    _sync();
  }

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  void _apply() {
    if (_secret.text.trim().isEmpty) {
      setState(() => _message = 'Enter your Mouser Search API key.');
      return;
    }
    _save(MouserCredentials(apiKey: _secret.text.trim()));
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: const Key('mouser-settings'),
    tilePadding: EdgeInsets.zero,
    title: const Text('Mouser'),
    children: [
      if (widget.store.read()?.credentials.configured == true)
        ServiceConnectionMessage(statusKey: 'Mouser:${widget.store.scope}'),
      TextField(
        key: const Key('mouser-api-key'),
        controller: _secret,
        onChanged: (_) => _edited = true,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(labelText: 'Search API key'),
      ),
      Wrap(
        spacing: 8,
        children: [
          FilledButton(
            key: const Key('apply-mouser-settings'),
            onPressed: _busy ? null : _apply,
            child: const Text('Save'),
          ),
          if (widget.syncRemote != null)
            TextButton(
              onPressed: _busy ? null : _sync,
              child: const Text('Sync'),
            ),
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    _secret.clear();
                    _save(const MouserCredentials());
                  },
            child: const Text('Clear'),
          ),
        ],
      ),
      if (_message.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(_message),
        ),
    ],
  );
}
