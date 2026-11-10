import '../models/models.dart';

class FinanceReconciliationIssue {
  const FinanceReconciliationIssue({
    required this.sourceType,
    required this.sourceId,
    required this.message,
  });

  final String sourceType;
  final String sourceId;
  final String message;

  @override
  String toString() => '$sourceType $sourceId: $message';
}

class FinanceReconciliationSummary {
  const FinanceReconciliationSummary({
    required this.sourceSaleCount,
    required this.journalSaleCount,
    required this.sourceSaleTotalPaise,
    required this.journalSaleTotalPaise,
    required this.sourceExpenseCount,
    required this.journalExpenseCount,
    required this.sourceExpenseTotalPaise,
    required this.journalExpenseTotalPaise,
    required this.issues,
  });

  final int sourceSaleCount;
  final int journalSaleCount;
  final int sourceSaleTotalPaise;
  final int journalSaleTotalPaise;
  final int sourceExpenseCount;
  final int journalExpenseCount;
  final int sourceExpenseTotalPaise;
  final int journalExpenseTotalPaise;
  final List<FinanceReconciliationIssue> issues;

  int get saleDifferencePaise =>
      sourceSaleTotalPaise - journalSaleTotalPaise;
  int get expenseDifferencePaise =>
      sourceExpenseTotalPaise - journalExpenseTotalPaise;
  bool get isBalanced => issues.isEmpty &&
      saleDifferencePaise == 0 &&
      expenseDifferencePaise == 0;
}

class FinanceReconciliationService {
  const FinanceReconciliationService();

  static int _paise(double amount) {
    if (!amount.isFinite || amount < 0) {
      throw const FormatException('Source amount must be finite and non-negative.');
    }
    return (amount * 100).round();
  }

  static String _sourceId(String id, int revision) => '$id:$revision';

  static bool _hasReversal(
    String transactionId,
    Iterable<FinanceTransaction> transactions,
  ) =>
      transactions.any(
        (transaction) =>
            transaction.transactionType == 'reversal' &&
            transaction.sourceType == 'reversal' &&
            transaction.sourceId == transactionId &&
            transaction.status == 'posted',
      );

  static int _debitTotal(
    String transactionId,
    Iterable<FinancePosting> postings,
  ) =>
      postings
          .where((line) => line.transactionId == transactionId)
          .fold<int>(0, (sum, line) => sum + line.debitPaise);

  FinanceReconciliationSummary reconcile({
    required Iterable<Sale> sales,
    required Iterable<Expense> expenses,
    required Iterable<FinanceTransaction> transactions,
    required Iterable<FinancePosting> postings,
  }) {
    final saleRecords = sales.toList();
    final expenseRecords = expenses.toList();
    final allTransactions = transactions.toList();
    final currentSaleKeys = {
      for (final sale in saleRecords) _sourceId(sale.id, sale.financeRevision),
    };
    final currentExpenseKeys = {
      for (final expense in expenseRecords)
        _sourceId(expense.id, expense.financeRevision),
    };
    final posted = allTransactions
        .where((transaction) => transaction.status == 'posted')
        .toList();
    final issues = <FinanceReconciliationIssue>[];
    var sourceSaleTotal = 0;
    var journalSaleTotal = 0;
    var journalSaleCount = 0;
    var sourceExpenseTotal = 0;
    var journalExpenseTotal = 0;
    var journalExpenseCount = 0;

    for (final sale in saleRecords) {
      final sourceId = _sourceId(sale.id, sale.financeRevision);
      int expected;
      try {
        expected = _paise(sale.totalAmount);
      } on FormatException catch (error) {
        issues.add(FinanceReconciliationIssue(
          sourceType: 'pos_sale',
          sourceId: sourceId,
          message: error.message.toString(),
        ));
        continue;
      }
      sourceSaleTotal += expected;
      final matches = posted
          .where((transaction) =>
              transaction.sourceType == 'pos_sale' &&
              transaction.sourceId == sourceId)
          .toList();
      if (matches.isEmpty) {
        issues.add(FinanceReconciliationIssue(
          sourceType: 'pos_sale',
          sourceId: sourceId,
          message: 'No posted journal transaction exists for this sale revision.',
        ));
        continue;
      }
      if (matches.length > 1) {
        issues.add(FinanceReconciliationIssue(
          sourceType: 'pos_sale',
          sourceId: sourceId,
          message: 'More than one posted journal transaction uses this source key.',
        ));
      }
      final transaction = matches.first;
      if (_hasReversal(transaction.id, allTransactions)) {
        issues.add(FinanceReconciliationIssue(
          sourceType: 'pos_sale',
          sourceId: sourceId,
          message: 'The current sale revision has been reversed.',
        ));
        continue;
      }
      final actual = _debitTotal(transaction.id, postings);
      journalSaleCount++;
      journalSaleTotal += actual;
      if (actual != expected) {
        issues.add(FinanceReconciliationIssue(
          sourceType: 'pos_sale',
          sourceId: sourceId,
          message: 'Source total is $expected paise; journal debit total is $actual paise.',
        ));
      }
    }

    for (final expense in expenseRecords) {
      final sourceId = _sourceId(expense.id, expense.financeRevision);
      int expected;
      try {
        expected = _paise(expense.amount);
      } on FormatException catch (error) {
        issues.add(FinanceReconciliationIssue(
          sourceType: 'legacy_expense',
          sourceId: sourceId,
          message: error.message.toString(),
        ));
        continue;
      }
      sourceExpenseTotal += expected;
      final matches = posted
          .where((transaction) =>
              transaction.sourceType == 'legacy_expense' &&
              transaction.sourceId == sourceId)
          .toList();
      if (matches.isEmpty) {
        issues.add(FinanceReconciliationIssue(
          sourceType: 'legacy_expense',
          sourceId: sourceId,
          message: 'No posted journal transaction exists for this expense revision.',
        ));
        continue;
      }
      if (matches.length > 1) {
        issues.add(FinanceReconciliationIssue(
          sourceType: 'legacy_expense',
          sourceId: sourceId,
          message: 'More than one posted journal transaction uses this source key.',
        ));
      }
      final transaction = matches.first;
      if (_hasReversal(transaction.id, allTransactions)) {
        issues.add(FinanceReconciliationIssue(
          sourceType: 'legacy_expense',
          sourceId: sourceId,
          message: 'The current expense revision has been reversed.',
        ));
        continue;
      }
      final actual = _debitTotal(transaction.id, postings);
      journalExpenseCount++;
      journalExpenseTotal += actual;
      if (actual != expected) {
        issues.add(FinanceReconciliationIssue(
          sourceType: 'legacy_expense',
          sourceId: sourceId,
          message: 'Source amount is $expected paise; journal debit total is $actual paise.',
        ));
      }
    }

    for (final transaction in posted) {
      if (transaction.sourceType == 'pos_sale' &&
          !currentSaleKeys.contains(transaction.sourceId) &&
          !_hasReversal(transaction.id, allTransactions)) {
        issues.add(FinanceReconciliationIssue(
          sourceType: 'pos_sale',
          sourceId: transaction.sourceId,
          message: 'Journal entry has no matching current source sale and has not been reversed.',
        ));
      }
      if (transaction.sourceType == 'legacy_expense' &&
          !currentExpenseKeys.contains(transaction.sourceId) &&
          !_hasReversal(transaction.id, allTransactions)) {
        issues.add(FinanceReconciliationIssue(
          sourceType: 'legacy_expense',
          sourceId: transaction.sourceId,
          message: 'Journal entry has no matching current source expense and has not been reversed.',
        ));
      }
    }

    return FinanceReconciliationSummary(
      sourceSaleCount: saleRecords.length,
      journalSaleCount: journalSaleCount,
      sourceSaleTotalPaise: sourceSaleTotal,
      journalSaleTotalPaise: journalSaleTotal,
      sourceExpenseCount: expenseRecords.length,
      journalExpenseCount: journalExpenseCount,
      sourceExpenseTotalPaise: sourceExpenseTotal,
      journalExpenseTotalPaise: journalExpenseTotal,
      issues: issues,
    );
  }
}
