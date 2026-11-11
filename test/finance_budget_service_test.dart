import 'dart:io';

import 'package:billit/models/models.dart';
import 'package:billit/services/boxes.dart';
import 'package:billit/services/finance_budget_service.dart';
import 'package:billit/services/finance_schema_migration.dart';
import 'package:billit/services/schema_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

void main() {
  late Directory directory;
  late Box<dynamic> settings;
  late Box<FinanceCategory> categories;
  late Box<FinanceBudget> budgets;
  late FinanceBudgetService service;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('billit_finance_budget');
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
    ];
    for (final adapter in adapters) {
      if (!Hive.isAdapterRegistered(adapter.typeId)) {
        Hive.registerAdapter(adapter);
      }
    }
    settings = await Hive.openBox<dynamic>('app_settings');
    await SchemaMigrationService(
      currentVersion: 6,
      migrations: [
        FinanceSchemaMigration.versionOneToTwo,
        FinanceSchemaMigration.versionTwoToThree,
        FinanceSchemaMigration.versionThreeToFour,
        FinanceSchemaMigration.versionFourToFive,
        FinanceSchemaMigration.versionFiveToSix,
      ],
    ).run(settings);
    categories = Hive.box<FinanceCategory>(Boxes.financeCategories);
    budgets = Hive.box<FinanceBudget>(Boxes.financeBudgets);
    service = FinanceBudgetService();
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

  test('creates an expense budget and calculates actual spend', () async {
    final budget = await service.saveBudget(
      id: 'rent-budget',
      name: 'Monthly rent',
      accountId: 'system:operating-expense',
      categoryId: 'rent-category',
      periodStart: DateTime(2026, 11, 1, 12),
      periodEnd: DateTime(2026, 11, 30, 12),
      budgetPaise: 100000,
    );
    expect(budget.periodStart, DateTime(2026, 11, 1));
    expect(budget.periodEnd, DateTime(2026, 11, 30));

    final transactions = [
      FinanceTransaction(
        id: 'rent-entry',
        transactionNumber: 'RENT-1',
        transactionType: 'expense',
        status: 'posted',
        date: DateTime(2026, 11, 5),
      ),
      FinanceTransaction(
        id: 'outside-entry',
        transactionNumber: 'RENT-2',
        transactionType: 'expense',
        status: 'posted',
        date: DateTime(2026, 12, 1),
      ),
    ];
    final postings = [
      FinancePosting(
        id: 'rent-debit',
        transactionId: 'rent-entry',
        accountId: 'system:operating-expense',
        debitPaise: 70000,
        categoryId: 'rent-category',
      ),
      FinancePosting(
        id: 'rent-credit',
        transactionId: 'rent-entry',
        accountId: 'system:cash',
        creditPaise: 70000,
      ),
      FinancePosting(
        id: 'outside-debit',
        transactionId: 'outside-entry',
        accountId: 'system:operating-expense',
        debitPaise: 90000,
        categoryId: 'rent-category',
      ),
    ];

    final progress = service.summarize(
      budgets: budgets.values,
      transactions: transactions,
      postings: postings,
    ).single;
    expect(progress.actualPaise, 70000);
    expect(progress.remainingPaise, 30000);
    expect(progress.usedRatio, closeTo(0.7, 0.0001));
    expect(progress.overBudget, isFalse);
  });

  test('rejects invalid account, category, period, and amount', () async {
    await expectLater(
      service.saveBudget(
        name: 'Invalid',
        accountId: 'system:sales-income',
        periodStart: DateTime(2026, 11, 1),
        periodEnd: DateTime(2026, 11, 30),
        budgetPaise: 10000,
      ),
      throwsA(isA<FinanceBudgetException>()),
    );
    await expectLater(
      service.saveBudget(
        name: 'Wrong category',
        accountId: 'system:operating-expense',
        categoryId: 'missing-category',
        periodStart: DateTime(2026, 11, 1),
        periodEnd: DateTime(2026, 11, 30),
        budgetPaise: 10000,
      ),
      throwsA(isA<FinanceBudgetException>()),
    );
    await expectLater(
      service.saveBudget(
        name: 'Bad period',
        accountId: 'system:operating-expense',
        periodStart: DateTime(2026, 12, 1),
        periodEnd: DateTime(2026, 11, 1),
        budgetPaise: 10000,
      ),
      throwsA(isA<FinanceBudgetException>()),
    );
    await expectLater(
      service.saveBudget(
        name: 'Zero budget',
        accountId: 'system:operating-expense',
        periodStart: DateTime(2026, 11, 1),
        periodEnd: DateTime(2026, 11, 30),
        budgetPaise: 0,
      ),
      throwsA(isA<FinanceBudgetException>()),
    );
  });

  test('archives a budget without deleting its record', () async {
    await service.saveBudget(
      id: 'budget-to-archive',
      name: 'Utilities',
      accountId: 'system:operating-expense',
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 11, 30),
      budgetPaise: 50000,
    );
    await service.archiveBudget('budget-to-archive');

    expect(budgets.get('budget-to-archive')!.active, isFalse);
    expect(
      service.summarize(
        budgets: budgets.values,
        transactions: const [],
        postings: const [],
      ),
      isEmpty,
    );
    expect(
      service.summarize(
        budgets: budgets.values,
        transactions: const [],
        postings: const [],
        includeArchived: true,
      ),
      hasLength(1),
    );
  });
}
