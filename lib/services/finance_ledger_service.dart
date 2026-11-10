import 'package:hive_ce/hive_ce.dart';

import '../models/models.dart';

class FinanceLedgerException implements Exception {
  final String message;
  const FinanceLedgerException(this.message);

  @override
  String toString() => 'FinanceLedgerException: $message';
}

/// Posting and balance operations for the append-only finance journal.
class FinanceLedgerService {
  static const _accountTypes = {
    'asset',
    'liability',
    'equity',
    'income',
    'expense',
  };

  static const _transactionTypes = {
    'income',
    'expense',
    'transfer',
    'customer_receipt',
    'supplier_payment',
    'opening_balance',
    'adjustment',
    'reversal',
  };

  /// Validates the complete journal entry without writing to Hive.
  static void validateJournal({
    required FinanceTransaction transaction,
    required List<FinancePosting> postings,
    required Map<String, FinanceAccount> accounts,
  }) {
    if (transaction.id.trim().isEmpty ||
        transaction.transactionNumber.trim().isEmpty) {
      throw const FinanceLedgerException(
        'Transaction ID and transaction number are required.',
      );
    }
    if (!_transactionTypes.contains(transaction.transactionType)) {
      throw FinanceLedgerException(
        'Unsupported transaction type: ${transaction.transactionType}',
      );
    }
    if (transaction.status != 'draft') {
      throw const FinanceLedgerException(
        'Only draft transactions can be posted.',
      );
    }
    if (postings.length < 2) {
      throw const FinanceLedgerException(
        'A journal entry requires at least two posting lines.',
      );
    }

    final lineIds = <String>{};
    var totalDebits = 0;
    var totalCredits = 0;
    String? journalCurrency;

    for (final line in postings) {
      if (line.id.trim().isEmpty || !lineIds.add(line.id)) {
        throw const FinanceLedgerException(
          'Posting IDs must be non-empty and unique within a transaction.',
        );
      }
      if (line.transactionId != transaction.id) {
        throw const FinanceLedgerException(
          'Every posting must reference the transaction being posted.',
        );
      }
      final account = accounts[line.accountId];
      if (account == null) {
        throw FinanceLedgerException(
          'Posting references an unknown account: ${line.accountId}',
        );
      }
      if (account.currencyCode != 'INR') {
        throw FinanceLedgerException(
          'Only INR accounts are supported by the paise ledger: ${line.accountId}',
        );
      }
      journalCurrency ??= account.currencyCode;
      if (journalCurrency != account.currencyCode) {
        throw const FinanceLedgerException(
          'A journal entry cannot mix currencies.',
        );
      }
      if (!account.active && transaction.transactionType != 'reversal') {
        throw FinanceLedgerException(
          'Posting references an inactive account: ${line.accountId}',
        );
      }
      if (!_accountTypes.contains(account.accountType)) {
        throw FinanceLedgerException(
          'Account ${line.accountId} has an unsupported account type.',
        );
      }
      if (line.debitPaise < 0 || line.creditPaise < 0) {
        throw const FinanceLedgerException(
          'Posting amounts cannot be negative.',
        );
      }
      final hasDebit = line.debitPaise > 0;
      final hasCredit = line.creditPaise > 0;
      if (hasDebit == hasCredit) {
        throw const FinanceLedgerException(
          'Each posting must contain either a debit or a credit, not both.',
        );
      }
      totalDebits += line.debitPaise;
      totalCredits += line.creditPaise;
    }

    final debitLines = postings.where((line) => line.debitPaise > 0);
    final creditLines = postings.where((line) => line.creditPaise > 0);
    bool allAccountsMatch(
      Iterable<FinancePosting> lines,
      bool Function(FinanceAccount) predicate,
    ) =>
        lines.every((line) => predicate(accounts[line.accountId]!));

    final validAccountMapping = switch (transaction.transactionType) {
      'income' =>
        allAccountsMatch(debitLines, (account) => account.accountType == 'asset') &&
            allAccountsMatch(
              creditLines,
              (account) =>
                  account.accountType == 'income' ||
                  account.accountType == 'liability',
            ),
      'expense' =>
        allAccountsMatch(
          debitLines,
          (account) => account.accountType == 'expense',
        ) &&
            allAccountsMatch(
              creditLines,
              (account) =>
                  account.accountType == 'asset' ||
                  account.accountType == 'liability',
            ),
      'transfer' =>
        allAccountsMatch(debitLines, (account) => account.accountType == 'asset') &&
            allAccountsMatch(creditLines, (account) => account.accountType == 'asset'),
      'customer_receipt' =>
        allAccountsMatch(debitLines, (account) => account.accountType == 'asset') &&
            creditLines.every((line) => line.accountId == 'system:receivables'),
      'supplier_payment' =>
        debitLines.every((line) => line.accountId == 'system:payables') &&
            allAccountsMatch(creditLines, (account) => account.accountType == 'asset'),
      _ => true,
    };
    if (!validAccountMapping) {
      throw FinanceLedgerException(
        'Posting accounts do not match transaction type ${transaction.transactionType}.',
      );
    }

    if (totalDebits <= 0 || totalDebits != totalCredits) {
      throw FinanceLedgerException(
        'Journal entry is unbalanced: debits=$totalDebits paise, '
        'credits=$totalCredits paise.',
      );
    }
  }

  /// Persists postings first and marks the transaction posted last.
  ///
  /// Hive cannot atomically commit across boxes. If a write fails, newly
  /// inserted postings are removed on a best-effort basis. The transaction
  /// header is written only after every posting succeeds.
  Future<void> postTransaction({
    required FinanceTransaction transaction,
    required List<FinancePosting> postings,
    required Box<FinanceAccount> accountsBox,
    required Box<FinanceTransaction> transactionsBox,
    required Box<FinancePosting> postingsBox,
    Box<FinanceCategory>? categoriesBox,
    Box<FinanceParty>? partiesBox,
  }) async {
    if (transactionsBox.containsKey(transaction.id)) {
      throw const FinanceLedgerException(
        'Transaction ID already exists; posted history cannot be overwritten.',
      );
    }
    if (transaction.sourceType.isNotEmpty && transaction.sourceId.isNotEmpty) {
      final duplicateSource = transactionsBox.values.any(
        (existing) =>
            existing.sourceType == transaction.sourceType &&
            existing.sourceId == transaction.sourceId,
      );
      if (duplicateSource) {
        throw const FinanceLedgerException(
          'This source record has already been posted.',
        );
      }
    }

    if (transactionsBox.values.any(
      (existing) =>
          existing.transactionNumber == transaction.transactionNumber,
    )) {
      throw const FinanceLedgerException(
        'Transaction number already exists.',
      );
    }

    final accounts = {
      for (final account in accountsBox.values) account.id: account,
    };
    validateJournal(
      transaction: transaction,
      postings: postings,
      accounts: accounts,
    );

    for (final line in postings) {
      if (line.categoryId != null) {
        if (categoriesBox == null) {
          throw const FinanceLedgerException(
            'Category storage is required when a posting references a category.',
          );
        }
        final category = categoriesBox.get(line.categoryId);
        if (category == null ||
            (!category.active && transaction.transactionType != 'reversal')) {
          throw FinanceLedgerException(
            'Posting references an unknown or inactive category: ${line.categoryId}',
          );
        }
        final account = accounts[line.accountId]!;
        if (category.accountId != line.accountId ||
            category.kind != account.accountType) {
          throw FinanceLedgerException(
            'Category ${category.id} does not match posting account ${line.accountId}.',
          );
        }
      }
      final requiresCustomer =
          line.accountId == 'system:receivables';
      final requiresSupplier =
          line.accountId == 'system:payables';
      if ((requiresCustomer || requiresSupplier) && line.partyId == null) {
        throw FinanceLedgerException(
          'Posting to ${line.accountId} requires a customer or supplier party.',
        );
      }
      if (line.partyId != null) {
        if (partiesBox == null) {
          throw const FinanceLedgerException(
            'Party storage is required when a posting references a party.',
          );
        }
        final party = partiesBox.get(line.partyId);
        if (party == null ||
            (!party.active && transaction.transactionType != 'reversal')) {
          throw FinanceLedgerException(
            'Posting references an unknown or inactive party: ${line.partyId}',
          );
        }
        if (requiresCustomer && party.partyType != 'customer') {
          throw FinanceLedgerException(
            'Accounts receivable postings require a customer party.',
          );
        }
        if (requiresSupplier && party.partyType != 'supplier') {
          throw FinanceLedgerException(
            'Accounts payable postings require a supplier party.',
          );
        }
      }
      if (postingsBox.containsKey(line.id)) {
        throw FinanceLedgerException(
          'Posting ID already exists: ${line.id}',
        );
      }
    }

    final postedTransaction = FinanceTransaction(
      id: transaction.id,
      transactionNumber: transaction.transactionNumber,
      transactionType: transaction.transactionType,
      status: 'posted',
      date: transaction.date,
      memo: transaction.memo,
      reference: transaction.reference,
      sourceType: transaction.sourceType,
      sourceId: transaction.sourceId,
      createdAt: transaction.createdAt,
      postedAt: DateTime.now(),
      reversedTransactionId: transaction.reversedTransactionId,
      dueDate: transaction.dueDate,
    );
    final insertedIds = <String>[];
    try {
      for (final line in postings) {
        insertedIds.add(line.id);
        await postingsBox.put(line.id, line);
      }
      await transactionsBox.put(transaction.id, postedTransaction);
    } catch (_) {
      try {
        await transactionsBox.delete(transaction.id);
      } catch (_) {
        // Preserve the original write error; cleanup is best effort.
      }
      for (final id in insertedIds.reversed) {
        try {
          await postingsBox.delete(id);
        } catch (_) {
          // Preserve the original write error; cleanup is best effort.
        }
      }
      rethrow;
    }
  }

  /// Posts an exact opposite entry without modifying the original posted record.
  Future<void> reverseTransaction({
    required String originalTransactionId,
    required String reversalId,
    required String reversalNumber,
    required DateTime reversalDate,
    required Box<FinanceAccount> accountsBox,
    required Box<FinanceTransaction> transactionsBox,
    required Box<FinancePosting> postingsBox,
    Box<FinanceCategory>? categoriesBox,
    Box<FinanceParty>? partiesBox,
    String memo = '',
  }) async {
    final original = transactionsBox.get(originalTransactionId);
    if (original == null || original.status != 'posted') {
      throw const FinanceLedgerException(
        'Only an existing posted transaction can be reversed.',
      );
    }
    final originalLines = postingsBox.values
        .where((line) => line.transactionId == originalTransactionId)
        .toList();
    if (originalLines.length < 2) {
      throw const FinanceLedgerException(
        'The original transaction has no complete journal entry to reverse.',
      );
    }

    final reversal = FinanceTransaction(
      id: reversalId,
      transactionNumber: reversalNumber,
      transactionType: 'reversal',
      date: reversalDate,
      memo: memo.isEmpty ? 'Reversal of ${original.transactionNumber}' : memo,
      reference: original.transactionNumber,
      sourceType: 'reversal',
      sourceId: original.id,
      reversedTransactionId: original.id,
    );
    final reversalLines = originalLines
        .map(
          (line) => FinancePosting(
            id: '$reversalId:${line.id}',
            transactionId: reversalId,
            accountId: line.accountId,
            debitPaise: line.creditPaise,
            creditPaise: line.debitPaise,
            partyId: line.partyId,
            categoryId: line.categoryId,
            memo: line.memo,
          ),
        )
        .toList();

    await postTransaction(
      transaction: reversal,
      postings: reversalLines,
      accountsBox: accountsBox,
      transactionsBox: transactionsBox,
      postingsBox: postingsBox,
      categoriesBox: categoriesBox,
      partiesBox: partiesBox,
    );
  }

  /// Returns the raw debit-minus-credit balance in paise for an account.
  /// Only postings belonging to posted transactions are included.
  int balancePaise({
    required String accountId,
    required Box<FinanceTransaction> transactionsBox,
    required Box<FinancePosting> postingsBox,
  }) {
    final postedIds = transactionsBox.values
        .where((transaction) => transaction.status == 'posted')
        .map((transaction) => transaction.id)
        .toSet();

    var balance = 0;
    for (final line in postingsBox.values) {
      if (line.accountId == accountId &&
          postedIds.contains(line.transactionId)) {
        balance += line.debitPaise - line.creditPaise;
      }
    }
    return balance;
  }
}
