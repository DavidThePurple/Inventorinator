import 'dart:convert';

import 'package:flutter/material.dart';

import 'local_database.dart';
import 'digikey_credentials.dart';
import 'service_status.dart';
import 'supabase_sync.dart';

/// Cached credentials backed by device-private preferences.
class DigiKeySettings {
  static String statusKey = 'DigiKey:local';
  static String clientId = '';
  static String clientSecret = '';
  static bool sandbox = false;
  static bool get configured => clientId.isNotEmpty && clientSecret.isNotEmpty;
  static void use(DigiKeyCredentials value) {
    clientId = value.clientId;
    clientSecret = value.clientSecret;
    sandbox = value.sandbox;
  }

  static void load(LocalDatabase database) {
    final raw = database.loadSyncConfig();
    final json = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    final scope = digiKeyScope(
      json['url'] as String? ?? '',
      json['workspaceId'] as String?,
    );
    statusKey = 'DigiKey:$scope';
    use(
      DigiKeyCredentialStore(database, scope).read()?.credentials ??
          const DigiKeyCredentials(),
    );
  }

  static void clear() {
    clientId = '';
    clientSecret = '';
    sandbox = false;
  }
}

class DigiKeySettingsPanel extends StatefulWidget {
  const DigiKeySettingsPanel({super.key, required this.store, this.syncRemote});
  final DigiKeyCredentialStore store;
  final Future<void> Function()? syncRemote;
  @override
  State<DigiKeySettingsPanel> createState() => _DigiKeySettingsPanelState();
}

class _DigiKeySettingsPanelState extends State<DigiKeySettingsPanel> {
  final _id = TextEditingController(text: DigiKeySettings.clientId);
  final _secret = TextEditingController(text: DigiKeySettings.clientSecret);
  bool _sandbox = DigiKeySettings.sandbox;
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
  void didUpdateWidget(covariant DigiKeySettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncRemote == null && widget.syncRemote != null) _sync();
  }

  void _reload() {
    final value =
        widget.store.read()?.credentials ?? const DigiKeyCredentials();
    DigiKeySettings.statusKey = 'DigiKey:${widget.store.scope}';
    DigiKeySettings.use(value);
    _id.text = value.clientId;
    _secret.text = value.clientSecret;
    _sandbox = value.sandbox;
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

  void _save(DigiKeyCredentials value) {
    widget.store.save(value, pending: widget.syncRemote != null);
    ServiceStatus.set(
      'DigiKey:${widget.store.scope}',
      ConnectionStateLed.unchecked,
    );
    DigiKeySettings.statusKey = 'DigiKey:${widget.store.scope}';
    DigiKeySettings.use(value);
    setState(() {
      _edited = false;
      _message = 'Saved locally.';
    });
    _sync();
  }

  @override
  void dispose() {
    _id.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _apply() {
    if (_id.text.trim().isEmpty || _secret.text.trim().isEmpty) {
      setState(() => _message = 'Enter both the client ID and client secret.');
      return;
    }
    _save(
      DigiKeyCredentials(
        clientId: _id.text.trim(),
        clientSecret: _secret.text.trim(),
        sandbox: _sandbox,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: const Key('digikey-settings'),
    tilePadding: EdgeInsets.zero,
    title: const Text('DigiKey'),
    children: [
      if (widget.store.read()?.credentials.configured == true)
        ServiceConnectionMessage(statusKey: 'DigiKey:${widget.store.scope}'),
      TextField(
        key: const Key('digikey-client-id'),
        controller: _id,
        onChanged: (_) => _edited = true,
        decoration: const InputDecoration(labelText: 'Client ID'),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('digikey-client-secret'),
        controller: _secret,
        onChanged: (_) => _edited = true,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(labelText: 'Client secret'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('DigiKey sandbox'),
        subtitle: const Text('Leave off to search real products.'),
        value: _sandbox,
        onChanged: (value) => setState(() {
          _edited = true;
          _sandbox = value;
        }),
      ),
      Wrap(
        spacing: 8,
        children: [
          FilledButton(
            key: const Key('apply-digikey-settings'),
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
                    _id.clear();
                    _secret.clear();
                    _sandbox = false;
                    _save(const DigiKeyCredentials());
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
