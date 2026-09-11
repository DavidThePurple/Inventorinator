import 'dart:async';

import 'package:flutter/material.dart';

import 'supabase_sync.dart';

enum ConnectionStateLed { unchecked, checking, connected, limited, failed }

class ServiceStatus {
  static final changes = ValueNotifier<int>(0);
  static final _schemaVersions = <String, int>{};
  static void setSchemaVersion(String key, int version) {
    _schemaVersions[key] = version;
  }

  static String compatibilityMessage(String key) {
    final version = _schemaVersions[key] ?? minimumInventorySchemaVersion;
    final missing = [
      if (version < 22) 'remote role templates',
      if (version < 23) 'DigiKey credential sync',
      if (version < 24) 'Mouser credential sync',
      if (version < 25) 'custom role assignment',
      if (version < 26) 'Scratch Pad backup',
    ];
    return 'Connected—server update needed for ${missing.join(', ')}. '
        'Inventory sync is supported. Local changes are retained.';
  }

  static final _states = <String, ConnectionStateLed>{};
  static ConnectionStateLed read(String key) =>
      _states[key] ?? ConnectionStateLed.unchecked;
  static void refresh() => scheduleMicrotask(() => changes.value++);
  static void set(String key, ConnectionStateLed state) {
    _states[key] =
        state == ConnectionStateLed.connected &&
            (_schemaVersions[key] ?? latestInventorinatorSchemaVersion) <
                latestInventorinatorSchemaVersion
        ? ConnectionStateLed.limited
        : state;
    refresh();
  }
}

class ServiceStatusLed extends StatelessWidget {
  const ServiceStatusLed({
    super.key,
    required this.name,
    required this.statusKey,
  });
  final String name, statusKey;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: ServiceStatus.changes,
    builder: (context, _, child) {
      final state = ServiceStatus.read(statusKey);
      final (color, label) = switch (state) {
        ConnectionStateLed.unchecked => (Colors.grey, 'Not checked'),
        ConnectionStateLed.checking => (Colors.amber, 'Checking'),
        ConnectionStateLed.connected => (
          Colors.greenAccent,
          'Last connection succeeded',
        ),
        ConnectionStateLed.limited => (
          Colors.amber,
          ServiceStatus.compatibilityMessage(statusKey),
        ),
        ConnectionStateLed.failed => (Colors.redAccent, 'Connection failed'),
      };
      return Tooltip(
        message: '$name: $label',
        child: Semantics(
          label: '$name: $label',
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: .35),
                      blurRadius: 5,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Text(name, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      );
    },
  );
}

class ServiceConnectionMessage extends StatelessWidget {
  const ServiceConnectionMessage({super.key, required this.statusKey});
  final String statusKey;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: ServiceStatus.changes,
    builder: (context, _, child) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(switch (ServiceStatus.read(statusKey)) {
        ConnectionStateLed.unchecked => 'Connection not checked yet.',
        ConnectionStateLed.checking => 'Connecting…',
        ConnectionStateLed.connected => 'Last connection succeeded.',
        ConnectionStateLed.limited => ServiceStatus.compatibilityMessage(
          statusKey,
        ),
        ConnectionStateLed.failed => 'Connection failed.',
      }),
    ),
  );
}
