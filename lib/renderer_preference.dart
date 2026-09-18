import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Which Flutter renderer the native launcher starts the engine with.
///
/// The engine picks its renderer before any Dart code runs, so the choice is
/// kept in a one-word `renderer` file beside the local database. The Linux,
/// Windows and Android launchers read that file at startup; a missing file
/// means the platform default.
enum RendererChoice { platformDefault, skia, impeller }

const rendererPreferenceFileName = 'renderer';

/// The renderer each platform uses when no choice is saved.
///
/// Linux uses Skia: Impeller's OpenGL ES backend rasterized the inventory grid
/// about four times slower there. Windows and Android keep Flutter's own
/// default, Impeller.
RendererChoice get platformDefaultRenderer =>
    Platform.isLinux ? RendererChoice.skia : RendererChoice.impeller;

String rendererLabel(RendererChoice choice) => switch (choice) {
  RendererChoice.platformDefault =>
    'Default (${rendererLabel(platformDefaultRenderer)})',
  RendererChoice.skia => 'Skia',
  RendererChoice.impeller => 'Impeller',
};

Future<RendererChoice> loadRendererChoice(Directory directory) async {
  final file = File('${directory.path}/$rendererPreferenceFileName');
  if (!await file.exists()) return RendererChoice.platformDefault;
  return switch ((await file.readAsString()).trim()) {
    'skia' => RendererChoice.skia,
    'impeller' => RendererChoice.impeller,
    _ => RendererChoice.platformDefault,
  };
}

Future<void> saveRendererChoice(
  Directory directory,
  RendererChoice choice,
) async {
  final file = File('${directory.path}/$rendererPreferenceFileName');
  if (choice == RendererChoice.platformDefault) {
    if (await file.exists()) await file.delete();
    return;
  }
  await directory.create(recursive: true);
  await file.writeAsString(choice.name);
}

/// Personalization control for the renderer used from the next launch.
class RendererPreferenceTile extends StatefulWidget {
  const RendererPreferenceTile({super.key, this.directory});

  /// Where the preference file lives; the app support directory by default.
  final Directory? directory;

  @override
  State<RendererPreferenceTile> createState() => _RendererPreferenceTileState();
}

class _RendererPreferenceTileState extends State<RendererPreferenceTile> {
  Directory? directory;
  RendererChoice? saved;
  RendererChoice? selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resolved =
          widget.directory ?? await getApplicationSupportDirectory();
      final choice = await loadRendererChoice(resolved);
      if (!mounted) return;
      setState(() {
        directory = resolved;
        saved = choice;
        selected = choice;
      });
    } catch (_) {
      // No app support directory (for example, in widget tests): hide the
      // control rather than offer a choice that cannot be kept.
    }
  }

  Future<void> _choose(RendererChoice choice) async {
    final target = directory;
    if (target == null) return;
    setState(() => selected = choice);
    try {
      await saveRendererChoice(target, choice);
    } catch (error) {
      if (!mounted) return;
      setState(() => selected = saved);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Could not save the renderer: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = selected;
    if (current == null) return const SizedBox.shrink();
    final pending = current != saved;
    return ListTile(
      key: const Key('renderer-preference'),
      contentPadding: EdgeInsets.zero,
      title: const Text('Renderer'),
      subtitle: Text(
        pending
            ? 'Restart Inventorinator to switch renderers.'
            : 'Graphics engine used to draw the app.',
      ),
      trailing: DropdownButton<RendererChoice>(
        key: const Key('renderer-preference-dropdown'),
        value: current,
        items: [
          for (final choice in RendererChoice.values)
            DropdownMenuItem(value: choice, child: Text(rendererLabel(choice))),
        ],
        onChanged: (choice) {
          if (choice != null) _choose(choice);
        },
      ),
    );
  }
}
