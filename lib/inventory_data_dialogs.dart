import 'package:flutter/material.dart';

import 'inventory_spreadsheet.dart';
import 'import_format_dialog.dart';

/// Lets the user confirm which inventory field each spreadsheet column holds,
/// with a live preview of the first rows. Pops the mapping, or null.
class SpreadsheetMappingDialog extends StatefulWidget {
  const SpreadsheetMappingDialog({
    super.key,
    required this.table,
    required this.fileName,
  });

  final SpreadsheetTable table;
  final String fileName;

  @override
  State<SpreadsheetMappingDialog> createState() =>
      _SpreadsheetMappingDialogState();
}

class _SpreadsheetMappingDialogState extends State<SpreadsheetMappingDialog> {
  late final List<InventorySpreadsheetField?> mapping = guessSpreadsheetMapping(
    widget.table.headers,
  );

  static const _previewRows = 5;

  void _assign(int column, InventorySpreadsheetField? field) {
    setState(() {
      // Each field comes from one column; taking it clears the old column.
      if (field != null) {
        for (var index = 0; index < mapping.length; index++) {
          if (mapping[index] == field) mapping[index] = null;
        }
      }
      mapping[column] = field;
    });
  }

  String _sample(int column) =>
      widget.table.rows
          .map((row) => row[column].trim())
          .where((value) => value.isNotEmpty)
          .firstOrNull ??
      '';

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final mapped = [
      for (var column = 0; column < mapping.length; column++)
        if (mapping[column] != null) column,
    ];
    final hasName = mapping.contains(InventorySpreadsheetField.name);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.table_chart_outlined),
          SizedBox(width: 10),
          Expanded(child: Text('Match spreadsheet columns')),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.fileName} · ${table.rows.length} rows. '
              'Choose what each column holds; unmatched columns are skipped.',
              style: TextStyle(color: muted),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const ImportFormatDialog(),
                ),
                icon: const Icon(Icons.help_outline),
                label: const Text('Column formats & examples'),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              flex: 3,
              child: ListView.separated(
                itemCount: table.headers.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, column) {
                  final header = table.headers[column];
                  final sample = _sample(column);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                header.isEmpty
                                    ? 'Column ${column + 1}'
                                    : header,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (sample.isNotEmpty)
                                Text(
                                  'e.g. $sample',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: muted, fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 220,
                          child: DropdownButton<InventorySpreadsheetField?>(
                            key: Key('spreadsheet-column-$column'),
                            isExpanded: true,
                            value: mapping[column],
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text("Don't import"),
                              ),
                              for (final field
                                  in InventorySpreadsheetField.values)
                                DropdownMenuItem(
                                  value: field,
                                  child: Text(field.label),
                                ),
                            ],
                            onChanged: (field) => _assign(column, field),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Text('Preview', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Expanded(
              flex: 2,
              child: mapped.isEmpty
                  ? Center(
                      child: Text(
                        'Match at least the Name column.',
                        style: TextStyle(color: muted),
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          key: const Key('spreadsheet-preview'),
                          headingRowHeight: 36,
                          dataRowMinHeight: 30,
                          dataRowMaxHeight: 36,
                          columns: [
                            for (final column in mapped)
                              DataColumn(label: Text(mapping[column]!.label)),
                          ],
                          rows: [
                            for (final row in table.rows.take(_previewRows))
                              DataRow(
                                cells: [
                                  for (final column in mapped)
                                    DataCell(Text(row[column])),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (!hasName)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Match a column to Name to continue.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('confirm-spreadsheet-mapping'),
          onPressed: hasName
              ? () => Navigator.pop(context, List.of(mapping))
              : null,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Review rows'),
        ),
      ],
    );
  }
}

enum InventoryExportFormat {
  csv('CSV', 'csv'),
  xlsx('XLSX', 'xlsx'),
  json('Portable JSON', 'json');

  const InventoryExportFormat(this.label, this.extension);

  final String label;
  final String extension;
}

typedef InventoryExportChoice = ({
  InventoryExportFormat format,
  bool filteredOnly,
});

/// Chooses an export format and scope. Pops the choice, or null.
class InventoryExportDialog extends StatefulWidget {
  const InventoryExportDialog({
    super.key,
    required this.allCount,
    required this.filteredCount,
    required this.filtersActive,
  });

  final int allCount;
  final int filteredCount;
  final bool filtersActive;

  @override
  State<InventoryExportDialog> createState() => _InventoryExportDialogState();
}

class _InventoryExportDialogState extends State<InventoryExportDialog> {
  var format = InventoryExportFormat.xlsx;
  var filteredOnly = false;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final count = filteredOnly ? widget.filteredCount : widget.allCount;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.ios_share_rounded),
          SizedBox(width: 10),
          Expanded(child: Text('Export inventory')),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<InventoryExportFormat>(
              key: const Key('inventory-export-format'),
              segments: [
                for (final value in InventoryExportFormat.values)
                  ButtonSegment(value: value, label: Text(value.label)),
              ],
              selected: {format},
              onSelectionChanged: (selection) =>
                  setState(() => format = selection.single),
            ),
            const SizedBox(height: 16),
            RadioGroup<bool>(
              groupValue: filteredOnly,
              onChanged: (value) =>
                  setState(() => filteredOnly = value ?? false),
              child: Column(
                children: [
                  RadioListTile<bool>(
                    key: const Key('inventory-export-all'),
                    value: false,
                    contentPadding: EdgeInsets.zero,
                    title: Text('All items (${widget.allCount})'),
                    subtitle: const Text('Includes archived items.'),
                  ),
                  RadioListTile<bool>(
                    key: const Key('inventory-export-filtered'),
                    value: true,
                    enabled: widget.filtersActive,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Items matching the current view (${widget.filteredCount})',
                    ),
                    subtitle: Text(
                      widget.filtersActive
                          ? 'Uses the active search, filters and sort.'
                          : 'No search or filter is active.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              format == InventoryExportFormat.json
                  ? filteredOnly
                        ? 'Portable JSON keeps item IDs for re-import.'
                        : 'Portable JSON also carries kits and the shopping list, and keeps item IDs for re-import. Connection settings are never exported.'
                  : 'Spreadsheets keep item IDs, so importing one back skips items you already have.',
              style: TextStyle(color: muted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('confirm-inventory-export'),
          onPressed: count == 0
              ? null
              : () => Navigator.pop<InventoryExportChoice>(context, (
                  format: format,
                  filteredOnly: filteredOnly,
                )),
          icon: const Icon(Icons.save_alt_rounded),
          label: Text('Export $count items'),
        ),
      ],
    );
  }
}
