import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'local_database.dart';
import 'qr_scanner.dart';
import 'supabase_sync.dart';
import 'workshop_merge.dart';

enum _SyncChoice { device, cloud }

class CloudSyncDialog extends StatefulWidget {
  const CloudSyncDialog({
    super.key,
    required this.database,
    required this.localStateJson,
    required this.onCloudState,
  });
  final LocalDatabase database;
  final String localStateJson;
  final ValueChanged<String> onCloudState;
  @override
  State<CloudSyncDialog> createState() => _CloudSyncDialogState();
}

class _CloudSyncDialogState extends State<CloudSyncDialog> {
  static const _defaultUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const _defaultKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  late final TextEditingController urlController;
  late final TextEditingController keyController;
  final pairingController = TextEditingController();
  late SupabaseConfig config;
  bool busy = false;
  bool joining = false;
  bool isWorkspaceOwner = false;
  String message = '';
  bool get connected => config.hasSession && config.workspaceId != null;

  @override
  void initState() {
    super.initState();
    final saved = widget.database.loadSyncConfig();
    config = saved == null
        ? const SupabaseConfig(url: _defaultUrl, publishableKey: _defaultKey)
        : SupabaseConfig.fromJson(jsonDecode(saved) as Map<String, dynamic>);
    urlController = TextEditingController(text: config.url);
    keyController = TextEditingController(text: config.publishableKey);
    isWorkspaceOwner = config.workspaceRole == 'owner';
    if (connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadOwnerAccess());
    }
  }

  @override
  void dispose() {
    urlController.dispose();
    keyController.dispose();
    pairingController.dispose();
    super.dispose();
  }

  SupabaseConfig _formConfig() => SupabaseConfig(
    syncMode: config.syncMode,
    url: urlController.text.trim(),
    publishableKey: keyController.text.trim(),
    userId: config.userId,
    workspaceId: config.workspaceId,
    workspaceRole: config.workspaceRole,
    refreshToken: config.refreshToken,
    lastSyncedAt: config.lastSyncedAt,
    lastSyncedStateJson: config.lastSyncedStateJson,
  );

  void _save(SupabaseConfig value) {
    config = value;
    widget.database.saveSyncConfig(jsonEncode(value.toJson()));
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      final result = await action();
      if (mounted) setState(() => message = result);
    } catch (error) {
      if (mounted) setState(() => message = error.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _requireServer(SupabaseConfig value) {
    if (!value.isConfigured) {
      throw const SupabaseSyncException(
        'Open Advanced and enter a sync server and publishable key.',
      );
    }
  }

  Future<String> _startSyncing() async {
    final next = _formConfig();
    _requireServer(next);
    final service = SupabaseSyncService(next);
    final session = await service.signInAnonymously();
    await service.requireCurrentSchema(session);
    final workspaceId = await service.createWorkspace(session);
    _save(
      next.copyWith(
        userId: session.userId,
        workspaceId: workspaceId,
        workspaceRole: 'owner',
        refreshToken: session.refreshToken,
      ),
    );
    await SupabaseSyncService(config).registerDevice(session, _deviceName);
    if (mounted) setState(() => isWorkspaceOwner = true);
    return _sync();
  }

  Map<String, dynamic>? _decodePairingPayload(String source) {
    const prefix = 'inventorinator:pair:';
    if (!source.startsWith(prefix)) return null;
    return jsonDecode(
      utf8.decode(
        base64Url.decode(base64Url.normalize(source.substring(prefix.length))),
      ),
    ) as Map<String, dynamic>;
  }

  Future<String> _joinDevice() async {
    final raw = pairingController.text.trim();
    if (raw.isEmpty) {
      throw const SupabaseSyncException('Enter or scan the pairing code.');
    }
    final payload = _decodePairingPayload(raw);
    if (payload != null) {
      urlController.text = payload['url'] as String;
      keyController.text = payload['key'] as String;
    }
    final code = payload?['code'] as String? ?? raw;
    final next = _formConfig();
    _requireServer(next);
    final service = SupabaseSyncService(next);
    final session = await service.signInAnonymously();
    await service.requireCurrentSchema(session);
    final workspaceId = await service.redeemPairingCode(session, code);
    final joined = next.copyWith(
      userId: session.userId,
      workspaceId: workspaceId,
      workspaceRole: 'builder',
      refreshToken: session.refreshToken,
    );
    _save(joined);
    final joinedService = SupabaseSyncService(joined);
    await joinedService.registerDevice(session, _deviceName);
    if (mounted) setState(() => isWorkspaceOwner = false);
    final cloud = await joinedService.download(session);
    if (cloud == null) {
      final state = _canonicalJson(widget.localStateJson);
      final updatedAt = await joinedService.upload(session, state);
      _save(
        joined.copyWith(lastSyncedAt: updatedAt, lastSyncedStateJson: state),
      );
    } else {
      // Joining an existing shared inventory must never upload starter/local
      // rows over it. The existing workspace is authoritative at pairing time.
      final state = canonicalWorkshopState(cloud.stateJson);
      widget.onCloudState(state);
      _save(
        joined.copyWith(
          lastSyncedAt: cloud.updatedAt,
          lastSyncedStateJson: state,
        ),
      );
    }
    pairingController.clear();
    return 'Connected. This device now shares the same inventory.';
  }

  Future<(SupabaseSyncService, SupabaseSession)> _session() async {
    final next = _formConfig();
    if (!next.isConfigured || !connected) {
      throw const SupabaseSyncException('Connect this device before syncing.');
    }
    final session = await SupabaseSyncService(next).refresh();
    final refreshed = next.copyWith(
      userId: session.userId,
      refreshToken: session.refreshToken,
    );
    // Refresh tokens rotate. Save the new token before subsequent requests.
    _save(refreshed);
    return (SupabaseSyncService(refreshed), session);
  }

  String get _deviceName => widget.database.loadStringPreference(
    'device_name',
    fallback: 'Unnamed device',
  );

  Future<void> _loadOwnerAccess() async {
    try {
      final (service, session) = await _session();
      final role = await service.currentRole(session);
      _save(config.copyWith(workspaceRole: role));
      if (mounted) setState(() => isWorkspaceOwner = role == 'owner');
    } catch (_) {
      if (mounted) setState(() => isWorkspaceOwner = false);
    }
  }

  Future<void> _manageDevices() async {
    final (service, session) = await _session();
    await service.registerDevice(session, _deviceName);
    if (await service.currentRole(session) != 'owner') {
      throw const SupabaseSyncException(
        'Only the shared inventory owner can manage devices.',
      );
    }
    var devices = await service.listDevices(session);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDeviceState) {
          final me = devices
              .where((device) => device.userId == session.userId)
              .firstOrNull;
          final isOwner = me?.role == 'owner';
          Future<void> refresh() async {
            devices = await service.listDevices(session);
            setDeviceState(() {});
          }

          return AlertDialog(
            title: const Text('Workspace devices'),
            content: SizedBox(
              width: 560,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: devices.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) {
                  final device = devices[index];
                  final isMe = device.userId == session.userId;
                  final removable = isOwner && !isMe && device.role != 'owner';
                  return ListTile(
                    leading: Icon(
                      device.role == 'owner'
                          ? Icons.workspace_premium_outlined
                          : device.role == 'admin'
                          ? Icons.admin_panel_settings_outlined
                          : device.role == 'manager'
                          ? Icons.manage_accounts_outlined
                          : device.role == 'editor'
                          ? Icons.edit_note_outlined
                          : Icons.devices_outlined,
                    ),
                    title: Text(
                      '${device.name}${isMe ? ' (this device)' : ''}',
                    ),
                    subtitle: Text(device.role.toUpperCase()),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (removable)
                          DropdownButton<String>(
                            key: Key('role-${device.userId}'),
                            value: switch (device.role) {
                              'member' => 'builder',
                              final role => role,
                            },
                            items: const [
                              DropdownMenuItem(
                                value: 'admin',
                                child: Text('Admin'),
                              ),
                              DropdownMenuItem(
                                value: 'manager',
                                child: Text('Manager'),
                              ),
                              DropdownMenuItem(
                                value: 'editor',
                                child: Text('Editor'),
                              ),
                              DropdownMenuItem(
                                value: 'builder',
                                child: Text('Builder'),
                              ),
                            ],
                            onChanged: (role) async {
                              if (role == null) return;
                              await service.setDeviceRole(
                                session,
                                device.userId,
                                role,
                              );
                              await refresh();
                            },
                          ),
                        if (removable)
                          PopupMenuButton<bool>(
                            tooltip: 'Device access',
                            onSelected: (lockOut) async {
                              await service.removeDevice(
                                session,
                                device.userId,
                                lockOut: lockOut,
                              );
                              await refresh();
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: false,
                                child: Text('Remove device'),
                              ),
                              PopupMenuItem(
                                value: true,
                                child: Text('Remove and lock out'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  Object? _sortedJson(Object? value) {
    if (value is List) return value.map(_sortedJson).toList();
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _sortedJson(value[key])};
    }
    return value;
  }

  String _canonicalJson(String source) =>
      jsonEncode(_sortedJson(jsonDecode(source)));

  Future<_SyncChoice?> _chooseConflict() => showDialog<_SyncChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Two inventories changed'),
      content: const Text(
        'Choose which version to keep. Nothing changes until you choose.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, _SyncChoice.cloud),
          child: const Text('Use shared inventory'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _SyncChoice.device),
          child: const Text('Keep this device'),
        ),
      ],
    ),
  );

  Future<String> _sync() async {
    final (service, session) = await _session();
    final cloud = await service.download(session);
    final localJson = _canonicalJson(widget.localStateJson);
    if (cloud == null) {
      final updatedAt = await service.upload(session, localJson);
      _save(
        config.copyWith(
          lastSyncedAt: updatedAt,
          lastSyncedStateJson: localJson,
        ),
      );
      return 'Synced. Your inventory is available to paired devices.';
    }
    final cloudJson = _canonicalJson(cloud.stateJson);
    final previous = config.lastSyncedStateJson == null
        ? null
        : _canonicalJson(config.lastSyncedStateJson!);
    final localChanged = previous == null || localJson != previous;
    final cloudChanged = previous == null || cloudJson != previous;
    if (localJson == cloudJson) {
      _save(
        config.copyWith(
          lastSyncedAt: cloud.updatedAt,
          lastSyncedStateJson: cloudJson,
        ),
      );
      return 'Already up to date.';
    }
    if (!localChanged && cloudChanged) {
      widget.onCloudState(cloudJson);
      _save(
        config.copyWith(
          lastSyncedAt: cloud.updatedAt,
          lastSyncedStateJson: cloudJson,
        ),
      );
      return 'Synced changes from another device.';
    }
    if (localChanged && !cloudChanged) {
      final updatedAt = await service.upload(session, localJson);
      _save(
        config.copyWith(
          lastSyncedAt: updatedAt,
          lastSyncedStateJson: localJson,
        ),
      );
      return 'Synced changes from this device.';
    }
    final choice = await _chooseConflict();
    if (choice == null) return 'Sync cancelled. Nothing was changed.';
    if (choice == _SyncChoice.cloud) {
      widget.onCloudState(cloudJson);
      _save(
        config.copyWith(
          lastSyncedAt: cloud.updatedAt,
          lastSyncedStateJson: cloudJson,
        ),
      );
      return 'Shared inventory restored to this device.';
    }
    final updatedAt = await service.upload(session, localJson);
    _save(
      config.copyWith(lastSyncedAt: updatedAt, lastSyncedStateJson: localJson),
    );
    return 'This device replaced the shared inventory.';
  }

  Future<void> _showPairingCode() async {
    setState(() {
      busy = true;
      message = '';
    });
    late final String code;
    try {
      final (service, session) = await _session();
      code = await service.createPairingCode(session);
    } catch (error) {
      if (mounted) setState(() => message = error.toString());
      return;
    } finally {
      if (mounted) setState(() => busy = false);
    }
    final payload =
        'inventorinator:pair:${base64UrlEncode(utf8.encode(jsonEncode({'url': config.url, 'key': config.publishableKey, 'code': code})))}';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => PairingCodeDialog(payload: payload, code: code),
    );
  }

  Future<void> _scanPairingCode() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (scannerContext) => InventoryQrScanner(
          onCode: (code, _, _) {
            if (!code.startsWith('inventorinator:pair:')) return;
            pairingController.text = code;
            Navigator.of(scannerContext).pop();
            _run(_joinDevice);
          },
        ),
      ),
    );
  }

  void _disconnect() {
    final next = _formConfig();
    _save(SupabaseConfig(url: next.url, publishableKey: next.publishableKey));
    setState(() {
      joining = false;
      isWorkspaceOwner = false;
      message = 'This device was disconnected. Shared data was not deleted.';
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.cloud_sync_outlined),
        SizedBox(width: 10),
        Text('Sync devices'),
      ],
    ),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (connected)
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: Colors.greenAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Shared inventory ${config.workspaceId!.substring(0, 8)}',
                  ),
                ],
              )
            else if (joining) ...[
              const Text(
                'Enter the code shown on a connected device, or scan its pairing QR.',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('pairing-code'),
                      controller: pairingController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Pairing code',
                      ),
                      onSubmitted: (_) {
                        if (!busy) _run(_joinDevice);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    key: const Key('scan-pairing-code'),
                    tooltip: 'Scan pairing QR',
                    onPressed: busy ? null : _scanPairingCode,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                  ),
                ],
              ),
            ] else
              const Text(
                'Create a new shared inventory, or join one already running on another device.',
              ),
            const SizedBox(height: 8),
            ExpansionTile(
              key: const Key('advanced-sync-settings'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Advanced'),
              children: [
                TextField(
                  key: const Key('supabase-url'),
                  controller: urlController,
                  decoration: const InputDecoration(labelText: 'Sync server'),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('supabase-key'),
                  controller: keyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Publishable key',
                  ),
                ),
              ],
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText(message),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      if (connected) ...[
        TextButton(
          onPressed: busy ? null : _disconnect,
          child: const Text('Disconnect'),
        ),
        if (isWorkspaceOwner)
          OutlinedButton.icon(
            key: const Key('manage-devices'),
            onPressed: busy
                ? null
                : () => _run(() async {
                    await _manageDevices();
                    return '';
                  }),
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('Devices'),
          ),
        OutlinedButton.icon(
          key: const Key('pair-device'),
          onPressed: busy ? null : _showPairingCode,
          icon: const Icon(Icons.qr_code_rounded),
          label: const Text('Add another device'),
        ),
        FilledButton.icon(
          key: const Key('sync-now'),
          onPressed: busy ? null : () => _run(_sync),
          icon: const Icon(Icons.sync_rounded),
          label: const Text('Sync now'),
        ),
      ] else if (joining) ...[
        TextButton(
          onPressed: busy ? null : () => setState(() => joining = false),
          child: const Text('Back'),
        ),
        FilledButton(
          key: const Key('join-device'),
          onPressed: busy ? null : () => _run(_joinDevice),
          child: const Text('Connect'),
        ),
      ] else ...[
        OutlinedButton(
          key: const Key('show-join-device'),
          onPressed: busy ? null : () => setState(() => joining = true),
          child: const Text('Join existing inventory'),
        ),
        FilledButton.icon(
          key: const Key('start-syncing'),
          onPressed: busy ? null : () => _run(_startSyncing),
          icon: const Icon(Icons.link_rounded),
          label: const Text('Create shared inventory'),
        ),
      ],
    ],
  );
}

class PairingCodeDialog extends StatelessWidget {
  const PairingCodeDialog({
    super.key,
    required this.payload,
    required this.code,
  });
  final String payload;
  final String code;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Pair another device'),
    content: SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: SizedBox.square(
              dimension: 220,
              child: QrImageView(data: payload),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Scan this QR code, or enter:'),
          const SizedBox(height: 6),
          SelectableText(
            code,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          const Text('One use · expires in 10 minutes'),
        ],
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}
