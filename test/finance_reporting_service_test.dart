import 'package:billit/models/models.dart';
import 'package:billit/services/finance_reporting_service.dart';
import 'package:billit/services/finance_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('journal reports calculate normal balances, P&L and cash flow', () {
    final accounts = [
      FinanceAccount(
        id: 'system:cash',
        name: 'Cash',
        accountType: 'asset',
      ),
      FinanceAccount(
        id: 'system:sales-income',
        name: 'Sales',
        accountType: 'income',
      ),
      FinanceAccount(
        id: 'system:operating-expense',
        name: 'Operating expenses',
        accountType: 'expense',
      ),
      FinanceAccount(
        id: 'system:gst-payable',
        name: 'GST payable',
        accountType: 'liability',
      ),
    ];
    final transactions = [
      FinanceTransaction(
        id: 'sale-1',
        transactionNumber: 'SALE-1',
        transactionType: 'income',
        status: 'posted',
        date: DateTime(2026, 10, 5),
      ),
      FinanceTransaction(
        id: 'expense-1',
        transactionNumber: 'EXP-1',
        transactionType: 'expense',
        status: 'posted',
        date: DateTime(2026, 10, 6),
      ),
    ];
    final postings = [
      FinancePosting(
        id: 'sale-cash',
        transactionId: 'sale-1',
        accountId: 'system:cash',
        debitPaise: 11800,
      ),
      FinancePosting(
        id: 'sale-income',
        transactionId: 'sale-1',
        accountId: 'system:sales-income',
        creditPaise: 10000,
      ),
      FinancePosting(
        id: 'sale-gst',
        transactionId: 'sale-1',
        accountId: 'system:gst-payable',
        creditPaise: 1800,
      ),
      FinancePosting(
        id: 'expense-cost',
        transactionId: 'expense-1',
        accountId: 'system:operating-expense',
        debitPaise: 3000,
      ),
      FinancePosting(
        id: 'expense-cash',
        transactionId: 'expense-1',
        accountId: 'system:cash',
        creditPaise: 3000,
      ),
    ];

    final summary = const FinanceReportingService().summarize(
      accounts: accounts,
      transactions: transactions,
      postings: postings,
      span: DateSpan(DateTime(2026, 10, 1), DateTime(2026, 11, 1)),
    );

    expect(summary.incomePaise, 10000);
    expect(summary.expensePaise, 3000);
    expect(summary.netProfitPaise, 7000);
    expect(summary.cashInPaise, 11800);
    expect(summary.cashOutPaise, 3000);
    expect(summary.netCashFlowPaise, 8800);
    expect(summary.transactionCount, 2);

    final postedIds =
        FinanceReportingService.postedTransactionIds(transactions);
    expect(
      FinanceReportingService.normalBalancePaise(
        account: accounts[0],
        postings: postings,
        postedTransactionIds: postedIds,
      ),
      8800,
    );
    expect(
      FinanceReportingService.normalBalancePaise(
        account: accounts[1],
        postings: postings,
        postedTransactionIds: postedIds,
      ),
      10000,
    );
    expect(
      FinanceReportingService.normalBalancePaise(
        account: accounts[2],
        postings: postings,
        postedTransactionIds: postedIds,
      ),
      3000,
    );
  });

  test('draft and out-of-period transactions are excluded', () {
    final account = FinanceAccount(
      id: 'income',
      name: 'Income',
      accountType: 'income',
    );
    final transactions = [
      FinanceTransaction(
        id: 'draft',
        transactionNumber: 'DRAFT',
        transactionType: 'income',
        status: 'draft',
        date: DateTime(2026, 10, 5),
      ),
      FinanceTransaction(
        id: 'old',
        transactionNumber: 'OLD',
        transactionType: 'income',
        status: 'posted',
        date: DateTime(2026, 9, 5),
      ),
    ];
    final postings = [
      FinancePosting(
        id: 'draft-line',
        transactionId: 'draft',
        accountId: 'income',
        creditPaise: 10000,
      ),
      FinancePosting(
        id: 'old-line',
        transactionId: 'old',
        accountId: 'income',
        creditPaise: 20000,
      ),
    ];

    final summary = const FinanceReportingService().summarize(
      accounts: [account],
      transactions: transactions,
      postings: postings,
      span: DateSpan(DateTime(2026, 10, 1), DateTime(2026, 11, 1)),
    );
    expect(summary.incomePaise, 0);
    expect(summary.transactionCount, 0);
  });
}
