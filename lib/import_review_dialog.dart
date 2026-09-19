import 'package:flutter/material.dart';

import 'main.dart' show InventoryJsonDraft;

/// Review edits stay in memory until the user accepts the selected rows.
class ImportReviewDialog extends StatefulWidget {
  const ImportReviewDialog({
    super.key,
    required this.drafts,
    required this.isDuplicate,
    required this.validate,
  });
  final List<InventoryJsonDraft> drafts;
  final bool Function(InventoryJsonDraft) isDuplicate;
  final List<String> Function(InventoryJsonDraft) validate;
  @override
  State<ImportReviewDialog> createState() => _ImportReviewDialogState();
}

class _ImportReviewDialogState extends State<ImportReviewDialog> {
  late final rows = List<InventoryJsonDraft>.of(widget.drafts);
  final excluded = <int>{};
  bool skipDuplicates = true;
  final _validation = <InventoryJsonDraft, List<String>>{};
  final _duplicate = <InventoryJsonDraft, bool>{};
  List<String> errorsFor(InventoryJsonDraft draft) =>
      _validation.putIfAbsent(draft, () => widget.validate(draft));
  bool isDuplicate(InventoryJsonDraft draft) =>
      _duplicate.putIfAbsent(draft, () => widget.isDuplicate(draft));
  Set<int> get duplicates {
    final seenIds = <String>{};
    final seenNames = <String>{};
    return {
      for (var i = 0; i < rows.length; i++)
        if (isDuplicate(rows[i]) |
            (rows[i].id.isNotEmpty && !seenIds.add(rows[i].id)) |
            !seenNames.add(
              '${rows[i].typeName.trim().toLowerCase()}|${rows[i].name.trim().toLowerCase()}',
            ))
          i,
    };
  }

  @override
  Widget build(BuildContext context) {
    final repeated = duplicates;
    final selected = [
      for (var i = 0; i < rows.length; i++)
        if (!excluded.contains(i) && !(skipDuplicates && repeated.contains(i)))
          i,
    ];
    final hasErrors = selected.any((i) => errorsFor(rows[i]).isNotEmpty);
    return AlertDialog(
      title: const Text('Review import'),
      content: SizedBox(
        width: 720,
        height: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Inspect or edit each row, then choose which items to import. Nothing is saved until you confirm.',
            ),
            const SizedBox(height: 8),
            if (repeated.isNotEmpty) ...[
              Text('${repeated.length} possible duplicates'),
              SegmentedButton<bool>(
                key: const Key('inventory-import-duplicates'),
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text('Skip ${repeated.length} duplicates'),
                  ),
                  const ButtonSegment(
                    value: false,
                    label: Text('Import them as new items'),
                  ),
                ],
                selected: {skipDuplicates},
                onSelectionChanged: (value) =>
                    setState(() => skipDuplicates = value.single),
              ),
            ],
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => setState(excluded.clear),
                  child: const Text('Select all'),
                ),
                TextButton(
                  onPressed: () => setState(
                    () => excluded.addAll(List.generate(rows.length, (i) => i)),
                  ),
                  child: const Text('Select none'),
                ),
                Text('${selected.length} selected'),
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final row = rows[i];
                  final errors = errorsFor(row);
                  final skipped = skipDuplicates && repeated.contains(i);
                  return ListTile(
                    key: Key('inventory-import-row-$i'),
                    leading: Checkbox(
                      key: Key('import-select-$i'),
                      value: selected.contains(i),
                      onChanged: skipped
                          ? null
                          : (value) => setState(() {
                              if (value == true) {
                                excluded.remove(i);
                              } else {
                                excluded.add(i);
                              }
                            }),
                    ),
                    title: Text(row.name),
                    subtitle: Text(
                      [
                        row.typeName,
                        'qty ${row.quantity}',
                        'cost ${row.cost}',
                        if (row.storageLocation.isNotEmpty) row.storageLocation,
                        if (repeated.contains(i))
                          skipped
                              ? 'Possible duplicate · skipped'
                              : 'Possible duplicate',
                        ...errors,
                      ].join(' · '),
                    ),
                    trailing: IconButton(
                      key: Key('import-edit-$i'),
                      tooltip: 'Inspect / edit',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final edited = await showDialog<InventoryJsonDraft>(
                          context: context,
                          builder: (_) => ImportRowEditor(
                            draft: row,
                            validate: widget.validate,
                          ),
                        );
                        if (edited != null && mounted) {
                          setState(() => rows[i] = edited);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            if (hasErrors)
              const Text(
                'Correct or deselect rows with errors before importing.',
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
          key: const Key('confirm-inventory-json-import'),
          onPressed: selected.isEmpty || hasErrors
              ? null
              : () =>
                    Navigator.pop(context, [for (final i in selected) rows[i]]),
          icon: const Icon(Icons.file_download_done_outlined),
          label: Text('Import ${selected.length} items'),
        ),
      ],
    );
  }
}

class ImportRowEditor extends StatefulWidget {
  const ImportRowEditor({
    super.key,
    required this.draft,
    required this.validate,
  });
  final InventoryJsonDraft draft;
  final List<String> Function(InventoryJsonDraft) validate;
  @override
  State<ImportRowEditor> createState() => _ImportRowEditorState();
}

class _ImportRowEditorState extends State<ImportRowEditor> {
  late final fields = <String, TextEditingController>{
    for (final entry in <String, String>{
      'Name': widget.draft.name,
      'Type': widget.draft.typeName,
      'Quantity': '${widget.draft.quantity}',
      'Cost': '${widget.draft.cost}',
      'Material': widget.draft.material,
      'Color': widget.draft.color,
      'Color label': widget.draft.colorLabel,
      'Brand': widget.draft.brand,
      'Vendor': widget.draft.vendor,
      'Location': widget.draft.storageLocation,
      'Barcode': widget.draft.barcode,
      'Product URL': widget.draft.productUrl,
      'Image URL': widget.draft.imageUrl,
    }.entries)
      entry.key: TextEditingController(text: entry.value),
  };
  String? error;
  String value(String key) => fields[key]!.text.trim();
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void save() {
    final quantity = double.tryParse(value('Quantity'));
    final cost = double.tryParse(value('Cost'));
    if (value('Name').isEmpty ||
        quantity == null ||
        !quantity.isFinite ||
        quantity < 0 ||
        cost == null ||
        !cost.isFinite ||
        cost < 0) {
      setState(
        () => error = 'Enter a name and valid, non-negative quantity and cost.',
      );
      return;
    }
    final d = widget.draft;
    final edited = InventoryJsonDraft(
      id: d.id,
      rowNumber: d.rowNumber,
      name: value('Name'),
      typeName: value('Type'),
      quantity: quantity,
      cost: cost,
      material: value('Material'),
      color: value('Color'),
      colorLabel: value('Color label'),
      brand: value('Brand'),
      vendor: value('Vendor'),
      storageLocation: value('Location'),
      barcode: value('Barcode'),
      productUrl: value('Product URL'),
      imageUrl: value('Image URL'),
      compatibility: d.compatibility,
      amsCompatible: d.amsCompatible,
      archived: d.archived,
    );
    final errors = widget.validate(edited);
    if (errors.isNotEmpty) {
      setState(() => error = errors.join('\n'));
      return;
    }
    Navigator.pop(context, edited);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Inspect / edit item'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in fields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  key: Key('import-field-${entry.key}'),
                  controller: entry.value,
                  decoration: InputDecoration(labelText: entry.key),
                ),
              ),
            if (error != null) Text(error!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('import-save-row'),
        onPressed: save,
        child: const Text('Apply changes'),
      ),
    ],
  );
}
