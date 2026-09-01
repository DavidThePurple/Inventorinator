import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const filamentColorsAttributionUrl = 'https://filamentcolors.xyz/';

class FilamentColorSwatch {
  const FilamentColorSwatch({
    required this.id,
    required this.name,
    required this.hex,
    required this.manufacturer,
    required this.filamentType,
    required this.material,
    required this.sourceUrl,
    this.hotEndTemperature = '',
    this.bedTemperature = '',
    this.purchaseUrl = '',
    this.notes = '',
  });

  final int id;
  final String name;
  final String hex;
  final String manufacturer;
  final String filamentType;
  final String material;
  final String sourceUrl;
  final String hotEndTemperature;
  final String bedTemperature;
  final String purchaseUrl;
  final String notes;

  factory FilamentColorSwatch.fromJson(Map<String, dynamic> json) {
    final manufacturer =
        json['manufacturer'] as Map<String, dynamic>? ?? const {};
    final filamentType =
        json['filament_type'] as Map<String, dynamic>? ?? const {};
    final parentType =
        filamentType['parent_type'] as Map<String, dynamic>? ?? const {};
    final id = (json['id'] as num?)?.toInt() ?? 0;
    final rawHex = (json['hex_color'] as String? ?? '').trim();
    final hex = rawHex.startsWith('#') ? rawHex : '#$rawHex';
    if (id <= 0 ||
        (json['color_name'] as String? ?? '').trim().isEmpty ||
        !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) {
      throw const FormatException('Invalid FilamentColors.xyz swatch.');
    }
    return FilamentColorSwatch(
      id: id,
      name: (json['color_name'] as String).trim(),
      hex: hex.toUpperCase(),
      manufacturer: (manufacturer['name'] as String? ?? '').trim(),
      filamentType: (filamentType['name'] as String? ?? '').trim(),
      material: (parentType['name'] as String? ?? '').trim(),
      sourceUrl: 'https://filamentcolors.xyz/swatch/$id/',
      hotEndTemperature: (filamentType['hot_end_temp']?.toString() ?? '')
          .trim(),
      bedTemperature: (filamentType['bed_temp']?.toString() ?? '').trim(),
      purchaseUrl:
          (json['mfr_purchase_link'] as String? ?? '').trim().isNotEmpty
          ? (json['mfr_purchase_link'] as String).trim()
          : (json['amazon_purchase_link'] as String? ?? '').trim(),
      notes: (json['notes'] as String? ?? '').trim(),
    );
  }
}

class FilamentColorsException implements Exception {
  const FilamentColorsException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef FilamentColorsCacheRead = String? Function(String key);
typedef FilamentColorsCacheWrite = void Function(String key, String value);
typedef FilamentColorsDelay = Future<void> Function(Duration duration);

class FilamentColorsClient {
  FilamentColorsClient({
    http.Client? httpClient,
    this.cacheRead,
    this.cacheWrite,
    this.cacheLifetime = const Duration(days: 7),
    this.minimumRequestInterval = const Duration(seconds: 2),
    this.maximumRequestsPerWindow = 10,
    this.requestWindow = const Duration(minutes: 1),
    DateTime Function()? clock,
    FilamentColorsDelay? delay,
  }) : _http = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  static final Uri _endpoint = Uri.parse(
    'https://filamentcolors.xyz/api/swatch/',
  );
  static const _requestTimeout = Duration(seconds: 15);

  final http.Client _http;
  final bool _ownsClient;
  final DateTime Function() _clock;
  final FilamentColorsDelay _delay;
  final FilamentColorsCacheRead? cacheRead;
  final FilamentColorsCacheWrite? cacheWrite;
  final Duration cacheLifetime;
  final Duration minimumRequestInterval;
  final int maximumRequestsPerWindow;
  final Duration requestWindow;
  final List<DateTime> _requestTimes = [];
  final Map<String, Future<List<FilamentColorSwatch>>> _inFlight = {};
  Future<void> _permitQueue = Future.value();
  DateTime? _lastRequestAt;
  DateTime? _cooldownUntil;

  Future<List<FilamentColorSwatch>> search({
    String brand = '',
    String material = '',
    String query = '',
  }) async {
    final cleanBrand = _cleanTerm(brand);
    final cleanMaterial = _cleanTerm(material);
    final cleanQuery = _cleanTerm(query);
    if (cleanBrand.isEmpty && cleanMaterial.isEmpty && cleanQuery.isEmpty) {
      throw const FilamentColorsException(
        'Enter a brand, material, or color before searching.',
      );
    }
    final parameters = <String, String>{
      'page_size': '50',
      'm': 'manufacturer',
      if (cleanBrand.isNotEmpty) 'manufacturer__name__icontains': cleanBrand,
      if (cleanMaterial.isNotEmpty)
        'filament_type__parent_type__name__icontains': cleanMaterial,
      if (cleanQuery.isNotEmpty) 'q': cleanQuery,
    };
    final uri = _endpoint.replace(queryParameters: parameters);
    final cacheKey = 'filamentcolors:${uri.query.toLowerCase()}';
    final cached = _readCache(cacheKey);
    if (cached != null && !cached.isExpired) return _parse(cached.body);

    final pending = _inFlight[cacheKey];
    if (pending != null) return pending;
    final request = _fetch(uri, cacheKey, cached);
    _inFlight[cacheKey] = request;
    try {
      return await request;
    } finally {
      if (identical(_inFlight[cacheKey], request)) _inFlight.remove(cacheKey);
    }
  }

  Future<List<FilamentColorSwatch>> _fetch(
    Uri uri,
    String cacheKey,
    _CachedResponse? cached,
  ) async {
    try {
      await _acquirePermit();
      final response = await _http
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'Inventorinator/1.0 (+https://github.com/DavidThePurple/Inventorinator)',
            },
          )
          .timeout(_requestTimeout);
      if (response.statusCode == 429) {
        final retryAfter = _retryAfter(response.headers['retry-after']);
        _cooldownUntil = _clock().add(retryAfter);
        throw FilamentColorsException(
          'FilamentColors.xyz asked us to slow down. Try again in ${retryAfter.inSeconds} seconds.',
        );
      }
      if (response.statusCode != 200) {
        throw FilamentColorsException(
          'FilamentColors.xyz returned HTTP ${response.statusCode}.',
        );
      }
      final results = _parse(response.body);
      cacheWrite?.call(
        cacheKey,
        jsonEncode({
          'savedAt': _clock().toUtc().toIso8601String(),
          'body': response.body,
        }),
      );
      return results;
    } on FilamentColorsException {
      if (cached != null) return _parse(cached.body);
      rethrow;
    } on TimeoutException {
      if (cached != null) return _parse(cached.body);
      throw const FilamentColorsException(
        'FilamentColors.xyz took too long to respond.',
      );
    } catch (_) {
      if (cached != null) return _parse(cached.body);
      throw const FilamentColorsException(
        'Could not reach FilamentColors.xyz.',
      );
    }
  }

  String _cleanTerm(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _acquirePermit() {
    final previous = _permitQueue;
    final released = Completer<void>();
    _permitQueue = released.future;
    return () async {
      await previous;
      try {
        var now = _clock();
        final cooldown = _cooldownUntil;
        if (cooldown != null && cooldown.isAfter(now)) {
          final seconds = cooldown.difference(now).inSeconds + 1;
          throw FilamentColorsException(
            'FilamentColors.xyz is cooling down. Try again in $seconds seconds.',
          );
        }
        _requestTimes.removeWhere(
          (time) => now.difference(time) >= requestWindow,
        );
        if (_requestTimes.length >= maximumRequestsPerWindow) {
          final retryAt = _requestTimes.first.add(requestWindow);
          final seconds = retryAt.difference(now).inSeconds + 1;
          throw FilamentColorsException(
            'Search limit reached. Try again in $seconds seconds; cached searches still work.',
          );
        }
        final lastRequest = _lastRequestAt;
        if (lastRequest != null) {
          final wait = minimumRequestInterval - now.difference(lastRequest);
          if (wait > Duration.zero) await _delay(wait);
        }
        now = _clock();
        _requestTimes.add(now);
        _lastRequestAt = now;
      } finally {
        released.complete();
      }
    }();
  }

  Duration _retryAfter(String? value) {
    final seconds = int.tryParse(value?.trim() ?? '');
    if (seconds != null && seconds > 0) return Duration(seconds: seconds);
    if (value != null) {
      final date = DateTime.tryParse(value)?.toUtc();
      if (date != null) {
        final difference = date.difference(_clock().toUtc());
        if (difference > Duration.zero) return difference;
      }
    }
    return const Duration(minutes: 1);
  }

  _CachedResponse? _readCache(String key) {
    final source = cacheRead?.call(key);
    if (source == null || source.isEmpty) return null;
    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      final savedAt = DateTime.parse(json['savedAt'] as String);
      return _CachedResponse(
        body: json['body'] as String,
        isExpired: _clock().difference(savedAt) > cacheLifetime,
      );
    } catch (_) {
      return null;
    }
  }

  List<FilamentColorSwatch> _parse(String source) {
    final root = jsonDecode(source) as Map<String, dynamic>;
    final rows = (root['results'] as List? ?? const []);
    final results = <FilamentColorSwatch>[];
    for (final row in rows) {
      try {
        results.add(
          FilamentColorSwatch.fromJson((row as Map).cast<String, dynamic>()),
        );
      } on FormatException {
        // Skip malformed upstream records without losing the valid results.
      }
    }
    return results;
  }

  void close() {
    if (_ownsClient) _http.close();
  }
}

class _CachedResponse {
  const _CachedResponse({required this.body, required this.isExpired});

  final String body;
  final bool isExpired;
}
