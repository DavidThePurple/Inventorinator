import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportRow {
  const ReportRow(this.cells, {this.date, this.values = const {}});
  final List<String> cells;
  final DateTime? date;
  final Map<String, double> values;
}

class WorkshopReport {
  const WorkshopReport(
    this.title,
    this.columns,
    this.rows, {
    this.note = '',
    this.dated = false,
  });
  final String title, note;
  final List<String> columns;
  final List<ReportRow> rows;
  final bool dated;
}

List<ReportRow> filterReport(
  WorkshopReport report,
  String query,
  DateTimeRange? range,
) {
  final q = query.trim().toLowerCase();
  return report.rows
      .where(
        (row) =>
            (q.isEmpty || row.cells.any((s) => s.toLowerCase().contains(q))) &&
            (range == null ||
                row.date != null &&
                    !row.date!.isBefore(range.start) &&
                    row.date!.isBefore(
                      DateTime(
                        range.end.year,
                        range.end.month,
                        range.end.day + 1,
                      ),
                    )),
      )
      .toList();
}

Future<Uint8List> generateReportPdf(Map<String, Object> input) async {
  final doc = pw.Document();
  final font = pw.Font.ttf(ByteData.sublistView(input['font'] as Uint8List));
  final rows = input['rows'] as List<List<String>>;
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      maxPages: 10000,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      margin: const pw.EdgeInsets.all(28),
      header: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              input['title'] as String,
              style: const pw.TextStyle(fontSize: 18),
            ),
            pw.Text(
              input['note'] as String,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      ),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Inventorinator · ${c.pageNumber} / ${c.pagesCount}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      build: (_) => [
        pw.TableHelper.fromTextArray(
          headers: input['columns'] as List<String>,
          columnWidths: {
            for (final (index, label)
                in (input['columns'] as List<String>).indexed)
              index: pw.FlexColumnWidth(switch (label.toLowerCase()) {
                'item' || 'notes' || 'details' || 'url' => 3,
                'added' || 'date' => 1.6,
                _ => 1.4,
              }),
          },
          data: rows,
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellPadding: const pw.EdgeInsets.all(5),
        ),
      ],
    ),
  );
  return doc.save();
}

Future<void> showWorkshopReports(
  BuildContext context,
  List<WorkshopReport> reports,
) => showDialog<void>(
  context: context,
  builder: (_) => _ReportsDialog(reports: reports),
);

class _ReportsDialog extends StatefulWidget {
  const _ReportsDialog({required this.reports});
  final List<WorkshopReport> reports;
  @override
  State<_ReportsDialog> createState() => _ReportsDialogState();
}

class _ReportsDialogState extends State<_ReportsDialog> {
  int selected = 0, page = 0;
  String query = '';
  DateTimeRange? range;
  bool busy = false;
  String? error;
  Future<void> pdf(WorkshopReport report, List<ReportRow> rows) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final font = (await rootBundle.load('assets/fonts/DejaVuSans.ttf')).buffer
          .asUint8List();
      final bytes = await compute(generateReportPdf, <String, Object>{
        'font': font,
        'title': report.title,
        'columns': report.columns,
        'note':
            '${report.note}\n${rows.length} rows · ${DateTime.now().toLocal()}${query.isEmpty ? '' : ' · Search: $query'}${range == null ? '' : ' · ${range!.start.toLocal()} to ${range!.end.toLocal()}'}',
        'rows': rows
            .map(
              (r) => r.cells
                  .map((c) => c.length > 1500 ? '${c.substring(0, 1500)}…' : c)
                  .toList(),
            )
            .toList(),
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(report.title),
              actions: [
                IconButton(
                  tooltip: 'Save PDF',
                  icon: const Icon(Icons.save_alt),
                  onPressed: () async {
                    await FilePicker.saveFile(
                      dialogTitle: 'Save report',
                      fileName: 'Inventorinator-report.pdf',
                      type: FileType.custom,
                      allowedExtensions: ['pdf'],
                      bytes: bytes,
                    );
                  },
                ),
              ],
            ),
            body: PdfPreview(
              build: (_) async => bytes,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              pdfFileName: 'Inventorinator-report.pdf',
            ),
          ),
        ),
      );
    } catch (e) {
      error = 'Could not create the PDF: $e';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.reports[selected];
    final rows = filterReport(report, query, range);
    final pages = (rows.length / 50).ceil().clamp(1, 1000000);
    final totals = <String, double>{};
    for (final row in rows) {
      for (final entry in row.values.entries) {
        totals.update(
          entry.key,
          (v) => v + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(title: const Text('Reports')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              DropdownButtonFormField<int>(
                initialValue: selected,
                isExpanded: true,
                items: [
                  for (var i = 0; i < widget.reports.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(widget.reports[i].title),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (i) => setState(() {
                        selected = i!;
                        range = null;
                        page = 0;
                      }),
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Filter report',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (s) => setState(() {
                  query = s;
                  page = 0;
                }),
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (report.dated)
                    TextButton.icon(
                      icon: const Icon(Icons.date_range),
                      label: Text(
                        range == null
                            ? 'All dates'
                            : '${range!.start.toString().split(' ').first} — ${range!.end.toString().split(' ').first}',
                      ),
                      onPressed: () async {
                        final value = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(1970),
                          lastDate: DateTime.now(),
                          initialDateRange: range,
                        );
                        if (mounted && value != null) {
                          setState(() {
                            range = value;
                            page = 0;
                          });
                        }
                      },
                    ),
                  if (range != null)
                    TextButton(
                      onPressed: () => setState(() {
                        range = null;
                        page = 0;
                      }),
                      child: const Text('Clear dates'),
                    ),
                  FilledButton.icon(
                    onPressed: busy || rows.isEmpty
                        ? null
                        : () => pdf(report, rows),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Preview / print PDF'),
                  ),
                  Text('${rows.length} rows'),
                ],
              ),
              if (report.note.isNotEmpty)
                Text(report.note, style: Theme.of(context).textTheme.bodySmall),
              if (totals.isNotEmpty)
                Text(
                  totals.entries
                      .map((e) => '${e.key}: ${e.value.toStringAsFixed(2)}')
                      .join(' · '),
                ),
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                const Center(child: Text('No matching records')),
              for (final row in rows.skip(page * 50).take(50))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var c = 0; c < report.columns.length; c++)
                          Text('${report.columns[c]}: ${row.cells[c]}'),
                      ],
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: page == 0 ? null : () => setState(() => page--),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('${page + 1} / $pages'),
                  IconButton(
                    onPressed: page + 1 >= pages
                        ? null
                        : () => setState(() => page++),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
