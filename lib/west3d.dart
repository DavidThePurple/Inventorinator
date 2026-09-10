import 'supplier_image_url.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;

enum Storefront {
  west3d('West3D', 'west3d.com'),
  ldo('LDO', 'store.ldomotion.com'),
  biqu('BIQU / BIGTREETECH', 'biqu.equipment'),
  e3d('E3D', 'e3d-online.com'),
  polymaker('Polymaker', 'us.polymaker.com'),
  printedsolid('Printed Solid', 'www.printedsolid.com'),
  slice('Slice Engineering', 'www.sliceengineering.com'),
  fabreeko('Fabreeko', 'www.fabreeko.com'),
  pihut('The Pi Hut', 'thepihut.com'),
  fillamentum('Fillamentum', 'shop.fillamentum.com'),
  sovol('Sovol', 'www.sovol3d.com'),
  siraya('Siraya Tech', 'siraya.tech'),
  microswiss('Micro Swiss', 'store.micro-swiss.com'),
  atomic('Atomic Filament', 'atomicfilament.com'),
  matter3d('Matter3D', 'www.matter3d.com'),
  mandala('Mandala Rose Works', 'mandalaroseworks.com'),
  ember('Ember Prototypes', 'emberprototypes.myshopify.com'),
  protopasta('Protopasta', 'proto-pasta.com'),
  fysetc('FYSETC', 'www.fysetc.com'),
  petgusa('PETG USA', 'petgusa.com'),
  sainsmart('SainSmart / Genmitsu', 'www.sainsmart.com'),
  printingcanada('3D Printing Canada', '3dprintingcanada.com'),
  m5stack('M5Stack', 'shop.m5stack.com'),
  rakwireless('RAKwireless', 'store.rakwireless.com'),
  dfh('DFH', 'checkout.dfh.fm'),
  overture('Overture', 'overture3d.com'),
  pimoroni('Pimoroni', 'shop.pimoroni.com'),
  arduino('Arduino', 'store.arduino.cc'),
  inventables('Inventables', 'www.inventables.com'),
  pushplastic('Push Plastic', 'www.pushplastic.com'),
  voxelpla('VOXELPLA', 'voxelpla.com'),
  fuel3d('3D-Fuel', 'www.3dfuel.com'),
  americanfilament('American Filament', 'www.americanfilament.us'),
  sequre('SEQURE', 'sequremall.com'),
  alpenglow('Alpenglow Industries', 'alpenglowindustries.com'),
  bantam('Bantam Tools', 'bantamtools.com'),
  dremc('DREMC', 'store.dremc.com.au'),
  cookiecad('Cookiecad', 'www.cookiecad.com'),
  revopoint('Revopoint', 'www.revopoint3d.com'),
  tinycircuits('TinyCircuits', 'tinycircuits.com'),
  hackerboxes('HackerBoxes', 'hackerboxes.com'),
  elektor('Elektor', 'www.elektor.com');

  const Storefront(this.label, this.host);
  final String label, host;
}

class West3DException implements Exception {
  const West3DException(this.message);
  final String message;
  @override
  String toString() => message;
}

class West3DProduct {
  West3DProduct.fromJson(Map<String, dynamic> data)
    : handle = data['handle'] as String,
      title = data['title'] as String,
      vendor = data['vendor'] as String? ?? '',
      category = (data['type'] ?? data['product_type']) as String? ?? '',
      imageUrl = supplierImageUrl(data['featured_image'] ?? data['image']);
  final String handle, title, vendor, category, imageUrl;
}

class West3DPart {
  West3DPart(
    this.product,
    Map<String, dynamic> variant, {
    this.store = Storefront.west3d,
  }) : id = '${variant['id']}',
       sku = variant['sku'] as String? ?? '',
       variantTitle =
           variant['public_title'] as String? ??
           variant['title'] as String? ??
           '',
       available = variant['available'] == true,
       price = (variant['price'] as num?)?.toDouble(),
       imageUrl = supplierImageUrl(variant['featured_image']).isNotEmpty
           ? supplierImageUrl(variant['featured_image'])
           : product.imageUrl;
  final West3DProduct product;
  final Storefront store;
  final String id, sku, variantTitle, imageUrl;
  final bool available;
  // Shopify's product Ajax endpoint returns prices in minor currency units.
  final double? price;
  String get itemName => variantTitle.isEmpty || variantTitle == 'Default Title'
      ? product.title
      : '${product.title} — $variantTitle';
  String get productUrl => Uri.https(
    store.host,
    '/products/${product.handle}',
    {'variant': id},
  ).toString();
  Map<String, String> get inventoryMetadata => {
    'supplier.${store.name}.variantId': id,
    'supplier.${store.name}.partNumber': sku,
    'supplier.${store.name}.productUrl': productUrl,
    'supplier.${store.name}.category': product.category,
    'supplier.${store.name}.variant': variantTitle,
  };
}

class West3DClient {
  West3DClient({http.Client? client, this.store = Storefront.west3d})
    : _client = client ?? http.Client();
  final http.Client _client;
  final Storefront store;
  void close() => _client.close();
  Future<Map<String, dynamic>> _get(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw West3DException(
          '${store.label} is unavailable. Please try again.',
        );
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on West3DException {
      rethrow;
    } catch (_) {
      throw West3DException(
        'Could not read ${store.label} listings. Check your connection and try again.',
      );
    }
  }

  Future<List<West3DProduct>> search(String query) async {
    if (query.trim().isEmpty || query.length > 250) {
      throw const West3DException(
        'Enter keywords or a SKU (up to 250 characters).',
      );
    }
    final data = await _get(
      Uri.https(store.host, '/search/suggest.json', {
        'q': query.trim(),
        'resources[type]': 'product',
        'resources[limit]': '10',
        'resources[options][fields]':
            'title,product_type,variants.title,vendor,variants.sku',
      }),
    );
    try {
      return (data['resources']['results']['products'] as List)
          .map(
            (p) => West3DProduct.fromJson(Map<String, dynamic>.from(p as Map)),
          )
          .toList();
    } catch (_) {
      throw West3DException(
        '${store.label} returned unexpected search results.',
      );
    }
  }

  Future<List<West3DPart>> variants(West3DProduct product) async {
    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(product.handle)) {
      throw const West3DException('This product link is invalid.');
    }
    final data = await _get(
      Uri.https(store.host, '/products/${product.handle}.js'),
    );
    try {
      final details = West3DProduct.fromJson(data);
      return (data['variants'] as List)
          .map(
            (v) => West3DPart(
              details,
              Map<String, dynamic>.from(v as Map),
              store: store,
            ),
          )
          .toList();
    } catch (_) {
      throw West3DException(
        '${store.label} returned unexpected product details.',
      );
    }
  }
}
