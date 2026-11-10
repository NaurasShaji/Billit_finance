import 'dart:io';

import 'package:billit/models/models.dart';
import 'package:billit/services/backup_restore_service.dart';
import 'package:billit/services/boxes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

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
        afterWrite: afterWrite,
      );

  test('replaces business records and merges app settings', () async {
    final oldUser = User()
      ..id = 'old'
      ..username = 'old-user'
      ..password = 'old-hash'
      ..userType = UserType.worker;
    await users.put(oldUser.id, oldUser);
    await settings.put('existing_setting', 'keep-me');
    await settings.put('overridden_setting', 'old');

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
          ],
          'financeTransactions': [],
          'financePostings': [],
          'financeCategories': [],
          'financeParties': [],
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
    expect(users.get('old-user')!.username, 'old-user');
    expect(products.get('old-product')!.name, 'Existing product');
    expect(sales.get('old-sale')!.totalAmount, 20);
    expect(expenses.get('old-expense')!.amount, 100);
    expect(employees.get('old-employee')!.name, 'Existing employee');
  });

  test('restores finance collections while preserving paise precision', () async {
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
  });

  test('legacy payload without app settings leaves current settings intact',
      () async {
    await settings.put('business_name', 'Legacy business');

    await restore({'users': [], 'products': [], 'sales': []});

    expect(settings.get('business_name'), 'Legacy business');
  });
}
