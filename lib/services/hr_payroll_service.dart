import 'package:hive_ce/hive_ce.dart';

import '../models/models.dart';
import 'boxes.dart';
import 'finance_source_sync_service.dart';
import 'hr_service.dart';
import 'payroll_service.dart';

class HrPayrollServiceException implements Exception {
  const HrPayrollServiceException(this.message);
  final String message;

  @override
  String toString() => 'HrPayrollServiceException: $message';
}

class HrPayrollService {
  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static int _rupeesToPaise(double amount, String label) {
    if (!amount.isFinite || amount < 0) {
      throw HrPayrollServiceException('$label is not a valid amount.');
    }
    return (amount * 100).round();
  }

  static String _periodId(DateTime start, DateTime end) {
    String key(DateTime date) =>
        '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
    return 'payroll:${key(start)}:${key(end)}';
  }

  static const overtimeSettingsKey = 'hr_overtime_entries';

  List<Map<String, dynamic>> overtimeEntries(String employeeId) {
    final raw = Hive.box<dynamic>('app_settings').get(overtimeSettingsKey);
    if (raw is! Map || raw[employeeId] is! List) return const [];
    return (raw[employeeId] as List)
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .where((entry) =>
            entry['id'] is String &&
            entry['date'] is String &&
            entry['hoursMilli'] is int &&
            entry['hourlyRatePaise'] is int)
        .toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
  }

  Future<void> addOvertimeEntry({
    required String employeeId,
    required DateTime date,
    required double hours,
    required int hourlyRatePaise,
  }) async {
    if (Hive.box<Employee>(Boxes.employees).get(employeeId) == null) {
      throw const HrPayrollServiceException('Employee was not found.');
    }
    if (!hours.isFinite || hours <= 0 || hours > 24) {
      throw const HrPayrollServiceException('Overtime hours must be greater than zero and no more than 24.');
    }
    if (hourlyRatePaise <= 0) {
      throw const HrPayrollServiceException('Overtime hourly rate must be positive.');
    }
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(overtimeSettingsKey);
    final allEntries = <String, dynamic>{
      if (raw is Map) ...Map<String, dynamic>.from(raw),
    };
    final entries = allEntries[employeeId] is List
        ? List<dynamic>.from(allEntries[employeeId] as List)
        : <dynamic>[];
    final hoursMilli = (hours * 1000).round();
    entries.add({
      'id': const Uuid().v4(),
      'date': _day(date).toIso8601String(),
      'hoursMilli': hoursMilli,
      'hourlyRatePaise': hourlyRatePaise,
      'amountPaise': (hoursMilli * hourlyRatePaise / 1000).round(),
      'createdAt': DateTime.now().toIso8601String(),
    });
    allEntries[employeeId] = entries;
    await settings.put(overtimeSettingsKey, allEntries);
  }

  int _approvedOvertimePaise(String employeeId, DateTime start, DateTime end) {
    return overtimeEntries(employeeId).where((entry) {
      final date = _day(DateTime.parse(entry['date'] as String));
      return !date.isBefore(start) && !date.isAfter(end);
    }).fold<int>(
      0,
      (total, entry) => total + (entry['amountPaise'] as int),
    );
  }

  Future<PayrollRun> generateRun({
    required DateTime periodStart,
    required DateTime periodEnd,
    String memo = '',
  }) async {
    final start = _day(periodStart);
    final end = _day(periodEnd);
    if (end.isBefore(start)) {
      throw const HrPayrollServiceException(
        'Payroll period end cannot be before its start.',
      );
    }

    final employeesBox = Hive.box<Employee>(Boxes.employees);
    final componentsBox =
        Hive.box<SalaryComponent>(Boxes.salaryComponents);
    final runsBox = Hive.box<PayrollRun>(Boxes.payrollRuns);
    final payslipsBox = Hive.box<Payslip>(Boxes.payslips);
    final runId = _periodId(start, end);
    if (runsBox.containsKey(runId) ||
        runsBox.values.any((run) =>
            _day(run.periodStart) == start && _day(run.periodEnd) == end)) {
      throw const HrPayrollServiceException(
        'A payroll run already exists for this period.',
      );
    }

    final activeEmployees = employeesBox.values
        .where((employee) => employee.employmentStatus == 'active')
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final slips = <Payslip>[];
    var grossTotal = 0;
    var deductionTotal = 0;
    var netTotal = 0;

    for (final employee in activeEmployees) {
      final payType =
          employee.type == PayrollService.typeDaily ? 'daily' : 'monthly';
      final attendance = HrService().summarizeAttendance(
        employeeId: employee.id,
        start: start,
        end: end,
      );
      final workTerms = HrService().employeeWorkTerms(employee);
      final frequency = workTerms['payFrequency'] ?? 'monthly';
      final monthlyBasePaise = _rupeesToPaise(
        employee.wage,
        payType == 'daily' ? 'Daily wage' : 'Monthly salary',
      );
      final basePaise = payType == 'daily'
          ? (monthlyBasePaise * attendance.payableDays).round()
          : switch (frequency) {
              'daily' => (monthlyBasePaise * 12 / 365).round(),
              'weekly' => (monthlyBasePaise * 12 / 52).round(),
              'fortnightly' => (monthlyBasePaise / 2).round(),
              _ => monthlyBasePaise,
            };

      final components = componentsBox.values.where((component) =>
          component.employeeId == employee.id &&
          component.active &&
          !component.effectiveFrom.isAfter(end) &&
          (component.effectiveTo == null ||
              !_day(component.effectiveTo!).isBefore(start)));
      var allowances = 0;
      var deductions = 0;
      for (final component in components) {
        if (component.componentType == 'earning') {
          allowances += component.amountPaise;
        } else if (component.componentType == 'deduction') {
          deductions += component.amountPaise;
        }
      }
      final overtime = _approvedOvertimePaise(employee.id, start, end);
      final gross = basePaise + allowances + overtime;
      final net = gross - deductions;
      if (net < 0) {
        throw HrPayrollServiceException(
          'Deductions exceed gross pay for ${employee.name}.',
        );
      }

      final slip = Payslip(
        id: '$runId:${Uri.encodeComponent(employee.id)}',
        payrollRunId: runId,
        employeeId: employee.id,
        payType: payType,
        basePaise: basePaise,
        allowancesPaise: allowances,
        deductionsPaise: deductions,
        payableDays: attendance.payableDays,
      );
      slips.add(slip);
      grossTotal += gross;
      deductionTotal += deductions;
      netTotal += net;
    }

    final run = PayrollRun(
      id: runId,
      periodStart: start,
      periodEnd: end,
      totalGrossPaise: grossTotal,
      totalDeductionsPaise: deductionTotal,
      totalNetPaise: netTotal,
      memo: memo.trim(),
    );

    final insertedSlipIds = <String>[];
    try {
      await runsBox.put(run.id, run);
      for (final slip in slips) {
        await payslipsBox.put(slip.id, slip);
        insertedSlipIds.add(slip.id);
      }
    } catch (_) {
      for (final id in insertedSlipIds.reversed) {
        try {
          await payslipsBox.delete(id);
        } catch (_) {}
      }
      try {
        await runsBox.delete(run.id);
      } catch (_) {}
      rethrow;
    }
    return run;
  }

  Future<PayrollRun> approveRun(String runId) async {
    final runsBox = Hive.box<PayrollRun>(Boxes.payrollRuns);
    final slipsBox = Hive.box<Payslip>(Boxes.payslips);
    final run = runsBox.get(runId);
    if (run == null || run.status != 'draft') {
      throw const HrPayrollServiceException(
        'Only draft payroll runs can be approved.',
      );
    }
    final slips = slipsBox.values
        .where((slip) => slip.payrollRunId == runId)
        .toList();
    final oldSlips = {for (final slip in slips) slip.id: slip};
    final approvedAt = DateTime.now();
    try {
      for (final slip in slips) {
        final updated = _copyPayslip(
          slip,
          status: slip.netPaise == 0 ? 'paid' : 'approved',
          paidAt: slip.netPaise == 0 ? approvedAt : slip.paidAt,
        );
        await slipsBox.put(updated.id, updated);
      }
      final updatedRun = _copyRun(
        run,
        status: slips.every((slip) => slip.netPaise == 0) ? 'paid' : 'approved',
        approvedAt: approvedAt,
        paidAt: slips.every((slip) => slip.netPaise == 0) ? approvedAt : null,
      );
      await runsBox.put(updatedRun.id, updatedRun);
      return updatedRun;
    } catch (_) {
      for (final old in oldSlips.values) {
        try {
          await slipsBox.put(old.id, old);
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<Payslip> payPayslip({
    required String payslipId,
    required int amountPaise,
  }) async {
    if (amountPaise <= 0) {
      throw const HrPayrollServiceException(
        'Payment amount must be positive.',
      );
    }
    final runsBox = Hive.box<PayrollRun>(Boxes.payrollRuns);
    final slipsBox = Hive.box<Payslip>(Boxes.payslips);
    final expensesBox = Hive.box<Expense>(Boxes.expenses);
    final slip = slipsBox.get(payslipId);
    if (slip == null) {
      throw const HrPayrollServiceException('Payslip was not found.');
    }
    final run = runsBox.get(slip.payrollRunId);
    if (run == null || (run.status != 'approved' && run.status != 'paid')) {
      throw const HrPayrollServiceException(
        'Approve the payroll run before recording payment.',
      );
    }
    if (slip.status == 'paid') {
      final allSlips = slipsBox.values
          .where((item) => item.payrollRunId == run.id)
          .toList();
      if (allSlips.isNotEmpty &&
          allSlips.every((item) => item.status == 'paid') &&
          run.status != 'paid') {
        await runsBox.put(
          run.id,
          _copyRun(run, status: 'paid', paidAt: DateTime.now()),
        );
      }
      return slip;
    }
    if (slip.status != 'approved' && slip.status != 'partially_paid') {
      throw const HrPayrollServiceException(
        'Payslip is not in a payable state.',
      );
    }
    if (amountPaise > slip.outstandingPaise) {
      throw const HrPayrollServiceException(
        'Payment cannot exceed the payslip outstanding amount.',
      );
    }

    final paymentId = 'payroll-payment:${slip.id}:from:${slip.paidPaise}';
    final existingPayment = expensesBox.get(paymentId);
    final actualPaymentPaise = existingPayment == null
        ? amountPaise
        : _rupeesToPaise(existingPayment.amount, 'Existing payroll payment');
    if (existingPayment == null) {
      final employee = Hive.box<Employee>(Boxes.employees).get(slip.employeeId);
      if (employee == null) {
        throw const HrPayrollServiceException(
          'Payslip employee record is missing.',
        );
      }
      final expense = Expense(
        id: paymentId,
        date: DateTime.now(),
        category: 'Salary-Run',
        amount: amountPaise / 100,
        description: 'Payroll run ${run.id}, payslip ${slip.id}',
        employeeId: slip.employeeId,
      );
      await expensesBox.put(expense.id, expense);
    }
    if (actualPaymentPaise > slip.outstandingPaise) {
      throw const HrPayrollServiceException(
        'Existing payroll payment exceeds the remaining payslip balance.',
      );
    }

    final expense = expensesBox.get(paymentId)!;
    try {
      await FinanceSourceSyncService().syncExpense(
        expense: expense,
        accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts),
        transactionsBox:
            Hive.box<FinanceTransaction>(Boxes.financeTransactions),
        postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
        categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
        partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
        employeesBox: Hive.box<Employee>(Boxes.employees),
      );
    } catch (error) {
      // Do not mark the payslip as paid when its accounting journal failed.
      // Keep the source expense so startup reconciliation or a later retry can
      // post it idempotently using the stable expense ID.
      if (Hive.isBoxOpen('app_settings')) {
        await FinanceSourceSyncService.recordIssue(
          Hive.box<dynamic>('app_settings'),
          'Payroll run ${run.id}, payslip ${slip.id}: $error',
        );
      }
      throw HrPayrollServiceException(
        'Payroll payment was saved, but its finance journal could not be posted. '
        'The payslip remains unpaid; retry finance reconciliation before '
        'recording another payment. Details: $error',
      );
    }

    final paidPaise = slip.paidPaise + actualPaymentPaise;
    final updatedSlip = _copyPayslip(
      slip,
      paidPaise: paidPaise,
      status: paidPaise >= slip.netPaise ? 'paid' : 'partially_paid',
      paidAt: paidPaise >= slip.netPaise ? DateTime.now() : null,
    );
    await slipsBox.put(updatedSlip.id, updatedSlip);

    await _refreshRunStatus(run, slipsBox);
    return updatedSlip;
  }

  Future<void> _refreshRunStatus(
    PayrollRun run,
    Box<Payslip> slipsBox,
  ) async {
    final allSlips = slipsBox.values
        .where((item) => item.payrollRunId == run.id)
        .toList();
    if (allSlips.isNotEmpty &&
        allSlips.every((item) => item.status == 'paid') &&
        run.status != 'paid') {
      await Hive.box<PayrollRun>(Boxes.payrollRuns).put(
        run.id,
        _copyRun(
          run,
          status: 'paid',
          paidAt: run.paidAt ?? DateTime.now(),
        ),
      );
    }
  }

  Future<SalaryComponent> addSalaryComponent({
    required String employeeId,
    required String name,
    required String componentType,
    required int amountPaise,
    required DateTime effectiveFrom,
    DateTime? effectiveTo,
  }) async {
    final employee = Hive.box<Employee>(Boxes.employees).get(employeeId);
    if (employee == null) {
      throw const HrPayrollServiceException('Employee was not found.');
    }
    if (name.trim().isEmpty) {
      throw const HrPayrollServiceException('Component name is required.');
    }
    if (componentType != 'earning' && componentType != 'deduction') {
      throw const HrPayrollServiceException(
        'Component type must be earning or deduction.',
      );
    }
    if (amountPaise <= 0) {
      throw const HrPayrollServiceException(
        'Component amount must be positive.',
      );
    }
    if (effectiveTo != null &&
        _day(effectiveTo).isBefore(_day(effectiveFrom))) {
      throw const HrPayrollServiceException(
        'Effective end date cannot be before start date.',
      );
    }
    final component = SalaryComponent(
      id: 'salary-component:${Uri.encodeComponent(employeeId)}:${DateTime.now().microsecondsSinceEpoch}',
      employeeId: employeeId,
      name: name.trim(),
      componentType: componentType,
      amountPaise: amountPaise,
      effectiveFrom: _day(effectiveFrom),
      effectiveTo: effectiveTo == null ? null : _day(effectiveTo),
    );
    await Hive.box<SalaryComponent>(Boxes.salaryComponents)
        .put(component.id, component);
    return component;
  }

  Future<void> archiveSalaryComponent(String componentId) async {
    final box = Hive.box<SalaryComponent>(Boxes.salaryComponents);
    final component = box.get(componentId);
    if (component == null) {
      throw const HrPayrollServiceException('Salary component was not found.');
    }
    await box.put(
      component.id,
      SalaryComponent(
        id: component.id,
        employeeId: component.employeeId,
        name: component.name,
        componentType: component.componentType,
        amountPaise: component.amountPaise,
        effectiveFrom: component.effectiveFrom,
        effectiveTo: component.effectiveTo,
        active: false,
      ),
    );
  }

  Payslip _copyPayslip(
    Payslip slip, {
    int? paidPaise,
    String? status,
    DateTime? paidAt,
  }) =>
      Payslip(
        id: slip.id,
        payrollRunId: slip.payrollRunId,
        employeeId: slip.employeeId,
        payType: slip.payType,
        basePaise: slip.basePaise,
        allowancesPaise: slip.allowancesPaise,
        deductionsPaise: slip.deductionsPaise,
        payableDays: slip.payableDays,
        paidPaise: paidPaise ?? slip.paidPaise,
        status: status ?? slip.status,
        generatedAt: slip.generatedAt,
        paidAt: paidAt ?? slip.paidAt,
      );

  PayrollRun _copyRun(
    PayrollRun run, {
    String? status,
    DateTime? approvedAt,
    DateTime? paidAt,
  }) =>
      PayrollRun(
        id: run.id,
        periodStart: run.periodStart,
        periodEnd: run.periodEnd,
        status: status ?? run.status,
        createdAt: run.createdAt,
        approvedAt: approvedAt ?? run.approvedAt,
        paidAt: paidAt ?? run.paidAt,
        totalGrossPaise: run.totalGrossPaise,
        totalDeductionsPaise: run.totalDeductionsPaise,
        totalNetPaise: run.totalNetPaise,
        memo: run.memo,
      );
}
