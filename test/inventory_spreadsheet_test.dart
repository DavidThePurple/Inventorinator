import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventorinator/inventory_spreadsheet.dart';

void main() {
  const awkward = [
    ['Name', 'Notes', 'Quantity'],
    ['PLA, matte "black"', 'line one\nline two', '3'],
    ['  padded  ', '', '0.5'],
    ['Überfilament 日本', 'semi;colon', '12'],
  ];

  test('CSV round-trips quotes, delimiters, line breaks and padding', () {
    final encoded = encodeCsv(awkward);
    expect(encoded.startsWith('﻿'), isTrue);
    expect(decodeCsv(encoded), awkward);
  });

  test('CSV detects semicolon and tab delimiters', () {
    expect(decodeCsv('Name;Qty\nBolt;4\n'), [
      ['Name', 'Qty'],
      ['Bolt', '4'],
    ]);
    expect(decodeCsv('Name\tQty\r\nBolt\t4'), [
      ['Name', 'Qty'],
      ['Bolt', '4'],
    ]);
  });

  test('XLSX round-trips text, numbers, booleans and gaps', () {
    final bytes = encodeXlsx([
      ['Name', 'Quantity', 'AMS'],
      ['PLA <matte> & "black"', 3, true],
      ['Überfilament 日本', 0.5, null],
    ]);
    expect(decodeXlsx(bytes), [
      ['Name', 'Quantity', 'AMS'],
      ['PLA <matte> & "black"', '3', 'true'],
      ['Überfilament 日本', '0.5'],
    ]);
  });

  test('XLSX reads shared strings and cell references from other apps', () {
    // A minimal workbook as spreadsheet apps write it: shared strings, a
    // skipped column (B) and a skipped row (2).
    const sheet =
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetData>'
        '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>'
        '<row r="3"><c r="A3" t="s"><v>2</v></c><c r="C3"><v>7</v></c></row>'
        '</sheetData></worksheet>';
    const strings =
        '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<si><t>Name</t></si><si><t>Qty</t></si>'
        '<si><r><t>Rich </t></r><r><t>text</t></r></si></sst>';
    final archive = Archive()
      ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', sheet))
      ..addFile(ArchiveFile.string('xl/sharedStrings.xml', strings));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    expect(decodeXlsx(bytes), [
      ['Name', '', 'Qty'],
      <String>[],
      ['Rich text', '', '7'],
    ]);
  });

  test('a non-XLSX file is rejected clearly', () {
    expect(
      () => decodeXlsx(Uint8List.fromList(utf8.encode('not a zip'))),
      throwsFormatException,
    );
  });

  test('spreadsheets decode to a padded header and data rows', () {
    final table = decodeInventorySpreadsheet(
      Uint8List.fromList(utf8.encode('Name,Qty,Extra\nBolt,4\n\n,,\n')),
      'stock.csv',
    );
    expect(table.headers, ['Name', 'Qty', 'Extra']);
    expect(table.rows, [
      ['Bolt', '4', ''],
    ]);
  });

  test('column mapping is guessed from headers, each field once', () {
    expect(
      guessSpreadsheetMapping([
        'Item Name',
        'QTY',
        'Unit Price',
        'Colour',
        'Notes',
        'Name',
      ]),
      [
        InventorySpreadsheetField.name,
        InventorySpreadsheetField.quantity,
        InventorySpreadsheetField.cost,
        InventorySpreadsheetField.color,
        null,
        null,
      ],
    );
  });

  test('mapped rows become importer rows and skip blank lines', () {
    const table = SpreadsheetTable(
      headers: ['Name', 'Ignored', 'Qty'],
      rows: [
        ['Bolt', 'x', '4'],
        ['', '', ''],
      ],
    );
    expect(
      spreadsheetRowsToInventoryJson(table, [
        InventorySpreadsheetField.name,
        null,
        InventorySpreadsheetField.quantity,
      ]),
      [
        {'name': 'Bolt', 'quantity': '4'},
      ],
    );
  });
}
