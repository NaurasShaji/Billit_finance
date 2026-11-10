import 'dart:io';

import 'package:billit/models/models.dart';
import 'package:billit/services/backup_restore_service.dart';
import 'package:billit/services/boxes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<User> users;
  late Box<Product> products;
  late Box<Sale> sales;
  late Box<Expense> expenses;
  late Box<Employee> employees;
  late Box<dynamic> settings;
  late Box<HrDepartment> departments;
  late Box<EmployeeAttendance> attendance;
  late Box<LeaveRequest> leaveRequests;
  const service = BackupRestoreService();

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('billit_hr_backup');
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
    users = await Hive.openBox<User>('users');
    products = await Hive.openBox<Product>('products');
    sales = await Hive.openBox<Sale>('sales');
    expenses = await Hive.openBox<Expense>('expenses');
    employees = await Hive.openBox<Employee>('employees');
    settings = await Hive.openBox<dynamic>('app_settings');
    departments = await Hive.openBox<HrDepartment>(Boxes.hrDepartments);
    attendance =
        await Hive.openBox<EmployeeAttendance>(Boxes.employeeAttendance);
    leaveRequests = await Hive.openBox<LeaveRequest>(Boxes.leaveRequests);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  Future<void> restore(
    Map<String, dynamic> data, {
    Future<void> Function(String stage)? afterWrite,
  }) =>
      service.restore(
        data,
        usersBox: users,
        productsBox: products,
        salesBox: sales,
        expensesBox: expenses,
        employeesBox: employees,
        appSettingsBox: settings,
        hrDepartmentsBox: departments,
        employeeAttendanceBox: attendance,
        leaveRequestsBox: leaveRequests,
        afterWrite: afterWrite,
      );

  Map<String, dynamic> validHrPayload() => {
        'employees': [
          {
            'id': 'emp-1',
            'name': 'Anu',
            'type': 'daily',
            'wage': 900,
            'employeeCode': 'EMP-001',
            'departmentId': 'dept-1',
            'designation': 'Sales',
            'employmentStatus': 'active',
          },
        ],
        'hrDepartments': [
          {
            'id': 'dept-1',
            'name': 'Sales',
            'description': '',
            'active': true,
          },
        ],
        'employeeAttendance': [
          {
            'id': 'attendance-1',
            'employeeId': 'emp-1',
            'date': '2026-11-01T00:00:00.000',
            'status': 'present',
          },
        ],
        'leaveRequests': [
          {
            'id': 'leave-1',
            'employeeId': 'emp-1',
            'leaveType': 'sick',
            'startDate': '2026-11-10T00:00:00.000',
            'endDate': '2026-11-11T00:00:00.000',
            'reason': 'Medical',
            'status': 'pending',
          },
        ],
      };

  test('restores employee profiles departments attendance and leave', () async {
    await restore(validHrPayload());

    expect(employees.get('emp-1')!.employeeCode, 'EMP-001');
    expect(employees.get('emp-1')!.departmentId, 'dept-1');
    expect(departments.get('dept-1')!.name, 'Sales');
    expect(attendance.get('attendance-1')!.status, 'present');
    expect(leaveRequests.get('leave-1')!.status, 'pending');
  });

  test('legacy backup without HR keys preserves current HR data', () async {
    await departments.put(
      'dept-existing',
      HrDepartment(id: 'dept-existing', name: 'Existing'),
    );
    await restore({'users': [], 'products': []});
    expect(departments.containsKey('dept-existing'), isTrue);
  });

  test('rejects partial HR collection payloads', () {
    expect(
      () => service.parse({'hrDepartments': []}),
      throwsFormatException,
    );
  });

  test('rejects attendance and leave references to unknown employees', () {
    final payload = validHrPayload()
      ..['employeeAttendance'] = [
        {
          'id': 'attendance-1',
          'employeeId': 'missing',
          'date': '2026-11-01T00:00:00.000',
          'status': 'present',
        },
      ];
    expect(() => service.parse(payload), throwsFormatException);
  });

  test('rolls back HR boxes when a later restore write fails', () async {
    await departments.put(
      'old-dept',
      HrDepartment(id: 'old-dept', name: 'Old department'),
    );
    await attendance.put(
      'old-attendance',
      EmployeeAttendance(
        id: 'old-attendance',
        employeeId: 'old-employee',
        date: DateTime(2026, 10, 1),
        status: 'present',
      ),
    );
    await expectLater(
      restore(
        validHrPayload(),
        afterWrite: (stage) async {
          if (stage == 'hrDepartments.putAll') {
            throw StateError('injected failure');
          }
        },
      ),
      throwsStateError,
    );
    expect(departments.keys, ['old-dept']);
    expect(attendance.keys, ['old-attendance']);
    expect(leaveRequests.isEmpty, isTrue);
  });
}
