import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/kit_package.dart';

void main() {
  test('example kit package validates and preserves its BOM structure', () {
    final source = File('examples/example.inventorinator-kit.json')
        .readAsStringSync();
    final result = parseInventorinatorKitPackage(source);

    expect(result.errors, isEmpty);
    expect(result.package, isNotNull);
    expect(result.package!.name, 'Example Printer Kit');
    expect(result.package!.sections.map((section) => section.name), [
      'Frame',
      'Toolhead',
    ]);
    expect(result.package!.parts.length, 2);
    expect(result.package!.parts.first.quantity, 12);
    expect(
      result.package!.parts.first.sources.single.url,
      contains('https://'),
    );
    expect(result.package!.machines.single.name, 'Example Printer');
  });

  test(
    'invalid references, quantities, types, and source URLs are rejected',
    () {
      final result = parseInventorinatorKitPackage(
        jsonEncode({
          'format': inventorinatorKitPackageFormat,
          'schemaVersion': inventorinatorKitPackageSchemaVersion,
          'id': 'bad-package',
          'name': 'Bad package',
          'sections': [
            {'id': 'frame', 'name': 'Frame'},
          ],
          'parts': [
            {
              'id': 'bad-part',
              'name': 'Bad part',
              'type': 'imaginaryType',
              'section': 'missing-section',
              'quantity': 0,
              'sources': [
                {'url': 'file:///tmp/not-allowed'},
              ],
            },
          ],
        }),
      );

      expect(result.package, isNull);
      expect(result.errors, contains(contains('unsupported type')));
      expect(result.errors, contains(contains('unknown section')));
      expect(result.errors, contains(contains('greater than 0')));
      expect(result.errors, contains(contains('valid HTTP(S) URL')));
    },
  );

  test('duplicate stable ids are rejected', () {
    final result = parseInventorinatorKitPackage(
      jsonEncode({
        'format': inventorinatorKitPackageFormat,
        'schemaVersion': inventorinatorKitPackageSchemaVersion,
        'id': 'duplicates',
        'name': 'Duplicate test',
        'sections': [
          {'id': 'main', 'name': 'Main'},
          {'id': 'main', 'name': 'Again'},
        ],
        'parts': [
          {
            'id': 'part',
            'name': 'Part one',
            'type': 'other',
            'section': 'main',
            'quantity': 1,
          },
          {
            'id': 'part',
            'name': 'Part two',
            'type': 'other',
            'section': 'main',
            'quantity': 1,
          },
        ],
      }),
    );

    expect(result.package, isNull);
    expect(result.errors, contains(contains('repeats section id')));
    expect(result.errors, contains(contains('repeats part id')));
  });
}
