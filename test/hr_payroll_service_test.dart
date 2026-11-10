import 'dart:io';

import 'package:billit/models/models.dart';
import 'package:billit/services/boxes.dart';
import 'package:billit/services/finance_schema_migration.dart';
import 'package:billit/services/hr_payroll_service.dart';
import 'package:billit/services/hr_service.dart';
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
      currentVersion: 10,
      migrations: [
        FinanceSchemaMigration.versionOneToTwo,
        FinanceSchemaMigration.versionTwoToThree,
        FinanceSchemaMigration.versionThreeToFour,
        FinanceSchemaMigration.versionFourToFive,
        FinanceSchemaMigration.versionFiveToSix,
        FinanceSchemaMigration.versionSixToSeven,
        FinanceSchemaMigration.versionSevenToEight,
        FinanceSchemaMigration.versionEightToNine,
        FinanceSchemaMigration.versionNineToTen,
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
    expect(payslips.values, hasLength(2));

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

  test('monthly salary is prorated by configured weekly pay frequency', () async {
    await HrService().saveEmployeeWorkTerms(
      employeeId: 'monthly-1',
      employmentType: 'permanent',
      payFrequency: 'weekly',
    );
    final run = await payroll.generateRun(
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 11, 7),
    );
    final slip = payslips.values.singleWhere(
      (item) => item.employeeId == 'monthly-1',
    );
    expect(slip.basePaise, (3000000 * 12 / 52).round());
  });

  test('dated overtime is included in payroll and payslip totals', () async {
    await payroll.addOvertimeEntry(
      employeeId: 'monthly-1',
      date: DateTime(2026, 11, 5),
      hours: 2.5,
      hourlyRatePaise: 120000,
    );
    final overtime = payroll.overtimeEntries('monthly-1').single;
    expect(overtime['status'], 'pending');
    await payroll.approveOvertimeEntry(
      employeeId: 'monthly-1',
      entryId: overtime['id'] as String,
    );
    final run = await payroll.generateRun(
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 11, 30),
    );
    final slip = payslips.values.singleWhere(
      (item) => item.employeeId == 'monthly-1',
    );
    expect(slip.allowancesPaise, 300000);
    expect(slip.netPaise, 3300000);
    expect(run.totalGrossPaise, 3300000);
  });

  test('pending and rejected overtime are excluded from payroll', () async {
    await payroll.addOvertimeEntry(
      employeeId: 'monthly-1',
      date: DateTime(2026, 11, 5),
      hours: 2,
      hourlyRatePaise: 100000,
    );
    await payroll.addOvertimeEntry(
      employeeId: 'monthly-1',
      date: DateTime(2026, 11, 6),
      hours: 1,
      hourlyRatePaise: 100000,
    );
    final entries = payroll.overtimeEntries('monthly-1');
    final pending = entries.singleWhere((item) => item['date'].toString().startsWith('2026-11-05'));
    final rejectable = entries.singleWhere((item) => item['date'].toString().startsWith('2026-11-06'));
    await payroll.rejectOvertimeEntry(
      employeeId: 'monthly-1',
      entryId: rejectable['id'] as String,
      reason: 'Not approved by supervisor',
    );
    expect(
      payroll.overtimeEntries('monthly-1').singleWhere(
        (item) => item['id'] == rejectable['id'],
      )['status'],
      'rejected',
    );

    final run = await payroll.generateRun(
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 11, 30),
    );
    final slip = payslips.values.singleWhere((item) => item.employeeId == 'monthly-1');
    expect(slip.allowancesPaise, 0);
    expect(run.totalGrossPaise, 3000000);

    await expectLater(
      payroll.addOvertimeEntry(
        employeeId: 'monthly-1',
        date: DateTime(2026, 11, 8),
        hours: 1,
        hourlyRatePaise: 100000,
      ),
      throwsA(isA<HrPayrollServiceException>()),
    );
    await expectLater(
      payroll.approveOvertimeEntry(
        employeeId: 'monthly-1',
        entryId: pending['id'] as String,
      ),
      throwsA(isA<HrPayrollServiceException>()),
    );
    final followUpRun = await payroll.generateRun(
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 12, 1),
    );
    final followUpSlip = payslips.values.singleWhere(
      (item) => item.payrollRunId == followUpRun.id && item.employeeId == 'monthly-1',
    );
    expect(followUpSlip.allowancesPaise, 0);
  });

  test('one-off bonus is included only in the payroll period containing its date', () async {
    await payroll.addBonusEntry(
      employeeId: 'monthly-1',
      date: DateTime(2026, 11, 12),
      amountPaise: 75000,
      description: 'Performance bonus',
    );
    final run = await payroll.generateRun(
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 11, 30),
    );
    final slip = payslips.values.singleWhere(
      (item) => item.employeeId == 'monthly-1',
    );
    expect(slip.allowancesPaise, 75000);
    expect(slip.netPaise, 3075000);
    expect(run.totalNetPaise, 3075000);
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
      cashAccountId: 'system:bank',
    );
    expect(firstPayment.status, 'partially_paid');
    expect(firstPayment.paidPaise, 1000000);
    expect(firstPayment.outstandingPaise, 2000000);
    final firstPaymentJournal = transactions.values.singleWhere(
      (item) => item.sourceType == 'legacy_expense' &&
          item.sourceId == 'payroll-payment:${monthlySlip.id}:from:0:0',
    );
    expect(
      postings.values.singleWhere(
        (line) => line.transactionId == firstPaymentJournal.id &&
            line.creditPaise > 0,
      ).accountId,
      'system:bank',
    );
    await expectLater(
      payroll.payPayslip(
        payslipId: monthlySlip.id,
        amountPaise: 1,
        cashAccountId: 'system:operating-expense',
      ),
      throwsA(isA<HrPayrollServiceException>()),
    );

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

  test('retrying an already-paid payslip repairs stale payroll run status',
      () async {
    final run = await payroll.generateRun(
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 11, 30),
    );
    await payroll.approveRun(run.id);
    final monthlySlip = payslips.values.singleWhere(
      (slip) => slip.employeeId == 'monthly-1',
    );
    await payroll.payPayslip(
      payslipId: monthlySlip.id,
      amountPaise: monthlySlip.netPaise,
    );
    expect(runs.get(run.id)!.status, 'paid');

    final staleRun = runs.get(run.id)!
      ..status = 'approved'
      ..paidAt = null;
    await runs.put(staleRun.id, staleRun);

    final retry = await payroll.payPayslip(
      payslipId: monthlySlip.id,
      amountPaise: 1,
    );
    expect(retry.status, 'paid');
    expect(runs.get(run.id)!.status, 'paid');
  });


  test('payroll advance recovery journals gross-up and reduces advance asset', () async {
    await payroll.addEmployeeAdvance(
      employeeId: 'monthly-1',
      principalPaise: 1000000,
      installmentPaise: 250000,
      issueDate: DateTime(2026, 10, 1),
      firstDueDate: DateTime(2026, 11, 1),
      cashAccountId: 'system:cash',
    );
    final run = await payroll.generateRun(
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 11, 30),
    );
    final slip = payslips.values.singleWhere((item) => item.employeeId == 'monthly-1');
    expect(slip.deductionsPaise, 250000);
    expect(slip.netPaise, 2750000);

    await payroll.approveRun(run.id);
    await payroll.payPayslip(payslipId: slip.id, amountPaise: slip.netPaise);

    final recovery = transactions.values.singleWhere(
      (item) => item.sourceType == 'payroll_advance_recovery' && item.sourceId == slip.id,
    );
    expect(recovery.status, 'posted');
    final recoveryLines = postings.values.where((line) => line.transactionId == recovery.id).toList();
    expect(recoveryLines.where((line) => line.accountId == 'system:salary-expense').single.debitPaise, 250000);
    expect(recoveryLines.where((line) => line.accountId == 'system:employee-advances').single.creditPaise, 250000);
    expect(payroll.advances('monthly-1').single['outstandingPaise'], 750000);
    expect(payroll.advanceReconciliation()['differencePaise'], 0);
  });

  test('manual advance issuance and repayment are journalled and reconcile', () async {
    await payroll.addEmployeeAdvance(
      employeeId: 'monthly-1',
      principalPaise: 500000,
      installmentPaise: 100000,
      issueDate: DateTime(2026, 11, 1),
      firstDueDate: DateTime(2026, 12, 1),
      cashAccountId: 'system:bank',
    );
    final advance = payroll.advances('monthly-1').single;
    await payroll.recordAdvanceRepayment(
      employeeId: 'monthly-1',
      advanceId: advance['id'] as String,
      amountPaise: 100000,
      date: DateTime(2026, 11, 15),
      cashAccountId: 'system:cash',
    );
    expect(payroll.advanceReconciliation()['subledgerPaise'], 400000);
    expect(payroll.advanceReconciliation()['journalPaise'], 400000);
    expect(payroll.advanceReconciliation()['differencePaise'], 0);
    expect(transactions.values.where((item) => item.sourceType == 'employee_advance_issue'), hasLength(1));
    expect(transactions.values.where((item) => item.sourceType == 'employee_advance_repayment'), hasLength(1));
  });

  test('multiple advance recoveries share one correctly balanced payslip journal', () async {
    await payroll.addEmployeeAdvance(
      employeeId: 'monthly-1',
      principalPaise: 600000,
      installmentPaise: 150000,
      issueDate: DateTime(2026, 10, 1),
      firstDueDate: DateTime(2026, 11, 1),
      cashAccountId: 'system:cash',
    );
    await payroll.addEmployeeAdvance(
      employeeId: 'monthly-1',
      principalPaise: 400000,
      installmentPaise: 100000,
      issueDate: DateTime(2026, 10, 2),
      firstDueDate: DateTime(2026, 11, 1),
      cashAccountId: 'system:bank',
    );
    final run = await payroll.generateRun(
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 11, 30),
    );
    final slip = payslips.values.singleWhere((item) => item.employeeId == 'monthly-1');
    expect(slip.deductionsPaise, 250000);
    await payroll.approveRun(run.id);
    await payroll.payPayslip(payslipId: slip.id, amountPaise: slip.netPaise);

    final recovery = transactions.values.singleWhere(
      (item) => item.sourceType == 'payroll_advance_recovery' && item.sourceId == slip.id,
    );
    final lines = postings.values.where((line) => line.transactionId == recovery.id).toList();
    expect(lines.where((line) => line.accountId == 'system:salary-expense').single.debitPaise, 250000);
    expect(lines.where((line) => line.accountId == 'system:employee-advances').single.creditPaise, 250000);
    expect(payroll.advances('monthly-1').where((item) => item['outstandingPaise'] == 450000), hasLength(1));
    expect(payroll.advances('monthly-1').where((item) => item['outstandingPaise'] == 300000), hasLength(1));
    expect(payroll.advanceReconciliation()['differencePaise'], 0);
  });

  test('verified legacy advance opening balance posts against opening equity', () async {
    await settings.put(HrPayrollService.advanceSettingsKey, {
      'monthly-1': [
        {
          'id': 'legacy-advance-1',
          'description': 'Legacy staff advance',
          'principalPaise': 400000,
          'outstandingPaise': 400000,
          'installmentPaise': 100000,
          'issueDate': DateTime(2026, 7, 1).toIso8601String(),
          'nextDueDate': DateTime(2026, 12, 1).toIso8601String(),
          'status': 'active',
          'repayments': <Map<String, dynamic>>[],
        },
      ],
    });

    await payroll.recordLegacyAdvanceOpeningBalance(
      employeeId: 'monthly-1',
      advanceId: 'legacy-advance-1',
      asOfDate: DateTime(2026, 11, 1),
    );

    final opening = transactions.values.singleWhere(
      (item) => item.sourceType == 'employee_advance_opening_balance',
    );
    expect(opening.transactionType, 'opening_balance');
    final lines = postings.values.where((line) => line.transactionId == opening.id).toList();
    expect(lines.where((line) => line.accountId == 'system:employee-advances').single.debitPaise, 400000);
    expect(lines.where((line) => line.accountId == 'system:opening-equity').single.creditPaise, 400000);
    expect(payroll.advanceReconciliation()['differencePaise'], 0);

    await expectLater(
      payroll.recordLegacyAdvanceOpeningBalance(
        employeeId: 'monthly-1',
        advanceId: 'legacy-advance-1',
        asOfDate: DateTime(2026, 11, 1),
      ),
      throwsA(isA<HrPayrollServiceException>()),
    );
  });

  test('legacy advance opening balance rejects repayment history', () async {
    await settings.put(HrPayrollService.advanceSettingsKey, {
      'monthly-1': [
        {
          'id': 'legacy-advance-with-repayment',
          'description': 'Legacy advance with repayment',
          'principalPaise': 600000,
          'outstandingPaise': 400000,
          'installmentPaise': 100000,
          'issueDate': DateTime(2026, 7, 1).toIso8601String(),
          'nextDueDate': DateTime(2026, 12, 1).toIso8601String(),
          'status': 'active',
          'repayments': [
            {'id': 'old-repayment', 'source': 'manual', 'amountPaise': 200000},
          ],
        },
      ],
    });

    await expectLater(
      payroll.recordLegacyAdvanceOpeningBalance(
        employeeId: 'monthly-1',
        advanceId: 'legacy-advance-with-repayment',
        asOfDate: DateTime(2026, 11, 1),
      ),
      throwsA(isA<HrPayrollServiceException>()),
    );
    expect(transactions.isEmpty, isTrue);
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
    expect(expenses.isEmpty, isTrue);
    expect(transactions.isEmpty, isTrue);
  });
  test('effective-dated base-pay changes apply to later payroll runs', () async {
    await payroll.addBasePayChange(
      employeeId: 'monthly-1',
      basePaise: 3200000,
      effectiveDate: DateTime(2026, 12, 1),
      note: 'Annual review',
    );
    final november = await payroll.generateRun(
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 11, 30),
    );
    final novemberSlip = payslips.values.singleWhere(
      (item) => item.payrollRunId == november.id && item.employeeId == 'monthly-1',
    );
    expect(novemberSlip.basePaise, 3000000);
    final december = await payroll.generateRun(
      periodStart: DateTime(2026, 12, 1),
      periodEnd: DateTime(2026, 12, 31),
    );
    final decemberSlip = payslips.values.singleWhere(
      (item) => item.payrollRunId == december.id && item.employeeId == 'monthly-1',
    );
    expect(decemberSlip.basePaise, 3200000);
    await expectLater(
      payroll.addBasePayChange(
        employeeId: 'monthly-1',
        basePaise: 3300000,
        effectiveDate: DateTime(2026, 12, 1),
      ),
      throwsA(isA<HrPayrollServiceException>()),
    );
  });

  test('salary structures can be saved and applied without overlapping old components', () async {
    await components.put('old-allowance', SalaryComponent(
      id: 'old-allowance',
      employeeId: 'monthly-1',
      name: 'Old transport',
      componentType: 'earning',
      amountPaise: 100000,
      effectiveFrom: DateTime(2026, 1, 1),
    ));
    final structureId = await HrService().saveSalaryStructure(
      name: 'Grade A',
      components: [
        {'name': 'Housing', 'componentType': 'earning', 'amountPaise': 250000},
        {'name': 'Meal deduction', 'componentType': 'deduction', 'amountPaise': 50000},
      ],
    );
    await HrService().applySalaryStructure(
      employeeId: 'monthly-1',
      structureId: structureId,
      effectiveFrom: DateTime(2026, 11, 1),
    );
    final old = components.get('old-allowance')!;
    expect(old.effectiveTo, DateTime(2026, 10, 31));
    final run = await payroll.generateRun(
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 11, 30),
    );
    final slip = payslips.values.singleWhere(
      (item) => item.payrollRunId == run.id && item.employeeId == 'monthly-1',
    );
    expect(slip.allowancesPaise, 250000);
    expect(slip.deductionsPaise, 50000);
  });

}
