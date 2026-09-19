import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// A spreadsheet read as text: one header row and the data rows under it.
class SpreadsheetTable {
  const SpreadsheetTable({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;
}

/// Inventory fields a spreadsheet column can be mapped to on import.
///
/// [key] is the column name the inventory JSON importer reads, so mapped
/// spreadsheet rows go through the same validation as JSON imports.
enum InventorySpreadsheetField {
  id('id', 'Item ID', ['id', 'itemid', 'inventoryid']),
  name('name', 'Name', [
    'name',
    'itemname',
    'productname',
    'item',
    'title',
    'description',
  ]),
  type('type', 'Type', ['type', 'itemtype', 'category']),
  quantity('quantity', 'Quantity', ['quantity', 'qty', 'count', 'stock']),
  cost('cost', 'Cost', ['cost', 'price', 'unitcost', 'unitprice']),
  material('material', 'Material', ['material', 'materialtype']),
  color('color', 'Color', ['color', 'colour', 'hex', 'colorhex', 'colourhex']),
  colorName('colorName', 'Color name', [
    'colorname',
    'colourname',
    'colorlabel',
    'colourlabel',
  ]),
  brand('brand', 'Brand', ['brand', 'maker', 'manufacturer']),
  vendor('vendor', 'Vendor', ['vendor', 'supplier', 'store']),
  storageLocation('storageLocation', 'Storage location', [
    'storagelocation',
    'location',
    'bin',
    'shelf',
  ]),
  barcode('barcode', 'Barcode', ['barcode', 'upc', 'ean', 'sku']),
  productUrl('productUrl', 'Product URL', [
    'producturl',
    'url',
    'sourceurl',
    'source',
  ]),
  imageUrl('imageUrl', 'Image URL', [
    'imageurl',
    'productimageurl',
    'photourl',
    'image',
    'productimage',
    'photo',
  ]),
  compatibility('compatibility', 'Compatibility', [
    'compatibility',
    'compatiblewith',
    'compatiblemachines',
  ]),
  amsCompatible('amsCompatible', 'AMS compatible', [
    'amscompatible',
    'amscompatibility',
    'ams',
  ]),
  archived('archived', 'Archived', ['archived', 'isarchived']);

  const InventorySpreadsheetField(this.key, this.label, this.aliases);

  final String key;
  final String label;
  final List<String> aliases;
}

String _normalizeHeader(String header) =>
    header.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Guesses which inventory field each column holds from its header. Each
/// field is assigned to at most one column; unrecognised columns map to null.
List<InventorySpreadsheetField?> guessSpreadsheetMapping(List<String> headers) {
  final taken = <InventorySpreadsheetField>{};
  return [
    for (final header in headers)
      () {
        final normalized = _normalizeHeader(header);
        for (final field in InventorySpreadsheetField.values) {
          if (!taken.contains(field) && field.aliases.contains(normalized)) {
            taken.add(field);
            return field;
          }
        }
        return null;
      }(),
  ];
}

/// Turns mapped spreadsheet rows into inventory JSON rows. Fully blank rows
/// are dropped; unmapped columns are ignored.
List<Map<String, Object?>> spreadsheetRowsToInventoryJson(
  SpreadsheetTable table,
  List<InventorySpreadsheetField?> mapping,
) => [
  for (final row in table.rows)
    if (row.any((cell) => cell.trim().isNotEmpty))
      {
        for (var column = 0; column < mapping.length; column++)
          if (mapping[column] != null && column < row.length)
            mapping[column]!.key: row[column],
      },
];

/// Reads a CSV or XLSX file chosen by its extension.
SpreadsheetTable decodeInventorySpreadsheet(Uint8List bytes, String fileName) {
  final rows = fileName.toLowerCase().endsWith('.xlsx')
      ? decodeXlsx(bytes)
      : decodeCsv(utf8.decode(bytes, allowMalformed: true));
  final nonEmpty = rows
      .where((row) => row.any((cell) => cell.trim().isNotEmpty))
      .toList();
  if (nonEmpty.isEmpty) {
    throw const FormatException('The spreadsheet has no rows.');
  }
  final width = nonEmpty.fold<int>(
    0,
    (widest, row) => row.length > widest ? row.length : widest,
  );
  List<String> padded(List<String> row) => [
    ...row,
    for (var i = row.length; i < width; i++) '',
  ];
  return SpreadsheetTable(
    headers: padded(nonEmpty.first).map((cell) => cell.trim()).toList(),
    rows: [for (final row in nonEmpty.skip(1)) padded(row)],
  );
}

// CSV ------------------------------------------------------------------------

/// Parses CSV per RFC 4180: quoted fields may hold delimiters, doubled quotes
/// and line breaks. The delimiter (comma, semicolon or tab) is detected from
/// the first line, and a leading byte order mark is ignored.
List<List<String>> decodeCsv(String source) {
  var text = source.startsWith('\ufeff') ? source.substring(1) : source;
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final delimiter = _detectCsvDelimiter(text);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var index = 0; index < text.length; index++) {
    final char = text[index];
    if (quoted) {
      if (char == '"') {
        if (index + 1 < text.length && text[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          quoted = false;
        }
      } else {
        field.write(char);
      }
    } else if (char == '"' && field.isEmpty) {
      quoted = true;
    } else if (char == delimiter) {
      row.add(field.toString());
      field.clear();
    } else if (char == '\n') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(char);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

String _detectCsvDelimiter(String text) {
  final newline = text.indexOf('\n');
  final firstLine = newline < 0 ? text : text.substring(0, newline);
  var best = ',';
  var bestCount = 0;
  for (final candidate in const [',', ';', '\t']) {
    final count = candidate.allMatches(firstLine).length;
    if (count > bestCount) {
      best = candidate;
      bestCount = count;
    }
  }
  return best;
}

/// Writes CSV with CRLF line endings, quoting fields that need it. A byte
/// order mark lets spreadsheet apps detect UTF-8.
String encodeCsv(List<List<Object?>> rows) {
  String field(Object? value) {
    final text = value?.toString() ?? '';
    if (text.contains(RegExp(r'[",\r\n]')) || text.trim() != text) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  return '\ufeff${rows.map((row) => row.map(field).join(',')).join('\r\n')}\r\n';
}

// XLSX -----------------------------------------------------------------------

/// Reads the first worksheet of an XLSX workbook as text rows.
List<List<String>> decodeXlsx(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('This is not a readable XLSX workbook.');
  }
  String? read(String path) {
    final file = archive.findFile(path);
    return file == null ? null : utf8.decode(file.content);
  }

  final sharedStrings = <String>[];
  final shared = read('xl/sharedStrings.xml');
  if (shared != null) {
    for (final item in XmlDocument.parse(
      shared,
    ).findAllElements('si', namespaceUri: '*')) {
      sharedStrings.add(
        item
            .findAllElements('t', namespaceUri: '*')
            .map((t) => t.innerText)
            .join(),
      );
    }
  }

  final sheetPath = _firstSheetPath(read) ?? 'xl/worksheets/sheet1.xml';
  final sheet = read(sheetPath);
  if (sheet == null) {
    throw const FormatException('The XLSX workbook has no worksheet.');
  }
  final rows = <List<String>>[];
  for (final rowElement in XmlDocument.parse(
    sheet,
  ).findAllElements('row', namespaceUri: '*')) {
    final row = <String>[];
    for (final cell in rowElement.findElements('c', namespaceUri: '*')) {
      final reference = cell.getAttribute('r');
      final column = reference == null ? row.length : _xlsxColumn(reference);
      while (row.length < column) {
        row.add('');
      }
      row.add(_xlsxCellText(cell, sharedStrings));
    }
    final rowNumber = int.tryParse(rowElement.getAttribute('r') ?? '');
    if (rowNumber != null) {
      while (rows.length < rowNumber - 1) {
        rows.add(const []);
      }
    }
    rows.add(row);
  }
  return rows;
}

String? _firstSheetPath(String? Function(String) read) {
  final workbook = read('xl/workbook.xml');
  final relations = read('xl/_rels/workbook.xml.rels');
  if (workbook == null || relations == null) return null;
  final firstSheet = XmlDocument.parse(workbook)
      .findAllElements('sheet', namespaceUri: '*')
      .firstOrNull;
  final relationId = firstSheet?.attributes
      .where((attribute) => attribute.localName == 'id')
      .firstOrNull
      ?.value;
  if (relationId == null) return null;
  final target = XmlDocument.parse(relations)
      .findAllElements('Relationship', namespaceUri: '*')
      .where((element) => element.getAttribute('Id') == relationId)
      .firstOrNull
      ?.getAttribute('Target');
  if (target == null) return null;
  return target.startsWith('/') ? target.substring(1) : 'xl/$target';
}

int _xlsxColumn(String reference) {
  var column = 0;
  for (final code in reference.codeUnits) {
    if (code < 65 || code > 90) break;
    column = column * 26 + (code - 64);
  }
  return column - 1;
}

String _xlsxCellText(XmlElement cell, List<String> sharedStrings) {
  final type = cell.getAttribute('t');
  if (type == 'inlineStr') {
    return cell
        .findAllElements('t', namespaceUri: '*')
        .map((t) => t.innerText)
        .join();
  }
  final value = cell
      .findElements('v', namespaceUri: '*')
      .firstOrNull
      ?.innerText;
  if (value == null) return '';
  switch (type) {
    case 's':
      final index = int.tryParse(value);
      return index != null && index < sharedStrings.length
          ? sharedStrings[index]
          : '';
    case 'b':
      return value == '1' ? 'true' : 'false';
    default:
      return value;
  }
}

String _xlsxColumnName(int column) {
  var name = '';
  var remaining = column + 1;
  while (remaining > 0) {
    final digit = (remaining - 1) % 26;
    name = String.fromCharCode(65 + digit) + name;
    remaining = (remaining - 1) ~/ 26;
  }
  return name;
}

/// Writes a single-sheet XLSX workbook. Numbers become numeric cells and
/// everything else inline text, with a bold header row.
Uint8List encodeXlsx(List<List<Object?>> rows, {String sheetName = 'Sheet1'}) {
  String escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  final sheet = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<sheetData>',
  );
  for (var r = 0; r < rows.length; r++) {
    sheet.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final value = rows[r][c];
      if (value == null) continue;
      final reference = '${_xlsxColumnName(c)}${r + 1}';
      final style = r == 0 ? ' s="1"' : '';
      if (value is num && value.isFinite) {
        sheet.write('<c r="$reference"$style><v>$value</v></c>');
      } else {
        final text = value is bool ? (value ? 'true' : 'false') : '$value';
        sheet.write(
          '<c r="$reference"$style t="inlineStr"><is><t xml:space="preserve">'
          '${escape(text)}</t></is></c>',
        );
      }
    }
    sheet.write('</row>');
  }
  sheet.write('</sheetData></worksheet>');

  final files = <String, String>{
    '[Content_Types].xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>',
    '_rels/.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="${escape(sheetName)}" sheetId="1" r:id="rId1"/></sheets>'
        '</workbook>',
    'xl/_rels/workbook.xml.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
    'xl/styles.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
        '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
        '</styleSheet>',
    'xl/worksheets/sheet1.xml': sheet.toString(),
  };
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
