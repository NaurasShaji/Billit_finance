import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/finance_budget_service.dart';
import '../../../widgets/responsive_page.dart';

class FinanceBudgetsScreen extends StatelessWidget {
  const FinanceBudgetsScreen({super.key});

  String _money(int paise) =>
      NumberFormat.simpleCurrency(locale: 'en_IN').format(paise / 100);

  Future<void> _addBudget(BuildContext context) async {
    final accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts)
        .values
        .where((item) => item.active && item.accountType == 'expense')
        .toList();
    final categories =
        Hive.box<FinanceCategory>(Boxes.financeCategories).values.toList();
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create an expense account before adding a budget.')),
      );
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => FinanceBudgetFormDialog(
        accounts: accounts,
        categories: categories,
      ),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Budget saved.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsivePage(child: Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(
            tooltip: 'Add budget',
            onPressed: () => _addBudget(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<FinanceBudget>>(
        valueListenable:
            Hive.box<FinanceBudget>(Boxes.financeBudgets).listenable(),
        builder: (context, budgetsBox, _) =>
            ValueListenableBuilder<Box<FinanceTransaction>>(
          valueListenable: Hive.box<FinanceTransaction>(
            Boxes.financeTransactions,
          ).listenable(),
          builder: (context, transactionsBox, __) =>
              ValueListenableBuilder<Box<FinancePosting>>(
            valueListenable:
                Hive.box<FinancePosting>(Boxes.financePostings).listenable(),
            builder: (context, postingsBox, ___) =>
                ValueListenableBuilder<Box<FinanceAccount>>(
              valueListenable:
                  Hive.box<FinanceAccount>(Boxes.financeAccounts).listenable(),
              builder: (context, accountsBox, ____) {
                final progress = const FinanceBudgetService().summarize(
                  budgets: budgetsBox.values,
                  transactions: transactionsBox.values,
                  postings: postingsBox.values,
                );
                final accounts = {
                  for (final account in accountsBox.values) account.id: account,
                };
                if (progress.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.pie_chart_outline, size: 48),
                          const SizedBox(height: 12),
                          const Text('No active budgets'),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => _addBudget(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Create budget'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Budget tracking',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Actual spend is calculated from posted expense journal lines.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    for (final item in progress)
                      Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.budget.name,
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (value) async {
                                      if (value == 'archive') {
                                        await FinanceBudgetService()
                                            .archiveBudget(item.budget.id);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'archive',
                                        child: Text('Archive budget'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Text(
                                '${accounts[item.budget.accountId]?.name ?? item.budget.accountId}'
                                '${item.budget.categoryId == null ? '' : ' • Category budget'}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${DateFormat('dd MMM yyyy').format(item.budget.periodStart)} – '
                                '${DateFormat('dd MMM yyyy').format(item.budget.periodEnd)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Spent: ${_money(item.actualPaise)}'),
                                  Text('Budget: ${_money(item.budget.budgetPaise)}'),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: item.usedRatio.clamp(0.0, 1.0).toDouble(),
                                minHeight: 8,
                                color: item.overBudget
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item.overBudget
                                    ? 'Over budget by ${_money(-item.remainingPaise)}'
                                    : '${_money(item.remainingPaise)} remaining',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: item.overBudget
                                          ? Theme.of(context).colorScheme.error
                                          : Theme.of(context).colorScheme.onSurface,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _addBudget(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Add another budget'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ));
  }
}

class FinanceBudgetFormDialog extends StatefulWidget {
  const FinanceBudgetFormDialog({
    super.key,
    required this.accounts,
    required this.categories,
  });

  final List<FinanceAccount> accounts;
  final List<FinanceCategory> categories;

  @override
  State<FinanceBudgetFormDialog> createState() =>
      _FinanceBudgetFormDialogState();
}

class _FinanceBudgetFormDialogState extends State<FinanceBudgetFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  late String _accountId;
  String? _categoryId;
  DateTimeRange _period = DateTimeRange(
    start: DateTime(DateTime.now().year, DateTime.now().month),
    end: DateTime(DateTime.now().year, DateTime.now().month + 1, 0),
  );
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _accountId = widget.accounts.first.id;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  int? _parsePaise(String raw) {
    final value = raw.trim();
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null) return null;
    final fraction = parts.length == 1
        ? 0
        : int.parse(parts[1].padRight(2, '0'));
    return whole * 100 + fraction;
  }

  Future<void> _pickPeriod() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDateRange: _period,
    );
    if (selected != null) setState(() => _period = selected);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final amountPaise = _parsePaise(_amount.text);
    if (amountPaise == null || amountPaise <= 0) return;
    setState(() => _saving = true);
    try {
      await FinanceBudgetService().saveBudget(
        name: _name.text,
        accountId: _accountId,
        categoryId: _categoryId,
        periodStart: _period.start,
        periodEnd: _period.end,
        budgetPaise: amountPaise,
        notes: _notes.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save budget: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableCategories = widget.categories
        .where((item) =>
            item.active &&
            item.kind == 'expense' &&
            item.accountId == _accountId)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (!availableCategories.any((item) => item.id == _categoryId)) {
      _categoryId = null;
    }

    return AlertDialog(
      title: const Text('Create budget'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Budget name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Enter a budget name'
                      : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _accountId,
                  decoration: const InputDecoration(
                    labelText: 'Expense account',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final account in widget.accounts)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _accountId = value ?? _accountId;
                    _categoryId = null;
                  }),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  value: _categoryId,
                  decoration: const InputDecoration(
                    labelText: 'Category (optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All categories in this account'),
                    ),
                    for (final category in availableCategories)
                      DropdownMenuItem<String?>(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Budget amount',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final amount = _parsePaise(value ?? '');
                    return amount == null || amount <= 0
                        ? 'Enter a positive amount with up to 2 decimals'
                        : null;
                  },
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Budget period'),
                  subtitle: Text(
                    '${DateFormat('dd MMM yyyy').format(_period.start)} – '
                    '${DateFormat('dd MMM yyyy').format(_period.end)}',
                  ),
                  trailing: IconButton(
                    onPressed: _pickPeriod,
                    icon: const Icon(Icons.calendar_month),
                  ),
                ),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save budget'),
        ),
      ],
    );
  }
}
