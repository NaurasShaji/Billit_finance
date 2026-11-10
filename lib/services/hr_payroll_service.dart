import 'package:hive_ce/hive_ce.dart';

import '../models/models.dart';
import 'boxes.dart';
import 'finance_source_sync_service.dart';
import 'finance_ledger_service.dart';
import 'hr_service.dart';
import 'payroll_service.dart';

class HrPayrollServiceException implements Exception {
  const HrPayrollServiceException(this.message);
  final String message;

  @override
  String toString() => 'HrPayrollServiceException: $message';
}

class HrPayrollService {
  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static int _rupeesToPaise(double amount, String label) {
    if (!amount.isFinite || amount < 0) {
      throw HrPayrollServiceException('$label is not a valid amount.');
    }
    return (amount * 100).round();
  }

  static String _periodId(DateTime start, DateTime end) {
    String key(DateTime date) =>
        '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
    return 'payroll:${key(start)}:${key(end)}';
  }

  static const advanceSettingsKey = 'hr_employee_advances';
  static const advancePayrollKey = 'hr_advance_payroll_deductions';
  static const payrollAdjustmentsKey = 'hr_payroll_adjustments';
  static const employeeReimbursementsKey = 'hr_employee_reimbursements';

  static const employeeAdvanceAccountId = 'system:employee-advances';

  FinanceAccount _requireAdvanceCashAccount(String accountId) {
    final account = Hive.box<FinanceAccount>(Boxes.financeAccounts).get(accountId);
    if (account == null || !account.active || account.accountType != 'asset' || account.currencyCode != 'INR') {
      throw const HrPayrollServiceException('Select an active INR cash or bank asset account.');
    }
    return account;
  }

  Future<void> _postAdvanceJournal({
    required String transactionId,
    required String transactionNumber,
    required String sourceType,
    required String sourceId,
    required DateTime date,
    required String memo,
    required String debitAccountId,
    required String creditAccountId,
    required int amountPaise,
  }) async {
    if (amountPaise <= 0) throw const HrPayrollServiceException('Journal amount must be positive.');
    _requireAdvanceCashAccount(debitAccountId == employeeAdvanceAccountId ? creditAccountId : debitAccountId);
    final accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    final advanceAccount = accounts.get(employeeAdvanceAccountId);
    if (advanceAccount == null || !advanceAccount.active || advanceAccount.accountType != 'asset') {
      throw const HrPayrollServiceException('Employee Advances asset account is unavailable.');
    }
    await FinanceLedgerService().postTransaction(
      transaction: FinanceTransaction(
        id: transactionId,
        transactionNumber: transactionNumber,
        transactionType: 'adjustment',
        date: date,
        memo: memo,
        sourceType: sourceType,
        sourceId: sourceId,
      ),
      postings: [
        FinancePosting(id: '$transactionId:debit', transactionId: transactionId, accountId: debitAccountId, debitPaise: amountPaise, memo: memo),
        FinancePosting(id: '$transactionId:credit', transactionId: transactionId, accountId: creditAccountId, creditPaise: amountPaise, memo: memo),
      ],
      accountsBox: accounts,
      transactionsBox: Hive.box<FinanceTransaction>(Boxes.financeTransactions),
      postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
      categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
      partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
    );
  }

  List<Map<String, dynamic>> advances(String employeeId) {
    final raw = Hive.box<dynamic>('app_settings').get(advanceSettingsKey);
    if (raw is! Map || raw[employeeId] is! List) return const [];
    return (raw[employeeId] as List).whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['id'] is String && e['principalPaise'] is int &&
          e['outstandingPaise'] is int && e['installmentPaise'] is int &&
          e['issueDate'] is String && e['nextDueDate'] is String &&
          e['status'] is String).toList()
      ..sort((a,b) => (a['issueDate'] as String).compareTo(b['issueDate'] as String));
  }

  List<Map<String, dynamic>> reimbursements({String? employeeId}) {
    final raw = Hive.box<dynamic>('app_settings').get(employeeReimbursementsKey);
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((entry) => Map<String, dynamic>.from(entry))
        .where((entry) => entry['id'] is String && (employeeId == null || entry['employeeId'] == employeeId))
        .toList()..sort((a, b) => (b['createdAt']?.toString() ?? '').compareTo(a['createdAt']?.toString() ?? ''));
  }

  Future<Map<String, dynamic>> submitReimbursement({required String employeeId, required int amountPaise, required DateTime expenseDate, String categoryId = '', String note = ''}) async {
    final employee = Hive.box<Employee>(Boxes.employees).get(employeeId);
    if (employee == null || employee.employmentStatus != 'active') throw const HrPayrollServiceException('Select an active employee.');
    if (amountPaise <= 0 || note.trim().isEmpty) throw const HrPayrollServiceException('Enter a positive claim amount and a description.');
    if (expenseDate.isAfter(DateTime.now())) throw const HrPayrollServiceException('Reimbursement date cannot be in the future.');
    if (categoryId.isNotEmpty) {
      final category = Hive.box<FinanceCategory>(Boxes.financeCategories).get(categoryId);
      if (category == null || !category.active || category.kind != 'expense') throw const HrPayrollServiceException('Select an active expense category.');
    }
    final settings = Hive.box<dynamic>('app_settings');
    final existingClaims = settings.get(employeeReimbursementsKey);
    if (existingClaims != null && existingClaims is! List) throw const HrPayrollServiceException('Reimbursement register is malformed.');
    final claims = existingClaims is List ? List<dynamic>.from(existingClaims) : <dynamic>[];
    final claim = {'id': const Uuid().v4(), 'employeeId': employeeId, 'amountPaise': amountPaise, 'paidPaise': 0, 'expenseDate': _day(expenseDate).toIso8601String(), 'categoryId': categoryId, 'note': note.trim(), 'status': 'submitted', 'createdAt': DateTime.now().toIso8601String(), 'payments': <Map<String, dynamic>>[]};
    await settings.put(employeeReimbursementsKey, [...claims, claim]);
    return claim;
  }

  Future<void> reviewReimbursement({required String claimId, required String decision, String reason = ''}) async {
    if (decision != 'approved' && decision != 'rejected') throw const HrPayrollServiceException('Decision must be approved or rejected.');
    if (decision == 'rejected' && reason.trim().isEmpty) throw const HrPayrollServiceException('A rejection reason is required.');
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(employeeReimbursementsKey);
    if (raw is! List) throw const HrPayrollServiceException('Reimbursement claim was not found.');
    final claims = List<dynamic>.from(raw);
    final index = claims.indexWhere((entry) => entry is Map && entry['id'] == claimId);
    if (index < 0) throw const HrPayrollServiceException('Reimbursement claim was not found.');
    final claim = Map<String, dynamic>.from(claims[index] as Map);
    if (claim['status'] != 'submitted') throw const HrPayrollServiceException('Only submitted reimbursement claims can be reviewed.');
    if (decision == 'approved') {
      final amount = claim['amountPaise'];
      if (amount is! int || amount <= 0) throw const HrPayrollServiceException('Reimbursement claim amount is invalid.');
      final categoryId = claim['categoryId'] is String ? claim['categoryId'] as String : '';
      final category = categoryId.isEmpty ? null : Hive.box<FinanceCategory>(Boxes.financeCategories).get(categoryId);
      if (categoryId.isNotEmpty && (category == null || !category.active || category.kind != 'expense')) throw const HrPayrollServiceException('The reimbursement expense category is unavailable.');
      final expenseAccountId = category?.accountId ?? 'system:operating-expense';
      _requirePayrollAccount(expenseAccountId, 'expense');
      _requirePayrollAccount('system:employee-reimbursements-payable', 'liability');
      final transactionId = 'finance:employee-reimbursement-accrual:$claimId';
      final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
      final postings = Hive.box<FinancePosting>(Boxes.financePostings);
      final existing = transactions.values.where((tx) => tx.sourceType == 'employee_reimbursement_accrual' && tx.sourceId == claimId).toList();
      if (existing.isEmpty) {
        await FinanceLedgerService().postTransaction(
          transaction: FinanceTransaction(id: transactionId, transactionNumber: 'REIMB-ACC-$claimId', transactionType: 'expense', date: DateTime.tryParse(claim['expenseDate']?.toString() ?? '') ?? DateTime.now(), memo: 'Employee reimbursement accrual: ${claim['note']}', sourceType: 'employee_reimbursement_accrual', sourceId: claimId),
          postings: [
            FinancePosting(id: '$transactionId:expense', transactionId: transactionId, accountId: expenseAccountId, debitPaise: amount, categoryId: categoryId.isEmpty ? null : categoryId, memo: 'Employee reimbursement expense'),
            FinancePosting(id: '$transactionId:payable', transactionId: transactionId, accountId: 'system:employee-reimbursements-payable', creditPaise: amount, memo: 'Approved employee reimbursement payable'),
          ],
          accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts), transactionsBox: transactions, postingsBox: postings,
          categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories), partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
        );
      } else {
        if (existing.length != 1 || existing.single.id != transactionId || existing.single.status != 'posted' || transactions.values.any((tx) => tx.transactionType == 'reversal' && tx.reversedTransactionId == transactionId && tx.status == 'posted')) throw const HrPayrollServiceException('Conflicting or reversed reimbursement accrual journal exists.');
        final lines = postings.values.where((line) => line.transactionId == transactionId).toList();
        if (lines.length != 2 || lines.where((line) => line.accountId == expenseAccountId).fold<int>(0, (sum, line) => sum + line.debitPaise) != amount || lines.where((line) => line.accountId == 'system:employee-reimbursements-payable').fold<int>(0, (sum, line) => sum + line.creditPaise) != amount) throw const HrPayrollServiceException('Existing reimbursement accrual journal does not match the claim.');
      }
    }
    claim['status'] = decision;
    claim['reviewedAt'] = DateTime.now().toIso8601String();
    claim['reviewNote'] = reason.trim();
    claims[index] = claim;
    await settings.put(employeeReimbursementsKey, claims);
  }

  Future<Map<String, dynamic>> payReimbursement({required String claimId, required int amountPaise, required String paymentAccountId}) async {
    if (amountPaise <= 0) throw const HrPayrollServiceException('Payment amount must be positive.');
    _requireAdvanceCashAccount(paymentAccountId);
    _requirePayrollAccount('system:employee-reimbursements-payable', 'liability');
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(employeeReimbursementsKey);
    if (raw is! List) throw const HrPayrollServiceException('Reimbursement claim was not found.');
    final claims = List<dynamic>.from(raw);
    final index = claims.indexWhere((entry) => entry is Map && entry['id'] == claimId);
    if (index < 0) throw const HrPayrollServiceException('Reimbursement claim was not found.');
    final claim = Map<String, dynamic>.from(claims[index] as Map);
    if (claim['status'] != 'approved' && claim['status'] != 'partially_paid') throw const HrPayrollServiceException('Approve the reimbursement claim before payment.');
    final total = claim['amountPaise'];
    final paid = claim['paidPaise'];
    if (total is! int || paid is! int || amountPaise > total - paid) throw const HrPayrollServiceException('Payment exceeds the reimbursement amount outstanding.');
    final sourceId = '$claimId:from:$paid';
    final transactionId = 'finance:employee-reimbursement-payment:$sourceId';
    final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    final postings = Hive.box<FinancePosting>(Boxes.financePostings);
    final existing = transactions.values.where((tx) => tx.sourceType == 'employee_reimbursement_payment' && tx.sourceId == sourceId).toList();
    if (existing.isEmpty) {
      await FinanceLedgerService().postTransaction(
        transaction: FinanceTransaction(id: transactionId, transactionNumber: 'REIMB-PAY-$claimId-$paid', transactionType: 'adjustment', date: DateTime.now(), memo: 'Employee reimbursement settlement: ${claim['note']}', sourceType: 'employee_reimbursement_payment', sourceId: sourceId),
        postings: [
          FinancePosting(id: '$transactionId:payable', transactionId: transactionId, accountId: 'system:employee-reimbursements-payable', debitPaise: amountPaise, memo: 'Settle approved reimbursement'),
          FinancePosting(id: '$transactionId:payment', transactionId: transactionId, accountId: paymentAccountId, creditPaise: amountPaise, memo: 'Reimbursement payment'),
        ],
        accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts), transactionsBox: transactions, postingsBox: postings,
        categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories), partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
      );
    } else {
      if (existing.length != 1 || existing.single.id != transactionId || existing.single.status != 'posted' || transactions.values.any((tx) => tx.transactionType == 'reversal' && tx.reversedTransactionId == transactionId && tx.status == 'posted')) throw const HrPayrollServiceException('Conflicting or reversed reimbursement payment journal exists.');
      final lines = postings.values.where((line) => line.transactionId == transactionId).toList();
      if (lines.length != 2 || lines.where((line) => line.accountId == 'system:employee-reimbursements-payable').fold<int>(0, (sum, line) => sum + line.debitPaise) != amountPaise || lines.where((line) => line.accountId == paymentAccountId).fold<int>(0, (sum, line) => sum + line.creditPaise) != amountPaise) throw const HrPayrollServiceException('Existing reimbursement settlement journal does not match this payment request.');
    }
    final payments = (claim['payments'] as List? ?? []).whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList();
    if (!payments.any((entry) => entry['sourceId'] == sourceId)) payments.add({'sourceId': sourceId, 'amountPaise': amountPaise, 'paymentAccountId': paymentAccountId, 'date': DateTime.now().toIso8601String(), 'journalId': transactionId});
    final newPaid = paid + amountPaise;
    claim['paidPaise'] = newPaid;
    claim['payments'] = payments;
    claim['status'] = newPaid == total ? 'paid' : 'partially_paid';
    claim['paidAt'] = newPaid == total ? DateTime.now().toIso8601String() : null;
    claims[index] = claim;
    await settings.put(employeeReimbursementsKey, claims);
    return claim;
  }
  Future<void> reverseReimbursementClaim({required String claimId, required String reason}) async {
    if (reason.trim().isEmpty) throw const HrPayrollServiceException('A cancellation/reversal reason is required.');
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(employeeReimbursementsKey);
    if (raw is! List) throw const HrPayrollServiceException('Reimbursement claim was not found.');
    final claims = List<dynamic>.from(raw);
    final index = claims.indexWhere((entry) => entry is Map && entry['id'] == claimId);
    if (index < 0) throw const HrPayrollServiceException('Reimbursement claim was not found.');
    final claim = Map<String, dynamic>.from(claims[index] as Map);
    if (claim['status'] == 'cancelled') return;
    if (claim['status'] != 'approved' && claim['status'] != 'partially_paid' && claim['status'] != 'paid') throw const HrPayrollServiceException('Only approved reimbursement claims can be cancelled.');
    final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    final payments = (claim['payments'] as List? ?? []).whereType<Map>().toList();
    final recordedPaid = payments.fold<int>(0, (sum, payment) {
      final amount = payment['amountPaise'];
      if (amount is! int || amount <= 0) throw const HrPayrollServiceException('Reimbursement payment history contains an invalid amount.');
      return sum + amount;
    });
    if (claim['paidPaise'] is! int || recordedPaid != claim['paidPaise']) {
      throw const HrPayrollServiceException('Reimbursement paid total does not match its payment history. Reconcile before reversal.');
    }
    // Reverse cash settlements first. This records the return of funds to the original payment account.
    for (final payment in payments.reversed) {
      final journalId = payment['journalId'];
      if (journalId is! String) throw const HrPayrollServiceException('Reimbursement payment history is missing its journal reference.');
      final original = transactions.get(journalId);
      if (original == null || original.status != 'posted') throw const HrPayrollServiceException('A reimbursement payment journal is unavailable.');
      final reversals = transactions.values.where((tx) => tx.transactionType == 'reversal' && tx.reversedTransactionId == journalId && tx.status == 'posted').toList();
      if (reversals.isEmpty) {
        await FinanceLedgerService().reverseTransaction(
          originalTransactionId: journalId, reversalId: 'finance:reversal:$journalId', reversalNumber: 'REV-REIMB-PAY-${journalId.hashCode.abs()}', reversalDate: DateTime.now(),
          accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts), transactionsBox: transactions,
          postingsBox: Hive.box<FinancePosting>(Boxes.financePostings), categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
          partiesBox: Hive.box<FinanceParty>(Boxes.financeParties), memo: 'Reimbursement payment reversal: ${reason.trim()}',
        );
      } else if (reversals.length != 1) {
        throw const HrPayrollServiceException('Multiple reversals exist for a reimbursement payment.');
      }
    }
    final accrualId = 'finance:employee-reimbursement-accrual:$claimId';
    final accrual = transactions.get(accrualId);
    if (accrual == null || accrual.status != 'posted') throw const HrPayrollServiceException('Reimbursement accrual journal is unavailable.');
    final accrualReversals = transactions.values.where((tx) => tx.transactionType == 'reversal' && tx.reversedTransactionId == accrualId && tx.status == 'posted').toList();
    if (accrualReversals.isEmpty) {
      await FinanceLedgerService().reverseTransaction(
        originalTransactionId: accrualId, reversalId: 'finance:reversal:$accrualId', reversalNumber: 'REV-REIMB-ACC-${claimId.hashCode.abs()}', reversalDate: DateTime.now(),
        accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts), transactionsBox: transactions,
        postingsBox: Hive.box<FinancePosting>(Boxes.financePostings), categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
        partiesBox: Hive.box<FinanceParty>(Boxes.financeParties), memo: 'Reimbursement accrual reversal: ${reason.trim()}',
      );
    } else if (accrualReversals.length != 1) {
      throw const HrPayrollServiceException('Multiple reversals exist for the reimbursement accrual.');
    }
    claim['status'] = 'cancelled';
    claim['cancelledAt'] = DateTime.now().toIso8601String();
    claim['cancellationReason'] = reason.trim();
    claim['paidPaise'] = 0;
    claims[index] = claim;
    await settings.put(employeeReimbursementsKey, claims);
  }
  Future<void> addEmployeeAdvance({
    required String employeeId, required int principalPaise,
    required int installmentPaise, required DateTime issueDate,
    required DateTime firstDueDate, String description = 'Employee advance',
    String cashAccountId = 'system:cash',
  }) async {
    if (Hive.box<Employee>(Boxes.employees).get(employeeId) == null) {
      throw const HrPayrollServiceException('Employee was not found.');
    }
    if (principalPaise <= 0 || installmentPaise <= 0 || installmentPaise > principalPaise) {
      throw const HrPayrollServiceException('Advance and instalment amounts must be positive; instalment cannot exceed the advance.');
    }
    if (_day(firstDueDate).isBefore(_day(issueDate)) || description.trim().isEmpty) {
      throw const HrPayrollServiceException('Enter a description and a valid first repayment date.');
    }
    _requireAdvanceCashAccount(cashAccountId);
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(advanceSettingsKey);
    final all = <String,dynamic>{if (raw is Map) ...Map<String,dynamic>.from(raw)};
    final list = all[employeeId] is List ? List<dynamic>.from(all[employeeId] as List) : <dynamic>[];
    list.add({
      'id': const Uuid().v4(), 'description': description.trim(),
      'principalPaise': principalPaise, 'outstandingPaise': principalPaise,
      'installmentPaise': installmentPaise,
      'issueDate': _day(issueDate).toIso8601String(),
      'nextDueDate': _day(firstDueDate).toIso8601String(),
      'status': 'active', 'repayments': <Map<String,dynamic>>[],
      'createdAt': DateTime.now().toIso8601String(),
    });
    all[employeeId] = list;
    await settings.put(advanceSettingsKey, all);
    final advanceId = (list.last as Map)['id'] as String;
    try {
      await _postAdvanceJournal(
        transactionId: 'finance:employee-advance:$advanceId',
        transactionNumber: 'ADV-$advanceId',
        sourceType: 'employee_advance_issue',
        sourceId: advanceId,
        date: issueDate,
        memo: 'Employee advance: ${description.trim()}',
        debitAccountId: employeeAdvanceAccountId,
        creditAccountId: cashAccountId,
        amountPaise: principalPaise,
      );
    } catch (_) {
      final current = settings.get(advanceSettingsKey);
      if (current is Map && current[employeeId] is List) {
        final rollback = Map<String, dynamic>.from(current);
        final entries = List<dynamic>.from(rollback[employeeId] as List)
          ..removeWhere((entry) => entry is Map && entry['id'] == advanceId);
        rollback[employeeId] = entries;
        await settings.put(advanceSettingsKey, rollback);
      }
      rethrow;
    }
  }

  Future<void> recordAdvanceRepayment({
    required String employeeId, required String advanceId,
    required int amountPaise, required DateTime date, String note = '',
    String cashAccountId = 'system:cash',
  }) async {
    if (amountPaise <= 0) throw const HrPayrollServiceException('Repayment must be positive.');
    _requireAdvanceCashAccount(cashAccountId);
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(advanceSettingsKey);
    if (raw is! Map || raw[employeeId] is! List) throw const HrPayrollServiceException('Advance was not found.');
    final all = Map<String,dynamic>.from(raw);
    final list = List<dynamic>.from(all[employeeId] as List);
    final index = list.indexWhere((e) => e is Map && e['id'] == advanceId);
    if (index < 0) throw const HrPayrollServiceException('Advance was not found.');
    final advance = Map<String,dynamic>.from(list[index] as Map);
    final outstanding = advance['outstandingPaise'] as int;
    final pendingRaw = settings.get(advancePayrollKey);
    if (pendingRaw is Map) {
      for (final pending in pendingRaw.entries) {
        final slip = Hive.box<Payslip>(Boxes.payslips).get(pending.key);
        if (slip != null && slip.status != 'paid' && pending.value is List &&
            (pending.value as List).whereType<Map>().any((item) => item['advanceId'] == advanceId && item['employeeId'] == employeeId)) {
          throw const HrPayrollServiceException('This advance has a deduction reserved by an unpaid payslip. Settle or correct that payroll before recording a manual repayment.');
        }
      }
    }
    if (amountPaise > outstanding) throw const HrPayrollServiceException('Repayment cannot exceed the outstanding advance balance.');
    final repayments = (advance['repayments'] as List? ?? []).whereType<Map>()
        .map((e) => Map<String,dynamic>.from(e)).toList();
    repayments.add({'id': const Uuid().v4(), 'date': _day(date).toIso8601String(),
      'amountPaise': amountPaise, 'note': note.trim(), 'source': 'manual',
      'createdAt': DateTime.now().toIso8601String()});
    final remaining = outstanding - amountPaise;
    advance['outstandingPaise'] = remaining;
    advance['repayments'] = repayments;
    advance['status'] = remaining == 0 ? 'settled' : 'active';
    list[index] = advance; all[employeeId] = list;
    await settings.put(advanceSettingsKey, all);
    final repaymentId = repayments.last['id'] as String;
    try {
      await _postAdvanceJournal(
        transactionId: 'finance:employee-advance-repayment:$repaymentId',
        transactionNumber: 'ADVR-$repaymentId',
        sourceType: 'employee_advance_repayment',
        sourceId: repaymentId,
        date: date,
        memo: note.trim().isEmpty ? 'Employee advance repayment' : note.trim(),
        debitAccountId: cashAccountId,
        creditAccountId: employeeAdvanceAccountId,
        amountPaise: amountPaise,
      );
    } catch (_) {
      final current = settings.get(advanceSettingsKey);
      if (current is Map && current[employeeId] is List) {
        final rollback = Map<String, dynamic>.from(current);
        final entries = List<dynamic>.from(rollback[employeeId] as List);
        final currentIndex = entries.indexWhere((entry) => entry is Map && entry['id'] == advanceId);
        if (currentIndex >= 0) {
          final restored = Map<String, dynamic>.from(entries[currentIndex] as Map);
          restored['outstandingPaise'] = outstanding;
          restored['repayments'] = repayments.where((entry) => entry['id'] != repaymentId).toList();
          restored['status'] = 'active';
          entries[currentIndex] = restored;
          rollback[employeeId] = entries;
          await settings.put(advanceSettingsKey, rollback);
        }
      }
      rethrow;
    }
  }

  List<Map<String,dynamic>> _advanceDeductionSnapshot(String employeeId, DateTime start, DateTime end) {
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(advancePayrollKey);
    final reserved = <String>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final slip = Hive.box<Payslip>(Boxes.payslips).get(entry.key);
        if (slip != null && slip.status != 'paid' && entry.value is List) {
          for (final item in (entry.value as List).whereType<Map>()) {
            if (item['employeeId'] == employeeId && item['advanceId'] is String) reserved.add(item['advanceId'] as String);
          }
        }
      }
    }
    return advances(employeeId).where((a) {
      final due = _day(DateTime.parse(a['nextDueDate'] as String));
      return a['status'] == 'active' && !reserved.contains(a['id']) &&
        !due.isBefore(start) && !due.isAfter(end);
    }).map((a) => <String,dynamic>{
      'employeeId': employeeId, 'advanceId': a['id'],
      'amountPaise': (a['installmentPaise'] as int).clamp(0, a['outstandingPaise'] as int),
    }).toList();
  }

  int _advanceDeductionPaise(String employeeId, DateTime start, DateTime end) =>
    _advanceDeductionSnapshot(employeeId, start, end)
      .fold<int>(0, (sum, item) => sum + (item['amountPaise'] as int));

  Future<void> _postPayrollAdvanceRecoveryJournal({
    required String payslipId,
    required DateTime date,
    required int amountPaise,
  }) async {
    if (amountPaise <= 0) return;
    final accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    final advanceAccount = accounts.get(employeeAdvanceAccountId);
    final salaryExpenseAccount = accounts.get('system:salary-expense');
    if (advanceAccount == null || !advanceAccount.active || advanceAccount.accountType != 'asset' ||
        salaryExpenseAccount == null || !salaryExpenseAccount.active || salaryExpenseAccount.accountType != 'expense') {
      throw const HrPayrollServiceException('Employee Advances or Salaries and Wages account is unavailable or has an invalid type.');
    }
    final transactionId = 'finance:payroll-advance-recovery:$payslipId';
    final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    final postings = Hive.box<FinancePosting>(Boxes.financePostings);
    final existing = transactions.values.where((item) =>
      item.sourceType == 'payroll_advance_recovery' && item.sourceId == payslipId).toList();
    if (existing.isNotEmpty) {
      if (existing.length != 1 || existing.single.id != transactionId) {
        throw const HrPayrollServiceException('Conflicting payroll advance recovery journal already exists.');
      }
      final lines = postings.values.where((line) => line.transactionId == transactionId).toList();
      final debit = lines.where((line) => line.accountId == 'system:salary-expense')
          .fold<int>(0, (sum, line) => sum + line.debitPaise - line.creditPaise);
      final credit = lines.where((line) => line.accountId == employeeAdvanceAccountId)
          .fold<int>(0, (sum, line) => sum + line.creditPaise - line.debitPaise);
      if (existing.single.status != 'posted' || debit != amountPaise || credit != amountPaise || lines.length != 2) {
        throw const HrPayrollServiceException('Existing payroll advance recovery journal does not match the pending deduction. Reconcile it manually.');
      }
      return;
    }
    await FinanceLedgerService().postTransaction(
      transaction: FinanceTransaction(
        id: transactionId,
        transactionNumber: 'PAYADV-$payslipId',
        transactionType: 'adjustment',
        date: date,
        memo: 'Employee advance recovery through payroll $payslipId',
        sourceType: 'payroll_advance_recovery',
        sourceId: payslipId,
      ),
      postings: [
        FinancePosting(id: '$transactionId:salary-expense', transactionId: transactionId,
          accountId: 'system:salary-expense', debitPaise: amountPaise,
          memo: 'Gross salary offset by employee advance recovery'),
        FinancePosting(id: '$transactionId:employee-advances', transactionId: transactionId,
          accountId: employeeAdvanceAccountId, creditPaise: amountPaise,
          memo: 'Employee advance recovered through payroll'),
      ],
      accountsBox: accounts,
      transactionsBox: Hive.box<FinanceTransaction>(Boxes.financeTransactions),
      postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
      categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
      partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
    );
  }

  /// Books a verified legacy advance balance as an opening asset.
  ///
  /// This is allowed only when no issue, repayment, or payroll-recovery journal
  /// already exists for the advance. The current outstanding balance is posted
  /// against Opening Balance Equity; historical cash movements are not invented.
  Future<void> recordLegacyAdvanceOpeningBalance({
    required String employeeId,
    required String advanceId,
    required DateTime asOfDate,
  }) async {
    final employee = Hive.box<Employee>(Boxes.employees).get(employeeId);
    if (employee == null) {
      throw const HrPayrollServiceException('Employee was not found.');
    }
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(advanceSettingsKey);
    if (raw is! Map || raw[employeeId] is! List) {
      throw const HrPayrollServiceException('Advance was not found.');
    }
    final matches = (raw[employeeId] as List)
        .whereType<Map>()
        .where((item) => item['id'] == advanceId)
        .toList();
    if (matches.length != 1) {
      throw const HrPayrollServiceException('Advance must exist exactly once in the HR register.');
    }
    final advance = matches.single;
    final principal = advance['principalPaise'];
    final outstanding = advance['outstandingPaise'];
    if (principal is! int || outstanding is! int ||
        principal <= 0 || outstanding <= 0 || outstanding != principal) {
      throw const HrPayrollServiceException(
        'Opening balance requires a positive outstanding amount equal to the recorded principal. Advances with prior repayments require manual reconstruction.',
      );
    }
    final issueDateValue = advance['issueDate'];
    final issueDate = issueDateValue is String ? DateTime.tryParse(issueDateValue) : null;
    final effectiveDate = _day(asOfDate);
    if (issueDate == null || effectiveDate.isBefore(_day(issueDate)) ||
        effectiveDate.isAfter(_day(DateTime.now()))) {
      throw const HrPayrollServiceException(
        'Opening balance date must be on or after the advance issue date and cannot be in the future.',
      );
    }

    final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    if (advance['repayments'] is! List ||
        (advance['repayments'] as List).isNotEmpty ||
        (advance['corrections'] is List &&
            (advance['corrections'] as List).isNotEmpty)) {
      throw const HrPayrollServiceException(
        'This advance has repayment history or malformed repayment data. Its opening balance requires manual reconstruction.',
      );
    }
    final payrollSnapshots = settings.get(advancePayrollKey);
    final payslipIds = <String>{};
    if (payrollSnapshots is Map) {
      for (final entry in payrollSnapshots.entries) {
        if (entry.value is List &&
            (entry.value as List).whereType<Map>().any((snapshot) =>
                snapshot['employeeId'] == employeeId &&
                snapshot['advanceId'] == advanceId)) {
          payslipIds.add(entry.key.toString());
        }
      }
    }
    final hasLinkedHistory = transactions.values.any((tx) =>
        (tx.sourceType == 'employee_advance_issue' && tx.sourceId == advanceId) ||
        (tx.sourceType == 'payroll_advance_recovery' && payslipIds.contains(tx.sourceId)) ||
        (tx.sourceType == 'employee_advance_opening_balance' && tx.sourceId == advanceId) ||
        (tx.sourceType == 'employee_advance_correction' && tx.sourceId.startsWith('$advanceId:')));
    if (hasLinkedHistory) {
      throw const HrPayrollServiceException(
        'This advance already has linked journal history. Do not create an opening balance; reconcile its existing entries instead.',
      );
    }

    final accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    final advanceAccount = accounts.get(employeeAdvanceAccountId);
    final openingEquity = accounts.get('system:opening-equity');
    if (advanceAccount == null || !advanceAccount.active || advanceAccount.accountType != 'asset' ||
        openingEquity == null || !openingEquity.active || openingEquity.accountType != 'equity' ||
        advanceAccount.currencyCode != 'INR' || openingEquity.currencyCode != 'INR') {
      throw const HrPayrollServiceException('Employee Advances or Opening Balance Equity account is unavailable or invalid.');
    }

    final transactionId = 'finance:employee-advance-opening:$advanceId';
    await FinanceLedgerService().postTransaction(
      transaction: FinanceTransaction(
        id: transactionId,
        transactionNumber: 'ADV-OPEN-$advanceId',
        transactionType: 'opening_balance',
        date: _day(asOfDate),
        memo: 'Opening balance for legacy employee advance ${advance['description'] ?? advanceId} (${employee.name})',
        sourceType: 'employee_advance_opening_balance',
        sourceId: advanceId,
      ),
      postings: [
        FinancePosting(
          id: '$transactionId:employee-advances',
          transactionId: transactionId,
          accountId: employeeAdvanceAccountId,
          debitPaise: outstanding,
          memo: 'Legacy employee advance outstanding at opening date',
        ),
        FinancePosting(
          id: '$transactionId:opening-equity',
          transactionId: transactionId,
          accountId: 'system:opening-equity',
          creditPaise: outstanding,
          memo: 'Offset for verified legacy employee advance balance',
        ),
      ],
      accountsBox: accounts,
      transactionsBox: transactions,
      postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
      categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
      partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
    );
  }

  Future<void> correctEmployeeAdvanceBalance({
    required String employeeId,
    required String advanceId,
    required int correctedOutstandingPaise,
    required DateTime effectiveDate,
    required String reason,
    required String offsetAccountId,
  }) async {
    if (correctedOutstandingPaise < 0 || reason.trim().isEmpty) throw const HrPayrollServiceException('Enter a non-negative verified balance and a correction reason.');
    final employees = Hive.box<Employee>(Boxes.employees);
    if (employees.get(employeeId) == null) throw const HrPayrollServiceException('Employee was not found.');
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(advanceSettingsKey);
    if (raw is! Map || raw[employeeId] is! List) throw const HrPayrollServiceException('Advance was not found.');
    final all = Map<String, dynamic>.from(raw);
    final list = List<dynamic>.from(all[employeeId] as List);
    final matches = list.asMap().entries.where((entry) => entry.value is Map && (entry.value as Map)['id'] == advanceId).toList();
    if (matches.length != 1) throw const HrPayrollServiceException('Advance must exist exactly once in the HR register.');
    final index = matches.single.key;
    final advance = Map<String, dynamic>.from(matches.single.value as Map);
    final current = advance['outstandingPaise'];
    if (current is! int || current < 0) throw const HrPayrollServiceException('The existing advance balance is malformed.');
    final delta = correctedOutstandingPaise - current;
    if (delta == 0) throw const HrPayrollServiceException('The verified balance is already equal to the HR register balance.');
    final date = _day(effectiveDate);
    final issueDate = DateTime.tryParse(advance['issueDate']?.toString() ?? '');
    if (issueDate == null || date.isBefore(_day(issueDate)) || date.isAfter(_day(DateTime.now()))) throw const HrPayrollServiceException('Correction date must be on or after the advance issue date and cannot be in the future.');
    final pending = settings.get(advancePayrollKey);
    if (pending is Map) {
      for (final entry in pending.entries) {
        final slip = Hive.box<Payslip>(Boxes.payslips).get(entry.key);
        if (slip != null && slip.status == 'draft' && entry.value is List && (entry.value as List).whereType<Map>().any((item) => item['employeeId'] == employeeId && item['advanceId'] == advanceId)) {
          throw const HrPayrollServiceException('A draft payroll run has reserved a deduction for this advance. Resolve that draft payroll before correcting the balance.');
        }
      }
    }
    final accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    final advanceAccount = accounts.get(employeeAdvanceAccountId);
    final offsetAccount = accounts.get(offsetAccountId);
    if (advanceAccount == null || !advanceAccount.active || advanceAccount.accountType != 'asset' || advanceAccount.currencyCode != 'INR' || offsetAccount == null || !offsetAccount.active || offsetAccount.currencyCode != 'INR' || offsetAccount.id == employeeAdvanceAccountId) {
      throw const HrPayrollServiceException('Select an active INR offset account different from Employee Advances.');
    }
    final dateKey = '${date.year.toString().padLeft(4, '0')}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final correctionId = '$advanceId:$current:$correctedOutstandingPaise:$dateKey';
    final transactionId = 'finance:employee-advance-correction:$correctionId';
    final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    final postings = Hive.box<FinancePosting>(Boxes.financePostings);
    final existing = transactions.values.where((tx) => tx.sourceType == 'employee_advance_correction' && tx.sourceId == correctionId).toList();
    if (existing.isNotEmpty) {
      if (existing.length != 1 || existing.single.id != transactionId || existing.single.status != 'posted' ||
          transactions.values.any((tx) => tx.transactionType == 'reversal' && tx.reversedTransactionId == transactionId && tx.status == 'posted')) {
        throw const HrPayrollServiceException('A conflicting or reversed correction journal already exists.');
      }
      final lines = postings.values.where((line) => line.transactionId == transactionId).toList();
      final expectedDebit = delta > 0 ? employeeAdvanceAccountId : offsetAccountId;
      final expectedCredit = delta > 0 ? offsetAccountId : employeeAdvanceAccountId;
      if (lines.length != 2 || lines.where((line) => line.accountId == expectedDebit).fold<int>(0, (sum, line) => sum + line.debitPaise) != delta.abs() || lines.where((line) => line.accountId == expectedCredit).fold<int>(0, (sum, line) => sum + line.creditPaise) != delta.abs()) throw const HrPayrollServiceException('Existing correction journal does not match the requested register correction.');
    } else {
      final debitAccount = delta > 0 ? employeeAdvanceAccountId : offsetAccountId;
      final creditAccount = delta > 0 ? offsetAccountId : employeeAdvanceAccountId;
      await FinanceLedgerService().postTransaction(
        transaction: FinanceTransaction(id: transactionId, transactionNumber: 'ADV-COR-$dateKey-${correctionId.hashCode.abs()}', transactionType: 'adjustment', date: date, memo: 'Employee advance balance correction: ${reason.trim()}', sourceType: 'employee_advance_correction', sourceId: correctionId),
        postings: [
          FinancePosting(id: '$transactionId:debit', transactionId: transactionId, accountId: debitAccount, debitPaise: delta.abs(), memo: reason.trim()),
          FinancePosting(id: '$transactionId:credit', transactionId: transactionId, accountId: creditAccount, creditPaise: delta.abs(), memo: reason.trim()),
        ],
        accountsBox: accounts, transactionsBox: transactions, postingsBox: postings,
        categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories), partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
      );
    }
    final corrections = (advance['corrections'] as List? ?? []).whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList();
    if (!corrections.any((entry) => entry['id'] == correctionId)) {
      corrections.add({'id': correctionId, 'date': date.toIso8601String(), 'previousOutstandingPaise': current, 'correctedOutstandingPaise': correctedOutstandingPaise, 'deltaPaise': delta, 'offsetAccountId': offsetAccountId, 'reason': reason.trim(), 'journalId': transactionId, 'status': 'posted'});
    }
    advance['outstandingPaise'] = correctedOutstandingPaise;
    advance['status'] = correctedOutstandingPaise == 0 ? 'settled' : 'active';
    advance['corrections'] = corrections;
    list[index] = advance;
    all[employeeId] = list;
    await settings.put(advanceSettingsKey, all);
  }
  Future<void> reverseEmployeeAdvanceCorrection({required String employeeId, required String advanceId, required String correctionId, required String reason}) async {
    if (reason.trim().isEmpty) throw const HrPayrollServiceException('A reversal reason is required.');
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(advanceSettingsKey);
    if (raw is! Map || raw[employeeId] is! List) throw const HrPayrollServiceException('Advance was not found.');
    final all = <String, dynamic>{...Map<String, dynamic>.from(raw)};
    final list = List<dynamic>.from(all[employeeId] as List);
    final advanceIndex = list.indexWhere((entry) => entry is Map && entry['id'] == advanceId);
    if (advanceIndex < 0) throw const HrPayrollServiceException('Advance was not found.');
    final advance = Map<String, dynamic>.from(list[advanceIndex] as Map);
    final corrections = (advance['corrections'] as List? ?? []).whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList();
    final index = corrections.indexWhere((entry) => entry['id'] == correctionId);
    if (index < 0) throw const HrPayrollServiceException('Advance correction was not found.');
    final correction = corrections[index];
    if (correction['status'] == 'reversed') return;
    if (corrections.skip(index + 1).any((entry) => entry['status'] != 'reversed')) throw const HrPayrollServiceException('Reverse later balance corrections first.');
    final current = advance['outstandingPaise'];
    final previous = correction['previousOutstandingPaise'];
    final corrected = correction['correctedOutstandingPaise'];
    final delta = correction['deltaPaise'];
    final journalId = correction['journalId'];
    if (current is! int || previous is! int || corrected is! int || delta is! int || journalId is! String || current != corrected) throw const HrPayrollServiceException('Advance balance has changed since this correction. Reconcile subsequent activity before reversing it.');
    final correctionDate = DateTime.tryParse(correction['date']?.toString() ?? '');
    if (correctionDate == null) throw const HrPayrollServiceException('Correction date is malformed.');
    final repayments = (advance['repayments'] as List? ?? []).whereType<Map>();
    if (repayments.any((entry) { final date = DateTime.tryParse(entry['date']?.toString() ?? ''); return date != null && !_day(date).isBefore(_day(correctionDate)); })) throw const HrPayrollServiceException('This advance has repayment activity on or after the correction date. Reverse or reconcile that activity first.');
    final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    final original = transactions.get(journalId);
    if (original == null || original.status != 'posted') throw const HrPayrollServiceException('Original advance correction journal is unavailable.');
    final reversalId = 'finance:reversal:$journalId';
    final reversals = transactions.values.where((tx) => tx.transactionType == 'reversal' && tx.reversedTransactionId == journalId && tx.status == 'posted').toList();
    if (reversals.isEmpty) {
      await FinanceLedgerService().reverseTransaction(
        originalTransactionId: journalId, reversalId: reversalId, reversalNumber: 'REV-ADV-COR-${correctionId.hashCode.abs()}', reversalDate: DateTime.now(),
        accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts), transactionsBox: transactions,
        postingsBox: Hive.box<FinancePosting>(Boxes.financePostings), categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
        partiesBox: Hive.box<FinanceParty>(Boxes.financeParties), memo: 'Employee advance correction reversal: ${reason.trim()}',
      );
    } else if (reversals.length != 1) {
      throw const HrPayrollServiceException('Multiple reversals exist for this advance correction. Reconcile manually.');
    }
    advance['outstandingPaise'] = previous;
    advance['status'] = previous == 0 ? 'settled' : 'active';
    correction['status'] = 'reversed';
    correction['reversedAt'] = DateTime.now().toIso8601String();
    correction['reversalReason'] = reason.trim();
    correction['reversalJournalId'] = reversalId;
    corrections[index] = correction;
    advance['corrections'] = corrections;
    list[advanceIndex] = advance;
    all[employeeId] = list;
    await settings.put(advanceSettingsKey, all);
  }
  /// Compares the HR advance register with the posted Employee Advances control account.
  Map<String, int> advanceReconciliation() {
    final raw = Hive.box<dynamic>('app_settings').get(advanceSettingsKey);
    var subledgerPaise = 0;
    if (raw is Map) {
      for (final employeeAdvances in raw.values) {
        if (employeeAdvances is! List) continue;
        for (final item in employeeAdvances.whereType<Map>()) {
          final outstanding = item['outstandingPaise'];
          if (outstanding is int && outstanding > 0) subledgerPaise += outstanding;
        }
      }
    }
    final journalPaise = FinanceLedgerService().balancePaise(
      accountId: employeeAdvanceAccountId,
      transactionsBox: Hive.box<FinanceTransaction>(Boxes.financeTransactions),
      postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
    );
    return {
      'subledgerPaise': subledgerPaise,
      'journalPaise': journalPaise,
      'differencePaise': journalPaise - subledgerPaise,
    };
  }

  Future<void> _settlePayrollAdvanceDeductions(String payslipId) async {
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(advancePayrollKey);
    if (raw is! Map || raw[payslipId] is! List) return;
    final advancesRaw = settings.get(advanceSettingsKey);
    if (advancesRaw is! Map) throw const HrPayrollServiceException('Employee advance register is unavailable.');
    final all = Map<String, dynamic>.from(advancesRaw);
    final deductions = (raw[payslipId] as List).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in deductions) {
      final employeeId = item['employeeId'];
      final advanceId = item['advanceId'];
      final amount = item['amountPaise'];
      if (employeeId is! String || advanceId is! String || amount is! int || amount <= 0) throw const HrPayrollServiceException('Payroll advance recovery snapshot contains invalid references or amount.');
      grouped.putIfAbsent(employeeId, () => []).add(item);
    }
    // The payroll accrual journal already credits Employee Advances. Update only the HR subledger here.
    for (final group in grouped.entries) {
      final list = List<dynamic>.from(all[group.key] as List? ?? []);
      for (final deduction in group.value) {
        final advanceId = deduction['advanceId'] as String;
        final amount = deduction['amountPaise'] as int;
        final index = list.indexWhere((entry) => entry is Map && entry['id'] == advanceId);
        if (index < 0) throw const HrPayrollServiceException('Advance record disappeared before payroll accrual.');
        final advance = Map<String, dynamic>.from(list[index] as Map);
        final repayments = (advance['repayments'] as List? ?? []).whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList();
        final repaymentId = 'payroll:$payslipId:$advanceId';
        final existing = repayments.where((entry) => entry['id'] == repaymentId).toList();
        if (existing.isNotEmpty) {
          if (existing.length != 1 || existing.single['amountPaise'] != amount) throw const HrPayrollServiceException('Existing payroll advance recovery conflicts with the approved payslip.');
          continue;
        }
        final outstanding = advance['outstandingPaise'];
        if (outstanding is! int || amount > outstanding) throw const HrPayrollServiceException('Advance balance changed after payroll generation. Reconcile before approval.');
        repayments.add({'id': repaymentId, 'date': DateTime.now().toIso8601String(), 'amountPaise': amount, 'note': 'Payroll deduction accrued', 'source': 'payroll', 'payslipId': payslipId});
        final remaining = outstanding - amount;
        advance['outstandingPaise'] = remaining;
        advance['repayments'] = repayments;
        advance['status'] = remaining == 0 ? 'settled' : 'active';
        list[index] = advance;
      }
      all[group.key] = list;
    }
    await settings.put(advanceSettingsKey, all);
    final snapshots = Map<String, dynamic>.from(raw)..remove(payslipId);
    await settings.put(advancePayrollKey, snapshots);
  }
  static const bonusSettingsKey = 'hr_bonus_entries';

  List<Map<String, dynamic>> bonusEntries(String employeeId) {
    final raw = Hive.box<dynamic>('app_settings').get(bonusSettingsKey);
    if (raw is! Map || raw[employeeId] is! List) return const [];
    return (raw[employeeId] as List)
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .where((entry) =>
            entry['id'] is String &&
            entry['date'] is String &&
            entry['amountPaise'] is int &&
            entry['description'] is String)
        .toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
  }

  Future<void> addBonusEntry({
    required String employeeId,
    required DateTime date,
    required int amountPaise,
    String description = 'Bonus',
  }) async {
    if (Hive.box<Employee>(Boxes.employees).get(employeeId) == null) {
      throw const HrPayrollServiceException('Employee was not found.');
    }
    if (amountPaise <= 0) {
      throw const HrPayrollServiceException('Bonus amount must be positive.');
    }
    if (description.trim().isEmpty) {
      throw const HrPayrollServiceException('Enter a bonus description.');
    }
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(bonusSettingsKey);
    final allEntries = <String, dynamic>{
      if (raw is Map) ...Map<String, dynamic>.from(raw),
    };
    final entries = allEntries[employeeId] is List
        ? List<dynamic>.from(allEntries[employeeId] as List)
        : <dynamic>[];
    entries.add({
      'id': const Uuid().v4(),
      'date': _day(date).toIso8601String(),
      'amountPaise': amountPaise,
      'description': description.trim(),
      'createdAt': DateTime.now().toIso8601String(),
    });
    allEntries[employeeId] = entries;
    await settings.put(bonusSettingsKey, allEntries);
  }

  int _bonusPaise(String employeeId, DateTime start, DateTime end) {
    return bonusEntries(employeeId).where((entry) {
      final date = _day(DateTime.parse(entry['date'] as String));
      final status = entry['status'] ?? 'approved';
      return status == 'approved' && !date.isBefore(start) && !date.isAfter(end);
    }).fold<int>(
      0,
      (total, entry) => total + (entry['amountPaise'] as int),
    );
  }

  static const overtimeSettingsKey = 'hr_overtime_entries';

  List<Map<String, dynamic>> overtimeEntries(String employeeId) {
    final raw = Hive.box<dynamic>('app_settings').get(overtimeSettingsKey);
    if (raw is! Map || raw[employeeId] is! List) return const [];
    return (raw[employeeId] as List)
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .where((entry) =>
            entry['id'] is String &&
            entry['date'] is String &&
            entry['hoursMilli'] is int &&
            entry['hourlyRatePaise'] is int)
        .toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
  }

  Future<void> addOvertimeEntry({
    required String employeeId,
    required DateTime date,
    required double hours,
    required int hourlyRatePaise,
  }) async {
    if (Hive.box<Employee>(Boxes.employees).get(employeeId) == null) {
      throw const HrPayrollServiceException('Employee was not found.');
    }
    if (!hours.isFinite || hours <= 0 || hours > 24) {
      throw const HrPayrollServiceException('Overtime hours must be greater than zero and no more than 24.');
    }
    if (hourlyRatePaise <= 0) {
      throw const HrPayrollServiceException('Overtime hourly rate must be positive.');
    }
    final overtimeDate = _day(date);
    final hasPayrollSnapshot = Hive.box<PayrollRun>(Boxes.payrollRuns).values.any((run) =>
        !_day(run.periodEnd).isBefore(overtimeDate) &&
        !_day(run.periodStart).isAfter(overtimeDate));
    if (hasPayrollSnapshot) {
      throw const HrPayrollServiceException(
        'A payroll run already exists for this date. Record any correction through an approved payroll adjustment instead.',
      );
    }
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(overtimeSettingsKey);
    final allEntries = <String, dynamic>{
      if (raw is Map) ...Map<String, dynamic>.from(raw),
    };
    final entries = allEntries[employeeId] is List
        ? List<dynamic>.from(allEntries[employeeId] as List)
        : <dynamic>[];
    final hoursMilli = (hours * 1000).round();
    entries.add({
      'id': const Uuid().v4(),
      'date': _day(date).toIso8601String(),
      'hoursMilli': hoursMilli,
      'hourlyRatePaise': hourlyRatePaise,
      'amountPaise': (hoursMilli * hourlyRatePaise / 1000).round(),
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    });
    allEntries[employeeId] = entries;
    await settings.put(overtimeSettingsKey, allEntries);
  }

  Future<void> _updateOvertimeStatus({
    required String employeeId,
    required String entryId,
    required String status,
    String reason = '',
  }) async {
    if (!{'approved', 'rejected'}.contains(status)) {
      throw const HrPayrollServiceException('Unsupported overtime decision.');
    }
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(overtimeSettingsKey);
    if (raw is! Map || raw[employeeId] is! List) {
      throw const HrPayrollServiceException('Overtime entry was not found.');
    }
    final all = Map<String, dynamic>.from(raw);
    final entries = List<dynamic>.from(all[employeeId] as List);
    final matches = entries.where((item) => item is Map && item['id'] == entryId).toList();
    if (matches.length != 1) {
      throw const HrPayrollServiceException('Overtime entry must exist exactly once.');
    }
    final entry = Map<String, dynamic>.from(matches.single as Map);
    final entryDateValue = entry['date'];
    final entryDate = entryDateValue is String ? DateTime.tryParse(entryDateValue) : null;
    if (entryDate == null) {
      throw const HrPayrollServiceException('Overtime entry has an invalid date.');
    }
    final hasPayrollSnapshot = Hive.box<PayrollRun>(Boxes.payrollRuns).values.any((run) =>
        !_day(run.periodEnd).isBefore(_day(entryDate)) &&
        !_day(run.periodStart).isAfter(_day(entryDate)));
    if (hasPayrollSnapshot) {
      throw const HrPayrollServiceException(
        'A payroll run already contains this date. Do not change overtime after payslip generation; correct it through an approved payroll adjustment.',
      );
    }
    // Missing status is treated as approved for records created before this workflow.
    if ((entry['status'] ?? 'approved') != 'pending') {
      throw const HrPayrollServiceException('Only pending overtime entries can be reviewed.');
    }
    entry['status'] = status;
    entry['reviewedAt'] = DateTime.now().toIso8601String();
    entry['reviewNote'] = reason.trim();
    entries[entries.indexWhere((item) => item is Map && item['id'] == entryId)] = entry;
    all[employeeId] = entries;
    await settings.put(overtimeSettingsKey, all);
  }

  Future<void> approveOvertimeEntry({
    required String employeeId,
    required String entryId,
    String note = '',
  }) => _updateOvertimeStatus(
        employeeId: employeeId,
        entryId: entryId,
        status: 'approved',
        reason: note,
      );

  Future<void> rejectOvertimeEntry({
    required String employeeId,
    required String entryId,
    required String reason,
  }) {
    if (reason.trim().isEmpty) {
      throw const HrPayrollServiceException('Enter a reason for rejecting overtime.');
    }
    return _updateOvertimeStatus(
      employeeId: employeeId,
      entryId: entryId,
      status: 'rejected',
      reason: reason,
    );
  }

  int _approvedOvertimePaise(String employeeId, DateTime start, DateTime end) {
    return overtimeEntries(employeeId).where((entry) {
      final date = _day(DateTime.parse(entry['date'] as String));
      // Legacy records without a status remain approved for compatibility.
      final status = entry['status'] ?? 'approved';
      return status == 'approved' &&
          !date.isBefore(start) && !date.isAfter(end);
    }).fold<int>(
      0,
      (total, entry) => total + (entry['amountPaise'] as int),
    );
  }

  Future<PayrollRun> generateRun({
    required DateTime periodStart,
    required DateTime periodEnd,
    String memo = '',
  }) async {
    final start = _day(periodStart);
    final end = _day(periodEnd);
    if (end.isBefore(start)) {
      throw const HrPayrollServiceException(
        'Payroll period end cannot be before its start.',
      );
    }

    final employeesBox = Hive.box<Employee>(Boxes.employees);
    final componentsBox =
        Hive.box<SalaryComponent>(Boxes.salaryComponents);
    final runsBox = Hive.box<PayrollRun>(Boxes.payrollRuns);
    final payslipsBox = Hive.box<Payslip>(Boxes.payslips);
    final runId = _periodId(start, end);
    if (runsBox.containsKey(runId) ||
        runsBox.values.any((run) =>
            _day(run.periodStart) == start && _day(run.periodEnd) == end)) {
      throw const HrPayrollServiceException(
        'A payroll run already exists for this period.',
      );
    }

    final activeEmployees = employeesBox.values
        .where((employee) => employee.employmentStatus == 'active')
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final slips = <Payslip>[];
    var grossTotal = 0;
    var deductionTotal = 0;
    var netTotal = 0;

    for (final employee in activeEmployees) {
      final payType =
          employee.type == PayrollService.typeDaily ? 'daily' : 'monthly';
      final attendance = HrService().summarizeAttendance(
        employeeId: employee.id,
        start: start,
        end: end,
      );
      final workTerms = HrService().employeeWorkTerms(employee);
      final frequency = workTerms['payFrequency'] ?? 'monthly';
      final basePaise = _basePayPaiseForPeriod(
        employee: employee,
        start: start,
        end: end,
        frequency: frequency,
        payType: payType,
      );

      final components = componentsBox.values.where((component) =>
          component.employeeId == employee.id &&
          component.active &&
          !component.effectiveFrom.isAfter(end) &&
          (component.effectiveTo == null ||
              !_day(component.effectiveTo!).isBefore(start)));
      var allowances = 0;
      var deductions = 0;
      for (final component in components) {
        if (component.componentType == 'earning') {
          allowances += component.amountPaise;
        } else if (component.componentType == 'deduction') {
          deductions += component.amountPaise;
        }
      }
      final overtime = _approvedOvertimePaise(employee.id, start, end);
      final bonus = _bonusPaise(employee.id, start, end);
      final advanceDeductions = _advanceDeductionPaise(employee.id, start, end);
      final gross = basePaise + allowances + overtime + bonus;
      final totalDeductions = deductions + advanceDeductions;
      final net = gross - totalDeductions;
      if (net < 0) {
        throw HrPayrollServiceException(
          'Deductions exceed gross pay for ${employee.name}.',
        );
      }

      final slip = Payslip(
        id: '$runId:${Uri.encodeComponent(employee.id)}',
        payrollRunId: runId,
        employeeId: employee.id,
        payType: payType,
        basePaise: basePaise,
        allowancesPaise: allowances + overtime + bonus,
        deductionsPaise: totalDeductions,
        payableDays: attendance.payableDays,
      );
      slips.add(slip);
      grossTotal += gross;
      deductionTotal += totalDeductions;
      netTotal += net;
    }

    final run = PayrollRun(
      id: runId,
      periodStart: start,
      periodEnd: end,
      totalGrossPaise: grossTotal,
      totalDeductionsPaise: deductionTotal,
      totalNetPaise: netTotal,
      memo: memo.trim(),
    );

    final insertedSlipIds = <String>[];
    final advanceSnapshots = <String,dynamic>{};
    try {
      await runsBox.put(run.id, run);
      for (final slip in slips) {
        await payslipsBox.put(slip.id, slip);
        insertedSlipIds.add(slip.id);
        final snapshot = _advanceDeductionSnapshot(slip.employeeId, start, end);
        if (snapshot.isNotEmpty) advanceSnapshots[slip.id] = snapshot;
      }
      if (advanceSnapshots.isNotEmpty) {
        final settings = Hive.box<dynamic>('app_settings');
        final raw = settings.get(advancePayrollKey);
        await settings.put(advancePayrollKey, <String,dynamic>{
          if (raw is Map) ...Map<String,dynamic>.from(raw),
          ...advanceSnapshots,
        });
      }
    } catch (_) {
      for (final id in insertedSlipIds.reversed) {
        try {
          await payslipsBox.delete(id);
        } catch (_) {}
      }
      try {
        await runsBox.delete(run.id);
      } catch (_) {}
      rethrow;
    }
    return run;
  }

  static const payrollPayableAccountId = 'system:payroll-payable';
  static const payrollDeductionsPayableAccountId = 'system:payroll-deductions-payable';

  int _advanceSnapshotTotal(String payslipId) {
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(advancePayrollKey);
    if (raw is Map && raw[payslipId] is List) {
      return (raw[payslipId] as List).whereType<Map>().fold<int>(0, (sum, item) {
        final amount = item['amountPaise'];
        if (amount is! int || amount < 0) throw const HrPayrollServiceException('Invalid payroll advance deduction snapshot.');
        return sum + amount;
      });
    }
    final advances = settings.get(advanceSettingsKey);
    if (advances is! Map) return 0;
    var total = 0;
    for (final employeeRecords in advances.values) {
      if (employeeRecords is! List) continue;
      for (final advance in employeeRecords.whereType<Map>()) {
        final repayments = advance['repayments'];
        if (repayments is! List) continue;
        for (final repayment in repayments.whereType<Map>()) {
          if (repayment['source'] == 'payroll' && repayment['payslipId'] == payslipId) {
            final amount = repayment['amountPaise'];
            if (amount is! int || amount <= 0) throw const HrPayrollServiceException('Recorded payroll advance recovery is malformed.');
            total += amount;
          }
        }
      }
    }
    return total;
  }

  void _requirePayrollAccount(String id, String type) {
    final account = Hive.box<FinanceAccount>(Boxes.financeAccounts).get(id);
    if (account == null || !account.active || account.accountType != type || account.currencyCode != 'INR') throw HrPayrollServiceException('Required payroll account $id is unavailable or invalid.');
  }

  Future<void> _postPayrollAccrual(Payslip slip, PayrollRun run) async {
    final gross = slip.basePaise + slip.allowancesPaise;
    final deductions = slip.deductionsPaise;
    final net = slip.netPaise;
    final advance = _advanceSnapshotTotal(slip.id);
    final other = deductions - advance;
    if (gross < 0 || deductions < 0 || net < 0 || gross != deductions + net || other < 0) throw HrPayrollServiceException('Payslip ${slip.id} has inconsistent gross, deduction, or net totals.');
    if (gross == 0) return;
    _requirePayrollAccount('system:salary-expense', 'expense');
    _requirePayrollAccount(payrollPayableAccountId, 'liability');
    if (advance > 0) _requirePayrollAccount(employeeAdvanceAccountId, 'asset');
    if (other > 0) _requirePayrollAccount(payrollDeductionsPayableAccountId, 'liability');
    final id = 'finance:payroll-accrual:${slip.id}';
    final txBox = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    final postingBox = Hive.box<FinancePosting>(Boxes.financePostings);
    final existing = txBox.values.where((tx) => tx.sourceType == 'payroll_accrual' && tx.sourceId == slip.id).toList();
    if (existing.isNotEmpty) {
      if (existing.length != 1 || existing.single.id != id || existing.single.status != 'posted' ||
          txBox.values.any((tx) => tx.transactionType == 'reversal' && tx.reversedTransactionId == id && tx.status == 'posted')) {
        throw const HrPayrollServiceException('Conflicting or reversed payroll accrual journal exists.');
      }
      final lines = postingBox.values.where((line) => line.transactionId == id).toList();
      int netFor(String account) => lines.where((line) => line.accountId == account).fold<int>(0, (sum, line) => sum + line.debitPaise - line.creditPaise);
      final expectedCount = 1 + (net > 0 ? 1 : 0) + (advance > 0 ? 1 : 0) + (other > 0 ? 1 : 0);
      if (lines.length != expectedCount || netFor('system:salary-expense') != gross || netFor(payrollPayableAccountId) != -net || netFor(employeeAdvanceAccountId) != -advance || netFor(payrollDeductionsPayableAccountId) != -other) throw const HrPayrollServiceException('Existing payroll accrual journal does not match the payslip snapshot.');
      return;
    }
    final lines = <FinancePosting>[
      FinancePosting(id: '$id:salary-expense', transactionId: id, accountId: 'system:salary-expense', debitPaise: gross, memo: 'Gross salary accrued for payroll run ${run.id}'),
    ];
    if (net > 0) lines.add(FinancePosting(id: '$id:payroll-payable', transactionId: id, accountId: payrollPayableAccountId, creditPaise: net, memo: 'Net salary payable'));
    if (advance > 0) lines.add(FinancePosting(id: '$id:employee-advances', transactionId: id, accountId: employeeAdvanceAccountId, creditPaise: advance, memo: 'Employee advance deduction accrued'));
    if (other > 0) lines.add(FinancePosting(id: '$id:deductions-payable', transactionId: id, accountId: payrollDeductionsPayableAccountId, creditPaise: other, memo: 'Other payroll deductions withheld'));
    await FinanceLedgerService().postTransaction(
      transaction: FinanceTransaction(id: id, transactionNumber: 'PAY-ACC-${slip.id}', transactionType: 'adjustment', date: run.periodEnd, memo: 'Payroll accrual for ${slip.employeeId}, run ${run.id}', sourceType: 'payroll_accrual', sourceId: slip.id),
      postings: lines, accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts), transactionsBox: txBox, postingsBox: postingBox,
      categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories), partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
    );
  }

  Future<void> _postPayrollPaymentJournal({required Payslip slip, required int amountPaise, required int paidBeforePaise, required String cashAccountId, required DateTime date}) async {
    _requirePayrollAccount(payrollPayableAccountId, 'liability');
    _requireAdvanceCashAccount(cashAccountId);
    final sourceId = '${slip.id}:from:$paidBeforePaise';
    final id = 'finance:payroll-payment:$sourceId';
    final txBox = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    final postingBox = Hive.box<FinancePosting>(Boxes.financePostings);
    final existing = txBox.values.where((tx) => tx.sourceType == 'payroll_payment' && tx.sourceId == sourceId).toList();
    if (existing.isNotEmpty) {
      if (existing.length != 1 || existing.single.id != id || existing.single.status != 'posted' ||
          txBox.values.any((tx) => tx.transactionType == 'reversal' && tx.reversedTransactionId == id && tx.status == 'posted')) {
        throw const HrPayrollServiceException('Conflicting or reversed payroll payment journal exists.');
      }
      final lines = postingBox.values.where((line) => line.transactionId == id).toList();
      final debit = lines.where((line) => line.accountId == payrollPayableAccountId).fold<int>(0, (sum, line) => sum + line.debitPaise);
      final credit = lines.where((line) => line.accountId == cashAccountId).fold<int>(0, (sum, line) => sum + line.creditPaise);
      if (lines.length != 2 || debit != amountPaise || credit != amountPaise) throw const HrPayrollServiceException('Existing payroll payment journal does not match this payment request.');
      return;
    }
    await FinanceLedgerService().postTransaction(
      transaction: FinanceTransaction(id: id, transactionNumber: 'PAY-SET-${slip.id}-$paidBeforePaise', transactionType: 'adjustment', date: date, memo: 'Payroll payment for payslip ${slip.id}', sourceType: 'payroll_payment', sourceId: sourceId),
      postings: [
        FinancePosting(id: '$id:payroll-payable', transactionId: id, accountId: payrollPayableAccountId, debitPaise: amountPaise, memo: 'Settle employee net salary payable'),
        FinancePosting(id: '$id:cash', transactionId: id, accountId: cashAccountId, creditPaise: amountPaise, memo: 'Payroll payment'),
      ],
      accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts), transactionsBox: txBox, postingsBox: postingBox,
      categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories), partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
    );
  }
  Future<PayrollRun> approveRun(String runId) async {
    final runsBox = Hive.box<PayrollRun>(Boxes.payrollRuns);
    final slipsBox = Hive.box<Payslip>(Boxes.payslips);
    final run = runsBox.get(runId);
    if (run == null || run.status != 'draft') throw const HrPayrollServiceException('Only draft payroll runs can be approved.');
    final slips = slipsBox.values.where((slip) => slip.payrollRunId == runId).toList()..sort((a, b) => a.id.compareTo(b.id));
    final approvedAt = DateTime.now();
    // Stable source IDs make an interrupted accrual retry-safe.
    for (final slip in slips) {
      await _postPayrollAccrual(slip, run);
    }
    for (final slip in slips) {
      await _settlePayrollAdvanceDeductions(slip.id);
    }
    for (final slip in slips) {
      final updated = _copyPayslip(slip, status: slip.netPaise == 0 ? 'paid' : 'approved', paidAt: slip.netPaise == 0 ? approvedAt : slip.paidAt);
      await slipsBox.put(updated.id, updated);
    }
    final allSettled = slips.every((slip) => slip.netPaise == 0);
    final updatedRun = _copyRun(run, status: allSettled ? 'paid' : 'approved', approvedAt: approvedAt, paidAt: allSettled ? approvedAt : null);
    await runsBox.put(updatedRun.id, updatedRun);
    return updatedRun;
  }
  Future<Payslip> payPayslip({
    required String payslipId,
    required int amountPaise,
    String cashAccountId = 'system:cash',
  }) async {
    if (amountPaise <= 0) throw const HrPayrollServiceException('Payment amount must be positive.');
    _requireAdvanceCashAccount(cashAccountId);
    final runsBox = Hive.box<PayrollRun>(Boxes.payrollRuns);
    final slipsBox = Hive.box<Payslip>(Boxes.payslips);
    final slip = slipsBox.get(payslipId);
    if (slip == null) throw const HrPayrollServiceException('Payslip was not found.');
    final run = runsBox.get(slip.payrollRunId);
    if (run == null || (run.status != 'approved' && run.status != 'paid')) throw const HrPayrollServiceException('Approve the payroll run before recording payment.');
    if (slip.status == 'paid') {
      await _refreshRunStatus(run, slipsBox);
      return slip;
    }
    if (slip.status != 'approved' && slip.status != 'partially_paid') throw const HrPayrollServiceException('Payslip is not in a payable state.');
    if (amountPaise > slip.outstandingPaise) throw const HrPayrollServiceException('Payment cannot exceed the payslip outstanding amount.');
    final payrollTransactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    final accruals = payrollTransactions.values.where((tx) =>
        tx.sourceType == 'payroll_accrual' && tx.sourceId == slip.id).toList();
    if (accruals.length > 1 ||
        (accruals.length == 1 && (accruals.single.status != 'posted' ||
            payrollTransactions.values.any((tx) => tx.transactionType == 'reversal' &&
                tx.reversedTransactionId == accruals.single.id && tx.status == 'posted')))) {
      throw const HrPayrollServiceException('Payroll accrual is conflicting or reversed. Reconcile it before paying this payslip.');
    }
    final accrualExists = accruals.length == 1;
    if (!accrualExists) {
      // Compatibility path for payroll runs approved before accrual accounting was introduced.
      final expensesBox = Hive.box<Expense>(Boxes.expenses);
      final paymentId = 'payroll-payment:${slip.id}:from:${slip.paidPaise}';
      final existingPayment = expensesBox.get(paymentId);
      final actualPaymentPaise = existingPayment == null ? amountPaise : _rupeesToPaise(existingPayment.amount, 'Existing payroll payment');
      if (actualPaymentPaise > slip.outstandingPaise) throw const HrPayrollServiceException('Existing payroll payment exceeds the remaining payslip balance.');
      if (existingPayment == null) {
        final employee = Hive.box<Employee>(Boxes.employees).get(slip.employeeId);
        if (employee == null) throw const HrPayrollServiceException('Payslip employee record is missing.');
        await expensesBox.put(paymentId, Expense(id: paymentId, date: DateTime.now(), category: 'Salary-Run', amount: amountPaise / 100, description: 'Legacy payroll run ${run.id}, payslip ${slip.id}; account=$cashAccountId', employeeId: slip.employeeId));
      }
      final expense = expensesBox.get(paymentId)!;
      await FinanceSourceSyncService().syncExpense(
        expense: expense,
        accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts),
        transactionsBox: Hive.box<FinanceTransaction>(Boxes.financeTransactions),
        postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
        categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
        partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
        employeesBox: Hive.box<Employee>(Boxes.employees),
        paymentAccountId: cashAccountId,
      );
      final legacyJournalId = 'finance:expense:${expense.id}:r${expense.financeRevision}';
      final legacyCredits = Hive.box<FinancePosting>(Boxes.financePostings).values.where((line) => line.transactionId == legacyJournalId && line.creditPaise > 0).toList();
      if (legacyCredits.length != 1 || legacyCredits.single.accountId != cashAccountId) throw const HrPayrollServiceException('Legacy payroll payment journal does not match the selected account. Reconcile it before continuing.');
      final legacyPaid = slip.paidPaise + actualPaymentPaise;
      final legacyUpdated = _copyPayslip(slip, paidPaise: legacyPaid, status: legacyPaid >= slip.netPaise ? 'paid' : 'partially_paid', paidAt: legacyPaid >= slip.netPaise ? DateTime.now() : null);
      if (legacyUpdated.status == 'paid') {
        await _postPayrollAdvanceRecoveryJournal(payslipId: slip.id, date: legacyUpdated.paidAt ?? DateTime.now(), amountPaise: _advanceSnapshotTotal(slip.id));
        await _settlePayrollAdvanceDeductions(legacyUpdated.id);
      }
      await slipsBox.put(legacyUpdated.id, legacyUpdated);
      await _refreshRunStatus(run, slipsBox);
      return legacyUpdated;
    }
    final paymentDate = DateTime.now();
    try {
      await _postPayrollPaymentJournal(slip: slip, amountPaise: amountPaise, paidBeforePaise: slip.paidPaise, cashAccountId: cashAccountId, date: paymentDate);
    } catch (error) {
      if (Hive.isBoxOpen('app_settings')) await FinanceSourceSyncService.recordIssue(Hive.box<dynamic>('app_settings'), 'Payroll run ${run.id}, payslip ${slip.id}: $error');
      throw HrPayrollServiceException('Payroll payment journal could not be posted. The payslip remains unpaid. Details: $error');
    }
    final paidPaise = slip.paidPaise + amountPaise;
    final updatedSlip = _copyPayslip(slip, paidPaise: paidPaise, status: paidPaise >= slip.netPaise ? 'paid' : 'partially_paid', paidAt: paidPaise >= slip.netPaise ? paymentDate : null);
    await slipsBox.put(updatedSlip.id, updatedSlip);
    await _refreshRunStatus(run, slipsBox);
    return updatedSlip;
  }
  Future<Payslip> adjustApprovedPayslip({
    required String payslipId,
    required String adjustmentType,
    required int amountPaise,
    required DateTime effectiveDate,
    required String reason,
  }) async {
    const types = {'earning_increase', 'earning_decrease', 'deduction_increase', 'deduction_decrease'};
    if (!types.contains(adjustmentType) || amountPaise <= 0 || reason.trim().isEmpty) throw const HrPayrollServiceException('Choose a valid adjustment, positive amount, and reason.');
    final slipsBox = Hive.box<Payslip>(Boxes.payslips);
    final runsBox = Hive.box<PayrollRun>(Boxes.payrollRuns);
    final slip = slipsBox.get(payslipId);
    if (slip == null) throw const HrPayrollServiceException('Payslip was not found.');
    if (slip.status != 'approved' && slip.status != 'partially_paid') throw const HrPayrollServiceException('Only unpaid or partially paid approved payslips can be adjusted.');
    final hasAccrual = Hive.box<FinanceTransaction>(Boxes.financeTransactions).values.any((tx) =>
        tx.sourceType == 'payroll_accrual' && tx.sourceId == slip.id && tx.status == 'posted');
    if (!hasAccrual) throw const HrPayrollServiceException('Legacy cash-basis payroll cannot use accrual adjustments. Correct its original expense/payment records instead.');
    final run = runsBox.get(slip.payrollRunId);
    if (run == null || (run.status != 'approved' && run.status != 'paid')) throw const HrPayrollServiceException('Payroll run must be approved before making an adjustment.');
    final date = _day(effectiveDate);
    if (date.isBefore(_day(run.periodStart)) || date.isAfter(_day(DateTime.now()))) throw const HrPayrollServiceException('Adjustment date must be within the payroll period and cannot be in the future.');
    final earningDelta = adjustmentType == 'earning_increase' ? amountPaise : adjustmentType == 'earning_decrease' ? -amountPaise : 0;
    final deductionDelta = adjustmentType == 'deduction_increase' ? amountPaise : adjustmentType == 'deduction_decrease' ? -amountPaise : 0;
    final newAllowances = slip.allowancesPaise + earningDelta;
    final newDeductions = slip.deductionsPaise + deductionDelta;
    final newNet = slip.basePaise + newAllowances - newDeductions;
    final advanceDeductions = _advanceSnapshotTotal(slip.id);
    if (newDeductions < advanceDeductions) throw const HrPayrollServiceException('This adjustment cannot remove an employee advance deduction already accrued to the Employee Advances account.');
    if (newAllowances < 0 || newDeductions < 0 || newNet < slip.paidPaise) throw const HrPayrollServiceException('Adjustment would create a negative component or reduce net pay below the amount already paid.');
    final netDelta = earningDelta - deductionDelta;
    final accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    _requirePayrollAccount('system:salary-expense', 'expense');
    _requirePayrollAccount(payrollPayableAccountId, 'liability');
    _requirePayrollAccount(payrollDeductionsPayableAccountId, 'liability');
    final debitAccount = switch (adjustmentType) {
      'earning_increase' => 'system:salary-expense',
      'earning_decrease' => payrollPayableAccountId,
      'deduction_increase' => payrollPayableAccountId,
      _ => payrollDeductionsPayableAccountId,
    };
    final creditAccount = switch (adjustmentType) {
      'earning_increase' => payrollPayableAccountId,
      'earning_decrease' => 'system:salary-expense',
      'deduction_increase' => payrollDeductionsPayableAccountId,
      _ => payrollPayableAccountId,
    };
    if (debitAccount == payrollPayableAccountId && amountPaise > slip.outstandingPaise) throw const HrPayrollServiceException('Adjustment exceeds the payslip net amount still payable.');
    if (adjustmentType == 'deduction_decrease') {
      final liabilityBalance = -FinanceLedgerService().balancePaise(accountId: payrollDeductionsPayableAccountId, transactionsBox: Hive.box<FinanceTransaction>(Boxes.financeTransactions), postingsBox: Hive.box<FinancePosting>(Boxes.financePostings));
      if (amountPaise > liabilityBalance) throw const HrPayrollServiceException('The payroll deductions payable control account does not contain enough withheld balance for this correction.');
    }
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(payrollAdjustmentsKey);
    final all = <String, dynamic>{if (raw is Map) ...Map<String, dynamic>.from(raw)};
    final history = (all[payslipId] is List ? List<dynamic>.from(all[payslipId] as List) : <dynamic>[]);
    final dateKey = '${date.year.toString().padLeft(4, '0')}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final sourceId = '${slip.id}:adjustment:$adjustmentType:$amountPaise:$dateKey:${reason.trim()}';
    final adjustmentId = Uri.encodeComponent(sourceId);
    final existingRecord = history.whereType<Map>().where((item) => item['id'] == adjustmentId).toList();
    if (existingRecord.isNotEmpty && existingRecord.length != 1) throw const HrPayrollServiceException('Duplicate payroll adjustment records require reconciliation.');
    final beforeAllowances = slip.allowancesPaise;
    final beforeDeductions = slip.deductionsPaise;
    final afterAllowances = beforeAllowances + earningDelta;
    final afterDeductions = beforeDeductions + deductionDelta;
    Map<String, dynamic> record;
    if (existingRecord.isEmpty) {
      record = {'id': adjustmentId, 'payslipId': slip.id, 'type': adjustmentType, 'amountPaise': amountPaise, 'date': date.toIso8601String(), 'reason': reason.trim(), 'beforeAllowancesPaise': beforeAllowances, 'beforeDeductionsPaise': beforeDeductions, 'afterAllowancesPaise': afterAllowances, 'afterDeductionsPaise': afterDeductions, 'beforeRunGrossPaise': run.totalGrossPaise, 'beforeRunDeductionsPaise': run.totalDeductionsPaise, 'beforeRunNetPaise': run.totalNetPaise, 'afterRunGrossPaise': run.totalGrossPaise + earningDelta, 'afterRunDeductionsPaise': run.totalDeductionsPaise + deductionDelta, 'afterRunNetPaise': run.totalNetPaise + netDelta, 'status': 'pending'};
      history.add(record);
      all[payslipId] = history;
      await settings.put(payrollAdjustmentsKey, all);
    } else {
      record = Map<String, dynamic>.from(existingRecord.single);
      if (record['type'] != adjustmentType || record['amountPaise'] != amountPaise || record['reason'] != reason.trim()) throw const HrPayrollServiceException('Existing payroll adjustment identity conflicts with this request.');
      final currentMatchesBefore = slip.allowancesPaise == record['beforeAllowancesPaise'] && slip.deductionsPaise == record['beforeDeductionsPaise'];
      final currentMatchesAfter = slip.allowancesPaise == record['afterAllowancesPaise'] && slip.deductionsPaise == record['afterDeductionsPaise'];
      if (!currentMatchesBefore && !currentMatchesAfter) throw const HrPayrollServiceException('Payslip changed after this adjustment was initiated. Reconcile before retrying.');
    }
    final transactionId = 'finance:payroll-adjustment:$adjustmentId';
    final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    final postings = Hive.box<FinancePosting>(Boxes.financePostings);
    final existingJournal = transactions.values.where((tx) => tx.sourceType == 'payroll_adjustment' && tx.sourceId == adjustmentId).toList();
    if (existingJournal.isEmpty) {
      await FinanceLedgerService().postTransaction(
        transaction: FinanceTransaction(id: transactionId, transactionNumber: 'PAY-ADJ-$dateKey-${adjustmentId.hashCode.abs()}', transactionType: 'adjustment', date: date, memo: 'Payroll adjustment for $payslipId: ${reason.trim()}', sourceType: 'payroll_adjustment', sourceId: adjustmentId),
        postings: [
          FinancePosting(id: '$transactionId:debit', transactionId: transactionId, accountId: debitAccount, debitPaise: amountPaise, memo: reason.trim()),
          FinancePosting(id: '$transactionId:credit', transactionId: transactionId, accountId: creditAccount, creditPaise: amountPaise, memo: reason.trim()),
        ],
        accountsBox: accounts, transactionsBox: transactions, postingsBox: postings,
        categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories), partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
      );
    } else {
      if (existingJournal.length != 1 || existingJournal.single.id != transactionId || existingJournal.single.status != 'posted' ||
          transactions.values.any((tx) => tx.transactionType == 'reversal' && tx.reversedTransactionId == transactionId && tx.status == 'posted')) {
        throw const HrPayrollServiceException('Conflicting or reversed payroll adjustment journal exists.');
      }
      final lines = postings.values.where((line) => line.transactionId == transactionId).toList();
      if (lines.length != 2 || lines.where((line) => line.accountId == debitAccount).fold<int>(0, (sum, line) => sum + line.debitPaise) != amountPaise || lines.where((line) => line.accountId == creditAccount).fold<int>(0, (sum, line) => sum + line.creditPaise) != amountPaise) throw const HrPayrollServiceException('Existing payroll adjustment journal does not match this adjustment.');
    }
    final current = slipsBox.get(payslipId)!;
    final currentMatchesBefore = current.allowancesPaise == record['beforeAllowancesPaise'] &&
        current.deductionsPaise == record['beforeDeductionsPaise'];
    final currentMatchesAfter = current.allowancesPaise == record['afterAllowancesPaise'] &&
        current.deductionsPaise == record['afterDeductionsPaise'];
    if (!currentMatchesBefore && !currentMatchesAfter) {
      throw const HrPayrollServiceException('Payslip changed while the payroll adjustment was being applied.');
    }
    if (currentMatchesBefore) {
      final updated = _copyPayslip(
        current,
        allowancesPaise: record['afterAllowancesPaise'] as int,
        deductionsPaise: record['afterDeductionsPaise'] as int,
        status: (current.basePaise + (record['afterAllowancesPaise'] as int) -
                    (record['afterDeductionsPaise'] as int)) == current.paidPaise
            ? 'paid'
            : current.status,
        paidAt: (current.basePaise + (record['afterAllowancesPaise'] as int) -
                    (record['afterDeductionsPaise'] as int)) == current.paidPaise
            ? DateTime.now()
            : current.paidAt,
      );
      await slipsBox.put(updated.id, updated);
    }
    var latestRun = runsBox.get(run.id)!;
    final runMatchesBefore = latestRun.totalGrossPaise == record['beforeRunGrossPaise'] &&
        latestRun.totalDeductionsPaise == record['beforeRunDeductionsPaise'] &&
        latestRun.totalNetPaise == record['beforeRunNetPaise'];
    final runMatchesAfter = latestRun.totalGrossPaise == record['afterRunGrossPaise'] &&
        latestRun.totalDeductionsPaise == record['afterRunDeductionsPaise'] &&
        latestRun.totalNetPaise == record['afterRunNetPaise'];
    if (runMatchesBefore) {
      latestRun = _copyRun(
        latestRun,
        totalGrossPaise: record['afterRunGrossPaise'] as int,
        totalDeductionsPaise: record['afterRunDeductionsPaise'] as int,
        totalNetPaise: record['afterRunNetPaise'] as int,
      );
      await runsBox.put(latestRun.id, latestRun);
    } else if (!runMatchesAfter) {
      throw const HrPayrollServiceException('Payroll run totals changed while the adjustment was being applied.');
    }
    await _refreshRunStatus(latestRun, slipsBox);
    final latest = settings.get(payrollAdjustmentsKey);
    final latestAll = <String, dynamic>{if (latest is Map) ...Map<String, dynamic>.from(latest)};
    final latestHistory = List<dynamic>.from(latestAll[payslipId] as List? ?? []);
    final recordIndex = latestHistory.indexWhere((item) => item is Map && item['id'] == adjustmentId);
    if (recordIndex >= 0) {
      final postedRecord = Map<String, dynamic>.from(latestHistory[recordIndex] as Map)..['status'] = 'posted'..['journalId'] = transactionId;
      latestHistory[recordIndex] = postedRecord;
      latestAll[payslipId] = latestHistory;
      await settings.put(payrollAdjustmentsKey, latestAll);
    }
    return slipsBox.get(payslipId)!;
  }
  Future<void> reversePayrollAdjustment({required String payslipId, required String adjustmentId, required String reason}) async {
    if (reason.trim().isEmpty) throw const HrPayrollServiceException('A reversal reason is required.');
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(payrollAdjustmentsKey);
    if (raw is! Map || raw[payslipId] is! List) throw const HrPayrollServiceException('Payroll adjustment history was not found.');
    final all = <String, dynamic>{...Map<String, dynamic>.from(raw)};
    final history = List<dynamic>.from(all[payslipId] as List);
    final index = history.indexWhere((entry) => entry is Map && entry['id'] == adjustmentId);
    if (index < 0) throw const HrPayrollServiceException('Payroll adjustment was not found.');
    final record = Map<String, dynamic>.from(history[index] as Map);
    if (record['status'] == 'reversed') return;
    if (record['status'] != 'posted') throw const HrPayrollServiceException('Only a posted payroll adjustment can be reversed.');
    if (history.skip(index + 1).whereType<Map>().any((entry) => entry['status'] == 'posted' || entry['status'] == 'pending')) throw const HrPayrollServiceException('Reverse later payroll adjustments first. Only the latest adjustment can be reversed.');
    final slipsBox = Hive.box<Payslip>(Boxes.payslips);
    final runsBox = Hive.box<PayrollRun>(Boxes.payrollRuns);
    final slip = slipsBox.get(payslipId);
    if (slip == null) throw const HrPayrollServiceException('Payslip was not found.');
    final run = runsBox.get(slip.payrollRunId);
    if (run == null) throw const HrPayrollServiceException('Payroll run was not found.');
    final type = record['type'];
    final amount = record['amountPaise'];
    if (type is! String || amount is! int || amount <= 0) throw const HrPayrollServiceException('Payroll adjustment history is malformed.');
    final earningDelta = type == 'earning_increase' ? amount : type == 'earning_decrease' ? -amount : 0;
    final deductionDelta = type == 'deduction_increase' ? amount : type == 'deduction_decrease' ? -amount : 0;
    final restoredAllowances = slip.allowancesPaise - earningDelta;
    final restoredDeductions = slip.deductionsPaise - deductionDelta;
    final restoredNet = slip.basePaise + restoredAllowances - restoredDeductions;
    if (restoredAllowances < 0 || restoredDeductions < 0 || restoredNet < slip.paidPaise) throw const HrPayrollServiceException('Reversing this adjustment would make the recorded salary payment exceed the corrected payslip. Resolve the employee recovery separately.');
    final transactionId = record['journalId'] is String ? record['journalId'] as String : 'finance:payroll-adjustment:$adjustmentId';
    final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    final original = transactions.get(transactionId);
    if (original == null || original.status != 'posted') throw const HrPayrollServiceException('Original payroll adjustment journal is unavailable.');
    final reversalId = 'finance:reversal:$transactionId';
    final existingReversal = transactions.values.where((tx) => tx.transactionType == 'reversal' && tx.reversedTransactionId == transactionId && tx.status == 'posted').toList();
    if (existingReversal.isEmpty) {
      await FinanceLedgerService().reverseTransaction(
        originalTransactionId: transactionId, reversalId: reversalId, reversalNumber: 'REV-PAY-ADJ-${adjustmentId.hashCode.abs()}', reversalDate: DateTime.now(),
        accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts), transactionsBox: transactions,
        postingsBox: Hive.box<FinancePosting>(Boxes.financePostings), categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
        partiesBox: Hive.box<FinanceParty>(Boxes.financeParties), memo: 'Payroll adjustment reversal: ${reason.trim()}',
      );
    } else if (existingReversal.length != 1) {
      throw const HrPayrollServiceException('Multiple reversals exist for this payroll adjustment. Reconcile manually.');
    }
    final updatedSlip = _copyPayslip(
      slip, allowancesPaise: restoredAllowances, deductionsPaise: restoredDeductions,
      status: restoredNet == slip.paidPaise ? 'paid' : slip.paidPaise > 0 ? 'partially_paid' : 'approved',
      clearPaidAt: restoredNet != slip.paidPaise,
    );
    await slipsBox.put(updatedSlip.id, updatedSlip);
    final updatedRun = _copyRun(
      run,
      status: restoredNet != slip.paidPaise && run.status == 'paid' ? 'approved' : run.status,
      clearPaidAt: restoredNet != slip.paidPaise && run.status == 'paid',
      totalGrossPaise: run.totalGrossPaise - earningDelta,
      totalDeductionsPaise: run.totalDeductionsPaise - deductionDelta,
      totalNetPaise: run.totalNetPaise - earningDelta + deductionDelta,
    );
    await runsBox.put(updatedRun.id, updatedRun);
    record['status'] = 'reversed';
    record['reversedAt'] = DateTime.now().toIso8601String();
    record['reversalJournalId'] = reversalId;
    record['reversalReason'] = reason.trim();
    history[index] = record;
    all[payslipId] = history;
    await settings.put(payrollAdjustmentsKey, all);
    await _refreshRunStatus(updatedRun, slipsBox);
  }
  Future<void> _refreshRunStatus(
    PayrollRun run,
    Box<Payslip> slipsBox,
  ) async {
    final allSlips = slipsBox.values
        .where((item) => item.payrollRunId == run.id)
        .toList();
    if (allSlips.isNotEmpty &&
        allSlips.every((item) => item.status == 'paid') &&
        run.status != 'paid') {
      await Hive.box<PayrollRun>(Boxes.payrollRuns).put(
        run.id,
        _copyRun(
          run,
          status: 'paid',
          paidAt: run.paidAt ?? DateTime.now(),
        ),
      );
    }
  }

  static const salaryHistoryKey = 'hr_salary_history';
  static const salaryGradesKey = 'hr_salary_grades';
  static const employeeSalaryGradesKey = 'hr_employee_salary_grades';

  List<Map<String, dynamic>> salaryGrades() {
    final raw = Hive.box<dynamic>('app_settings').get(salaryGradesKey);
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).where((entry) =>
        entry['id'] is String && entry['name'] is String && entry['minPaise'] is int && entry['maxPaise'] is int && entry['active'] != false).toList()
      ..sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
  }

  Map<String, dynamic>? salaryGradeFor(String employeeId, DateTime date) {
    final raw = Hive.box<dynamic>('app_settings').get(employeeSalaryGradesKey);
    if (raw is! Map || raw[employeeId] is! List) return null;
    final assignments = (raw[employeeId] as List).whereType<Map>().where((entry) =>
        entry['gradeId'] is String && entry['effectiveDate'] is String &&
        !_day(DateTime.parse(entry['effectiveDate'] as String)).isAfter(_day(date))).toList()
      ..sort((a, b) => DateTime.parse(a['effectiveDate'] as String).compareTo(DateTime.parse(b['effectiveDate'] as String)));
    if (assignments.isEmpty) return null;
    final gradeId = assignments.last['gradeId'] as String;
    final grades = salaryGrades();
    final matches = grades.where((grade) => grade['id'] == gradeId).toList();
    return matches.length == 1 ? matches.single : null;
  }

  Future<Map<String, dynamic>> createSalaryGrade({required String name, required int minPaise, required int maxPaise}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || minPaise <= 0 || maxPaise < minPaise) throw const HrPayrollServiceException('Enter a grade name and a valid minimum/maximum salary range.');
    final settings = Hive.box<dynamic>('app_settings');
    final grades = salaryGrades();
    if (grades.any((grade) => (grade['name'] as String).toLowerCase() == cleanName.toLowerCase())) throw const HrPayrollServiceException('A salary grade with this name already exists.');
    final grade = {'id': const Uuid().v4(), 'name': cleanName, 'minPaise': minPaise, 'maxPaise': maxPaise, 'active': true, 'createdAt': DateTime.now().toIso8601String()};
    await settings.put(salaryGradesKey, [...grades, grade]);
    return grade;
  }

  Future<void> assignSalaryGrade({required String employeeId, required String gradeId, required DateTime effectiveDate}) async {
    final employee = Hive.box<Employee>(Boxes.employees).get(employeeId);
    if (employee == null) throw const HrPayrollServiceException('Employee was not found.');
    final grades = salaryGrades().where((grade) => grade['id'] == gradeId).toList();
    if (grades.length != 1) throw const HrPayrollServiceException('Select an active salary grade.');
    final date = _day(effectiveDate);
    final hasPayrollSnapshot = Hive.box<PayrollRun>(Boxes.payrollRuns).values.any((run) =>
        !date.isAfter(_day(run.periodEnd)) && !date.isBefore(_day(run.periodStart)));
    if (hasPayrollSnapshot) throw const HrPayrollServiceException('A payroll run already covers this grade effective date. Use an approved payroll adjustment instead.');
    final base = basePayPaiseFor(employee, date);
    final min = grades.single['minPaise'] as int;
    final max = grades.single['maxPaise'] as int;
    if (base < min || base > max) throw const HrPayrollServiceException('The employee base pay is outside the selected salary grade range. Change base pay or choose another grade.');
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(employeeSalaryGradesKey);
    final all = <String, dynamic>{if (raw is Map) ...Map<String, dynamic>.from(raw)};
    final history = all[employeeId] is List ? List<dynamic>.from(all[employeeId] as List) : <dynamic>[];
    if (history.any((entry) => entry is Map && entry['effectiveDate'] is String && _day(DateTime.parse(entry['effectiveDate'] as String)) == date)) throw const HrPayrollServiceException('A salary grade assignment already exists for this effective date.');
    history.add({'id': const Uuid().v4(), 'gradeId': gradeId, 'effectiveDate': date.toIso8601String(), 'createdAt': DateTime.now().toIso8601String()});
    all[employeeId] = history;
    await settings.put(employeeSalaryGradesKey, all);
  }
  List<Map<String, dynamic>> salaryHistory(String employeeId) {
    final raw = Hive.box<dynamic>('app_settings').get(salaryHistoryKey);
    if (raw is! Map || raw[employeeId] is! List) return const [];
    return (raw[employeeId] as List)
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .where((entry) =>
            entry['effectiveDate'] is String &&
            entry['basePaise'] is int &&
            (entry['basePaise'] as int) > 0)
        .toList()
      ..sort((a, b) => DateTime.parse(a['effectiveDate'] as String)
          .compareTo(DateTime.parse(b['effectiveDate'] as String)));
  }

  int basePayPaiseFor(Employee employee, DateTime date) {
    final effective = salaryHistory(employee.id)
        .where((entry) => !_day(DateTime.parse(entry['effectiveDate'] as String))
            .isAfter(_day(date)))
        .toList();
    return effective.isEmpty
        ? _rupeesToPaise(employee.wage, 'Base salary')
        : effective.last['basePaise'] as int;
  }

  int _basePayPaiseForPeriod({
    required Employee employee,
    required DateTime start,
    required DateTime end,
    required String frequency,
    required String payType,
  }) {
    final first = _day(start);
    final last = _day(end);
    if (last.isBefore(first)) throw const HrPayrollServiceException('Payroll period end cannot be before its start.');
    if (payType == 'daily') {
      final records = Hive.box<EmployeeAttendance>(Boxes.employeeAttendance).values.where((record) =>
          record.employeeId == employee.id && !record.date.isBefore(first) && !record.date.isAfter(last));
      var total = 0.0;
      for (final record in records) {
        final rate = basePayPaiseFor(employee, record.date);
        final grade = salaryGradeFor(employee.id, record.date);
        if (grade != null && (rate < (grade['minPaise'] as int) || rate > (grade['maxPaise'] as int))) {
          throw HrPayrollServiceException('Daily base pay for ${employee.name} is outside the assigned salary grade range.');
        }
        if (record.status == 'present') total += rate;
        if (record.status == 'half_day') total += rate / 2;
      }
      return total.round();
    }
    var total = 0.0;
    for (var day = first; !day.isAfter(last); day = day.add(const Duration(days: 1))) {
      final base = basePayPaiseFor(employee, day);
      final grade = salaryGradeFor(employee.id, day);
      if (grade != null && (base < (grade['minPaise'] as int) || base > (grade['maxPaise'] as int))) {
        throw HrPayrollServiceException('Base pay for ${employee.name} is outside the assigned salary grade range.');
      }
      final daysInMonth = DateTime(day.year, day.month + 1, 0).day;
      final dailyRate = switch (frequency) {
        'daily' => base * 12 / 365,
        'weekly' => base * 12 / 52 / 7,
        'fortnightly' => base / 2 / 14,
        _ => base / daysInMonth,
      };
      total += dailyRate;
    }
    return total.round();
  }
  Future<void> addBasePayChange({
    required String employeeId,
    required int basePaise,
    required DateTime effectiveDate,
    String note = '',
  }) async {
    if (basePaise <= 0) {
      throw const HrPayrollServiceException('Base pay must be positive.');
    }
    if (Hive.box<Employee>(Boxes.employees).get(employeeId) == null) {
      throw const HrPayrollServiceException('Employee was not found.');
    }
    final date = _day(effectiveDate);
    final employee = Hive.box<Employee>(Boxes.employees).get(employeeId)!;
    final grade = salaryGradeFor(employeeId, date);
    if (grade != null && (basePaise < (grade['minPaise'] as int) || basePaise > (grade['maxPaise'] as int))) {
      throw const HrPayrollServiceException('New base pay is outside the assigned salary grade range.');
    }
    final hasSnapshot = Hive.box<PayrollRun>(Boxes.payrollRuns).values.any(
      (run) => !_day(run.periodEnd).isBefore(date),
    );
    if (hasSnapshot) {
      throw const HrPayrollServiceException(
        'A payroll run already covers this effective date. Use a payroll adjustment instead of changing historical base pay.',
      );
    }
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(salaryHistoryKey);
    final all = <String, dynamic>{
      if (raw is Map) ...Map<String, dynamic>.from(raw),
    };
    final entries = all[employeeId] is List
        ? List<dynamic>.from(all[employeeId] as List)
        : <dynamic>[];
    if (entries.any((entry) =>
        entry is Map &&
        entry['effectiveDate'] is String &&
        _day(DateTime.parse(entry['effectiveDate'] as String)) == date)) {
      throw const HrPayrollServiceException(
        'A base-pay change already exists for this effective date.',
      );
    }
    entries.add({
      'id': const Uuid().v4(),
      'effectiveDate': date.toIso8601String(),
      'basePaise': basePaise,
      'note': note.trim(),
      'createdAt': DateTime.now().toIso8601String(),
    });
    all[employeeId] = entries;
    await settings.put(salaryHistoryKey, all);
    await HrService().addEmploymentHistory(
      employeeId: employeeId,
      eventType: 'pay_change',
      title: 'Base pay changed to ₹${(basePaise / 100).toStringAsFixed(2)}',
      effectiveDate: date,
      notes: note,
    );
  }

  Future<SalaryComponent> addSalaryComponent({
    required String employeeId,
    required String name,
    required String componentType,
    required int amountPaise,
    required DateTime effectiveFrom,
    DateTime? effectiveTo,
  }) async {
    final employee = Hive.box<Employee>(Boxes.employees).get(employeeId);
    if (employee == null) {
      throw const HrPayrollServiceException('Employee was not found.');
    }
    if (name.trim().isEmpty) {
      throw const HrPayrollServiceException('Component name is required.');
    }
    if (componentType != 'earning' && componentType != 'deduction') {
      throw const HrPayrollServiceException(
        'Component type must be earning or deduction.',
      );
    }
    if (amountPaise <= 0) {
      throw const HrPayrollServiceException(
        'Component amount must be positive.',
      );
    }
    if (effectiveTo != null &&
        _day(effectiveTo).isBefore(_day(effectiveFrom))) {
      throw const HrPayrollServiceException(
        'Effective end date cannot be before start date.',
      );
    }
    final component = SalaryComponent(
      id: 'salary-component:${Uri.encodeComponent(employeeId)}:${DateTime.now().microsecondsSinceEpoch}',
      employeeId: employeeId,
      name: name.trim(),
      componentType: componentType,
      amountPaise: amountPaise,
      effectiveFrom: _day(effectiveFrom),
      effectiveTo: effectiveTo == null ? null : _day(effectiveTo),
    );
    await Hive.box<SalaryComponent>(Boxes.salaryComponents)
        .put(component.id, component);
    return component;
  }

  Future<void> archiveSalaryComponent(String componentId) async {
    final box = Hive.box<SalaryComponent>(Boxes.salaryComponents);
    final component = box.get(componentId);
    if (component == null) {
      throw const HrPayrollServiceException('Salary component was not found.');
    }
    await box.put(
      component.id,
      SalaryComponent(
        id: component.id,
        employeeId: component.employeeId,
        name: component.name,
        componentType: component.componentType,
        amountPaise: component.amountPaise,
        effectiveFrom: component.effectiveFrom,
        effectiveTo: component.effectiveTo,
        active: false,
      ),
    );
  }

  Payslip _copyPayslip(
    Payslip slip, {
    int? paidPaise,
    int? allowancesPaise,
    int? deductionsPaise,
    String? status,
    DateTime? paidAt,
    bool clearPaidAt = false,
  }) =>
      Payslip(
        id: slip.id,
        payrollRunId: slip.payrollRunId,
        employeeId: slip.employeeId,
        payType: slip.payType,
        basePaise: slip.basePaise,
        allowancesPaise: allowancesPaise ?? slip.allowancesPaise,
        deductionsPaise: deductionsPaise ?? slip.deductionsPaise,
        payableDays: slip.payableDays,
        paidPaise: paidPaise ?? slip.paidPaise,
        status: status ?? slip.status,
        generatedAt: slip.generatedAt,
        paidAt: clearPaidAt ? null : paidAt ?? slip.paidAt,
      );

  PayrollRun _copyRun(
    PayrollRun run, {
    String? status,
    DateTime? approvedAt,
    DateTime? paidAt,
    int? totalGrossPaise,
    int? totalDeductionsPaise,
    int? totalNetPaise,
    bool clearPaidAt = false,
  }) =>
      PayrollRun(
        id: run.id,
        periodStart: run.periodStart,
        periodEnd: run.periodEnd,
        status: status ?? run.status,
        createdAt: run.createdAt,
        approvedAt: approvedAt ?? run.approvedAt,
        paidAt: clearPaidAt ? null : paidAt ?? run.paidAt,
        totalGrossPaise: totalGrossPaise ?? run.totalGrossPaise,
        totalDeductionsPaise: totalDeductionsPaise ?? run.totalDeductionsPaise,
        totalNetPaise: totalNetPaise ?? run.totalNetPaise,
        memo: run.memo,
      );
}
