import '../models/models.dart';
import 'finance_service.dart';

class FinanceLedgerSummary {
  const FinanceLedgerSummary({
    required this.incomePaise,
    required this.expensePaise,
    required this.cashInPaise,
    required this.cashOutPaise,
    required this.transactionCount,
  });

  final int incomePaise;
  final int expensePaise;
  final int cashInPaise;
  final int cashOutPaise;
  final int transactionCount;

  int get netProfitPaise => incomePaise - expensePaise;
  int get netCashFlowPaise => cashInPaise - cashOutPaise;
}

class FinanceLedgerLine {
  const FinanceLedgerLine({
    required this.transaction,
    required this.debitPaise,
    required this.creditPaise,
    required this.runningBalancePaise,
  });

  final FinanceTransaction transaction;
  final int debitPaise;
  final int creditPaise;
  final int runningBalancePaise;
}

class FinanceReportingService {
  const FinanceReportingService();

  static int normalBalancePaise({
    required FinanceAccount account,
    required Iterable<FinancePosting> postings,
    required Set<String> postedTransactionIds,
  }) {
    var debit = 0;
    var credit = 0;
    for (final line in postings) {
      if (line.accountId != account.id ||
          !postedTransactionIds.contains(line.transactionId)) {
        continue;
      }
      debit += line.debitPaise;
      credit += line.creditPaise;
    }
    return switch (account.accountType) {
      'asset' || 'expense' => debit - credit,
      'liability' || 'equity' || 'income' => credit - debit,
      _ => debit - credit,
    };
  }

  FinanceLedgerSummary summarize({
    required Iterable<FinanceAccount> accounts,
    required Iterable<FinanceTransaction> transactions,
    required Iterable<FinancePosting> postings,
    required DateSpan span,
  }) {
    final accountsById = {for (final account in accounts) account.id: account};
    final allTransactions = transactions.toList();
    final allTransactionsById = {
      for (final transaction in allTransactions) transaction.id: transaction,
    };
    final postedInPeriod = allTransactions
        .where((transaction) =>
            transaction.status == 'posted' && span.contains(transaction.date))
        .toList();
    final transactionsById = {
      for (final transaction in postedInPeriod) transaction.id: transaction,
    };
    final transactionIds = transactionsById.keys.toSet();

    var income = 0;
    var expense = 0;
    var cashIn = 0;
    var cashOut = 0;
    for (final line in postings) {
      if (!transactionIds.contains(line.transactionId)) continue;
      final account = accountsById[line.accountId];
      if (account == null) continue;

      if (account.accountType == 'income') {
        income += line.creditPaise - line.debitPaise;
      } else if (account.accountType == 'expense') {
        expense += line.debitPaise - line.creditPaise;
      }

      final transaction = transactionsById[line.transactionId]!;
      final originalTransaction = transaction.transactionType == 'reversal'
          ? allTransactionsById[transaction.reversedTransactionId]
          : null;
      final isInternalMovement =
          transaction.transactionType == 'transfer' ||
          transaction.transactionType == 'opening_balance' ||
          originalTransaction?.transactionType == 'transfer' ||
          originalTransaction?.transactionType == 'opening_balance';
      if ((line.accountId == 'system:cash' ||
              line.accountId == 'system:bank') &&
          !isInternalMovement) {
        cashIn += line.debitPaise;
        cashOut += line.creditPaise;
      }
    }

    return FinanceLedgerSummary(
      incomePaise: income,
      expensePaise: expense,
      cashInPaise: cashIn,
      cashOutPaise: cashOut,
      transactionCount: postedInPeriod.length,
    );
  }

  List<FinanceLedgerLine> ledgerForAccount({
    required FinanceAccount account,
    required Iterable<FinanceTransaction> transactions,
    required Iterable<FinancePosting> postings,
    required DateSpan span,
  }) {
    final postedById = {
      for (final transaction in transactions)
        if (transaction.status == 'posted') transaction.id: transaction,
    };
    final grouped = <String, List<FinancePosting>>{};
    for (final line in postings) {
      if (line.accountId == account.id &&
          postedById.containsKey(line.transactionId)) {
        grouped.putIfAbsent(line.transactionId, () => []).add(line);
      }
    }

    final ordered = grouped.entries.toList()
      ..sort((a, b) {
        final left = postedById[a.key]!;
        final right = postedById[b.key]!;
        final date = left.date.compareTo(right.date);
        return date != 0
            ? date
            : left.transactionNumber.compareTo(right.transactionNumber);
      });

    final normalSign =
        account.accountType == 'liability' ||
                account.accountType == 'equity' ||
                account.accountType == 'income'
            ? -1
            : 1;
    var runningBalance = 0;
    final rows = <FinanceLedgerLine>[];
    for (final entry in ordered) {
      final transaction = postedById[entry.key]!;
      final debit = entry.value.fold<int>(
        0,
        (sum, line) => sum + line.debitPaise,
      );
      final credit = entry.value.fold<int>(
        0,
        (sum, line) => sum + line.creditPaise,
      );
      final movement = (debit - credit) * normalSign;
      if (transaction.date.isBefore(span.start)) {
        runningBalance += movement;
        continue;
      }
      if (!span.contains(transaction.date)) continue;
      runningBalance += movement;
      rows.add(
        FinanceLedgerLine(
          transaction: transaction,
          debitPaise: debit,
          creditPaise: credit,
          runningBalancePaise: runningBalance,
        ),
      );
    }
    return rows;
  }

  static Set<String> postedTransactionIds(
    Iterable<FinanceTransaction> transactions,
  ) =>
      transactions
          .where((transaction) => transaction.status == 'posted')
          .map((transaction) => transaction.id)
          .toSet();

  static int transactionAmountPaise(
    String transactionId,
    Iterable<FinancePosting> postings,
  ) =>
      postings
          .where((line) => line.transactionId == transactionId)
          .fold<int>(0, (sum, line) => sum + line.debitPaise);
}
