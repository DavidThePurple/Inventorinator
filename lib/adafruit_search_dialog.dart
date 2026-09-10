import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'adafruit.dart';
import 'adafruit_catalog.dart';
import 'supplier_images.dart';

class AdafruitSearchDialog extends StatefulWidget {
  const AdafruitSearchDialog({
    super.key,
    this.client,
    this.catalog,
    this.catalogPath,
  });
  final AdafruitClient? client;
  final AdafruitCatalog? catalog;
  final String? catalogPath;
  @override
  State<AdafruitSearchDialog> createState() => _AdafruitSearchDialogState();
}

class _AdafruitSearchDialogState extends State<AdafruitSearchDialog> {
  late final _client = widget.client ?? AdafruitClient.shared;
  AdafruitCatalog? _catalog;
  final _query = TextEditingController();
  Timer? _timer;
  AdafruitCatalogPage? _page;
  String? _error;
  String _searched = '';
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _open();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _open() async {
    try {
      final catalog =
          widget.catalog ??
          AdafruitCatalog(
            widget.catalogPath ??
                path.join(
                  (await getApplicationSupportDirectory()).path,
                  'adafruit-catalog.sqlite3',
                ),
          );
      if (!mounted) {
        if (widget.catalog == null) catalog.close();
        return;
      }
      setState(() => _catalog = catalog);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open the local product catalog.');
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _query.dispose();
    if (widget.catalog == null) _catalog?.close();
    super.dispose();
  }

  Future<void> _search({
    int offset = 0,
    bool refresh = false,
    bool pageOnly = false,
  }) async {
    final catalog = _catalog;
    if (_busy || catalog == null) return;
    FocusScope.of(context).unfocus();
    final query = pageOnly ? _searched : _query.text.trim();
    if (!refresh && query.isEmpty) {
      setState(
        () => _error = 'Enter keywords, a part number, or a product link.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (refresh ||
          (catalog.count == 0 && AdafruitClient.productId(query) == null)) {
        await catalog.refresh(_client);
      }
      if (!mounted) return;
      var page = catalog.search(query, offset: offset);
      if (page.total == 0 &&
          AdafruitClient.productId(query) != null &&
          !refresh) {
        final part = await _client.lookup(query);
        page = AdafruitCatalogPage([part], 1, 0);
      }
      if (mounted) {
        setState(() {
          _page = page;
          _searched = query;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AdafruitException ? e.message : 'Could not update the catalog. Your saved products are still available.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card(AdafruitPart part, double width) => SizedBox(
    width: width,
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(part.itemName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SupplierImagePreview(url: part.imageUrl),
            Text(
              '${part.manufacturer} · ${part.partNumber.isEmpty ? 'ADA${part.id}' : part.partNumber}',
            ),
            const SizedBox(height: 12),
            SupplierUsePartButton(
              imageUrl: part.imageUrl,
              onSelected: () => Navigator.pop(context, part),
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(part.productUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Product page'),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final seconds = _client.secondsRemaining;
    final hasCatalog = _catalog?.updatedAt != null;
    final networkReady = seconds == 0 && !_client.requestInFlight;
    final canSearch =
        !_busy &&
        _catalog != null &&
        (hasCatalog || _client.cached(_query.text) != null || networkReady);
    return Dialog(
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
                      'Search Adafruit',
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
                  final columns =
                      ((width + 12) / (350 * scale.clamp(1, 2) + 12))
                          .floor()
                          .clamp(1, 3);
                  final cardWidth = (width - (columns - 1) * 12) / columns;
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TextField(
                        key: const Key('adafruit-query'),
                        controller: _query,
                        maxLength: 250,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          labelText: 'Keywords, part number, or product link',
                          counterText: '',
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) {
                          if (canSearch) _search();
                        },
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton(
                            key: const Key('adafruit-search'),
                            onPressed: canSearch ? () => _search() : null,
                            child: Text(_busy ? 'Loading…' : 'Search'),
                          ),
                          OutlinedButton(
                            key: const Key('adafruit-refresh'),
                            onPressed:
                                !_busy && _catalog != null && networkReady
                                ? () => _search(refresh: true)
                                : null,
                            child: Text(
                              hasCatalog
                                  ? 'Refresh catalog'
                                  : 'Download catalog',
                            ),
                          ),
                          Text(
                            seconds > 0
                                ? 'Next request in ${seconds}s'
                                : (_client.requestInFlight
                                      ? 'Request in progress'
                                      : 'Ready'),
                            key: const Key('adafruit-cooldown'),
                          ),
                        ],
                      ),
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(),
                        ),
                      if (seconds > 0) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _client.cooldownProgress,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        hasCatalog
                            ? 'Saved catalog · updated ${MaterialLocalizations.of(context).formatShortDate(_catalog!.updatedAt!.toLocal())} · searches work offline'
                            : 'The first keyword search downloads the catalog once. Searches then work offline.',
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (_page case final page?) ...[
                        const SizedBox(height: 12),
                        Text(
                          page.total == 0
                              ? 'No matching products. Try another search.'
                              : '${page.total} results',
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final part in page.parts)
                              _card(part, cardWidth),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (page.total > 12)
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              OutlinedButton(
                                key: const Key('adafruit-previous'),
                                onPressed: !_busy && page.offset > 0
                                    ? () => _search(
                                        offset: page.offset - 12,
                                        pageOnly: true,
                                      )
                                    : null,
                                child: const Text('Previous'),
                              ),
                              Text(
                                'Page ${page.offset ~/ 12 + 1} of ${(page.total / 12).ceil()}',
                              ),
                              OutlinedButton(
                                key: const Key('adafruit-next'),
                                onPressed:
                                    !_busy &&
                                        page.offset + page.parts.length <
                                            page.total
                                    ? () => _search(
                                        offset: page.offset + 12,
                                        pageOnly: true,
                                      )
                                    : null,
                                child: const Text('Next'),
                              ),
                            ],
                          ),
                      ],
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
}
