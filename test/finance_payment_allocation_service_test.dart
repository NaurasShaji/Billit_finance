import 'dart:io';

import 'package:billit/models/models.dart';
import 'package:billit/services/boxes.dart';
import 'package:billit/services/finance_ledger_service.dart';
import 'package:billit/services/finance_payment_allocation_service.dart';
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
  late Box<Map> allocations;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('billit_allocations');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(FinanceAccountAdapter());
    if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(FinanceTransactionAdapter());
    if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(FinancePostingAdapter());
    if (!Hive.isAdapterRegistered(13)) Hive.registerAdapter(FinanceCategoryAdapter());
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(FinancePartyAdapter());
    settings = await Hive.openBox<dynamic>('settings');
    await SchemaMigrationService(
      currentVersion: 2,
      migrations: [FinanceSchemaMigration.versionOneToTwo],
    ).run(settings);
    await settings.put(SchemaMigrationService.versionKey, 7);
    await SchemaMigrationService(
      currentVersion: 8,
      migrations: [FinanceSchemaMigration.versionSevenToEight],
    ).run(settings);
    accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    postings = Hive.box<FinancePosting>(Boxes.financePostings);
    parties = Hive.box<FinanceParty>(Boxes.financeParties);
    allocations = Hive.box<Map>(Boxes.financePaymentAllocations);
    await parties.put('customer-1', FinanceParty(
      id: 'customer-1', name: 'Customer One', partyType: 'customer',
    ));
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> postInvoice() async {
    const id = 'invoice-1';
    await FinanceLedgerService().postTransaction(
      transaction: FinanceTransaction(
        id: id, transactionNumber: 'INV-1', transactionType: 'income',
        date: DateTime(2026, 1, 1), sourceType: 'test', sourceId: id,
      ),
      postings: [
        FinancePosting(
          id: '$id:ar', transactionId: id,
          accountId: 'system:receivables', debitPaise: 10000,
          partyId: 'customer-1',
        ),
        FinancePosting(
          id: '$id:sales', transactionId: id,
          accountId: 'system:sales-income', creditPaise: 10000,
        ),
      ],
      accountsBox: accounts, transactionsBox: transactions,
      postingsBox: postings, partiesBox: parties,
    );
  }

  Future<void> postReceipt() async {
    const id = 'receipt-1';
    await FinanceLedgerService().postTransaction(
      transaction: FinanceTransaction(
        id: id, transactionNumber: 'REC-1', transactionType: 'customer_receipt',
        date: DateTime(2026, 1, 2), sourceType: 'test', sourceId: id,
      ),
      postings: [
        FinancePosting(
          id: '$id:cash', transactionId: id,
          accountId: 'system:cash', debitPaise: 8000,
        ),
        FinancePosting(
          id: '$id:ar', transactionId: id,
          accountId: 'system:receivables', creditPaise: 8000,
          partyId: 'customer-1',
        ),
      ],
      accountsBox: accounts, transactionsBox: transactions,
      postingsBox: postings, partiesBox: parties,
    );
  }

  test('persists partial invoice allocation and calculates remaining balances', () async {
    await postInvoice();
    await postReceipt();
    final service = FinancePaymentAllocationService();
    await service.allocate(
      id: 'allocation-1',
      settlementTransactionId: 'receipt-1',
      invoiceTransactionId: 'invoice-1',
      partyId: 'customer-1',
      amountPaise: 5000,
      partyType: 'customer',
      transactions: transactions.values,
      postings: postings.values,
    );

    expect(service.allocatedToInvoice('invoice-1', transactions: transactions.values), 5000);
    expect(service.allocatedFromSettlement('receipt-1', transactions: transactions.values), 5000);
    expect(allocations.length, 1);
  });

  test('reversing a settlement makes its allocations ineffective but preserves history', () async {
    await postInvoice();
    await postReceipt();
    final service = FinancePaymentAllocationService();
    await service.allocate(
      id: 'allocation-reversal',
      settlementTransactionId: 'receipt-1',
      invoiceTransactionId: 'invoice-1',
      partyId: 'customer-1',
      amountPaise: 4000,
      partyType: 'customer',
      transactions: transactions.values,
      postings: postings.values,
    );
    await FinanceLedgerService().reverseTransaction(
      originalTransactionId: 'receipt-1',
      reversalId: 'receipt-reversal',
      reversalNumber: 'REC-REV-1',
      reversalDate: DateTime(2026, 1, 3),
      accountsBox: accounts,
      transactionsBox: transactions,
      postingsBox: postings,
      partiesBox: parties,
    );

    expect(allocations.length, 1);
    expect(service.allocatedFromSettlement(
      'receipt-1', transactions: transactions.values,
    ), 0);
    expect(service.allocatedToInvoice(
      'invoice-1', transactions: transactions.values,
    ), 0);
  });

  test('rejects invoice and settlement over-allocation', () async {
    await postInvoice();
    await postReceipt();
    final service = FinancePaymentAllocationService();
    await service.allocate(
      id: 'allocation-1',
      settlementTransactionId: 'receipt-1',
      invoiceTransactionId: 'invoice-1',
      partyId: 'customer-1',
      amountPaise: 8000,
      partyType: 'customer',
      transactions: transactions.values,
      postings: postings.values,
    );
    await expectLater(
      service.allocate(
        id: 'allocation-2',
        settlementTransactionId: 'receipt-1',
        invoiceTransactionId: 'invoice-1',
        partyId: 'customer-1',
        amountPaise: 1,
        partyType: 'customer',
        transactions: transactions.values,
        postings: postings.values,
      ),
      throwsA(isA<FinanceAllocationException>()),
    );
    expect(allocations.length, 1);
  });
}
