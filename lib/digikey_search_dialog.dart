import 'supplier_images.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'digikey.dart';
import 'digikey_settings.dart';
import 'service_status.dart';

class DigiKeySearchDialog extends StatefulWidget {
  const DigiKeySearchDialog({super.key, this.searchOverride});
  final Future<DigiKeyPage> Function(String query, int offset)? searchOverride;
  @override
  State<DigiKeySearchDialog> createState() => _DigiKeySearchDialogState();
}

class _DigiKeySearchDialogState extends State<DigiKeySearchDialog> {
  final _query = TextEditingController();
  DigiKeyClient? _client;
  DigiKeyPage? _page;
  bool _busy = false;
  final bool _sandbox = DigiKeySettings.sandbox;
  String? _error;
  String _lastQuery = '';
  final _statusKey = DigiKeySettings.statusKey;
  @override
  void dispose() {
    _query.dispose();
    _client?.close();
    super.dispose();
  }

  Future<void> _search({int offset = 0}) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _page = null;
    });
    ServiceStatus.set(_statusKey, ConnectionStateLed.checking);
    try {
      if (offset == 0) _lastQuery = _query.text.trim();
      _client ??= DigiKeyClient(
        clientId: DigiKeySettings.clientId,
        clientSecret: DigiKeySettings.clientSecret,
        sandbox: _sandbox,
      );
      final page = widget.searchOverride == null
          ? await _client!.search(_lastQuery, offset: offset)
          : await widget.searchOverride!(_lastQuery, offset);
      ServiceStatus.set(_statusKey, ConnectionStateLed.connected);
      if (mounted) setState(() => _page = page);
    } catch (error) {
      ServiceStatus.set(_statusKey, ConnectionStateLed.failed);
      if (mounted) {
        setState(
          () => _error = error is DigiKeyException
              ? error.message
              : 'Could not read DigiKey results. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canSearch =>
      !_busy && (widget.searchOverride != null || DigiKeySettings.configured);

  Widget _searchControls(double width, double textScale) {
    final field = TextField(
      key: const Key('digikey-query'),
      controller: _query,
      enabled: !_busy,
      maxLength: 250,
      textInputAction: TextInputAction.search,
      decoration: const InputDecoration(
        labelText: 'Part number or keywords',
        counterText: '',
      ),
      onSubmitted: _canSearch ? (_) => _search() : null,
    );
    final button = FilledButton.icon(
      key: const Key('digikey-search'),
      onPressed: _canSearch ? () => _search() : null,
      style: FilledButton.styleFrom(minimumSize: const Size(100, 48)),
      icon: const Icon(Icons.search),
      label: const Text('Search'),
    );
    if (width >= 520 * textScale) {
      return Row(
        children: [
          Expanded(child: field),
          const SizedBox(width: 12),
          button,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [field, const SizedBox(height: 12), button],
    );
  }

  Widget _partCard(DigiKeyPart part, double width) => SizedBox(
    width: width,
    child: Card(
      key: ValueKey('digikey-part-${part.supplierPartNumber}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SupplierImagePreview(url: part.imageUrl),
            SelectableText(
              part.manufacturerPartNumber.isEmpty
                  ? part.supplierPartNumber
                  : part.manufacturerPartNumber,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(part.manufacturer),
            SelectableText(part.supplierPartNumber),
            const SizedBox(height: 10),
            Text(part.description),
            const SizedBox(height: 12),
            Text(
              'Packaging: ${part.packaging.isEmpty ? 'Not specified' : part.packaging}',
            ),
            if (part.minimumOrderQuantity != null)
              Text('Minimum order: ${part.minimumOrderQuantity}'),
            if (part.standardPackage != null)
              Text('Standard package: ${part.standardPackage} units'),
            if (part.available != null)
              Text('Supplier stock: ${part.available} units'),
            if (part.unitPrice != null && part.currency.isNotEmpty)
              Text(
                'Unit quote: ${part.currency} ${part.unitPrice!.toStringAsFixed(4)}',
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SupplierUsePartButton(
                  imageUrl: part.imageUrl,
                  onSelected: () => Navigator.pop(context, part),
                ),
                if (part.productUrl.isNotEmpty)
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(100, 48),
                    ),
                    onPressed: () => launchUrl(
                      Uri.parse(part.productUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text('Product page'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    child: SizedBox(
      width: 1160,
      height: MediaQuery.sizeOf(context).height * .9,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final padding = constraints.maxWidth < 600 ? 16.0 : 24.0;
          final width = constraints.maxWidth - padding * 2;
          final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
          final columns = ((width + 12) / (360 * textScale.clamp(1, 2) + 12))
              .floor()
              .clamp(1, 3);
          final cardWidth = (width - (columns - 1) * 12) / columns;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(padding, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Search DigiKey',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  key: const Key('digikey-content'),
                  padding: EdgeInsets.fromLTRB(padding, 16, padding, 16),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    if (widget.searchOverride == null &&
                        !DigiKeySettings.configured)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Set up DigiKey in Remote Settings → DigiKey first.',
                        ),
                      ),
                    _searchControls(width, textScale),
                    const SizedBox(height: 12),
                    if (_sandbox)
                      const Text(
                        'Sandbox results are sample data, not live products.',
                      ),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        const Text('US catalog · USD'),
                        if (_page != null)
                          Text('${_page!.productCount} products'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_page != null && _page!.parts.isEmpty)
                      const Text(
                        'No selectable parts found. Try a different search.',
                      ),
                    if (_page != null)
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final part in _page!.parts)
                            _partCard(part, cardWidth),
                        ],
                      ),
                    if (_page != null) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: _busy || _page!.offset == 0
                                ? null
                                : () => _search(
                                    offset: (_page!.offset - 20).clamp(
                                      0,
                                      2147483647,
                                    ),
                                  ),
                            child: const Text('Previous'),
                          ),
                          TextButton(
                            onPressed: _busy || !_page!.hasNext
                                ? null
                                : () => _search(
                                    offset:
                                        _page!.offset + _page!.returnedProducts,
                                  ),
                            child: const Text('Next'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
