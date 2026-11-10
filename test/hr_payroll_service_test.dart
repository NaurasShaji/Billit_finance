import 'dart:io';

import 'package:billit/models/models.dart';
import 'package:billit/services/boxes.dart';
import 'package:billit/services/finance_schema_migration.dart';
import 'package:billit/services/hr_payroll_service.dart';
import 'package:billit/services/schema_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

void main() {
  late Directory directory;
  late Box<dynamic> settings;
  late Box<Employee> employees;
  late Box<EmployeeAttendance> attendance;
  late Box<SalaryComponent> components;
  late Box<PayrollRun> runs;
  late Box<Payslip> payslips;
  late Box<Expense> expenses;
  late Box<FinanceAccount> accounts;
  late Box<FinanceTransaction> transactions;
  late Box<FinancePosting> postings;
  late Box<FinanceCategory> categories;
  late Box<FinanceParty> parties;
  late HrPayrollService payroll;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('billit_hr_payroll');
    Hive.init(directory.path);
    final adapters = <TypeAdapter>[
      UserAdapter(),
      UserTypeAdapter(),
      UnitTypeAdapter(),
      ProductAdapter(),
      PaymentMethodAdapter(),
      SaleItemAdapter(),
      SaleAdapter(),
      ExpenseAdapter(),
      EmployeeAdapter(),
      FinanceAccountAdapter(),
      FinanceTransactionAdapter(),
      FinancePostingAdapter(),
      FinanceCategoryAdapter(),
      FinancePartyAdapter(),
      HrDepartmentAdapter(),
      EmployeeAttendanceAdapter(),
      LeaveRequestAdapter(),
      SalaryComponentAdapter(),
      PayrollRunAdapter(),
      PayslipAdapter(),
    ];
    for (final adapter in adapters) {
      if (!Hive.isAdapterRegistered(adapter.typeId)) {
        Hive.registerAdapter(adapter);
      }
    }

    settings = await Hive.openBox<dynamic>('app_settings');
    await SchemaMigrationService(
      currentVersion: 5,
      migrations: [
        FinanceSchemaMigration.versionOneToTwo,
        FinanceSchemaMigration.versionTwoToThree,
        FinanceSchemaMigration.versionThreeToFour,
        FinanceSchemaMigration.versionFourToFive,
      ],
    ).run(settings);

    employees = await Hive.openBox<Employee>(Boxes.employees);
    attendance =
        Hive.box<EmployeeAttendance>(Boxes.employeeAttendance);
    components = Hive.box<SalaryComponent>(Boxes.salaryComponents);
    runs = Hive.box<PayrollRun>(Boxes.payrollRuns);
    payslips = Hive.box<Payslip>(Boxes.payslips);
    expenses = await Hive.openBox<Expense>(Boxes.expenses);
    accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    postings = Hive.box<FinancePosting>(Boxes.financePostings);
    categories = Hive.box<FinanceCategory>(Boxes.financeCategories);
    parties = Hive.box<FinanceParty>(Boxes.financeParties);
    payroll = HrPayrollService();

    await employees.put(
      'monthly-1',
      Employee(
        id: 'monthly-1',
        name: 'Maya',
        type: 'monthly',
        wage: 30000,
      ),
    );
    await employees.put(
      'daily-1',
      Employee(
        id: 'daily-1',
        name: 'Ravi',
        type: 'daily',
        wage: 1000,
      ),
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('generates payroll from salary components and daily attendance',
      () async {
    final start = DateTime(2026, 11, 1);
    final end = DateTime(2026, 11, 30);
    await attendance.put(
      'attendance:daily-1:20261103',
      EmployeeAttendance(
        id: 'attendance:daily-1:20261103',
        employeeId: 'daily-1',
        date: DateTime(2026, 11, 3),
        status: 'present',
      ),
    );
    await attendance.put(
      'attendance:daily-1:20261104',
      EmployeeAttendance(
        id: 'attendance:daily-1:20261104',
        employeeId: 'daily-1',
        date: DateTime(2026, 11, 4),
        status: 'half_day',
      ),
    );
    await components.put(
      'allowance-1',
      SalaryComponent(
        id: 'allowance-1',
        employeeId: 'monthly-1',
        name: 'Transport allowance',
        componentType: 'earning',
        amountPaise: 200000,
        effectiveFrom: start,
      ),
    );
    await components.put(
      'deduction-1',
      SalaryComponent(
        id: 'deduction-1',
        employeeId: 'monthly-1',
        name: 'Meal deduction',
        componentType: 'deduction',
        amountPaise: 50000,
        effectiveFrom: start,
      ),
    );

    final run = await payroll.generateRun(
      periodStart: start,
      periodEnd: end,
      memo: 'November payroll',
    );
    expect(run.status, 'draft');
    expect(run.totalGrossPaise, 3350000);
    expect(run.totalDeductionsPaise, 50000);
    expect(run.totalNetPaise, 3300000);
    expect(payslips, hasLength(2));

    final monthlySlip = payslips.values.singleWhere(
      (slip) => slip.employeeId == 'monthly-1',
    );
    final dailySlip = payslips.values.singleWhere(
      (slip) => slip.employeeId == 'daily-1',
    );
    expect(monthlySlip.basePaise, 3000000);
    expect(monthlySlip.allowancesPaise, 200000);
    expect(monthlySlip.deductionsPaise, 50000);
    expect(monthlySlip.netPaise, 3150000);
    expect(dailySlip.payableDays, 1.5);
    expect(dailySlip.netPaise, 150000);
    await expectLater(
      payroll.generateRun(periodStart: start, periodEnd: end),
      throwsA(isA<HrPayrollServiceException>()),
    );
  });

  test('approval and partial payslip payments post salary expenses once',
      () async {
    final start = DateTime(2026, 11, 1);
    final end = DateTime(2026, 11, 30);
    await attendance.put(
      'attendance:daily-1:20261103',
      EmployeeAttendance(
        id: 'attendance:daily-1:20261103',
        employeeId: 'daily-1',
        date: DateTime(2026, 11, 3),
        status: 'present',
      ),
    );

    final run = await payroll.generateRun(
      periodStart: start,
      periodEnd: end,
    );
    final approved = await payroll.approveRun(run.id);
    expect(approved.status, 'approved');

    final monthlySlip = payslips.values.singleWhere(
      (slip) => slip.employeeId == 'monthly-1',
    );
    final firstPayment = await payroll.payPayslip(
      payslipId: monthlySlip.id,
      amountPaise: 1000000,
    );
    expect(firstPayment.status, 'partially_paid');
    expect(firstPayment.paidPaise, 1000000);
    expect(firstPayment.outstandingPaise, 2000000);

    final secondPayment = await payroll.payPayslip(
      payslipId: monthlySlip.id,
      amountPaise: 2000000,
    );
    expect(secondPayment.status, 'paid');
    expect(secondPayment.paidPaise, 3000000);

    final dailySlip = payslips.values.singleWhere(
      (slip) => slip.employeeId == 'daily-1',
    );
    final dailyPaid = await payroll.payPayslip(
      payslipId: dailySlip.id,
      amountPaise: 100000,
    );
    expect(dailyPaid.status, 'paid');

    expect(expenses.values, hasLength(3));
    expect(
      transactions.values.where((item) => item.sourceType == 'legacy_expense'),
      hasLength(3),
    );
    final salaryLines = postings.values
        .where((line) =>
            line.accountId == 'system:salary-expense' && line.debitPaise > 0)
        .toList();
    expect(salaryLines, hasLength(3));
    expect(
      salaryLines.fold<int>(0, (sum, line) => sum + line.debitPaise),
      3100000,
    );
    expect(
      expenses.values.every((expense) => expense.category == 'Salary-Run'),
      isTrue,
    );
    expect(parties.get('employee:monthly-1')!.name, 'Maya');
    expect(parties.get('employee:daily-1')!.name, 'Ravi');
    expect(runs.get(run.id)!.status, 'paid');
  });

  test('paying a payslip cannot exceed the remaining balance', () async {
    final run = await payroll.generateRun(
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 11, 30),
    );
    await payroll.approveRun(run.id);
    final slip = payslips.values.first;
    await expectLater(
      payroll.payPayslip(
        payslipId: slip.id,
        amountPaise: slip.netPaise + 1,
      ),
      throwsA(isA<HrPayrollServiceException>()),
    );
    expect(expenses, isEmpty);
    expect(transactions, isEmpty);
  });
}
