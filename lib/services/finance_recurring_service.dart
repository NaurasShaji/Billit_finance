import 'package:hive_ce/hive_ce.dart';

import '../models/models.dart';
import 'boxes.dart';
import 'finance_ledger_service.dart';

class FinanceRecurringException implements Exception {
  const FinanceRecurringException(this.message);
  final String message;

  @override
  String toString() => 'FinanceRecurringException: $message';
}

class FinanceRecurringProcessResult {
  const FinanceRecurringProcessResult({
    required this.postedCount,
    required this.skippedCount,
    required this.issues,
  });

  final int postedCount;
  final int skippedCount;
  final List<String> issues;
}

class FinanceRecurringService {
  FinanceRecurringService({FinanceLedgerService? ledger})
      : _ledger = ledger ?? FinanceLedgerService();

  final FinanceLedgerService _ledger;

  static const intervals = {
    'daily',
    'weekly',
    'monthly',
    'quarterly',
    'yearly',
  };

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';

  static DateTime _addMonths(DateTime date, int months) {
    final monthIndex = date.month - 1 + months;
    final year = date.year + monthIndex ~/ 12;
    final month = monthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final sourceWasMonthEnd =
        date.day == DateTime(date.year, date.month + 1, 0).day;
    final targetDay =
        sourceWasMonthEnd ? lastDay : date.day.clamp(1, lastDay).toInt();
    return DateTime(year, month, targetDay);
  }

  static DateTime _nextDate(DateTime date, String interval) => switch (interval) {
        'daily' => date.add(const Duration(days: 1)),
        'weekly' => date.add(const Duration(days: 7)),
        'monthly' => _addMonths(date, 1),
        'quarterly' => _addMonths(date, 3),
        'yearly' => _addMonths(date, 12),
        _ => throw FinanceRecurringException('Unsupported interval: $interval'),
      };

  Future<FinanceRecurringTemplate> createTemplate({
    required String name,
    required String transactionType,
    required String debitAccountId,
    required String creditAccountId,
    required int amountPaise,
    required String interval,
    required DateTime nextDueDate,
    DateTime? endDate,
    String? categoryId,
    String? partyId,
    String memo = '',
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const FinanceRecurringException('Template name is required.');
    }
    if (!{'income', 'expense', 'transfer'}.contains(transactionType)) {
      throw const FinanceRecurringException('Unsupported recurring transaction type.');
    }
    if (!intervals.contains(interval)) {
      throw const FinanceRecurringException('Unsupported recurring interval.');
    }
    if (amountPaise <= 0) {
      throw const FinanceRecurringException('Recurring amount must be positive.');
    }
    if (debitAccountId == creditAccountId) {
      throw const FinanceRecurringException('Debit and credit accounts must differ.');
    }

    final accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    final debitAccount = accounts.get(debitAccountId);
    final creditAccount = accounts.get(creditAccountId);
    if (debitAccount == null ||
        creditAccount == null ||
        !debitAccount.active ||
        !creditAccount.active ||
        debitAccount.currencyCode != 'INR' ||
        creditAccount.currencyCode != 'INR') {
      throw const FinanceRecurringException('Choose active INR accounts.');
    }

    final validTypes = switch (transactionType) {
      'income' =>
        debitAccount.accountType == 'asset' &&
            creditAccount.accountType == 'income',
      'expense' =>
        debitAccount.accountType == 'expense' &&
            creditAccount.accountType == 'asset',
      'transfer' =>
        debitAccount.accountType == 'asset' &&
            creditAccount.accountType == 'asset',
      _ => false,
    };
    if (!validTypes) {
      throw const FinanceRecurringException(
        'Selected accounts do not match the transaction type.',
      );
    }

    if (categoryId != null) {
      final category =
          Hive.box<FinanceCategory>(Boxes.financeCategories).get(categoryId);
      final categoryAccountId =
          transactionType == 'income' ? creditAccountId : debitAccountId;
      if (transactionType == 'transfer' ||
          category == null ||
          !category.active ||
          category.kind != transactionType ||
          category.accountId != categoryAccountId) {
        throw const FinanceRecurringException(
          'The selected category does not match this transaction.',
        );
      }
    }
    if (partyId != null) {
      final party =
          Hive.box<FinanceParty>(Boxes.financeParties).get(partyId);
      if (party == null || !party.active) {
        throw const FinanceRecurringException('Choose an active party.');
      }
    }

    final due = _day(nextDueDate);
    final end = endDate == null ? null : _day(endDate);
    if (end != null && end.isBefore(due)) {
      throw const FinanceRecurringException(
        'End date cannot be before the first due date.',
      );
    }

    final id = 'recurring:${DateTime.now().microsecondsSinceEpoch}';
    final template = FinanceRecurringTemplate(
      id: id,
      name: cleanName,
      transactionType: transactionType,
      debitAccountId: debitAccountId,
      creditAccountId: creditAccountId,
      amountPaise: amountPaise,
      interval: interval,
      nextDueDate: due,
      endDate: end,
      categoryId: categoryId,
      partyId: partyId,
      memo: memo.trim(),
    );
    await Hive.box<FinanceRecurringTemplate>(Boxes.financeRecurringTemplates)
        .put(id, template);
    return template;
  }

  Future<void> archiveTemplate(String templateId) async {
    final box =
        Hive.box<FinanceRecurringTemplate>(Boxes.financeRecurringTemplates);
    final template = box.get(templateId);
    if (template == null) {
      throw const FinanceRecurringException('Recurring template was not found.');
    }
    await box.put(
      template.id,
      FinanceRecurringTemplate(
        id: template.id,
        name: template.name,
        transactionType: template.transactionType,
        debitAccountId: template.debitAccountId,
        creditAccountId: template.creditAccountId,
        amountPaise: template.amountPaise,
        interval: template.interval,
        nextDueDate: template.nextDueDate,
        endDate: template.endDate,
        categoryId: template.categoryId,
        partyId: template.partyId,
        memo: template.memo,
        active: false,
        createdAt: template.createdAt,
      ),
    );
  }

  Future<FinanceRecurringProcessResult> processDue({
    DateTime? now,
    int maxOccurrencesPerTemplate = 366,
  }) async {
    final today = _day(now ?? DateTime.now());
    final templatesBox =
        Hive.box<FinanceRecurringTemplate>(Boxes.financeRecurringTemplates);
    final accountsBox = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    final transactionsBox =
        Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    final postingsBox = Hive.box<FinancePosting>(Boxes.financePostings);
    final categoriesBox = Hive.box<FinanceCategory>(Boxes.financeCategories);
    final partiesBox = Hive.box<FinanceParty>(Boxes.financeParties);
    var postedCount = 0;
    var skippedCount = 0;
    final issues = <String>[];

    for (final template in templatesBox.values.where((item) => item.active)) {
      var due = _day(template.nextDueDate);
      var processed = 0;
      try {
        while (!due.isAfter(today) &&
            (template.endDate == null || !due.isAfter(_day(template.endDate!))) &&
            processed < maxOccurrencesPerTemplate) {
          final dateKey = _dateKey(due);
          final sourceId = '${template.id}:$dateKey';
          final existing = transactionsBox.values.any(
            (transaction) =>
                transaction.sourceType == 'recurring_template' &&
                transaction.sourceId == sourceId,
          );
          if (existing) {
            skippedCount++;
          } else {
            final transactionId =
                'finance:recurring:${Uri.encodeComponent(template.id)}:$dateKey';
            final categoryOnDebit =
                template.transactionType == 'expense' ? template.categoryId : null;
            final categoryOnCredit =
                template.transactionType == 'income' ? template.categoryId : null;
            final partyOnDebit =
                template.transactionType == 'expense' ? template.partyId : null;
            final partyOnCredit =
                template.transactionType == 'income' ? template.partyId : null;
            await _ledger.postTransaction(
              transaction: FinanceTransaction(
                id: transactionId,
                transactionNumber:
                    'REC-${Uri.encodeComponent(template.id)}-$dateKey',
                transactionType: template.transactionType,
                date: due,
                memo: template.memo.isEmpty ? template.name : template.memo,
                sourceType: 'recurring_template',
                sourceId: sourceId,
              ),
              postings: [
                FinancePosting(
                  id: '$transactionId:debit',
                  transactionId: transactionId,
                  accountId: template.debitAccountId,
                  debitPaise: template.amountPaise,
                  categoryId: categoryOnDebit,
                  partyId: partyOnDebit,
                  memo: template.memo,
                ),
                FinancePosting(
                  id: '$transactionId:credit',
                  transactionId: transactionId,
                  accountId: template.creditAccountId,
                  creditPaise: template.amountPaise,
                  categoryId: categoryOnCredit,
                  partyId: partyOnCredit,
                  memo: template.memo,
                ),
              ],
              accountsBox: accountsBox,
              transactionsBox: transactionsBox,
              postingsBox: postingsBox,
              categoriesBox: categoriesBox,
              partiesBox: partiesBox,
            );
            postedCount++;
          }
          due = _nextDate(due, template.interval);
          processed++;
        }

        final stillActive =
            template.endDate == null || !due.isAfter(_day(template.endDate!));
        await templatesBox.put(
          template.id,
          FinanceRecurringTemplate(
            id: template.id,
            name: template.name,
            transactionType: template.transactionType,
            debitAccountId: template.debitAccountId,
            creditAccountId: template.creditAccountId,
            amountPaise: template.amountPaise,
            interval: template.interval,
            nextDueDate: due,
            endDate: template.endDate,
            categoryId: template.categoryId,
            partyId: template.partyId,
            memo: template.memo,
            active: stillActive,
            createdAt: template.createdAt,
          ),
        );
      } catch (error) {
        issues.add('Template ${template.id}: $error');
      }
    }

    return FinanceRecurringProcessResult(
      postedCount: postedCount,
      skippedCount: skippedCount,
      issues: issues,
    );
  }
}
