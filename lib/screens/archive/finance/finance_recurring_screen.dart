import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/finance_recurring_service.dart';

class FinanceRecurringScreen extends StatefulWidget {
  const FinanceRecurringScreen({super.key});

  @override
  State<FinanceRecurringScreen> createState() => _FinanceRecurringScreenState();
}

class _FinanceRecurringScreenState extends State<FinanceRecurringScreen> {
  bool _processing = false;

  String _money(int paise) =>
      NumberFormat.simpleCurrency(locale: 'en_IN').format(paise / 100);

  Future<void> _add() async {
    final accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts)
        .values
        .where((item) => item.active && item.currencyCode == 'INR')
        .toList();
    if (accounts.isEmpty) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RecurringTemplateDialog(accounts: accounts),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recurring template saved.')),
      );
    }
  }

  Future<void> _processDue() async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      final result = await FinanceRecurringService().processDue();
      final settings = Hive.box<dynamic>('app_settings');
      if (result.issues.isEmpty) {
        await settings.delete('finance_recurring_errors');
      } else {
        await settings.put('finance_recurring_errors', result.issues);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.postedCount} posted, ${result.skippedCount} already posted, ${result.issues.length} issue(s).',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _archive(FinanceRecurringTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive recurring template?'),
        content: const Text(
          'Future entries will stop. Existing journal entries remain unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FinanceRecurringService().archiveTemplate(template.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring transactions'),
        actions: [
          IconButton(
            onPressed: _processing ? null : _processDue,
            tooltip: 'Process due transactions',
            icon: _processing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
          IconButton(
            onPressed: _add,
            tooltip: 'Add template',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<FinanceRecurringTemplate>>(
        valueListenable: Hive.box<FinanceRecurringTemplate>(
          Boxes.financeRecurringTemplates,
        ).listenable(),
        builder: (context, templatesBox, _) =>
            ValueListenableBuilder<Box<FinanceAccount>>(
          valueListenable:
              Hive.box<FinanceAccount>(Boxes.financeAccounts).listenable(),
          builder: (context, accountsBox, __) {
            final templates = templatesBox.values.toList()
              ..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));
            final accounts = {
              for (final account in accountsBox.values) account.id: account,
            };
            if (templates.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event_repeat_outlined, size: 48),
                    const SizedBox(height: 12),
                    const Text('No recurring templates'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _add,
                      icon: const Icon(Icons.add),
                      label: const Text('Create template'),
                    ),
                  ],
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Due templates are processed at app startup or manually.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                for (final template in templates)
                  Card(
                    child: ListTile(
                      title: Text(template.name),
                      subtitle: Text(
                        '${template.transactionType.toUpperCase()} • ${template.interval} • Next: ${DateFormat('dd MMM yyyy').format(template.nextDueDate)}\n'
                        '${accounts[template.debitAccountId]?.name ?? template.debitAccountId} → ${accounts[template.creditAccountId]?.name ?? template.creditAccountId}'
                        '${template.active ? '' : ' • Archived'}',
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_money(template.amountPaise)),
                          if (template.active)
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'archive') _archive(template);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'archive',
                                  child: Text('Archive'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _processing ? null : _processDue,
                  icon: const Icon(Icons.sync),
                  label: const Text('Process due transactions now'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RecurringTemplateDialog extends StatefulWidget {
  const _RecurringTemplateDialog({required this.accounts});
  final List<FinanceAccount> accounts;

  @override
  State<_RecurringTemplateDialog> createState() =>
      _RecurringTemplateDialogState();
}

class _RecurringTemplateDialogState extends State<_RecurringTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _memo = TextEditingController();
  String _type = 'expense';
  String _interval = 'monthly';
  String? _debitId;
  String? _creditId;
  DateTime _dueDate = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _memo.dispose();
    super.dispose();
  }

  String get _debitType => _type == 'income' ? 'asset' : 'expense';
  String get _creditType => _type == 'income' ? 'income' : 'asset';

  List<FinanceAccount> _options(String type) => widget.accounts
      .where((item) =>
          item.accountType == type && item.id != 'system:receivables')
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  int? _paise(String raw) {
    final value = raw.trim();
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null) return null;
    return whole * 100 +
        (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final debit = _debitId;
    final credit = _creditId;
    final amount = _paise(_amount.text);
    if (debit == null || credit == null || amount == null || amount <= 0) {
      return;
    }
    setState(() => _saving = true);
    try {
      await FinanceRecurringService().createTemplate(
        name: _name.text,
        transactionType: _type,
        debitAccountId: debit,
        creditAccountId: credit,
        amountPaise: amount,
        interval: _interval,
        nextDueDate: _dueDate,
        memo: _memo.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save template: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final debitAccounts = _options(_debitType);
    final creditAccounts = _options(_creditType);
    if (!debitAccounts.any((item) => item.id == _debitId)) {
      _debitId = debitAccounts.isEmpty ? null : debitAccounts.first.id;
    }
    if (!creditAccounts.any((item) => item.id == _creditId)) {
      _creditId = creditAccounts.isEmpty ? null : creditAccounts.first.id;
    }
    return AlertDialog(
      title: const Text('Create recurring template'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Template name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Enter a template name'
                      : null,
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'income', label: Text('Income')),
                    ButtonSegment(value: 'expense', label: Text('Expense')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (value) => setState(() {
                    _type = value.first;
                    _debitId = null;
                    _creditId = null;
                  }),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final amount = _paise(value ?? '');
                    return amount == null || amount <= 0
                        ? 'Enter a positive amount with up to 2 decimals'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _debitId,
                  decoration: const InputDecoration(
                    labelText: 'Debit account',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final account in debitAccounts)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _debitId = value),
                  validator: (value) =>
                      value == null ? 'Select a debit account' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _creditId,
                  decoration: const InputDecoration(
                    labelText: 'Credit account',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final account in creditAccounts)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _creditId = value),
                  validator: (value) =>
                      value == null ? 'Select a credit account' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _interval,
                  decoration: const InputDecoration(
                    labelText: 'Repeat',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(value: 'quarterly', child: Text('Quarterly')),
                    DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                  ],
                  onChanged: (value) =>
                      setState(() => _interval = value ?? 'monthly'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('First due date'),
                  subtitle: Text(DateFormat('dd MMM yyyy').format(_dueDate)),
                  trailing: IconButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _dueDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ),
                      );
                      if (picked != null) setState(() => _dueDate = picked);
                    },
                    icon: const Icon(Icons.calendar_month),
                  ),
                ),
                TextFormField(
                  controller: _memo,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Memo (optional)',
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
          child: Text(_saving ? 'Saving...' : 'Save template'),
        ),
      ],
    );
  }
}
