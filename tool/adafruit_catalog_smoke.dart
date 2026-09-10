import 'dart:io';
import 'package:inventorinator/adafruit.dart';
import 'package:inventorinator/adafruit_catalog.dart';

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp('adafruit-catalog-smoke-');
  final catalog = AdafruitCatalog('${directory.path}/catalog.db');
  final client = AdafruitClient();
  try {
    await catalog.refresh(client);
    final page = catalog.search('feather');
    stdout.writeln('${catalog.count} catalog products; ${page.total} feather matches; ${page.parts.length} loaded.');
    if (page.parts.isEmpty) throw StateError('No search results');
    stdout.writeln(page.parts.first.itemName);
  } finally {
    catalog.close(); client.close(); await directory.delete(recursive: true);
  }
}
