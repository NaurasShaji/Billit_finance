import 'dart:io';

import 'package:billit/models/models.dart';
import 'package:billit/services/boxes.dart';
import 'package:billit/services/finance_schema_migration.dart';
import 'package:billit/services/hr_service.dart';
import 'package:billit/services/payroll_service.dart';
import 'package:billit/services/schema_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

void main() {
  late Directory directory;
  late Box<dynamic> settings;
  late Box<Employee> employees;
  late Box<HrDepartment> departments;
  late Box<EmployeeAttendance> attendance;
  late Box<LeaveRequest> leaveRequests;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('billit_hr_service');
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
    ];
    for (final adapter in adapters) {
      if (!Hive.isAdapterRegistered(adapter.typeId)) {
        Hive.registerAdapter(adapter);
      }
    }
    settings = await Hive.openBox<dynamic>('app_settings');
    await SchemaMigrationService(
      currentVersion: 4,
      migrations: [
        FinanceSchemaMigration.versionOneToTwo,
        FinanceSchemaMigration.versionTwoToThree,
        FinanceSchemaMigration.versionThreeToFour,
      ],
    ).run(settings);
    employees = await Hive.openBox<Employee>(Boxes.employees);
    departments = Hive.box<HrDepartment>(Boxes.hrDepartments);
    attendance =
        Hive.box<EmployeeAttendance>(Boxes.employeeAttendance);
    leaveRequests = Hive.box<LeaveRequest>(Boxes.leaveRequests);
    await employees.put(
      'employee-1',
      Employee(
        id: 'employee-1',
        name: 'Anu',
        type: 'daily',
        wage: 900,
        employeeCode: 'EMP-001',
        phone: '9876543210',
        departmentId: 'system:general',
        designation: 'Sales Associate',
      ),
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('schema v4 seeds General department and profile fields persist', () {
    expect(departments.get('system:general')!.name, 'General');
    final employee = employees.get('employee-1')!;
    expect(employee.employeeCode, 'EMP-001');
    expect(employee.departmentId, 'system:general');
    expect(employee.designation, 'Sales Associate');
  });

  test('attendance upserts by employee and date and calculates payable days',
      () async {
    final service = HrService();
    final date = DateTime(2026, 11, 2);
    await service.recordAttendance(
      employeeId: 'employee-1',
      date: date,
      status: 'present',
    );
    await service.recordAttendance(
      employeeId: 'employee-1',
      date: date,
      status: 'half_day',
      notes: 'Left early',
    );
    await service.recordAttendance(
      employeeId: 'employee-1',
      date: date.add(const Duration(days: 1)),
      status: 'absent',
    );

    expect(attendance.length, 2);
    final summary = service.summarizeAttendance(
      employeeId: 'employee-1',
      start: DateTime(2026, 11, 1),
      end: DateTime(2026, 11, 30),
    );
    expect(summary.presentDays, 0);
    expect(summary.halfDays, 1);
    expect(summary.absentDays, 1);
    expect(summary.payableDays, 0.5);
  });

  test('daily wage due is driven by present and half-day attendance', () async {
    final employee = employees.get('employee-1')!;
    final service = HrService();
    final now = DateTime(2026, 11, 20);

    expect(
      PayrollService.outstandingFor(
        employee,
        const <Expense>[],
        now,
        allEmployees: [employee],
      ),
      0,
    );

    await service.recordAttendance(
      employeeId: employee.id,
      date: now,
      status: 'present',
    );
    expect(
      PayrollService.outstandingFor(
        employee,
        const <Expense>[],
        now,
        allEmployees: [employee],
      ),
      900,
    );

    await service.recordAttendance(
      employeeId: employee.id,
      date: now,
      status: 'half_day',
    );
    expect(
      PayrollService.outstandingFor(
        employee,
        const <Expense>[],
        now,
        allEmployees: [employee],
      ),
      450,
    );

    await service.recordAttendance(
      employeeId: employee.id,
      date: now,
      status: 'absent',
    );
    expect(
      PayrollService.outstandingFor(
        employee,
        const <Expense>[],
        now,
        allEmployees: [employee],
      ),
      0,
    );
  });

  test('approved leave creates attendance and prevents overlapping requests',
      () async {
    final service = HrService();
    final request = await service.submitLeaveRequest(
      employeeId: 'employee-1',
      leaveType: 'sick',
      startDate: DateTime(2026, 11, 10),
      endDate: DateTime(2026, 11, 11),
      reason: 'Medical leave',
    );

    await expectLater(
      service.submitLeaveRequest(
        employeeId: 'employee-1',
        leaveType: 'casual',
        startDate: DateTime(2026, 11, 11),
        endDate: DateTime(2026, 11, 12),
      ),
      throwsA(isA<HrServiceException>()),
    );

    final approved = await service.reviewLeaveRequest(
      requestId: request.id,
      decision: 'approved',
      reviewerId: 'admin',
    );
    expect(approved.status, 'approved');
    expect(attendance.length, 2);
    expect(attendance.values.every((record) => record.status == 'leave'), isTrue);
    expect(leaveRequests.get(request.id)!.reviewedBy, 'admin');
  });

  test('leave approval fails when attendance already exists for a date',
      () async {
    final service = HrService();
    await service.recordAttendance(
      employeeId: 'employee-1',
      date: DateTime(2026, 11, 15),
      status: 'present',
    );
    final request = await service.submitLeaveRequest(
      employeeId: 'employee-1',
      leaveType: 'casual',
      startDate: DateTime(2026, 11, 15),
      endDate: DateTime(2026, 11, 15),
    );

    await expectLater(
      service.reviewLeaveRequest(
        requestId: request.id,
        decision: 'approved',
        reviewerId: 'admin',
      ),
      throwsA(isA<HrServiceException>()),
    );
    expect(leaveRequests.get(request.id)!.status, 'pending');
    expect(attendance.values.single.status, 'present');
  });
}
