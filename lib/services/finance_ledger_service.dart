import 'package:hive/hive.dart';

import '../models/models.dart';

class FinanceLedgerException implements Exception {
  final String message;
  const FinanceLedgerException(this.message);

  @override
  String toString() => 'FinanceLedgerException: $message';
}

/// Posting and balance operations for the append-only finance journal.
class FinanceLedgerService {
  static const _transactionTypes = {
    'income',
    'expense',
    'transfer',
    'opening_balance',
    'adjustment',
    'reversal',
  };

  /// Validates the complete journal entry without writing to Hive.
  static void validateJournal({
    required FinanceTransaction transaction,
    required List<FinancePosting> postings,
    required Set<String> accountIds,
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
      if (!accountIds.contains(line.accountId)) {
        throw FinanceLedgerException(
          'Posting references an unknown account: ${line.accountId}',
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

    validateJournal(
      transaction: transaction,
      postings: postings,
      accountIds: accountsBox.values.map((account) => account.id).toSet(),
    );

    for (final line in postings) {
      if (postingsBox.containsKey(line.id)) {
        throw FinanceLedgerException(
          'Posting ID already exists: ${line.id}',
        );
      }
    }

    final insertedIds = <String>[];
    try {
      for (final line in postings) {
        await postingsBox.put(line.id, line);
        insertedIds.add(line.id);
      }
      transaction
        ..status = 'posted'
        ..postedAt = DateTime.now();
      await transactionsBox.put(transaction.id, transaction);
    } catch (_) {
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
