import 'dart:io';

import 'package:billit/models/models.dart';
import 'package:billit/services/backup_restore_service.dart';
import 'package:billit/services/boxes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

void main() {
  late Directory tempDirectory;
  late Box<User> users;
  late Box<Product> products;
  late Box<Sale> sales;
  late Box<Expense> expenses;
  late Box<Employee> employees;
  late Box<dynamic> settings;
  late Box<FinanceAccount> financeAccounts;
  late Box<FinanceTransaction> financeTransactions;
  late Box<FinancePosting> financePostings;
  late Box<FinanceCategory> financeCategories;
  late Box<FinanceParty> financeParties;
  late Box<FinanceBudget> financeBudgets;
  late Box<FinanceRecurringTemplate> recurringTemplates;
  const service = BackupRestoreService();

  setUp(() async {
    tempDirectory =
        await Directory.systemTemp.createTemp('billit_backup_restore_test');
    Hive.init(tempDirectory.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(UserAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(UserTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(UnitTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(ProductAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(PaymentMethodAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(SaleItemAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(SaleAdapter());
    }
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(ExpenseAdapter());
    }
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(EmployeeAdapter());
    }

    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(FinanceAccountAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(FinanceTransactionAdapter());
    }
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(FinancePostingAdapter());
    }
    if (!Hive.isAdapterRegistered(13)) {
      Hive.registerAdapter(FinanceCategoryAdapter());
    }
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(FinancePartyAdapter());
    }
    if (!Hive.isAdapterRegistered(21)) {
      Hive.registerAdapter(FinanceBudgetAdapter());
    }
    if (!Hive.isAdapterRegistered(22)) {
      Hive.registerAdapter(FinanceRecurringTemplateAdapter());
    }

    users = await Hive.openBox<User>('users');
    products = await Hive.openBox<Product>('products');
    sales = await Hive.openBox<Sale>('sales');
    expenses = await Hive.openBox<Expense>('expenses');
    employees = await Hive.openBox<Employee>('employees');
    settings = await Hive.openBox<dynamic>('app_settings');
    financeAccounts =
        await Hive.openBox<FinanceAccount>(Boxes.financeAccounts);
    financeTransactions =
        await Hive.openBox<FinanceTransaction>(Boxes.financeTransactions);
    financePostings =
        await Hive.openBox<FinancePosting>(Boxes.financePostings);
    financeCategories =
        await Hive.openBox<FinanceCategory>(Boxes.financeCategories);
    financeParties =
        await Hive.openBox<FinanceParty>(Boxes.financeParties);
    financeBudgets =
        await Hive.openBox<FinanceBudget>(Boxes.financeBudgets);
    recurringTemplates = await Hive.openBox<FinanceRecurringTemplate>(
      Boxes.financeRecurringTemplates,
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<void> restore(
    Map<String, dynamic> data, {
    Future<void> Function(String stage)? afterWrite,
  }) => service.restore(
        data,
        usersBox: users,
        productsBox: products,
        salesBox: sales,
        expensesBox: expenses,
        employeesBox: employees,
        appSettingsBox: settings,
        financeAccountsBox: financeAccounts,
        financeTransactionsBox: financeTransactions,
        financePostingsBox: financePostings,
        financeCategoriesBox: financeCategories,
        financePartiesBox: financeParties,
        financeBudgetsBox: financeBudgets,
        financeRecurringTemplatesBox: recurringTemplates,
        afterWrite: afterWrite,
      );

  test('restores recurring templates with validated account mappings', () async {
    await restore({
      'users': [],
      'financeAccounts': [
        {
          'id': 'cash',
          'name': 'Cash',
          'accountType': 'asset',
          'currencyCode': 'INR',
          'active': true,
        },
        {
          'id': 'rent-expense',
          'name': 'Rent',
          'accountType': 'expense',
          'currencyCode': 'INR',
          'active': true,
        },
      ],
      'financeTransactions': [],
      'financePostings': [],
      'financeCategories': [
        {
          'id': 'rent-category',
          'name': 'Rent',
          'kind': 'expense',
          'accountId': 'rent-expense',
          'active': true,
        },
      ],
      'financeParties': [],
      'financeRecurringTemplates': [
        {
          'id': 'rent-monthly',
          'name': 'Monthly rent',
          'transactionType': 'expense',
          'debitAccountId': 'rent-expense',
          'creditAccountId': 'cash',
          'amountPaise': 250000,
          'interval': 'monthly',
          'nextDueDate': '2026-12-01T00:00:00.000',
          'endDate': null,
          'categoryId': 'rent-category',
          'partyId': null,
          'memo': 'Shop rent',
          'active': true,
          'createdAt': '2026-11-01T00:00:00.000',
        },
      ],
    });

    final template = recurringTemplates.get('rent-monthly');
    expect(template, isNotNull);
    expect(template!.amountPaise, 250000);
    expect(template.interval, 'monthly');
    expect(template.categoryId, 'rent-category');
  });

  test('restores finance budgets with account and category references', () async {
    await restore({
      'users': [],
      'financeAccounts': [
        {
          'id': 'expense-account',
          'name': 'Rent',
          'accountType': 'expense',
          'currencyCode': 'INR',
          'active': true,
        },
      ],
      'financeTransactions': [],
      'financePostings': [],
      'financeCategories': [
        {
          'id': 'rent-category',
          'name': 'Rent',
          'kind': 'expense',
          'accountId': 'expense-account',
          'active': true,
        },
      ],
      'financeParties': [],
      'financeBudgets': [
        {
          'id': 'rent-budget',
          'name': 'Monthly rent',
          'accountId': 'expense-account',
          'categoryId': 'rent-category',
          'periodStart': '2026-11-01T00:00:00.000',
          'periodEnd': '2026-11-30T00:00:00.000',
          'budgetPaise': 500000,
          'active': true,
          'notes': 'Shop rent',
          'createdAt': '2026-10-30T00:00:00.000',
        },
      ],
    });

    final budget = financeBudgets.get('rent-budget');
    expect(budget, isNotNull);
    expect(budget!.budgetPaise, 500000);
    expect(budget.accountId, 'expense-account');
    expect(budget.categoryId, 'rent-category');
  });

  test('replaces business records and merges app settings', () async {
    final oldUser = User()
      ..id = 'old'
      ..username = 'old-user'
      ..password = 'old-hash'
      ..userType = UserType.worker;
    await users.put(oldUser.id, oldUser);
    await settings.put('existing_setting', 'keep-me');
    await settings.put('overridden_setting', 'old');
    await financeBudgets.put(
      'legacy-budget',
      FinanceBudget(
        id: 'legacy-budget',
        name: 'Existing budget',
        accountId: 'legacy-expense-account',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 31),
        budgetPaise: 10000,
      ),
    );

    await restore({
      'users': [
        {
          'id': 'new',
          'username': 'admin',
          'password': 'new-hash',
          'userType': 'admin',
        },
      ],
      'appSettings': {'overridden_setting': 'new', 'new_setting': true},
    });

    expect(users.keys, ['new']);
    expect(users.get('new')!.username, 'admin');
    expect(settings.get('existing_setting'), 'keep-me');
    expect(settings.get('overridden_setting'), 'new');
    expect(settings.get('new_setting'), isTrue);
    expect(financeBudgets.get('legacy-budget')!.budgetPaise, 10000);
  });

  test('malformed payload leaves all existing boxes unchanged', () async {
    final oldUser = User()
      ..id = 'old'
      ..username = 'old-user'
      ..password = 'old-hash'
      ..userType = UserType.admin;
    final oldProduct = Product()
      ..id = 'old-product'
      ..name = 'Existing product'
      ..sellingPrice = 20
      ..costPrice = 10
      ..stock = 5;
    await users.put(oldUser.id, oldUser);
    await products.put(oldProduct.id, oldProduct);
    await settings.put('business_name', 'Existing business');

    await expectLater(
      restore({
        'users': [
          {
            'id': 'new',
            'username': 'new-user',
            'password': 'hash',
            'userType': 'worker',
          },
        ],
        'products': [
          {
            'id': 'bad-product',
            'name': 'Broken product',
            'sellingPrice': 'not-a-number',
            'costPrice': 10,
            'stock': 1,
          },
        ],
      }),
      throwsFormatException,
    );

    expect(users.keys, ['old']);
    expect(users.get('old')!.username, 'old-user');
    expect(products.keys, ['old-product']);
    expect(products.get('old-product')!.name, 'Existing product');
    expect(settings.get('business_name'), 'Existing business');
  });

  test('rolls back every box when a Hive write sequence fails', () async {
    final oldUser = User()
      ..id = 'old-user'
      ..username = 'old-user'
      ..password = 'old-hash'
      ..userType = UserType.worker;
    final oldProduct = Product()
      ..id = 'old-product'
      ..name = 'Existing product'
      ..sellingPrice = 20
      ..costPrice = 10
      ..stock = 5;
    final oldSale = Sale()
      ..id = 'old-sale'
      ..date = DateTime(2026, 1, 2)
      ..items = []
      ..totalAmount = 20
      ..totalCost = 10
      ..profit = 10
      ..payment = PaymentMethod.cash;
    final oldExpense = Expense(
      id: 'old-expense',
      date: DateTime(2026, 1, 3),
      category: 'Rent',
      amount: 100,
      description: 'Existing expense',
    );
    final oldEmployee = Employee(
      id: 'old-employee',
      name: 'Existing employee',
      type: 'Monthly',
      wage: 1000,
    );

    await users.put(oldUser.id, oldUser);
    await products.put(oldProduct.id, oldProduct);
    await sales.put(oldSale.id, oldSale);
    await expenses.put(oldExpense.id, oldExpense);
    await employees.put(oldEmployee.id, oldEmployee);
    await settings.put('business_name', 'Original business');
    await financeAccounts.put(
      'old-account',
      FinanceAccount(
        id: 'old-account',
        name: 'Old account',
        accountType: 'asset',
      ),
    );
    await financeTransactions.put(
      'old-finance-transaction',
      FinanceTransaction(
        id: 'old-finance-transaction',
        transactionNumber: 'OLD-1',
        transactionType: 'adjustment',
      ),
    );
    await financePostings.put(
      'old-finance-posting',
      FinancePosting(
        id: 'old-finance-posting',
        transactionId: 'old-finance-transaction',
        accountId: 'old-account',
        debitPaise: 100,
      ),
    );
    await financeCategories.put(
      'old-finance-category',
      FinanceCategory(
        id: 'old-finance-category',
        name: 'Old category',
        kind: 'expense',
        accountId: 'old-account',
      ),
    );
    await financeParties.put(
      'old-finance-party',
      FinanceParty(
        id: 'old-finance-party',
        name: 'Old party',
        partyType: 'supplier',
      ),
    );
    await financeBudgets.put(
      'old-budget',
      FinanceBudget(
        id: 'old-budget',
        name: 'Old budget',
        accountId: 'old-account',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 31),
        budgetPaise: 25000,
      ),
    );
    await recurringTemplates.put(
      'old-recurring',
      FinanceRecurringTemplate(
        id: 'old-recurring',
        name: 'Old recurring',
        transactionType: 'transfer',
        debitAccountId: 'old-account',
        creditAccountId: 'old-account',
        amountPaise: 1000,
        interval: 'monthly',
        nextDueDate: DateTime(2026, 1, 1),
      ),
    );

    var injected = false;
    await expectLater(
      restore(
        {
          'users': [
            {
              'id': 'new-user',
              'username': 'new-user',
              'password': 'new-hash',
              'userType': 'admin',
            },
          ],
          'appSettings': {'business_name': 'Replacement business'},
          'financeAccounts': [
            {
              'id': 'new-account',
              'name': 'New account',
              'accountType': 'asset',
              'currencyCode': 'INR',
              'active': true,
              'createdAt': '2026-01-01T00:00:00.000',
            },
            {
              'id': 'new-expense',
              'name': 'New expense',
              'accountType': 'expense',
              'currencyCode': 'INR',
              'active': true,
              'createdAt': '2026-01-01T00:00:00.000',
            },
          ],
          'financeTransactions': [],
          'financePostings': [],
          'financeCategories': [],
          'financeParties': [],
          'financeBudgets': [
            {
              'id': 'new-budget',
              'name': 'New budget',
              'accountId': 'new-expense',
              'periodStart': '2026-01-01T00:00:00.000',
              'periodEnd': '2026-01-31T00:00:00.000',
              'budgetPaise': 50000,
            },
          ],
          'financeRecurringTemplates': [
            {
              'id': 'new-recurring',
              'name': 'New recurring',
              'transactionType': 'expense',
              'debitAccountId': 'new-expense',
              'creditAccountId': 'new-account',
              'amountPaise': 1000,
              'interval': 'monthly',
              'nextDueDate': '2026-01-01T00:00:00.000',
            },
          ],
        },
        afterWrite: (stage) async {
          if (stage == 'appSettings.putAll' && !injected) {
            injected = true;
            throw StateError('Simulated Hive write failure');
          }
        },
      ),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        'Simulated Hive write failure',
      )),
    );

    expect(injected, isTrue);
    expect(users.keys, ['old-user']);
    expect(products.keys, ['old-product']);
    expect(sales.keys, ['old-sale']);
    expect(expenses.keys, ['old-expense']);
    expect(employees.keys, ['old-employee']);
    expect(settings.get('business_name'), 'Original business');
    expect(financeAccounts.keys, ['old-account']);
    expect(financeAccounts.get('old-account')!.name, 'Old account');
    expect(financeTransactions.keys, ['old-finance-transaction']);
    expect(financePostings.keys, ['old-finance-posting']);
    expect(financeCategories.keys, ['old-finance-category']);
    expect(financeParties.keys, ['old-finance-party']);
    expect(financeBudgets.keys, ['old-budget']);
    expect(financeBudgets.get('old-budget')!.budgetPaise, 25000);
    expect(recurringTemplates.keys, ['old-recurring']);
    expect(recurringTemplates.get('old-recurring')!.name, 'Old recurring');
    expect(users.get('old-user')!.username, 'old-user');
    expect(products.get('old-product')!.name, 'Existing product');
    expect(sales.get('old-sale')!.totalAmount, 20);
    expect(expenses.get('old-expense')!.amount, 100);
    expect(employees.get('old-employee')!.name, 'Existing employee');
  });

  test('restores finance collections while preserving paise precision', () async {
    await financeBudgets.put(
      'existing-budget',
      FinanceBudget(
        id: 'existing-budget',
        name: 'Existing office budget',
        accountId: 'expense',
        categoryId: 'office',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 31),
        budgetPaise: 80000,
      ),
    );
    await recurringTemplates.put(
      'existing-recurring',
      FinanceRecurringTemplate(
        id: 'existing-recurring',
        name: 'Existing office supplies',
        transactionType: 'expense',
        debitAccountId: 'expense',
        creditAccountId: 'cash',
        amountPaise: 2500,
        interval: 'monthly',
        nextDueDate: DateTime(2026, 2, 1),
        categoryId: 'office',
        partyId: 'supplier',
      ),
    );
    await financeAccounts.put(
      'old-account',
      FinanceAccount(
        id: 'old-account',
        name: 'Old account',
        accountType: 'asset',
      ),
    );

    await restore({
      'financeAccounts': [
        {
          'id': 'cash',
          'name': 'Cash',
          'accountType': 'asset',
          'currencyCode': 'INR',
          'active': true,
          'createdAt': '2026-01-01T00:00:00.000',
        },
        {
          'id': 'expense',
          'name': 'Operating Expenses',
          'accountType': 'expense',
          'currencyCode': 'INR',
          'active': true,
          'createdAt': '2026-01-01T00:00:00.000',
        },
      ],
      'financeTransactions': [
        {
          'id': 'txn',
          'transactionNumber': 'TXN-1',
          'transactionType': 'expense',
          'status': 'posted',
          'date': '2026-01-02T00:00:00.000',
          'createdAt': '2026-01-02T00:00:00.000',
          'memo': 'Office supplies',
          'reference': '',
          'sourceType': 'manual',
          'sourceId': 'expense-1',
        },
      ],
      'financePostings': [
        {
          'id': 'line-debit',
          'transactionId': 'txn',
          'accountId': 'expense',
          'debitPaise': 12551,
          'creditPaise': 0,
          'memo': '',
        },
        {
          'id': 'line-credit',
          'transactionId': 'txn',
          'accountId': 'cash',
          'debitPaise': 0,
          'creditPaise': 12551,
          'memo': '',
        },
      ],
      'financeCategories': [
        {
          'id': 'office',
          'name': 'Office',
          'kind': 'expense',
          'accountId': 'expense',
          'active': true,
        },
      ],
      'financeParties': [
        {
          'id': 'supplier',
          'name': 'Stationery supplier',
          'partyType': 'supplier',
          'phone': '',
          'email': '',
          'taxIdentifier': '',
          'active': true,
        },
      ],
    });

    expect(financeAccounts.keys, containsAll(['cash', 'expense']));
    expect(financeTransactions.get('txn')!.status, 'posted');
    expect(financePostings.get('line-debit')!.debitPaise, 12551);
    expect(financeCategories.get('office')!.accountId, 'expense');
    expect(financeParties.get('supplier')!.partyType, 'supplier');
    expect(financeBudgets.get('existing-budget')!.budgetPaise, 80000);
    expect(
      recurringTemplates.get('existing-recurring')!.partyId,
      'supplier',
    );
  });

  test('legacy payload preserves finance data and current settings', () async {
    await settings.put('business_name', 'Legacy business');
    await financeAccounts.put(
      'legacy-finance-account',
      FinanceAccount(
        id: 'legacy-finance-account',
        name: 'Existing finance account',
        accountType: 'asset',
      ),
    );

    await restore({'users': [], 'products': [], 'sales': []});

    expect(settings.get('business_name'), 'Legacy business');
    expect(financeAccounts.get('legacy-finance-account')!.name,
        'Existing finance account');
  });
}
