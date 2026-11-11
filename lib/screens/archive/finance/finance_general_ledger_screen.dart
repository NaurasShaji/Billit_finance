import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../widgets/responsive_page.dart';

class FinanceGeneralLedgerScreen extends StatefulWidget {
  const FinanceGeneralLedgerScreen({super.key});

  @override
  State<FinanceGeneralLedgerScreen> createState() =>
      _FinanceGeneralLedgerScreenState();
}

class _FinanceGeneralLedgerScreenState extends State<FinanceGeneralLedgerScreen> {
  String? _accountId;
  DateTimeRange? _range;

  String _money(int paise) =>
      NumberFormat.simpleCurrency(locale: 'en_IN').format(paise.abs() / 100);

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: _range,
    );
    if (picked != null && mounted) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) => ResponsivePage(child: Scaffold(
        appBar: AppBar(title: const Text('General ledger')),
        body: ValueListenableBuilder<Box<FinanceAccount>>(
          valueListenable: Hive.box<FinanceAccount>(Boxes.financeAccounts).listenable(),
          builder: (context, accountsBox, _) =>
              ValueListenableBuilder<Box<FinanceTransaction>>(
            valueListenable: Hive.box<FinanceTransaction>(Boxes.financeTransactions).listenable(),
            builder: (context, transactionsBox, __) =>
                ValueListenableBuilder<Box<FinancePosting>>(
              valueListenable: Hive.box<FinancePosting>(Boxes.financePostings).listenable(),
              builder: (context, postingsBox, ___) {
                final accounts = accountsBox.values.where((a) => a.active).toList()
                  ..sort((a, b) => a.name.compareTo(b.name));
                if (_accountId == null || !accounts.any((a) => a.id == _accountId)) {
                  _accountId = accounts.isEmpty ? null : accounts.first.id;
                }
                if (_accountId == null) {
                  return const Center(child: Text('No active accounts found.'));
                }
                final account = accounts.firstWhere((a) => a.id == _accountId);
                final start = _range == null
                    ? DateTime(2000)
                    : DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
                final endExclusive = _range == null
                    ? DateTime.now().add(const Duration(days: 1))
                    : DateTime(_range!.end.year, _range!.end.month, _range!.end.day)
                        .add(const Duration(days: 1));
                final transactions = {
                  for (final t in transactionsBox.values)
                    if (t.status == 'posted') t.id: t,
                };
                final lines = postingsBox.values
                    .where((line) => line.accountId == account.id &&
                        transactions.containsKey(line.transactionId))
                    .toList()
                  ..sort((a, b) {
                    final ta = transactions[a.transactionId]!;
                    final tb = transactions[b.transactionId]!;
                    final date = ta.date.compareTo(tb.date);
                    return date != 0 ? date : ta.transactionNumber.compareTo(tb.transactionNumber);
                  });
                var opening = 0;
                var debitTotal = 0;
                var creditTotal = 0;
                var running = 0;
                final visible = <FinancePosting>[];
                for (final line in lines) {
                  final transaction = transactions[line.transactionId]!;
                  final movement = line.debitPaise - line.creditPaise;
                  if (transaction.date.isBefore(start)) {
                    opening += movement;
                  } else if (!transaction.date.isBefore(endExclusive)) {
                    continue;
                  } else {
                    visible.add(line);
                    debitTotal += line.debitPaise;
                    creditTotal += line.creditPaise;
                  }
                }
                running = opening;
                final rows = <({FinancePosting line, FinanceTransaction transaction, int balance})>[];
                for (final line in visible) {
                  running += line.debitPaise - line.creditPaise;
                  rows.add((line: line, transaction: transactions[line.transactionId]!, balance: running));
                }
                final fmt = DateFormat('dd MMM yyyy');
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    DropdownButtonFormField<String>(
                      value: _accountId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Account', border: OutlineInputBorder()),
                      items: [
                        for (final a in accounts)
                          DropdownMenuItem(value: a.id, child: Text('${a.name} • ${a.accountType}')),
                      ],
                      onChanged: (v) => setState(() => _accountId = v),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _pickRange,
                      icon: const Icon(Icons.date_range),
                      label: Text(_range == null
                          ? 'All dates'
                          : '${fmt.format(_range!.start)} – ${fmt.format(_range!.end)}'),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _range = null),
                        child: const Text('Clear date range'),
                      ),
                    ),
                    Card(child: ListTile(
                      title: const Text('Opening balance'),
                      trailing: Text('${opening < 0 ? '-' : ''}${_money(opening)}'),
                    )),
                    Card(child: ListTile(
                      title: const Text('Period debits'),
                      trailing: Text(_money(debitTotal)),
                    )),
                    Card(child: ListTile(
                      title: const Text('Period credits'),
                      trailing: Text(_money(creditTotal)),
                    )),
                    Card(child: ListTile(
                      title: const Text('Closing balance'),
                      trailing: Text('${running < 0 ? '-' : ''}${_money(running)}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    )),
                    const SizedBox(height: 12),
                    Text('Ledger entries', style: Theme.of(context).textTheme.titleMedium),
                    if (rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No postings for this account and period.'),
                      ),
                    for (final row in rows)
                      Card(
                        child: ListTile(
                          title: Text(row.transaction.transactionNumber),
                          subtitle: Text('${fmt.format(row.transaction.date)} • ${row.transaction.memo.isEmpty ? row.line.memo : row.transaction.memo}'),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(row.line.debitPaise > 0 ? 'Dr ${_money(row.line.debitPaise)}' : 'Cr ${_money(row.line.creditPaise)}'),
                              Text('Bal ${row.balance < 0 ? '-' : ''}${_money(row.balance)}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ));
}
