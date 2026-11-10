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
    await Hive.openBox<User>(Boxes.users);
    await Hive.openBox<dynamic>('session');
    final admin = User()
      ..id = 'admin'
      ..username = 'admin'
      ..password = User.hash('admin123')
      ..userType = UserType.admin;
    await Hive.box<User>(Boxes.users).put(admin.id, admin);
    await Hive.box<dynamic>('session').put('user_id', admin.id);
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

  test('check-out requires same-day check-in and valid time ordering', () async {
    final service = HrService();
    final date = DateTime(2026, 11, 20);
    await expectLater(
      service.recordAttendance(
        employeeId: 'employee-1',
        date: date,
        status: 'present',
        checkOut: DateTime(2026, 11, 20, 17),
      ),
      throwsA(isA<HrServiceException>()),
    );
    await expectLater(
      service.recordAttendance(
        employeeId: 'employee-1',
        date: date,
        status: 'present',
        checkIn: DateTime(2026, 11, 20, 18),
        checkOut: DateTime(2026, 11, 20, 17),
      ),
      throwsA(isA<HrServiceException>()),
    );
    await expectLater(
      service.recordAttendance(
        employeeId: 'employee-1',
        date: date,
        status: 'present',
        checkIn: DateTime(2026, 11, 19, 9),
      ),
      throwsA(isA<HrServiceException>()),
    );
  });

  test('employee employment type and pay frequency persist with validation', () async {
    final service = HrService();
    expect(service.employeeWorkTerms(employees.get('employee-1')!), {
      'employmentType': 'permanent',
      'payFrequency': 'daily',
    });
    await service.saveEmployeeWorkTerms(
      employeeId: 'employee-1',
      employmentType: 'contract',
      payFrequency: 'fortnightly',
    );
    expect(service.employeeWorkTerms(employees.get('employee-1')!), {
      'employmentType': 'contract',
      'payFrequency': 'fortnightly',
    });
    await expectLater(
      service.saveEmployeeWorkTerms(
        employeeId: 'employee-1',
        employmentType: 'invalid',
        payFrequency: 'monthly',
      ),
      throwsA(isA<HrServiceException>()),
    );
  });

  test('employment history persists per employee in app settings', () async {
    final service = HrService();
    await service.addEmploymentHistory(
      employeeId: 'employee-1',
      eventType: 'designation',
      title: 'Promoted to Senior Associate',
      effectiveDate: DateTime(2026, 10, 1),
      notes: 'Promotion approved by management.',
    );
    final history = service.employmentHistory('employee-1');
    expect(history, hasLength(1));
    expect(history.single['eventType'], 'designation');
    expect(history.single['title'], 'Promoted to Senior Associate');
    expect(service.employmentHistory('unknown-employee'), isEmpty);
    await expectLater(
      service.addEmploymentHistory(
        employeeId: 'employee-1',
        eventType: 'unknown',
        title: 'Invalid event',
        effectiveDate: DateTime(2026, 10, 2),
      ),
      throwsA(isA<HrServiceException>()),
    );
  });

  test('employee documents are admin-only and enforce file constraints', () async {
    final service = HrService();
    await service.addEmployeeDocument(
      employeeId: 'employee-1',
      fileName: 'contract.pdf',
      bytes: [37, 80, 68, 70],
    );
    final document = service.employeeDocuments('employee-1').single;
    expect(document['name'], 'contract.pdf');
    expect(service.employeeDocumentBytes(document), [37, 80, 68, 70]);

    await expectLater(
      service.addEmployeeDocument(
        employeeId: 'employee-1',
        fileName: 'contract.exe',
        bytes: [1, 2, 3],
      ),
      throwsA(isA<HrServiceException>()),
    );
    await expectLater(
      service.addEmployeeDocument(
        employeeId: 'employee-1',
        fileName: 'large.pdf',
        bytes: List<int>.filled(HrService.maxEmployeeDocumentBytes + 1, 1),
      ),
      throwsA(isA<HrServiceException>()),
    );

    await service.deleteEmployeeDocument(
      employeeId: 'employee-1',
      documentId: document['id'] as String,
    );
    expect(service.employeeDocuments('employee-1'), isEmpty);
  });

  test('workers cannot read or modify employee documents', () async {
    final worker = User()
      ..id = 'worker'
      ..username = 'worker'
      ..password = User.hash('worker123')
      ..userType = UserType.worker;
    await Hive.box<User>(Boxes.users).put(worker.id, worker);
    await Hive.box<dynamic>('session').put('user_id', worker.id);
    final service = HrService();

    expect(service.employeeDocuments('employee-1'), isEmpty);
    await expectLater(
      service.addEmployeeDocument(
        employeeId: 'employee-1',
        fileName: 'contract.pdf',
        bytes: [1, 2, 3],
      ),
      throwsA(isA<HrServiceException>()),
    );
  });

  test('leave balance accrues monthly and deducts approved leave', () async {
    final employee = employees.get('employee-1')!;
    employee.joiningDate = DateTime(2026, 1, 15);
    await employees.put(employee.id, employee);
    final service = HrService();
    await service.saveLeavePolicies({
      for (final type in HrService.leaveTypes)
        type: LeavePolicy(
          annualEntitlementDays: type == 'casual' ? 12 : 0,
          accrualEnabled: type == 'casual',
        ),
    });

    final beforeFirstAccrual = service.leaveBalance(
      employeeId: employee.id,
      leaveType: 'casual',
      asOf: DateTime(2026, 2, 14),
    );
    expect(beforeFirstAccrual.entitledDays, 0);

    final request = await service.submitLeaveRequest(
      employeeId: employee.id,
      leaveType: 'casual',
      startDate: DateTime(2026, 2, 20),
      endDate: DateTime(2026, 2, 20),
    );
    await service.reviewLeaveRequest(
      requestId: request.id,
      decision: 'approved',
      reviewerId: 'admin',
    );
    final balance = service.leaveBalance(
      employeeId: employee.id,
      leaveType: 'casual',
      asOf: DateTime(2026, 3, 15),
    );
    expect(balance.entitledDays, 2);
    expect(balance.usedDays, 1);
    expect(balance.availableDays, 1);
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

  test('approving leave locks an existing manually marked leave day',
      () async {
    final service = HrService();
    final date = DateTime(2026, 11, 18);
    await service.recordAttendance(
      employeeId: 'employee-1',
      date: date,
      status: 'leave',
      notes: 'Marked manually',
    );
    final request = await service.submitLeaveRequest(
      employeeId: 'employee-1',
      leaveType: 'sick',
      startDate: date,
      endDate: date,
    );

    await service.reviewLeaveRequest(
      requestId: request.id,
      decision: 'approved',
      reviewerId: 'admin',
    );

    expect(
      attendance.values.single.notes,
      'Approved leave request ${request.id}',
    );
    await expectLater(
      service.recordAttendance(
        employeeId: 'employee-1',
        date: date,
        status: 'present',
      ),
      throwsA(isA<HrServiceException>()),
    );
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
