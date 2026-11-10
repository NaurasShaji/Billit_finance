import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';

class FinanceCategoryManagementScreen extends StatelessWidget {
  const FinanceCategoryManagementScreen({super.key});

  Future<void> _openForm(
    BuildContext context, [
    FinanceCategory? category,
  ]) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FinanceCategoryFormScreen(category: category),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountsBox = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    return Scaffold(
      appBar: AppBar(title: const Text('Finance categories')),
      body: ValueListenableBuilder<Box<FinanceCategory>>(
        valueListenable:
            Hive.box<FinanceCategory>(Boxes.financeCategories).listenable(),
        builder: (context, categoriesBox, _) {
          final categories = categoriesBox.values.toList()
            ..sort((a, b) {
              final kind = a.kind.compareTo(b.kind);
              return kind != 0 ? kind : a.name.compareTo(b.name);
            });
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _openForm(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add category'),
                ),
              ),
              const SizedBox(height: 12),
              if (categories.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No finance categories created yet.'),
                ),
              for (final category in categories)
                Card(
                  child: ListTile(
                    onTap: () => _openForm(context, category),
                    title: Text(category.name),
                    subtitle: Text(
                      '${category.kind.toUpperCase()} • '
                      '${accountsBox.get(category.accountId)?.name ?? category.accountId}'
                      '${category.active ? '' : ' • ARCHIVED'}',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class FinanceCategoryFormScreen extends StatefulWidget {
  const FinanceCategoryFormScreen({super.key, this.category});

  final FinanceCategory? category;

  @override
  State<FinanceCategoryFormScreen> createState() =>
      _FinanceCategoryFormScreenState();
}

class _FinanceCategoryFormScreenState
    extends State<FinanceCategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late String _kind;
  String? _accountId;
  bool _active = true;
  bool _saving = false;

  String _legacyCategoryId(Expense expense) {
    final name = expense.category.trim().isEmpty
        ? 'Uncategorised'
        : expense.category.trim();
    return 'legacy-expense-category:${Uri.encodeComponent(name.toLowerCase())}';
  }

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.category?.name ?? '');
    _kind = widget.category?.kind ?? 'expense';
    _accountId = widget.category?.accountId;
    _active = widget.category?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save(
    Box<FinanceAccount> accounts,
    Box<FinanceCategory> categories,
  ) async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final name = _name.text.trim();
    final accountId = _accountId;
    if (accountId == null) return;

    final account = accounts.get(accountId);
    if (account == null || !account.active || account.accountType != _kind) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose an active account matching the category type.'),
        ),
      );
      return;
    }

    final existing = widget.category;
    final duplicate = categories.values.any((item) =>
        item.id != existing?.id &&
        item.kind == _kind &&
        item.name.trim().toLowerCase() == name.toLowerCase());
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A category with this name and type already exists.'),
        ),
      );
      return;
    }
    final hasPostings = existing != null &&
        Hive.box<FinancePosting>(Boxes.financePostings)
            .values
            .any((line) => line.categoryId == existing.id);
    final hasSourceExpenses = existing != null &&
        Hive.box<Expense>(Boxes.expenses).values.any((expense) {
          return _legacyCategoryId(expense) == existing.id;
        });
    if (existing != null &&
        (hasPostings || hasSourceExpenses) &&
        (existing.kind != _kind || existing.accountId != accountId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Category type and account cannot change while source records or journal postings use it.',
          ),
        ),
      );
      return;
    }
    if (existing != null &&
        !_active &&
        (hasPostings || hasSourceExpenses)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This category is still used by source records or posted journal entries.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final id = existing?.id ?? 'finance-category:${const Uuid().v4()}';
      await categories.put(
        id,
        FinanceCategory(
          id: id,
          name: name,
          kind: _kind,
          accountId: accountId,
          active: _active,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save category: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    final categories = Hive.box<FinanceCategory>(Boxes.financeCategories);
    final postings = Hive.box<FinancePosting>(Boxes.financePostings);
    final sourceExpenses = Hive.box<Expense>(Boxes.expenses);
    final existing = widget.category;
    final hasPostings = existing != null &&
        postings.values.any((line) => line.categoryId == existing.id);
    final hasSourceExpenses = existing != null &&
        sourceExpenses.values.any((expense) =>
            'legacy-expense-category:${Uri.encodeComponent(expense.category.trim().toLowerCase())}' ==
            existing.id);
    final canChangeMapping =
        existing == null || (!hasPostings && !hasSourceExpenses);

    return Scaffold(
      appBar: AppBar(
        title: Text(existing == null ? 'New category' : 'Edit category'),
      ),
      body: ValueListenableBuilder<Box<FinanceAccount>>(
        valueListenable: accounts.listenable(),
        builder: (context, accountBox, _) {
          final available = accountBox.values
              .where((account) =>
                  account.active && account.accountType == _kind)
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          if (!available.any((account) => account.id == _accountId)) {
            _accountId =
                available.isEmpty ? null : available.first.id;
          }
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Category name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Enter a category name'
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _kind,
                  decoration: const InputDecoration(
                    labelText: 'Category type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'income', child: Text('Income')),
                    DropdownMenuItem(value: 'expense', child: Text('Expense')),
                  ],
                  onChanged: !canChangeMapping
                      ? null
                      : (value) => setState(() {
                            _kind = value ?? _kind;
                            _accountId = null;
                          }),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _accountId,
                  decoration: const InputDecoration(
                    labelText: 'Linked ledger account',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final account in available)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: canChangeMapping
                      ? (value) => setState(() => _accountId = value)
                      : null,
                  validator: (value) =>
                      value == null ? 'Select a ledger account' : null,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active category'),
                  value: _active,
                  onChanged: hasPostings || hasSourceExpenses
                      ? null
                      : (value) => setState(() => _active = value),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () => _save(accounts, categories),
                  child: Text(_saving ? 'Saving...' : 'Save category'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
