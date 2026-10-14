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
      if (version < 28) 'Scratch Pad note links',
      if (version < 29) 'delete-queue fix',
      if (version < 34) 'checkout sync',
      if (version < 33) 'modified-time sync ordering',
      if (version < 32) 'workspace drying policy',
      if (version < 31) 'Scratch Pad device recovery',
      if (version < 30) 'safe import undo',
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
    this.inventoryCraft = false,
    this.framed = true,
  });
  final String name, statusKey;
  final bool inventoryCraft;
  final bool framed;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: ServiceStatus.changes,
    builder: (context, _, child) {
      final state = ServiceStatus.read(statusKey);
      final (color, label) = switch (state) {
        ConnectionStateLed.unchecked => (
          Colors.grey,
          'Remote unavailable or not configured',
        ),
        ConnectionStateLed.checking => (Colors.grey, 'Checking Remote'),
        ConnectionStateLed.connected => (
          Colors.greenAccent,
          'Remote connected and syncing',
        ),
        ConnectionStateLed.limited => (
          Colors.orange,
          ServiceStatus.compatibilityMessage(statusKey),
        ),
        ConnectionStateLed.failed => (
          Colors.redAccent,
          'Remote connection succeeded but sync failed',
        ),
      };
      final content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 17,
            height: 18,
            child: CustomPaint(painter: _OfficialSupabaseMarkPainter(color)),
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFamily: inventoryCraft ? 'monospace' : null,
              fontSize: inventoryCraft ? 12 : null,
              letterSpacing: inventoryCraft ? .7 : null,
            ),
          ),
        ],
      );
      final visual = inventoryCraft && framed
          ? Container(
              height: 40,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface
                    .withValues(alpha: .62),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: content,
            )
          : content;
      return Tooltip(
        message: '$name: $label',
        child: Semantics(
          label: '$name: $label',
          excludeSemantics: true,
          child: visual,
        ),
      );
    },
  );
}

/// The exact official Supabase symbol, recolored only to communicate the
/// connection state. The two paths are copied from the official SVG asset.
class _OfficialSupabaseMarkPainter extends CustomPainter {
  const _OfficialSupabaseMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 109, size.height / 113);
    final lower = Path()
      ..moveTo(63.7076, 110.284)
      ..cubicTo(60.8481, 113.885, 55.0502, 111.912, 54.9813, 107.314)
      ..lineTo(53.9738, 40.0625)
      ..lineTo(99.1935, 40.0625)
      ..cubicTo(107.384, 40.0625, 111.952, 49.5226, 106.859, 55.9372)
      ..lineTo(63.7076, 110.284)
      ..close();
    final upper = Path()
      ..moveTo(45.317, 2.07103)
      ..cubicTo(48.1765, -1.53037, 53.9745, 0.442937, 54.0434, 5.041)
      ..lineTo(54.4849, 72.2922)
      ..lineTo(9.83113, 72.2922)
      ..cubicTo(1.64038, 72.2922, -2.92775, 62.8321, 2.1655, 56.4175)
      ..lineTo(45.317, 2.07103)
      ..close();
    final glow = Paint()
      ..color = color.withValues(alpha: .40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawPath(lower, glow);
    canvas.drawPath(upper, glow);
    canvas.drawPath(lower, Paint()..color = color);
    canvas.drawPath(upper, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _OfficialSupabaseMarkPainter oldDelegate) =>
      oldDelegate.color != color;
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
