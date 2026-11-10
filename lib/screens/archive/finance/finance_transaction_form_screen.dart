import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/finance_ledger_service.dart';
import '../../../services/finance_payment_allocation_service.dart';
import '../../../widgets/responsive_page.dart';

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
  DateTime? _dueDate;
  bool _saving = false;
  final List<String?> _allocationInvoiceIds = [];
  final List<TextEditingController> _allocationAmountControllers = [];

  @override
  void dispose() {
    _amountController.dispose();
    _memoController.dispose();
    for (final controller in _allocationAmountControllers) { controller.dispose(); }
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

  bool get _hasDueDate =>
      (_type == 'income' && _debitAccountId == 'system:receivables') ||
      (_type == 'expense' && _creditAccountId == 'system:payables');

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 20),
    );
    if (selected != null && mounted) {
      setState(() => _dueDate = DateTime(
        selected.year, selected.month, selected.day,
      ));
    }
  }

  String get _creditLabel => switch (_type) {
        'income' => 'Income account',
        'transfer' => 'Transfer from',
        'customer_receipt' => 'Accounts receivable',
        'supplier_payment' => 'Paid from',
        'adjustment' => 'Credit account',
        _ => 'Paid from / payable',
      };

  bool get _supportsInvoiceAllocation => _type == 'customer_receipt' || _type == 'supplier_payment';

  void _clearAllocationRows() {
    for (final controller in _allocationAmountControllers) { controller.dispose(); }
    _allocationInvoiceIds.clear();
    _allocationAmountControllers.clear();
  }

  void _addAllocationRow() {
    setState(() { _allocationInvoiceIds.add(null); _allocationAmountControllers.add(TextEditingController()); });
  }

  void _removeAllocationRow(int index) {
    setState(() { _allocationInvoiceIds.removeAt(index); _allocationAmountControllers.removeAt(index).dispose(); });
  }

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
      final allocationDrafts = <FinanceAllocationDraft>[];
      if (_supportsInvoiceAllocation && _allocationInvoiceIds.isNotEmpty) {
        final party = Hive.box<FinanceParty>(Boxes.financeParties).get(_partyId);
        if (party == null) throw const FinanceAllocationException('Select a valid party before allocating.');
        final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions).values.toList();
        final postings = Hive.box<FinancePosting>(Boxes.financePostings).values.toList();
        final allocationService = FinancePaymentAllocationService();
        var allocationTotal = 0;
        for (var i = 0; i < _allocationInvoiceIds.length; i++) {
          final invoiceId = _allocationInvoiceIds[i];
          final amount = _parsePaise(_allocationAmountControllers[i].text);
          if (invoiceId == null || amount == null || amount <= 0) throw const FinanceAllocationException('Complete every invoice allocation row or remove it.');
          final outstanding = allocationService.invoiceOutstandingPaise(invoiceId:invoiceId, partyId:party.id, partyType:party.partyType, transactions:transactions, postings:postings);
          final duplicateTotal = allocationDrafts.where((d)=>d.invoiceTransactionId==invoiceId).fold<int>(0,(sum,d)=>sum+d.amountPaise);
          if (duplicateTotal + amount > outstanding) throw const FinanceAllocationException('Allocation exceeds the invoice outstanding balance.');
          allocationDrafts.add(FinanceAllocationDraft(id:const Uuid().v4(), invoiceTransactionId:invoiceId, amountPaise:amount));
          allocationTotal += amount;
        }
        if (allocationTotal > amountPaise) throw const FinanceAllocationException('Total invoice allocations cannot exceed the receipt/payment amount.');
      }
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
        dueDate: _hasDueDate ? _dueDate : null,
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
      if (allocationDrafts.isNotEmpty) {
        try {
          await FinancePaymentAllocationService().allocateBatch(
            settlementTransactionId:id, partyId:_partyId!, partyType:_type == 'customer_receipt' ? 'customer' : 'supplier',
            drafts:allocationDrafts,
            transactions:Hive.box<FinanceTransaction>(Boxes.financeTransactions).values,
            postings:Hive.box<FinancePosting>(Boxes.financePostings).values,
          );
        } catch (_) {
          await FinanceLedgerService().reverseTransaction(
            originalTransactionId:id, reversalId:const Uuid().v4(),
            reversalNumber:'REV-$number', reversalDate:DateTime.now(),
            accountsBox:Hive.box<FinanceAccount>(Boxes.financeAccounts),
            transactionsBox:Hive.box<FinanceTransaction>(Boxes.financeTransactions),
            postingsBox:Hive.box<FinancePosting>(Boxes.financePostings),
            categoriesBox:Hive.box<FinanceCategory>(Boxes.financeCategories),
            partiesBox:Hive.box<FinanceParty>(Boxes.financeParties),
            memo:'Automatic reversal: payment allocation could not be saved',
          );
          rethrow;
        }
      }
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
    return ResponsivePage(child: Scaffold(
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
                    _clearAllocationRows();
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
                if (_hasDueDate) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _pickDueDate,
                    icon: const Icon(Icons.event_available_outlined),
                    label: Text(_dueDate == null
                        ? 'Set due date (optional)'
                        : 'Due ${DateFormat('dd MMM yyyy').format(_dueDate!)}'),
                  ),
                  if (_dueDate != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _dueDate = null),
                        child: const Text('Clear due date'),
                      ),
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
                        onChanged: (value) => setState(() {
                          _partyId = value;
                          _clearAllocationRows();
                        }),
                        validator: (value) => _partyRequired && value == null
                            ? 'Select a party'
                            : null,
                      );
                    },
                  ),
                ],
                const SizedBox(height: 16),
                if (_supportsInvoiceAllocation && _partyId != null) ...[
                  const SizedBox(height: 20),
                  Text('Allocate to invoices (optional)', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  const Text('Split this receipt/payment across one or more open invoices. Any unallocated amount remains as a party advance.'),
                  ValueListenableBuilder<Box<FinanceTransaction>>(
                    valueListenable:Hive.box<FinanceTransaction>(Boxes.financeTransactions).listenable(),
                    builder:(context, txBox, _) => ValueListenableBuilder<Box<FinancePosting>>(
                      valueListenable:Hive.box<FinancePosting>(Boxes.financePostings).listenable(),
                      builder:(context, postingBox, __) {
                        final partyType = _type == 'customer_receipt' ? 'customer' : 'supplier';
                        final accountId = partyType == 'customer' ? 'system:receivables' : 'system:payables';
                        final invoiceType = partyType == 'customer' ? 'income' : 'expense';
                        final reversed = txBox.values.where((t)=>t.status=='posted' && t.transactionType=='reversal').map((t)=>t.reversedTransactionId).whereType<String>().toSet();
                        final service = FinancePaymentAllocationService();
                        final invoices = txBox.values.where((t) =>
                          t.status == 'posted' && t.transactionType == invoiceType &&
                          !reversed.contains(t.id) && !t.date.isAfter(DateTime.now()) &&
                          postingBox.values.any((p) => p.transactionId == t.id && p.accountId == accountId && p.partyId == _partyId) &&
                          service.invoiceOutstandingPaise(invoiceId:t.id, partyId:_partyId!, partyType:partyType, transactions:txBox.values, postings:postingBox.values) > 0,
                        ).toList()..sort((a,b) => a.date.compareTo(b.date));
                        return Column(crossAxisAlignment:CrossAxisAlignment.stretch, children:[
                          for (var i=0; i<_allocationInvoiceIds.length; i++)
                            Padding(padding:const EdgeInsets.only(top:10), child: Row(crossAxisAlignment:CrossAxisAlignment.start, children:[
                              Expanded(flex:3, child: DropdownButtonFormField<String>(
                                value:invoices.any((t)=>t.id==_allocationInvoiceIds[i]) ? _allocationInvoiceIds[i] : null,
                                decoration:InputDecoration(labelText:'Invoice ${i+1}', border:const OutlineInputBorder()),
                                items:[for(final invoice in invoices) DropdownMenuItem(value:invoice.id, child:Text(invoice.transactionNumber))],
                                onChanged:(value)=>setState(()=>_allocationInvoiceIds[i]=value),
                              )),
                              const SizedBox(width:8),
                              Expanded(flex:2, child:TextField(controller:_allocationAmountControllers[i], keyboardType:const TextInputType.numberWithOptions(decimal:true), decoration:const InputDecoration(labelText:'Amount', prefixText:'₹ ', border:OutlineInputBorder()))),
                              IconButton(onPressed:()=>_removeAllocationRow(i), icon:const Icon(Icons.remove_circle_outline)),
                            ])),
                          Align(alignment:Alignment.centerLeft, child:TextButton.icon(onPressed:invoices.isEmpty ? null : _addAllocationRow, icon:const Icon(Icons.add), label:const Text('Add invoice'))),
                          if (invoices.isEmpty) const Text('No eligible posted invoices for this party.'),
                        ]);
                      },
                    ),
                  ),
                ],
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
    ));
  }
}
