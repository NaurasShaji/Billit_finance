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
    final postedInPeriod = transactions
        .where((transaction) =>
            transaction.status == 'posted' && span.contains(transaction.date))
        .toList();
    final transactionIds = postedInPeriod.map((item) => item.id).toSet();

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

      if (line.accountId == 'system:cash' ||
          line.accountId == 'system:bank') {
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
