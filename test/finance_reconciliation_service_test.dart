import 'package:billit/models/models.dart';
import 'package:billit/services/finance_reconciliation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = FinanceReconciliationService();

  Sale sale({
    String id = 'sale-1',
    double total = 118,
    int revision = 0,
  }) =>
      Sale()
        ..id = id
        ..date = DateTime(2026, 11, 1)
        ..items = []
        ..totalAmount = total
        ..financeRevision = revision;

  Expense expense({
    String id = 'expense-1',
    double amount = 50,
    int revision = 0,
  }) =>
      Expense(
        id: id,
        date: DateTime(2026, 11, 2),
        category: 'Rent',
        amount: amount,
        description: 'Rent',
        financeRevision: revision,
      );

  FinanceTransaction transaction({
    required String id,
    required String type,
    required String sourceId,
    String transactionType = 'income',
  }) =>
      FinanceTransaction(
        id: id,
        transactionNumber: id,
        transactionType: transactionType,
        status: 'posted',
        date: DateTime(2026, 11, 1),
        sourceType: type,
        sourceId: sourceId,
      );

  FinancePosting debit({
    required String id,
    required String transactionId,
    required int amount,
  }) =>
      FinancePosting(
        id: id,
        transactionId: transactionId,
        accountId: 'system:cash',
        debitPaise: amount,
      );

  test('reports matching sale and expense source totals', () {
    final result = service.reconcile(
      sales: [sale()],
      expenses: [expense()],
      transactions: [
        transaction(
          id: 'journal-sale',
          type: 'pos_sale',
          sourceId: 'sale-1:0',
        ),
        transaction(
          id: 'journal-expense',
          type: 'legacy_expense',
          sourceId: 'expense-1:0',
          transactionType: 'expense',
        ),
      ],
      postings: [
        debit(id: 'sale-debit', transactionId: 'journal-sale', amount: 11800),
        debit(
          id: 'expense-debit',
          transactionId: 'journal-expense',
          amount: 5000,
        ),
      ],
    );

    expect(result.isBalanced, isTrue);
    expect(result.sourceSaleCount, 1);
    expect(result.journalSaleCount, 1);
    expect(result.sourceSaleTotalPaise, 11800);
    expect(result.journalSaleTotalPaise, 11800);
    expect(result.sourceExpenseTotalPaise, 5000);
    expect(result.journalExpenseTotalPaise, 5000);
  });

  test('reports missing journal entries and amount mismatches', () {
    final result = service.reconcile(
      sales: [sale()],
      expenses: [expense()],
      transactions: [
        transaction(
          id: 'journal-sale',
          type: 'pos_sale',
          sourceId: 'sale-1:0',
        ),
      ],
      postings: [
        debit(id: 'sale-debit', transactionId: 'journal-sale', amount: 11700),
      ],
    );

    expect(result.isBalanced, isFalse);
    expect(result.issues, hasLength(2));
    expect(
      result.issues.any((issue) => issue.sourceType == 'pos_sale' &&
          issue.message.contains('journal debit total')),
      isTrue,
    );
    expect(
      result.issues.any((issue) => issue.sourceType == 'legacy_expense' &&
          issue.message.contains('No posted journal transaction')),
      isTrue,
    );
  });

  test('flags a current source revision whose journal was reversed', () {
    final original = transaction(
      id: 'journal-sale',
      type: 'pos_sale',
      sourceId: 'sale-1:0',
    );
    final reversal = transaction(
      id: 'reversal-sale',
      type: 'reversal',
      sourceId: original.id,
      transactionType: 'reversal',
    );
    final result = service.reconcile(
      sales: [sale()],
      expenses: const [],
      transactions: [original, reversal],
      postings: [
        debit(id: 'sale-debit', transactionId: original.id, amount: 11800),
      ],
    );

    expect(result.isBalanced, isFalse);
    expect(result.issues.single.message, contains('has been reversed'));
  });
}
