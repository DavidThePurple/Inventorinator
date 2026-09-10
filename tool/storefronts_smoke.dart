import 'dart:io';

import 'package:inventorinator/west3d.dart';

Future<void> main(List<String> args) async {
  for (final entry in {
    Storefront.biqu: 'skr',
    Storefront.e3d: 'revo',
    Storefront.polymaker: 'pla',
    Storefront.printedsolid: 'jessie',
    Storefront.slice: 'mosquito',
    Storefront.fabreeko: 'voron',
    Storefront.pihut: 'sensor',
    Storefront.fillamentum: 'pla',
    Storefront.sovol: 'nozzle',
    Storefront.siraya: 'resin',
    Storefront.microswiss: 'nozzle',
    Storefront.atomic: 'petg',
    Storefront.matter3d: 'pla',
    Storefront.mandala: 'voron',
    Storefront.ember: 'cxc',
    Storefront.protopasta: 'htpla',
    Storefront.fysetc: 'spider',
    Storefront.petgusa: 'matte',
    Storefront.sainsmart: 'end mill',
    Storefront.printingcanada: 'nozzle',
    Storefront.m5stack: 'sensor',
    Storefront.rakwireless: 'sensor',
    Storefront.dfh: 'voron',
    Storefront.overture: 'petg',
    Storefront.pimoroni: 'sensor',
    Storefront.arduino: 'sensor',
    Storefront.inventables: 'bit',
    Storefront.pushplastic: 'petg',
    Storefront.voxelpla: 'pla',
    Storefront.fuel3d: 'pla',
    Storefront.americanfilament: 'petg',
    Storefront.sequre: 'soldering',
    Storefront.alpenglow: 'kit',
    Storefront.bantam: 'end mill',
    Storefront.dremc: 'nozzle',
    Storefront.cookiecad: 'pla',
    Storefront.revopoint: 'scanner',
    Storefront.tinycircuits: 'sensor',
    Storefront.hackerboxes: 'kit',
    Storefront.elektor: 'sensor',
  }.entries) {
    if (args.isNotEmpty && !args.contains(entry.key.name)) continue;
    final client = West3DClient(store: entry.key);
    try {
      final products = await client.search(entry.value);
      if (products.isEmpty) throw StateError('${entry.key.label}: no products');
      final variants = await client.variants(products.first);
      if (variants.isEmpty ||
          variants.first.store != entry.key ||
          Uri.parse(variants.first.productUrl).host != entry.key.host) {
        throw StateError('${entry.key.label}: invalid variants');
      }
      stdout.writeln(
        '${entry.key.label}: ${products.length} matches; ${variants.length} variants; ${variants.first.itemName}',
      );
    } finally {
      client.close();
    }
  }
}
