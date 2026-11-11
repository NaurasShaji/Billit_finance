import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../widgets/finance_content_frame.dart';

import '../../models/models.dart';
import '../../services/boxes.dart';
import '../../services/finance_service.dart';
import '../../services/finance_source_sync_service.dart';
import '../../services/finance_reporting_service.dart';
import '../../services/finance_recurring_service.dart';
import '../../utils/theme_colors.dart';
import '../../widgets/app_components.dart';
import '../archive/expenses/add_expense_screen.dart';
import '../archive/expenses/expenses_list_screen.dart';
import '../archive/gst_exports_screen.dart';
import '../archive/finance/finance_ledger_screen.dart';
import '../archive/finance/finance_reconciliation_screen.dart';
import '../archive/finance/finance_bank_reconciliation_screen.dart';
import '../archive/finance/finance_category_management_screen.dart';
import '../archive/finance/finance_reports_screen.dart';
import '../archive/finance/finance_parties_screen.dart';
import '../archive/finance/finance_budgets_screen.dart';
import '../archive/finance/finance_recurring_screen.dart';
import '../archive/finance/finance_payment_settings_screen.dart';

/// Top-level Finance screen: what came in, what went out, what is left.
class FinanceTab extends StatefulWidget {
  const FinanceTab({super.key});

  @override
  State<FinanceTab> createState() => _FinanceTabState();
}

class _FinanceTabState extends State<FinanceTab> {
  FinancePeriod _period = FinancePeriod.month;

  static const _periodLabels = {
    FinancePeriod.today: 'Today',
    FinancePeriod.month: 'This month',
    FinancePeriod.year: 'This year',
  };

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = NumberFormat.simpleCurrency(locale: 'en_IN');

    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<Box<FinanceTransaction>>(
          valueListenable: Hive.box<FinanceTransaction>(Boxes.financeTransactions).listenable(),
          builder: (context, transactionsBox, ___) =>
              ValueListenableBuilder<Box<Sale>>(
          valueListenable: Hive.box<Sale>(Boxes.sales).listenable(),
          builder: (context, salesBox, _) => ValueListenableBuilder<Box<Expense>>(
            valueListenable: Hive.box<Expense>(Boxes.expenses).listenable(),
            builder: (context, expensesBox, __) {
              final span = FinanceService.spanFor(_period, DateTime.now());
              final summary = FinanceService.summarize(
                sales: salesBox.values.toList(),
                expenses: expensesBox.values.toList(),
                span: span,
              );
              final paymentMappings = Hive.box<dynamic>('app_settings').get(
                FinanceSourceSyncService.paymentAccountSettingsKey,
              );
              final cashAccountIds = <String>{'system:cash', 'system:bank'};
              if (paymentMappings is Map) {
                cashAccountIds.addAll(paymentMappings.values.whereType<String>());
              }
              final accountingSummary = const FinanceReportingService().summarize(
                accounts: Hive.box<FinanceAccount>(Boxes.financeAccounts).values,
                transactions: transactionsBox.values,
                postings: Hive.box<FinancePosting>(Boxes.financePostings).values,
                span: span,
                cashAccountIds: cashAccountIds,
              );
              final settings = Hive.box<dynamic>('app_settings');
              final syncIssues = (settings.get(
                'finance_sync_errors',
                defaultValue: const <String>[],
              ) as List).cast<String>();
              final recurringIssues = (settings.get(
                'finance_recurring_errors',
                defaultValue: const <String>[],
              ) as List).cast<String>();

              return FinanceContentFrame(child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                children: [
                  _header(theme, scheme),
                  if (syncIssues.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _syncWarning(syncIssues.length),
                  ],
                  if (recurringIssues.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _recurringWarning(recurringIssues.length),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<FinancePeriod>(
                      showSelectedIcon: false,
                      segments: [
                        for (final p in FinancePeriod.values)
                          ButtonSegment(
                              value: p, label: Text(_periodLabels[p]!)),
                      ],
                      selected: {_period},
                      onSelectionChanged: (s) =>
                          setState(() => _period = s.first),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _NetProfitCard(summary: summary, currency: currency),
                  const SizedBox(height: 12),
                  _AccountingProfitCard(summary: accountingSummary, currency: currency),
                  const SizedBox(height: 12),
                  _metrics(summary, accountingSummary, currency),
                  const SizedBox(height: 24),
                  _sectionTitle(theme, scheme, 'RECORDED EXPENSE CATEGORIES'),
                  const SizedBox(height: 4),
                  Text(
                    'Category breakdown is based on expense records. Accrued payroll and other journal-only entries are reflected in Accounting P&L above.',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  _Breakdown(summary: summary, currency: currency),
                  const SizedBox(height: 24),
                  _recentHeader(theme, scheme),
                  const SizedBox(height: 6),
                  _recent(summary, currency),
                  const SizedBox(height: 24),
                  _sectionTitle(theme, scheme, 'FINANCE TOOLS'),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 2.15,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _financeAction(
                        label: 'Expense history',
                        icon: Icons.receipt_long_outlined,
                        onPressed: () => _open(const ExpensesListScreen()),
                      ),
                      _financeAction(
                        label: 'Reports & exports',
                        icon: Icons.file_download_outlined,
                        onPressed: () => _open(const GstExportsScreen()),
                      ),
                      _financeAction(
                        label: 'Accounting reports',
                        icon: Icons.assessment_outlined,
                        onPressed: () => _open(const FinanceReportsScreen()),
                      ),
                      _financeAction(
                        label: 'Accounts & journal',
                        icon: Icons.account_balance_outlined,
                        onPressed: () => _open(const FinanceLedgerScreen()),
                      ),
                      _financeAction(
                        label: 'Reconciliation',
                        icon: Icons.fact_check_outlined,
                        onPressed: () =>
                            _open(const FinanceReconciliationScreen()),
                      ),
                      _financeAction(
                        label: 'Bank reconciliation',
                        icon: Icons.account_balance_wallet_outlined,
                        onPressed: () =>
                            _open(const FinanceBankReconciliationScreen()),
                      ),
                      _financeAction(
                        label: 'Bank statements',
                        icon: Icons.account_balance_outlined,
                        onPressed: () =>
                            _open(const FinanceBankReconciliationScreen()),
                      ),
                      _financeAction(
                        label: 'Categories',
                        icon: Icons.category_outlined,
                        onPressed: () =>
                            _open(const FinanceCategoryManagementScreen()),
                      ),
                      _financeAction(
                        label: 'Customers & suppliers',
                        icon: Icons.people_outline,
                        onPressed: () => _open(const FinancePartiesScreen()),
                      ),
                      _financeAction(
                        label: 'Budgets',
                        icon: Icons.pie_chart_outline,
                        onPressed: () => _open(const FinanceBudgetsScreen()),
                      ),
                      _financeAction(
                        label: 'Recurring',
                        icon: Icons.event_repeat_outlined,
                        onPressed: () => _open(const FinanceRecurringScreen()),
                      ),
                      _financeAction(
                        label: 'Payment accounts',
                        icon: Icons.account_balance_wallet_outlined,
                        onPressed: () =>
                            _open(const FinancePaymentSettingsScreen()),
                      ),
                    ],
                  ),
                ],
              ));
            },
          ),
        ),
      ),
    ),
    );
  }

  Widget _financeAction({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: context.panelColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 20, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recurringWarning(int issueCount) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.event_busy_outlined, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$issueCount recurring transaction(s) could not be processed.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: _retryRecurring,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _retryRecurring() async {
    final result = await FinanceRecurringService().processDue();
    final settings = Hive.box<dynamic>('app_settings');
    if (result.issues.isEmpty) {
      await settings.delete('finance_recurring_errors');
    } else {
      await settings.put('finance_recurring_errors', result.issues);
    }
  }

  Widget _syncWarning(int issueCount) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$issueCount legacy record(s) still need finance journal sync.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: _retryFinanceSync,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _retryFinanceSync() async {
    final issues = await FinanceSourceSyncService().syncAll(
      salesBox: Hive.box<Sale>(Boxes.sales),
      expensesBox: Hive.box<Expense>(Boxes.expenses),
      employeesBox: Hive.box<Employee>(Boxes.employees),
      accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts),
      transactionsBox: Hive.box<FinanceTransaction>(Boxes.financeTransactions),
      postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
      categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
      partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
      settingsBox: Hive.box<dynamic>('app_settings'),
    );
    final settings = Hive.box<dynamic>('app_settings');
    if (issues.isEmpty) {
      await settings.delete('finance_sync_errors');
    } else {
      await settings.put('finance_sync_errors', issues);
    }
    if (mounted) setState(() {});
  }

  Widget _header(ThemeData theme, ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Finance',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'POS sales, expenses and accounting ledger',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: () => _open(const AddExpenseScreen()),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Expense'),
        ),
      ],
    );
  }

  Widget _sectionTitle(ThemeData theme, ColorScheme scheme, String text) {
    return Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: scheme.onSurface.withValues(alpha: 0.55),
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _metrics(FinanceSummary s, FinanceLedgerSummary accounting, NumberFormat currency) {
    final scheme = Theme.of(context).colorScheme;
    final cards = [
      _MetricTile(
        title: 'POS sales total',
        value: currency.format(s.revenue),
        icon: Icons.point_of_sale_rounded,
        color: scheme.primary,
      ),
      _MetricTile(
        title: 'POS gross profit estimate',
        value: currency.format(s.grossProfit),
        icon: Icons.trending_up_rounded,
        color: scheme.tertiary,
      ),
      _MetricTile(
        title: 'Accounting expenses',
        value: currency.format(accounting.expensePaise / 100),
        icon: Icons.receipt_long_outlined,
        color: scheme.error,
      ),
      _MetricTile(
        title: 'Net cash flow',
        value: currency.format(accounting.netCashFlowPaise / 100),
        icon: Icons.account_balance_wallet_outlined,
        color: scheme.secondary,
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 720 ? 4 : 2;
      const gap = 12.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final c in cards) SizedBox(width: width, child: c)],
      );
    });
  }

  Widget _recentHeader(ThemeData theme, ColorScheme scheme) {
    return Row(
      children: [
        Expanded(child: _sectionTitle(theme, scheme, 'RECENT EXPENSES')),
        TextButton(
          onPressed: () => _open(const ExpensesListScreen()),
          child: const Text('View all'),
        ),
      ],
    );
  }

  Widget _recent(FinanceSummary s, NumberFormat currency) {
    if (s.recent.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
          height: 290,
          child: AppEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No expenses ${_period == FinancePeriod.today ? 'today' : _period == FinancePeriod.month ? 'this month' : 'this year'}',
            message: 'Record rent, supplies, transport and other costs to see '
                'your real profit.',
            actions: [
              FilledButton.icon(
                onPressed: () => _open(const AddExpenseScreen()),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Record expense'),
              ),
            ],
          ),
        ),
      );
    }
    final dateFmt = DateFormat('dd MMM, hh:mm a');
    return Column(
      children: [
        for (final e in s.recent)
          _ExpenseRow(
            expense: e,
            amount: currency.format(e.amount),
            date: dateFmt.format(e.date),
          ),
      ],
    );
  }
}

class _NetProfitCard extends StatelessWidget {
  const _NetProfitCard({required this.summary, required this.currency});
  final FinanceSummary summary;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final positive = summary.netProfit >= 0;
    final tone = positive ? scheme.primary : scheme.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                positive ? Icons.savings_outlined : Icons.warning_amber_rounded,
                size: 20,
                color: tone.adaptive(context),
              ),
              const SizedBox(width: 8),
              Text(
                'POS net profit estimate',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: tone.adaptive(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              currency.format(summary.netProfit),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'POS gross profit − recorded expenses. This is not the accounting P&L.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountingProfitCard extends StatelessWidget {
  const _AccountingProfitCard({required this.summary, required this.currency});
  final FinanceLedgerSummary summary;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final positive = summary.netProfitPaise >= 0;
    final color = positive ? scheme.primary : scheme.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Accounting net profit', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(currency.format(summary.netProfitPaise / 100), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Posted journal income minus posted journal expenses. Payroll accruals are included.', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ]),
    );
  }
}
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.panelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color.adaptive(context)),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.summary, required this.currency});
  final FinanceSummary summary;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = summary.totalExpenses;

    if (summary.categories.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.panelColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          'Nothing spent in this period.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.62)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: context.panelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (final c in summary.categories)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        currency.format(c.amount),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          total <= 0
                              ? ''
                              : '${(c.amount / total * 100).toStringAsFixed(0)}%',
                          textAlign: TextAlign.right,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: total <= 0 ? 0 : (c.amount / total).clamp(0.0, 1.0),
                    minHeight: 7,
                    borderRadius: BorderRadius.circular(6),
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: c.isSalary
                        ? Theme.of(context).colorScheme.secondary
                        : Theme.of(context).colorScheme.error,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({
    required this.expense,
    required this.amount,
    required this.date,
  });

  final Expense expense;
  final String amount;
  final String date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final salary = FinanceService.isSalary(expense);
    final color = salary ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.error;
    final title = expense.description.trim().isNotEmpty
        ? expense.description.trim()
        : FinanceService.categoryLabel(expense.category);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          salary ? Icons.payments_outlined : Icons.receipt_long_outlined,
          color: color.adaptive(context),
          size: 21,
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${FinanceService.categoryLabel(expense.category)} · $date',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
      ),
      trailing: Text(
        amount,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}