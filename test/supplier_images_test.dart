import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:inventorinator/supplier_images.dart';
import 'package:inventorinator/supplier_image_url.dart';
import 'package:inventorinator/digikey.dart';
import 'package:inventorinator/mouser.dart';
import 'package:inventorinator/west3d.dart';

import 'digikey_test.dart' show digiKeyFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final png = img.encodePng(img.Image(width: 1200, height: 600));
  test(
    'deduplicates requests and reuses resized photo and thumbnail',
    () async {
      var calls = 0;
      final cache = SupplierImageCache(
        clientFactory: () => MockClient((request) async {
          calls++;
          expect(request.headers.containsKey('Authorization'), false);
          return http.Response.bytes(png, 200);
        }),
      );
      const url = 'https://example.com/photo.png';
      final results = await Future.wait([cache.load(url), cache.load(url)]);
      expect(calls, 1);
      expect(results[0], same(results[1]));
      expect(img.decodePng(results[0]!.bytes)!.width, 1024);
      expect(img.decodePng(results[0]!.thumbnail)!.width, 256);
      expect(await cache.load(url), same(results[0]));
      expect(calls, 1);
    },
  );
  test('limits concurrent downloads to two', () async {
    var active = 0, peak = 0;
    final cache = SupplierImageCache(
      clientFactory: () => MockClient((_) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        active--;
        return http.Response.bytes(png, 200);
      }),
    );
    await Future.wait(
      List.generate(5, (i) => cache.load('https://example.com/$i.png')),
    );
    expect(peak, 2);
  });
  test('caches failures and rejects invalid or oversized data', () async {
    var calls = 0;
    final cache = SupplierImageCache(
      clientFactory: () => MockClient((request) async {
        calls++;
        if (request.url.path == '/large') {
          return http.Response.bytes(
            Uint8List(SupplierImageCache.maxDownloadBytes + 1),
            200,
          );
        }
        return http.Response('not an image', 200);
      }),
    );
    expect(await cache.load('https://example.com/bad'), isNull);
    expect(await cache.load('https://example.com/bad'), isNull);
    expect(calls, 1);
    expect(await cache.load('https://example.com/large'), isNull);
    expect(await cache.load('http://example.com/photo'), isNull);
    expect(await cache.load('https://secret@example.com/photo'), isNull);
    expect(calls, 2);
  });
  test('reads supplier image fields and prefers variant image', () {
    expect(
      supplierImageUrl({'src': '//cdn.shopify.com/image.png'}),
      'https://cdn.shopify.com/image.png',
    );
    final product = West3DProduct.fromJson({
      'handle': 'part',
      'title': 'Part',
      'featured_image': '//cdn.shopify.com/base.png',
    });
    expect(West3DPart(product, {'id': 1}).imageUrl, product.imageUrl);
    expect(
      West3DPart(product, {
        'id': 2,
        'featured_image': {'src': '//cdn.shopify.com/variant.png'},
      }).imageUrl,
      'https://cdn.shopify.com/variant.png',
    );
    final digi = digiKeyFixture();
    (digi['Products'] as List).first['PhotoUrl'] =
        'https://example.com/digi.jpg';
    expect(
      DigiKeyPage.fromJson(digi).parts.first.imageUrl,
      'https://example.com/digi.jpg',
    );
    final mouser = MouserPage.fromJson({
      'SearchResults': {
        'Parts': [
          {
            'MouserPartNumber': '123',
            'ImagePath': 'https://example.com/mouser.jpg',
          },
        ],
      },
    });
    expect(mouser.parts.single.imageUrl, 'https://example.com/mouser.jpg');
  });
}
