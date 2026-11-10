import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'boxes.dart';
import 'finance_service.dart';
import 'finance_source_sync_service.dart';
import 'hr_service.dart';

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

  /// Total amount paid to [employee] inside the applicable payroll period.
  static double paidAmountFor(
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
        .fold<double>(0, (total, payment) => total + payment.amount);
  }

  static EmployeeAttendance? attendanceFor(
    Employee employee,
    DateTime now,
  ) {
    if (employee.type != typeDaily ||
        !Hive.isBoxOpen(Boxes.employeeAttendance)) {
      return null;
    }
    return Hive.box<EmployeeAttendance>(Boxes.employeeAttendance).get(
      HrService.attendanceId(employee.id, now),
    );
  }

  /// Remaining amount due in the applicable payroll period.
  static double outstandingFor(
    Employee employee,
    Iterable<Expense> expenses,
    DateTime now, {
    required Iterable<Employee> allEmployees,
  }) {
    var targetAmount = employee.wage;
    if (employee.type == typeDaily &&
        Hive.isBoxOpen(Boxes.employeeAttendance)) {
      final attendance = attendanceFor(employee, now);
      if (attendance == null) return 0;
      if (attendance.status == 'half_day') {
        targetAmount = employee.wage / 2;
      } else if (attendance.status != 'present') {
        return 0;
      }
    }
    final paid = paidAmountFor(
      employee,
      expenses,
      now,
      allEmployees: allEmployees,
    );
    return (targetAmount - paid).clamp(0.0, double.infinity).toDouble();
  }

  /// Monthly staff: fully paid this month. Daily staff: fully paid today.
  /// A partial payment must not mark the entire wage as paid.
  static bool isPaid(
    Employee employee,
    Iterable<Expense> expenses,
    DateTime now, {
    required Iterable<Employee> allEmployees,
  }) =>
      outstandingFor(
        employee,
        expenses,
        now,
        allEmployees: allEmployees,
      ) <= 0.005;

  static PayrollSummary summarize(
    List<Employee> employees,
    List<Expense> expenses,
    DateTime now,
  ) {
    final today = FinanceService.spanFor(FinancePeriod.today, now);
    final month = FinanceService.spanFor(FinancePeriod.month, now);

    final activeEmployees = employees
        .where((employee) => employee.employmentStatus == 'active')
        .toList();
    var monthlyCount = 0, dailyCount = 0;
    var monthlyUnpaid = 0, dailyUnpaid = 0;
    var monthlyDue = 0.0, dailyDue = 0.0;
    for (final e in activeEmployees) {
      final paid = isPaid(e, expenses, now, allEmployees: employees);
      if (e.type == typeDaily) {
        dailyCount++;
        if (!paid) {
          dailyUnpaid++;
          dailyDue += outstandingFor(e, expenses, now, allEmployees: employees);
        }
      } else {
        monthlyCount++;
        if (!paid) {
          monthlyUnpaid++;
          monthlyDue += outstandingFor(e, expenses, now, allEmployees: employees);
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
      employeeCount: activeEmployees.length,
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
    if (employee.employmentStatus != 'active') {
      throw StateError('Inactive employees cannot receive payroll payments.');
    }
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be a positive finite amount');
    }

    final expensesBox = Hive.box<Expense>(Boxes.expenses);
    final employeesBox = Hive.box<Employee>(Boxes.employees);
    final outstanding = outstandingFor(
      employee,
      expensesBox.values,
      DateTime.now(),
      allEmployees: employeesBox.values,
    );
    if (amount > outstanding + 0.005) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Cannot exceed the outstanding payroll balance of $outstanding',
      );
    }

    final payment =
        buildPayment(employee, amount, DateTime.now(), const Uuid().v4());
    await expensesBox.put(payment.id, payment);

    // Keep payroll posting additive; startup reconciliation retries failures.
    if (Hive.isBoxOpen(Boxes.financeAccounts) &&
        Hive.isBoxOpen(Boxes.financeTransactions) &&
        Hive.isBoxOpen(Boxes.financePostings) &&
        Hive.isBoxOpen(Boxes.financeCategories) &&
        Hive.isBoxOpen(Boxes.financeParties)) {
      try {
        await FinanceSourceSyncService().syncExpense(
          expense: payment,
          accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts),
          transactionsBox: Hive.box<FinanceTransaction>(Boxes.financeTransactions),
          postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
          categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
          partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
          employeesBox: employeesBox,
        );
      } catch (error) {
        if (Hive.isBoxOpen('app_settings')) {
          await FinanceSourceSyncService.recordIssue(
            Hive.box<dynamic>('app_settings'),
            'Payroll expense ${payment.id}: $error',
          );
        }
      }
    }
    return payment;
  }
}