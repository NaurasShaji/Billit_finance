import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/finance_ledger_service.dart';
import '../../../services/finance_reporting_service.dart';
import '../../../services/finance_service.dart';
import 'finance_transaction_form_screen.dart';

class FinanceLedgerScreen extends StatefulWidget {
  const FinanceLedgerScreen({super.key});

  @override
  State<FinanceLedgerScreen> createState() => _FinanceLedgerScreenState();
}

class _FinanceLedgerScreenState extends State<FinanceLedgerScreen> {
  FinancePeriod _period = FinancePeriod.month;

  String _money(int paise) => NumberFormat.simpleCurrency(locale: 'en_IN')
      .format(paise / 100);

  Future<void> _newTransaction() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const FinanceTransactionFormScreen(),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Journal transaction posted.')),
      );
    }
  }

  Future<void> _reverse(FinanceTransaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reverse transaction?'),
        content: Text(
          'This creates an exact opposite journal entry for '
          '${transaction.transactionNumber}. The original record remains unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create reversal'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await FinanceLedgerService().reverseTransaction(
        originalTransactionId: transaction.id,
        reversalId: 'finance:reversal:${transaction.id}',
        reversalNumber: 'REV-${transaction.transactionNumber}',
        reversalDate: DateTime.now(),
        accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts),
        transactionsBox:
            Hive.box<FinanceTransaction>(Boxes.financeTransactions),
        postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
        categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
        partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reversal posted.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not reverse transaction: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Accounts & Journal'),
          actions: [
            IconButton(
              onPressed: _newTransaction,
              tooltip: 'New transaction',
              icon: const Icon(Icons.add),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Accounts'),
              Tab(text: 'Journal'),
            ],
          ),
        ),
        body: ValueListenableBuilder<Box<FinanceAccount>>(
          valueListenable:
              Hive.box<FinanceAccount>(Boxes.financeAccounts).listenable(),
          builder: (context, accountsBox, _) =>
              ValueListenableBuilder<Box<FinanceTransaction>>(
            valueListenable: Hive.box<FinanceTransaction>(
              Boxes.financeTransactions,
            ).listenable(),
            builder: (context, transactionsBox, __) =>
                ValueListenableBuilder<Box<FinancePosting>>(
              valueListenable:
                  Hive.box<FinancePosting>(Boxes.financePostings).listenable(),
              builder: (context, postingsBox, ___) {
                final accounts = accountsBox.values.toList();
                final transactions = transactionsBox.values
                    .where((item) => item.status == 'posted')
                    .toList()
                  ..sort((a, b) => b.date.compareTo(a.date));
                final postings = postingsBox.values.toList();
                final postedIds = FinanceReportingService.postedTransactionIds(
                  transactionsBox.values,
                );
                final summary = const FinanceReportingService().summarize(
                  accounts: accounts,
                  transactions: transactionsBox.values,
                  postings: postings,
                  span: FinanceService.spanFor(_period, DateTime.now()),
                );

                return TabBarView(
                  children: [
                    _overview(summary),
                    _accounts(accounts, postings, postedIds),
                    _journal(transactions, postings, transactionsBox.values),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _overview(FinanceLedgerSummary summary) {
    final theme = Theme.of(context);
    final cards = [
      _summaryCard('Income', summary.incomePaise, Icons.trending_up, true),
      _summaryCard('Expenses', summary.expensePaise, Icons.trending_down, false),
      _summaryCard('Net profit', summary.netProfitPaise, Icons.account_balance, true),
      _summaryCard('Cash received', summary.cashInPaise, Icons.south_west, true),
      _summaryCard('Cash paid', summary.cashOutPaise, Icons.north_east, false),
      _summaryCard('Net cash flow', summary.netCashFlowPaise, Icons.payments, true),
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Accounting overview',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Calculated from posted journal entries. POS gross profit is reported separately.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        SegmentedButton<FinancePeriod>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: FinancePeriod.today, label: Text('Today')),
            ButtonSegment(value: FinancePeriod.month, label: Text('Month')),
            ButtonSegment(value: FinancePeriod.year, label: Text('Year')),
          ],
          selected: {_period},
          onSelectionChanged: (value) =>
              setState(() => _period = value.first),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 650 ? 3 : 2;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  SizedBox(width: width, child: card),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          '${summary.transactionCount} posted transactions in this period',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _newTransaction,
          icon: const Icon(Icons.add),
          label: const Text('Record income, expense or transfer'),
        ),
      ],
    );
  }

  Widget _summaryCard(
    String title,
    int value,
    IconData icon,
    bool positive,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(height: 10),
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _money(value),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: value < 0
                    ? theme.colorScheme.error
                    : positive
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accounts(
    List<FinanceAccount> accounts,
    List<FinancePosting> postings,
    Set<String> postedIds,
  ) {
    final theme = Theme.of(context);
    final sorted = [...accounts]
      ..sort((a, b) {
        final type = a.accountType.compareTo(b.accountType);
        return type != 0 ? type : a.name.compareTo(b.name);
      });
    if (sorted.isEmpty) {
      return const Center(child: Text('No accounts have been created.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final account = sorted[index];
        final balance = FinanceReportingService.normalBalancePaise(
          account: account,
          postings: postings,
          postedTransactionIds: postedIds,
        );
        return ListTile(
          tileColor: theme.colorScheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(account.name),
          subtitle: Text(
            '${account.accountType.toUpperCase()}'
            '${account.active ? '' : ' • ARCHIVED'}',
          ),
          trailing: Text(
            _money(balance),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }

  Widget _journal(
    List<FinanceTransaction> transactions,
    List<FinancePosting> postings,
    Iterable<FinanceTransaction> allTransactions,
  ) {
    if (transactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long_outlined, size: 48),
              const SizedBox(height: 12),
              const Text('No journal entries yet'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _newTransaction,
                icon: const Icon(Icons.add),
                label: const Text('Record transaction'),
              ),
            ],
          ),
        ),
      );
    }

    final currency = DateFormat('dd MMM yyyy');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: transactions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final transaction = transactions[index];
        final amount = FinanceReportingService.transactionAmountPaise(
          transaction.id,
          postings,
        );
        final hasReversal = allTransactions.any(
          (item) =>
              item.transactionType == 'reversal' &&
              item.sourceType == 'reversal' &&
              item.sourceId == transaction.id,
        );
        return Card(
          child: ListTile(
            title: Text(transaction.transactionNumber),
            subtitle: Text(
              '${transaction.memo.isEmpty ? transaction.transactionType : transaction.memo}\n'
              '${currency.format(transaction.date)}'
              '${hasReversal ? ' • Reversed' : ''}',
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _money(amount),
                  style: themeTextStyle(context),
                ),
                if (!hasReversal)
                  IconButton(
                    tooltip: 'Reverse transaction',
                    onPressed: () => _reverse(transaction),
                    icon: const Icon(Icons.undo),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  TextStyle? themeTextStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          );
}
