import 'package:hive/hive.dart';

import '../models/models.dart';
import 'finance_ledger_service.dart';

/// Bridges existing POS, expense, and payroll records into the accounting
/// journal. Legacy records remain the operational source of truth; journal
/// entries are immutable, revisioned snapshots with stable idempotency keys.
class FinanceSourceSyncService {
  FinanceSourceSyncService({FinanceLedgerService? ledger})
      : _ledger = ledger ?? FinanceLedgerService();

  final FinanceLedgerService _ledger;

  static int _toPaise(double amount, String source) {
    if (!amount.isFinite || amount < 0) {
      throw FinanceLedgerException(
        '$source contains an invalid monetary amount.',
      );
    }
    return (amount * 100).round();
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
            categoryName == 'Salary-Monthly'
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

  /// Posts one expense snapshot. Repeated calls are safe and do not duplicate it.
  Future<bool> syncExpense({
    required Expense expense,
    required Box<FinanceAccount> accountsBox,
    required Box<FinanceTransaction> transactionsBox,
    required Box<FinancePosting> postingsBox,
    required Box<FinanceCategory> categoriesBox,
    required Box<FinanceParty> partiesBox,
    Box<Employee>? employeesBox,
  }) async {
    final sourceType = 'legacy_expense';
    final sourceId = _sourceId(expense.id, expense.financeRevision);
    if (_hasSource(transactionsBox, sourceType, sourceId)) return false;

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
    final transactionId =
        'finance:expense:${expense.id}:r${expense.financeRevision}';
    final transaction = FinanceTransaction(
      id: transactionId,
      transactionNumber: 'EXP-${expense.id}-${expense.financeRevision}',
      transactionType: 'expense',
      date: expense.date,
      memo: expense.description.isEmpty
          ? category.name
          : expense.description,
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
          accountId: 'system:cash',
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
    final receiptAccount = sale.payment == PaymentMethod.cash
        ? 'system:cash'
        : 'system:bank';
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
  Future<void> syncAll({
    required Box<Sale> salesBox,
    required Box<Expense> expensesBox,
    required Box<Employee> employeesBox,
    required Box<FinanceAccount> accountsBox,
    required Box<FinanceTransaction> transactionsBox,
    required Box<FinancePosting> postingsBox,
    required Box<FinanceCategory> categoriesBox,
    required Box<FinanceParty> partiesBox,
  }) async {
    for (final sale in salesBox.values) {
      await syncSale(
        sale: sale,
        accountsBox: accountsBox,
        transactionsBox: transactionsBox,
        postingsBox: postingsBox,
        categoriesBox: categoriesBox,
        partiesBox: partiesBox,
      );
    }
    for (final expense in expensesBox.values) {
      await syncExpense(
        expense: expense,
        accountsBox: accountsBox,
        transactionsBox: transactionsBox,
        postingsBox: postingsBox,
        categoriesBox: categoriesBox,
        partiesBox: partiesBox,
        employeesBox: employeesBox,
      );
    }
  }
}
