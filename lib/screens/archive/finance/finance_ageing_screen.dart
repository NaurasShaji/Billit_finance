import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/finance_payment_allocation_service.dart';
import '../../../widgets/responsive_page.dart';

enum FinanceAgeingBucket { current, days1To30, days31To60, days61To90, over90 }

class FinanceAgeingRow {
  const FinanceAgeingRow({
    required this.party,
    required this.invoice,
    required this.dueDate,
    required this.outstandingPaise,
    required this.daysOverdue,
    required this.bucket,
  });
  final FinanceParty party;
  final FinanceTransaction invoice;
  final DateTime dueDate;
  final int outstandingPaise;
  final int daysOverdue;
  final FinanceAgeingBucket bucket;
}

class FinanceAgeingService {
  const FinanceAgeingService();

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  List<FinanceAgeingRow> build({
    Iterable<FinancePaymentAllocation> allocations = const [],
    required String partyType,
    required DateTime asOf,
    required Iterable<FinanceParty> parties,
    required Iterable<FinanceTransaction> transactions,
    required Iterable<FinancePosting> postings,
  }) {
    if (partyType != 'customer' && partyType != 'supplier') {
      throw ArgumentError.value(partyType, 'partyType');
    }
    final cutoff = _day(asOf);
    final activeParties = {
      for (final p in parties)
        if (p.active && p.partyType == partyType) p.id: p,
    };
    final posted = {
      for (final t in transactions)
        if (t.status == 'posted' && !_day(t.date).isAfter(cutoff)) t.id: t,
    };
    final reversed = posted.values
        .where((t) => t.transactionType == 'reversal')
        .map((t) => t.reversedTransactionId)
        .whereType<String>()
        .toSet();
    final account = partyType == 'customer'
        ? 'system:receivables'
        : 'system:payables';
    final settlementType =
        partyType == 'customer' ? 'customer_receipt' : 'supplier_payment';
    final isDebitInvoice = partyType == 'customer';
    final isCreditSettlement = partyType == 'customer';
    final linesByTransaction = <String, List<FinancePosting>>{};
    for (final line in postings) {
      if (posted.containsKey(line.transactionId)) {
        linesByTransaction.putIfAbsent(line.transactionId, () => []).add(line);
      }
    }

    final invoices = <_AgeingInvoice>[];
    final settlements = <_AgeingSettlement>[];
    for (final entry in linesByTransaction.entries) {
      final transaction = posted[entry.key]!;
      if (transaction.transactionType == 'reversal' ||
          reversed.contains(transaction.id)) continue;
      for (final line in entry.value) {
        final partyId = line.partyId;
        if (line.accountId != account ||
            partyId == null ||
            !activeParties.containsKey(partyId)) continue;
        final invoiceAmount =
            isDebitInvoice ? line.debitPaise : line.creditPaise;
        if ((transaction.transactionType == 'income' ||
                transaction.transactionType == 'expense') &&
            invoiceAmount > 0) {
          invoices.add(_AgeingInvoice(
            party: activeParties[partyId]!,
            transaction: transaction,
            dueDate: _day(transaction.dueDate ?? transaction.date),
            amount: invoiceAmount,
          ));
        } else if (transaction.transactionType == settlementType) {
          final amount =
              isCreditSettlement ? line.creditPaise : line.debitPaise;
          if (amount > 0) {
            settlements.add(_AgeingSettlement(
              transactionId: transaction.id,
              partyId: partyId,
              date: _day(transaction.date),
              amount: amount,
            ));
          }
        }
      }
    }

    invoices.sort((a, b) {
      final date = a.transaction.date.compareTo(b.transaction.date);
      return date != 0
          ? date
          : a.transaction.transactionNumber.compareTo(
              b.transaction.transactionNumber);
    });
    settlements.sort((a, b) => a.date.compareTo(b.date));

    // Apply explicit invoice allocations first. They are immutable records;
    // a reversal of either linked journal transaction makes them ineffective.
    final settlementById = {
      for (final settlement in settlements) settlement.transactionId: settlement,
    };
    final invoiceById = {
      for (final invoice in invoices) invoice.transaction.id: invoice,
    };
    final explicitlyAllocated = <String, int>{};
    for (final allocation in allocations) {
      final settlement = settlementById[allocation.settlementTransactionId];
      final invoice = invoiceById[allocation.invoiceTransactionId];
      if (settlement == null || invoice == null ||
          settlement.partyId != allocation.partyId ||
          invoice.party.id != allocation.partyId ||
          allocation.createdAt.isAfter(cutoff.add(const Duration(days: 1)))) {
        continue;
      }
      final applied = allocation.amountPaise < invoice.remaining
          ? allocation.amountPaise
          : invoice.remaining;
      if (applied <= 0) continue;
      invoice.remaining -= applied;
      explicitlyAllocated.update(
        settlement.transactionId,
        (value) => value + applied,
        ifAbsent: () => applied,
      );
    }

    // Preserve legacy behaviour for receipts/payments that have not yet been
    // explicitly allocated: only their unallocated amount is applied FIFO.
    for (final settlement in settlements) {
      var remaining = settlement.amount -
          (explicitlyAllocated[settlement.transactionId] ?? 0);
      for (final invoice in invoices) {
        if (remaining == 0) break;
        if (invoice.party.id != settlement.partyId ||
            invoice.remaining == 0 ||
            invoice.transaction.date.isAfter(settlement.date)) continue;
        final applied =
            remaining < invoice.remaining ? remaining : invoice.remaining;
        invoice.remaining -= applied;
        remaining -= applied;
      }
    }

    final result = <FinanceAgeingRow>[];
    for (final invoice in invoices) {
      if (invoice.remaining <= 0) continue;
      final days = cutoff.difference(invoice.dueDate).inDays;
      final bucket = days <= 0
          ? FinanceAgeingBucket.current
          : days <= 30
              ? FinanceAgeingBucket.days1To30
              : days <= 60
                  ? FinanceAgeingBucket.days31To60
                  : days <= 90
                      ? FinanceAgeingBucket.days61To90
                      : FinanceAgeingBucket.over90;
      result.add(FinanceAgeingRow(
        party: invoice.party,
        invoice: invoice.transaction,
        dueDate: invoice.dueDate,
        outstandingPaise: invoice.remaining,
        daysOverdue: days > 0 ? days : 0,
        bucket: bucket,
      ));
    }
    result.sort((a, b) {
      final p = a.party.name.compareTo(b.party.name);
      if (p != 0) return p;
      return a.dueDate.compareTo(b.dueDate);
    });
    return result;
  }
}

class _AgeingInvoice {
  _AgeingInvoice({
    required this.party,
    required this.transaction,
    required this.dueDate,
    required int amount,
  }) : remaining = amount;
  final FinanceParty party;
  final FinanceTransaction transaction;
  final DateTime dueDate;
  int remaining;
}

class _AgeingSettlement {
  const _AgeingSettlement({
    required this.transactionId,
    required this.partyId,
    required this.date,
    required this.amount,
  });
  final String transactionId;
  final String partyId;
  final DateTime date;
  final int amount;
}

class FinanceAgeingScreen extends StatefulWidget {
  const FinanceAgeingScreen({super.key});
  @override
  State<FinanceAgeingScreen> createState() => _FinanceAgeingScreenState();
}

class _FinanceAgeingScreenState extends State<FinanceAgeingScreen> {
  String _type = 'customer';
  DateTime _asOf = DateTime.now();

  String _money(int paise) =>
      NumberFormat.simpleCurrency(locale: 'en_IN').format(paise / 100);

  String _label(FinanceAgeingBucket b) => switch (b) {
        FinanceAgeingBucket.current => 'Current / not due',
        FinanceAgeingBucket.days1To30 => '1–30 days',
        FinanceAgeingBucket.days31To60 => '31–60 days',
        FinanceAgeingBucket.days61To90 => '61–90 days',
        FinanceAgeingBucket.over90 => '90+ days',
      };

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _asOf,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() => _asOf = DateTime(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) => ScaffolResponsivePage(child: Scaffold((
        appBar: AppBar(title: const Text('Receivables / payables ageing')),
        body: ValueListenableBuilder<Box<Map>>(
          valueListenable: Hive.box<Map>(Boxes.financePaymentAllocations).listenable(),
          builder: (context, allocationBox, _) => ValueListenableBuilder<Box<FinanceParty>>(
          valueListenable:
              Hive.box<FinanceParty>(Boxes.financeParties).listenable(),
          builder: (context, parties, _) =>
              ValueListenableBuilder<Box<FinanceTransaction>>(
            valueListenable: Hive.box<FinanceTransaction>(
              Boxes.financeTransactions,
            ).listenable(),
            builder: (context, transactions, __) =>
                ValueListenableBuilder<Box<FinancePosting>>(
              valueListenable:
                  Hive.box<FinancePosting>(Boxes.financePostings).listenable(),
              builder: (context, postings, ___) {
                final rows = const FinanceAgeingService().build(
                  partyType: _type,
                  allocations: allocationBox.values.map(FinancePaymentAllocation.fromMap),
                  asOf: _asOf,
                  parties: parties.values,
                  transactions: transactions.values,
                  postings: postings.values,
                );
                final total = rows.fold<int>(
                    0, (sum, row) => sum + row.outstandingPaise);
                final totals = {
                  for (final b in FinanceAgeingBucket.values)
                    b: rows
                        .where((row) => row.bucket == b)
                        .fold<int>(0, (sum, row) => sum + row.outstandingPaise),
                };
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                            value: 'customer', label: Text('Receivables')),
                        ButtonSegment(
                            value: 'supplier', label: Text('Payables')),
                      ],
                      selected: {_type},
                      onSelectionChanged: (value) =>
                          setState(() => _type = value.first),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(
                        'Ageing as of ${DateFormat('dd MMM yyyy').format(_asOf)}',
                      ),
                    ),
                    Card(
                      child: ListTile(
                        title: const Text('Total outstanding'),
                        subtitle: Text('${rows.length} open invoice(s)'),
                        trailing: Text(_money(total)),
                      ),
                    ),
                    for (final bucket in FinanceAgeingBucket.values)
                      Card(
                        child: ListTile(
                          title: Text(_label(bucket)),
                          trailing: Text(_money(totals[bucket]!)),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text('Open invoices',
                        style: Theme.of(context).textTheme.titleMedium),
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No outstanding invoices for this date.'),
                      ),
                    for (final row in rows)
                      Card(
                        child: ListTile(
                          title: Text(row.party.name),
                          subtitle: Text(
                            '${row.invoice.transactionNumber} • Due ${DateFormat('dd MMM yyyy').format(row.dueDate)} • ${row.daysOverdue == 0 ? 'Not overdue' : '${row.daysOverdue} days overdue'}',
                          ),
                          trailing: Text(_money(row.outstandingPaise)),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Explicit invoice allocations are applied first. Any remaining unallocated receipt/payment balance is applied FIFO for legacy compatibility. Invoices without an explicit due date use their transaction date.',
                      style: Theme.of(context).textTheme.bodySmall,
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
