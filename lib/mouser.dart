import 'supplier_image_url.dart';

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class MouserException implements Exception {
  const MouserException(this.message);
  final String message;
  @override
  String toString() => message;
}

String _text(dynamic value) => value is String ? value.trim() : '';
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

class MouserPart {
  const MouserPart({
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
    'supplier.mouser.partNumber': supplierPartNumber,
    'supplier.mouser.manufacturerPartNumber': manufacturerPartNumber,
    'supplier.mouser.description': description,
    'supplier.mouser.category': category,
    'supplier.mouser.packaging': packaging,
    'supplier.mouser.productUrl': productUrl,
    'supplier.mouser.datasheetUrl': datasheetUrl,
    if (minimumOrderQuantity != null)
      'supplier.mouser.minimumOrderQuantity': '$minimumOrderQuantity',
    if (standardPackage != null)
      'supplier.mouser.standardPackage': '$standardPackage',
  };
}

class MouserPage {
  const MouserPage(
    this.parts,
    this.productCount,
    this.offset,
    this.returnedProducts,
  );
  final List<MouserPart> parts;
  final int productCount, offset, returnedProducts;
  bool get hasNext =>
      returnedProducts > 0 && offset + returnedProducts < productCount;
  factory MouserPage.fromJson(Map<String, dynamic> json, {int offset = 0}) {
    if (json['Errors'] is List && (json['Errors'] as List).isNotEmpty) {
      throw const MouserException(
        'Mouser rejected the search. Check your Search API key and usage limit.',
      );
    }
    final results = json['SearchResults'];
    if (results is! Map || results['Parts'] is! List) {
      throw const MouserException(
        'Mouser returned an unexpected search response.',
      );
    }
    final raw = results['Parts'] as List;
    final parts = <MouserPart>[];
    final seen = <String>{};
    for (final part in raw.whereType<Map>()) {
      final sku = _text(part['MouserPartNumber']);
      if (sku.isEmpty || !seen.add(sku)) continue;
      String packaging = '';
      if (part['ProductAttributes'] is List) {
        for (final attr
            in (part['ProductAttributes'] as List).whereType<Map>()) {
          if (attr['AttributeName'] == 'Packaging') {
            packaging = _text(attr['AttributeValue']);
          }
        }
      }
      parts.add(
        MouserPart(
          manufacturerPartNumber: _text(part['ManufacturerPartNumber']),
          supplierPartNumber: sku,
          manufacturer: _text(part['Manufacturer']),
          description: _text(part['Description']),
          category: _text(part['Category']),
          packaging: packaging,
          productUrl: safeProductLink(part['ProductDetailUrl']),
          datasheetUrl: safeProductLink(part['DataSheetUrl']),
          imageUrl: supplierImageUrl(part['ImagePath']),
          currency: '',
          minimumOrderQuantity: int.tryParse('${part['Min']}'),
          available: int.tryParse('${part['AvailabilityInStock']}'),
        ),
      );
    }
    return MouserPage(
      parts,
      (results['NumberOfResult'] as num?)?.toInt() ?? raw.length,
      offset,
      raw.length,
    );
  }
}

class MouserClient {
  MouserClient({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client();
  final String apiKey;
  final http.Client _client;
  void close() => _client.close();
  Future<MouserPage> search(String query, {int offset = 0}) async {
    if (apiKey.trim().isEmpty) {
      throw const MouserException(
        'Enter your Mouser Search API key in Remote Settings.',
      );
    }
    if (query.trim().isEmpty || query.length > 250 || offset < 0) {
      throw const MouserException(
        'Enter a part number or keyword (up to 250 characters).',
      );
    }
    try {
      final response = await _client
          .post(
            Uri.https('api.mouser.com', '/api/v1/search/keyword', {
              'apiKey': apiKey.trim(),
            }),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'SearchByKeywordRequest': {
                'keyword': query.trim(),
                'records': 20,
                'startingRecord': offset,
                'searchOptions': 'None',
              },
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw MouserException(
          response.statusCode == 429
              ? 'Mouser search limit reached. Try again later.'
              : 'Mouser search failed. Check your Search API key and connection.',
        );
      }
      return MouserPage.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
        offset: offset,
      );
    } on MouserException {
      rethrow;
    } on TimeoutException {
      throw const MouserException('Mouser timed out. Try again.');
    } catch (_) {
      // HTTP exception URLs can contain the API key. Never expose them.
      throw const MouserException(
        'Could not connect to Mouser or read its response.',
      );
    }
  }
}
