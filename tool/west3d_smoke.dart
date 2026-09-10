import 'dart:io';
import 'package:inventorinator/west3d.dart';

Future<void> main() async {
  final client = West3DClient();
  try {
    final products = await client.search('ldo');
    if (products.isEmpty) throw StateError('Expected live LDO listings');
    final parts = await client.variants(products.first);
    if (parts.isEmpty) throw StateError('Expected live variants');
    stdout.writeln(
      '${products.length} matches; ${parts.length} variants; ${parts.first.itemName}; SKU ${parts.first.sku}',
    );
  } finally {
    client.close();
  }
}
