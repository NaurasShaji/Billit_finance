import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';
import '../../../services/boxes.dart';
import '../../../services/finance_source_sync_service.dart';
import '../../../models/models.dart';
import '../../../utils/theme_colors.dart';
import '../../../widgets/responsive_page.dart';

class ExpensesListScreen extends StatefulWidget {
  const ExpensesListScreen({super.key});

  @override
  State<ExpensesListScreen> createState() => _ExpensesListScreenState();
}

class _ExpensesListScreenState extends State<ExpensesListScreen>
    with SingleTickerProviderStateMixin {
  String _filter = 'all';
  late TabController _tab;
  DateTime _anchor = DateTime.now();

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
    final theme = Theme.of(context);
    final currency = NumberFormat.simpleCurrency(locale: 'en_IN');
    final dateFmt = DateFormat('dd MMM yyyy');
    final monthFmt = DateFormat('MMMM yyyy');

    return ResponsivePage(child: Scaffold(
      backgroundColor:
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      appBar: AppBar(
        title: const Text('Expense Records'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tab,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              indicator: BoxDecoration(
                color: context.panelColor,
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Daily'),
                Tab(text: 'Monthly'),
                Tab(text: 'Yearly'),
              ],
            ),
          ),
        ),
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box<Expense>(Boxes.expenses).listenable(),
        builder: (context, Box<Expense> box, _) {
          DateTime rangeStart;
          DateTime rangeEnd;

          if (_tab.index == 0) {
            rangeStart = DateTime(_anchor.year, _anchor.month, _anchor.day);
            rangeEnd = rangeStart.add(const Duration(days: 1));
          } else if (_tab.index == 1) {
            rangeStart = DateTime(_anchor.year, _anchor.month, 1);
            rangeEnd = DateTime(_anchor.year, _anchor.month + 1, 1);
          } else {
            rangeStart = DateTime(_anchor.year, 1, 1);
            rangeEnd = DateTime(_anchor.year + 1, 1, 1);
          }

          final all = box.values
              .where((e) =>
                  !e.date.isBefore(rangeStart) && e.date.isBefore(rangeEnd))
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));

          final salaryMonthly = all
              .where((e) => e.category == 'Salary-Monthly')
              .fold<double>(0, (s, e) => s + e.amount);
          final salaryDaily = all
              .where((e) => e.category == 'Salary-Daily')
              .fold<double>(0, (s, e) => s + e.amount);
          final otherExpenses = all
              .where((e) => !(e.category == 'Salary-Monthly' ||
                  e.category == 'Salary-Daily'))
              .fold<double>(0, (s, e) => s + e.amount);
          final totalSalary = salaryMonthly + salaryDaily;
          final netExpenses = totalSalary + otherExpenses;

          List<Expense> filtered = all;
          if (_filter == 'salary') {
            filtered = all
                .where((e) =>
                    e.category == 'Salary-Monthly' ||
                    e.category == 'Salary-Daily')
                .toList();
          } else if (_filter == 'other') {
            filtered = all
                .where((e) => !(e.category == 'Salary-Monthly' ||
                    e.category == 'Salary-Daily'))
                .toList();
          }

          return Column(
            children: [
              // Professional Date Navigation Header
              Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.08),
                      offset: const Offset(0, 2),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          tooltip: 'Previous',
                          icon: Icon(Icons.chevron_left,
                              color: theme.colorScheme.error),
                          onPressed: () =>
                              setState(() => _anchor = _previous(_anchor)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: TextButton.icon(
                            onPressed: _pickPeriod,
                            icon: Icon(Icons.calendar_today,
                                color: theme.colorScheme.secondary, size: 20),
                            label: Text(
                              _tab.index == 0
                                  ? dateFmt.format(_anchor)
                                  : _tab.index == 1
                                      ? monthFmt.format(_anchor)
                                      : _anchor.year.toString(),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.secondary,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          tooltip: 'Next',
                          icon: Icon(Icons.chevron_right,
                              color: theme.colorScheme.error),
                          onPressed: () =>
                              setState(() => _anchor = _next(_anchor)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // Enhanced Summary Card
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.08),
                              offset: const Offset(0, 4),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.analytics_outlined,
                                      color: theme.colorScheme.primary,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Financial Summary',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Expense breakdown for selected period',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // Expense Categories
                              _buildSummaryRow(
                                'Monthly Salaries',
                                currency.format(salaryMonthly),
                                Icons.payments_outlined,
                                theme.colorScheme.secondary,
                              ),
                              const SizedBox(height: 12),
                              _buildSummaryRow(
                                'Daily Wages',
                                currency.format(salaryDaily),
                                Icons.schedule_outlined,
                                theme.colorScheme.tertiary,
                              ),
                              const SizedBox(height: 12),
                              _buildSummaryRow(
                                'Other Expenses',
                                currency.format(otherExpenses),
                                Icons.receipt_long_outlined,
                                theme.colorScheme.primary,
                              ),

                              const SizedBox(height: 16),
                              Divider(
                                  color: theme.colorScheme.outline
                                      .withValues(alpha: 0.2)),
                              const SizedBox(height: 16),

                              // Total
                              _buildSummaryRow(
                                'Total Expenses',
                                currency.format(netExpenses),
                                Icons.account_balance_wallet_outlined,
                                theme.colorScheme.error,
                                isBold: true,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Enhanced Filter Chips
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.08),
                              offset: const Offset(0, 2),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.filter_list_outlined,
                                    color: theme.colorScheme.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Filter by Category',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  _buildFilterChip('All Expenses', 'all',
                                      Icons.list_alt_outlined),
                                  _buildFilterChip('Salary Only', 'salary',
                                      Icons.payments_outlined),
                                  _buildFilterChip('Other Only', 'other',
                                      Icons.receipt_outlined),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Enhanced Expenses List
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.08),
                              offset: const Offset(0, 4),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // List Header
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.receipt_long_outlined,
                                      color: theme.colorScheme.tertiary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Expense Records (${filtered.length})',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // List Content
                            if (filtered.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.inbox_outlined,
                                      size: 48,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.3),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No expense records found',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Expenses will appear here once recorded',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Column(
                                children: filtered.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final expense = entry.value;
                                  final isLast = index == filtered.length - 1;

                                  return Column(
                                    children: [
                                      _buildExpenseItem(
                                          expense, currency, dateFmt, theme),
                                      if (!isLast)
                                        Divider(
                                          height: 1,
                                          thickness: 0.5,
                                          color: theme.colorScheme.outline
                                              .withValues(alpha: 0.2),
                                          indent: 56,
                                          endIndent: 20,
                                        ),
                                    ],
                                  );
                                }).toList(),
                              ),

                            const SizedBox(height: 8),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ));
  }

  Widget _buildSummaryRow(
      String title, String value, IconData icon, Color color,
      {bool isBold = false}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: color,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: isBold ? 16 : 15,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 16 : 15,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
            color: isBold
                ? color
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value, IconData icon) {
    final isSelected = _filter == value;
    final theme = Theme.of(context);

    return Material(
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpenseItem(Expense expense, NumberFormat currency,
      DateFormat dateFmt, ThemeData theme) {
    final isSalary = expense.category == 'Salary-Monthly' ||
        expense.category == 'Salary-Daily';
    final color = isSalary ? theme.colorScheme.secondary : theme.colorScheme.tertiary;
    final icon = isSalary ? Icons.payments_outlined : Icons.receipt_outlined;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.description.isNotEmpty
                      ? expense.description
                      : expense.category,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      expense.category,
                      style: TextStyle(
                        fontSize: 13,
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      ' • ${dateFmt.format(expense.date)}',
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                currency.format(expense.amount),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!expense.id.startsWith('payroll-payment:'))
                    IconButton(
                      onPressed: () => _editExpense(expense),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: 'Correct expense',
                    ),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: IconButton(
                      onPressed: () => _deleteExpense(expense),
                      icon: Icon(Icons.delete_outline, color: theme.colorScheme.error, size: 18),
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: 'Delete expense',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  DateTime _previous(DateTime d) {
    if (_tab.index == 0) {
      return d.subtract(const Duration(days: 1));
    } else if (_tab.index == 1) {
      final y = d.year;
      final m = d.month == 1 ? 12 : d.month - 1;
      final ny = d.month == 1 ? y - 1 : y;
      return DateTime(ny, m, 1);
    } else {
      return DateTime(d.year - 1, 1, 1);
    }
  }

  DateTime _next(DateTime d) {
    if (_tab.index == 0) {
      return d.add(const Duration(days: 1));
    } else if (_tab.index == 1) {
      final y = d.year;
      final m = d.month == 12 ? 1 : d.month + 1;
      final ny = d.month == 12 ? y + 1 : y;
      return DateTime(ny, m, 1);
    } else {
      return DateTime(d.year + 1, 1, 1);
    }
  }

  Future<void> _pickPeriod() async {
    if (_tab.index == 0) {
      final picked = await showDatePicker(
        context: context,
        initialDate: _anchor,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked != null) setState(() => _anchor = picked);
    } else if (_tab.index == 1) {
      final picked = await _showMonthYearPicker(
        context: context,
        initialYear: _anchor.year,
        initialMonth: _anchor.month,
      );
      if (picked != null) setState(() => _anchor = picked);
    } else {
      final selected = await showDialog<int>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Select Year'),
            content: SizedBox(
              width: 300,
              height: 300,
              child: YearPicker(
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDate: DateTime(_anchor.year),
                selectedDate: DateTime(_anchor.year),
                onChanged: (date) => Navigator.of(ctx).pop(date.year),
              ),
            ),
          );
        },
      );
      if (selected != null) setState(() => _anchor = DateTime(selected, 1, 1));
    }
  }

  Future<void> _editExpense(Expense expense) async {
    if (expense.id.startsWith('payroll-payment:')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payroll payments must be corrected through payroll.')),
      );
      return;
    }
    final category = TextEditingController(text: expense.category);
    final amount = TextEditingController(text: expense.amount.toStringAsFixed(2));
    final description = TextEditingController(text: expense.description);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Correct expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: category,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 8),
                Text(
                  'The original date and payment account are retained. The previous journal entry will be reversed and a new revision posted.',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Post correction')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final nextCategory = category.text.trim();
      final nextAmount = double.tryParse(amount.text.trim());
      if (nextCategory.isEmpty || nextAmount == null || !nextAmount.isFinite || nextAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a category and a positive valid amount.')),
        );
        return;
      }

      final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
      final postings = Hive.box<FinancePosting>(Boxes.financePostings);
      final sourceId = '${expense.id}:${expense.financeRevision}';
      final sourceJournals = transactions.values.where((tx) =>
          tx.sourceType == 'legacy_expense' && tx.sourceId == sourceId).toList();
      var paymentAccountId = 'system:cash';
      if (sourceJournals.length > 1) {
        throw StateError('Duplicate source journals exist. Reconcile this expense before correcting it.');
      }
      if (sourceJournals.length == 1) {
        final credits = postings.values.where((line) =>
            line.transactionId == sourceJournals.single.id && line.creditPaise > 0).toList();
        if (credits.length != 1) {
          throw StateError('The original expense payment account cannot be identified. Reconcile it before correcting this expense.');
        }
        paymentAccountId = credits.single.accountId;
      }

      final oldRevision = expense.financeRevision;
      expense
        ..category = nextCategory
        ..amount = nextAmount
        ..description = description.text.trim()
        ..financeRevision = oldRevision + 1;
      await Hive.box<Expense>(Boxes.expenses).put(expense.id, expense);
      try {
        await FinanceSourceSyncService().syncExpense(
          expense: expense,
          accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts),
          transactionsBox: transactions,
          postingsBox: postings,
          categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
          partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
          employeesBox: Hive.box<Employee>(Boxes.employees),
          paymentAccountId: paymentAccountId,
        );
      } catch (error) {
        await FinanceSourceSyncService.recordIssue(
          Hive.box<dynamic>('app_settings'),
          'Expense correction ${expense.id} revision ${expense.financeRevision}: $error',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Correction saved, but journal sync failed. Retry Finance reconciliation before editing it again: $error')),
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense corrected. The previous journal was reversed and the new revision posted.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not correct expense: $error')),
        );
      }
    } finally {
      category.dispose();
      amount.dispose();
      description.dispose();
    }
  }

  Future<void> _deleteExpense(Expense expense) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_outlined,
              color: Theme.of(context).colorScheme.tertiary,
              size: 24,
            ),
            const SizedBox(width: 12),
            const Text('Delete Expense'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete this expense?',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.description.isNotEmpty
                        ? expense.description
                        : expense.category,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${expense.category} • ${NumberFormat.simpleCurrency(locale: 'en_IN').format(expense.amount)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This action cannot be undone.',
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FinanceSourceSyncService().reverseExpense(
          expense: expense,
          accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts),
          transactionsBox: Hive.box<FinanceTransaction>(Boxes.financeTransactions),
          postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
          categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
          partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
        );
        await expense.delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Theme.of(context).colorScheme.onPrimary,
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Text('Expense deleted successfully'),
                ],
              ),
              backgroundColor: theme.colorScheme.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.onPrimary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text('Failed to delete expense: $e'),
                ],
              ),
              backgroundColor: theme.colorScheme.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<DateTime?> _showMonthYearPicker({
    required BuildContext context,
    required int initialYear,
    required int initialMonth,
  }) async {
    return showDialog<DateTime>(
      context: context,
      builder: (ctx) {
        int selectedYear = initialYear;
        int selectedMonth = initialMonth;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('Select Month and Year'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 200,
                      child: YearPicker(
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: DateTime(selectedYear),
                        selectedDate: DateTime(selectedYear),
                        onChanged: (date) {
                          setStateDialog(() {
                            selectedYear = date.year;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(12, (i) {
                        final m = i + 1;
                        final isSelected = m == selectedMonth;
                        return ChoiceChip(
                          label: Text(
                              DateFormat('MMM').format(DateTime(2000, m, 1))),
                          selected: isSelected,
                          onSelected: (_) {
                            setStateDialog(() {
                              selectedMonth = m;
                            });
                          },
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx)
                        .pop(DateTime(selectedYear, selectedMonth, 1));
                  },
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Select'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
