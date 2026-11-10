import 'package:hive_ce/hive_ce.dart';

import '../models/employee.dart';
import '../models/expense.dart';
import '../models/finance_account.dart';
import '../models/finance_budget.dart';
import '../models/finance_recurring_template.dart';
import '../models/finance_category.dart';
import '../models/finance_party.dart';
import '../models/finance_posting.dart';
import '../models/finance_transaction.dart';
import '../models/hr_department.dart';
import '../models/employee_attendance.dart';
import '../models/leave_request.dart';
import '../models/salary_component.dart';
import '../models/payroll_run.dart';
import '../models/payslip.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/user.dart';

/// Fully parsed backup data. Constructing this object performs all validation,
/// before the caller mutates any live Hive box.
class BackupRestorePayload {
  final List<User> users;
  final List<Product> products;
  final List<Sale> sales;
  final List<Expense> expenses;
  final List<Employee> employees;
  /// Null means a legacy backup that predates finance-ledger serialization.
  final List<FinanceAccount>? financeAccounts;
  final List<FinanceTransaction>? financeTransactions;
  final List<FinancePosting>? financePostings;
  final List<FinanceCategory>? financeCategories;
  final List<FinanceParty>? financeParties;
  /// Null means the backup predates budget serialization.
  final List<FinanceBudget>? financeBudgets;
  /// Null means the backup predates recurring-template serialization.
  final List<FinanceRecurringTemplate>? financeRecurringTemplates;
  /// Null means a legacy backup that predates HR serialization.
  final List<HrDepartment>? hrDepartments;
  final List<EmployeeAttendance>? employeeAttendance;
  final List<LeaveRequest>? leaveRequests;
  final List<SalaryComponent>? salaryComponents;
  final List<PayrollRun>? payrollRuns;
  final List<Payslip>? payslips;
  final Map<String, dynamic>? appSettings;

  const BackupRestorePayload({
    required this.users,
    required this.products,
    required this.sales,
    required this.expenses,
    required this.employees,
    required this.financeAccounts,
    required this.financeTransactions,
    required this.financePostings,
    required this.financeCategories,
    required this.financeParties,
    this.financeBudgets,
    this.financeRecurringTemplates,
    required this.hrDepartments,
    required this.employeeAttendance,
    required this.leaveRequests,
    required this.salaryComponents,
    required this.payrollRuns,
    required this.payslips,
    required this.appSettings,
  });
}

class BackupRestoreService {
  const BackupRestoreService();

  /// Parses first, then applies. Invalid data cannot mutate live boxes.
  Future<void> restore(
    Map<String, dynamic> data, {
    required Box<User> usersBox,
    required Box<Product> productsBox,
    required Box<Sale> salesBox,
    required Box<Expense> expensesBox,
    required Box<Employee> employeesBox,
    required Box<dynamic> appSettingsBox,
    Box<FinanceAccount>? financeAccountsBox,
    Box<FinanceTransaction>? financeTransactionsBox,
    Box<FinancePosting>? financePostingsBox,
    Box<FinanceCategory>? financeCategoriesBox,
    Box<FinanceParty>? financePartiesBox,
    Box<FinanceBudget>? financeBudgetsBox,
    Box<FinanceRecurringTemplate>? financeRecurringTemplatesBox,
    Box<HrDepartment>? hrDepartmentsBox,
    Box<EmployeeAttendance>? employeeAttendanceBox,
    Box<LeaveRequest>? leaveRequestsBox,
    Box<SalaryComponent>? salaryComponentsBox,
    Box<PayrollRun>? payrollRunsBox,
    Box<Payslip>? payslipsBox,
    Future<void> Function(String stage)? afterWrite,
  }) async {
    final payload = parse(data);
    await apply(
      payload,
      usersBox: usersBox,
      productsBox: productsBox,
      salesBox: salesBox,
      expensesBox: expensesBox,
      employeesBox: employeesBox,
      appSettingsBox: appSettingsBox,
      financeAccountsBox: financeAccountsBox,
      financeTransactionsBox: financeTransactionsBox,
      financePostingsBox: financePostingsBox,
      financeCategoriesBox: financeCategoriesBox,
      financePartiesBox: financePartiesBox,
      financeBudgetsBox: financeBudgetsBox,
      financeRecurringTemplatesBox: financeRecurringTemplatesBox,
      hrDepartmentsBox: hrDepartmentsBox,
      employeeAttendanceBox: employeeAttendanceBox,
      leaveRequestsBox: leaveRequestsBox,
      salaryComponentsBox: salaryComponentsBox,
      payrollRunsBox: payrollRunsBox,
      payslipsBox: payslipsBox,
      afterWrite: afterWrite,
    );
  }

  /// Applies a previously validated payload. Hive does not provide a
  /// multi-box transaction, so existing contents are snapshotted and restored
  /// on a write failure (best effort).
  Future<void> apply(
    BackupRestorePayload payload, {
    required Box<User> usersBox,
    required Box<Product> productsBox,
    required Box<Sale> salesBox,
    required Box<Expense> expensesBox,
    required Box<Employee> employeesBox,
    required Box<dynamic> appSettingsBox,
    Box<FinanceAccount>? financeAccountsBox,
    Box<FinanceTransaction>? financeTransactionsBox,
    Box<FinancePosting>? financePostingsBox,
    Box<FinanceCategory>? financeCategoriesBox,
    Box<FinanceParty>? financePartiesBox,
    Box<FinanceBudget>? financeBudgetsBox,
    Box<FinanceRecurringTemplate>? financeRecurringTemplatesBox,
    Box<HrDepartment>? hrDepartmentsBox,
    Box<EmployeeAttendance>? employeeAttendanceBox,
    Box<LeaveRequest>? leaveRequestsBox,
    Box<SalaryComponent>? salaryComponentsBox,
    Box<PayrollRun>? payrollRunsBox,
    Box<Payslip>? payslipsBox,
    Future<void> Function(String stage)? afterWrite,
  }) async {
    final hasFinancePayload = payload.financeAccounts != null;
    final hasBudgetPayload = payload.financeBudgets != null;
    final hasRecurringPayload = payload.financeRecurringTemplates != null;
    if (hasRecurringPayload && financeRecurringTemplatesBox == null) {
      throw const FormatException(
        'Recurring finance backup data was supplied but recurring-template storage is unavailable.',
      );
    }
    if (hasFinancePayload &&
        !hasRecurringPayload &&
        financeRecurringTemplatesBox != null) {
      final restoredAccountIds =
          payload.financeAccounts!.map((item) => item.id).toSet();
      final restoredCategoryIds =
          payload.financeCategories!.map((item) => item.id).toSet();
      final restoredPartyIds =
          payload.financeParties!.map((item) => item.id).toSet();
      for (final template in financeRecurringTemplatesBox.values) {
        if (!restoredAccountIds.contains(template.debitAccountId) ||
            !restoredAccountIds.contains(template.creditAccountId) ||
            (template.categoryId != null &&
                !restoredCategoryIds.contains(template.categoryId)) ||
            (template.partyId != null &&
                !restoredPartyIds.contains(template.partyId))) {
          throw FormatException(
            'Restoring this older finance backup would orphan recurring template ${template.id}.',
          );
        }
      }
    }
    if (hasBudgetPayload && financeBudgetsBox == null) {
      throw const FormatException(
        'Finance budget backup data was supplied but budget storage is unavailable.',
      );
    }
    if (hasFinancePayload &&
        !hasBudgetPayload &&
        financeBudgetsBox != null) {
      final restoredAccountIds =
          payload.financeAccounts!.map((item) => item.id).toSet();
      final restoredCategoryIds =
          payload.financeCategories!.map((item) => item.id).toSet();
      for (final budget in financeBudgetsBox.values) {
        if (!restoredAccountIds.contains(budget.accountId) ||
            (budget.categoryId != null &&
                !restoredCategoryIds.contains(budget.categoryId))) {
          throw FormatException(
            'Restoring this older finance backup would orphan budget ${budget.id}.',
          );
        }
      }
    }
    if (hasFinancePayload &&
        (financeAccountsBox == null ||
            financeTransactionsBox == null ||
            financePostingsBox == null ||
            financeCategoriesBox == null ||
            financePartiesBox == null)) {
      throw const FormatException(
        'Finance backup data was supplied but finance storage boxes are unavailable.',
      );
    }

    final hasHrPayload = payload.hrDepartments != null;
    final hasPayrollPayload = payload.salaryComponents != null;
    if (hasHrPayload &&
        (hrDepartmentsBox == null ||
            employeeAttendanceBox == null ||
            leaveRequestsBox == null)) {
      throw const FormatException(
        'HR backup data was supplied but HR storage boxes are unavailable.',
      );
    }

    final hrDepartmentsSnapshot = hrDepartmentsBox == null
        ? null
        : Map<dynamic, HrDepartment>.from(hrDepartmentsBox.toMap());
    final employeeAttendanceSnapshot = employeeAttendanceBox == null
        ? null
        : Map<dynamic, EmployeeAttendance>.from(employeeAttendanceBox.toMap());
    final leaveRequestsSnapshot = leaveRequestsBox == null
        ? null
        : Map<dynamic, LeaveRequest>.from(leaveRequestsBox.toMap());

    if (hasPayrollPayload &&
        (salaryComponentsBox == null ||
            payrollRunsBox == null ||
            payslipsBox == null)) {
      throw const FormatException(
        'Payroll backup data was supplied but payroll storage boxes are unavailable.',
      );
    }

    final salaryComponentsSnapshot = salaryComponentsBox == null
        ? null
        : Map<dynamic, SalaryComponent>.from(salaryComponentsBox.toMap());
    final payrollRunsSnapshot = payrollRunsBox == null
        ? null
        : Map<dynamic, PayrollRun>.from(payrollRunsBox.toMap());
    final payslipsSnapshot = payslipsBox == null
        ? null
        : Map<dynamic, Payslip>.from(payslipsBox.toMap());

    final financeAccountsSnapshot =
        financeAccountsBox == null ? null : Map<dynamic, FinanceAccount>.from(financeAccountsBox.toMap());
    final financeTransactionsSnapshot = financeTransactionsBox == null
        ? null
        : Map<dynamic, FinanceTransaction>.from(financeTransactionsBox.toMap());
    final financePostingsSnapshot =
        financePostingsBox == null ? null : Map<dynamic, FinancePosting>.from(financePostingsBox.toMap());
    final financeCategoriesSnapshot =
        financeCategoriesBox == null ? null : Map<dynamic, FinanceCategory>.from(financeCategoriesBox.toMap());
    final financePartiesSnapshot =
        financePartiesBox == null ? null : Map<dynamic, FinanceParty>.from(financePartiesBox.toMap());
    final financeBudgetsSnapshot =
        financeBudgetsBox == null ? null : Map<dynamic, FinanceBudget>.from(financeBudgetsBox.toMap());
    final financeRecurringTemplatesSnapshot = financeRecurringTemplatesBox == null
        ? null
        : Map<dynamic, FinanceRecurringTemplate>.from(financeRecurringTemplatesBox.toMap());

    final usersSnapshot = Map<dynamic, User>.from(usersBox.toMap());
    final productsSnapshot = Map<dynamic, Product>.from(productsBox.toMap());
    final salesSnapshot = Map<dynamic, Sale>.from(salesBox.toMap());
    final expensesSnapshot = Map<dynamic, Expense>.from(expensesBox.toMap());
    final employeesSnapshot = Map<dynamic, Employee>.from(employeesBox.toMap());
    final settingsSnapshot = Map<dynamic, dynamic>.from(appSettingsBox.toMap());

    try {
      await usersBox.clear();
      await usersBox.putAll({for (final item in payload.users) item.id: item});
      await afterWrite?.call('users.putAll');
      await productsBox.clear();
      await productsBox.putAll({for (final item in payload.products) item.id: item});
      await afterWrite?.call('products.putAll');
      await salesBox.clear();
      await salesBox.putAll({for (final item in payload.sales) item.id: item});
      await afterWrite?.call('sales.putAll');
      await expensesBox.clear();
      await expensesBox.putAll({for (final item in payload.expenses) item.id: item});
      await afterWrite?.call('expenses.putAll');
      await employeesBox.clear();
      await employeesBox.putAll({for (final item in payload.employees) item.id: item});
      await afterWrite?.call('employees.putAll');
      if (hasHrPayload) {
        await hrDepartmentsBox!.clear();
        await hrDepartmentsBox.putAll({
          for (final item in payload.hrDepartments!) item.id: item,
        });
        await afterWrite?.call('hrDepartments.putAll');
        await employeeAttendanceBox!.clear();
        await employeeAttendanceBox.putAll({
          for (final item in payload.employeeAttendance!) item.id: item,
        });
        await afterWrite?.call('employeeAttendance.putAll');
        await leaveRequestsBox!.clear();
        await leaveRequestsBox.putAll({
          for (final item in payload.leaveRequests!) item.id: item,
        });
        await afterWrite?.call('leaveRequests.putAll');
      }
      if (hasPayrollPayload) {
        await salaryComponentsBox!.clear();
        await salaryComponentsBox.putAll({
          for (final item in payload.salaryComponents!) item.id: item,
        });
        await afterWrite?.call('salaryComponents.putAll');
        await payrollRunsBox!.clear();
        await payrollRunsBox.putAll({
          for (final item in payload.payrollRuns!) item.id: item,
        });
        await afterWrite?.call('payrollRuns.putAll');
        await payslipsBox!.clear();
        await payslipsBox.putAll({
          for (final item in payload.payslips!) item.id: item,
        });
        await afterWrite?.call('payslips.putAll');
      }
      if (hasFinancePayload) {
        await financeAccountsBox!.clear();
        await financeAccountsBox.putAll({
          for (final item in payload.financeAccounts!) item.id: item,
        });
        await afterWrite?.call('financeAccounts.putAll');
        await financeTransactionsBox!.clear();
        await financeTransactionsBox.putAll({
          for (final item in payload.financeTransactions!) item.id: item,
        });
        await afterWrite?.call('financeTransactions.putAll');
        await financePostingsBox!.clear();
        await financePostingsBox.putAll({
          for (final item in payload.financePostings!) item.id: item,
        });
        await afterWrite?.call('financePostings.putAll');
        await financeCategoriesBox!.clear();
        await financeCategoriesBox.putAll({
          for (final item in payload.financeCategories!) item.id: item,
        });
        await afterWrite?.call('financeCategories.putAll');
        await financePartiesBox!.clear();
        await financePartiesBox.putAll({
          for (final item in payload.financeParties!) item.id: item,
        });
        await afterWrite?.call('financeParties.putAll');
      }
      if (hasBudgetPayload) {
        await financeBudgetsBox!.clear();
        await financeBudgetsBox.putAll({
          for (final item in payload.financeBudgets!) item.id: item,
        });
        await afterWrite?.call('financeBudgets.putAll');
      }
      if (hasRecurringPayload) {
        await financeRecurringTemplatesBox!.clear();
        await financeRecurringTemplatesBox.putAll({
          for (final item in payload.financeRecurringTemplates!) item.id: item,
        });
        await afterWrite?.call('financeRecurringTemplates.putAll');
      }
      if (payload.appSettings != null) {
        await appSettingsBox.putAll(payload.appSettings!);
        await afterWrite?.call('appSettings.putAll');
      }
    } catch (restoreError, stackTrace) {
      try {
        await usersBox.clear();
        await usersBox.putAll(usersSnapshot);
        await productsBox.clear();
        await productsBox.putAll(productsSnapshot);
        await salesBox.clear();
        await salesBox.putAll(salesSnapshot);
        await expensesBox.clear();
        await expensesBox.putAll(expensesSnapshot);
        await employeesBox.clear();
        await employeesBox.putAll(employeesSnapshot);
        if (hrDepartmentsSnapshot != null) {
          await hrDepartmentsBox!.clear();
          await hrDepartmentsBox.putAll(hrDepartmentsSnapshot);
        }
        if (employeeAttendanceSnapshot != null) {
          await employeeAttendanceBox!.clear();
          await employeeAttendanceBox.putAll(employeeAttendanceSnapshot);
        }
        if (leaveRequestsSnapshot != null) {
          await leaveRequestsBox!.clear();
          await leaveRequestsBox.putAll(leaveRequestsSnapshot);
        }
        if (salaryComponentsSnapshot != null) {
          await salaryComponentsBox!.clear();
          await salaryComponentsBox.putAll(salaryComponentsSnapshot);
        }
        if (payrollRunsSnapshot != null) {
          await payrollRunsBox!.clear();
          await payrollRunsBox.putAll(payrollRunsSnapshot);
        }
        if (payslipsSnapshot != null) {
          await payslipsBox!.clear();
          await payslipsBox.putAll(payslipsSnapshot);
        }
        if (financeAccountsSnapshot != null) {
          await financeAccountsBox!.clear();
          await financeAccountsBox.putAll(financeAccountsSnapshot);
        }
        if (financeTransactionsSnapshot != null) {
          await financeTransactionsBox!.clear();
          await financeTransactionsBox.putAll(financeTransactionsSnapshot);
        }
        if (financePostingsSnapshot != null) {
          await financePostingsBox!.clear();
          await financePostingsBox.putAll(financePostingsSnapshot);
        }
        if (financeCategoriesSnapshot != null) {
          await financeCategoriesBox!.clear();
          await financeCategoriesBox.putAll(financeCategoriesSnapshot);
        }
        if (financePartiesSnapshot != null) {
          await financePartiesBox!.clear();
          await financePartiesBox.putAll(financePartiesSnapshot);
        }
        if (financeBudgetsSnapshot != null) {
          await financeBudgetsBox!.clear();
          await financeBudgetsBox.putAll(financeBudgetsSnapshot);
        }
        if (financeRecurringTemplatesSnapshot != null) {
          await financeRecurringTemplatesBox!.clear();
          await financeRecurringTemplatesBox.putAll(financeRecurringTemplatesSnapshot);
        }
        await appSettingsBox.clear();
        await appSettingsBox.putAll(settingsSnapshot);
      } catch (rollbackError) {
        Error.throwWithStackTrace(
          StateError(
            'Restore failed ($restoreError) and rollback also failed '
            '($rollbackError). Data may require recovery from a backup.',
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(restoreError, stackTrace);
    }
  }

  BackupRestorePayload parse(Map<String, dynamic> data) {
    const financeKeys = [
      'financeAccounts',
      'financeTransactions',
      'financePostings',
      'financeCategories',
      'financeParties',
    ];
    final hasAnyFinanceKey = financeKeys.any(data.containsKey);
    if (hasAnyFinanceKey && !financeKeys.every(data.containsKey)) {
      throw const FormatException(
        'Finance backup is incomplete; all finance collections are required.',
      );
    }
    final financeAccounts = hasAnyFinanceKey
        ? _parseRecords(data, 'financeAccounts', _parseFinanceAccount)
        : null;
    final financeTransactions = hasAnyFinanceKey
        ? _parseRecords(data, 'financeTransactions', _parseFinanceTransaction)
        : null;
    final financePostings = hasAnyFinanceKey
        ? _parseRecords(data, 'financePostings', _parseFinancePosting)
        : null;
    final financeCategories = hasAnyFinanceKey
        ? _parseRecords(data, 'financeCategories', _parseFinanceCategory)
        : null;
    final financeParties = hasAnyFinanceKey
        ? _parseRecords(data, 'financeParties', _parseFinanceParty)
        : null;
    if (data.containsKey('financeBudgets') && !hasAnyFinanceKey) {
      throw const FormatException(
        'Finance budgets cannot be restored without finance collections.',
      );
    }
    final financeBudgets = data.containsKey('financeBudgets')
        ? _parseRecords(data, 'financeBudgets', _parseFinanceBudget)
        : null;
    if (data.containsKey('financeRecurringTemplates') && !hasAnyFinanceKey) {
      throw const FormatException(
        'Recurring templates cannot be restored without finance collections.',
      );
    }
    final financeRecurringTemplates =
        data.containsKey('financeRecurringTemplates')
            ? _parseRecords(
                data,
                'financeRecurringTemplates',
                _parseFinanceRecurringTemplate,
              )
            : null;

    const hrKeys = [
      'hrDepartments',
      'employeeAttendance',
      'leaveRequests',
    ];
    final hasAnyHrKey = hrKeys.any(data.containsKey);
    if (hasAnyHrKey && !hrKeys.every(data.containsKey)) {
      throw const FormatException(
        'HR backup is incomplete; all HR collections are required.',
      );
    }
    final hrDepartments = hasAnyHrKey
        ? _parseRecords(data, 'hrDepartments', _parseHrDepartment)
        : null;
    final employeeAttendance = hasAnyHrKey
        ? _parseRecords(data, 'employeeAttendance', _parseEmployeeAttendance)
        : null;
    final leaveRequests = hasAnyHrKey
        ? _parseRecords(data, 'leaveRequests', _parseLeaveRequest)
        : null;

    const payrollKeys = [
      'salaryComponents',
      'payrollRuns',
      'payslips',
    ];
    final hasAnyPayrollKey = payrollKeys.any(data.containsKey);
    if (hasAnyPayrollKey &&
        (!hasAnyHrKey || !payrollKeys.every(data.containsKey))) {
      throw const FormatException(
        'Payroll backup is incomplete; HR and all payroll collections are required.',
      );
    }
    final salaryComponents = hasAnyPayrollKey
        ? _parseRecords(data, 'salaryComponents', _parseSalaryComponent)
        : null;
    final payrollRuns = hasAnyPayrollKey
        ? _parseRecords(data, 'payrollRuns', _parsePayrollRun)
        : null;
    final payslips = hasAnyPayrollKey
        ? _parseRecords(data, 'payslips', _parsePayslip)
        : null;

    final employees = _parseRecords(data, 'employees', _parseEmployee);
    if (hasAnyHrKey) {
      _validateHrCollections(
        employees,
        hrDepartments!,
        employeeAttendance!,
        leaveRequests!,
      );
    }
    if (hasAnyPayrollKey) {
      _validatePayrollCollections(
        employees,
        salaryComponents!,
        payrollRuns!,
        payslips!,
      );
    }
    if (hasAnyFinanceKey) {
      _validateFinanceCollections(
        financeAccounts!,
        financeTransactions!,
        financePostings!,
        financeCategories!,
        financeParties!,
      );
    }
    if (financeBudgets != null) {
      _validateFinanceBudgets(
        financeBudgets,
        financeAccounts!,
        financeCategories!,
      );
    }
    if (financeRecurringTemplates != null) {
      _validateFinanceRecurringTemplates(
        financeRecurringTemplates,
        financeAccounts!,
        financeCategories!,
        financeParties!,
      );
    }

    return BackupRestorePayload(
      users: _parseRecords(data, 'users', _parseUser),
      products: _parseRecords(data, 'products', _parseProduct),
      sales: _parseRecords(data, 'sales', _parseSale),
      expenses: _parseRecords(data, 'expenses', _parseExpense),
      employees: employees,
      financeAccounts: financeAccounts,
      financeTransactions: financeTransactions,
      financePostings: financePostings,
      financeCategories: financeCategories,
      financeParties: financeParties,
      financeBudgets: financeBudgets,
      financeRecurringTemplates: financeRecurringTemplates,
      hrDepartments: hrDepartments,
      employeeAttendance: employeeAttendance,
      leaveRequests: leaveRequests,
      salaryComponents: salaryComponents,
      payrollRuns: payrollRuns,
      payslips: payslips,
      appSettings: _parseSettings(data['appSettings']),
    );
  }

  List<T> _parseRecords<T>(
    Map<String, dynamic> root,
    String key,
    T Function(Map<String, dynamic>) parser,
  ) {
    final raw = root[key];
    if (raw == null) return <T>[];
    if (raw is! List) {
      throw FormatException('Backup field "$key" must be a list.');
    }

    final records = <T>[];
    final ids = <String>{};
    for (var index = 0; index < raw.length; index++) {
      final record = _asMap(raw[index], '$key[$index]');
      final parsed = parser(record);
      final id = _requiredString(record, 'id', '$key[$index]');
      if (!ids.add(id)) {
        throw FormatException('Duplicate id "$id" in backup field "$key".');
      }
      records.add(parsed);
    }
    return records;
  }

  Map<String, dynamic> _asMap(Object? value, String path) {
    if (value is! Map) throw FormatException('$path must be an object.');
    try {
      return Map<String, dynamic>.from(value);
    } on TypeError {
      throw FormatException('$path contains a non-string key.');
    }
  }

  String _requiredString(Map<String, dynamic> map, String key, String path) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$path.$key must be a non-empty string.');
    }
    return value;
  }

  String _optionalString(
    Map<String, dynamic> map,
    String key,
    String fallback,
    String path,
  ) {
    final value = map[key];
    if (value == null) return fallback;
    if (value is! String) throw FormatException('$path.$key must be a string.');
    return value;
  }

  double _number(Map<String, dynamic> map, String key, String path,
      {double? fallback}) {
    final value = map[key];
    if (value == null && fallback != null) return fallback;
    if (value is! num || !value.toDouble().isFinite) {
      throw FormatException('$path.$key must be a finite number.');
    }
    return value.toDouble();
  }

  double? _optionalNumber(
      Map<String, dynamic> map, String key, String path) {
    if (map[key] == null) return null;
    return _number(map, key, path);
  }

  String? _nullableString(
      Map<String, dynamic> map, String key, String path) {
    final value = map[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('$path.$key must be a string or null.');
    }
    return value;
  }

  bool _boolean(Map<String, dynamic> map, String key, String path,
      {bool fallback = false}) {
    final value = map[key];
    if (value == null) return fallback;
    if (value is! bool) throw FormatException('$path.$key must be a boolean.');
    return value;
  }

  DateTime _date(Map<String, dynamic> map, String key, String path) {
    final value = _requiredString(map, key, path);
    try {
      return DateTime.parse(value);
    } on FormatException {
      throw FormatException('$path.$key is not a valid date.');
    }
  }

  User _parseUser(Map<String, dynamic> json) {
    const path = 'users';
    final userType = json['userType'];
    if (userType is! String) {
      throw const FormatException('users.userType must be a string.');
    }
    return User()
      ..id = _requiredString(json, 'id', path)
      ..username = _requiredString(json, 'username', path)
      ..password = _requiredString(json, 'password', path)
      ..userType = userType == 'admin' ? UserType.admin : UserType.worker;
  }

  Product _parseProduct(Map<String, dynamic> json) {
    const path = 'products';
    final unitName = _optionalString(json, 'unit', 'pcs', path);
    return Product()
      ..id = _requiredString(json, 'id', path)
      ..name = _requiredString(json, 'name', path)
      ..sellingPrice = _number(json, 'sellingPrice', path)
      ..costPrice = _number(json, 'costPrice', path)
      ..stock = _number(json, 'stock', path)
      ..unit = UnitType.values.firstWhere(
        (unit) => unit.name == unitName,
        orElse: () => UnitType.pcs,
      )
      ..category = _optionalString(json, 'category', 'General', path)
      ..subCategory = _optionalString(json, 'subCategory', '', path)
      ..active = _boolean(json, 'active', path, fallback: true)
      ..barcode = _nullableString(json, 'barcode', path)
      ..hsnCode = _optionalString(json, 'hsnCode', '', path)
      ..gstRate = _optionalNumber(json, 'gstRate', path);
  }

  SaleItem _parseSaleItem(Map<String, dynamic> json, String path) {
    return SaleItem()
      ..productId = _requiredString(json, 'productId', path)
      ..qty = _number(json, 'qty', path)
      ..sellingPrice = _number(json, 'sellingPrice', path)
      ..costPrice = _number(json, 'costPrice', path)
      ..subtotal = _number(json, 'subtotal', path)
      ..unitLabel = _optionalString(json, 'unitLabel', 'pcs', path)
      ..hsnCode = _optionalString(json, 'hsnCode', '', path)
      ..gstRate = _optionalNumber(json, 'gstRate', path)
      ..taxableAmount = _number(json, 'taxableAmount', path, fallback: 0)
      ..cgstAmount = _number(json, 'cgstAmount', path, fallback: 0)
      ..sgstAmount = _number(json, 'sgstAmount', path, fallback: 0)
      ..igstAmount = _number(json, 'igstAmount', path, fallback: 0);
  }

  Sale _parseSale(Map<String, dynamic> json) {
    const path = 'sales';
    final rawItems = json['items'];
    if (rawItems != null && rawItems is! List) {
      throw FormatException('$path.items must be a list.');
    }
    final items = (rawItems as List? ?? const [])
        .asMap()
        .entries
        .map((entry) => _parseSaleItem(
              _asMap(entry.value, '$path.items[${entry.key}]'),
              '$path.items[${entry.key}]',
            ))
        .toList();
    final payment = json['payment'];
    if (payment is! String) {
      throw const FormatException('sales.payment must be a string.');
    }

    return Sale()
      ..id = _requiredString(json, 'id', path)
      ..date = _date(json, 'date', path)
      ..items = items
      ..totalAmount = _number(json, 'totalAmount', path)
      ..totalCost = _number(json, 'totalCost', path)
      ..profit = _number(json, 'profit', path)
      ..payment = switch (payment) {
        'card' => PaymentMethod.card,
        'upi' => PaymentMethod.upi,
        _ => PaymentMethod.cash,
      }
      ..customerName = _optionalString(json, 'customerName', '', path)
      ..customerPhone = _optionalString(json, 'customerPhone', '', path)
      ..userId = _optionalString(json, 'userId', '', path)
      ..discount = _number(json, 'discount', path, fallback: 0)
      ..gstEnabled = _boolean(json, 'gstEnabled', path)
      ..gstRate = _number(json, 'gstRate', path, fallback: 0)
      ..taxableAmount = _number(json, 'taxableAmount', path, fallback: 0)
      ..cgstAmount = _number(json, 'cgstAmount', path, fallback: 0)
      ..sgstAmount = _number(json, 'sgstAmount', path, fallback: 0)
      ..igstAmount = _number(json, 'igstAmount', path, fallback: 0)
      ..customerGstin = _optionalString(json, 'customerGstin', '', path)
      ..interstateSale = _boolean(json, 'interstateSale', path)
      ..gstInclusive = _boolean(json, 'gstInclusive', path)
      ..financeRevision = _integer(json, 'financeRevision', path, fallback: 0);
  }

  Expense _parseExpense(Map<String, dynamic> json) {
    const path = 'expenses';
    final employeeId = json['employeeId'];
    if (employeeId != null && employeeId is! String) {
      throw const FormatException('expenses.employeeId must be a string.');
    }
    return Expense(
      id: _requiredString(json, 'id', path),
      date: _date(json, 'date', path),
      category: _requiredString(json, 'category', path),
      amount: _number(json, 'amount', path),
      description: _optionalString(json, 'description', '', path),
      employeeId: employeeId as String?,
      financeRevision: _integer(json, 'financeRevision', path, fallback: 0),
    );
  }

  Employee _parseEmployee(Map<String, dynamic> json) {
    const path = 'employees';
    final attendance = json['attendance'];
    if (attendance != null && attendance is! num) {
      throw const FormatException('employees.attendance must be numeric.');
    }
    final attendanceValue = (attendance as num?)?.toDouble() ?? 0;
    if (!attendanceValue.isFinite || attendanceValue % 1 != 0) {
      throw const FormatException('employees.attendance must be a finite integer.');
    }
    final employmentStatus =
        _optionalString(json, 'employmentStatus', 'active', path);
    if (!{'active', 'inactive', 'on_leave', 'terminated'}
        .contains(employmentStatus)) {
      throw const FormatException('employees.employmentStatus is unsupported.');
    }
    return Employee(
      id: _requiredString(json, 'id', path),
      name: _requiredString(json, 'name', path),
      type: _requiredString(json, 'type', path),
      wage: _number(json, 'wage', path),
      attendance: attendanceValue.toInt(),
      salaryPaid: _boolean(json, 'salaryPaid', path),
      employeeCode: _optionalString(json, 'employeeCode', '', path),
      phone: _optionalString(json, 'phone', '', path),
      email: _optionalString(json, 'email', '', path),
      departmentId: _nullableString(json, 'departmentId', path),
      designation: _optionalString(json, 'designation', '', path),
      joiningDate: json['joiningDate'] == null
          ? null
          : _date(json, 'joiningDate', path),
      employmentStatus: employmentStatus,
      emergencyContact: _optionalString(json, 'emergencyContact', '', path),
      address: _optionalString(json, 'address', '', path),
      notes: _optionalString(json, 'notes', '', path),
    );
  }

  HrDepartment _parseHrDepartment(Map<String, dynamic> json) {
    const path = 'hrDepartments';
    return HrDepartment(
      id: _requiredString(json, 'id', path),
      name: _requiredString(json, 'name', path),
      description: _optionalString(json, 'description', '', path),
      active: _boolean(json, 'active', path, fallback: true),
      createdAt: json['createdAt'] == null
          ? DateTime.now()
          : _date(json, 'createdAt', path),
    );
  }

  EmployeeAttendance _parseEmployeeAttendance(
      Map<String, dynamic> json) {
    const path = 'employeeAttendance';
    final status = _requiredString(json, 'status', path);
    if (!{'present', 'absent', 'half_day', 'leave', 'holiday'}
        .contains(status)) {
      throw FormatException('$path.status is unsupported.');
    }
    final checkIn = json['checkIn'] == null
        ? null
        : _date(json, 'checkIn', path);
    final checkOut = json['checkOut'] == null
        ? null
        : _date(json, 'checkOut', path);
    if (checkIn != null && checkOut != null && checkOut.isBefore(checkIn)) {
      throw FormatException('$path.checkOut cannot be before checkIn.');
    }
    return EmployeeAttendance(
      id: _requiredString(json, 'id', path),
      employeeId: _requiredString(json, 'employeeId', path),
      date: _date(json, 'date', path),
      status: status,
      checkIn: checkIn,
      checkOut: checkOut,
      notes: _optionalString(json, 'notes', '', path),
      updatedAt: json['updatedAt'] == null
          ? DateTime.now()
          : _date(json, 'updatedAt', path),
    );
  }

  LeaveRequest _parseLeaveRequest(Map<String, dynamic> json) {
    const path = 'leaveRequests';
    final leaveType = _requiredString(json, 'leaveType', path);
    if (!{'casual', 'sick', 'earned', 'unpaid', 'other'}
        .contains(leaveType)) {
      throw FormatException('$path.leaveType is unsupported.');
    }
    final status = _optionalString(json, 'status', 'pending', path);
    if (!{'pending', 'approved', 'rejected', 'cancelled'}.contains(status)) {
      throw FormatException('$path.status is unsupported.');
    }
    final startDate = _date(json, 'startDate', path);
    final endDate = _date(json, 'endDate', path);
    if (endDate.isBefore(startDate)) {
      throw FormatException('$path.endDate cannot be before startDate.');
    }
    return LeaveRequest(
      id: _requiredString(json, 'id', path),
      employeeId: _requiredString(json, 'employeeId', path),
      leaveType: leaveType,
      startDate: startDate,
      endDate: endDate,
      reason: _optionalString(json, 'reason', '', path),
      status: status,
      reviewedBy: _optionalString(json, 'reviewedBy', '', path),
      reviewedAt: json['reviewedAt'] == null
          ? null
          : _date(json, 'reviewedAt', path),
      createdAt: json['createdAt'] == null
          ? DateTime.now()
          : _date(json, 'createdAt', path),
    );
  }

  SalaryComponent _parseSalaryComponent(Map<String, dynamic> json) {
    const path = 'salaryComponents';
    final componentType = _requiredString(json, 'componentType', path);
    if (componentType != 'earning' && componentType != 'deduction') {
      throw const FormatException(
        'salaryComponents.componentType must be earning or deduction.',
      );
    }
    final amountPaise = _integer(json, 'amountPaise', path);
    if (amountPaise <= 0) {
      throw const FormatException('salaryComponents.amountPaise must be positive.');
    }
    final effectiveFrom = _date(json, 'effectiveFrom', path);
    final effectiveTo = json['effectiveTo'] == null
        ? null
        : _date(json, 'effectiveTo', path);
    if (effectiveTo != null && effectiveTo.isBefore(effectiveFrom)) {
      throw const FormatException(
        'salaryComponents.effectiveTo cannot be before effectiveFrom.',
      );
    }
    return SalaryComponent(
      id: _requiredString(json, 'id', path),
      employeeId: _requiredString(json, 'employeeId', path),
      name: _requiredString(json, 'name', path),
      componentType: componentType,
      amountPaise: amountPaise,
      effectiveFrom: effectiveFrom,
      effectiveTo: effectiveTo,
      active: _boolean(json, 'active', path, fallback: true),
    );
  }

  PayrollRun _parsePayrollRun(Map<String, dynamic> json) {
    const path = 'payrollRuns';
    final status = _optionalString(json, 'status', 'draft', path);
    if (!{'draft', 'approved', 'paid'}.contains(status)) {
      throw FormatException('$path.status is unsupported.');
    }
    final periodStart = _date(json, 'periodStart', path);
    final periodEnd = _date(json, 'periodEnd', path);
    if (periodEnd.isBefore(periodStart)) {
      throw FormatException('$path.periodEnd cannot be before periodStart.');
    }
    return PayrollRun(
      id: _requiredString(json, 'id', path),
      periodStart: periodStart,
      periodEnd: periodEnd,
      status: status,
      createdAt: json['createdAt'] == null
          ? DateTime.now()
          : _date(json, 'createdAt', path),
      approvedAt: json['approvedAt'] == null
          ? null
          : _date(json, 'approvedAt', path),
      paidAt: json['paidAt'] == null ? null : _date(json, 'paidAt', path),
      totalGrossPaise: _integer(json, 'totalGrossPaise', path, fallback: 0),
      totalDeductionsPaise:
          _integer(json, 'totalDeductionsPaise', path, fallback: 0),
      totalNetPaise: _integer(json, 'totalNetPaise', path, fallback: 0),
      memo: _optionalString(json, 'memo', '', path),
    );
  }

  Payslip _parsePayslip(Map<String, dynamic> json) {
    const path = 'payslips';
    final status = _optionalString(json, 'status', 'draft', path);
    if (!{'draft', 'approved', 'partially_paid', 'paid'}.contains(status)) {
      throw FormatException('$path.status is unsupported.');
    }
    final payableDays = _number(json, 'payableDays', path);
    if (payableDays < 0) {
      throw const FormatException('payslips.payableDays cannot be negative.');
    }
    return Payslip(
      id: _requiredString(json, 'id', path),
      payrollRunId: _requiredString(json, 'payrollRunId', path),
      employeeId: _requiredString(json, 'employeeId', path),
      payType: _requiredString(json, 'payType', path),
      basePaise: _integer(json, 'basePaise', path, fallback: 0),
      allowancesPaise: _integer(json, 'allowancesPaise', path, fallback: 0),
      deductionsPaise: _integer(json, 'deductionsPaise', path, fallback: 0),
      payableDays: payableDays,
      paidPaise: _integer(json, 'paidPaise', path, fallback: 0),
      status: status,
      generatedAt: json['generatedAt'] == null
          ? DateTime.now()
          : _date(json, 'generatedAt', path),
      paidAt: json['paidAt'] == null ? null : _date(json, 'paidAt', path),
    );
  }

  void _validatePayrollCollections(
    List<Employee> employees,
    List<SalaryComponent> components,
    List<PayrollRun> runs,
    List<Payslip> payslips,
  ) {
    final employeeIds = employees.map((item) => item.id).toSet();
    final runById = {for (final run in runs) run.id: run};
    for (final component in components) {
      if (!employeeIds.contains(component.employeeId)) {
        throw FormatException(
          'salaryComponents.${component.id} references an unknown employee.',
        );
      }
    }

    final runPeriods = <String>{};
    for (final run in runs) {
      final key = '${run.periodStart.year}-${run.periodStart.month}-'
          '${run.periodEnd.year}-${run.periodEnd.month}';
      if (!runPeriods.add(key)) {
        throw const FormatException('Payroll backup contains duplicate payroll periods.');
      }
      if (run.totalGrossPaise < 0 ||
          run.totalDeductionsPaise < 0 ||
          run.totalNetPaise < 0) {
        throw FormatException('payrollRuns.${run.id} contains negative totals.');
      }
    }

    final payslipKeys = <String>{};
    final totals = <String, List<int>>{};
    for (final payslip in payslips) {
      if (!employeeIds.contains(payslip.employeeId)) {
        throw FormatException(
          'payslips.${payslip.id} references an unknown employee.',
        );
      }
      if (!runById.containsKey(payslip.payrollRunId)) {
        throw FormatException(
          'payslips.${payslip.id} references an unknown payroll run.',
        );
      }
      if (payslip.basePaise < 0 ||
          payslip.allowancesPaise < 0 ||
          payslip.deductionsPaise < 0 ||
          payslip.paidPaise < 0 ||
          payslip.netPaise < 0 ||
          payslip.paidPaise > payslip.netPaise) {
        throw FormatException('payslips.${payslip.id} contains invalid amounts.');
      }
      final key = '${payslip.payrollRunId}:${payslip.employeeId}';
      if (!payslipKeys.add(key)) {
        throw const FormatException(
          'Payroll backup contains duplicate payslips for an employee and run.',
        );
      }
      final aggregate = totals.putIfAbsent(
        payslip.payrollRunId,
        () => [0, 0, 0],
      );
      aggregate[0] += payslip.grossPaise;
      aggregate[1] += payslip.deductionsPaise;
      aggregate[2] += payslip.netPaise;
      if (payslip.status == 'paid' && payslip.paidPaise != payslip.netPaise) {
        throw FormatException('payslips.${payslip.id} is marked paid with an outstanding balance.');
      }
    }

    for (final run in runs) {
      final aggregate = totals[run.id] ?? [0, 0, 0];
      if (run.totalGrossPaise != aggregate[0] ||
          run.totalDeductionsPaise != aggregate[1] ||
          run.totalNetPaise != aggregate[2]) {
        throw FormatException(
          'payrollRuns.${run.id} totals do not match its payslips.',
        );
      }
      if (run.status == 'paid' &&
          payslips
              .where((item) => item.payrollRunId == run.id)
              .any((item) => item.status != 'paid')) {
        throw FormatException(
          'payrollRuns.${run.id} is paid but contains unpaid payslips.',
        );
      }
    }
  }

  void _validateHrCollections(
    List<Employee> employees,
    List<HrDepartment> departments,
    List<EmployeeAttendance> attendance,
    List<LeaveRequest> leaveRequests,
  ) {
    final employeeIds = employees.map((item) => item.id).toSet();
    final departmentIds = departments.map((item) => item.id).toSet();
    final employeeCodes = <String>{};
    for (final employee in employees) {
      if (employee.departmentId != null &&
          !departmentIds.contains(employee.departmentId)) {
        throw FormatException(
          'employees.${employee.id} references an unknown department.',
        );
      }
      if (employee.employeeCode.isNotEmpty &&
          !employeeCodes.add(employee.employeeCode.toLowerCase())) {
        throw const FormatException('HR backup contains duplicate employee codes.');
      }
    }

    final attendanceKeys = <String>{};
    for (final record in attendance) {
      if (!employeeIds.contains(record.employeeId)) {
        throw FormatException(
          'employeeAttendance.${record.id} references an unknown employee.',
        );
      }
      final key = '${record.employeeId}:${record.date.year}-'
          '${record.date.month}-${record.date.day}';
      if (!attendanceKeys.add(key)) {
        throw const FormatException(
          'HR backup contains duplicate attendance records for an employee and date.',
        );
      }
    }
    for (final request in leaveRequests) {
      if (!employeeIds.contains(request.employeeId)) {
        throw FormatException(
          'leaveRequests.${request.id} references an unknown employee.',
        );
      }
    }
  }

  void _validateFinanceRecurringTemplates(
    List<FinanceRecurringTemplate> templates,
    List<FinanceAccount> accounts,
    List<FinanceCategory> categories,
    List<FinanceParty> parties,
  ) {
    final accountsById = {for (final item in accounts) item.id: item};
    final categoriesById = {for (final item in categories) item.id: item};
    final partiesById = {for (final item in parties) item.id: item};
    for (final template in templates) {
      final debit = accountsById[template.debitAccountId];
      final credit = accountsById[template.creditAccountId];
      if (template.name.trim().isEmpty ||
          template.amountPaise <= 0 ||
          !{'daily', 'weekly', 'monthly', 'quarterly', 'yearly'}
              .contains(template.interval) ||
          (template.endDate != null &&
              template.endDate!.isBefore(template.nextDueDate))) {
        throw FormatException(
          'financeRecurringTemplates.${template.id} contains invalid schedule details.',
        );
      }
      final validAccounts = switch (template.transactionType) {
        'income' =>
          debit?.accountType == 'asset' && credit?.accountType == 'income',
        'expense' =>
          debit?.accountType == 'expense' && credit?.accountType == 'asset',
        'transfer' =>
          debit?.accountType == 'asset' && credit?.accountType == 'asset',
        _ => false,
      };
      if (!validAccounts ||
          debit?.currencyCode != 'INR' ||
          credit?.currencyCode != 'INR') {
        throw FormatException(
          'financeRecurringTemplates.${template.id} references incompatible INR accounts.',
        );
      }
      if (template.categoryId != null) {
        final category = categoriesById[template.categoryId];
        final expectedAccountId = template.transactionType == 'income'
            ? template.creditAccountId
            : template.debitAccountId;
        if (template.transactionType == 'transfer' ||
            category == null ||
            category.kind != template.transactionType ||
            category.accountId != expectedAccountId) {
          throw FormatException(
            'financeRecurringTemplates.${template.id} references an incompatible category.',
          );
        }
      }
      final requiresParty =
          (template.transactionType == 'income' &&
              template.debitAccountId == 'system:receivables') ||
          (template.transactionType == 'expense' &&
              template.creditAccountId == 'system:payables');
      if (requiresParty && template.partyId == null) {
        throw FormatException(
          'financeRecurringTemplates.${template.id} requires a customer or supplier party.',
        );
      }
      if (template.partyId != null) {
        final party = partiesById[template.partyId];
        final expectedPartyType =
            template.transactionType == 'income' ? 'customer' : 'supplier';
        if (party == null || party.partyType != expectedPartyType) {
          throw FormatException(
            'financeRecurringTemplates.${template.id} references an invalid party.',
          );
        }
      }
    }
  }

  void _validateFinanceBudgets(
    List<FinanceBudget> budgets,
    List<FinanceAccount> accounts,
    List<FinanceCategory> categories,
  ) {
    final accountsById = {for (final item in accounts) item.id: item};
    final categoriesById = {for (final item in categories) item.id: item};
    for (final budget in budgets) {
      final account = accountsById[budget.accountId];
      if (account == null ||
          account.accountType != 'expense' ||
          account.currencyCode != 'INR') {
        throw FormatException(
          'financeBudgets.${budget.id} must reference an INR expense account.',
        );
      }
      if (budget.name.trim().isEmpty ||
          budget.budgetPaise <= 0 ||
          budget.periodEnd.isBefore(budget.periodStart)) {
        throw FormatException(
          'financeBudgets.${budget.id} contains invalid budget details.',
        );
      }
      if (budget.categoryId != null) {
        final category = categoriesById[budget.categoryId];
        if (category == null ||
            category.kind != 'expense' ||
            category.accountId != budget.accountId) {
          throw FormatException(
            'financeBudgets.${budget.id} references an incompatible expense category.',
          );
        }
      }
    }
  }

  void _validateFinanceCollections(
    List<FinanceAccount> accounts,
    List<FinanceTransaction> transactions,
    List<FinancePosting> postings,
    List<FinanceCategory> categories,
    List<FinanceParty> parties,
  ) {
    final accountIds = accounts.map((item) => item.id).toSet();
    final accountsById = {for (final item in accounts) item.id: item};
    final transactionById = {
      for (final item in transactions) item.id: item,
    };
    final transactionNumbers = <String>{};
    final sourceKeys = <String>{};
    for (final account in accounts) {
      if (account.parentId != null) {
        final parent = accountsById[account.parentId];
        if (parent == null) {
          throw FormatException(
            'financeAccounts.${account.id} references an unknown parent account.',
          );
        }
        if (parent.accountType != account.accountType) {
          throw FormatException(
            'financeAccounts.${account.id} has a parent with a different account type.',
          );
        }
      }
      final ancestors = <String>{account.id};
      var parentId = account.parentId;
      while (parentId != null) {
        if (!ancestors.add(parentId)) {
          throw FormatException(
            'financeAccounts.${account.id} belongs to a circular account hierarchy.',
          );
        }
        parentId = accountsById[parentId]?.parentId;
      }
    }

    for (final transaction in transactions) {
      if (transaction.reversedTransactionId != null &&
          !transactionById.containsKey(transaction.reversedTransactionId)) {
        throw FormatException(
          'financeTransactions.${transaction.id} references an unknown reversal target.',
        );
      }
      if (!transactionNumbers.add(transaction.transactionNumber)) {
        throw const FormatException(
          'Finance backup contains duplicate transaction numbers.',
        );
      }
      if (transaction.sourceType.isNotEmpty && transaction.sourceId.isNotEmpty) {
        final sourceKey = '${transaction.sourceType}:${transaction.sourceId}';
        if (!sourceKeys.add(sourceKey)) {
          throw const FormatException(
            'Finance backup contains duplicate source references.',
          );
        }
      }
    }
    final categoryIds = categories.map((item) => item.id).toSet();
    final partiesById = {for (final item in parties) item.id: item};
    final partyIds = partiesById.keys.toSet();
    final postingsByTransaction = <String, List<FinancePosting>>{};

    for (final category in categories) {
      final categoryAccount = accountsById[category.accountId];
      if (categoryAccount == null) {
        throw FormatException(
          'financeCategories.${category.id} references an unknown account.',
        );
      }
      if (category.kind != categoryAccount.accountType) {
        throw FormatException(
          'financeCategories.${category.id} kind does not match its account type.',
        );
      }
    }

    for (final line in postings) {
      if (!transactionById.containsKey(line.transactionId)) {
        throw FormatException(
          'financePostings.${line.id} references an unknown transaction.',
        );
      }
      if (!accountIds.contains(line.accountId)) {
        throw FormatException(
          'financePostings.${line.id} references an unknown account.',
        );
      }
      if (line.partyId != null && !partyIds.contains(line.partyId)) {
        throw FormatException(
          'financePostings.${line.id} references an unknown party.',
        );
      }
      final requiresCustomer = line.accountId == 'system:receivables';
      final requiresSupplier = line.accountId == 'system:payables';
      if ((requiresCustomer || requiresSupplier) && line.partyId == null) {
        throw FormatException(
          'financePostings.${line.id} requires a customer or supplier party.',
        );
      }
      if (line.partyId != null) {
        final party = partiesById[line.partyId]!;
        if (requiresCustomer && party.partyType != 'customer') {
          throw FormatException(
            'financePostings.${line.id} requires a customer party.',
          );
        }
        if (requiresSupplier && party.partyType != 'supplier') {
          throw FormatException(
            'financePostings.${line.id} requires a supplier party.',
          );
        }
      }
      if (line.categoryId != null && !categoryIds.contains(line.categoryId)) {
        throw FormatException(
          'financePostings.${line.id} references an unknown category.',
        );
      }
      final debit = line.debitPaise;
      final credit = line.creditPaise;
      if (debit < 0 || credit < 0 || (debit == 0) == (credit == 0)) {
        throw FormatException(
          'financePostings.${line.id} must contain one positive debit or credit.',
        );
      }
      postingsByTransaction
          .putIfAbsent(line.transactionId, () => <FinancePosting>[])
          .add(line);
    }

    for (final transaction in transactions) {
      if (transaction.status != 'posted') continue;
      final lines = postingsByTransaction[transaction.id] ?? const [];
      if (lines.length < 2) {
        throw FormatException(
          'Posted finance transaction ${transaction.id} requires at least two lines.',
        );
      }
      final debits = lines.fold<int>(0, (sum, line) => sum + line.debitPaise);
      final credits =
          lines.fold<int>(0, (sum, line) => sum + line.creditPaise);
      if (debits <= 0 || debits != credits) {
        throw FormatException(
          'Posted finance transaction ${transaction.id} is not balanced.',
        );
      }
    }
  }

  int _integer(Map<String, dynamic> map, String key, String path,
      {int? fallback}) {
    final value = map[key];
    if (value == null && fallback != null) return fallback;
    if (value is! int) throw FormatException('$path.$key must be an integer.');
    return value;
  }

  FinanceAccount _parseFinanceAccount(Map<String, dynamic> json) {
    const path = 'financeAccounts';
    final type = _requiredString(json, 'accountType', path);
    if (!{'asset', 'liability', 'equity', 'income', 'expense'}.contains(type)) {
      throw FormatException('$path.accountType is unsupported.');
    }
    final currencyCode = _optionalString(json, 'currencyCode', 'INR', path);
    if (currencyCode != 'INR') {
      throw FormatException('$path.currencyCode must be INR in this release.');
    }
    return FinanceAccount(
      id: _requiredString(json, 'id', path),
      name: _requiredString(json, 'name', path),
      accountType: type,
      parentId: _nullableString(json, 'parentId', path),
      currencyCode: currencyCode,
      active: _boolean(json, 'active', path, fallback: true),
      createdAt: json['createdAt'] == null
          ? DateTime.now()
          : _date(json, 'createdAt', path),
    );
  }

  FinanceTransaction _parseFinanceTransaction(Map<String, dynamic> json) {
    const path = 'financeTransactions';
    final type = _requiredString(json, 'transactionType', path);
    if (!{'income', 'expense', 'transfer', 'customer_receipt', 'supplier_payment', 'opening_balance', 'adjustment', 'reversal'}.contains(type)) {
      throw FormatException('$path.transactionType is unsupported.');
    }
    final status = _optionalString(json, 'status', 'draft', path);
    if (!{'draft', 'posted', 'reversed'}.contains(status)) {
      throw FormatException('$path.status is unsupported.');
    }
    return FinanceTransaction(
      id: _requiredString(json, 'id', path),
      transactionNumber: _requiredString(json, 'transactionNumber', path),
      transactionType: type,
      status: status,
      date: _date(json, 'date', path),
      memo: _optionalString(json, 'memo', '', path),
      reference: _optionalString(json, 'reference', '', path),
      sourceType: _optionalString(json, 'sourceType', '', path),
      sourceId: _optionalString(json, 'sourceId', '', path),
      createdAt: json['createdAt'] == null
          ? DateTime.now()
          : _date(json, 'createdAt', path),
      postedAt: json['postedAt'] == null ? null : _date(json, 'postedAt', path),
      reversedTransactionId:
          _nullableString(json, 'reversedTransactionId', path),
    );
  }

  FinancePosting _parseFinancePosting(Map<String, dynamic> json) {
    const path = 'financePostings';
    return FinancePosting(
      id: _requiredString(json, 'id', path),
      transactionId: _requiredString(json, 'transactionId', path),
      accountId: _requiredString(json, 'accountId', path),
      debitPaise: _integer(json, 'debitPaise', path, fallback: 0),
      creditPaise: _integer(json, 'creditPaise', path, fallback: 0),
      partyId: _nullableString(json, 'partyId', path),
      categoryId: _nullableString(json, 'categoryId', path),
      memo: _optionalString(json, 'memo', '', path),
    );
  }

  FinanceCategory _parseFinanceCategory(Map<String, dynamic> json) {
    const path = 'financeCategories';
    final kind = _requiredString(json, 'kind', path);
    if (!{'income', 'expense'}.contains(kind)) {
      throw FormatException('$path.kind is unsupported.');
    }
    return FinanceCategory(
      id: _requiredString(json, 'id', path),
      name: _requiredString(json, 'name', path),
      kind: kind,
      accountId: _requiredString(json, 'accountId', path),
      active: _boolean(json, 'active', path, fallback: true),
    );
  }

  FinanceParty _parseFinanceParty(Map<String, dynamic> json) {
    const path = 'financeParties';
    final type = _requiredString(json, 'partyType', path);
    if (!{'customer', 'supplier', 'employee', 'other'}.contains(type)) {
      throw FormatException('$path.partyType is unsupported.');
    }
    return FinanceParty(
      id: _requiredString(json, 'id', path),
      name: _requiredString(json, 'name', path),
      partyType: type,
      phone: _optionalString(json, 'phone', '', path),
      email: _optionalString(json, 'email', '', path),
      taxIdentifier: _optionalString(json, 'taxIdentifier', '', path),
      active: _boolean(json, 'active', path, fallback: true),
    );
  }

  FinanceRecurringTemplate _parseFinanceRecurringTemplate(
    Map<String, dynamic> json,
  ) {
    const path = 'financeRecurringTemplates';
    final type = _requiredString(json, 'transactionType', path);
    if (!{'income', 'expense', 'transfer'}.contains(type)) {
      throw FormatException('$path.transactionType is unsupported.');
    }
    return FinanceRecurringTemplate(
      id: _requiredString(json, 'id', path),
      name: _requiredString(json, 'name', path),
      transactionType: type,
      debitAccountId: _requiredString(json, 'debitAccountId', path),
      creditAccountId: _requiredString(json, 'creditAccountId', path),
      amountPaise: _integer(json, 'amountPaise', path),
      interval: _requiredString(json, 'interval', path),
      nextDueDate: _date(json, 'nextDueDate', path),
      endDate: json['endDate'] == null ? null : _date(json, 'endDate', path),
      categoryId: _nullableString(json, 'categoryId', path),
      partyId: _nullableString(json, 'partyId', path),
      memo: _optionalString(json, 'memo', '', path),
      active: _boolean(json, 'active', path, fallback: true),
      createdAt: json['createdAt'] == null
          ? DateTime.now()
          : _date(json, 'createdAt', path),
    );
  }

  FinanceBudget _parseFinanceBudget(Map<String, dynamic> json) {
    const path = 'financeBudgets';
    return FinanceBudget(
      id: _requiredString(json, 'id', path),
      name: _requiredString(json, 'name', path),
      accountId: _requiredString(json, 'accountId', path),
      categoryId: _nullableString(json, 'categoryId', path),
      periodStart: _date(json, 'periodStart', path),
      periodEnd: _date(json, 'periodEnd', path),
      budgetPaise: _integer(json, 'budgetPaise', path),
      active: _boolean(json, 'active', path, fallback: true),
      notes: _optionalString(json, 'notes', '', path),
      createdAt: json['createdAt'] == null
          ? DateTime.now()
          : _date(json, 'createdAt', path),
    );
  }

  Map<String, dynamic>? _parseSettings(Object? value) {
    if (value == null) return null;
    return _asMap(value, 'appSettings');
  }
}
