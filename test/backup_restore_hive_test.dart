import 'dart:io';

import 'package:billit/models/models.dart';
import 'package:billit/services/backup_restore_service.dart';
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

    users = await Hive.openBox<User>('users');
    products = await Hive.openBox<Product>('products');
    sales = await Hive.openBox<Sale>('sales');
    expenses = await Hive.openBox<Expense>('expenses');
    employees = await Hive.openBox<Employee>('employees');
    settings = await Hive.openBox<dynamic>('app_settings');
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<void> restore(Map<String, dynamic> data) => service.restore(
        data,
        usersBox: users,
        productsBox: products,
        salesBox: sales,
        expensesBox: expenses,
        employeesBox: employees,
        appSettingsBox: settings,
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

  test('legacy payload without app settings leaves current settings intact',
      () async {
    await settings.put('business_name', 'Legacy business');

    await restore({'users': [], 'products': [], 'sales': []});

    expect(settings.get('business_name'), 'Legacy business');
  });
}
