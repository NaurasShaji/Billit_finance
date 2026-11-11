import 'package:flutter_test/flutter_test.dart';
import 'package:billit/models/employee.dart';
import 'package:billit/models/expense.dart';
import 'package:billit/models/sale.dart';
import 'package:billit/services/finance_service.dart';
import 'package:billit/services/payroll_service.dart';

Expense _expense(String id, DateTime date, String category, double amount,
        String description, {String? employeeId}) =>
    Expense(
      id: id,
      date: date,
      category: category,
      amount: amount,
      description: description,
      employeeId: employeeId,
    );

Sale _sale(DateTime date, double total, double profit) => Sale()
  ..id = 'S${date.microsecondsSinceEpoch}'
  ..date = date
  ..items = []
  ..totalAmount = total
  ..profit = profit;

void main() {
  final now = DateTime(2026, 11, 9, 15);

  group('PayrollService paid status', () {
    test('a payment to "Ravi Kumar" does not mark "Ravi" as paid', () {
      final ravi = Employee(id: 'e1', name: 'Ravi', type: 'monthly', wage: 20000);
      final kumar =
          Employee(id: 'e2', name: 'Ravi Kumar', type: 'monthly', wage: 25000);
      final staff = [ravi, kumar];
      final legacy = [
        _expense('x', DateTime(2026, 11, 3), 'Salary-Monthly', 25000,
            'Monthly salary paid to Ravi Kumar'),
      ];
      expect(PayrollService.isPaid(ravi, legacy, now, allEmployees: staff),
          isFalse);
      expect(PayrollService.isPaid(kumar, legacy, now, allEmployees: staff),
          isTrue);
    });

    test('id-linked payments survive a rename and never cross employees', () {
      final a = Employee(id: 'a', name: 'Ravi', type: 'monthly', wage: 100);
      final b = Employee(id: 'b', name: 'Ravi Kumar', type: 'monthly', wage: 100);
      final payment =
          PayrollService.buildPayment(a, 100, DateTime(2026, 11, 5), 'p');
      a.name = 'Ravi S';
      expect(PayrollService.isPaid(a, [payment], now, allEmployees: [a, b]),
          isTrue);
      expect(PayrollService.isPaid(b, [payment], now, allEmployees: [a, b]),
          isFalse);
    });

    test('partial payments leave the remaining salary outstanding', () {
      final employee =
          Employee(id: 'partial', name: 'Meera', type: 'monthly', wage: 20000);
      final payments = [
        PayrollService.buildPayment(
            employee, 7500, DateTime(2026, 11, 3), 'partial-1'),
        PayrollService.buildPayment(
            employee, 2500, DateTime(2026, 11, 7), 'partial-2'),
      ];

      expect(
        PayrollService.paidAmountFor(employee, payments, now,
            allEmployees: [employee]),
        10000,
      );
      expect(
        PayrollService.outstandingFor(employee, payments, now,
            allEmployees: [employee]),
        10000,
      );
      expect(
        PayrollService.isPaid(employee, payments, now,
            allEmployees: [employee]),
        isFalse,
      );
    });

    test('overpayment does not produce a negative outstanding balance', () {
      final employee =
          Employee(id: 'overpaid', name: 'Asha', type: 'monthly', wage: 1000);
      final payments = [
        PayrollService.buildPayment(
            employee, 1200, DateTime(2026, 11, 3), 'overpaid-1'),
      ];

      expect(
        PayrollService.outstandingFor(employee, payments, now,
            allEmployees: [employee]),
        0,
      );
      expect(
        PayrollService.isPaid(employee, payments, now,
            allEmployees: [employee]),
        isTrue,
      );
    });

    test('legacy payment for a duplicated name is not guessed', () {
      final a = Employee(id: '1', name: 'Anu', type: 'daily', wage: 700);
      final b = Employee(id: '2', name: 'Anu', type: 'daily', wage: 800);
      final legacy = [
        _expense('d', DateTime(2026, 11, 9, 9), 'Salary-Daily', 700,
            'Daily wage paid to Anu'),
      ];
      expect(PayrollService.isPaid(a, legacy, now, allEmployees: [a, b]),
          isFalse);
    });

    test('period boundaries', () {
      final m = Employee(id: 'm', name: 'Meera', type: 'monthly', wage: 100);
      final d = Employee(id: 'd', name: 'Joy', type: 'daily', wage: 50);
      expect(
          PayrollService.isPaid(
              m,
              [PayrollService.buildPayment(m, 100, DateTime(2026, 10, 31, 23, 59), 'a')],
              now,
              allEmployees: [m]),
          isFalse);
      expect(
          PayrollService.isPaid(
              m,
              [PayrollService.buildPayment(m, 100, DateTime(2026, 11, 1), 'b')],
              now,
              allEmployees: [m]),
          isTrue);
      expect(
          PayrollService.isPaid(
              d,
              [PayrollService.buildPayment(d, 50, DateTime(2026, 11, 8, 23, 59), 'c')],
              now,
              allEmployees: [d]),
          isFalse);
    });
  });

  group('PayrollService.summarize', () {
    test('summary reports only the unpaid portion after a partial payment', () {
      final employee =
          Employee(id: 'partial-summary', name: 'Maya', type: 'monthly', wage: 20000);
      final partial = PayrollService.buildPayment(
        employee, 8000, DateTime(2026, 11, 5), 'partial-summary-payment');
      final summary = PayrollService.summarize(
        [employee],
        [partial],
        now,
      );

      expect(summary.monthlyUnpaid, 1);
      expect(summary.monthlyDueAmount, 12000);
      expect(summary.paidThisMonth, 8000);
    });

    test('counts what is paid and what is still due', () {
      final staff = [
        Employee(id: 'm1', name: 'Meera', type: 'monthly', wage: 18000),
        Employee(id: 'm2', name: 'Nikhil', type: 'monthly', wage: 22000),
        Employee(id: 'd1', name: 'Joy', type: 'daily', wage: 700),
        Employee(id: 'd2', name: 'Kiran', type: 'daily', wage: 650),
      ];
      final expenses = [
        PayrollService.buildPayment(staff[0], 18000, DateTime(2026, 11, 2), 's1'),
        PayrollService.buildPayment(staff[2], 700, DateTime(2026, 11, 9, 8), 's2'),
        PayrollService.buildPayment(staff[2], 700, DateTime(2026, 11, 8, 8), 's3'),
        _expense('o', DateTime(2026, 11, 4), 'Rent', 12000, 'Shop rent'),
      ];
      final s = PayrollService.summarize(staff, expenses, now);
      expect(s.employeeCount, 4);
      expect(s.monthlyUnpaid, 1);
      expect(s.monthlyDueAmount, 22000);
      expect(s.dailyUnpaidToday, 1);
      expect(s.dailyDueTodayAmount, 650);
      expect(s.paidThisMonth, 19400); // rent is not payroll
      expect(s.paidToday, 700);
    });
  });

  group('FinanceService.summarize', () {
    final expenses = [
      _expense('s', DateTime(2026, 11, 2), 'Salary-Monthly', 18000, 'salary'),
      _expense('r', DateTime(2026, 11, 4), 'Rent', 12000, 'rent'),
      _expense('t', DateTime(2026, 11, 9, 11), 'Transport', 800, 'delivery'),
      _expense('old', DateTime(2026, 10, 15), 'Rent', 12000, 'last month'),
    ];
    final sales = [
      _sale(DateTime(2026, 11, 2), 10000, 3000),
      _sale(DateTime(2026, 11, 9), 5000, 1500),
      _sale(DateTime(2026, 10, 30), 99999, 99999),
    ];

    test('month totals, net profit and ordering', () {
      final m = FinanceService.summarize(
        sales: sales,
        expenses: expenses,
        span: FinanceService.spanFor(FinancePeriod.month, now),
      );
      expect(m.revenue, 15000);
      expect(m.grossProfit, 4500);
      expect(m.salaryExpenses, 18000);
      expect(m.otherExpenses, 12800);
      expect(m.netProfit, 4500 - 30800);
      expect(m.categories.first.label, 'Monthly salaries');
      expect(m.recent.first.id, 't');
    });

    test('today and year spans', () {
      final today = FinanceService.summarize(
        sales: sales,
        expenses: expenses,
        span: FinanceService.spanFor(FinancePeriod.today, now),
      );
      expect(today.totalExpenses, 800);
      final year = FinanceService.summarize(
        sales: sales,
        expenses: expenses,
        span: FinanceService.spanFor(FinancePeriod.year, now),
      );
      expect(year.otherExpenses, 12000 + 800 + 12000);
    });

    test('December rolls into the next year', () {
      final span = FinanceService.spanFor(
          FinancePeriod.month, DateTime(2026, 12, 31, 23, 59));
      expect(span.end, DateTime(2027, 1, 1));
    });
  });

  group('Expense JSON', () {
    test('keeps employeeId and still reads old backups', () {
      final p = _expense('p', DateTime(2026, 11, 1), 'Salary-Daily', 1, 'x',
          employeeId: 'e1');
      expect(Expense.fromJson(p.toJson()).employeeId, 'e1');
      expect(
        Expense.fromJson({
          'id': 'z',
          'date': '2026-11-01T00:00:00.000',
          'category': 'Rent',
          'amount': 5,
          'description': '',
        }).employeeId,
        isNull,
      );
    });
  });
}