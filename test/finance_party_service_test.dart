import 'dart:io';

import 'package:billit/models/models.dart';
import 'package:billit/services/boxes.dart';
import 'package:billit/services/finance_ledger_service.dart';
import 'package:billit/services/finance_party_service.dart';
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
  late Box<FinanceParty> parties;
  late FinancePartyService service;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('billit_party_test');
    Hive.init(directory.path);
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
    accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    postings = Hive.box<FinancePosting>(Boxes.financePostings);
    parties = Hive.box<FinanceParty>(Boxes.financeParties);
    service = FinancePartyService();
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  Future<void> post({
    required String id,
    required String type,
    required String debitAccount,
    required String creditAccount,
    required int amountPaise,
    required String partyId,
  }) async {
    await FinanceLedgerService().postTransaction(
      transaction: FinanceTransaction(
        id: id,
        transactionNumber: id.toUpperCase(),
        transactionType: type,
        sourceType: 'party-test',
        sourceId: id,
      ),
      postings: [
        FinancePosting(
          id: '$id:debit',
          transactionId: id,
          accountId: debitAccount,
          debitPaise: amountPaise,
          partyId: partyId,
        ),
        FinancePosting(
          id: '$id:credit',
          transactionId: id,
          accountId: creditAccount,
          creditPaise: amountPaise,
          partyId: partyId,
        ),
      ],
      accountsBox: accounts,
      transactionsBox: transactions,
      postingsBox: postings,
      categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
      partiesBox: parties,
    );
  }

  test('tracks customer receivables and partial customer receipts', () async {
    final customer = await service.saveParty(
      id: 'customer-1',
      name: 'Northwind Stores',
      partyType: 'customer',
      phone: '9999999999',
    );
    await post(
      id: 'customer-invoice',
      type: 'income',
      debitAccount: 'system:receivables',
      creditAccount: 'system:sales-income',
      amountPaise: 50000,
      partyId: customer.id,
    );
    await post(
      id: 'customer-receipt-1',
      type: 'customer_receipt',
      debitAccount: 'system:cash',
      creditAccount: 'system:receivables',
      amountPaise: 20000,
      partyId: customer.id,
    );

    expect(
      service.balancePaise(
        party: customer,
        transactions: transactions.values,
        postings: postings.values,
      ),
      30000,
    );
    await expectLater(
      service.archiveParty(
        partyId: customer.id,
        transactions: transactions.values,
        postings: postings.values,
      ),
      throwsA(isA<FinancePartyException>()),
    );

    await post(
      id: 'customer-receipt-2',
      type: 'customer_receipt',
      debitAccount: 'system:cash',
      creditAccount: 'system:receivables',
      amountPaise: 30000,
      partyId: customer.id,
    );
    expect(
      service.balancePaise(
        party: customer,
        transactions: transactions.values,
        postings: postings.values,
      ),
      0,
    );
    await service.archiveParty(
      partyId: customer.id,
      transactions: transactions.values,
      postings: postings.values,
    );
    expect(parties.get(customer.id)!.active, isFalse);
  });

  test('tracks supplier payables and partial supplier payments', () async {
    final supplier = await service.saveParty(
      id: 'supplier-1',
      name: 'Supply House',
      partyType: 'supplier',
    );
    await post(
      id: 'supplier-bill',
      type: 'expense',
      debitAccount: 'system:operating-expense',
      creditAccount: 'system:payables',
      amountPaise: 60000,
      partyId: supplier.id,
    );
    await post(
      id: 'supplier-payment',
      type: 'supplier_payment',
      debitAccount: 'system:payables',
      creditAccount: 'system:cash',
      amountPaise: 25000,
      partyId: supplier.id,
    );
    expect(
      service.balancePaise(
        party: supplier,
        transactions: transactions.values,
        postings: postings.values,
      ),
      35000,
    );
  });

  test('ledger rejects a supplier party on a receivable posting', () async {
    final supplier = await service.saveParty(
      id: 'wrong-party',
      name: 'Wrong party',
      partyType: 'supplier',
    );
    await expectLater(
      post(
        id: 'wrong-receivable-party',
        type: 'income',
        debitAccount: 'system:receivables',
        creditAccount: 'system:sales-income',
        amountPaise: 10000,
        partyId: supplier.id,
      ),
      throwsA(isA<FinanceLedgerException>()),
    );
    expect(transactions.isEmpty, isTrue);
    expect(postings.isEmpty, isTrue);
  });

  test('rejects duplicate parties and reserved employee party type', () async {
    await service.saveParty(
      id: 'customer-one',
      name: 'Contoso',
      partyType: 'customer',
    );
    await expectLater(
      service.saveParty(name: 'contoso', partyType: 'customer'),
      throwsA(isA<FinancePartyException>()),
    );
    await expectLater(
      service.saveParty(name: 'Employee', partyType: 'employee'),
      throwsA(isA<FinancePartyException>()),
    );
  });
}
