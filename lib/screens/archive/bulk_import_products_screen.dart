import 'package:excel_community/excel_community.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:uuid/uuid.dart';

import '../../models/models.dart';
import '../../services/boxes.dart';

class BulkImportProductsScreen extends StatefulWidget {
  const BulkImportProductsScreen({super.key});

  @override
  State<BulkImportProductsScreen> createState() =>
      _BulkImportProductsScreenState();
}

class _BulkImportProductsScreenState extends State<BulkImportProductsScreen> {
  String? _fileName;
  List<_ImportRow> _rows = [];
  bool _isReading = false;
  bool _isImporting = false;
  int? _importedCount;

  int get _validCount => _rows.where((row) => row.error == null).length;
  int get _skippedCount => _rows.where((row) => row.error != null).length;

  Future<void> _pickExcelFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _showMessage(
            'Could not read this file. Please select the .xlsx file again.');
        return;
      }

      setState(() {
        _isReading = true;
        _fileName = file.name;
        _rows = [];
        _importedCount = null;
      });

      final workbook = Excel.decodeBytes(bytes);
      if (workbook.tables.isEmpty) {
        throw const FormatException(
            'The workbook does not contain a worksheet.');
      }
      final sheet = workbook.tables.values.first;
      final sheetRows = sheet.rows;
      var headerIndex = -1;
      for (var i = 0; i < sheetRows.length; i++) {
        if (sheetRows[i].any((cell) => _cellText(cell).trim().isNotEmpty)) {
          headerIndex = i;
          break;
        }
      }
      if (headerIndex < 0) {
        throw const FormatException('The worksheet is empty.');
      }

      final headers = sheetRows[headerIndex]
          .map((cell) => _normaliseHeader(_cellText(cell)))
          .toList();
      final nameColumn = _findColumn(
          headers, ['name', 'product', 'productname', 'item', 'itemname']);
      final sellingColumn = _findColumn(
          headers, ['sellingprice', 'saleprice', 'price', 'unitprice']);
      if (nameColumn == -1 || sellingColumn == -1) {
        throw const FormatException(
          'Required columns not found. The first row must include Product Name and Selling Price.',
        );
      }

      final costColumn = _findColumn(
          headers, ['costprice', 'purchaseprice', 'cost', 'buyingprice']);
      final stockColumn = _findColumn(
          headers, ['stock', 'quantity', 'openingstock', 'openingquantity']);
      final unitColumn = _findColumn(headers, ['unit', 'unittype', 'measure']);
      final categoryColumn = _findColumn(headers, ['category']);
      final subCategoryColumn = _findColumn(headers, ['subcategory', 'subcat']);
      final barcodeColumn =
          _findColumn(headers, ['barcode', 'sku', 'productcode']);
      final hsnColumn = _findColumn(headers, ['hsn', 'hsncode']);
      final gstColumn =
          _findColumn(headers, ['gstrate', 'gst', 'gstpercent', 'taxrate']);

      final productBox = Hive.box<Product>(Boxes.products);
      final existingNames = productBox.values
          .map((p) => p.name.trim().toLowerCase())
          .where((v) => v.isNotEmpty)
          .toSet();
      final existingBarcodes = productBox.values
          .map((p) => (p.barcode ?? '').trim())
          .where((v) => v.isNotEmpty)
          .toSet();
      final seenNames = <String>{};
      final seenBarcodes = <String>{};
      final parsedRows = <_ImportRow>[];

      for (var i = headerIndex + 1; i < sheetRows.length; i++) {
        final row = sheetRows[i];
        if (row.every((cell) => _cellText(cell).trim().isEmpty)) continue;

        final name = _readColumn(row, nameColumn).trim();
        final sellingText = _readColumn(row, sellingColumn).trim();
        final costText = _readOptionalColumn(row, costColumn, '0').trim();
        final stockText = _readOptionalColumn(row, stockColumn, '0').trim();
        final unitText =
            _readOptionalColumn(row, unitColumn, 'pcs').trim().toLowerCase();
        final category =
            _readOptionalColumn(row, categoryColumn, 'General').trim();
        final subCategory =
            _readOptionalColumn(row, subCategoryColumn, '').trim();
        final barcode = _readOptionalColumn(row, barcodeColumn, '').trim();
        final hsn = _readOptionalColumn(row, hsnColumn, '').trim();
        final gstText = _readOptionalColumn(row, gstColumn, '').trim();

        String? error;
        final sellingPrice = double.tryParse(sellingText.replaceAll(',', ''));
        final costPrice = double.tryParse(costText.replaceAll(',', ''));
        final stock = double.tryParse(stockText.replaceAll(',', ''));
        final gstRate = gstText.isEmpty
            ? null
            : double.tryParse(gstText.replaceAll('%', '').trim());

        UnitType unit;
        switch (_normaliseHeader(unitText)) {
          case 'kg':
          case 'kilogram':
          case 'kilograms':
            unit = UnitType.kg;
            break;
          case 'sqft':
          case 'squarefeet':
          case 'squarefoot':
            unit = UnitType.sqft;
            break;
          case '':
          case 'pcs':
          case 'pc':
          case 'piece':
          case 'pieces':
          case 'unit':
          case 'units':
            unit = UnitType.pcs;
            break;
          default:
            unit = UnitType.pcs;
            error = 'Unknown unit "$unitText". Use pcs, kg, or sqft.';
        }

        if (name.isEmpty) {
          error ??= 'Product name is required.';
        } else if (sellingPrice == null || sellingPrice < 0) {
          error ??=
              'Selling price must be a valid number greater than or equal to 0.';
        } else if (costPrice == null || costPrice < 0) {
          error ??=
              'Cost price must be a valid number greater than or equal to 0.';
        } else if (stock == null || stock < 0) {
          error ??= 'Stock must be a valid number greater than or equal to 0.';
        } else if (gstText.isNotEmpty &&
            (gstRate == null || gstRate < 0 || gstRate > 100)) {
          error ??= 'GST rate must be between 0 and 100.';
        }

        final nameKey = name.toLowerCase();
        if (name.isNotEmpty &&
            (existingNames.contains(nameKey) || !seenNames.add(nameKey))) {
          error ??= 'A product with this name already exists.';
        }
        if (barcode.isNotEmpty &&
            (existingBarcodes.contains(barcode) ||
                !seenBarcodes.add(barcode))) {
          error ??= 'This barcode/SKU is already assigned.';
        }

        parsedRows.add(_ImportRow(
          spreadsheetRow: i + 1,
          name: name,
          sellingPrice: sellingPrice ?? 0,
          costPrice: costPrice ?? 0,
          stock: stock ?? 0,
          unit: unit,
          category: category.isEmpty ? 'General' : category,
          subCategory: subCategory,
          barcode: barcode,
          hsnCode: hsn,
          gstRate: gstRate,
          error: error,
        ));
      }

      if (!mounted) return;
      setState(() {
        _rows = parsedRows;
        _isReading = false;
      });
      if (parsedRows.isEmpty) {
        _showMessage('No product rows were found below the header row.');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isReading = false;
        _rows = [];
      });
      _showMessage(error is FormatException
          ? error.message
          : 'Could not read the Excel file: $error');
    }
  }

  Future<void> _importProducts() async {
    final rowsToImport = _rows.where((row) => row.error == null).toList();
    if (rowsToImport.isEmpty || _isImporting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import products?'),
        content: Text(
          'Add ${rowsToImport.length} products from "$_fileName". '
          '${_skippedCount == 0 ? '' : '$_skippedCount row(s) with errors or duplicates will be skipped.'} '
          'Existing products will not be overwritten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isImporting = true);
    try {
      final box = Hive.box<Product>(Boxes.products);
      final products = <String, Product>{};
      for (final row in rowsToImport) {
        final product = Product()
          ..id = const Uuid().v4()
          ..name = row.name
          ..sellingPrice = row.sellingPrice
          ..costPrice = row.costPrice
          ..stock = row.stock
          ..unit = row.unit
          ..category = row.category
          ..subCategory = row.subCategory
          ..active = true
          ..barcode = row.barcode.isEmpty ? null : row.barcode
          ..hsnCode = row.hsnCode
          ..gstRate = row.gstRate;
        products[product.id] = product;
      }
      await box.putAll(products);
      if (!mounted) return;
      setState(() {
        _importedCount = products.length;
        _isImporting = false;
      });
      _showMessage('Successfully imported ${products.length} products.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _isImporting = false);
      _showMessage('Import failed: $error');
    }
  }

  String _cellText(Data? cell) {
    final value = cell?.value;
    if (value == null) return '';
    if (value is TextCellValue) return value.value.toString();
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    if (value is BoolCellValue) return value.value.toString();
    return value.toString();
  }

  String _normaliseHeader(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  int _findColumn(List<String> headers, List<String> aliases) {
    for (var i = 0; i < headers.length; i++) {
      if (aliases.contains(headers[i])) return i;
    }
    return -1;
  }

  String _readColumn(List<Data?> row, int index) =>
      index >= 0 && index < row.length ? _cellText(row[index]) : '';

  String _readOptionalColumn(List<Data?> row, int index, String fallback) {
    if (index < 0 || index >= row.length) return fallback;
    final value = _cellText(row[index]);
    return value.trim().isEmpty ? fallback : value;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Bulk Import Products')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.table_view_outlined,
                              color: theme.colorScheme.primary, size: 30),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text('Import products from Excel',
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                          'Select an .xlsx file. Product Name and Selling Price columns are required.'),
                      const SizedBox(height: 12),
                      const Text(
                        'Columns: Product Name, Selling Price, Cost Price, Stock, Unit, Category, Subcategory, Barcode, HSN Code, GST Rate.',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Units: pcs, kg, sqft. Cost and stock default to 0. Duplicate names or barcodes are skipped.',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: _isReading || _isImporting
                                ? null
                                : _pickExcelFile,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Choose Excel file'),
                          ),
                          if (_fileName != null)
                            Chip(
                              avatar: const Icon(Icons.description_outlined,
                                  size: 18),
                              label: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 260),
                                child: Text(_fileName!,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          if (_isReading) const CircularProgressIndicator(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_importedCount != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline,
                            color: theme.colorScheme.onPrimaryContainer),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(
                                '$_importedCount products imported successfully.',
                                style: TextStyle(
                                    color: theme.colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w600))),
                        TextButton(
                          onPressed: () => setState(() {
                            _fileName = null;
                            _rows = [];
                            _importedCount = null;
                          }),
                          child: const Text('Import another file'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_rows.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Preview',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(label: Text('Rows: ${_rows.length}')),
                            Chip(label: Text('Ready to import: $_validCount')),
                            Chip(label: Text('Skipped: $_skippedCount')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._rows.take(100).map((row) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: row.error == null
                                    ? theme.colorScheme.primaryContainer
                                    : theme.colorScheme.errorContainer,
                                child: Text('${row.spreadsheetRow}',
                                    style: const TextStyle(fontSize: 11)),
                              ),
                              title: Text(row.name.isEmpty
                                  ? '(Unnamed product)'
                                  : row.name),
                              subtitle: Text(
                                row.error ??
                                    'Selling: ${row.sellingPrice.toStringAsFixed(2)} • Cost: ${row.costPrice.toStringAsFixed(2)} • Stock: ${row.stock} ${row.unit.name}',
                                style: TextStyle(
                                  color: row.error == null
                                      ? theme.colorScheme.onSurfaceVariant
                                      : theme.colorScheme.error,
                                ),
                              ),
                              trailing: Icon(
                                row.error == null
                                    ? Icons.check_circle_outline
                                    : Icons.error_outline,
                                color: row.error == null
                                    ? Colors.green
                                    : theme.colorScheme.error,
                              ),
                            )),
                        if (_rows.length > 100)
                          Text('Showing the first 100 of ${_rows.length} rows.',
                              style: theme.textTheme.bodySmall),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _validCount == 0 ||
                                    _isImporting ||
                                    _importedCount != null
                                ? null
                                : _importProducts,
                            icon: _isImporting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.playlist_add_check),
                            label: Text(_isImporting
                                ? 'Importing…'
                                : 'Import $_validCount products'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportRow {
  final int spreadsheetRow;
  final String name;
  final double sellingPrice;
  final double costPrice;
  final double stock;
  final UnitType unit;
  final String category;
  final String subCategory;
  final String barcode;
  final String hsnCode;
  final double? gstRate;
  final String? error;

  const _ImportRow({
    required this.spreadsheetRow,
    required this.name,
    required this.sellingPrice,
    required this.costPrice,
    required this.stock,
    required this.unit,
    required this.category,
    required this.subCategory,
    required this.barcode,
    required this.hsnCode,
    required this.gstRate,
    required this.error,
  });
}
