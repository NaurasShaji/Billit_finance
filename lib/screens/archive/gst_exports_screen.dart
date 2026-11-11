import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/models.dart';
import '../../services/boxes.dart';

class GstExportsScreen extends StatefulWidget {
  const GstExportsScreen({super.key});

  @override
  State<GstExportsScreen> createState() => _GstExportsScreenState();
}

class _GstExportsScreenState extends State<GstExportsScreen> {
  bool _singleDayStatement = true;
  DateTime _statementStart = DateTime.now();
  DateTime _statementEnd = DateTime.now();
  bool _exportingStatement = false;
  bool _exportingPdf = false;

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Future<void> _pickStatementDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _statementStart : _statementEnd,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (_singleDayStatement) {
        _statementStart = picked;
        _statementEnd = picked;
      } else if (isStart) {
        _statementStart = picked;
        if (_statementEnd.isBefore(_statementStart)) {
          _statementEnd = _statementStart;
        }
      } else {
        _statementEnd = picked;
        if (_statementEnd.isBefore(_statementStart)) {
          _statementStart = _statementEnd;
        }
      }
    });
  }

  Future<void> _exportSalesStatementPdf({bool share = false}) async {
    if (_exportingPdf) return;
    final startDate = _dateOnly(_statementStart);
    final endDate =
        _dateOnly(_singleDayStatement ? _statementStart : _statementEnd);
    final endExclusive = endDate.add(const Duration(days: 1));
    final sales = Hive.box<Sale>(Boxes.sales).values.where((sale) {
      final date = sale.date.toLocal();
      return !date.isBefore(startDate) && date.isBefore(endExclusive);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    if (sales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No sales found for the selected date period.')),
      );
      return;
    }

    setState(() => _exportingPdf = true);
    try {
      final totalSales =
          sales.fold<double>(0, (sum, sale) => sum + sale.totalAmount);
      final totalDiscount =
          sales.fold<double>(0, (sum, sale) => sum + sale.discount);
      final paymentTotals = <PaymentMethod, double>{PaymentMethod.cash: 0, PaymentMethod.card: 0, PaymentMethod.upi: 0};
      final paymentCounts = <PaymentMethod, int>{PaymentMethod.cash: 0, PaymentMethod.card: 0, PaymentMethod.upi: 0};
      for (final sale in sales) {
        paymentTotals[sale.payment] = (paymentTotals[sale.payment] ?? 0) + sale.totalAmount;
        paymentCounts[sale.payment] = (paymentCounts[sale.payment] ?? 0) + 1;
      }
      final totalTax = sales.fold<double>(
        0,
        (sum, sale) =>
            sum + sale.cgstAmount + sale.sgstAmount + sale.igstAmount,
      );
      final rows = <List<String>>[
        [
          'Period',
          '${DateFormat('dd MMM yyyy').format(startDate)} - ${DateFormat('dd MMM yyyy').format(endDate)}'
        ],
        ['Total Invoices', sales.length.toString()],
        ['Total Sales', totalSales.toStringAsFixed(2)],
        ['Total Discounts', totalDiscount.toStringAsFixed(2)],
        ['Total GST', totalTax.toStringAsFixed(2)],
        ['PAYMENT METHOD SUMMARY', '', ''],
        ['Payment Method', 'Transactions', 'Amount'],
        ['Cash', paymentCounts[PaymentMethod.cash].toString(), (paymentTotals[PaymentMethod.cash] ?? 0).toStringAsFixed(2)],
        ['Card', paymentCounts[PaymentMethod.card].toString(), (paymentTotals[PaymentMethod.card] ?? 0).toStringAsFixed(2)],
        ['UPI', paymentCounts[PaymentMethod.upi].toString(), (paymentTotals[PaymentMethod.upi] ?? 0).toStringAsFixed(2)],
        ['Total Collected', sales.length.toString(), totalSales.toStringAsFixed(2)],
        [
          'Invoice No',
          'Date & Time',
          'Customer',
          'Phone',
          'Payment',
          'Subtotal',
          'Discount',
          'Taxable',
          'CGST',
          'SGST',
          'IGST',
          'Total GST',
          'Invoice Total'
        ],
        for (final sale in sales)
          [
            sale.id,
            DateFormat('yyyy-MM-dd HH:mm:ss').format(sale.date.toLocal()),
            sale.customerName,
            sale.customerPhone,
            sale.payment.name.toUpperCase(),
            sale.items
                .fold<double>(0, (sum, item) => sum + item.subtotal)
                .toStringAsFixed(2),
            sale.discount.toStringAsFixed(2),
            (sale.gstEnabled
                    ? sale.taxableAmount
                    : sale.items.fold<double>(
                            0, (sum, item) => sum + item.subtotal) -
                        sale.discount)
                .toStringAsFixed(2),
            sale.cgstAmount.toStringAsFixed(2),
            sale.sgstAmount.toStringAsFixed(2),
            sale.igstAmount.toStringAsFixed(2),
            (sale.cgstAmount + sale.sgstAmount + sale.igstAmount)
                .toStringAsFixed(2),
            sale.totalAmount.toStringAsFixed(2),
          ],
      ];
      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (context) => [
            pw.Text('Billit - Sales Statement',
                style:
                    pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              data: rows,
              headerCount: 0,
              cellStyle: const pw.TextStyle(fontSize: 6.5),
              cellPadding:
                  const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
            ),
          ],
        ),
      );
      final filename = _singleDayStatement
          ? 'sales_statement_${DateFormat('yyyyMMdd').format(startDate)}.pdf'
          : 'sales_statement_${DateFormat('yyyyMMdd').format(startDate)}_to_${DateFormat('yyyyMMdd').format(endDate)}.pdf';
      final bytes = await document.save();
      if (share) {
        await _shareFile(filename, bytes, 'application/pdf');
      } else {
        await _downloadFile(filename, bytes);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _exportSalesStatement({bool share = false}) async {
    if (_exportingStatement) return;
    final start = _dateOnly(_statementStart);
    final end =
        _dateOnly(_singleDayStatement ? _statementStart : _statementEnd);
    final endExclusive = end.add(const Duration(days: 1));
    final sales = Hive.box<Sale>(Boxes.sales).values.where((sale) {
      final date = sale.date.toLocal();
      return !date.isBefore(start) && date.isBefore(endExclusive);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    if (sales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No sales found for the selected date period.')),
      );
      return;
    }

    setState(() => _exportingStatement = true);
    try {
      final totalSales =
          sales.fold<double>(0, (sum, sale) => sum + sale.totalAmount);
      final totalDiscount =
          sales.fold<double>(0, (sum, sale) => sum + sale.discount);
      final paymentTotals = <PaymentMethod, double>{PaymentMethod.cash: 0, PaymentMethod.card: 0, PaymentMethod.upi: 0};
      final paymentCounts = <PaymentMethod, int>{PaymentMethod.cash: 0, PaymentMethod.card: 0, PaymentMethod.upi: 0};
      for (final sale in sales) {
        paymentTotals[sale.payment] = (paymentTotals[sale.payment] ?? 0) + sale.totalAmount;
        paymentCounts[sale.payment] = (paymentCounts[sale.payment] ?? 0) + 1;
      }
      final totalTax = sales.fold<double>(
        0,
        (sum, sale) =>
            sum + sale.cgstAmount + sale.sgstAmount + sale.igstAmount,
      );
      final rows = <List<Object?>>[
        ['SALES STATEMENT'],
        [
          'Period',
          '${DateFormat('dd MMM yyyy').format(start)} - ${DateFormat('dd MMM yyyy').format(end)}'
        ],
        ['Total Invoices', sales.length],
        ['Total Sales', totalSales.toStringAsFixed(2)],
        ['Total Discounts', totalDiscount.toStringAsFixed(2)],
        ['Total GST', totalTax.toStringAsFixed(2)],
        [],
        ['PAYMENT METHOD SUMMARY'],
        ['Payment Method', 'Transactions', 'Amount'],
        ['Cash', paymentCounts[PaymentMethod.cash] ?? 0, (paymentTotals[PaymentMethod.cash] ?? 0).toStringAsFixed(2)],
        ['Card', paymentCounts[PaymentMethod.card] ?? 0, (paymentTotals[PaymentMethod.card] ?? 0).toStringAsFixed(2)],
        ['UPI', paymentCounts[PaymentMethod.upi] ?? 0, (paymentTotals[PaymentMethod.upi] ?? 0).toStringAsFixed(2)],
        ['Total Collected', sales.length, totalSales.toStringAsFixed(2)],
        [],
        [
          'Invoice No',
          'Date & Time',
          'Customer',
          'Phone',
          'Payment Method',
          'Subtotal',
          'Discount',
          'Taxable Value',
          'CGST',
          'SGST',
          'IGST',
          'Total GST',
          'Invoice Total'
        ],
        for (final sale in sales)
          [
            sale.id,
            DateFormat('yyyy-MM-dd HH:mm:ss').format(sale.date.toLocal()),
            sale.customerName,
            sale.customerPhone,
            sale.payment.name.toUpperCase(),
            sale.items
                .fold<double>(0, (sum, item) => sum + item.subtotal)
                .toStringAsFixed(2),
            sale.discount.toStringAsFixed(2),
            (sale.gstEnabled
                    ? sale.taxableAmount
                    : sale.items.fold<double>(
                            0, (sum, item) => sum + item.subtotal) -
                        sale.discount)
                .toStringAsFixed(2),
            sale.cgstAmount.toStringAsFixed(2),
            sale.sgstAmount.toStringAsFixed(2),
            sale.igstAmount.toStringAsFixed(2),
            (sale.cgstAmount + sale.sgstAmount + sale.igstAmount)
                .toStringAsFixed(2),
            sale.totalAmount.toStringAsFixed(2),
          ],
      ];
      final filename = _singleDayStatement
          ? 'sales_statement_${DateFormat('yyyyMMdd').format(start)}.csv'
          : 'sales_statement_${DateFormat('yyyyMMdd').format(start)}_to_${DateFormat('yyyyMMdd').format(end)}.csv';
      if (share) {
        await _shareCsv(filename, rows);
      } else {
        await _downloadCsv(filename, rows);
      }
    } finally {
      if (mounted) setState(() => _exportingStatement = false);
    }
  }

  Widget _dateSelectionTile({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      child: ListTile(
        leading: const Icon(Icons.calendar_month_outlined),
        title: Text(label),
        subtitle: Text(DateFormat('dd MMM yyyy').format(date)),
        trailing: const Icon(Icons.edit_calendar_outlined),
        onTap: onTap,
      ),
    );
  }

  String _csvCell(Object? value) {
    final text = (value ?? '').toString().replaceAll('"', '""');
    return '"$text"';
  }

  Future<void> _downloadFile(String filename, List<int> bytes) async {
    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save export',
      fileName: filename,
      bytes: Uint8List.fromList(bytes),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(savedPath == null
            ? 'Export cancelled.'
            : 'File saved successfully.'),
      ),
    );
  }

  Future<void> _downloadCsv(String filename, List<List<Object?>> rows) async {
    try {
      final csv = rows.map((row) => row.map(_csvCell).join(',')).join('\\r\\n');
      await _downloadFile(filename, utf8.encode(csv));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save CSV: $e')),
      );
    }
  }

  Future<void> _shareFile(String filename, List<int> bytes, String mimeType) async {
    await Share.shareXFiles(
      [
        XFile.fromData(
          Uint8List.fromList(bytes),
          mimeType: mimeType,
          name: filename,
        ),
      ],
      subject: filename,
    );
  }

  Future<void> _shareCsv(String filename, List<List<Object?>> rows) async {
    final csv = rows.map((row) => row.map(_csvCell).join(',')).join('\\r\\n');
    await _shareFile(filename, utf8.encode(csv), 'text/csv');
  }

  Future<void> _exportGstSalesRegister({bool share = false}) async {
    final sales = Hive.box<Sale>(Boxes.sales).values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final rows = <List<Object?>>[
      [
        'Invoice No',
        'Date',
        'Customer',
        'Phone',
        'Customer GSTIN',
        'Subtotal',
        'Discount',
        'Taxable Value',
        'CGST',
        'SGST',
        'IGST',
        'Total GST',
        'Invoice Total',
        'Payment',
        'Tax Type',
        'HSN/SAC Summary',
        'GST Rate Summary'
      ],
      for (final sale in sales)
        [
          sale.id,
          DateFormat('yyyy-MM-dd HH:mm:ss').format(sale.date.toLocal()),
          sale.customerName,
          sale.customerPhone,
          sale.customerGstin,
          sale.items
              .fold<double>(0, (sum, item) => sum + item.subtotal)
              .toStringAsFixed(2),
          sale.discount.toStringAsFixed(2),
          (sale.gstEnabled
                  ? sale.taxableAmount
                  : (sale.items
                          .fold<double>(0, (sum, item) => sum + item.subtotal) -
                      sale.discount))
              .toStringAsFixed(2),
          sale.cgstAmount.toStringAsFixed(2),
          sale.sgstAmount.toStringAsFixed(2),
          sale.igstAmount.toStringAsFixed(2),
          (sale.cgstAmount + sale.sgstAmount + sale.igstAmount)
              .toStringAsFixed(2),
          sale.totalAmount.toStringAsFixed(2),
          sale.payment.name.toUpperCase(),
          sale.gstEnabled
              ? (sale.interstateSale ? 'IGST' : 'CGST+SGST')
              : 'No GST',
          sale.items
              .map((item) => item.hsnCode)
              .where((code) => code.isNotEmpty)
              .toSet()
              .join('; '),
          sale.items
              .map((item) => item.gstRate ?? 0.0)
              .where((rate) => rate > 0)
              .toSet()
              .join('; '),
        ],
    ];
    if (share) {
      await _shareCsv('billit_gst_sales_register.csv', rows);
    } else {
      await _downloadCsv('billit_gst_sales_register.csv', rows);
    }
  }

  Future<void> _exportGstItemRegister({bool share = false}) async {
    final sales = Hive.box<Sale>(Boxes.sales).values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final products = Hive.box<Product>(Boxes.products);
    final rows = <List<Object?>>[
      [
        'Invoice No',
        'Date',
        'Customer',
        'Customer GSTIN',
        'Product',
        'HSN/SAC',
        'Quantity',
        'Unit Rate',
        'Taxable Value',
        'GST Rate %',
        'CGST',
        'SGST',
        'IGST',
        'Line Total'
      ],
      for (final sale in sales)
        for (final item in sale.items)
          [
            sale.id,
            DateFormat('yyyy-MM-dd').format(sale.date.toLocal()),
            sale.customerName,
            sale.customerGstin,
            products.get(item.productId)?.name ?? 'Unknown Product',
            item.hsnCode.isNotEmpty
                ? item.hsnCode
                : (products.get(item.productId)?.hsnCode ?? ''),
            item.qty,
            item.sellingPrice.toStringAsFixed(2),
            (sale.gstEnabled ? item.taxableAmount : item.subtotal)
                .toStringAsFixed(2),
            sale.gstEnabled ? (item.gstRate ?? 0.0).toStringAsFixed(2) : '0.00',
            item.cgstAmount.toStringAsFixed(2),
            item.sgstAmount.toStringAsFixed(2),
            item.igstAmount.toStringAsFixed(2),
            ((sale.gstEnabled ? item.taxableAmount : item.subtotal) +
                    item.cgstAmount +
                    item.sgstAmount +
                    item.igstAmount)
                .toStringAsFixed(2),
          ],
    ];
    if (share) {
      await _shareCsv('billit_gst_item_register.csv', rows);
    } else {
      await _downloadCsv('billit_gst_item_register.csv', rows);
    }
  }

  Future<void> _exportExpensesRegister({bool share = false}) async {
    final expenses = Hive.box<Expense>(Boxes.expenses).values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final rows = <List<Object?>>[
      ['Expense ID', 'Date', 'Category', 'Description', 'Amount'],
      for (final expense in expenses)
        [
          expense.id,
          DateFormat('yyyy-MM-dd').format(expense.date.toLocal()),
          expense.category,
          expense.description,
          expense.amount.toStringAsFixed(2),
        ],
    ];
    if (share) {
      await _shareCsv('billit_expenses_register.csv', rows);
    } else {
      await _downloadCsv('billit_expenses_register.csv', rows);
    }
  }

  Widget _exportOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required VoidCallback onShare,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share_outlined),
              onPressed: onShare,
            ),
            const Icon(Icons.file_download_outlined),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports & Statements')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Sales statements and tax exports',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Export sales, GST and expense reports.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 22),
          Text(
            'Sales Statements',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Export invoice-wise sales as CSV or PDF.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: true,
                  label: Text('Single day'),
                  icon: Icon(Icons.today_outlined)),
              ButtonSegment(
                  value: false,
                  label: Text('Date range'),
                  icon: Icon(Icons.date_range_outlined)),
            ],
            selected: {_singleDayStatement},
            onSelectionChanged: (values) => setState(() {
              _singleDayStatement = values.first;
              if (_singleDayStatement) _statementEnd = _statementStart;
            }),
          ),
          const SizedBox(height: 12),
          _dateSelectionTile(
            label: _singleDayStatement ? 'Statement date' : 'From date',
            date: _statementStart,
            onTap: () => _pickStatementDate(isStart: true),
          ),
          if (!_singleDayStatement) ...[
            const SizedBox(height: 8),
            _dateSelectionTile(
              label: 'To date',
              date: _statementEnd,
              onTap: () => _pickStatementDate(isStart: false),
            ),
          ],
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.35,
            children: [
              SizedBox.expand(
                child: FilledButton.icon(
                  onPressed: _exportingStatement || _exportingPdf
                      ? null
                      : _exportSalesStatement,
                  icon: const Icon(Icons.table_view_outlined, size: 19),
                  label: const Text('Download CSV', maxLines: 1, softWrap: false),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              SizedBox.expand(
                child: OutlinedButton.icon(
                  onPressed: _exportingStatement || _exportingPdf
                      ? null
                      : () => _exportSalesStatementPdf(),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 19),
                  label: const Text('Download PDF', maxLines: 1, softWrap: false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              SizedBox.expand(
                child: OutlinedButton.icon(
                  onPressed: _exportingStatement || _exportingPdf
                      ? null
                      : () => _exportSalesStatement(share: true),
                  icon: const Icon(Icons.share_outlined, size: 19),
                  label: const Text('Share CSV', maxLines: 1, softWrap: false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              SizedBox.expand(
                child: OutlinedButton.icon(
                  onPressed: _exportingStatement || _exportingPdf
                      ? null
                      : () => _exportSalesStatementPdf(share: true),
                  icon: const Icon(Icons.share_outlined, size: 19),
                  label: const Text('Share PDF', maxLines: 1, softWrap: false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'GST & Accounting Exports',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _exportOption(
            icon: Icons.receipt_long_outlined,
            title: 'GST Sales Register',
            subtitle:
                'Invoice-wise taxable value, GST and customer details.',
            onTap: _exportGstSalesRegister,
            onShare: () => _exportGstSalesRegister(share: true),
          ),
          _exportOption(
            icon: Icons.table_chart_outlined,
            title: 'GST Item Register',
            subtitle:
                'Product-wise HSN/SAC and tax summary.',
            onTap: _exportGstItemRegister,
            onShare: () => _exportGstItemRegister(share: true),
          ),
          _exportOption(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Expenses Register',
            subtitle:
                'Export expense details.',
            onTap: _exportExpensesRegister,
            onShare: () => _exportExpensesRegister(share: true),
          ),
        ],
      ),
    );
  }
}
