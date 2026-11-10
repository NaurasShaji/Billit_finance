import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';

/// Party-wise receivable/payable statement derived from the immutable journal.
class FinancePartyStatementScreen extends StatefulWidget {
  const FinancePartyStatementScreen({super.key, required this.party});

  final FinanceParty party;

  @override
  State<FinancePartyStatementScreen> createState() =>
      _FinancePartyStatementScreenState();
}

class _FinancePartyStatementScreenState
    extends State<FinancePartyStatementScreen> {
  DateTime? _from;
  DateTime? _to;

  String _money(int paise) =>
      NumberFormat.simpleCurrency(locale: 'en_IN').format(paise.abs() / 100);

  String get _accountId => widget.party.partyType == 'customer'
      ? 'system:receivables'
      : 'system:payables';

  int _signedAmount(FinancePosting line) => widget.party.partyType == 'customer'
      ? line.debitPaise - line.creditPaise
      : line.creditPaise - line.debitPaise;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _from == null || _to == null
          ? null
          : DateTimeRange(start: _from!, end: _to!),
    );
    if (range != null && mounted) {
      setState(() {
        _from = DateTime(range.start.year, range.start.month, range.start.day);
        _to = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.party.name} statement'),
        actions: [
          IconButton(
            tooltip: 'Filter dates',
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range),
          ),
          if (_from != null || _to != null)
            IconButton(
              tooltip: 'Clear date filter',
              onPressed: () => setState(() {
                _from = null;
                _to = null;
              }),
              icon: const Icon(Icons.filter_alt_off),
            ),
        ],
      ),
      body: ValueListenableBuilder<Box<FinanceTransaction>>(
        valueListenable: Hive.box<FinanceTransaction>(
          Boxes.financeTransactions,
        ).listenable(),
        builder: (context, transactionsBox, _) =>
            ValueListenableBuilder<Box<FinancePosting>>(
          valueListenable:
              Hive.box<FinancePosting>(Boxes.financePostings).listenable(),
          builder: (context, postingsBox, __) {
            final transactions = {
              for (final t in transactionsBox.values)
                if (t.status == 'posted') t.id: t,
            };
            final entries = <_PartyStatementEntry>[];
            for (final line in postingsBox.values) {
              if (line.partyId != widget.party.id ||
                  line.accountId != _accountId) continue;
              final transaction = transactions[line.transactionId];
              if (transaction == null) continue;
              entries.add(_PartyStatementEntry(
                transaction: transaction,
                posting: line,
                amount: _signedAmount(line),
              ));
            }
            entries.sort((a, b) {
              final date = a.transaction.date.compareTo(b.transaction.date);
              if (date != 0) return date;
              final number = a.transaction.transactionNumber.compareTo(
                b.transaction.transactionNumber,
              );
              return number != 0 ? number : a.posting.id.compareTo(b.posting.id);
            });

            final opening = entries
                .where((e) => _from != null && e.transaction.date.isBefore(_from!))
                .fold<int>(0, (sum, e) => sum + e.amount);
            final visible = entries.where((e) {
              if (_from != null && e.transaction.date.isBefore(_from!)) {
                return false;
              }
              if (_to != null && e.transaction.date.isAfter(_to!)) return false;
              return true;
            }).toList();
            final periodNet = visible.fold<int>(
              0,
              (sum, entry) => sum + entry.amount,
            );
            final closing = opening + periodNet;
            var running = opening;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.party.partyType == 'customer'
                            ? 'Accounts receivable statement'
                            : 'Accounts payable statement',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (widget.party.phone.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(widget.party.phone),
                        ],
                        if (widget.party.taxIdentifier.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Tax ID: ${widget.party.taxIdentifier}'),
                        ],
                        const Divider(height: 24),
                        _StatementTotal(label: 'Opening balance', value: opening, money: _money),
                        _StatementTotal(label: 'Period movement', value: periodNet, money: _money),
                        _StatementTotal(label: 'Closing balance', value: closing, money: _money, emphasized: true),
                        const SizedBox(height: 8),
                        Text(
                          _from == null && _to == null
                              ? 'All posted journal activity'
                              : _to == null
                                  ? 'From ${DateFormat('dd MMM yyyy').format(_from!)} onward'
                                  : '${_from == null ? 'Beginning' : DateFormat('dd MMM yyyy').format(_from!)} – ${DateFormat('dd MMM yyyy').format(_to!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Transactions', style: Theme.of(context).textTheme.titleMedium),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No transactions in this period.'),
                  ),
                for (final entry in visible) ...[
                  Builder(builder: (context) {
                    running += entry.amount;
                    final isIncrease = entry.amount >= 0;
                    return Card(
                      child: ListTile(
                        title: Text(entry.transaction.memo.isEmpty
                            ? entry.transaction.transactionType.replaceAll('_', ' ')
                            : entry.transaction.memo),
                        subtitle: Text(
                          '${entry.transaction.transactionNumber} • ${DateFormat('dd MMM yyyy').format(entry.transaction.date)}\n'
                          '${isIncrease ? 'Increase' : 'Settlement / reduction'} • Balance ${_money(running)}',
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          '${isIncrease ? '+' : '−'}${_money(entry.amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isIncrease
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PartyStatementEntry {
  const _PartyStatementEntry({
    required this.transaction,
    required this.posting,
    required this.amount,
  });
  final FinanceTransaction transaction;
  final FinancePosting posting;
  final int amount;
}

class _StatementTotal extends StatelessWidget {
  const _StatementTotal({
    required this.label,
    required this.value,
    required this.money,
    this.emphasized = false,
  });
  final String label;
  final int value;
  final String Function(int) money;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                style: emphasized
                    ? const TextStyle(fontWeight: FontWeight.w700)
                    : null,
              ),
            ),
            Text(
              '${value < 0 ? '−' : ''}${money(value)}',
              style: emphasized
                  ? Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      )
                  : null,
            ),
          ],
        ),
      );
}
