import 'dart:typed_data';

import 'package:excel_community/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/finance_reporting_service.dart';
import '../../../services/finance_service.dart';

class FinanceReportsScreen extends StatefulWidget {
  const FinanceReportsScreen({super.key});

  @override
  State<FinanceReportsScreen> createState() => _FinanceReportsScreenState();
}

class _FinanceReportsScreenState extends State<FinanceReportsScreen> {
  FinancePeriod _period = FinancePeriod.month;

  String _money(int paise) =>
      NumberFormat.simpleCurrency(locale: 'en_IN').format(paise / 100);

  String _date(DateTime value) => DateFormat('dd MMM yyyy').format(value);

  List<_TrialBalanceRow> _trialBalance({
    required List<FinanceAccount> accounts,
    required List<FinanceTransaction> transactions,
    required List<FinancePosting> postings,
    required DateSpan span,
  }) {
    final postedIds = transactions
        .where((transaction) =>
            transaction.status == 'posted' &&
            transaction.date.isBefore(span.end))
        .map((transaction) => transaction.id)
        .toSet();
    final rows = <_TrialBalanceRow>[];
    for (final account in accounts) {
      var rawBalance = 0;
      for (final line in postings) {
        if (line.accountId == account.id &&
            postedIds.contains(line.transactionId)) {
          rawBalance += line.debitPaise - line.creditPaise;
        }
      }
      if (rawBalance == 0) continue;
      rows.add(
        _TrialBalanceRow(
          account: account,
          debitPaise: rawBalance > 0 ? rawBalance : 0,
          creditPaise: rawBalance < 0 ? -rawBalance : 0,
        ),
      );
    }
    rows.sort((a, b) {
      final type = a.account.accountType.compareTo(b.account.accountType);
      return type != 0
          ? type
          : a.account.name.toLowerCase().compareTo(b.account.name.toLowerCase());
    });
    return rows;
  }

  Future<void> _exportPdf({
    required FinanceLedgerSummary summary,
    required List<_TrialBalanceRow> rows,
    required DateSpan span,
    required int debitTotal,
    required int creditTotal,
  }) async {
    final settings = Hive.box<dynamic>('app_settings');
    final businessName =
        settings.get('business_name', defaultValue: 'Billit').toString();
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: const pw.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(
            businessName.isEmpty ? 'Billit' : businessName,
            style: pw.TextStyle(
              fontSize: 21,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Accounting reports'),
          pw.Text('Period: ${_date(span.start)} – ${_date(span.end.subtract(const Duration(days: 1)))}'),
          pw.SizedBox(height: 18),
          pw.Text(
            'Profit and loss',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.Table.fromTextArray(
            headers: ['Metric', 'Amount'],
            data: [
              ['Income', _money(summary.incomePaise)],
              ['Expenses', _money(summary.expensePaise)],
              ['Net profit', _money(summary.netProfitPaise)],
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Cash flow',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.Table.fromTextArray(
            headers: ['Metric', 'Amount'],
            data: [
              ['Cash received', _money(summary.cashInPaise)],
              ['Cash paid', _money(summary.cashOutPaise)],
              ['Net cash flow', _money(summary.netCashFlowPaise)],
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Trial balance as at ${_date(span.end.subtract(const Duration(days: 1)))}',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.Table.fromTextArray(
            headers: ['Account', 'Type', 'Debit', 'Credit'],
            data: [
              for (final row in rows)
                [
                  row.account.name,
                  row.account.accountType,
                  _money(row.debitPaise),
                  _money(row.creditPaise),
                ],
              ['TOTAL', '', _money(debitTotal), _money(creditTotal)],
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            'Prepared from posted journal transactions. POS gross profit is not used as accounting net profit.',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(
      onLayout: (_) async => document.save(),
      name: 'billit-accounting-report.pdf',
    );
  }

  Future<void> _exportExcel({
    required FinanceLedgerSummary summary,
    required List<_TrialBalanceRow> rows,
    required DateSpan span,
    required int debitTotal,
    required int creditTotal,
  }) async {
    final workbook = Excel.createExcel();
    final summarySheet = workbook['Summary'];
    summarySheet.appendRow([
      TextCellValue('Metric'),
      TextCellValue('Amount (INR)'),
    ]);
    summarySheet.appendRow([
      TextCellValue('Period'),
      TextCellValue(
        '${_date(span.start)} – ${_date(span.end.subtract(const Duration(days: 1)))}',
      ),
    ]);
    summarySheet.appendRow([
      TextCellValue('Income'),
      IntCellValue(summary.incomePaise),
    ]);
    summarySheet.appendRow([
      TextCellValue('Expenses'),
      IntCellValue(summary.expensePaise),
    ]);
    summarySheet.appendRow([
      TextCellValue('Net profit'),
      IntCellValue(summary.netProfitPaise),
    ]);
    summarySheet.appendRow([
      TextCellValue('Cash received'),
      IntCellValue(summary.cashInPaise),
    ]);
    summarySheet.appendRow([
      TextCellValue('Cash paid'),
      IntCellValue(summary.cashOutPaise),
    ]);
    summarySheet.appendRow([
      TextCellValue('Net cash flow'),
      IntCellValue(summary.netCashFlowPaise),
    ]);

    final trialBalance = workbook['Trial Balance'];
    trialBalance.appendRow([
      TextCellValue('Account'),
      TextCellValue('Type'),
      TextCellValue('Debit (paise)'),
      TextCellValue('Credit (paise)'),
    ]);
    for (final row in rows) {
      trialBalance.appendRow([
        TextCellValue(row.account.name),
        TextCellValue(row.account.accountType),
        IntCellValue(row.debitPaise),
        IntCellValue(row.creditPaise),
      ]);
    }
    trialBalance.appendRow([
      TextCellValue('TOTAL'),
      TextCellValue(''),
      IntCellValue(debitTotal),
      IntCellValue(creditTotal),
    ]);

    final bytes = workbook.save();
    if (bytes == null) {
      throw StateError('Could not generate the accounting workbook.');
    }
    await FileSaver.instance.saveFile(
      name: 'billit-accounting-report',
      bytes: Uint8List.fromList(bytes),
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final span = FinanceService.spanFor(_period, DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('Accounting reports')),
      body: ValueListenableBuilder<Box<FinanceAccount>>(
        valueListenable:
            Hive.box<FinanceAccount>(Boxes.financeAccounts).listenable(),
        builder: (context, accountsBox, _) =>
            ValueListenableBuilder<Box<FinanceTransaction>>(
          valueListenable: Hive.box<FinanceTransaction>(
            Boxes.financeTransactions,
          ).listenable(),
          builder: (context, transactionsBox, __) =>
              ValueListenableBuilder<Box<FinancePosting>>(
            valueListenable:
                Hive.box<FinancePosting>(Boxes.financePostings).listenable(),
            builder: (context, postingsBox, ___) {
              final accounts = accountsBox.values.toList();
              final transactions = transactionsBox.values.toList();
              final postings = postingsBox.values.toList();
              final summary = const FinanceReportingService().summarize(
                accounts: accounts,
                transactions: transactions,
                postings: postings,
                span: span,
              );
              final rows = _trialBalance(
                accounts: accounts,
                transactions: transactions,
                postings: postings,
                span: span,
              );
              final debitTotal = rows.fold<int>(
                0,
                (sum, row) => sum + row.debitPaise,
              );
              final creditTotal = rows.fold<int>(
                0,
                (sum, row) => sum + row.creditPaise,
              );

              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  SegmentedButton<FinancePeriod>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: FinancePeriod.today,
                        label: Text('Today'),
                      ),
                      ButtonSegment(
                        value: FinancePeriod.month,
                        label: Text('Month'),
                      ),
                      ButtonSegment(
                        value: FinancePeriod.year,
                        label: Text('Year'),
                      ),
                    ],
                    selected: {_period},
                    onSelectionChanged: (value) =>
                        setState(() => _period = value.first),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${_date(span.start)} – ${_date(span.end.subtract(const Duration(days: 1)))}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 18),
                  _section(
                    context,
                    'Profit and loss',
                    [
                      _metric('Income', summary.incomePaise),
                      _metric('Expenses', summary.expensePaise),
                      _metric('Net profit', summary.netProfitPaise),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _section(
                    context,
                    'Cash flow',
                    [
                      _metric('Cash received', summary.cashInPaise),
                      _metric('Cash paid', summary.cashOutPaise),
                      _metric('Net cash flow', summary.netCashFlowPaise),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _section(
                    context,
                    'Trial balance',
                    [
                      _metric('Debit total', debitTotal),
                      _metric('Credit total', creditTotal),
                      _metric('Difference', debitTotal - creditTotal),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Account balances as at period end',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final row in rows)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(row.account.name),
                      subtitle: Text(row.account.accountType.toUpperCase()),
                      trailing: Text(
                        row.debitPaise > 0
                            ? 'Dr ${_money(row.debitPaise)}'
                            : 'Cr ${_money(row.creditPaise)}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text('No posted balances in the selected period.'),
                    ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => _exportPdf(
                      summary: summary,
                      rows: rows,
                      span: span,
                      debitTotal: debitTotal,
                      creditTotal: creditTotal,
                    ),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Print / export PDF'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _exportExcel(
                      summary: summary,
                      rows: rows,
                      span: span,
                      debitTotal: debitTotal,
                      creditTotal: creditTotal,
                    ),
                    icon: const Icon(Icons.table_view_outlined),
                    label: const Text('Export Excel workbook'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Reports use posted journal entries. Opening balances and internal transfers are excluded from cash-flow totals.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    List<Widget> children,
  ) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );

  Widget _metric(String label, int paise) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(
              _money(paise),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}

class _TrialBalanceRow {
  const _TrialBalanceRow({
    required this.account,
    required this.debitPaise,
    required this.creditPaise,
  });

  final FinanceAccount account;
  final int debitPaise;
  final int creditPaise;
}
