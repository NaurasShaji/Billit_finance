import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../services/boxes.dart';
import '../../../services/finance_source_sync_service.dart';
import '../../../models/models.dart';
import '../../../utils/theme_colors.dart';
import '../../../widgets/responsive_page.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String? _selectedCategory;
  late List<String> _allCategories;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final defaults = <String>[
      'Salary-Monthly',
      'Salary-Daily',
      'Rent',
      'Utilities',
      'Transport',
      'Supplies',
      'Maintenance',
      'Miscellaneous',
    ];
    final existing = {
      for (final e in Hive.box<Expense>(Boxes.expenses).values) e.category
    };
    _allCategories = {...defaults, ...existing}.toList()..sort();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.simpleCurrency(locale: 'en_IN');

    return ResponsivePage(child: Scaffold(
      backgroundColor:
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      appBar: AppBar(
        title: const Text('Add Expense'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Main Form Card
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.08),
                      offset: const Offset(0, 4),
                      blurRadius: 16,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Section
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.add_business_outlined,
                                color: theme.colorScheme.error,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Record New Expense',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Track your business expenditures',
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

                        const SizedBox(height: 32),

                        // Category Selection with Add Button
                        Text(
                          'Category',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: theme.colorScheme.outline
                                        .withValues(alpha: 0.2),
                                  ),
                                ),
                                child: DropdownButtonFormField<String>(
                                  value: _selectedCategory,
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.category_outlined),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    hintText: 'Select category',
                                  ),
                                  items: _allCategories
                                      .map((c) => DropdownMenuItem(
                                          value: c, child: Text(c)))
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => _selectedCategory = v),
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'Please select a category'
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.4)),
                              ),
                              child: IconButton(
                                tooltip: 'Add new category',
                                icon: Icon(Icons.add,
                                    color: theme.colorScheme.primary),
                                onPressed: _addNewCategory,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Amount Field
                        Text(
                          'Amount',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.2),
                            ),
                          ),
                          child: TextFormField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              prefixIcon:
                                  const Icon(Icons.currency_rupee_outlined),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                              hintText:
                                  'Enter amount (${currency.currencySymbol})',
                              hintStyle: TextStyle(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.5)),
                            ),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w500),
                            validator: (value) {
                              final v = double.tryParse((value ?? '').trim());
                              return (v == null || v <= 0)
                                  ? 'Please enter a valid amount'
                                  : null;
                            },
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Description Field
                        Text(
                          'Description',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.2),
                            ),
                          ),
                          child: TextFormField(
                            controller: _descriptionController,
                            maxLines: 3,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.notes_outlined),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                              hintText: 'Add description (optional)',
                              hintStyle: TextStyle(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.5)),
                            ),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Save Button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _saveExpense,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.surface,
                              foregroundColor: theme.colorScheme.onSurface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          theme.colorScheme.onError),
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.save_outlined, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'Save Expense',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Recent Expenses Section
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.08),
                      offset: const Offset(0, 4),
                      blurRadius: 16,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Recent Expenses Header
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.history,
                              color: theme.colorScheme.secondary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Recent Expenses',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Recent Expenses List
                    ValueListenableBuilder(
                      valueListenable:
                          Hive.box<Expense>(Boxes.expenses).listenable(),
                      builder: (context, Box<Expense> box, _) {
                        final recentExpenses = box.values.toList()
                          ..sort((a, b) => b.date.compareTo(a.date));
                        final displayExpenses = recentExpenses.take(5).toList();

                        if (displayExpenses.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.receipt_long_outlined,
                                  size: 48,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.3),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No expenses recorded yet',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Your recent expenses will appear here',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return Column(
                          children:
                              displayExpenses.asMap().entries.map((entry) {
                            final index = entry.key;
                            final expense = entry.value;
                            final isLast = index == displayExpenses.length - 1;

                            return Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 16),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.receipt_outlined,
                                          color: Colors.orange.shade600,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              expense.category,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              expense.description.isNotEmpty
                                                  ? '${expense.description} • ${DateFormat('dd MMM yyyy').format(expense.date)}'
                                                  : DateFormat('dd MMM yyyy')
                                                      .format(expense.date),
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: theme
                                                    .colorScheme.onSurface
                                                    .withValues(alpha: 0.6),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '${currency.currencySymbol}${expense.amount.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: theme.colorScheme.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
                        );
                      },
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    ));
  }

  Future<void> _saveExpense() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      await Future.delayed(
          const Duration(milliseconds: 500)); // Simulate loading

      final id = const Uuid().v4();
      final expense = Expense(
        id: id,
        date: DateTime.now(),
        category: _selectedCategory!,
        amount: double.tryParse(_amountController.text.trim()) ?? 0,
        description: _descriptionController.text.trim(),
      );

      final box = Hive.box<Expense>(Boxes.expenses);
      await box.put(expense.id, expense);

      try {
        await FinanceSourceSyncService().syncExpense(
          expense: expense,
          accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts),
          transactionsBox: Hive.box<FinanceTransaction>(Boxes.financeTransactions),
          postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
          categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
          partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
          employeesBox: Hive.box<Employee>(Boxes.employees),
        );
      } catch (financeError) {
        await FinanceSourceSyncService.recordIssue(
          Hive.box<dynamic>('app_settings'),
          'Expense ${expense.id}: $financeError',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Expense saved; finance journal sync will retry on next launch: $financeError'),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
      }

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Expense saved successfully!'),
            backgroundColor: theme.colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context, true);
      }
    }
  }

  Future<void> _addNewCategory() async {
    final newCat = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AddExpenseCategoryScreen()),
    );
    if (!mounted || newCat == null || newCat.isEmpty) return;
    if (!_allCategories.contains(newCat)) {
      setState(() {
        _allCategories.add(newCat);
        _allCategories.sort();
      });
    }
    setState(() => _selectedCategory = newCat);
  }
}

class AddExpenseCategoryScreen extends StatefulWidget {
  const AddExpenseCategoryScreen({super.key});

  @override
  State<AddExpenseCategoryScreen> createState() =>
      _AddExpenseCategoryScreenState();
}

class _AddExpenseCategoryScreenState extends State<AddExpenseCategoryScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a category name')),
      );
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsivePage(child: Scaffold(
      appBar: AppBar(
        title: const Text('Add Expense Category'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Create a category',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Use a clear name so expenses can be grouped correctly.',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'Category name',
                hintText: 'e.g. Internet, Repairs, Packaging',
                prefixIcon: Icon(Icons.category_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.add),
              label: const Text('Add Category'),
            ),
          ],
        ),
      ),
    ));
  }
}
