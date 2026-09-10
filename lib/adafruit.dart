import 'dart:convert';
import 'dart:io' show HttpDate, File;

import 'package:http/http.dart' as http;

import 'supplier_image_url.dart';

class AdafruitException implements Exception {
  const AdafruitException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AdafruitPart {
  AdafruitPart.fromJson(Map<String, dynamic> data)
    : id = '${data['product_id'] ?? ''}',
      itemName = '${data['product_name'] ?? ''}',
      manufacturer = '${data['product_manufacturer'] ?? ''}'.trim().isEmpty
          ? 'Adafruit'
          : '${data['product_manufacturer']}',
      partNumber = '${data['product_mpn'] ?? ''}',
      imageUrl = supplierImageUrl(data['product_image']);
  final String id, itemName, manufacturer, partNumber, imageUrl;
  String get productUrl => 'https://www.adafruit.com/product/$id';
  Map<String, String> get inventoryMetadata => {
    'supplier.adafruit.partNumber': partNumber.isEmpty ? 'ADA$id' : partNumber,
    'supplier.adafruit.productId': id,
    'supplier.adafruit.productUrl': productUrl,
  };
}

/// One shared gate across dialogs. Space requests 13s apart (under 5/minute).
/// Cached lookups are free; failures still consume their request slot.
class AdafruitClient {
  AdafruitClient({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;
  static final shared = AdafruitClient();
  final http.Client _client;
  final DateTime Function() _now;
  DateTime _next = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _started = DateTime.fromMillisecondsSinceEpoch(0);
  bool get requestInFlight => _busy;
  double get cooldownProgress {
    final span = _next.difference(_started).inMilliseconds;
    return span <= 0
        ? 1
        : (1 - _next.difference(_now()).inMilliseconds / span).clamp(0, 1);
  }

  void Function(DateTime)? persistCooldown;
  bool _busy = false;
  final _cache = <String, (DateTime, AdafruitPart)>{};
  final _pending = <String, Future<AdafruitPart>>{};
  int get secondsRemaining {
    final ms = _next.difference(_now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  void restoreCooldown(DateTime? next) {
    if (next != null && next.isAfter(_next)) {
      _started = _now();
      _next = next;
    }
  }

  void _cooldown(DateTime next) {
    if (next.isAfter(_next)) {
      _started = _now();
      _next = next;
    }
    persistCooldown?.call(_next);
  }

  static String? productId(String input) {
    final text = input.trim();
    if (RegExp(r'^[1-9][0-9]{0,8}$').hasMatch(text)) return text;
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !['adafruit.com', 'www.adafruit.com'].contains(uri.host) ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final match = RegExp(r'^/product/([1-9][0-9]{0,8})/?$')
        .firstMatch(uri.path);
    return match?.group(1);
  }

  AdafruitPart? cached(String input) {
    final id = productId(input);
    final entry = _cache[id];
    return entry != null &&
            _now().difference(entry.$1) < const Duration(minutes: 30)
        ? entry.$2
        : null;
  }

  Future<AdafruitPart> lookup(String input) {
    final id = productId(input);
    if (id == null) {
      return Future.error(
        const AdafruitException(
          'Enter an Adafruit product ID or product link.',
        ),
      );
    }
    final hit = cached(input);
    if (hit != null) return Future.value(hit);
    if (_pending[id] != null) return _pending[id]!;
    if (_busy || secondsRemaining > 0) {
      return Future.error(
        AdafruitException('Next lookup available in ${secondsRemaining}s.'),
      );
    }
    _busy = true;
    _cooldown(_now().add(const Duration(seconds: 13)));
    final future = _fetch(id).whenComplete(() {
      _pending.remove(id);
      _busy = false;
    });
    _pending[id] = future;
    return future;
  }

  Future<AdafruitPart> _fetch(String id) async {
    try {
      final response = await _client
          .get(Uri.https('www.adafruit.com', '/api/product/$id'))
          .timeout(const Duration(seconds: 20));
      _checkStatus(response.statusCode, response.headers);
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) throw const FormatException();
      final part = AdafruitPart.fromJson(data);
      if (part.id != id || part.itemName.isEmpty) {
        throw const AdafruitException(
          'Product not found. Check the product ID.',
        );
      }
      _cache.remove(id);
      _cache[id] = (_now(), part);
      while (_cache.length > 32) {
        _cache.remove(_cache.keys.first);
      }
      return part;
    } on AdafruitException {
      rethrow;
    } catch (_) {
      throw const AdafruitException(
        'Could not load Adafruit. Check your connection.',
      );
    }
  }

  void _checkStatus(int status, Map<String, String> headers) {
    if (status == 429) {
      final retry = headers['retry-after'];
      var seconds = int.tryParse(retry ?? '');
      if (seconds == null && retry != null) {
        try {
          seconds = HttpDate.parse(retry).difference(_now()).inSeconds;
        } catch (_) {
          /* Fall back to one minute. */
        }
      }
      seconds ??= 60;
      _cooldown(_now().add(Duration(seconds: seconds < 13 ? 13 : seconds)));
      throw const AdafruitException(
        'Adafruit requested a pause. Wait for the countdown.',
      );
    }
    if (status == 404) {
      throw const AdafruitException('Product not found. Check the product ID.');
    }
    if (status != 200) {
      throw const AdafruitException(
        'Adafruit is unavailable. Please try later.',
      );
    }
  }

  Future<void> downloadCatalog(File destination) async {
    if (_busy || secondsRemaining > 0) {
      throw AdafruitException(
        'Next download available in ${secondsRemaining}s.',
      );
    }
    _busy = true;
    _cooldown(_now().add(const Duration(seconds: 13)));
    final sink = destination.openWrite();
    try {
      final response = await _client
          .send(
            http.Request('GET', Uri.https('www.adafruit.com', '/api/products')),
          )
          .timeout(const Duration(seconds: 30));
      _checkStatus(response.statusCode, response.headers);
      const maxBytes = 32 * 1024 * 1024;
      if ((response.contentLength ?? 0) > maxBytes) {
        throw const AdafruitException('Catalog download is too large.');
      }
      var received = 0;
      await for (final bytes in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        received += bytes.length;
        if (received > maxBytes) {
          throw const AdafruitException('Catalog download is too large.');
        }
        sink.add(bytes);
        await sink.flush();
      }
    } on AdafruitException {
      rethrow;
    } catch (_) {
      throw const AdafruitException(
        'Could not update Adafruit. Your saved catalog is still available.',
      );
    } finally {
      await sink.close();
      _busy = false;
    }
  }

  void close() => _client.close();
}
