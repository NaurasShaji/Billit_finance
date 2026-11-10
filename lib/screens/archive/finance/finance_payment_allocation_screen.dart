import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/finance_payment_allocation_service.dart';

class FinancePaymentAllocationScreen extends StatefulWidget {
  const FinancePaymentAllocationScreen({super.key});

  @override
  State<FinancePaymentAllocationScreen> createState() =>
      _FinancePaymentAllocationScreenState();
}

class _FinancePaymentAllocationScreenState
    extends State<FinancePaymentAllocationScreen> {
  String? _partyId;
  String? _settlementId;
  String? _invoiceId;
  final _amount = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? _parsePaise(String raw) {
    final value = raw.trim();
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    final whole = int.tryParse(parts.first);
    if (whole == null) return null;
    return whole * 100 +
        (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  }

  String _money(int paise) =>
      NumberFormat.simpleCurrency(locale: 'en_IN').format(paise / 100);

  Future<void> _allocate() async {
    if (_saving) return;
    final partyId = _partyId;
    final settlementId = _settlementId;
    final invoiceId = _invoiceId;
    final amount = _parsePaise(_amount.text);
    if (partyId == null || settlementId == null || invoiceId == null ||
        amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a party, settlement, invoice and valid amount.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final parties = Hive.box<FinanceParty>(Boxes.financeParties);
      final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
      final postings = Hive.box<FinancePosting>(Boxes.financePostings);
      final party = parties.get(partyId);
      if (party == null) throw StateError('Party was not found.');
      await FinancePaymentAllocationService().allocate(
        id: const Uuid().v4(),
        settlementTransactionId: settlementId,
        invoiceTransactionId: invoiceId,
        partyId: partyId,
        amountPaise: amount,
        partyType: party.partyType,
        transactions: transactions.values,
        postings: postings.values,
      );
      _amount.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice allocation saved.')),
        );
        setState(() {
          _invoiceId = null;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not allocate payment: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Allocate payments to invoices')),
      body: ValueListenableBuilder<Box<FinanceParty>>(
        valueListenable: Hive.box<FinanceParty>(Boxes.financeParties).listenable(),
        builder: (context, partiesBox, _) =>
            ValueListenableBuilder<Box<FinanceTransaction>>(
          valueListenable: Hive.box<FinanceTransaction>(Boxes.financeTransactions).listenable(),
          builder: (context, transactionsBox, __) =>
              ValueListenableBuilder<Box<FinancePosting>>(
            valueListenable: Hive.box<FinancePosting>(Boxes.financePostings).listenable(),
            builder: (context, postingsBox, ___) {
              final party = partiesBox.get(_partyId);
              final type = party?.partyType;
              final settlementType = type == 'customer'
                  ? 'customer_receipt'
                  : type == 'supplier' ? 'supplier_payment' : null;
              final invoiceType = type == 'customer' ? 'income' : 'expense';
              final accountId = type == 'customer'
                  ? 'system:receivables'
                  : 'system:payables';
              final posted = transactionsBox.values
                  .where((t) => t.status == 'posted').toList();
              final reversed = posted
                  .where((t) => t.transactionType == 'reversal')
                  .map((t) => t.reversedTransactionId)
                  .whereType<String>().toSet();
              final service = FinancePaymentAllocationService();
              final settlements = posted.where((t) =>
                  settlementType != null && t.transactionType == settlementType &&
                  !reversed.contains(t.id) &&
                  postingsBox.values.any((p) => p.transactionId == t.id &&
                      p.accountId == accountId && p.partyId == party?.id)).toList()
                ..sort((a,b) => b.date.compareTo(a.date));
              final invoices = posted.where((t) =>
                  t.transactionType == invoiceType && !reversed.contains(t.id) &&
                  postingsBox.values.any((p) => p.transactionId == t.id &&
                      p.accountId == accountId && p.partyId == party?.id)).toList()
                ..sort((a,b) => a.date.compareTo(b.date));
              final settlement = transactionsBox.get(_settlementId);
              final invoice = transactionsBox.get(_invoiceId);
              final settlementAmount = settlement == null || party == null ? 0 :
                  service.settlementAmountPaise(
                    settlementId: settlement.id, partyId: party.id,
                    partyType: party.partyType, transactions: posted,
                    postings: postingsBox.values);
              final settlementAllocated = settlement == null ? 0 :
                  service.allocatedFromSettlement(settlement.id, transactions: posted);
              final invoiceAmount = invoice == null || party == null ? 0 :
                  service.invoiceAmountPaise(
                    invoiceId: invoice.id, partyId: party.id,
                    partyType: party.partyType, transactions: posted,
                    postings: postingsBox.values);
              final invoiceAllocated = invoice == null ? 0 :
                  service.allocatedToInvoice(invoice.id, transactions: posted);
              final settlementRemaining = settlementAmount - settlementAllocated;
              final invoiceRemaining = invoiceAmount - invoiceAllocated;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Choose a customer or supplier, then select a posted receipt/payment and an outstanding invoice.'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _partyId,
                    decoration: const InputDecoration(labelText: 'Party', border: OutlineInputBorder()),
                    items: [
                      for (final p in partiesBox.values.where((p) => p.active && (p.partyType == 'customer' || p.partyType == 'supplier')))
                        DropdownMenuItem(value: p.id, child: Text('${p.name} • ${p.partyType}')),
                    ],
                    onChanged: (value) => setState(() {
                      _partyId = value;
                      _settlementId = null;
                      _invoiceId = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: settlements.any((t) => t.id == _settlementId) ? _settlementId : null,
                    decoration: const InputDecoration(labelText: 'Receipt / supplier payment', border: OutlineInputBorder()),
                    items: [
                      for (final t in settlements)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text('${t.transactionNumber} • ${DateFormat('dd MMM yyyy').format(t.date)}'),
                        ),
                    ],
                    onChanged: (value) => setState(() => _settlementId = value),
                  ),
                  if (settlement != null) Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Unallocated settlement: ${_money(settlementRemaining)}'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: invoices.any((t) => t.id == _invoiceId) ? _invoiceId : null,
                    decoration: const InputDecoration(labelText: 'Invoice to settle', border: OutlineInputBorder()),
                    items: [
                      for (final t in invoices)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text('${t.transactionNumber} • ${DateFormat('dd MMM yyyy').format(t.date)}'),
                        ),
                    ],
                    onChanged: (value) => setState(() => _invoiceId = value),
                  ),
                  if (invoice != null) Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Invoice outstanding: ${_money(invoiceRemaining)}'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount to allocate',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _saving || settlementRemaining <= 0 ||
                        invoiceRemaining <= 0 ? null : _allocate,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link),
                    label: Text(_saving ? 'Saving...' : 'Allocate payment'),
                  ),
                  const SizedBox(height: 24),
                  Text('Allocation history', style: Theme.of(context).textTheme.titleMedium),
                  for (final a in service.allocations.where((a) => a.partyId == _partyId))
                    Card(
                      child: ListTile(
                        title: Text('${transactionsBox.get(a.invoiceTransactionId)?.transactionNumber ?? a.invoiceTransactionId}'),
                        subtitle: Text('Settled by ${transactionsBox.get(a.settlementTransactionId)?.transactionNumber ?? a.settlementTransactionId} • ${DateFormat('dd MMM yyyy').format(a.createdAt)}'),
                        trailing: Text(_money(a.amountPaise)),
                      ),
                    ),
                  if (_partyId == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('Select a party to view its allocation history.'),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
