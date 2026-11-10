import 'dart:io';

import 'package:billit/models/models.dart';
import 'package:billit/services/boxes.dart';
import 'package:billit/services/finance_recurring_service.dart';
import 'package:billit/services/finance_schema_migration.dart';
import 'package:billit/services/schema_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

void main() {
  late Directory directory;
  late Box<dynamic> settings;
  late Box<FinanceAccount> accounts;
  late Box<FinanceTransaction> transactions;
  late Box<FinancePosting> postings;
  late Box<FinanceCategory> categories;
  late Box<FinanceParty> parties;
  late Box<FinanceRecurringTemplate> templates;
  late FinanceRecurringService service;

  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('billit_finance_recurring');
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
      SalaryComponentAdapter(),
      PayrollRunAdapter(),
      PayslipAdapter(),
      FinanceBudgetAdapter(),
      FinanceRecurringTemplateAdapter(),
    ];
    for (final adapter in adapters) {
      if (!Hive.isAdapterRegistered(adapter.typeId)) {
        Hive.registerAdapter(adapter);
      }
    }
    settings = await Hive.openBox<dynamic>('app_settings');
    await SchemaMigrationService(
      currentVersion: 7,
      migrations: [
        FinanceSchemaMigration.versionOneToTwo,
        FinanceSchemaMigration.versionTwoToThree,
        FinanceSchemaMigration.versionThreeToFour,
        FinanceSchemaMigration.versionFourToFive,
        FinanceSchemaMigration.versionFiveToSix,
        FinanceSchemaMigration.versionSixToSeven,
      ],
    ).run(settings);
    accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    transactions =
        Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    postings = Hive.box<FinancePosting>(Boxes.financePostings);
    categories = Hive.box<FinanceCategory>(Boxes.financeCategories);
    parties = Hive.box<FinanceParty>(Boxes.financeParties);
    templates = Hive.box<FinanceRecurringTemplate>(
      Boxes.financeRecurringTemplates,
    );
    service = FinanceRecurringService();
    await categories.put(
      'rent-category',
      FinanceCategory(
        id: 'rent-category',
        name: 'Rent',
        kind: 'expense',
        accountId: 'system:operating-expense',
      ),
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('posts all due monthly entries once and stops after the end date',
      () async {
    final template = await service.createTemplate(
      name: 'Monthly rent',
      transactionType: 'expense',
      debitAccountId: 'system:operating-expense',
      creditAccountId: 'system:cash',
      amountPaise: 120000,
      interval: 'monthly',
      nextDueDate: DateTime(2026, 11, 30),
      endDate: DateTime(2026, 12, 31),
      categoryId: 'rent-category',
      memo: 'Shop rent',
    );

    final result = await service.processDue(now: DateTime(2026, 12, 31));
    expect(result.postedCount, 2);
    expect(result.skippedCount, 0);
    expect(result.issues, isEmpty);
    expect(
      transactions.values
          .where((item) => item.sourceType == 'recurring_template'),
      hasLength(2),
    );
    expect(
      postings.values
          .where((line) =>
              line.accountId == 'system:operating-expense' &&
              line.debitPaise == 120000),
      hasLength(2),
    );

    final updated = templates.get(template.id)!;
    expect(updated.active, isFalse);
    expect(updated.nextDueDate, DateTime(2027, 1, 31));

    final secondRun =
        await service.processDue(now: DateTime(2026, 12, 31));
    expect(secondRun.postedCount, 0);
    expect(transactions.values, hasLength(2));
  });

  test('advances an already-posted occurrence without duplicating it',
      () async {
    final template = await service.createTemplate(
      name: 'Daily utilities',
      transactionType: 'expense',
      debitAccountId: 'system:operating-expense',
      creditAccountId: 'system:bank',
      amountPaise: 2500,
      interval: 'daily',
      nextDueDate: DateTime(2026, 11, 10),
    );
    const dateKey = '20261110';
    final transactionId =
        'finance:recurring:${Uri.encodeComponent(template.id)}:$dateKey';
    await transactions.put(
      transactionId,
      FinanceTransaction(
        id: transactionId,
        transactionNumber: 'REC-${Uri.encodeComponent(template.id)}-$dateKey',
        transactionType: 'expense',
        status: 'posted',
        date: DateTime(2026, 11, 10),
        sourceType: 'recurring_template',
        sourceId: '${template.id}:$dateKey',
      ),
    );

    final result = await service.processDue(now: DateTime(2026, 11, 10));
    expect(result.postedCount, 0);
    expect(result.skippedCount, 1);
    expect(transactions.values, hasLength(1));
    expect(templates.get(template.id)!.nextDueDate, DateTime(2026, 11, 11));
  });

  test('preserves month-end cadence across February', () async {
    final template = await service.createTemplate(
      name: 'Month end rent',
      transactionType: 'expense',
      debitAccountId: 'system:operating-expense',
      creditAccountId: 'system:cash',
      amountPaise: 10000,
      interval: 'monthly',
      nextDueDate: DateTime(2027, 1, 31),
    );
    await service.processDue(now: DateTime(2027, 1, 31));
    expect(templates.get(template.id)!.nextDueDate, DateTime(2027, 2, 28));
    await service.processDue(now: DateTime(2027, 2, 28));
    expect(templates.get(template.id)!.nextDueDate, DateTime(2027, 3, 31));
  });

  test('rejects account mappings that do not match transaction type',
      () async {
    await expectLater(
      service.createTemplate(
        name: 'Invalid expense',
        transactionType: 'expense',
        debitAccountId: 'system:sales-income',
        creditAccountId: 'system:cash',
        amountPaise: 10000,
        interval: 'monthly',
        nextDueDate: DateTime(2026, 11, 1),
      ),
      throwsA(isA<FinanceRecurringException>()),
    );
  });
}
