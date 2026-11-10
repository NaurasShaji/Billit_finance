import '../models/expense.dart';
import '../models/sale.dart';

/// Reporting periods offered on the Finance tab.
enum FinancePeriod { today, month, year }

/// Half-open date range: [start, end).
class DateSpan {
  const DateSpan(this.start, this.end);
  final DateTime start;
  final DateTime end;

  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);
}

/// One row of the category breakdown shown on the Finance tab.
class CategoryTotal {
  const CategoryTotal(this.label, this.amount, {this.isSalary = false});
  final String label;
  final double amount;
  final bool isSalary;
}

/// Everything the Finance tab shows for one period.
class FinanceSummary {
  const FinanceSummary({
    required this.span,
    required this.revenue,
    required this.grossProfit,
    required this.salaryExpenses,
    required this.otherExpenses,
    required this.categories,
    required this.recent,
    required this.expenseCount,
  });

  final DateSpan span;
  final double revenue;

  /// Profit on sales before any expenses (same figure the dashboard uses).
  final double grossProfit;
  final double salaryExpenses;
  final double otherExpenses;

  /// Largest first.
  final List<CategoryTotal> categories;

  /// Newest first, limited by [FinanceService.summarize]'s `recentCount`.
  final List<Expense> recent;
  final int expenseCount;

  double get totalExpenses => salaryExpenses + otherExpenses;

  /// Profit minus expenses, matching the dashboard's "Net profit".
  double get netProfit => grossProfit - totalExpenses;
}

/// Pure finance maths, kept free of Flutter/Hive so it is easy to test.
class FinanceService {
  static const salaryDailyCategory = 'Salary-Daily';
  static const salaryMonthlyCategory = 'Salary-Monthly';
  static const salaryRunCategory = 'Salary-Run';

  static bool isSalaryCategory(String category) =>
      category == salaryDailyCategory ||
      category == salaryMonthlyCategory ||
      category == salaryRunCategory;

  static bool isSalary(Expense e) => isSalaryCategory(e.category);

  /// Friendly name for a stored category value.
  static String categoryLabel(String category) {
    switch (category) {
      case salaryDailyCategory:
        return 'Daily wages';
      case salaryMonthlyCategory:
        return 'Monthly salaries';
      case salaryRunCategory:
        return 'Payroll run payments';
      default:
        return category.trim().isEmpty ? 'Uncategorised' : category.trim();
    }
  }

  static DateSpan spanFor(FinancePeriod period, DateTime now) {
    switch (period) {
      case FinancePeriod.today:
        final start = DateTime(now.year, now.month, now.day);
        return DateSpan(start, DateTime(now.year, now.month, now.day + 1));
      case FinancePeriod.month:
        return DateSpan(
            DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 1));
      case FinancePeriod.year:
        return DateSpan(DateTime(now.year, 1, 1), DateTime(now.year + 1, 1, 1));
    }
  }

  static FinanceSummary summarize({
    required List<Sale> sales,
    required List<Expense> expenses,
    required DateSpan span,
    int recentCount = 6,
  }) {
    var revenue = 0.0;
    var profit = 0.0;
    for (final sale in sales) {
      if (span.contains(sale.date)) {
        revenue += sale.totalAmount;
        profit += sale.profit;
      }
    }

    final inSpan = expenses.where((e) => span.contains(e.date)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    var salary = 0.0;
    var other = 0.0;
    final byCategory = <String, double>{};
    for (final e in inSpan) {
      if (isSalary(e)) {
        salary += e.amount;
      } else {
        other += e.amount;
      }
      byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
    }

    final categories = [
      for (final entry in byCategory.entries)
        CategoryTotal(categoryLabel(entry.key), entry.value,
            isSalary: isSalaryCategory(entry.key)),
    ]..sort((a, b) => b.amount.compareTo(a.amount));

    return FinanceSummary(
      span: span,
      revenue: revenue,
      grossProfit: profit,
      salaryExpenses: salary,
      otherExpenses: other,
      categories: categories,
      recent: inSpan.take(recentCount).toList(),
      expenseCount: inSpan.length,
    );
  }
}