import '../models/employee.dart';
import '../models/finance_account.dart';
import '../models/finance_category.dart';
import '../models/finance_party.dart';
import '../models/finance_posting.dart';
import '../models/finance_transaction.dart';
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
  /// Null means a legacy backup that predates finance-ledger serialization.
  final List<FinanceAccount>? financeAccounts;
  final List<FinanceTransaction>? financeTransactions;
  final List<FinancePosting>? financePostings;
  final List<FinanceCategory>? financeCategories;
  final List<FinanceParty>? financeParties;
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
    Future<void> Function(String stage)? afterWrite,
  }) async {
    final hasFinancePayload = payload.financeAccounts != null;
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
    if (hasAnyFinanceKey) {
      _validateFinanceCollections(
        financeAccounts!,
        financeTransactions!,
        financePostings!,
        financeCategories!,
        financeParties!,
      );
    }

    return BackupRestorePayload(
      users: _parseRecords(data, 'users', _parseUser),
      products: _parseRecords(data, 'products', _parseProduct),
      sales: _parseRecords(data, 'sales', _parseSale),
      expenses: _parseRecords(data, 'expenses', _parseExpense),
      employees: _parseRecords(data, 'employees', _parseEmployee),
      financeAccounts: financeAccounts,
      financeTransactions: financeTransactions,
      financePostings: financePostings,
      financeCategories: financeCategories,
      financeParties: financeParties,
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

  void _validateFinanceCollections(
    List<FinanceAccount> accounts,
    List<FinanceTransaction> transactions,
    List<FinancePosting> postings,
    List<FinanceCategory> categories,
    List<FinanceParty> parties,
  ) {
    final accountIds = accounts.map((item) => item.id).toSet();
    final transactionById = {
      for (final item in transactions) item.id: item,
    };
    final categoryIds = categories.map((item) => item.id).toSet();
    final partyIds = parties.map((item) => item.id).toSet();
    final postingsByTransaction = <String, List<FinancePosting>>{};

    for (final category in categories) {
      if (!accountIds.contains(category.accountId)) {
        throw FormatException(
          'financeCategories.${category.id} references an unknown account.',
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
    return FinanceAccount(
      id: _requiredString(json, 'id', path),
      name: _requiredString(json, 'name', path),
      accountType: type,
      parentId: _nullableString(json, 'parentId', path),
      currencyCode: _optionalString(json, 'currencyCode', 'INR', path),
      active: _boolean(json, 'active', path, fallback: true),
      createdAt: json['createdAt'] == null
          ? DateTime.now()
          : _date(json, 'createdAt', path),
    );
  }

  FinanceTransaction _parseFinanceTransaction(Map<String, dynamic> json) {
    const path = 'financeTransactions';
    final type = _requiredString(json, 'transactionType', path);
    if (!{'income', 'expense', 'transfer', 'opening_balance', 'adjustment', 'reversal'}.contains(type)) {
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

  Map<String, dynamic>? _parseSettings(Object? value) {
    if (value == null) return null;
    return _asMap(value, 'appSettings');
  }
}
