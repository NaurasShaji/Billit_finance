import 'package:hive_ce/hive_ce.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'boxes.dart';

class FinanceBankReconciliationException implements Exception {
  const FinanceBankReconciliationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Stores imported bank statement lines and their immutable match history in
/// app settings, avoiding a new Hive adapter while remaining in Google Drive backups.
class FinanceBankReconciliationService {
  static const storageKey = 'finance_bank_statement_lines';

  Box<dynamic> get _settings => Hive.box<dynamic>('app_settings');

  List<Map<String, dynamic>> lines({String? accountId}) {
    final raw = _settings.get(storageKey);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .where((entry) =>
            accountId == null || entry['accountId'] == accountId)
        .toList()
      ..sort((a, b) => DateTime.parse(b['date'] as String)
          .compareTo(DateTime.parse(a['date'] as String)));
  }

  String _fingerprint(String value) {
    var hash = 2166136261;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  List<List<String>> _parseCsv(String source) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (char == '"') {
        if (quoted && i + 1 < source.length && source[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        row.add(field.toString().trim());
        field.clear();
      } else if ((char == '\n' || char == '\r') && !quoted) {
        if (char == '\r' && i + 1 < source.length && source[i + 1] == '\n') {
          i++;
        }
        row.add(field.toString().trim());
        field.clear();
        if (row.any((value) => value.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        field.write(char);
      }
    }
    row.add(field.toString().trim());
    if (row.any((value) => value.isNotEmpty)) rows.add(row);
    if (quoted) {
      throw const FinanceBankReconciliationException(
        'The CSV contains an unterminated quoted field.',
      );
    }
    return rows;
  }

  DateTime _parseDate(String value) {
    final iso = DateTime.tryParse(value);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    for (final separator in ['/', '-']) {
      final parts = value.split(separator);
      if (parts.length != 3) continue;
      final first = int.tryParse(parts[0]);
      final second = int.tryParse(parts[1]);
      final third = int.tryParse(parts[2]);
      if (first == null || second == null || third == null) continue;
      final day = first > 31 ? third : first;
      final month = second;
      final year = first > 31 ? first : third;
      if (year < 100 || month < 1 || month > 12 || day < 1 || day > 31) {
        continue;
      }
      final date = DateTime(year, month, day);
      if (date.year == year && date.month == month && date.day == day) {
        return date;
      }
    }
    throw FinanceBankReconciliationException('Invalid statement date: $value');
  }

  int _parsePaise(String value) {
    final cleaned = value.replaceAll(',', '').replaceAll('₹', '').trim();
    if (cleaned.isEmpty) return 0;
    final amount = double.tryParse(cleaned);
    if (amount == null || !amount.isFinite) {
      throw FinanceBankReconciliationException('Invalid statement amount: $value');
    }
    return (amount * 100).round();
  }

  Future<int> importCsv({
    required String accountId,
    required String csvText,
  }) async {
    final account = Hive.box<FinanceAccount>(Boxes.financeAccounts).get(accountId);
    if (account == null || !account.active ||
        account.accountType != 'asset' || account.currencyCode != 'INR') {
      throw const FinanceBankReconciliationException(
        'Select an active INR asset account.',
      );
    }
    final rows = _parseCsv(csvText);
    if (rows.length < 2) {
      throw const FinanceBankReconciliationException(
        'The CSV must contain a header and at least one statement row.',
      );
    }
    final headers = rows.first
        .map((value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .toList();
    int column(List<String> names) =>
        headers.indexWhere((header) => names.contains(header));
    final dateColumn = column(['date', 'transactiondate', 'valuedate']);
    final descriptionColumn = column(['description', 'narration', 'details', 'particulars']);
    final referenceColumn = column(['reference', 'ref', 'referenceno', 'chequeno', 'utr']);
    final debitColumn = column(['debit', 'withdrawal', 'withdrawals', 'paidout']);
    final creditColumn = column(['credit', 'deposit', 'deposits', 'paidin']);
    final amountColumn = column(['amount', 'transactionamount']);
    if (dateColumn < 0 || (debitColumn < 0 && creditColumn < 0 && amountColumn < 0)) {
      throw const FinanceBankReconciliationException(
        'CSV headers must include Date and either Amount or Debit/Credit columns.',
      );
    }

    final fingerprint = _fingerprint(csvText);
    final existing = _settings.get(storageKey);
    final stored = existing is List
        ? existing.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    if (stored.any((line) => line['accountId'] == accountId &&
        line['batchFingerprint'] == fingerprint)) {
      throw const FinanceBankReconciliationException(
        'This statement file has already been imported for the selected account.',
      );
    }

    final batchId = const Uuid().v4();
    final imported = <Map<String, dynamic>>[];
    for (var index = 1; index < rows.length; index++) {
      final row = rows[index];
      String cell(int columnIndex) =>
          columnIndex >= 0 && columnIndex < row.length ? row[columnIndex] : '';
      final dateValue = cell(dateColumn);
      if (dateValue.isEmpty) continue;
      final debit = debitColumn >= 0 ? _parsePaise(cell(debitColumn)) : 0;
      final credit = creditColumn >= 0 ? _parsePaise(cell(creditColumn)) : 0;
      if (debit > 0 && credit > 0) {
        throw FinanceBankReconciliationException(
          'Statement row ${index + 1} contains both debit and credit values.',
        );
      }
      final signedAmount = debitColumn >= 0 || creditColumn >= 0
          ? credit - debit
          : _parsePaise(cell(amountColumn));
      if (signedAmount == 0) continue;
      imported.add({
        'id': const Uuid().v4(),
        'batchId': batchId,
        'batchFingerprint': fingerprint,
        'accountId': accountId,
        'date': _parseDate(dateValue).toIso8601String(),
        'description': cell(descriptionColumn),
        'reference': cell(referenceColumn),
        'amountPaise': signedAmount,
        'status': 'unmatched',
        'matchedTransactionId': null,
        'matchedPostingId': null,
        'matchHistory': <dynamic>[],
      });
    }
    if (imported.isEmpty) {
      throw const FinanceBankReconciliationException(
        'No non-zero statement transactions were found in the CSV.',
      );
    }
    await _settings.put(storageKey, [...stored, ...imported]);

    // Auto-match only when one exact amount/direction candidate exists within
    // five days. Ambiguous or unmatched rows remain available for manual review.
    for (final line in imported) {
      final candidates = candidatePostings(
        line,
        maxDateDifferenceDays: 5,
      );
      if (candidates.length == 1) {
        try {
          await match(
            statementLineId: line['id'] as String,
            transactionId: candidates.single.transaction.id,
            postingId: candidates.single.posting.id,
            automatic: true,
          );
        } catch (_) {
          // Keep the imported line unmatched if another operation claimed it.
        }
      }
    }
    return imported.length;
  }

  Future<void> match({
    required String statementLineId,
    required String transactionId,
    required String postingId,
    bool automatic = false,
  }) async {
    final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    final postings = Hive.box<FinancePosting>(Boxes.financePostings);
    final stored = lines();
    final index = stored.indexWhere((line) => line['id'] == statementLineId);
    if (index < 0) {
      throw const FinanceBankReconciliationException('Statement line not found.');
    }
    final line = stored[index];
    if (line['status'] == 'matched') {
      throw const FinanceBankReconciliationException('Statement line is already matched.');
    }
    final transaction = transactions.get(transactionId);
    final posting = postings.get(postingId);
    if (transaction == null || transaction.status != 'posted' ||
        posting == null || posting.transactionId != transactionId ||
        posting.accountId != line['accountId']) {
      throw const FinanceBankReconciliationException(
        'Select a posted ledger entry on the same bank account.',
      );
    }
    final amount = line['amountPaise'];
    if (amount is! int ||
        posting.debitPaise - posting.creditPaise != amount) {
      throw const FinanceBankReconciliationException(
        'Statement and ledger amounts or directions do not match exactly.',
      );
    }
    final usedPostingIds = stored
        .where((entry) => entry['status'] == 'matched' &&
            entry['matchedPostingId'] != null)
        .map((entry) => entry['matchedPostingId'].toString())
        .toSet();
    if (usedPostingIds.contains(postingId)) {
      throw const FinanceBankReconciliationException(
        'This ledger posting is already matched to another statement line.',
      );
    }
    final history = line['matchHistory'] is List
        ? List<dynamic>.from(line['matchHistory'] as List)
        : <dynamic>[];
    history.add({
      'action': automatic ? 'auto_matched' : 'matched',
      'transactionId': transactionId,
      'postingId': postingId,
      'at': DateTime.now().toIso8601String(),
    });
    line
      ..['status'] = 'matched'
      ..['matchedTransactionId'] = transactionId
      ..['matchedPostingId'] = postingId
      ..['matchedAt'] = DateTime.now().toIso8601String()
      ..['matchHistory'] = history;
    await _settings.put(storageKey, [
      for (final entry in stored)
        if (entry['id'] == statementLineId) line else entry,
    ]);
  }

  Future<void> unmatch(String statementLineId) async {
    final stored = lines();
    final index = stored.indexWhere((line) => line['id'] == statementLineId);
    if (index < 0) {
      throw const FinanceBankReconciliationException('Statement line not found.');
    }
    final line = stored[index];
    if (line['status'] != 'matched') {
      throw const FinanceBankReconciliationException('Statement line is not matched.');
    }
    final history = line['matchHistory'] is List
        ? List<dynamic>.from(line['matchHistory'] as List)
        : <dynamic>[];
    history.add({
      'action': 'unmatched',
      'transactionId': line['matchedTransactionId'],
      'postingId': line['matchedPostingId'],
      'at': DateTime.now().toIso8601String(),
    });
    line
      ..['status'] = 'unmatched'
      ..['matchedTransactionId'] = null
      ..['matchedPostingId'] = null
      ..['matchedAt'] = null
      ..['matchHistory'] = history;
    await _settings.put(storageKey, [
      for (final entry in stored)
        if (entry['id'] == statementLineId) line else entry,
    ]);
  }

  List<({FinanceTransaction transaction, FinancePosting posting})>
      candidatePostings(
    Map<String, dynamic> line, {
    int? maxDateDifferenceDays,
  }) {
    final date = DateTime.parse(line['date'] as String);
    final amount = line['amountPaise'] as int;
    final matched = lines()
        .where((entry) => entry['status'] == 'matched')
        .map((entry) => entry['matchedPostingId']?.toString())
        .whereType<String>()
        .toSet();
    final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    final candidates =
        <({FinanceTransaction transaction, FinancePosting posting})>[];
    for (final posting in Hive.box<FinancePosting>(Boxes.financePostings).values) {
      if (posting.accountId != line['accountId'] ||
          posting.debitPaise - posting.creditPaise != amount ||
          matched.contains(posting.id)) {
        continue;
      }
      final transaction = transactions.get(posting.transactionId);
      if (transaction == null || transaction.status != 'posted') {
        continue;
      }
      if (maxDateDifferenceDays != null &&
          transaction.date.difference(date).inDays.abs() >
              maxDateDifferenceDays) {
        continue;
      }
      candidates.add((transaction: transaction, posting: posting));
    }
    return candidates
      ..sort((a, b) =>
          a.transaction.date.difference(date).inDays.abs().compareTo(
            b.transaction.date.difference(date).inDays.abs(),
          ));
  }
}
