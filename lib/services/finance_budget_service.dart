import 'package:hive_ce/hive_ce.dart';

import '../models/models.dart';
import 'boxes.dart';

class FinanceBudgetException implements Exception {
  const FinanceBudgetException(this.message);
  final String message;

  @override
  String toString() => 'FinanceBudgetException: $message';
}

class FinanceBudgetProgress {
  const FinanceBudgetProgress({
    required this.budget,
    required this.actualPaise,
  });

  final FinanceBudget budget;
  final int actualPaise;

  int get remainingPaise => budget.budgetPaise - actualPaise;
  double get usedRatio =>
      budget.budgetPaise <= 0 ? 0 : actualPaise / budget.budgetPaise;
  bool get overBudget => actualPaise > budget.budgetPaise;
}

class FinanceBudgetService {
  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Future<FinanceBudget> saveBudget({
    String? id,
    required String name,
    required String accountId,
    String? categoryId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int budgetPaise,
    String notes = '',
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const FinanceBudgetException('Budget name is required.');
    }
    if (budgetPaise <= 0) {
      throw const FinanceBudgetException('Budget amount must be positive.');
    }
    final start = _day(periodStart);
    final end = _day(periodEnd);
    if (end.isBefore(start)) {
      throw const FinanceBudgetException(
        'Budget end date cannot be before its start date.',
      );
    }

    final accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    final account = accounts.get(accountId);
    if (account == null ||
        !account.active ||
        account.accountType != 'expense' ||
        account.currencyCode != 'INR') {
      throw const FinanceBudgetException(
        'Choose an active INR expense account.',
      );
    }

    if (categoryId != null) {
      final category =
          Hive.box<FinanceCategory>(Boxes.financeCategories).get(categoryId);
      if (category == null ||
          !category.active ||
          category.kind != 'expense' ||
          category.accountId != accountId) {
        throw const FinanceBudgetException(
          'The selected category must be active and belong to this expense account.',
        );
      }
    }

    final box = Hive.box<FinanceBudget>(Boxes.financeBudgets);
    final budgetId = id ?? 'budget:${DateTime.now().microsecondsSinceEpoch}';
    final duplicate = box.values.any((item) =>
        item.id != budgetId &&
        item.active &&
        item.name.toLowerCase() == cleanName.toLowerCase() &&
        item.accountId == accountId &&
        item.periodStart == start &&
        item.periodEnd == end &&
        item.categoryId == categoryId);
    if (duplicate) {
      throw const FinanceBudgetException(
        'An active budget with the same name, account, category, and period already exists.',
      );
    }

    final existing = box.get(budgetId);
    final budget = FinanceBudget(
      id: budgetId,
      name: cleanName,
      accountId: accountId,
      categoryId: categoryId,
      periodStart: start,
      periodEnd: end,
      budgetPaise: budgetPaise,
      active: existing?.active ?? true,
      notes: notes.trim(),
      createdAt: existing?.createdAt,
    );
    await box.put(budget.id, budget);
    return budget;
  }

  Future<void> archiveBudget(String budgetId) async {
    final box = Hive.box<FinanceBudget>(Boxes.financeBudgets);
    final existing = box.get(budgetId);
    if (existing == null) {
      throw const FinanceBudgetException('Budget was not found.');
    }
    await box.put(
      budgetId,
      FinanceBudget(
        id: existing.id,
        name: existing.name,
        accountId: existing.accountId,
        categoryId: existing.categoryId,
        periodStart: existing.periodStart,
        periodEnd: existing.periodEnd,
        budgetPaise: existing.budgetPaise,
        active: false,
        notes: existing.notes,
        createdAt: existing.createdAt,
      ),
    );
  }

  List<FinanceBudgetProgress> summarize({
    required Iterable<FinanceBudget> budgets,
    required Iterable<FinanceTransaction> transactions,
    required Iterable<FinancePosting> postings,
    bool includeArchived = false,
  }) {
    final posted = {
      for (final transaction in transactions)
        if (transaction.status == 'posted') transaction.id: transaction,
    };
    final results = <FinanceBudgetProgress>[];
    for (final budget in budgets) {
      if (!includeArchived && !budget.active) continue;
      var actual = 0;
      for (final line in postings) {
        if (line.accountId != budget.accountId ||
            (budget.categoryId != null &&
                line.categoryId != budget.categoryId)) {
          continue;
        }
        final transaction = posted[line.transactionId];
        if (transaction == null) continue;
        final date = _day(transaction.date);
        if (date.isBefore(budget.periodStart) ||
            date.isAfter(budget.periodEnd)) {
          continue;
        }
        actual += line.debitPaise - line.creditPaise;
      }
      results.add(
        FinanceBudgetProgress(budget: budget, actualPaise: actual),
      );
    }
    results.sort((a, b) => a.budget.periodStart.compareTo(b.budget.periodStart));
    return results;
  }
}
