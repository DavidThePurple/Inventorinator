import 'package:flutter/material.dart';

import 'supabase_sync.dart';

class SyncOnboardingChoice {
  const SyncOnboardingChoice.local() : config = null;
  const SyncOnboardingChoice.supabase(this.config);
  final SupabaseConfig? config;
}

class SyncOnboardingDialog extends StatefulWidget {
  const SyncOnboardingDialog({super.key});

  @override
  State<SyncOnboardingDialog> createState() => _SyncOnboardingDialogState();
}

class _SyncOnboardingDialogState extends State<SyncOnboardingDialog> {
  static const _defaultUrl = String.fromEnvironment('SUPABASE_URL');
  static const _defaultKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final serverController = TextEditingController(text: _defaultUrl);
  final keyController = TextEditingController(text: _defaultKey);
  bool configuringSupabase = false;
  bool busy = false;
  String error = '';

  @override
  void dispose() {
    serverController.dispose();
    keyController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final server = serverController.text.trim();
    final key = keyController.text.trim();
    if (Uri.tryParse(server)?.hasScheme != true || key.isEmpty) {
      setState(
        () => error = 'Enter the Supabase server address and publishable key.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final config = SupabaseConfig(
        syncMode: 'supabase',
        url: server,
        publishableKey: key,
      );
      await SupabaseSyncService(config).verifyServer();
      if (!mounted) return;
      Navigator.pop(context, SyncOnboardingChoice.supabase(config));
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      configuringSupabase
          ? 'Connect Supabase'
          : 'Where should Inventorinator save?',
    ),
    content: SizedBox(
      width: 520,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: configuringSupabase
            ? Column(
                key: const ValueKey('supabase-setup'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Enter the connection details from your Supabase instance.',
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('supabase-onboarding-url'),
                    controller: serverController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Supabase server address',
                      hintText: 'https://supabase.example.com',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('supabase-onboarding-key'),
                    controller: keyController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Publishable key',
                    ),
                    onSubmitted: (_) {
                      if (!busy) _connect();
                    },
                  ),
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ],
              )
            : Column(
                key: const ValueKey('provider-choice'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ProviderCard(
                    icon: Icons.computer_rounded,
                    title: 'This device only',
                    subtitle: 'No server. Enable syncing whenever you want.',
                    onTap: () => Navigator.pop(
                      context,
                      const SyncOnboardingChoice.local(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ProviderCard(
                    icon: Icons.dns_rounded,
                    title: 'Supabase',
                    subtitle: 'Connect to hosted or self-hosted Supabase.',
                    onTap: () => setState(() => configuringSupabase = true),
                  ),
                ],
              ),
      ),
    ),
    actions: configuringSupabase
        ? [
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      configuringSupabase = false;
                      error = '';
                    }),
              child: const Text('Back'),
            ),
            FilledButton(
              key: const Key('verify-supabase'),
              onPressed: busy ? null : _connect,
              child: const Text('Verify and continue'),
            ),
          ]
        : const [],
  );
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      contentPadding: const EdgeInsets.all(14),
      leading: Icon(icon, size: 30),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}
