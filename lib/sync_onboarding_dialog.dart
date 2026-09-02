import 'dart:convert';

import 'package:flutter/material.dart';

import 'qr_scanner.dart';
import 'supabase_sync.dart';

class SyncOnboardingChoice {
  const SyncOnboardingChoice.local() : config = null, pairingPayload = null;
  const SyncOnboardingChoice.supabase(this.config, {this.pairingPayload});
  final SupabaseConfig? config;
  final String? pairingPayload;
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
  final pairingController = TextEditingController();
  bool configuringSupabase = false;
  bool joiningExisting = false;
  bool busy = false;
  String error = '';

  @override
  void dispose() {
    serverController.dispose();
    keyController.dispose();
    pairingController.dispose();
    super.dispose();
  }

  SupabaseConfig _enteredConfig() => SupabaseConfig(
    syncMode: 'supabase',
    url: serverController.text.trim(),
    publishableKey: keyController.text.trim(),
  );

  Future<void> _connect() async {
    final candidate = _enteredConfig();
    if (!candidate.isConfigured) {
      setState(
        () => error =
            'Enter an HTTP(S) Supabase server address and publishable key.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await SupabaseSyncService(candidate).verifyServer();
      if (!mounted) return;
      Navigator.pop(context, SyncOnboardingChoice.supabase(candidate));
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  ({SupabaseConfig config, String payload}) _decodePairingKey(String source) {
    const prefix = 'inventorinator:pair:';
    if (!source.startsWith(prefix)) throw const FormatException();
    final payload = jsonDecode(
      utf8.decode(
        base64Url.decode(base64Url.normalize(source.substring(prefix.length))),
      ),
    ) as Map<String, dynamic>;
    final config = SupabaseConfig(
      syncMode: 'supabase',
      url: payload['url'] as String? ?? '',
      publishableKey: payload['key'] as String? ?? '',
    );
    if (!config.isConfigured || (payload['code'] as String? ?? '').isEmpty) {
      throw const FormatException();
    }
    return (config: config, payload: source);
  }

  Future<void> _joinWithPairingKey() async {
    final source = pairingController.text.trim();
    if (source.isEmpty) {
      setState(() => error = 'Paste the pairing key from the inventory owner.');
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final decoded = _decodePairingKey(source);
      await SupabaseSyncService(decoded.config).verifyServer();
      if (!mounted) return;
      Navigator.pop(
        context,
        SyncOnboardingChoice.supabase(
          decoded.config,
          pairingPayload: decoded.payload,
        ),
      );
    } on FormatException {
      if (mounted) {
        setState(
          () => error = 'That is not a valid Inventorinator pairing key.',
        );
      }
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _scanPairingQr() async {
    String? scanned;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (scannerContext) => InventoryQrScanner(
          onCode: (code, _, _) {
            if (!code.startsWith('inventorinator:pair:')) return;
            scanned = code;
            Navigator.of(scannerContext).pop();
          },
        ),
      ),
    );
    if (!mounted || scanned == null) return;
    try {
      final decoded = _decodePairingKey(scanned!);
      setState(() {
        busy = true;
        error = '';
      });
      await SupabaseSyncService(decoded.config).verifyServer();
      if (!mounted) return;
      Navigator.pop(
        context,
        SyncOnboardingChoice.supabase(
          decoded.config,
          pairingPayload: decoded.payload,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'That is not a valid Inventorinator pairing QR.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      joiningExisting
          ? 'Join existing inventory'
          : configuringSupabase
          ? 'Owner setup'
          : 'Where should Inventorinator save?',
    ),
    content: SizedBox(
      width: 520,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: joiningExisting
            ? SingleChildScrollView(
                key: const ValueKey('pairing-setup'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Paste the pairing key supplied by the inventory owner, or scan its QR code.',
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('supabase-onboarding-pairing-key'),
                      controller: pairingController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Pairing key',
                      ),
                      onSubmitted: (_) {
                        if (!busy) _joinWithPairingKey();
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
                ),
              )
            : configuringSupabase
            ? SingleChildScrollView(
                key: const ValueKey('supabase-setup'),
                child: Column(
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
                ),
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
                    icon: Icons.group_add_rounded,
                    title: 'Join an existing inventory',
                    subtitle: 'Use a pairing key from its owner.',
                    onTap: () => setState(() => joiningExisting = true),
                  ),
                  const SizedBox(height: 12),
                  _ProviderCard(
                    icon: Icons.dns_rounded,
                    title: 'Owner setup',
                    subtitle: 'Create or recover an inventory with Supabase.',
                    onTap: () => setState(() => configuringSupabase = true),
                  ),
                ],
              ),
      ),
    ),
    actions: joiningExisting
        ? [
            OutlinedButton.icon(
              key: const Key('onboarding-scan-pairing'),
              onPressed: busy ? null : _scanPairingQr,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan pairing QR'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      joiningExisting = false;
                      error = '';
                    }),
              child: const Text('Back'),
            ),
            FilledButton(
              key: const Key('onboarding-join-with-key'),
              onPressed: busy ? null : _joinWithPairingKey,
              child: const Text('Join'),
            ),
          ]
        : configuringSupabase
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
