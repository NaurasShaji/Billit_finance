import 'package:excel_community/excel_community.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:uuid/uuid.dart';

import '../../models/models.dart';
import '../../services/boxes.dart';

class BulkProductImportScreen extends StatefulWidget {
  const BulkProductImportScreen({super.key});
  @override
  State<BulkProductImportScreen> createState() =>
      _BulkProductImportScreenState();
}

class _BulkProductImportScreenState extends State<BulkProductImportScreen> {
  List<_ImportRow> _rows = [];
  String? _fileName;
  String? _error;
  bool _busy = false;

  int get _ready => _rows.where((r) => r.error == null).length;
  int get _skipped => _rows.length - _ready;
  String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  int _col(List<String> headers, List<String> aliases) {
    for (var i = 0; i < headers.length; i++) {
      if (aliases.map(_norm).contains(headers[i])) return i;
    }
    return -1;
  }

  Future<void> _chooseFile() async {
    setState(() {
      _busy = true;
      _error = null;
      _rows = [];
      _fileName = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final file = picked.files.single;
      if (file.bytes == null || file.bytes!.isEmpty) {
        throw Exception('Could not read this file. Please select it again.');
      }
      final workbook = Excel.decodeBytes(file.bytes!);
      if (workbook.tables.isEmpty) {
        throw Exception('No worksheet found in this workbook.');
      }
      final sheet = workbook.tables.values.first;
      if (sheet.rows.length < 2) {
        throw Exception('Add a header row and at least one product row.');
      }
      final headers = sheet.rows.first
          .map((c) => _norm(c?.value?.toString() ?? ''))
          .toList();
      final nameCol =
          _col(headers, ['name', 'product', 'productname', 'itemname']);
      final sellCol =
          _col(headers, ['sellingprice', 'saleprice', 'price', 'sellingrate']);
      final costCol =
          _col(headers, ['costprice', 'purchaseprice', 'cost', 'buyingprice']);
      final stockCol =
          _col(headers, ['stock', 'quantity', 'qty', 'openingstock']);
      if ([nameCol, sellCol, costCol, stockCol].any((c) => c < 0)) {
        throw Exception(
            'Required columns: Name, Selling Price, Cost Price, Stock. Optional: Unit, Category, Subcategory, Barcode, HSN Code, GST Rate.');
      }
      final parsed = <_ImportRow>[];
      for (var i = 1; i < sheet.rows.length; i++) {
        final cells = sheet.rows[i];
        String val(int index) => index < 0 || index >= cells.length
            ? ''
            : (cells[index]?.value?.toString().trim() ?? '');
        double? numAt(int index) =>
            double.tryParse(val(index).replaceAll(',', ''));
        if (cells.every((c) => (c?.value?.toString().trim() ?? '').isEmpty)) {
          continue;
        }
        final name = val(nameCol);
        final selling = numAt(sellCol);
        final cost = numAt(costCol);
        final stock = numAt(stockCol);
        final unitText = val(_col(headers, ['unit', 'units'])).toLowerCase();
        final category = val(_col(headers, ['category', 'productcategory']));
        final subcategory = val(_col(headers, ['subcategory', 'subcat']));
        final barcode = val(_col(headers, ['barcode', 'ean', 'sku']));
        final hsn = val(_col(headers, ['hsn', 'hsncode', 'hsnsac']));
        final gstText =
            val(_col(headers, ['gstrate', 'gst', 'gstpercent', 'taxrate']));
        final gst = gstText.isEmpty
            ? null
            : double.tryParse(gstText.replaceAll('%', '').trim());
        String? error;
        if (name.isEmpty) {
          error = 'Product name required';
        } else if (selling == null || selling < 0) {
          error = 'Invalid selling price';
        } else if (cost == null || cost < 0) {
          error = 'Invalid cost price';
        } else if (stock == null || stock < 0) {
          error = 'Invalid stock quantity';
        } else if (unitText.isNotEmpty &&
            !['pcs', 'piece', 'pieces', 'kg', 'sqft', 'sq ft']
                .contains(unitText)) {
          error = 'Unit must be pcs, kg or sqft';
        } else if (gstText.isNotEmpty &&
            (gst == null || gst < 0 || gst > 100)) {
          error = 'GST rate must be 0–100';
        }
        parsed.add(_ImportRow(
          row: i + 1,
          name: name,
          selling: selling ?? 0,
          cost: cost ?? 0,
          stock: stock ?? 0,
          unit: unitText == 'kg'
              ? UnitType.kg
              : ((unitText == 'sqft' || unitText == 'sq ft')
                  ? UnitType.sqft
                  : UnitType.pcs),
          category: category.isEmpty ? 'General' : category,
          subcategory: subcategory,
          barcode: barcode,
          hsn: hsn,
          gst: gst,
          error: error,
        ));
      }
      if (parsed.isEmpty) throw Exception('No product rows found.');
      _markDuplicates(parsed);
      if (!mounted) return;
      setState(() {
        _rows = parsed;
        _fileName = file.name;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _busy = false;
        });
      }
    }
  }

  void _markDuplicates(List<_ImportRow> rows) {
    // Build duplicate indexes defensively. Older/corrupt Hive records can
    // contain null values in fields that are non-nullable in the current
    // Product model; one such record must not abort an Excel import.
    final names = <String>{};
    final codes = <String>{};
    try {
      final products = Hive.box<Product>(Boxes.products).values;
      for (final product in products) {
        try {
          final name = product.name.trim().toLowerCase();
          if (name.isNotEmpty) names.add(name);
        } catch (_) {
          // Ignore malformed legacy records; they cannot participate in
          // duplicate-name detection.
        }
        try {
          final code = (product.barcode ?? '').trim();
          if (code.isNotEmpty) codes.add(code);
        } catch (_) {
          // Ignore malformed legacy barcode values.
        }
      }
    } catch (_) {
      // Keep import parsing available even if the existing inventory cannot
      // be read for duplicate detection. Imported rows are still validated
      // against one another below.
    }

    final seenNames = <String>{};
    final seenCodes = <String>{};
    for (final row in rows) {
      if (row.error != null) continue;
      final name = row.name.trim().toLowerCase();
      final code = row.barcode.trim();
      if (names.contains(name) || !seenNames.add(name)) {
        row.error = 'Duplicate product name';
      } else if (code.isNotEmpty &&
          (codes.contains(code) || !seenCodes.add(code))) {
        row.error = 'Duplicate barcode';
      }
    }
  }

  Future<void> _import() async {
    final valid = _rows.where((r) => r.error == null).toList();
    if (valid.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm import'),
        content: Text(
            'Add ${valid.length} products? Existing products will not be overwritten. ${_skipped > 0 ? '$_skipped invalid or duplicate rows will be skipped.' : ''}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Import')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final box = Hive.box<Product>(Boxes.products);
      for (final r in valid) {
        final p = Product()
          ..id = const Uuid().v4()
          ..name = r.name
          ..sellingPrice = r.selling
          ..costPrice = r.cost
          ..stock = r.stock
          ..unit = r.unit
          ..category = r.category
          ..subCategory = r.subcategory
          ..active = true
          ..barcode = r.barcode.isEmpty ? null : r.barcode
          ..hsnCode = r.hsn
          ..gstRate = r.gst;
        await box.put(p.id, p);
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _rows = [];
        _fileName = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Imported ${valid.length} products successfully.')));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Bulk Add Products')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.upload_file_outlined,
                              size: 30, color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text('Import from Excel',
                                  style: theme.textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold))),
                        ]),
                        const SizedBox(height: 12),
                        const Text(
                            'Upload an .xlsx file. The first row must contain column headings.'),
                        const SizedBox(height: 8),
                        const Text(
                            'Required: Name, Selling Price, Cost Price, Stock',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        const Text(
                            'Optional: Unit, Category, Subcategory, Barcode, HSN Code, GST Rate'),
                        const SizedBox(height: 4),
                        const Text(
                            'Units: pcs, kg or sqft. Enter GST as a number, e.g. 5 or 18.'),
                        const SizedBox(height: 16),
                        SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _chooseFile,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.folder_open),
                              label: Text(_busy
                                  ? 'Processing…'
                                  : 'Choose Excel file (.xlsx)'),
                            )),
                        if (_fileName != null) ...[
                          const SizedBox(height: 8),
                          Text('Selected: ${_fileName!}',
                              overflow: TextOverflow.ellipsis),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(_error!,
                              style: TextStyle(color: theme.colorScheme.error)),
                        ],
                      ],
                    ))),
            if (_rows.isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(label: Text('Rows: ${_rows.length}')),
                Chip(
                    label: Text('Ready: $_ready'),
                    avatar: const Icon(Icons.check_circle,
                        color: Colors.green, size: 18)),
                Chip(
                    label: Text('Skipped: $_skipped'),
                    avatar: Icon(Icons.warning_amber,
                        color: _skipped > 0
                            ? theme.colorScheme.error
                            : Colors.grey,
                        size: 18)),
              ]),
              const SizedBox(height: 10),
              Card(
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Row')),
                          DataColumn(label: Text('Product')),
                          DataColumn(label: Text('Selling')),
                          DataColumn(label: Text('Cost')),
                          DataColumn(label: Text('Stock')),
                          DataColumn(label: Text('Unit')),
                          DataColumn(label: Text('Status')),
                        ],
                        rows: _rows
                            .take(300)
                            .map((r) => DataRow(cells: [
                                  DataCell(Text(r.row.toString())),
                                  DataCell(SizedBox(
                                      width: 180,
                                      child: Text(r.name.isEmpty ? '—' : r.name,
                                          overflow: TextOverflow.ellipsis))),
                                  DataCell(
                                      Text('₹${r.selling.toStringAsFixed(2)}')),
                                  DataCell(
                                      Text('₹${r.cost.toStringAsFixed(2)}')),
                                  DataCell(Text(r.stock.toString())),
                                  DataCell(Text(r.unit.name)),
                                  DataCell(SizedBox(
                                      width: 200,
                                      child: Text(r.error ?? 'Ready',
                                          style: TextStyle(
                                              color: r.error == null
                                                  ? Colors.green
                                                  : theme.colorScheme.error)))),
                                ]))
                            .toList()),
                  )),
              if (_rows.length > 300)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      'Showing first 300 of ${_rows.length} rows; all valid rows will be imported.'),
                ),
              const SizedBox(height: 12),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy || _ready == 0 ? null : _import,
                    icon: const Icon(Icons.playlist_add_check),
                    label:
                        Text(_busy ? 'Importing…' : 'Import $_ready products'),
                  )),
            ],
          ]),
        ),
      ),
    );
  }
}

class _ImportRow {
  _ImportRow(
      {required this.row,
      required this.name,
      required this.selling,
      required this.cost,
      required this.stock,
      required this.unit,
      required this.category,
      required this.subcategory,
      required this.barcode,
      required this.hsn,
      required this.gst,
      required this.error});
  final int row;
  final String name;
  final double selling;
  final double cost;
  final double stock;
  final UnitType unit;
  final String category;
  final String subcategory;
  final String barcode;
  final String hsn;
  final double? gst;
  String? error;
}
