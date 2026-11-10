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
  String? _categoryId;
  String? _partyId;
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
          .where((account) {
            if (!account.active) return false;
            return switch (type) {
              'all' => true,
              'asset_or_liability' =>
                account.accountType == 'asset' ||
                    account.accountType == 'liability',
              'receivables' => account.id == 'system:receivables',
              'payables' => account.id == 'system:payables',
              'cash_accounts' =>
                account.id == 'system:cash' || account.id == 'system:bank',
              _ => account.accountType == type,
            };
          })
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  String _debitType => switch (_type) {
        'income' => 'asset',
        'transfer' || 'customer_receipt' => 'cash_accounts',
        'supplier_payment' => 'payables',
        'adjustment' => 'all',
        _ => 'expense',
      };

  String _creditType => switch (_type) {
        'income' => 'income',
        'expense' => 'asset_or_liability',
        'customer_receipt' => 'receivables',
        'supplier_payment' || 'transfer' => 'cash_accounts',
        'adjustment' => 'all',
        _ => 'asset',
      };

  String? get _partyTypeFilter => switch (_type) {
        'income' || 'customer_receipt' => 'customer',
        'expense' || 'supplier_payment' => 'supplier',
        'adjustment' =>
          _debitAccountId == 'system:receivables' ||
                  _creditAccountId == 'system:receivables'
              ? 'customer'
              : _debitAccountId == 'system:payables' ||
                      _creditAccountId == 'system:payables'
                  ? 'supplier'
                  : null,
        _ => null,
      };

  bool get _partyRequired =>
      _type == 'customer_receipt' ||
      _type == 'supplier_payment' ||
      (_type == 'income' && _debitAccountId == 'system:receivables') ||
      (_type == 'expense' && _creditAccountId == 'system:payables') ||
      (_type == 'adjustment' &&
          (_debitAccountId == 'system:receivables' ||
              _creditAccountId == 'system:receivables' ||
              _debitAccountId == 'system:payables' ||
              _creditAccountId == 'system:payables'));

  String get _debitLabel => switch (_type) {
        'income' => 'Deposit to / receivable',
        'transfer' => 'Transfer to',
        'customer_receipt' => 'Received into',
        'supplier_payment' => 'Accounts payable',
        'adjustment' => 'Debit account',
        _ => 'Expense account',
      };

  String get _creditLabel => switch (_type) {
        'income' => 'Income account',
        'transfer' => 'Transfer from',
        'customer_receipt' => 'Accounts receivable',
        'supplier_payment' => 'Paid from',
        'adjustment' => 'Credit account',
        _ => 'Paid from / payable',
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
    final touchesReceivables = debitAccountId == 'system:receivables' ||
        creditAccountId == 'system:receivables';
    final touchesPayables = debitAccountId == 'system:payables' ||
        creditAccountId == 'system:payables';
    if (touchesReceivables && touchesPayables) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adjust receivables and payables in separate entries.'),
        ),
      );
      return;
    }
    if ((_type == 'transfer' ||
            _type == 'adjustment' ||
            _type == 'customer_receipt' ||
            _type == 'supplier_payment') &&
        debitAccountId == creditAccountId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose two different accounts.')),
      );
      return;
    }
    if (_partyRequired && (_partyId == null || _partyId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select the customer or supplier for this entry.')),
      );
      return;
    }
    if (_partyId != null) {
      final party = Hive.box<FinanceParty>(Boxes.financeParties).get(_partyId);
      final expectedType = _partyTypeFilter;
      if (party == null ||
          !party.active ||
          (expectedType != null && party.partyType != expectedType)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select an active party of the correct type.')),
        );
        return;
      }
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
            categoryId: _type == 'expense' ? _categoryId : null,
            partyId: _partyId,
            memo: _memoController.text.trim(),
          ),
          FinancePosting(
            id: '$id:credit',
            transactionId: id,
            accountId: creditAccountId,
            creditPaise: amountPaise,
            categoryId: _type == 'income' ? _categoryId : null,
            partyId: _partyId,
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
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(
                    labelText: 'Transaction type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'income', child: Text('Income')),
                    DropdownMenuItem(value: 'expense', child: Text('Expense')),
                    DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                    DropdownMenuItem(
                      value: 'customer_receipt',
                      child: Text('Customer receipt'),
                    ),
                    DropdownMenuItem(
                      value: 'supplier_payment',
                      child: Text('Supplier payment'),
                    ),
                    DropdownMenuItem(
                      value: 'adjustment',
                      child: Text('Journal adjustment'),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _type = value ?? _type;
                    _debitAccountId = null;
                    _creditAccountId = null;
                    _categoryId = null;
                    _partyId = null;
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
                if (_type == 'income' || _type == 'expense') ...[
                  const SizedBox(height: 16),
                  ValueListenableBuilder<Box<FinanceCategory>>(
                    valueListenable: Hive.box<FinanceCategory>(
                      Boxes.financeCategories,
                    ).listenable(),
                    builder: (context, categoryBox, _) {
                      final categoryKind =
                          _type == 'income' ? 'income' : 'expense';
                      final accountId = _type == 'income'
                          ? _creditAccountId
                          : _debitAccountId;
                      final availableCategories = categoryBox.values
                          .where((category) =>
                              category.active &&
                              category.kind == categoryKind &&
                              category.accountId == accountId)
                          .toList()
                        ..sort((a, b) => a.name.compareTo(b.name));
                      if (!availableCategories
                          .any((category) => category.id == _categoryId)) {
                        _categoryId = null;
                      }
                      return DropdownButtonFormField<String?>(
                        value: _categoryId,
                        decoration: const InputDecoration(
                          labelText: 'Category (optional)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('No category'),
                          ),
                          for (final category in availableCategories)
                            DropdownMenuItem<String?>(
                              value: category.id,
                              child: Text(category.name),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _categoryId = value),
                      );
                    },
                  ),
                ],
                if (_type != 'transfer') ...[
                  const SizedBox(height: 16),
                  ValueListenableBuilder<Box<FinanceParty>>(
                    valueListenable:
                        Hive.box<FinanceParty>(Boxes.financeParties).listenable(),
                    builder: (context, partiesBox, _) {
                      final availableParties = partiesBox.values
                          .where((party) =>
                              party.active &&
                              (_partyTypeFilter == null ||
                                  party.partyType == _partyTypeFilter))
                          .toList()
                        ..sort((a, b) => a.name.compareTo(b.name));
                      if (!availableParties
                          .any((party) => party.id == _partyId)) {
                        _partyId = null;
                      }
                      return DropdownButtonFormField<String?>(
                        value: _partyId,
                        decoration: InputDecoration(
                          labelText: _partyRequired
                              ? 'Customer / supplier (required)'
                              : 'Party (optional)',
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          if (!_partyRequired)
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('No party'),
                            ),
                          for (final party in availableParties)
                            DropdownMenuItem<String?>(
                              value: party.id,
                              child: Text(party.name),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _partyId = value),
                        validator: (value) => _partyRequired && value == null
                            ? 'Select a party'
                            : null,
                      );
                    },
                  ),
                ],
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
                  switch (_type) {
                    'customer_receipt' =>
                      'Records a customer payment against accounts receivable. Partial receipts are supported.',
                    'supplier_payment' =>
                      'Records a supplier payment against accounts payable. Partial payments are supported.',
                    'adjustment' =>
                      'Use adjustments for corrections between any two accounts. Posted entries are immutable; correct mistakes with a reversal.',
                    _ =>
                      'Posted transactions are immutable. Correct mistakes by creating a reversal.',
                  },
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
