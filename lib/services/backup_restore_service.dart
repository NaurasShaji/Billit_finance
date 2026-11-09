import '../models/employee.dart';
import '../models/expense.dart';
import '../models/product.dart';
import '../models/sale.dart';
import 'package:hive/hive.dart';

import '../models/user.dart';

/// Fully parsed backup data. Constructing this object performs all validation,
/// before the caller mutates any live Hive box.
class BackupRestorePayload {
  final List<User> users;
  final List<Product> products;
  final List<Sale> sales;
  final List<Expense> expenses;
  final List<Employee> employees;
  final Map<String, dynamic>? appSettings;

  const BackupRestorePayload({
    required this.users,
    required this.products,
    required this.sales,
    required this.expenses,
    required this.employees,
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
    Future<void> Function(String stage)? afterWrite,
  }) async {
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
    return BackupRestorePayload(
      users: _parseRecords(data, 'users', _parseUser),
      products: _parseRecords(data, 'products', _parseProduct),
      sales: _parseRecords(data, 'sales', _parseSale),
      expenses: _parseRecords(data, 'expenses', _parseExpense),
      employees: _parseRecords(data, 'employees', _parseEmployee),
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
      ..gstInclusive = _boolean(json, 'gstInclusive', path);
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
    return Employee(
      id: _requiredString(json, 'id', path),
      name: _requiredString(json, 'name', path),
      type: _requiredString(json, 'type', path),
      wage: _number(json, 'wage', path),
      attendance: attendanceValue.toInt(),
      salaryPaid: _boolean(json, 'salaryPaid', path),
    );
  }

  Map<String, dynamic>? _parseSettings(Object? value) {
    if (value == null) return null;
    return _asMap(value, 'appSettings');
  }
}
