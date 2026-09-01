import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'local_database.dart';
import 'device_name_dialog.dart';
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
    this.initialPairingCode,
  });
  final LocalDatabase database;
  final String localStateJson;
  final ValueChanged<String> onCloudState;
  final String? initialPairingCode;
  @override
  State<CloudSyncDialog> createState() => _CloudSyncDialogState();
}

class _CloudSyncDialogState extends State<CloudSyncDialog> {
  static const _knownWorkspacesPreference = 'known_supabase_workspaces';
  static const _defaultUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const _defaultKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  late final TextEditingController urlController;
  late final TextEditingController keyController;
  final pairingController = TextEditingController();
  late SupabaseConfig config;
  late List<SupabaseConfig> knownWorkspaces;
  bool busy = false;
  bool joining = false;
  bool isWorkspaceOwner = false;
  bool sessionNeedsReconnect = false;
  String message = '';
  bool get connected => config.hasSession && config.workspaceId != null;
  bool get canManageDevices => canManageWorkspaceDevices(config.workspaceRole);

  String _visibleSyncError(Object error) =>
      visibleSyncErrorForRole(error, config.workspaceRole);

  @override
  void initState() {
    super.initState();
    final saved = widget.database.loadSyncConfig();
    config = saved == null
        ? const SupabaseConfig(url: _defaultUrl, publishableKey: _defaultKey)
        : SupabaseConfig.fromJson(jsonDecode(saved) as Map<String, dynamic>);
    urlController = TextEditingController(text: config.url);
    keyController = TextEditingController(text: config.publishableKey);
    knownWorkspaces = _loadKnownWorkspaces();
    _rememberWorkspace(config);
    isWorkspaceOwner =
        config.workspaceRole == 'owner' ||
        (config.workspaceId != null &&
            widget.database.loadWorkspaceRecoveryKey(config.workspaceId!) !=
                null);
    if (widget.initialPairingCode != null) {
      pairingController.text = widget.initialPairingCode!;
      joining = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _run(_joinDevice));
    } else if (connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!_deviceNameConfirmed) await _run(_renameCurrentDevice);
        if (mounted) await _loadOwnerAccess();
      });
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
    accessToken: config.accessToken,
    accessTokenExpiresAt: config.accessTokenExpiresAt,
    refreshToken: config.refreshToken,
    lastSyncedAt: config.lastSyncedAt,
    lastSyncedStateJson: config.lastSyncedStateJson,
  );

  void _save(SupabaseConfig value) {
    config = value;
    widget.database.saveSyncConfig(jsonEncode(value.toJson()));
    _rememberWorkspace(value);
  }

  List<SupabaseConfig> _loadKnownWorkspaces() {
    final source = widget.database.loadStringPreference(
      _knownWorkspacesPreference,
      fallback: '[]',
    );
    try {
      return (jsonDecode(source) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(SupabaseConfig.fromJson)
          .where(
            (candidate) =>
                candidate.isConfigured &&
                candidate.hasSession &&
                candidate.workspaceId != null,
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _rememberWorkspace(SupabaseConfig value) {
    if (!value.isConfigured || !value.hasSession || value.workspaceId == null) {
      return;
    }
    final index = knownWorkspaces.indexWhere(
      (candidate) =>
          candidate.url == value.url &&
          candidate.workspaceId == value.workspaceId,
    );
    if (index < 0) {
      knownWorkspaces.add(value);
    } else {
      knownWorkspaces[index] = value;
    }
    widget.database.saveStringPreference(
      _knownWorkspacesPreference,
      jsonEncode(
        knownWorkspaces.map((candidate) => candidate.toJson()).toList(),
      ),
    );
  }

  void _forgetWorkspace(SupabaseConfig value) {
    setState(() {
      knownWorkspaces.removeWhere(
        (candidate) =>
            candidate.url == value.url &&
            candidate.workspaceId == value.workspaceId,
      );
    });
    widget.database.saveStringPreference(
      _knownWorkspacesPreference,
      jsonEncode(
        knownWorkspaces.map((candidate) => candidate.toJson()).toList(),
      ),
    );
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
      if (mounted) {
        setState(() {
          if (error is SupabaseSyncException && error.isInvalidRefreshToken) {
            sessionNeedsReconnect = true;
          }
          message = _visibleSyncError(error);
        });
      }
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
    final registrationName = await _deviceNameForRegistration();
    final next = _formConfig();
    _requireServer(next);
    final service = SupabaseSyncService(next);
    final session = await service.signInAnonymously();
    await service.requireCurrentSchema(session);
    final recovery = await service.createWorkspaceWithRecovery(session);
    widget.database.saveWorkspaceRecoveryKey(
      recovery.workspaceId,
      recovery.key,
    );
    _save(
      next.copyWith(
        userId: session.userId,
        workspaceId: recovery.workspaceId,
        workspaceRole: 'owner',
        accessToken: session.accessToken,
        accessTokenExpiresAt: session.expiresAt,
        refreshToken: session.refreshToken,
      ),
    );
    await SupabaseSyncService(config).registerDevice(session, registrationName);
    if (mounted) {
      setState(() {
        isWorkspaceOwner = true;
        sessionNeedsReconnect = false;
      });
    }
    final result = await _sync();
    if (mounted) await _showRecoveryKey(recovery);
    return result;
  }

  String _recoveryPayload(WorkspaceRecovery recovery) =>
      'inventorinator:recovery:${base64UrlEncode(utf8.encode(jsonEncode({'url': config.url, 'key': config.publishableKey, 'workspace_id': recovery.workspaceId, 'recovery_key': recovery.key})))}';

  Future<void> _showRecoveryKey(WorkspaceRecovery recovery) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => RecoveryKeyDialog(
      workspaceId: recovery.workspaceId,
      recoveryKey: recovery.key,
      payload: _recoveryPayload(recovery),
    ),
  );

  Future<String> _recoverOwnership() async {
    final source = await showDialog<String>(
      context: context,
      builder: (_) => const RecoveryImportDialog(),
    );
    if (source == null || source.trim().isEmpty) return '';
    const prefix = 'inventorinator:recovery:';
    Map<String, dynamic> package;
    try {
      final raw = source.trim();
      package = jsonDecode(
        raw.startsWith(prefix)
            ? utf8.decode(
                base64Url.decode(
                  base64Url.normalize(raw.substring(prefix.length)),
                ),
              )
            : raw,
      ) as Map<String, dynamic>;
    } catch (_) {
      throw const SupabaseSyncException('That recovery package is invalid.');
    }
    urlController.text = package['url'] as String? ?? urlController.text;
    keyController.text = package['key'] as String? ?? keyController.text;
    final workspaceId = package['workspace_id'] as String? ?? '';
    final recoveryKey = package['recovery_key'] as String? ?? '';
    final next = _formConfig();
    _requireServer(next);
    final service = SupabaseSyncService(next);
    final session = await service.signInAnonymously();
    await service.requireCurrentSchema(session);
    final registrationName = await _deviceNameForRegistration();
    final replacement = await service.recoverWorkspace(
      session,
      workspaceId: workspaceId,
      recoveryKey: recoveryKey,
      deviceName: registrationName,
    );
    widget.database.saveWorkspaceRecoveryKey(
      replacement.workspaceId,
      replacement.key,
    );
    final recovered = next.copyWith(
      syncMode: 'supabase',
      userId: session.userId,
      workspaceId: replacement.workspaceId,
      workspaceRole: 'owner',
      accessToken: session.accessToken,
      accessTokenExpiresAt: session.expiresAt,
      refreshToken: session.refreshToken,
    );
    _save(recovered);
    final cloud = await SupabaseSyncService(recovered).download(session);
    if (cloud != null) {
      final state = canonicalWorkshopState(cloud.stateJson);
      widget.onCloudState(state);
      _save(
        recovered.copyWith(
          lastSyncedAt: cloud.updatedAt,
          lastSyncedStateJson: state,
        ),
      );
    }
    if (mounted) {
      setState(() {
        joining = false;
        isWorkspaceOwner = true;
        sessionNeedsReconnect = false;
      });
      await _showRecoveryKey(replacement);
    }
    return 'Ownership recovered. Previous owner devices were locked out.';
  }

  Future<void> _replaceRecoveryKey() async {
    await _run(() async {
      final (service, session) = await _session();
      final key = await service.rotateRecoveryKey(session);
      final recovery = WorkspaceRecovery(
        workspaceId: config.workspaceId!,
        key: key,
      );
      widget.database.saveWorkspaceRecoveryKey(recovery.workspaceId, key);
      if (mounted) await _showRecoveryKey(recovery);
      return 'Recovery key replaced. The old key no longer works.';
    });
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
    final registrationName = await _deviceNameForRegistration();
    final workspaceId = await service.redeemPairingCode(session, code);
    final joined = next.copyWith(
      userId: session.userId,
      workspaceId: workspaceId,
      workspaceRole: 'builder',
      accessToken: session.accessToken,
      accessTokenExpiresAt: session.expiresAt,
      refreshToken: session.refreshToken,
    );
    _save(joined);
    final joinedService = SupabaseSyncService(joined);
    await joinedService.registerDevice(session, registrationName);
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
    if (mounted) setState(() => sessionNeedsReconnect = false);
    return 'Connected. This device now shares the same inventory.';
  }

  Future<(SupabaseSyncService, SupabaseSession)> _session() async {
    return widget.database.withSyncSessionLock(() async {
      final saved = widget.database.loadSyncConfig();
      final next = saved == null
          ? _formConfig()
          : SupabaseConfig.fromJson(jsonDecode(saved) as Map<String, dynamic>);
      if (!next.isConfigured || !next.hasSession || next.workspaceId == null) {
        throw const SupabaseSyncException(
          'Connect this device before syncing.',
        );
      }
      final (refreshed, session) = await _refreshOrRecoverOwner(next);
      if (identical(refreshed, next)) {
        config = refreshed;
      } else {
        // Refresh tokens rotate. Save the replacement while the shared session
        // lock is held so automatic sync cannot reuse the old token.
        _save(refreshed);
      }
      return (SupabaseSyncService(refreshed), session);
    });
  }

  Future<(SupabaseConfig, SupabaseSession)> _refreshOrRecoverOwner(
    SupabaseConfig source,
  ) async {
    final cached = source.cachedSession;
    if (cached != null) return (source, cached);
    try {
      final session = await SupabaseSyncService(source).refresh();
      return (
        source.copyWith(
          userId: session.userId,
          accessToken: session.accessToken,
          accessTokenExpiresAt: session.expiresAt,
          refreshToken: session.refreshToken,
        ),
        session,
      );
    } on SupabaseSyncException catch (error) {
      final workspaceId = source.workspaceId;
      final recoveryKey = workspaceId == null
          ? null
          : widget.database.loadWorkspaceRecoveryKey(workspaceId);
      if (!error.isInvalidRefreshToken ||
          workspaceId == null ||
          recoveryKey == null) {
        rethrow;
      }
      final service = SupabaseSyncService(source);
      final replacementSession = await service.signInAnonymously();
      await service.requireCurrentSchema(replacementSession);
      final replacement = await service.recoverWorkspace(
        replacementSession,
        workspaceId: workspaceId,
        recoveryKey: recoveryKey,
        deviceName: _deviceName,
      );
      widget.database.saveWorkspaceRecoveryKey(
        replacement.workspaceId,
        replacement.key,
      );
      if (mounted) {
        setState(() {
          isWorkspaceOwner = true;
          sessionNeedsReconnect = false;
        });
      }
      return (
        source.copyWith(
          syncMode: 'supabase',
          userId: replacementSession.userId,
          workspaceId: replacement.workspaceId,
          workspaceRole: 'owner',
          accessToken: replacementSession.accessToken,
          accessTokenExpiresAt: replacementSession.expiresAt,
          refreshToken: replacementSession.refreshToken,
        ),
        replacementSession,
      );
    }
  }

  String get _deviceName => widget.database.loadStringPreference(
    'device_name',
    fallback: 'Unnamed device',
  );

  bool get _deviceNameConfirmed => widget.database.loadBoolPreference(
    'device_name_confirmed',
    fallback: !Platform.isAndroid,
  );

  Future<String?> _promptForDeviceName() async {
    final chosen = await showDeviceNameDialog(
      context,
      initialName: _deviceName,
      explainAndroidRestriction: Platform.isAndroid,
    );
    if (chosen == null || chosen.isEmpty) return null;
    widget.database.saveStringPreference('device_name', chosen);
    widget.database.saveBoolPreference('device_name_confirmed', true);
    if (mounted) setState(() {});
    return chosen;
  }

  Future<String> _deviceNameForRegistration() async {
    if (_deviceNameConfirmed) return _deviceName;
    final chosen = await _promptForDeviceName();
    if (chosen == null) {
      throw const SupabaseSyncException('Choose a device name to continue.');
    }
    return chosen;
  }

  Future<String> _renameCurrentDevice() async {
    final chosen = await _promptForDeviceName();
    if (chosen == null) return '';
    if (connected) {
      final (service, session) = await _session();
      await service.registerDevice(session, chosen);
    }
    return 'Device renamed to $chosen.';
  }

  Future<void> _loadOwnerAccess() async {
    try {
      final (service, session) = await _session();
      final role = await service.currentRole(session);
      _save(config.copyWith(workspaceRole: role));
      if (role == 'owner') {
        final recoveryKey = await service.ensureRecoveryKey(session);
        if (recoveryKey != null && config.workspaceId != null) {
          widget.database.saveWorkspaceRecoveryKey(
            config.workspaceId!,
            recoveryKey,
          );
        }
      }
      if (mounted) {
        setState(() {
          isWorkspaceOwner = role == 'owner';
          sessionNeedsReconnect = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          if (error is SupabaseSyncException && error.isInvalidRefreshToken) {
            sessionNeedsReconnect = true;
          }
          message = _visibleSyncError(error);
        });
      }
    }
  }

  Future<void> _manageDevices() async {
    final (service, session) = await _session();
    await service.registerDevice(session, _deviceName);
    final callerRole = await service.currentRole(session);
    if (!canManageWorkspaceDevices(callerRole)) {
      throw const SupabaseSyncException('Your role cannot manage devices.');
    }
    var devices = await service.listDevices(session);
    var accessMessage = '';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDeviceState) {
          final me = devices
              .where((device) => device.userId == session.userId)
              .firstOrNull;
          final isOwner = me?.role == 'owner';
          final isAdmin = me?.role == 'admin';
          final isManager = me?.role == 'manager';
          Future<void> refresh() async {
            devices = await service.listDevices(session);
            setDeviceState(() {});
          }

          return AlertDialog(
            title: const Text('Roles & device access'),
            content: SizedBox(
              width: 680,
              height: MediaQuery.sizeOf(context).height * .64,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Owner controls recovery and removal. Admins manage all non-owner roles. Managers manage Editors and Builders.',
                    style: TextStyle(color: Color(0xff929aac)),
                  ),
                  if (accessMessage.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      accessMessage,
                      key: const Key('role-editor-message'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _RoleSummaryChip(role: 'Admin', summary: 'Full control'),
                      _RoleSummaryChip(
                        role: 'Manager',
                        summary: 'Manage, no hard delete',
                      ),
                      _RoleSummaryChip(
                        role: 'Editor',
                        summary: 'Edit existing items',
                      ),
                      _RoleSummaryChip(
                        role: 'Builder',
                        summary: 'View and operate builds',
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  Expanded(
                    child: ListView.separated(
                      itemCount: devices.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        final isMe = device.userId == session.userId;
                        final editable =
                            !isMe &&
                            device.role != 'owner' &&
                            (isOwner ||
                                isAdmin ||
                                isManager &&
                                    (device.role == 'editor' ||
                                        device.role == 'builder' ||
                                        device.role == 'member'));
                        final assignableRoles = isManager
                            ? const ['editor', 'builder']
                            : const ['admin', 'manager', 'editor', 'builder'];
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
                          subtitle: device.role == 'owner'
                              ? const Text(
                                  'OWNER · Transfer with the recovery package',
                                )
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (editable)
                                DropdownButton<String>(
                                  key: Key('role-${device.userId}'),
                                  value: switch (device.role) {
                                    'member' => 'builder',
                                    final role => role,
                                  },
                                  items: assignableRoles
                                      .map(
                                        (role) => DropdownMenuItem(
                                          value: role,
                                          child: Text(
                                            '${role[0].toUpperCase()}${role.substring(1)}',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (role) async {
                                    if (role == null || role == device.role) {
                                      return;
                                    }
                                    try {
                                      await service.setDeviceRole(
                                        session,
                                        device.userId,
                                        role,
                                      );
                                      accessMessage = '';
                                      await refresh();
                                    } catch (error) {
                                      setDeviceState(() {
                                        accessMessage = error.toString();
                                      });
                                    }
                                  },
                                )
                              else if (device.role != 'owner')
                                Text(device.role.toUpperCase()),
                              if (isOwner && editable)
                                PopupMenuButton<bool>(
                                  tooltip: 'Device access',
                                  onSelected: (lockOut) async {
                                    try {
                                      await service.removeDevice(
                                        session,
                                        device.userId,
                                        lockOut: lockOut,
                                      );
                                      accessMessage = '';
                                      await refresh();
                                    } catch (error) {
                                      setDeviceState(() {
                                        accessMessage = error.toString();
                                      });
                                    }
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
                ],
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
      builder: (_) => PairingCodeDialog(payload: payload),
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

  Future<String> _reconnectWorkspace(SupabaseConfig remembered) async {
    final (initial, session) = await widget.database.withSyncSessionLock(
      () => _refreshOrRecoverOwner(remembered),
    );
    var restored = initial.copyWith(syncMode: 'supabase');
    // Refresh tokens rotate. Preserve the replacement before any later request
    // can fail and strand an otherwise valid remembered workspace.
    _rememberWorkspace(restored);
    var service = SupabaseSyncService(restored);
    await service.requireCurrentSchema(session);
    final role = await service.currentRole(session);
    restored = restored.copyWith(workspaceRole: role);
    service = SupabaseSyncService(restored);
    await service.registerDevice(session, _deviceName);
    final cloud = await service.download(session);
    if (cloud != null) {
      final state = canonicalWorkshopState(cloud.stateJson);
      widget.onCloudState(state);
      restored = restored.copyWith(
        lastSyncedAt: cloud.updatedAt,
        lastSyncedStateJson: state,
      );
    }
    urlController.text = restored.url;
    keyController.text = restored.publishableKey;
    _save(restored);
    if (mounted) {
      setState(() {
        joining = false;
        isWorkspaceOwner = role == 'owner';
        sessionNeedsReconnect = false;
      });
    }
    return cloud == null
        ? 'Connected. This shared inventory is empty.'
        : 'Connected to the selected inventory.';
  }

  void _disconnect() {
    final next = _formConfig();
    _rememberWorkspace(next);
    _save(SupabaseConfig(url: next.url, publishableKey: next.publishableKey));
    setState(() {
      joining = false;
      isWorkspaceOwner = false;
      sessionNeedsReconnect = false;
      message = 'This device was disconnected. Shared data was not deleted.';
    });
  }

  Widget _dialogActions() => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 10.0;
      final useColumns = constraints.maxWidth >= 220;
      final buttonWidth = useColumns
          ? (constraints.maxWidth - gap) / 2
          : constraints.maxWidth;

      Widget tile(IconData icon, String label) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      );

      Widget action(Widget child) =>
          SizedBox(width: buttonWidth, height: 104, child: child);

      final actions = <Widget>[];
      if (joining) {
        actions.addAll([
          action(
            FilledButton(
              key: const Key('join-device'),
              onPressed: busy ? null : () => _run(_joinDevice),
              child: tile(
                Icons.link_rounded,
                sessionNeedsReconnect ? 'Reconnect' : 'Connect',
              ),
            ),
          ),
          action(
            OutlinedButton(
              key: const Key('recover-ownership'),
              onPressed: busy ? null : () => _run(_recoverOwnership),
              child: tile(Icons.restore_rounded, 'Recover ownership'),
            ),
          ),
          action(
            OutlinedButton(
              onPressed: busy ? null : () => setState(() => joining = false),
              child: tile(Icons.arrow_back_rounded, 'Back'),
            ),
          ),
        ]);
      } else if (connected) {
        if (sessionNeedsReconnect) {
          actions.add(
            action(
              FilledButton(
                key: const Key('reconnect-device'),
                onPressed: busy ? null : () => setState(() => joining = true),
                child: tile(Icons.link_rounded, 'Reconnect this device'),
              ),
            ),
          );
        } else {
          actions.add(
            action(
              FilledButton(
                key: const Key('sync-now'),
                onPressed: busy ? null : () => _run(_sync),
                child: tile(Icons.sync_rounded, 'Sync now'),
              ),
            ),
          );
          if (canManageDevices) {
            actions.addAll([
              action(
                OutlinedButton(
                  key: const Key('manage-devices'),
                  onPressed: busy
                      ? null
                      : () => _run(() async {
                          await _manageDevices();
                          return '';
                        }),
                  child: tile(
                    Icons.admin_panel_settings_outlined,
                    'Roles & devices',
                  ),
                ),
              ),
              action(
                OutlinedButton(
                  key: const Key('pair-device'),
                  onPressed: busy ? null : _showPairingCode,
                  child: tile(Icons.qr_code_rounded, 'Add another device'),
                ),
              ),
            ]);
          }
          if (isWorkspaceOwner) {
            actions.add(
              action(
                OutlinedButton(
                  key: const Key('replace-recovery-key'),
                  onPressed: busy ? null : _replaceRecoveryKey,
                  child: tile(Icons.key_rounded, 'Ownership & recovery'),
                ),
              ),
            );
          }
        }
        actions.add(
          action(
            OutlinedButton(
              onPressed: busy ? null : _disconnect,
              child: tile(Icons.link_off_rounded, 'Disconnect this device'),
            ),
          ),
        );
      } else {
        actions.addAll([
          action(
            OutlinedButton(
              key: const Key('show-join-device'),
              onPressed: busy ? null : () => setState(() => joining = true),
              child: tile(Icons.group_add_outlined, 'Join existing inventory'),
            ),
          ),
          action(
            FilledButton(
              key: const Key('start-syncing'),
              onPressed: busy ? null : () => _run(_startSyncing),
              child: tile(Icons.add_link_rounded, 'Create shared inventory'),
            ),
          ),
        ]);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 28),
          Wrap(spacing: gap, runSpacing: gap, children: actions),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Icon(Icons.cloud_sync_outlined),
        const SizedBox(width: 10),
        const Expanded(child: Text('Remote Sync')),
        IconButton(
          key: const Key('close-remote-sync'),
          tooltip: 'Close',
          onPressed: busy ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (joining) ...[
              if (!sessionNeedsReconnect && knownWorkspaces.isNotEmpty) ...[
                const Text(
                  'Previously joined on this device',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                for (final workspace in knownWorkspaces)
                  Card(
                    child: ListTile(
                      key: Key('known-workspace-${workspace.workspaceId}'),
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(
                        'Shared inventory ${workspace.workspaceId!.substring(0, 8)}',
                      ),
                      subtitle: Text(
                        '${workspace.workspaceRole ?? 'member'} · ${workspace.url}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: busy
                          ? null
                          : () => _run(() => _reconnectWorkspace(workspace)),
                      trailing: IconButton(
                        key: Key('forget-workspace-${workspace.workspaceId}'),
                        tooltip: 'Forget this saved connection',
                        onPressed: busy
                            ? null
                            : () => _forgetWorkspace(workspace),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ),
                const Divider(height: 28),
              ],
              Text(
                sessionNeedsReconnect
                    ? 'Enter a new pairing key from an Owner, Admin, or Manager.'
                    : 'For a new device, paste its pairing key or scan its pairing QR.',
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
                        labelText: 'Pairing key',
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
            ] else if (connected)
              Row(
                children: [
                  Icon(
                    sessionNeedsReconnect
                        ? Icons.link_off_rounded
                        : Icons.check_circle_outline,
                    color: sessionNeedsReconnect
                        ? Colors.orangeAccent
                        : Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sessionNeedsReconnect
                          ? 'Reconnect this device to verify its access.'
                          : 'Shared inventory ${config.workspaceId!.substring(0, 8)}',
                    ),
                  ),
                ],
              )
            else
              const Text(
                'Create a new shared inventory, or join one already running on another device.',
              ),
            const SizedBox(height: 8),
            ExpansionTile(
              key: const Key('advanced-sync-settings'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Advanced'),
              children: [
                if (connected) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Device name'),
                    subtitle: Text(_deviceName),
                    trailing: IconButton(
                      key: const Key('rename-cloud-device'),
                      tooltip: 'Rename this device',
                      onPressed: busy ? null : () => _run(_renameCurrentDevice),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
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
            _dialogActions(),
          ],
        ),
      ),
    ),
  );
}

class RecoveryKeyDialog extends StatelessWidget {
  const RecoveryKeyDialog({
    super.key,
    required this.workspaceId,
    required this.recoveryKey,
    required this.payload,
  });

  final String workspaceId;
  final String recoveryKey;
  final String payload;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save your owner recovery key'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'This restores ownership if every connected device is lost. '
            'Keep it in a password manager or another safe place.',
          ),
          const SizedBox(height: 14),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(10),
            alignment: Alignment.center,
            child: SizedBox.square(
              dimension: 210,
              child: QrImageView(data: payload),
            ),
          ),
          const SizedBox(height: 12),
          SelectableText('Inventory ID: $workspaceId'),
          const SizedBox(height: 6),
          SelectableText('Recovery key: $recoveryKey'),
          const SizedBox(height: 10),
          const Text(
            'Recovery transfers ownership, locks out the previous owner device, '
            'and replaces this key.',
          ),
        ],
      ),
    ),
    actions: [
      OutlinedButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: payload));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Recovery package copied.')),
            );
          }
        },
        icon: const Icon(Icons.copy_rounded),
        label: const Text('Copy recovery package'),
      ),
      OutlinedButton.icon(
        onPressed: () async {
          final decoded = utf8.decode(
            base64Url.decode(
              base64Url.normalize(
                payload.substring('inventorinator:recovery:'.length),
              ),
            ),
          );
          await FilePicker.saveFile(
            dialogTitle: 'Save Inventorinator owner recovery file',
            fileName: 'inventorinator-owner-recovery.json',
            bytes: Uint8List.fromList(utf8.encode(decoded)),
            mimeType: 'application/json',
          );
        },
        icon: const Icon(Icons.download_rounded),
        label: const Text('Save file'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('I saved it'),
      ),
    ],
  );
}

class RecoveryImportDialog extends StatefulWidget {
  const RecoveryImportDialog({super.key});

  @override
  State<RecoveryImportDialog> createState() => _RecoveryImportDialogState();
}

class _RecoveryImportDialogState extends State<RecoveryImportDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Recover shared inventory'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('recovery-package'),
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Owner recovery package',
              hintText:
                  'Paste the package saved when the inventory was created',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await FilePicker.pickFile(
                dialogTitle: 'Choose Inventorinator owner recovery file',
                type: FileType.custom,
                allowedExtensions: const ['json'],
              );
              if (picked != null) {
                controller.text = utf8.decode(await picked.readAsBytes());
              }
            },
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Choose recovery file'),
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
        key: const Key('confirm-recovery'),
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('Recover and lock out old owner'),
      ),
    ],
  );
}

class _RoleSummaryChip extends StatelessWidget {
  const _RoleSummaryChip({required this.role, required this.summary});

  final String role;
  final String summary;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .28),
      ),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$role · ',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          TextSpan(text: summary),
        ],
      ),
    ),
  );
}

class PairingCodeDialog extends StatelessWidget {
  const PairingCodeDialog({super.key, required this.payload});
  final String payload;

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
          const Text('Scan the QR code or copy the pairing key.'),
          const SizedBox(height: 6),
          const Text('One use · expires in 10 minutes'),
        ],
      ),
    ),
    actions: [
      OutlinedButton.icon(
        key: const Key('copy-pairing-key'),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: payload));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Pairing key copied.')),
            );
          }
        },
        icon: const Icon(Icons.copy_rounded),
        label: const Text('Copy pairing key'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}
