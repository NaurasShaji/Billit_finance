import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';
import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../widgets/responsive_page.dart';

class PayrollReportScreen extends StatefulWidget {
  const PayrollReportScreen({super.key});

  @override
  State<PayrollReportScreen> createState() => _PayrollReportScreenState();
}

class _PayrollReportScreenState extends State<PayrollReportScreen>
    with SingleTickerProviderStateMixin {
  String _filter = 'all'; // all | salary | other
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency(locale: 'en_IN');
    final dateFmt = DateFormat('dd MMM yyyy');
    return ResponsivePage(child: Scaffold(
      appBar: AppBar(
        title: const Text('Payroll Report'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Daily'),
            Tab(text: 'Monthly'),
            Tab(text: 'Yearly'),
          ],
        ),
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box<Expense>(Boxes.expenses).listenable(),
        builder: (context, Box<Expense> expBox, _) =>
            ValueListenableBuilder<Box<Payslip>>(
          valueListenable: Hive.box<Payslip>(Boxes.payslips).listenable(),
          builder: (context, payslipsBox, __) {
          final now = DateTime.now();
          DateTime rangeStart;
          DateTime rangeEnd;
          if (_tab.index == 0) {
            // Daily
            rangeStart = DateTime(now.year, now.month, now.day);
            rangeEnd = rangeStart.add(const Duration(days: 1));
          } else if (_tab.index == 1) {
            // Monthly
            rangeStart = DateTime(now.year, now.month, 1);
            rangeEnd = DateTime(now.year, now.month + 1, 1);
          } else {
            // Yearly
            rangeStart = DateTime(now.year, 1, 1);
            rangeEnd = DateTime(now.year + 1, 1, 1);
          }

          final all = expBox.values
              .where((e) =>
                  !e.date.isBefore(rangeStart) && e.date.isBefore(rangeEnd))
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          final payrollRuns = Hive.box<PayrollRun>(Boxes.payrollRuns).values
              .where((run) => !run.periodEnd.isBefore(rangeStart) && run.periodEnd.isBefore(rangeEnd))
              .toList();
          final runIds = payrollRuns.map((run) => run.id).toSet();
          final payrollTransactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions).values;
          final accruedSlips = payslipsBox.values
              .where((slip) => runIds.contains(slip.payrollRunId) &&
                  payrollTransactions.any((tx) => tx.sourceType == 'payroll_accrual' && tx.sourceId == slip.id && tx.status == 'posted'))
              .toList();
          final accruedGross = accruedSlips.fold<int>(0, (sum, slip) => sum + slip.basePaise + slip.allowancesPaise);
          final accruedDeductions = accruedSlips.fold<int>(0, (sum, slip) => sum + slip.deductionsPaise);
          final accruedNet = accruedSlips.fold<int>(0, (sum, slip) => sum + slip.netPaise);
          final accruedPaid = accruedSlips.fold<int>(0, (sum, slip) => sum + slip.paidPaise);
          final accruedOutstanding = accruedSlips.fold<int>(0, (sum, slip) => sum + slip.outstandingPaise);
          final salaryMonthly = all
              .where((e) => e.category == 'Salary-Monthly')
              .fold<double>(0, (s, e) => s + e.amount);
          final salaryDaily = all
              .where((e) => e.category == 'Salary-Daily')
              .fold<double>(0, (s, e) => s + e.amount);
          final salaryRun = all
              .where((e) => e.category == 'Salary-Run')
              .fold<double>(0, (s, e) => s + e.amount);
          final otherExpenses = all
              .where((e) => !(e.category == 'Salary-Monthly' ||
                  e.category == 'Salary-Daily' || e.category == 'Salary-Run'))
              .fold<double>(0, (s, e) => s + e.amount);
          final totalSalary = salaryMonthly + salaryDaily + salaryRun;
          final netExpenses = totalSalary + otherExpenses;

          List<Expense> filtered = all;
          if (_filter == 'salary') {
            filtered = all
                .where((e) =>
                    e.category == 'Salary-Monthly' ||
                    e.category == 'Salary-Daily' ||
                    e.category == 'Salary-Run')
                .toList();
          } else if (_filter == 'other') {
            filtered = all
                .where((e) => !(e.category == 'Salary-Monthly' ||
                    e.category == 'Salary-Daily' || e.category == 'Salary-Run'))
                .toList();
          }

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Accrued payroll', style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            _row('Gross accrued', currency.format(accruedGross / 100)),
                            _row('Deductions', currency.format(accruedDeductions / 100)),
                            _row('Net payable', currency.format(accruedNet / 100)),
                            _row('Paid', currency.format(accruedPaid / 100)),
                            _row('Outstanding', currency.format(accruedOutstanding / 100), isBold: true),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [
                              Icon(Icons.payments),
                              SizedBox(width: 8),
                              Text('Legacy and direct expense records',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                            ]),
                            const SizedBox(height: 8),
                            _row('Monthly Salaries',
                                currency.format(salaryMonthly)),
                            _row('Daily Wages', currency.format(salaryDaily)),
                            _row('Payroll run payments', currency.format(salaryRun)),
                            _row('Other Expenses',
                                currency.format(otherExpenses)),
                            const Divider(height: 20),
                            _row('Net Expense', currency.format(netExpenses),
                                isBold: true),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          selected: _filter == 'all',
                          onSelected: (_) => setState(() => _filter = 'all'),
                        ),
                        ChoiceChip(
                          label: const Text('Salary Only'),
                          selected: _filter == 'salary',
                          onSelected: (_) => setState(() => _filter = 'salary'),
                        ),
                        ChoiceChip(
                          label: const Text('Other Only'),
                          selected: _filter == 'other',
                          onSelected: (_) => setState(() => _filter = 'other'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Center(child: Text('No expense records')),
                      )
                    else
                      ...filtered.map((e) => ListTile(
                            leading: Icon(
                              e.category == 'Salary-Monthly' ||
                                      e.category == 'Salary-Daily'
                                  ? Icons.wallet
                                  : Icons.receipt,
                            ),
                            title: Text(e.description.isNotEmpty
                                ? e.description
                                : e.category),
                            subtitle: Text(dateFmt.format(e.date)),
                            trailing: Text(
                              currency.format(e.amount),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          )),
                  ],
                ),
              ),
            ],
          );
          },
        ),
      ),
    ));
  }

  Widget _row(String title, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontWeight:
                          isBold ? FontWeight.w600 : FontWeight.normal))),
          Text(value,
              style: TextStyle(
                  fontWeight: isBold ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}
