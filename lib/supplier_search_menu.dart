import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'west3d.dart';

/// One compact entry point; supplier choices live in a scrollable popup.
class SupplierSearchMenu extends StatelessWidget {
  const SupplierSearchMenu({
    super.key,
    required this.onDigiKey,
    required this.onMouser,
    required this.onWest3D,
    required this.onLdo,
    required this.onAdafruit,
    required this.onStorefront,
  });

  final VoidCallback onDigiKey;
  final VoidCallback onMouser;
  final VoidCallback onWest3D;
  final VoidCallback onLdo, onAdafruit;
  final ValueChanged<Storefront> onStorefront;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const Key('supplier-search-menu'),
    onPressed: () async {
      FocusManager.instance.primaryFocus?.unfocus();
      final select = await showDialog<VoidCallback>(
        context: context,
        builder: (_) => _SupplierPicker(suppliers: this),
      );
      if (context.mounted) select?.call();
    },
    icon: const Icon(Icons.search),
    label: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text('Search suppliers')),
        SizedBox(width: 8),
        Icon(Icons.expand_more),
      ],
    ),
  );
}

class _SupplierPicker extends StatefulWidget {
  const _SupplierPicker({required this.suppliers});
  final SupplierSearchMenu suppliers;
  @override
  State<_SupplierPicker> createState() => _SupplierPickerState();
}

class _SupplierPickerState extends State<_SupplierPicker> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(580.0, math.max(160.0, size.width - 32));
    final columns = width >= 520 ? 3 : (width >= 260 ? 2 : 1);
    final tileWidth = (width - 16) / columns;
    final query = _normalize(_filter.text);
    final allProviders =
        <({String id, String name, Widget logo, VoidCallback select})>[
          (
            id: 'digikey',
            name: 'DigiKey',
            logo: _logo('digikey-logo-transparent.png'),
            select: widget.suppliers.onDigiKey,
          ),
          (
            id: 'mouser',
            name: 'Mouser',
            logo: _logo('mouser-logo.png', liftDarkInk: true),
            select: widget.suppliers.onMouser,
          ),
          (
            id: 'west3d',
            name: 'West3D',
            logo: const _West3DLogo(),
            select: widget.suppliers.onWest3D,
          ),
          (
            id: 'ldo',
            name: 'LDO Motion',
            logo: _logo('ldo-logo.png', liftDarkInk: true),
            select: widget.suppliers.onLdo,
          ),
          (
            id: 'adafruit',
            name: 'Adafruit',
            logo: const Text('Adafruit'),
            select: widget.suppliers.onAdafruit,
          ),
          for (final store in Storefront.values.where(
            (s) => s != Storefront.west3d && s != Storefront.ldo,
          ))
            (
              id: store.name,
              name: store.label,
              logo: _storeLogo(store),
              select: () => widget.suppliers.onStorefront(store),
            ),
        ];
    final providers = allProviders
        .where((provider) => _normalize(provider.name).contains(query))
        .toList();
    return Dialog(
      key: const Key('supplier-import-actions'),
      alignment: Alignment.center,
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        key: const Key('supplier-provider-panel'),
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(
              140,
              size.height - MediaQuery.viewInsetsOf(context).bottom - 32,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${allProviders.length} search providers',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                TextField(
                  key: const Key('supplier-filter'),
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Find supplier',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _filter.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear supplier filter',
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(_filter.clear),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    primary: false,
                    child: providers.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No matching suppliers'),
                          )
                        : Wrap(
                            children: [
                              for (final provider in providers)
                                SizedBox(
                                  width: tileWidth,
                                  height: 90,
                                  child: _entry(
                                    provider.id,
                                    provider.name,
                                    provider.logo,
                                    provider.select,
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _entry(String id, String name, Widget logo, VoidCallback onPressed) =>
      TextButton(
        key: Key('search-$id'),
        onPressed: () => Navigator.of(context).pop(onPressed),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 82),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          visualDensity: VisualDensity.standard,
        ),
        child: Semantics(
          label: 'Search $name',
          excludeSemantics: true,
          child: Center(child: logo),
        ),
      );

  Widget _storeLogo(Storefront store) => _logo(
    '${store.name}-logo.png',
    store: store,
    width: store == Storefront.biqu ? 72 : 120,
    height: 54,
    liftDarkInk: const {
      Storefront.biqu,
      Storefront.pihut,
      Storefront.slice,
      Storefront.printingcanada,
      Storefront.petgusa,
      Storefront.mandala,
      Storefront.microswiss,
      Storefront.protopasta,
      Storefront.m5stack,
      Storefront.rakwireless,
      Storefront.pimoroni,
      Storefront.arduino,
      Storefront.voxelpla,
      Storefront.americanfilament,
      Storefront.alpenglow,
      Storefront.dremc,
      Storefront.elektor,
      Storefront.printedsolid,
    }.contains(store),
  );

  Widget _logo(
    String asset, {
    Storefront? store,
    double width = 100,
    double height = 40,
    bool liftDarkInk = false,
  }) {
    if (store != null) {
      final suffix =
          const {
            Storefront.sainsmart,
            Storefront.slice,
            Storefront.printedsolid,
            Storefront.pihut,
          }.contains(store)
          ? '-transparent'
          : '';
      asset = '${store.name}-logo$suffix.png';
    }
    Widget logo = Image.asset(
      'assets/images/$asset',
      width: width,
      height: height,
      fit: BoxFit.contain,
    );
    if (liftDarkInk && Theme.of(context).brightness == Brightness.dark) {
      // Lift dark ink for contrast on the tile, preserving hue and alpha.
      logo = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          .5,
          0,
          0,
          0,
          127,
          0,
          .5,
          0,
          0,
          127,
          0,
          0,
          .5,
          0,
          127,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: logo,
      );
    }
    return Padding(padding: const EdgeInsets.all(6), child: logo);
  }
}

class _West3DLogo extends StatelessWidget {
  const _West3DLogo();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 100,
    height: 62,
    child: FittedBox(
      fit: BoxFit.contain,
      // The official 280 x 281 asset has transparent margins above and below
      // its artwork. Frame the complete mark and tagline without stretching it.
      child: SizedBox(
        width: 280,
        height: 171,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: 0,
              top: -75,
              width: 280,
              height: 281,
              child: Image.asset(
                'assets/images/west3d-logo.png',
                semanticLabel: 'West3D',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
