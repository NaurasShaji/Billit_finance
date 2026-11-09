import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/employee.dart';
import '../models/expense.dart';
import 'boxes.dart';
import 'finance_service.dart';

/// Everything the Team tab shows about payroll for the current day/month.
class PayrollSummary {
  const PayrollSummary({
    required this.employeeCount,
    required this.monthlyCount,
    required this.dailyCount,
    required this.monthlyUnpaid,
    required this.monthlyDueAmount,
    required this.dailyUnpaidToday,
    required this.dailyDueTodayAmount,
    required this.paidThisMonth,
    required this.paidToday,
  });

  final int employeeCount;
  final int monthlyCount;
  final int dailyCount;

  /// Monthly-salary staff not yet paid this month, and what they are owed.
  final int monthlyUnpaid;
  final double monthlyDueAmount;

  /// Daily-wage staff not yet paid today, and what they are owed.
  final int dailyUnpaidToday;
  final double dailyDueTodayAmount;

  /// All salary + wage payments recorded this month / today.
  final double paidThisMonth;
  final double paidToday;
}

/// Payroll rules, kept separate from the screens so they are consistent
/// everywhere and testable without Flutter.
class PayrollService {
  static const typeDaily = 'daily';
  static const typeMonthly = 'monthly';

  static String categoryFor(Employee e) => e.type == typeDaily
      ? FinanceService.salaryDailyCategory
      : FinanceService.salaryMonthlyCategory;

  static String _legacyDescription(Employee e) => e.type == typeDaily
      ? 'Daily wage paid to ${e.name}'
      : 'Monthly salary paid to ${e.name}';

  /// Builds (does not save) the expense record for a payment.
  static Expense buildPayment(
    Employee employee,
    double amount,
    DateTime when,
    String id,
  ) =>
      Expense(
        id: id,
        date: when,
        category: categoryFor(employee),
        amount: amount,
        description: _legacyDescription(employee),
        employeeId: employee.id,
      );

  /// Payments for [employee] inside [span].
  ///
  /// Matches by employee id. Payments saved before ids were recorded are
  /// matched by their exact original description, and only when no other
  /// employee shares that name (so one person's payment can never be
  /// credited to someone else).
  static List<Expense> paymentsFor(
    Employee employee,
    Iterable<Expense> expenses,
    DateSpan span, {
    required Iterable<Employee> allEmployees,
  }) {
    final category = categoryFor(employee);
    final nameIsUnique =
        allEmployees.where((e) => e.name == employee.name).length <= 1;
    final legacy = _legacyDescription(employee);
    return expenses.where((x) {
      if (x.category != category || !span.contains(x.date)) return false;
      if (x.employeeId != null) return x.employeeId == employee.id;
      return nameIsUnique && x.description == legacy;
    }).toList();
  }

  /// Monthly staff: paid this month. Daily staff: paid today.
  static bool isPaid(
    Employee employee,
    Iterable<Expense> expenses,
    DateTime now, {
    required Iterable<Employee> allEmployees,
  }) {
    final span = FinanceService.spanFor(
      employee.type == typeDaily ? FinancePeriod.today : FinancePeriod.month,
      now,
    );
    return paymentsFor(employee, expenses, span, allEmployees: allEmployees)
        .isNotEmpty;
  }

  static PayrollSummary summarize(
    List<Employee> employees,
    List<Expense> expenses,
    DateTime now,
  ) {
    final today = FinanceService.spanFor(FinancePeriod.today, now);
    final month = FinanceService.spanFor(FinancePeriod.month, now);

    var monthlyCount = 0, dailyCount = 0;
    var monthlyUnpaid = 0, dailyUnpaid = 0;
    var monthlyDue = 0.0, dailyDue = 0.0;
    for (final e in employees) {
      final paid = isPaid(e, expenses, now, allEmployees: employees);
      if (e.type == typeDaily) {
        dailyCount++;
        if (!paid) {
          dailyUnpaid++;
          dailyDue += e.wage;
        }
      } else {
        monthlyCount++;
        if (!paid) {
          monthlyUnpaid++;
          monthlyDue += e.wage;
        }
      }
    }

    var paidMonth = 0.0, paidToday = 0.0;
    for (final x in expenses) {
      if (!FinanceService.isSalary(x)) continue;
      if (month.contains(x.date)) paidMonth += x.amount;
      if (today.contains(x.date)) paidToday += x.amount;
    }

    return PayrollSummary(
      employeeCount: employees.length,
      monthlyCount: monthlyCount,
      dailyCount: dailyCount,
      monthlyUnpaid: monthlyUnpaid,
      monthlyDueAmount: monthlyDue,
      dailyUnpaidToday: dailyUnpaid,
      dailyDueTodayAmount: dailyDue,
      paidThisMonth: paidMonth,
      paidToday: paidToday,
    );
  }

  /// Records a salary/wage payment as an expense linked to the employee.
  static Future<Expense> recordPayment(Employee employee, double amount) async {
    final payment =
        buildPayment(employee, amount, DateTime.now(), const Uuid().v4());
    await Hive.box<Expense>(Boxes.expenses).put(payment.id, payment);
    return payment;
  }
}