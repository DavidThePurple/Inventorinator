import 'package:flutter/material.dart';

Future<String?> showDeviceNameDialog(
  BuildContext context, {
  required String initialName,
  bool explainAndroidRestriction = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _DeviceNameDialog(
    initialName: initialName,
    explainAndroidRestriction: explainAndroidRestriction,
  ),
);

class _DeviceNameDialog extends StatefulWidget {
  const _DeviceNameDialog({
    required this.initialName,
    required this.explainAndroidRestriction,
  });

  final String initialName;
  final bool explainAndroidRestriction;

  @override
  State<_DeviceNameDialog> createState() => _DeviceNameDialogState();
}

class _DeviceNameDialogState extends State<_DeviceNameDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void save() {
    final cleaned = controller.text.trim();
    if (cleaned.isNotEmpty) Navigator.pop(context, cleaned);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Name this device'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.explainAndroidRestriction) ...[
            const Text(
              'Android may hide the name you gave this phone. Confirm or replace it here.',
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            key: const Key('device-name'),
            controller: controller,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Device name'),
            onSubmitted: (_) => save(),
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
        key: const Key('save-device-name'),
        onPressed: save,
        child: const Text('Save'),
      ),
    ],
  );
}
