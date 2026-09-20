import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'inventory_spreadsheet.dart';

const inventoryImportCsvExample =
    '''name,type,quantity,cost,material,storageLocation
Purple PLA,Filament,2,19.99,PLA,Shelf A
M3 bolts,Fastener,50,0.10,,Bin 3''';

const inventoryImportJsonExample = '''[
  {
    "name": "Purple PLA",
    "type": "Filament",
    "quantity": 2,
    "cost": 19.99,
    "material": "PLA",
    "storageLocation": "Shelf A"
  }
]''';

String inventoryImportFieldHelp(
  InventorySpreadsheetField field,
) => switch (field) {
  InventorySpreadsheetField.name => 'Required. Item name, e.g. Purple PLA.',
  InventorySpreadsheetField.type => 'Type name, e.g. Filament or Fastener. Custom types must already exist in Catalog. Blank: Other.',
  InventorySpreadsheetField.quantity =>
    'Number, zero or greater, e.g. 2 or 0.5. Blank: 1.',
  InventorySpreadsheetField.cost => 'Cost per item, zero or greater, e.g. 19.99. Use a decimal point. Blank: 0.',
  InventorySpreadsheetField.id => 'Optional item identifier. Leave blank to generate one. Existing IDs are flagged as duplicates, not used to overwrite items.',
  InventorySpreadsheetField.material =>
    'Material name, e.g. PLA, PETG or Steel.',
  InventorySpreadsheetField.color => 'Color value, e.g. #7455FF.',
  InventorySpreadsheetField.colorName => 'Readable color name, e.g. Purple.',
  InventorySpreadsheetField.brand => 'Brand name, e.g. Polymaker.',
  InventorySpreadsheetField.vendor => 'Supplier or store name.',
  InventorySpreadsheetField.storageLocation => 'Location name, e.g. Shelf A.',
  InventorySpreadsheetField.barcode => 'Text, e.g. 001234567890. Format spreadsheet cells as text to preserve leading zeros.',
  InventorySpreadsheetField.productUrl =>
    'Product page address, e.g. https://example.com/product.',
  InventorySpreadsheetField.imageUrl =>
    'HTTP or HTTPS address of an image, e.g. https://example.com/photo.jpg.',
  InventorySpreadsheetField.compatibility => 'Spreadsheet: separate names with semicolons, e.g. Printer A; Printer B. JSON: ["Printer A", "Printer B"].',
  InventorySpreadsheetField.amsCompatible =>
    'true or false (yes/no and 1/0 also work). Blank: false.',
  InventorySpreadsheetField.archived =>
    'true or false (yes/no and 1/0 also work). Blank: false.',
};

class ImportFormatDialog extends StatelessWidget {
  const ImportFormatDialog({super.key, this.chooseFile = false});

  final bool chooseFile;

  Widget _example(BuildContext context, String label, String example) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: example));
          if (!context.mounted) return;
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(SnackBar(content: Text('$label example copied')));
        },
        icon: const Icon(Icons.copy_outlined),
        label: Text('Copy $label example'),
      ),
      SelectableText(example, style: const TextStyle(fontFamily: 'monospace')),
      const SizedBox(height: 16),
    ],
  );

  Widget _field(InventorySpreadsheetField field) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${field.label} · ${field.key}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(inventoryImportFieldHelp(field)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Import file format'),
    scrollable: true,
    content: SizedBox(
      width: 640,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Only Name is required. All other fields are optional. Files must be 10 MB or smaller. You can review and correct items before importing.',
          ),
          const SizedBox(height: 16),
          for (final field in [
            InventorySpreadsheetField.name,
            InventorySpreadsheetField.type,
            InventorySpreadsheetField.quantity,
            InventorySpreadsheetField.cost,
          ])
            _field(field),
          const Text(
            'CSV / XLSX',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'Start with a header row, then one item per row. Columns can be in any order; you will match them before importing. XLSX uses the first worksheet. For CSV, quote values containing commas, quotes or line breaks; double any quotes inside a quoted value.',
          ),
          _example(context, 'CSV', inventoryImportCsvExample),
          const Text('JSON', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text(
            'Use a list of items as shown below, or an object with an "items" list. Use the field keys shown in this guide. Extra fields are ignored.',
          ),
          _example(context, 'JSON', inventoryImportJsonExample),
          ExpansionTile(
            title: const Text('All supported columns'),
            tilePadding: EdgeInsets.zero,
            children: [
              for (final field in InventorySpreadsheetField.values)
                Align(alignment: Alignment.centerLeft, child: _field(field)),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(chooseFile ? 'Cancel' : 'Close'),
      ),
      if (chooseFile)
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Choose file…'),
        ),
    ],
  );
}
