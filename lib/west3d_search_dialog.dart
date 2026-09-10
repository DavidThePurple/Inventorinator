import 'supplier_images.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'west3d.dart';

class West3DSearchDialog extends StatefulWidget {
  const West3DSearchDialog({
    super.key,
    this.client,
    this.store = Storefront.west3d,
  });
  final West3DClient? client;
  final Storefront store;
  @override
  State<West3DSearchDialog> createState() => _West3DSearchDialogState();
}

class _West3DSearchDialogState extends State<West3DSearchDialog> {
  late final _client = widget.client ?? West3DClient(store: widget.store);
  final _query = TextEditingController();
  List<West3DProduct>? _products;
  List<West3DPart>? _parts;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _query.dispose();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _load({West3DProduct? product}) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _parts = null;
      if (product == null) _products = null;
    });
    try {
      if (product == null) {
        final result = await _client.search(_query.text);
        if (mounted) setState(() => _products = result);
      } else {
        final result = await _client.variants(product);
        if (mounted) setState(() => _parts = result);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is West3DException
              ? e.message
              : 'Could not load ${_client.store.label} results. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card(String title, List<Widget> children, double width) => SizedBox(
    width: width,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
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
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Search ${_client.store.label}',
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth - 32;
                final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
                final columns = ((width + 12) / (350 * scale.clamp(1, 2) + 12))
                    .floor()
                    .clamp(1, 3);
                final cardWidth = (width - (columns - 1) * 12) / columns;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      key: Key('${_client.store.name}-query'),
                      controller: _query,
                      enabled: !_busy,
                      maxLength: 250,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        labelText: 'Keywords or SKU',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        key: Key('${_client.store.name}-search'),
                        onPressed: _busy ? null : () => _load(),
                        child: const Text('Search'),
                      ),
                    ),
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_parts != null)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _parts = null),
                        child: const Text('Back to results'),
                      ),
                    if (_parts == null && _products != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _products!.isEmpty
                              ? 'No matching products. Try another search.'
                              : 'Top ${_products!.length} matches. Refine your search for other products.',
                        ),
                      ),
                    if (_parts?.isEmpty == true)
                      const Text('No variants available for this product.'),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (_parts == null && _products != null)
                          for (final p in _products!)
                            _card(p.title, [
                              SupplierImagePreview(url: p.imageUrl),
                              Text(p.vendor),
                              Text(p.category),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _busy
                                    ? null
                                    : () => _load(product: p),
                                child: const Text('Choose variant'),
                              ),
                            ], cardWidth),
                        if (_parts != null)
                          for (final p in _parts!)
                            _card(p.itemName, [
                              SupplierImagePreview(url: p.imageUrl),
                              if (p.sku.isNotEmpty) Text('SKU: ${p.sku}'),
                              Text(
                                p.available
                                    ? 'Available from ${_client.store.label}'
                                    : 'Currently unavailable from ${_client.store.label}',
                              ),
                              const SizedBox(height: 12),
                              SupplierUsePartButton(
                                imageUrl: p.imageUrl,
                                onSelected: () => Navigator.pop(context, p),
                              ),
                              TextButton(
                                onPressed: () => launchUrl(
                                  Uri.parse(p.productUrl),
                                  mode: LaunchMode.externalApplication,
                                ),
                                child: const Text('Product page'),
                              ),
                            ], cardWidth),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
