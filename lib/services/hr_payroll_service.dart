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
    final outstanding = advance['outstandingPaise'];
    if (outstanding is! int || outstanding <= 0) {
      throw const HrPayrollServiceException('Only an advance with a positive outstanding balance can be opened.');
    }

    final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    final repayments = advance['repayments'] is List
        ? (advance['repayments'] as List).whereType<Map>().toList()
        : <Map>[];
    final repaymentIds = repayments
        .where((item) => item['source'] == 'manual' && item['id'] is String)
        .map((item) => item['id'] as String)
        .toSet();
    final payslipIds = repayments
        .where((item) => item['source'] == 'payroll' && item['payslipId'] is String)
        .map((item) => item['payslipId'] as String)
        .toSet();
    final hasLinkedHistory = transactions.values.any((tx) =>
        (tx.sourceType == 'employee_advance_issue' && tx.sourceId == advanceId) ||
        (tx.sourceType == 'employee_advance_repayment' && repaymentIds.contains(tx.sourceId)) ||
        (tx.sourceType == 'payroll_advance_recovery' && payslipIds.contains(tx.sourceId)) ||
        (tx.sourceType == 'employee_advance_opening_balance' && tx.sourceId == advanceId));
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
    if (advancesRaw is! Map) return;
    final all = Map<String,dynamic>.from(advancesRaw);
    final slip = Hive.box<Payslip>(Boxes.payslips).get(payslipId);
    if (slip == null) throw const HrPayrollServiceException('Payslip was not found for advance recovery.');
    final deductions = (raw[payslipId] as List).whereType<Map>()
        .map((item) => Map<String,dynamic>.from(item)).toList();
    final recoveryTotal = deductions.fold<int>(0, (sum, item) {
      final amount = item['amountPaise'];
      if (amount is! int || amount <= 0 || item['employeeId'] is! String || item['advanceId'] is! String) {
        throw const HrPayrollServiceException('Payroll advance recovery snapshot contains invalid references or amount.');
      }
      final employeeRecords = all[item['employeeId']] as List?;
      final matches = employeeRecords?.whereType<Map>().where((entry) => entry['id'] == item['advanceId']).toList() ?? <Map>[];
      final record = matches.isEmpty ? null : matches.first;
      if (record == null || record['outstandingPaise'] is! int || amount > (record['outstandingPaise'] as int)) {
        throw const HrPayrollServiceException('Advance balance changed after payroll generation. Reconcile before settlement.');
      }
      return sum + amount;
    });
    final grouped = <String,List<Map<String,dynamic>>>{};
    for (final item in deductions) {
      grouped.putIfAbsent(item['employeeId'] as String, () => []).add(item);
    }
    await _postPayrollAdvanceRecoveryJournal(
      payslipId: payslipId,
      date: slip.paidAt ?? DateTime.now(),
      amountPaise: recoveryTotal,
    );
    for (final group in grouped.entries) {
      final list = List<dynamic>.from(all[group.key] as List? ?? []);
      for (final deduction in group.value) {
        final index = list.indexWhere((a) => a is Map && a['id'] == deduction['advanceId']);
        if (index < 0) throw const HrPayrollServiceException('Advance record disappeared before payroll recovery settlement.');
        final advance = Map<String,dynamic>.from(list[index] as Map);
        final amount = deduction['amountPaise'] as int;
        final outstanding = advance['outstandingPaise'] as int;
        if (amount <= 0 || amount > outstanding) throw const HrPayrollServiceException('Advance balance changed after payroll generation. Reconcile before settlement.');
        final repayments = (advance['repayments'] as List? ?? []).whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList();
        repayments.add({'id': 'payroll:$payslipId:${advance['id']}', 'date': DateTime.now().toIso8601String(), 'amountPaise': amount, 'note': 'Payroll recovery', 'source': 'payroll', 'payslipId': payslipId});
        final remaining = outstanding - amount;
        final due = DateTime.parse(advance['nextDueDate'] as String);
        advance['outstandingPaise'] = remaining;
        advance['repayments'] = repayments;
        advance['nextDueDate'] = DateTime(due.year, due.month + 1, due.day).toIso8601String();
        advance['status'] = remaining == 0 ? 'settled' : 'active';
        list[index] = advance;
      }
      all[group.key] = list;
    }
    await settings.put(advanceSettingsKey, all);
    final snapshots = Map<String,dynamic>.from(raw)..remove(payslipId);
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
      return !date.isBefore(start) && !date.isAfter(end);
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
      'createdAt': DateTime.now().toIso8601String(),
    });
    allEntries[employeeId] = entries;
    await settings.put(overtimeSettingsKey, allEntries);
  }

  int _approvedOvertimePaise(String employeeId, DateTime start, DateTime end) {
    return overtimeEntries(employeeId).where((entry) {
      final date = _day(DateTime.parse(entry['date'] as String));
      return !date.isBefore(start) && !date.isAfter(end);
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
      final monthlyBasePaise = _rupeesToPaise(
        employee.wage,
        payType == 'daily' ? 'Daily wage' : 'Monthly salary',
      );
      final basePaise = payType == 'daily'
          ? (monthlyBasePaise * attendance.payableDays).round()
          : switch (frequency) {
              'daily' => (monthlyBasePaise * 12 / 365).round(),
              'weekly' => (monthlyBasePaise * 12 / 52).round(),
              'fortnightly' => (monthlyBasePaise / 2).round(),
              _ => monthlyBasePaise,
            };

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

  Future<PayrollRun> approveRun(String runId) async {
    final runsBox = Hive.box<PayrollRun>(Boxes.payrollRuns);
    final slipsBox = Hive.box<Payslip>(Boxes.payslips);
    final run = runsBox.get(runId);
    if (run == null || run.status != 'draft') {
      throw const HrPayrollServiceException(
        'Only draft payroll runs can be approved.',
      );
    }
    final slips = slipsBox.values
        .where((slip) => slip.payrollRunId == runId)
        .toList();
    final oldSlips = {for (final slip in slips) slip.id: slip};
    final approvedAt = DateTime.now();
    try {
      // A zero-net payslip is settled on approval; post its advance recovery
      // before changing the payslip state so journal failures remain retryable.
      for (final slip in slips.where((item) => item.netPaise == 0)) {
        await _settlePayrollAdvanceDeductions(slip.id);
      }
      for (final slip in slips) {
        final updated = _copyPayslip(
          slip,
          status: slip.netPaise == 0 ? 'paid' : 'approved',
          paidAt: slip.netPaise == 0 ? approvedAt : slip.paidAt,
        );
        await slipsBox.put(updated.id, updated);
      }
      final updatedRun = _copyRun(
        run,
        status: slips.every((slip) => slip.netPaise == 0) ? 'paid' : 'approved',
        approvedAt: approvedAt,
        paidAt: slips.every((slip) => slip.netPaise == 0) ? approvedAt : null,
      );
      await runsBox.put(updatedRun.id, updatedRun);
      return updatedRun;
    } catch (_) {
      for (final old in oldSlips.values) {
        try {
          await slipsBox.put(old.id, old);
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<Payslip> payPayslip({
    required String payslipId,
    required int amountPaise,
  }) async {
    if (amountPaise <= 0) {
      throw const HrPayrollServiceException(
        'Payment amount must be positive.',
      );
    }
    final runsBox = Hive.box<PayrollRun>(Boxes.payrollRuns);
    final slipsBox = Hive.box<Payslip>(Boxes.payslips);
    final expensesBox = Hive.box<Expense>(Boxes.expenses);
    final slip = slipsBox.get(payslipId);
    if (slip == null) {
      throw const HrPayrollServiceException('Payslip was not found.');
    }
    final run = runsBox.get(slip.payrollRunId);
    if (run == null || (run.status != 'approved' && run.status != 'paid')) {
      throw const HrPayrollServiceException(
        'Approve the payroll run before recording payment.',
      );
    }
    if (slip.status == 'paid') {
      final allSlips = slipsBox.values
          .where((item) => item.payrollRunId == run.id)
          .toList();
      if (allSlips.isNotEmpty &&
          allSlips.every((item) => item.status == 'paid') &&
          run.status != 'paid') {
        await runsBox.put(
          run.id,
          _copyRun(run, status: 'paid', paidAt: DateTime.now()),
        );
      }
      return slip;
    }
    if (slip.status != 'approved' && slip.status != 'partially_paid') {
      throw const HrPayrollServiceException(
        'Payslip is not in a payable state.',
      );
    }
    if (amountPaise > slip.outstandingPaise) {
      throw const HrPayrollServiceException(
        'Payment cannot exceed the payslip outstanding amount.',
      );
    }

    final paymentId = 'payroll-payment:${slip.id}:from:${slip.paidPaise}';
    final existingPayment = expensesBox.get(paymentId);
    final actualPaymentPaise = existingPayment == null
        ? amountPaise
        : _rupeesToPaise(existingPayment.amount, 'Existing payroll payment');
    if (existingPayment == null) {
      final employee = Hive.box<Employee>(Boxes.employees).get(slip.employeeId);
      if (employee == null) {
        throw const HrPayrollServiceException(
          'Payslip employee record is missing.',
        );
      }
      final expense = Expense(
        id: paymentId,
        date: DateTime.now(),
        category: 'Salary-Run',
        amount: amountPaise / 100,
        description: 'Payroll run ${run.id}, payslip ${slip.id}',
        employeeId: slip.employeeId,
      );
      await expensesBox.put(expense.id, expense);
    }
    if (actualPaymentPaise > slip.outstandingPaise) {
      throw const HrPayrollServiceException(
        'Existing payroll payment exceeds the remaining payslip balance.',
      );
    }

    final expense = expensesBox.get(paymentId)!;
    try {
      await FinanceSourceSyncService().syncExpense(
        expense: expense,
        accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts),
        transactionsBox:
            Hive.box<FinanceTransaction>(Boxes.financeTransactions),
        postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
        categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
        partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
        employeesBox: Hive.box<Employee>(Boxes.employees),
      );
    } catch (error) {
      // Do not mark the payslip as paid when its accounting journal failed.
      // Keep the source expense so startup reconciliation or a later retry can
      // post it idempotently using the stable expense ID.
      if (Hive.isBoxOpen('app_settings')) {
        await FinanceSourceSyncService.recordIssue(
          Hive.box<dynamic>('app_settings'),
          'Payroll run ${run.id}, payslip ${slip.id}: $error',
        );
      }
      throw HrPayrollServiceException(
        'Payroll payment was saved, but its finance journal could not be posted. '
        'The payslip remains unpaid; retry finance reconciliation before '
        'recording another payment. Details: $error',
      );
    }

    final paidPaise = slip.paidPaise + actualPaymentPaise;
    final updatedSlip = _copyPayslip(
      slip,
      paidPaise: paidPaise,
      status: paidPaise >= slip.netPaise ? 'paid' : 'partially_paid',
      paidAt: paidPaise >= slip.netPaise ? DateTime.now() : null,
    );
    if (updatedSlip.status == 'paid') {
      // Keep the payslip unpaid if the recovery journal cannot be posted.
      await _settlePayrollAdvanceDeductions(updatedSlip.id);
    }
    await slipsBox.put(updatedSlip.id, updatedSlip);

    await _refreshRunStatus(run, slipsBox);
    return updatedSlip;
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
    String? status,
    DateTime? paidAt,
  }) =>
      Payslip(
        id: slip.id,
        payrollRunId: slip.payrollRunId,
        employeeId: slip.employeeId,
        payType: slip.payType,
        basePaise: slip.basePaise,
        allowancesPaise: slip.allowancesPaise,
        deductionsPaise: slip.deductionsPaise,
        payableDays: slip.payableDays,
        paidPaise: paidPaise ?? slip.paidPaise,
        status: status ?? slip.status,
        generatedAt: slip.generatedAt,
        paidAt: paidAt ?? slip.paidAt,
      );

  PayrollRun _copyRun(
    PayrollRun run, {
    String? status,
    DateTime? approvedAt,
    DateTime? paidAt,
  }) =>
      PayrollRun(
        id: run.id,
        periodStart: run.periodStart,
        periodEnd: run.periodEnd,
        status: status ?? run.status,
        createdAt: run.createdAt,
        approvedAt: approvedAt ?? run.approvedAt,
        paidAt: paidAt ?? run.paidAt,
        totalGrossPaise: run.totalGrossPaise,
        totalDeductionsPaise: run.totalDeductionsPaise,
        totalNetPaise: run.totalNetPaise,
        memo: run.memo,
      );
}
