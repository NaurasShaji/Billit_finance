import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/finance_ledger_service.dart';

class FinanceTransactionFormScreen extends StatefulWidget {
  const FinanceTransactionFormScreen({super.key});

  @override
  State<FinanceTransactionFormScreen> createState() =>
      _FinanceTransactionFormScreenState();
}

class _FinanceTransactionFormScreenState
    extends State<FinanceTransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();
  String _type = 'expense';
  String? _debitAccountId;
  String? _creditAccountId;
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  int? _parsePaise(String raw) {
    final value = raw.trim();
    final match = RegExp(r'^\d+(?:\.\d{1,2})?$').firstMatch(value);
    if (match == null) return null;
    final parts = value.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null) return null;
    final fraction = parts.length == 1
        ? 0
        : int.parse(parts[1].padRight(2, '0'));
    return whole * 100 + fraction;
  }

  List<FinanceAccount> _accounts(Box<FinanceAccount> box, String type) =>
      box.values
          .where((account) => account.active && account.accountType == type)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  String _debitType => _type == 'income' || _type == 'transfer'
      ? 'asset'
      : 'expense';

  String _creditType => _type == 'income' ? 'income' : 'asset';

  String get _debitLabel => switch (_type) {
        'income' => 'Deposit to',
        'transfer' => 'Transfer to',
        _ => 'Expense account',
      };

  String get _creditLabel => switch (_type) {
        'income' => 'Income account',
        'transfer' => 'Transfer from',
        _ => 'Paid from',
      };

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final debitAccountId = _debitAccountId;
    final creditAccountId = _creditAccountId;
    final amountPaise = _parsePaise(_amountController.text);
    if (debitAccountId == null ||
        creditAccountId == null ||
        amountPaise == null ||
        amountPaise <= 0) {
      return;
    }
    if (_type == 'transfer' && debitAccountId == creditAccountId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose two different accounts.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final id = const Uuid().v4();
      final number =
          'MAN-${DateFormat('yyyyMMdd').format(now)}-${id.substring(0, 8).toUpperCase()}';
      final transaction = FinanceTransaction(
        id: id,
        transactionNumber: number,
        transactionType: _type,
        date: now,
        memo: _memoController.text.trim(),
        sourceType: 'manual',
        sourceId: id,
      );
      await FinanceLedgerService().postTransaction(
        transaction: transaction,
        postings: [
          FinancePosting(
            id: '$id:debit',
            transactionId: id,
            accountId: debitAccountId,
            debitPaise: amountPaise,
            memo: _memoController.text.trim(),
          ),
          FinancePosting(
            id: '$id:credit',
            transactionId: id,
            accountId: creditAccountId,
            creditPaise: amountPaise,
            memo: _memoController.text.trim(),
          ),
        ],
        accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts),
        transactionsBox:
            Hive.box<FinanceTransaction>(Boxes.financeTransactions),
        postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
        categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
        partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save transaction: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('New finance transaction')),
      body: ValueListenableBuilder<Box<FinanceAccount>>(
        valueListenable:
            Hive.box<FinanceAccount>(Boxes.financeAccounts).listenable(),
        builder: (context, accounts, _) {
          final debitAccounts = _accounts(accounts, _debitType);
          final creditAccounts = _accounts(accounts, _creditType);
          if (!debitAccounts.any((item) => item.id == _debitAccountId)) {
            _debitAccountId =
                debitAccounts.isEmpty ? null : debitAccounts.first.id;
          }
          if (!creditAccounts.any((item) => item.id == _creditAccountId)) {
            _creditAccountId =
                creditAccounts.isEmpty ? null : creditAccounts.first.id;
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'income', label: Text('Income')),
                    ButtonSegment(value: 'expense', label: Text('Expense')),
                    ButtonSegment(value: 'transfer', label: Text('Transfer')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (value) => setState(() {
                    _type = value.first;
                    _debitAccountId = null;
                    _creditAccountId = null;
                  }),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final amount = _parsePaise(value ?? '');
                    return amount == null || amount <= 0
                        ? 'Enter a positive amount with up to 2 decimal places'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _debitAccountId,
                  decoration: InputDecoration(
                    labelText: _debitLabel,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final account in debitAccounts)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _debitAccountId = value),
                  validator: (value) =>
                      value == null ? 'Select an account' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _creditAccountId,
                  decoration: InputDecoration(
                    labelText: _creditLabel,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final account in creditAccounts)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _creditAccountId = value),
                  validator: (value) =>
                      value == null ? 'Select an account' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _memoController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description / reference',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Enter a description'
                      : null,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ||
                          debitAccounts.isEmpty ||
                          creditAccounts.isEmpty
                      ? null
                      : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_saving ? 'Saving...' : 'Post transaction'),
                ),
                const SizedBox(height: 10),
                Text(
                  'Posted transactions are immutable. Correct mistakes by creating a reversal.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
