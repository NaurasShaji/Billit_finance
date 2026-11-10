import 'package:hive_ce/hive_ce.dart';

import '../models/models.dart';
import 'finance_ledger_service.dart';

/// Bridges existing POS, expense, and payroll records into the accounting
/// journal. Legacy records remain the operational source of truth; journal
/// entries are immutable, revisioned snapshots with stable idempotency keys.
class FinanceSourceSyncService {
  FinanceSourceSyncService({FinanceLedgerService? ledger})
      : _ledger = ledger ?? FinanceLedgerService();

  final FinanceLedgerService _ledger;

  static Future<void> recordIssue(
    Box<dynamic> settingsBox,
    String issue,
  ) async {
    final raw = settingsBox.get(
      'finance_sync_errors',
      defaultValue: const <String>[],
    );
    final issues = raw is List
        ? raw.map((item) => item.toString()).toList()
        : <String>[];
    if (!issues.contains(issue)) issues.add(issue);
    await settingsBox.put('finance_sync_errors', issues);
  }

  static int _toPaise(double amount, String source) {
    if (!amount.isFinite || amount < 0) {
      throw FinanceLedgerException(
        '$source contains an invalid monetary amount.',
      );
    }
    return (amount * 100).round();
  }

  static const paymentAccountSettingsKey = 'finance_payment_account_mapping';

  static const defaultPaymentAccountMapping = <String, String>{
    'cash': 'system:cash',
    'card': 'system:bank',
    'upi': 'system:bank',
  };

  /// Resolve a configured destination account for a POS payment method.
  static String paymentAccountFor({
    required String method,
    required Box<FinanceAccount> accountsBox,
    Box<dynamic>? settingsBox,
  }) {
    final raw = settingsBox?.get(paymentAccountSettingsKey);
    final mapping = raw is Map
        ? raw.map((key, value) => MapEntry(key.toString(), value.toString()))
        : const <String, String>{};
    final accountId = mapping[method] ?? defaultPaymentAccountMapping[method];
    if (accountId == null) {
      throw FinanceLedgerException('No payment account is configured for $method.');
    }
    final account = accountsBox.get(accountId);
    if (account == null || !account.active || account.accountType != 'asset' || account.currencyCode != 'INR') {
      throw FinanceLedgerException('The account configured for $method must be an active INR asset account.');
    }
    return account.id;
  }

  /// Persist configurable POS payment-method to account mappings. The
  /// existing cash/card/UPI methods are required to keep POS reconciliation
  /// deterministic; each can point to a separate cash/bank/wallet asset.
  Future<void> savePaymentAccountMapping({
    required Map<String, String> mapping,
    required Box<FinanceAccount> accountsBox,
    required Box<dynamic> settingsBox,
  }) async {
    const requiredMethods = {'cash', 'card', 'upi'};
    const allowed = {'cash', 'card', 'upi'};
    final normalized = <String, String>{};
    for (final entry in mapping.entries) {
      final method = entry.key.trim().toLowerCase();
      if (!allowed.contains(method)) throw FinanceLedgerException('Unsupported POS payment method: ${entry.key}.');
      final account = accountsBox.get(entry.value);
      if (account == null || !account.active || account.accountType != 'asset' || account.currencyCode != 'INR') {
        throw FinanceLedgerException('Choose an active INR asset account for ${entry.key}.');
      }
      normalized[method] = account.id;
    }
    if (!normalized.keys.toSet().containsAll(requiredMethods)) {
      throw const FinanceLedgerException('Cash, card, and UPI mappings are required.');
    }
    await settingsBox.put(paymentAccountSettingsKey, normalized);
  }

  static String _sourceId(String id, int revision) => '$id:$revision';

  bool _hasSource(
    Box<FinanceTransaction> transactionsBox,
    String sourceType,
    String sourceId,
  ) =>
      transactionsBox.values.any(
        (transaction) =>
            transaction.sourceType == sourceType &&
            transaction.sourceId == sourceId,
      );

  FinanceTransaction? _findSource(
    Box<FinanceTransaction> transactionsBox,
    String sourceType,
    String sourceId,
  ) {
    for (final transaction in transactionsBox.values) {
      if (transaction.sourceType == sourceType &&
          transaction.sourceId == sourceId) {
        return transaction;
      }
    }
    return null;
  }

  bool _hasReversal(
    Box<FinanceTransaction> transactionsBox,
    String originalId,
  ) =>
      transactionsBox.values.any(
        (transaction) =>
            transaction.transactionType == 'reversal' &&
            transaction.sourceType == 'reversal' &&
            transaction.sourceId == originalId,
      );

  Future<void> _reversePreviousRevisions({
    required String sourceType,
    required String sourceRecordId,
    required int currentRevision,
    required Box<FinanceAccount> accountsBox,
    required Box<FinanceTransaction> transactionsBox,
    required Box<FinancePosting> postingsBox,
    required Box<FinanceCategory> categoriesBox,
    required Box<FinanceParty> partiesBox,
  }) async {
    for (var revision = 0; revision < currentRevision; revision++) {
      final previous = _findSource(
        transactionsBox,
        sourceType,
        _sourceId(sourceRecordId, revision),
      );
      if (previous == null || _hasReversal(transactionsBox, previous.id)) {
        continue;
      }
      await _reverse(
        previous,
        accountsBox: accountsBox,
        transactionsBox: transactionsBox,
        postingsBox: postingsBox,
        categoriesBox: categoriesBox,
        partiesBox: partiesBox,
      );
    }
  }

  Future<void> _reverse(
    FinanceTransaction original, {
    required Box<FinanceAccount> accountsBox,
    required Box<FinanceTransaction> transactionsBox,
    required Box<FinancePosting> postingsBox,
    required Box<FinanceCategory> categoriesBox,
    required Box<FinanceParty> partiesBox,
  }) async {
    await _ledger.reverseTransaction(
      originalTransactionId: original.id,
      reversalId: 'finance:reversal:${original.id}',
      reversalNumber: 'REV-${original.transactionNumber}',
      reversalDate: DateTime.now(),
      accountsBox: accountsBox,
      transactionsBox: transactionsBox,
      postingsBox: postingsBox,
      categoriesBox: categoriesBox,
      partiesBox: partiesBox,
    );
  }

  Future<FinanceCategory> _ensureExpenseCategory({
    required Expense expense,
    required Box<FinanceCategory> categoriesBox,
  }) async {
    final categoryName = expense.category.trim().isEmpty
        ? 'Uncategorised'
        : expense.category.trim();
    final id =
        'legacy-expense-category:${Uri.encodeComponent(categoryName.toLowerCase())}';
    final existing = categoriesBox.get(id);
    if (existing != null) {
      if (existing.kind != 'expense' || !existing.active) {
        throw FinanceLedgerException(
          'Expense category "$categoryName" is inactive or has an invalid type.',
        );
      }
      return existing;
    }

    final accountId = categoryName == 'Salary-Daily' ||
            categoryName == 'Salary-Monthly' ||
            categoryName == 'Salary-Run'
        ? 'system:salary-expense'
        : 'system:operating-expense';
    final category = FinanceCategory(
      id: id,
      name: categoryName,
      kind: 'expense',
      accountId: accountId,
    );
    await categoriesBox.put(id, category);
    return category;
  }

  Future<FinanceParty?> _ensureEmployeeParty({
    required Expense expense,
    required Box<FinanceParty> partiesBox,
    Box<Employee>? employeesBox,
  }) async {
    final employeeId = expense.employeeId;
    if (employeeId == null || employeeId.trim().isEmpty) return null;

    final partyId = 'employee:$employeeId';
    final existing = partiesBox.get(partyId);
    if (existing != null) {
      if (!existing.active || existing.partyType != 'employee') {
        throw FinanceLedgerException(
          'Employee party "$employeeId" is inactive or invalid.',
        );
      }
      return existing;
    }

    final employee = employeesBox?.get(employeeId);
    final party = FinanceParty(
      id: partyId,
      name: employee?.name ?? 'Employee $employeeId',
      partyType: 'employee',
    );
    await partiesBox.put(partyId, party);
    return party;
  }

  Future<void> _markExpenseCorrectionPosted({
    required Box<dynamic>? settingsBox,
    required String sourceId,
    required String transactionId,
  }) async {
    if (settingsBox == null) return;
    final raw = settingsBox.get('finance_expense_corrections');
    if (raw is! Map || raw[sourceId] is! Map) return;
    final history = <String, dynamic>{...Map<String, dynamic>.from(raw)};
    final record = <String, dynamic>{...Map<String, dynamic>.from(history[sourceId] as Map)};
    record['status'] = 'posted';
    record['journalId'] = transactionId;
    record['postedAt'] = DateTime.now().toIso8601String();
    history[sourceId] = record;
    await settingsBox.put('finance_expense_corrections', history);
  }

  /// Posts one expense snapshot. Repeated calls are safe and do not duplicate it.
  Future<bool> syncExpense({
    required Expense expense,
    required Box<FinanceAccount> accountsBox,
    required Box<FinanceTransaction> transactionsBox,
    required Box<FinancePosting> postingsBox,
    required Box<FinanceCategory> categoriesBox,
    required Box<FinanceParty> partiesBox,
    Box<Employee>? employeesBox,
    Box<dynamic>? settingsBox,
    String paymentAccountId = 'system:cash',
  }) async {
    final sourceType = 'legacy_expense';
    final sourceId = _sourceId(expense.id, expense.financeRevision);
    final transactionId = 'finance:expense:${expense.id}:r${expense.financeRevision}';
    if (_hasSource(transactionsBox, sourceType, sourceId)) {
      await _markExpenseCorrectionPosted(
        settingsBox: settingsBox,
        sourceId: sourceId,
        transactionId: transactionId,
      );
      return false;
    }

    await _reversePreviousRevisions(
      sourceType: sourceType,
      sourceRecordId: expense.id,
      currentRevision: expense.financeRevision,
      accountsBox: accountsBox,
      transactionsBox: transactionsBox,
      postingsBox: postingsBox,
      categoriesBox: categoriesBox,
      partiesBox: partiesBox,
    );

    final amountPaise = _toPaise(expense.amount, 'Expense ${expense.id}');
    if (amountPaise <= 0) {
      throw FinanceLedgerException(
        'Expense ${expense.id} must have a positive amount.',
      );
    }
    final category = await _ensureExpenseCategory(
      expense: expense,
      categoriesBox: categoriesBox,
    );
    final employee = await _ensureEmployeeParty(
      expense: expense,
      partiesBox: partiesBox,
      employeesBox: employeesBox,
    );
    final paymentAccount = accountsBox.get(paymentAccountId);
    if (paymentAccount == null ||
        !paymentAccount.active ||
        paymentAccount.accountType != 'asset' ||
        paymentAccount.currencyCode != 'INR') {
      throw FinanceLedgerException(
        'Expense payment account must be an active INR asset account.',
      );
    }
    final transactionId =
        'finance:expense:${expense.id}:r${expense.financeRevision}';
    final correctionHistory = settingsBox?.get('finance_expense_corrections');
    final correction = correctionHistory is Map ? correctionHistory[sourceId] : null;
    final correctionReason = correction is Map && correction['reason'] is String
        ? (correction['reason'] as String).trim()
        : '';
    final expenseMemo = expense.description.isEmpty ? category.name : expense.description;
    final transaction = FinanceTransaction(
      id: transactionId,
      transactionNumber: 'EXP-${expense.id}-${expense.financeRevision}',
      transactionType: 'expense',
      date: expense.date,
      memo: correctionReason.isEmpty
          ? expenseMemo
          : '$expenseMemo • Correction: $correctionReason',
      reference: correctionReason.isEmpty ? expense.id : 'Correction: $correctionReason',
      sourceType: sourceType,
      sourceId: sourceId,
    );
    await _ledger.postTransaction(
      transaction: transaction,
      postings: [
        FinancePosting(
          id: '$transactionId:debit',
          transactionId: transactionId,
          accountId: category.accountId,
          debitPaise: amountPaise,
          categoryId: category.id,
          partyId: employee?.id,
          memo: expense.description,
        ),
        FinancePosting(
          id: '$transactionId:credit',
          transactionId: transactionId,
          accountId: paymentAccountId,
          creditPaise: amountPaise,
          memo: expense.description,
        ),
      ],
      accountsBox: accountsBox,
      transactionsBox: transactionsBox,
      postingsBox: postingsBox,
      categoriesBox: categoriesBox,
      partiesBox: partiesBox,
    );
    await _markExpenseCorrectionPosted(
      settingsBox: settingsBox,
      sourceId: sourceId,
      transactionId: transactionId,
    );
    return true;
  }

  /// Posts one POS sale snapshot, separating GST collected from sales revenue.
  Future<bool> syncSale({
    required Sale sale,
    required Box<FinanceAccount> accountsBox,
    required Box<FinanceTransaction> transactionsBox,
    required Box<FinancePosting> postingsBox,
    required Box<FinanceCategory> categoriesBox,
    required Box<FinanceParty> partiesBox,
    Box<dynamic>? settingsBox,
  }) async {
    const sourceType = 'pos_sale';
    final sourceId = _sourceId(sale.id, sale.financeRevision);
    if (_hasSource(transactionsBox, sourceType, sourceId)) return false;

    await _reversePreviousRevisions(
      sourceType: sourceType,
      sourceRecordId: sale.id,
      currentRevision: sale.financeRevision,
      accountsBox: accountsBox,
      transactionsBox: transactionsBox,
      postingsBox: postingsBox,
      categoriesBox: categoriesBox,
      partiesBox: partiesBox,
    );

    final totalPaise = _toPaise(sale.totalAmount, 'Sale ${sale.id}');
    if (totalPaise <= 0) {
      throw FinanceLedgerException(
        'Sale ${sale.id} must have a positive total.',
      );
    }
    final taxPaise = sale.gstEnabled
        ? _toPaise(
            sale.cgstAmount + sale.sgstAmount + sale.igstAmount,
            'GST for sale ${sale.id}',
          )
        : 0;
    if (taxPaise > totalPaise) {
      throw FinanceLedgerException(
        'GST amount exceeds the total for sale ${sale.id}.',
      );
    }
    final revenuePaise = totalPaise - taxPaise;
    if (revenuePaise <= 0) {
      throw FinanceLedgerException(
        'Sale ${sale.id} has no positive sales revenue after GST.',
      );
    }

    final transactionId =
        'finance:sale:${sale.id}:r${sale.financeRevision}';
    final method = switch (sale.payment) {
      PaymentMethod.cash => 'cash',
      PaymentMethod.card => 'card',
      PaymentMethod.upi => 'upi',
    };
    final receiptAccount = paymentAccountFor(
      method: method,
      accountsBox: accountsBox,
      settingsBox: settingsBox,
    );
    final lines = <FinancePosting>[
      FinancePosting(
        id: '$transactionId:receipt',
        transactionId: transactionId,
        accountId: receiptAccount,
        debitPaise: totalPaise,
        memo: 'POS receipt',
      ),
      FinancePosting(
        id: '$transactionId:revenue',
        transactionId: transactionId,
        accountId: 'system:sales-income',
        creditPaise: revenuePaise,
        memo: 'Sales revenue',
      ),
    ];
    if (taxPaise > 0) {
      lines.add(
        FinancePosting(
          id: '$transactionId:gst',
          transactionId: transactionId,
          accountId: 'system:gst-payable',
          creditPaise: taxPaise,
          memo: 'GST collected',
        ),
      );
    }

    await _ledger.postTransaction(
      transaction: FinanceTransaction(
        id: transactionId,
        transactionNumber: 'SALE-${sale.id}-${sale.financeRevision}',
        transactionType: 'income',
        date: sale.date,
        memo: 'POS sale ${sale.id}',
        reference: sale.id,
        sourceType: sourceType,
        sourceId: sourceId,
      ),
      postings: lines,
      accountsBox: accountsBox,
      transactionsBox: transactionsBox,
      postingsBox: postingsBox,
      categoriesBox: categoriesBox,
      partiesBox: partiesBox,
    );
    return true;
  }

  /// Reverses the current journal snapshot before a source record is deleted.
  Future<void> reverseExpense({
    required Expense expense,
    required Box<FinanceAccount> accountsBox,
    required Box<FinanceTransaction> transactionsBox,
    required Box<FinancePosting> postingsBox,
    required Box<FinanceCategory> categoriesBox,
    required Box<FinanceParty> partiesBox,
  }) async {
    await _reverseCurrent(
      sourceType: 'legacy_expense',
      sourceRecordId: expense.id,
      revision: expense.financeRevision,
      accountsBox: accountsBox,
      transactionsBox: transactionsBox,
      postingsBox: postingsBox,
      categoriesBox: categoriesBox,
      partiesBox: partiesBox,
    );
  }

  Future<void> reverseSale({
    required Sale sale,
    required Box<FinanceAccount> accountsBox,
    required Box<FinanceTransaction> transactionsBox,
    required Box<FinancePosting> postingsBox,
    required Box<FinanceCategory> categoriesBox,
    required Box<FinanceParty> partiesBox,
  }) async {
    await _reverseCurrent(
      sourceType: 'pos_sale',
      sourceRecordId: sale.id,
      revision: sale.financeRevision,
      accountsBox: accountsBox,
      transactionsBox: transactionsBox,
      postingsBox: postingsBox,
      categoriesBox: categoriesBox,
      partiesBox: partiesBox,
    );
  }

  Future<void> _reverseCurrent({
    required String sourceType,
    required String sourceRecordId,
    required int revision,
    required Box<FinanceAccount> accountsBox,
    required Box<FinanceTransaction> transactionsBox,
    required Box<FinancePosting> postingsBox,
    required Box<FinanceCategory> categoriesBox,
    required Box<FinanceParty> partiesBox,
  }) async {
    final original = _findSource(
      transactionsBox,
      sourceType,
      _sourceId(sourceRecordId, revision),
    );
    if (original == null || _hasReversal(transactionsBox, original.id)) return;
    await _reverse(
      original,
      accountsBox: accountsBox,
      transactionsBox: transactionsBox,
      postingsBox: postingsBox,
      categoriesBox: categoriesBox,
      partiesBox: partiesBox,
    );
  }

  /// Reconciles all existing POS and expense records at startup.
  Future<List<String>> syncAll({
    required Box<Sale> salesBox,
    required Box<Expense> expensesBox,
    required Box<Employee> employeesBox,
    required Box<FinanceAccount> accountsBox,
    required Box<FinanceTransaction> transactionsBox,
    required Box<FinancePosting> postingsBox,
    required Box<FinanceCategory> categoriesBox,
    required Box<FinanceParty> partiesBox,
    Box<dynamic>? settingsBox,
  }) async {
    final issues = <String>[];
    for (final sale in salesBox.values) {
      try {
        await syncSale(
          sale: sale,
          accountsBox: accountsBox,
          transactionsBox: transactionsBox,
          postingsBox: postingsBox,
          categoriesBox: categoriesBox,
          partiesBox: partiesBox,
          settingsBox: settingsBox,
        );
      } catch (error) {
        issues.add('Sale ${sale.id}: $error');
      }
    }
    for (final expense in expensesBox.values) {
      try {
        await syncExpense(
          expense: expense,
          accountsBox: accountsBox,
          transactionsBox: transactionsBox,
          postingsBox: postingsBox,
          categoriesBox: categoriesBox,
          partiesBox: partiesBox,
          employeesBox: employeesBox,
          settingsBox: settingsBox,
        );
      } catch (error) {
        issues.add('Expense ${expense.id}: $error');
      }
    }
    return issues;
  }
}
