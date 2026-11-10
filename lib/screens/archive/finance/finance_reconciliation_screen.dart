import 'package:flutter/material.dart';

import '../../../widgets/finance_content_frame.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/finance_reconciliation_service.dart';
import '../../../services/finance_source_sync_service.dart';
import '../../../services/hr_payroll_service.dart';

class FinanceReconciliationScreen extends StatefulWidget {
  const FinanceReconciliationScreen({super.key});

  @override
  State<FinanceReconciliationScreen> createState() =>
      _FinanceReconciliationScreenState();
}

class _FinanceReconciliationScreenState
    extends State<FinanceReconciliationScreen> {
  bool _retrying = false;

  String _money(int paise) =>
      NumberFormat.simpleCurrency(locale: 'en_IN').format(paise / 100);

  Future<void> _retrySync() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      final issues = await FinanceSourceSyncService().syncAll(
        salesBox: Hive.box<Sale>(Boxes.sales),
        expensesBox: Hive.box<Expense>(Boxes.expenses),
        employeesBox: Hive.box<Employee>(Boxes.employees),
        accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts),
        transactionsBox:
            Hive.box<FinanceTransaction>(Boxes.financeTransactions),
        postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
        categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
        partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
      );
      final settings = Hive.box<dynamic>('app_settings');
      if (issues.isEmpty) {
        await settings.delete('finance_sync_errors');
      } else {
        await settings.put('finance_sync_errors', issues);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              issues.isEmpty
                  ? 'Source synchronization completed.'
                  : '${issues.length} source record(s) still need attention.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finance reconciliation')),
      body: ValueListenableBuilder<Box<Sale>>(
        valueListenable: Hive.box<Sale>(Boxes.sales).listenable(),
        builder: (context, salesBox, _) =>
            ValueListenableBuilder<Box<Expense>>(
          valueListenable: Hive.box<Expense>(Boxes.expenses).listenable(),
          builder: (context, expensesBox, __) =>
              ValueListenableBuilder<Box<FinanceTransaction>>(
            valueListenable: Hive.box<FinanceTransaction>(
              Boxes.financeTransactions,
            ).listenable(),
            builder: (context, transactionsBox, ___) =>
                ValueListenableBuilder<Box<Payslip>>(
              valueListenable: Hive.box<Payslip>(Boxes.payslips).listenable(),
              builder: (context, payslipsBox, ____) =>
                  ValueListenableBuilder<Box<dynamic>>(
                valueListenable: Hive.box<dynamic>('app_settings').listenable(keys: [HrPayrollService.employeeReimbursementsKey]),
                builder: (context, settingsBox, _____) =>
                    ValueListenableBuilder<Box<FinancePosting>>(
              valueListenable:
                  Hive.box<FinancePosting>(Boxes.financePostings).listenable(),
              builder: (context, postingsBox, ____) {
                final summary = const FinanceReconciliationService().reconcile(
                  sales: salesBox.values,
                  expenses: expensesBox.values,
                  transactions: transactionsBox.values,
                  postings: postingsBox.values,
                  payslips: payslipsBox.values,
                  reimbursements: (settingsBox.get(HrPayrollService.employeeReimbursementsKey, defaultValue: const <dynamic>[]) as List)
                      .whereType<Map>()
                      .map((entry) => Map<String, dynamic>.from(entry)),
                );
                return FinanceContentFrame(child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _status(summary),
                    const SizedBox(height: 16),
                    _section(
                      'Sales',
                      sourceCount: summary.sourceSaleCount,
                      journalCount: summary.journalSaleCount,
                      sourceTotal: summary.sourceSaleTotalPaise,
                      journalTotal: summary.journalSaleTotalPaise,
                      difference: summary.saleDifferencePaise,
                    ),
                    const SizedBox(height: 12),
                    _section(
                      'Expenses',
                      sourceCount: summary.sourceExpenseCount,
                      journalCount: summary.journalExpenseCount,
                      sourceTotal: summary.sourceExpenseTotalPaise,
                      journalTotal: summary.journalExpenseTotalPaise,
                      difference: summary.expenseDifferencePaise,
                    ),
                    const SizedBox(height: 12),
                    _section(
                      'Payroll accruals',
                      sourceCount: summary.payrollAccrualCount,
                      journalCount: summary.payrollAccrualCount,
                      sourceTotal: summary.payrollGrossPaise,
                      journalTotal: summary.payrollJournalGrossPaise,
                      difference: summary.payrollGrossDifferencePaise,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Payroll payable control', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 10),
                            _row('Payslip outstanding', _money(summary.payrollOutstandingPaise)),
                            _row('Ledger liability', _money(summary.payrollLiabilityPaise)),
                            const Divider(height: 20),
                            _row(
                              'Difference',
                              _money(summary.payrollLiabilityDifferencePaise),
                              valueColor: summary.payrollLiabilityDifferencePaise == 0
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _section(
                      'Employee reimbursements',
                      sourceCount: summary.reimbursementAccrualCount,
                      journalCount: summary.reimbursementAccrualCount,
                      sourceTotal: summary.reimbursementExpensePaise,
                      journalTotal: summary.reimbursementJournalExpensePaise,
                      difference: summary.reimbursementExpenseDifferencePaise,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Reimbursement payable control', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 10),
                            _row('Claim outstanding', _money(summary.reimbursementOutstandingPaise)),
                            _row('Ledger liability', _money(summary.reimbursementLiabilityPaise)),
                            const Divider(height: 20),
                            _row(
                              'Difference',
                              _money(summary.reimbursementLiabilityDifferencePaise),
                              valueColor: summary.reimbursementLiabilityDifferencePaise == 0
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _retrying ? null : _retrySync,
                      icon: _retrying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(
                        _retrying ? 'Synchronizing...' : 'Retry source synchronization',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Issues',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (summary.issues.isEmpty)
                      const ListTile(
                        leading: Icon(Icons.check_circle_outline),
                        title: Text('No reconciliation issues found'),
                        subtitle: Text(
                          'Current POS, expense, payroll, and reimbursement records match their posted journal entries.',
                        ),
                      )
                    else
                      for (final issue in summary.issues)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.warning_amber_rounded),
                            title: Text(issue.sourceId),
                            subtitle: Text(
                              '${issue.sourceType}\n${issue.message}',
                            ),
                            isThreeLine: true,
                          ),
                        ),
                    const SizedBox(height: 16),
                    Text(
                      'This report reconciles POS sales, expenses, payroll accruals and settlements, employee advances, and reimbursement claims against the journal. It does not reconcile bank statements or inventory cost of goods sold.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ));
              },
            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _status(FinanceReconciliationSummary summary) {
    final theme = Theme.of(context);
    final color = summary.isBalanced
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            summary.isBalanced
                ? Icons.verified_outlined
                : Icons.report_problem_outlined,
            color: color,
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.isBalanced ? 'Reconciliation passed' : 'Reconciliation needs attention',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  summary.isBalanced
                      ? 'All current source records have matching journal entries.'
                      : '${summary.issues.length} issue(s) found in source-to-journal matching.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    String title, {
    required int sourceCount,
    required int journalCount,
    required int sourceTotal,
    required int journalTotal,
    required int difference,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _row('Source records', sourceCount.toString()),
            _row('Journal entries', journalCount.toString()),
            _row('Source total', _money(sourceTotal)),
            _row('Journal total', _money(journalTotal)),
            const Divider(height: 20),
            _row(
              'Difference',
              _money(difference),
              valueColor: difference == 0
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ],
        ),
      );
}
