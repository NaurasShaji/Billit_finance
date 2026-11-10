import 'dart:io';

import 'package:billit/models/models.dart';
import 'package:billit/services/boxes.dart';
import 'package:billit/services/finance_ledger_service.dart';
import 'package:billit/services/finance_schema_migration.dart';
import 'package:billit/services/schema_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDirectory;
  late Box<dynamic> settings;
  late Box<FinanceAccount> accounts;
  late Box<FinanceTransaction> transactions;
  late Box<FinancePosting> postings;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('billit_finance_test');
    Hive.init(tempDirectory.path);
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
    settings = await Hive.openBox<dynamic>('app_settings');
    await SchemaMigrationService(
      currentVersion: 2,
      migrations: [FinanceSchemaMigration.versionOneToTwo],
    ).run(settings);
    accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    transactions =
        Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    postings = Hive.box<FinancePosting>(Boxes.financePostings);
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  FinanceTransaction transaction({
    String id = 'txn-1',
    String sourceId = 'source-1',
  }) =>
      FinanceTransaction(
        id: id,
        transactionNumber: id.toUpperCase(),
        transactionType: 'expense',
        sourceType: 'manual',
        sourceId: sourceId,
      );

  List<FinancePosting> balancedLines(String transactionId) => [
        FinancePosting(
          id: '$transactionId-debit',
          transactionId: transactionId,
          accountId: 'system:operating-expense',
          debitPaise: 12550,
        ),
        FinancePosting(
          id: '$transactionId-credit',
          transactionId: transactionId,
          accountId: 'system:cash',
          creditPaise: 12550,
        ),
      ];

  test('schema v2 creates finance boxes and stable default accounts', () async {
    expect(settings.get(SchemaMigrationService.versionKey), 2);
    expect(accounts.get('system:cash')!.accountType, 'asset');
    expect(accounts.get('system:operating-expense')!.accountType, 'expense');
    expect(accounts.length, 9);

    await SchemaMigrationService(
      currentVersion: 2,
      migrations: [FinanceSchemaMigration.versionOneToTwo],
    ).run(settings);
    expect(accounts.length, 9);
  });

  test('posts balanced integer-paise journal and derives account balances',
      () async {
    final service = FinanceLedgerService();
    final entry = transaction();

    await service.postTransaction(
      transaction: entry,
      postings: balancedLines(entry.id),
      accountsBox: accounts,
      transactionsBox: transactions,
      postingsBox: postings,
    );

    expect(transactions.get(entry.id)!.status, 'posted');
    expect(transactions.get(entry.id)!.postedAt, isNotNull);
    expect(postings.length, 2);
    expect(
      service.balancePaise(
        accountId: 'system:operating-expense',
        transactionsBox: transactions,
        postingsBox: postings,
      ),
      12550,
    );
    expect(
      service.balancePaise(
        accountId: 'system:cash',
        transactionsBox: transactions,
        postingsBox: postings,
      ),
      -12550,
    );
  });

  test('reverses a posted entry without mutating its original', () async {
    final service = FinanceLedgerService();
    final original = transaction();
    await service.postTransaction(
      transaction: original,
      postings: balancedLines(original.id),
      accountsBox: accounts,
      transactionsBox: transactions,
      postingsBox: postings,
    );

    await service.reverseTransaction(
      originalTransactionId: original.id,
      reversalId: 'txn-reversal',
      reversalNumber: 'TXN-REV-1',
      reversalDate: DateTime(2026, 1, 4),
      accountsBox: accounts,
      transactionsBox: transactions,
      postingsBox: postings,
    );

    expect(transactions.get(original.id)!.status, 'posted');
    expect(
      transactions.get('txn-reversal')!.reversedTransactionId,
      original.id,
    );
    expect(
      service.balancePaise(
        accountId: 'system:operating-expense',
        transactionsBox: transactions,
        postingsBox: postings,
      ),
      0,
    );
    expect(
      service.balancePaise(
        accountId: 'system:cash',
        transactionsBox: transactions,
        postingsBox: postings,
      ),
      0,
    );
  });

  test('rejects unbalanced entries without writing anything', () async {
    final entry = transaction();
    final lines = balancedLines(entry.id);
    lines[1].creditPaise = 12549;

    await expectLater(
      FinanceLedgerService().postTransaction(
        transaction: entry,
        postings: lines,
        accountsBox: accounts,
        transactionsBox: transactions,
        postingsBox: postings,
      ),
      throwsA(isA<FinanceLedgerException>()),
    );
    expect(transactions.isEmpty, isTrue);
    expect(postings.isEmpty, isTrue);
  });

  test('rejects duplicate source records and duplicate transaction IDs',
      () async {
    final service = FinanceLedgerService();
    final first = transaction();
    await service.postTransaction(
      transaction: first,
      postings: balancedLines(first.id),
      accountsBox: accounts,
      transactionsBox: transactions,
      postingsBox: postings,
    );

    await expectLater(
      service.postTransaction(
        transaction: transaction(id: 'txn-2'),
        postings: balancedLines('txn-2'),
        accountsBox: accounts,
        transactionsBox: transactions,
        postingsBox: postings,
      ),
      throwsA(isA<FinanceLedgerException>()),
    );
    await expectLater(
      service.postTransaction(
        transaction: transaction(id: 'txn-1', sourceId: 'different-source'),
        postings: balancedLines('txn-1'),
        accountsBox: accounts,
        transactionsBox: transactions,
        postingsBox: postings,
      ),
      throwsA(isA<FinanceLedgerException>()),
    );
    expect(transactions.length, 1);
    expect(postings.length, 2);
  });

  test('draft transaction postings do not affect account balances', () async {
    final entry = transaction()..status = 'draft';
    await transactions.put(entry.id, entry);
    await postings.putAll({
      'draft-debit': FinancePosting(
        id: 'draft-debit',
        transactionId: entry.id,
        accountId: 'system:operating-expense',
        debitPaise: 900,
      ),
      'draft-credit': FinancePosting(
        id: 'draft-credit',
        transactionId: entry.id,
        accountId: 'system:cash',
        creditPaise: 900,
      ),
    });

    expect(
      FinanceLedgerService().balancePaise(
        accountId: 'system:operating-expense',
        transactionsBox: transactions,
        postingsBox: postings,
      ),
      0,
    );
  });
}
