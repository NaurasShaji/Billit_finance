import 'dart:io';

import 'package:billit/models/models.dart';
import 'package:billit/services/boxes.dart';
import 'package:billit/services/finance_ledger_service.dart';
import 'package:billit/services/finance_schema_migration.dart';
import 'package:billit/services/finance_source_sync_service.dart';
import 'package:billit/services/schema_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

void main() {
  late Directory directory;
  late Box<dynamic> settings;
  late Box<Sale> sales;
  late Box<Expense> expenses;
  late Box<Employee> employees;
  late Box<FinanceAccount> accounts;
  late Box<FinanceTransaction> transactions;
  late Box<FinancePosting> postings;
  late Box<FinanceCategory> categories;
  late Box<FinanceParty> parties;
  late FinanceSourceSyncService sync;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('billit_source_sync');
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
    ];
    for (final adapter in adapters) {
      if (!Hive.isAdapterRegistered(adapter.typeId)) {
        Hive.registerAdapter(adapter);
      }
    }

    settings = await Hive.openBox<dynamic>('app_settings');
    await SchemaMigrationService(
      currentVersion: 3,
      migrations: [
        FinanceSchemaMigration.versionOneToTwo,
        FinanceSchemaMigration.versionTwoToThree,
      ],
    ).run(settings);
    sales = await Hive.openBox<Sale>(Boxes.sales);
    expenses = await Hive.openBox<Expense>(Boxes.expenses);
    employees = await Hive.openBox<Employee>(Boxes.employees);
    accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    postings = Hive.box<FinancePosting>(Boxes.financePostings);
    categories = Hive.box<FinanceCategory>(Boxes.financeCategories);
    parties = Hive.box<FinanceParty>(Boxes.financeParties);
    sync = FinanceSourceSyncService();
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('imports GST sale into cash/bank, revenue and GST liability once', () async {
    final sale = Sale()
      ..id = 'sale-100'
      ..date = DateTime(2026, 10, 1)
      ..items = []
      ..totalAmount = 118
      ..taxableAmount = 100
      ..cgstAmount = 9
      ..sgstAmount = 9
      ..gstEnabled = true
      ..payment = PaymentMethod.upi;
    await sales.put(sale.id, sale);

    expect(
      await sync.syncSale(
        sale: sale,
        accountsBox: accounts,
        transactionsBox: transactions,
        postingsBox: postings,
        categoriesBox: categories,
        partiesBox: parties,
        settingsBox: settings,
      ),
      isTrue,
    );
    expect(
      await sync.syncSale(
        sale: sale,
        accountsBox: accounts,
        transactionsBox: transactions,
        postingsBox: postings,
        categoriesBox: categories,
        partiesBox: parties,
        settingsBox: settings,
      ),
      isFalse,
    );

    final journal = transactions.values.single;
    expect(journal.sourceType, 'pos_sale');
    expect(journal.sourceId, 'sale-100:0');
    expect(postings.values, hasLength(3));
    expect(
      postings.values
          .where((line) => line.accountId == 'system:bank')
          .single
          .debitPaise,
      11800,
    );
    expect(
      postings.values
          .where((line) => line.accountId == 'system:sales-income')
          .single
          .creditPaise,
      10000,
    );
    expect(
      postings.values
          .where((line) => line.accountId == 'system:gst-payable')
          .single
          .creditPaise,
      1800,
    );
  });

  test('POS payment accounts can be configured independently by method', () async {
    final wallet = FinanceAccount(
      id: 'shop-wallet',
      name: 'Shop Wallet',
      accountType: 'asset',
      currencyCode: 'INR',
    );
    await accounts.put(wallet.id, wallet);
    await sync.savePaymentAccountMapping(
      mapping: {
        'cash': 'system:cash',
        'card': 'system:bank',
        'upi': wallet.id,
      },
      accountsBox: accounts,
      settingsBox: settings,
    );

    final sale = Sale()
      ..id = 'sale-mapped-upi'
      ..date = DateTime(2026, 10, 2)
      ..items = []
      ..totalAmount = 250
      ..gstEnabled = false
      ..payment = PaymentMethod.upi;

    await sync.syncSale(
      sale: sale,
      accountsBox: accounts,
      transactionsBox: transactions,
      postingsBox: postings,
      categoriesBox: categories,
      partiesBox: parties,
      settingsBox: settings,
    );

    final receipt = postings.values.singleWhere(
      (line) => line.transactionId == 'finance:sale:sale-mapped-upi:r0:receipt',
    );
    expect(receipt.accountId, wallet.id);
    expect(receipt.debitPaise, 25000);
  });

  test('invalid POS payment account mapping is rejected before posting', () async {
    await settings.put(
      FinanceSourceSyncService.paymentAccountSettingsKey,
      {'cash': 'system:operating-expense', 'card': 'system:bank', 'upi': 'system:bank'},
    );
    final sale = Sale()
      ..id = 'sale-invalid-method-map'
      ..date = DateTime(2026, 10, 2)
      ..items = []
      ..totalAmount = 25
      ..gstEnabled = false
      ..payment = PaymentMethod.cash;

    await expectLater(
      sync.syncSale(
        sale: sale,
        accountsBox: accounts,
        transactionsBox: transactions,
        postingsBox: postings,
        categoriesBox: categories,
        partiesBox: parties,
        settingsBox: settings,
      ),
      throwsA(isA<FinanceLedgerException>()),
    );
    expect(transactions.values.where((t) => t.sourceType == 'pos_sale'), isEmpty);
    expect(postings.values, isEmpty);
  });

  test('imports expenses in paise and maps payroll to salary account and party',
      () async {
    final employee = Employee(
      id: 'emp-1',
      name: 'Asha',
      type: 'Monthly',
      wage: 25000,
    );
    await employees.put(employee.id, employee);
    final rent = Expense(
      id: 'expense-rent',
      date: DateTime(2026, 10, 2),
      category: 'Rent',
      amount: 123.45,
      description: 'Shop rent',
    );
    final salary = Expense(
      id: 'expense-salary',
      date: DateTime(2026, 10, 3),
      category: 'Salary-Monthly',
      amount: 25000,
      description: 'Monthly salary',
      employeeId: employee.id,
    );
    await expenses.put(rent.id, rent);
    await expenses.put(salary.id, salary);

    await sync.syncAll(
      salesBox: sales,
      expensesBox: expenses,
      employeesBox: employees,
      accountsBox: accounts,
      transactionsBox: transactions,
      postingsBox: postings,
      categoriesBox: categories,
      partiesBox: parties,
    );

    final rentTxn = transactions.values
        .singleWhere((item) => item.sourceId == 'expense-rent:0');
    final salaryTxn = transactions.values
        .singleWhere((item) => item.sourceId == 'expense-salary:0');
    expect(rentTxn.transactionType, 'expense');
    expect(salaryTxn.transactionType, 'expense');
    expect(
      postings.values
          .singleWhere((line) => line.transactionId == rentTxn.id &&
              line.debitPaise > 0)
          .debitPaise,
      12345,
    );
    final salaryDebit = postings.values.singleWhere(
      (line) => line.transactionId == salaryTxn.id && line.debitPaise > 0,
    );
    expect(salaryDebit.accountId, 'system:salary-expense');
    expect(salaryDebit.partyId, 'employee:emp-1');
    expect(parties.get('employee:emp-1')!.name, 'Asha');
    expect(
      accounts.get('system:salary-expense')!.accountType,
      'expense',
    );
  });

  test('expense journal uses the selected active INR asset payment account', () async {
    final expense = Expense(
      id: 'expense-bank-paid',
      date: DateTime(2026, 10, 7),
      category: 'Rent',
      amount: 250,
      description: 'Rent paid from bank',
    );
    await sync.syncExpense(
      expense: expense,
      accountsBox: accounts,
      transactionsBox: transactions,
      postingsBox: postings,
      categoriesBox: categories,
      partiesBox: parties,
      employeesBox: employees,
      paymentAccountId: 'system:bank',
    );

    final journal = transactions.values.singleWhere(
      (item) => item.sourceId == 'expense-bank-paid:0',
    );
    final credit = postings.values.singleWhere(
      (line) => line.transactionId == journal.id && line.creditPaise > 0,
    );
    expect(credit.accountId, 'system:bank');
    expect(credit.creditPaise, 25000);
  });

  test('expense journal rejects a non-asset payment account', () async {
    final expense = Expense(
      id: 'expense-invalid-payment-account',
      date: DateTime(2026, 10, 7),
      category: 'Rent',
      amount: 250,
      description: 'Invalid destination',
    );
    await expectLater(
      sync.syncExpense(
        expense: expense,
        accountsBox: accounts,
        transactionsBox: transactions,
        postingsBox: postings,
        categoriesBox: categories,
        partiesBox: parties,
        employeesBox: employees,
        paymentAccountId: 'system:operating-expense',
      ),
      throwsA(isA<FinanceLedgerException>()),
    );
    expect(transactions.values, isEmpty);
    expect(postings.values, isEmpty);
  });

  test('sale edits reverse the previous snapshot and post the new revision',
      () async {
    final sale = Sale()
      ..id = 'sale-edit'
      ..date = DateTime(2026, 10, 4)
      ..items = []
      ..totalAmount = 100
      ..payment = PaymentMethod.cash;
    await sync.syncSale(
      sale: sale,
      accountsBox: accounts,
      transactionsBox: transactions,
      postingsBox: postings,
      categoriesBox: categories,
      partiesBox: parties,
    );

    sale
      ..financeRevision = 1
      ..totalAmount = 150;
    await sales.put(sale.id, sale);
    await sync.syncSale(
      sale: sale,
      accountsBox: accounts,
      transactionsBox: transactions,
      postingsBox: postings,
      categoriesBox: categories,
      partiesBox: parties,
    );

    expect(transactions.values.where((t) => t.transactionType == 'reversal'),
        hasLength(1));
    expect(
      FinanceLedgerBalance.balance(
        accountId: 'system:cash',
        transactions: transactions,
        postings: postings,
      ),
      15000,
    );
    expect(
      FinanceLedgerBalance.balance(
        accountId: 'system:sales-income',
        transactions: transactions,
        postings: postings,
      ),
      -15000,
    );
  });

  test('deleting an expense reverses its journal without deleting history',
      () async {
    final expense = Expense(
      id: 'expense-delete',
      date: DateTime(2026, 10, 5),
      category: 'Supplies',
      amount: 50,
      description: 'Supplies',
    );
    await sync.syncExpense(
      expense: expense,
      accountsBox: accounts,
      transactionsBox: transactions,
      postingsBox: postings,
      categoriesBox: categories,
      partiesBox: parties,
      employeesBox: employees,
    );
    await sync.reverseExpense(
      expense: expense,
      accountsBox: accounts,
      transactionsBox: transactions,
      postingsBox: postings,
      categoriesBox: categories,
      partiesBox: parties,
    );

    expect(transactions.values.where((t) => t.transactionType == 'reversal'),
        hasLength(1));
    expect(
      FinanceLedgerBalance.balance(
        accountId: 'system:operating-expense',
        transactions: transactions,
        postings: postings,
      ),
      0,
    );
    expect(transactions.values, hasLength(2));
  });
}

/// Minimal test-only projection for the raw debit-minus-credit account balance.
class FinanceLedgerBalance {
  static int balance({
    required String accountId,
    required Iterable<FinanceTransaction> transactions,
    required Iterable<FinancePosting> postings,
  }) {
    final posted = transactions
        .where((transaction) => transaction.status == 'posted')
        .map((transaction) => transaction.id)
        .toSet();
    return postings
        .where((line) =>
            line.accountId == accountId && posted.contains(line.transactionId))
        .fold<int>(0, (sum, line) => sum + line.debitPaise - line.creditPaise);
  }
}
