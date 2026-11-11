import 'dart:io';

import 'package:billit/models/models.dart';
import 'package:billit/services/boxes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

void main() {
  late Directory directory;

  final adapters = <TypeAdapter>[
    UserTypeAdapter(),
    UserAdapter(),
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
    FinanceBudgetAdapter(),
    FinanceRecurringTemplateAdapter(),
  ];

  Future<void> initializeHive() async {
    Hive.init(directory.path);
    for (final adapter in adapters) {
      if (!Hive.isAdapterRegistered(adapter.typeId)) {
        Hive.registerAdapter(adapter);
      }
    }
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('billit_hive_ce');
    await initializeHive();
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('all persisted Type IDs remain unique and stable from 1 through 20',
      () {
    final ids = adapters.map((adapter) => adapter.typeId).toList()..sort();
    expect(ids, List<int>.generate(22, (index) => index + 1));
  });

  test('legacy and finance/HR typed boxes survive close and reopen', () async {
    final sales = await Hive.openBox<Sale>(Boxes.sales);
    final expenses = await Hive.openBox<Expense>(Boxes.expenses);
    final employees = await Hive.openBox<Employee>(Boxes.employees);
    final accounts =
        await Hive.openBox<FinanceAccount>(Boxes.financeAccounts);
    final transactions =
        await Hive.openBox<FinanceTransaction>(Boxes.financeTransactions);
    final postings = await Hive.openBox<FinancePosting>(Boxes.financePostings);
    final departments =
        await Hive.openBox<HrDepartment>(Boxes.hrDepartments);
    final attendance =
        await Hive.openBox<EmployeeAttendance>(Boxes.employeeAttendance);
    final budgets =
        await Hive.openBox<FinanceBudget>(Boxes.financeBudgets);
    final recurring =
        await Hive.openBox<FinanceRecurringTemplate>(Boxes.financeRecurringTemplates);

    final sale = Sale()
      ..id = 'legacy-sale-1'
      ..date = DateTime(2026, 11, 1)
      ..items = []
      ..totalAmount = 118;
    final expense = Expense(
      id: 'legacy-expense-1',
      date: DateTime(2026, 11, 2),
      category: 'Rent',
      amount: 125.50,
      description: 'Shop rent',
    );
    final employee = Employee(
      id: 'legacy-employee-1',
      name: 'Anu',
      type: 'daily',
      wage: 900,
    );
    final account = FinanceAccount(
      id: 'system:cash',
      name: 'Cash',
      accountType: 'asset',
    );
    final transaction = FinanceTransaction(
      id: 'txn-1',
      transactionNumber: 'TXN-1',
      transactionType: 'expense',
      status: 'posted',
    );
    final posting = FinancePosting(
      id: 'posting-1',
      transactionId: transaction.id,
      accountId: account.id,
      debitPaise: 12550,
    );
    final department = HrDepartment(id: 'dept-1', name: 'Sales');
    final attendanceRecord = EmployeeAttendance(
      id: 'attendance-1',
      employeeId: employee.id,
      date: DateTime(2026, 11, 3),
      status: 'present',
    );
    final budget = FinanceBudget(
      id: 'budget-1',
      name: 'Rent',
      accountId: account.id,
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 11, 30),
      budgetPaise: 100000,
    );
    final recurringTemplate = FinanceRecurringTemplate(
      id: 'recurring-1',
      name: 'Monthly rent',
      transactionType: 'expense',
      debitAccountId: 'system:operating-expense',
      creditAccountId: 'system:cash',
      amountPaise: 100000,
      interval: 'monthly',
      nextDueDate: DateTime(2026, 12, 1),
    );

    await sales.put(sale.id, sale);
    await expenses.put(expense.id, expense);
    await employees.put(employee.id, employee);
    await accounts.put(account.id, account);
    await transactions.put(transaction.id, transaction);
    await postings.put(posting.id, posting);
    await departments.put(department.id, department);
    await attendance.put(attendanceRecord.id, attendanceRecord);
    await budgets.put(budget.id, budget);
    await recurring.put(recurringTemplate.id, recurringTemplate);
    await Hive.close();

    await initializeHive();
    final reopenedSales = await Hive.openBox<Sale>(Boxes.sales);
    final reopenedExpenses = await Hive.openBox<Expense>(Boxes.expenses);
    final reopenedEmployees = await Hive.openBox<Employee>(Boxes.employees);
    final reopenedAccounts =
        await Hive.openBox<FinanceAccount>(Boxes.financeAccounts);
    final reopenedTransactions =
        await Hive.openBox<FinanceTransaction>(Boxes.financeTransactions);
    final reopenedPostings =
        await Hive.openBox<FinancePosting>(Boxes.financePostings);
    final reopenedDepartments =
        await Hive.openBox<HrDepartment>(Boxes.hrDepartments);
    final reopenedAttendance =
        await Hive.openBox<EmployeeAttendance>(Boxes.employeeAttendance);
    final reopenedBudgets =
        await Hive.openBox<FinanceBudget>(Boxes.financeBudgets);
    final reopenedRecurring = await Hive.openBox<FinanceRecurringTemplate>(
      Boxes.financeRecurringTemplates,
    );

    expect(reopenedSales.get('legacy-sale-1')!.totalAmount, 118);
    expect(reopenedExpenses.get('legacy-expense-1')!.amount, 125.50);
    expect(reopenedEmployees.get('legacy-employee-1')!.name, 'Anu');
    expect(reopenedAccounts.get('system:cash')!.accountType, 'asset');
    expect(reopenedTransactions.get('txn-1')!.status, 'posted');
    expect(reopenedPostings.get('posting-1')!.debitPaise, 12550);
    expect(reopenedDepartments.get('dept-1')!.name, 'Sales');
    expect(reopenedAttendance.get('attendance-1')!.status, 'present');
    expect(reopenedBudgets.get('budget-1')!.budgetPaise, 100000);
    expect(
      reopenedRecurring.get('recurring-1')!.amountPaise,
      100000,
    );
  });
}
