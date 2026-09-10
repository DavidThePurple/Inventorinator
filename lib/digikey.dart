import 'supplier_image_url.dart';

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class DigiKeyException implements Exception {
  const DigiKeyException(this.message);
  final String message;
  @override
  String toString() => message;
}

String _text(dynamic value) => value is String ? value.trim() : '';
Map _map(dynamic value) => value is Map ? value : const {};
String safeProductLink(dynamic value) {
  final text = _text(value);
  final uri = Uri.tryParse(text);
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? text
      : '';
}

class DigiKeyPart {
  const DigiKeyPart({
    required this.manufacturerPartNumber,
    required this.supplierPartNumber,
    required this.manufacturer,
    required this.description,
    this.category = '',
    this.imageUrl = '',
    required this.packaging,
    required this.productUrl,
    required this.datasheetUrl,
    required this.currency,
    this.minimumOrderQuantity,
    this.standardPackage,
    this.available,
    this.unitPrice,
  });
  final String manufacturerPartNumber,
      supplierPartNumber,
      manufacturer,
      description;
  final String packaging, productUrl, datasheetUrl, currency;
  final String category;
  final String imageUrl;
  String get itemName => description.trim().isNotEmpty
      ? description.trim()
      : manufacturerPartNumber.isNotEmpty
      ? manufacturerPartNumber
      : supplierPartNumber;
  final int? minimumOrderQuantity, standardPackage, available;
  final double? unitPrice;

  Map<String, String> get inventoryMetadata => {
    'supplier.digikey.partNumber': supplierPartNumber,
    'supplier.digikey.manufacturerPartNumber': manufacturerPartNumber,
    'supplier.digikey.description': description,
    'supplier.digikey.category': category,
    'supplier.digikey.packaging': packaging,
    'supplier.digikey.productUrl': productUrl,
    'supplier.digikey.datasheetUrl': datasheetUrl,
    if (minimumOrderQuantity != null)
      'supplier.digikey.minimumOrderQuantity': '$minimumOrderQuantity',
    if (standardPackage != null)
      'supplier.digikey.standardPackage': '$standardPackage',
  };
}

class DigiKeyPage {
  const DigiKeyPage(
    this.parts,
    this.productCount,
    this.offset,
    this.returnedProducts,
  );
  final List<DigiKeyPart> parts;
  final int productCount, offset, returnedProducts;
  bool get hasNext =>
      returnedProducts > 0 && offset + returnedProducts < productCount;
  factory DigiKeyPage.fromJson(Map<String, dynamic> json, {int offset = 0}) {
    if (json['Products'] is! List) {
      throw const DigiKeyException(
        'DigiKey returned an unexpected search response.',
      );
    }
    final products = json['Products'] as List;
    final currency = _text(_map(json['SearchLocaleUsed'])['Currency']);
    final parts = <DigiKeyPart>[];
    final seen = <String>{};
    for (final product in products.whereType<Map>()) {
      final variations = product['ProductVariations'];
      if (variations is! List) continue;
      for (final variation in variations.whereType<Map>()) {
        final sku = _text(variation['DigiKeyProductNumber']);
        if (sku.isEmpty || !seen.add(sku)) continue;
        final pricing = variation['StandardPricing'];
        final breaks = pricing is List
            ? pricing.whereType<Map>().where((p) => p['BreakQuantity'] == 1)
            : const <Map>[];
        final price = breaks.isEmpty ? null : breaks.first['UnitPrice'];
        parts.add(
          DigiKeyPart(
            manufacturerPartNumber: _text(product['ManufacturerProductNumber']),
            supplierPartNumber: sku,
            manufacturer: _text(_map(product['Manufacturer'])['Name']),
            description: _text(
              _map(product['Description'])['ProductDescription'],
            ),
            category: _text(_map(product['Category'])['Name']),
            packaging: _text(_map(variation['PackageType'])['Name']),
            productUrl: safeProductLink(product['ProductUrl']),
            datasheetUrl: safeProductLink(product['DatasheetUrl']),
            imageUrl: supplierImageUrl(product['PhotoUrl']),
            currency: currency,
            unitPrice: price is num && price >= 0 ? price.toDouble() : null,
            minimumOrderQuantity: (variation['MinimumOrderQuantity'] as num?)
                ?.toInt(),
            standardPackage: (variation['StandardPackage'] as num?)?.toInt(),
            available: (variation['QuantityAvailableforPackageType'] as num?)
                ?.toInt(),
          ),
        );
      }
    }
    return DigiKeyPage(
      parts,
      (json['ProductsCount'] as num?)?.toInt() ?? products.length,
      offset,
      products.length,
    );
  }
}

/// User-supplied credentials stay in memory. Never export or embed app secrets.
class DigiKeyClient {
  DigiKeyClient({
    required this.clientId,
    required this.clientSecret,
    this.sandbox = false,
    http.Client? client,
  }) : _client = client ?? http.Client();
  final String clientId, clientSecret;
  final bool sandbox;
  final http.Client _client;
  String? _token;
  DateTime? _expires;
  String get _host => sandbox ? 'sandbox-api.digikey.com' : 'api.digikey.com';
  void close() {
    _token = null;
    _client.close();
  }

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DigiKeyException(switch (response.statusCode) {
        400 => 'DigiKey rejected the request. Check the search and API application settings.',
        401 || 403 => 'DigiKey access was denied. Check your credentials and Product Information V4 subscription.',
        429 => 'DigiKey’s request limit was reached. Please try again later.',
        _ =>
          'DigiKey is unavailable (HTTP ${response.statusCode}). Please try again later.',
      });
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const DigiKeyException('DigiKey returned an unexpected response.');
    }
    return body;
  }

  Future<DigiKeyPage> search(String query, {int offset = 0}) async {
    final keywords = query.trim();
    if (keywords.isEmpty || keywords.length > 250 || offset < 0) {
      throw const DigiKeyException(
        'Enter a part number or keywords (up to 250 characters).',
      );
    }
    if (clientId.trim().isEmpty || clientSecret.trim().isEmpty) {
      throw const DigiKeyException(
        'Enter your DigiKey developer client ID and secret to search.',
      );
    }
    try {
      if (_token == null || !_expires!.isAfter(DateTime.now())) {
        final auth = await _decode(
          await _client
              .post(
                Uri.https(_host, '/v1/oauth2/token'),
                body: {
                  'client_id': clientId.trim(),
                  'client_secret': clientSecret.trim(),
                  'grant_type': 'client_credentials',
                },
              )
              .timeout(const Duration(seconds: 20)),
        );
        final token = auth['access_token'];
        if (token is! String || token.isEmpty) {
          throw const DigiKeyException(
            'DigiKey did not return an access token.',
          );
        }
        _token = token;
        final seconds = (auth['expires_in'] as num?)?.toInt() ?? 0;
        _expires = DateTime.now().add(
          Duration(seconds: seconds > 30 ? seconds - 30 : 0),
        );
      }
      final response = await _client
          .post(
            Uri.https(_host, '/products/v4/search/keyword'),
            headers: {
              'Authorization': 'Bearer $_token',
              'X-DIGIKEY-Client-Id': clientId.trim(),
              'X-DIGIKEY-Locale-Site': 'US',
              'X-DIGIKEY-Locale-Language': 'en',
              'X-DIGIKEY-Locale-Currency': 'USD',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'Keywords': keywords,
              'Limit': 20,
              'Offset': offset,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401) _token = null;
      return DigiKeyPage.fromJson(await _decode(response), offset: offset);
    } on TimeoutException {
      throw const DigiKeyException(
        'DigiKey timed out. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const DigiKeyException(
        'Could not reach DigiKey. Check your connection and try again.',
      );
    } on FormatException {
      throw const DigiKeyException(
        'DigiKey returned an unreadable response. Please try again later.',
      );
    }
  }
}
