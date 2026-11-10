import 'package:hive_ce/hive_ce.dart';

import '../models/models.dart';
import 'boxes.dart';

class FinanceAllocationException implements Exception {
  const FinanceAllocationException(this.message);
  final String message;
  @override
  String toString() => 'FinanceAllocationException: $message';
}

/// Immutable invoice-to-settlement allocation stored as a primitive Hive map.
/// Using a primitive record avoids consuming a new Hive adapter type ID.
class FinancePaymentAllocation {
  const FinancePaymentAllocation({
    required this.id,
    required this.settlementTransactionId,
    required this.invoiceTransactionId,
    required this.partyId,
    required this.amountPaise,
    required this.createdAt,
  });

  final String id;
  final String settlementTransactionId;
  final String invoiceTransactionId;
  final String partyId;
  final int amountPaise;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'settlementTransactionId': settlementTransactionId,
        'invoiceTransactionId': invoiceTransactionId,
        'partyId': partyId,
        'amountPaise': amountPaise,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FinancePaymentAllocation.fromMap(Map<dynamic, dynamic> map) {
    return FinancePaymentAllocation(
      id: map['id'] as String,
      settlementTransactionId: map['settlementTransactionId'] as String,
      invoiceTransactionId: map['invoiceTransactionId'] as String,
      partyId: map['partyId'] as String,
      amountPaise: map['amountPaise'] as int,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}

class FinanceAllocationDraft {\n  const FinanceAllocationDraft({required this.id, required this.invoiceTransactionId, required this.amountPaise});\n  final String id;\n  final String invoiceTransactionId;\n  final int amountPaise;\n}\n\nclass FinancePaymentAllocationService {
  Box<Map> get _box => Hive.box<Map>(Boxes.financePaymentAllocations);

  List<FinancePaymentAllocation> get allocations => _box.values
      .map(FinancePaymentAllocation.fromMap)
      .toList(growable: false);

  int allocatedToInvoice(String invoiceId, {
    Iterable<FinanceTransaction>? transactions,
  }) {
    final posted = transactions == null
        ? null
        : {
            for (final t in transactions)
              if (t.status == 'posted') t.id: t,
          };
    final reversed = posted == null
        ? <String>{}
        : posted.values
            .where((t) => t.transactionType == 'reversal')
            .map((t) => t.reversedTransactionId)
            .whereType<String>()
            .toSet();
    return allocations
        .where((a) =>
            a.invoiceTransactionId == invoiceId &&
            (posted == null ||
                (posted.containsKey(a.settlementTransactionId) &&
                    !reversed.contains(a.settlementTransactionId) &&
                    posted.containsKey(a.invoiceTransactionId) &&
                    !reversed.contains(a.invoiceTransactionId))))
        .fold(0, (sum, a) => sum + a.amountPaise);
  }

  int allocatedFromSettlement(String settlementId, {
    Iterable<FinanceTransaction>? transactions,
  }) {
    final reversed = transactions == null
        ? <String>{}
        : transactions
            .where((t) =>
                t.status == 'posted' && t.transactionType == 'reversal')
            .map((t) => t.reversedTransactionId)
            .whereType<String>()
            .toSet();
    if (reversed.contains(settlementId)) return 0;
    return allocations
        .where((a) => a.settlementTransactionId == settlementId)
        .fold(0, (sum, a) => sum + a.amountPaise);
  }

  int invoiceAmountPaise({
    required String invoiceId,
    required String partyId,
    required String partyType,
    required Iterable<FinanceTransaction> transactions,
    required Iterable<FinancePosting> postings,
  }) {
    final invoice = transactions.firstWhere(
      (t) => t.id == invoiceId && t.status == 'posted',
      orElse: () => throw const FinanceAllocationException(
        'Invoice must be a posted transaction.',
      ),
    );
    if (invoice.transactionType != (partyType == 'customer' ? 'income' : 'expense')) {
      throw const FinanceAllocationException('Transaction is not a supported invoice.');
    }
    final accountId = partyType == 'customer'
        ? 'system:receivables'
        : 'system:payables';
    return postings
        .where((p) =>
            p.transactionId == invoiceId &&
            p.accountId == accountId &&
            p.partyId == partyId)
        .fold(0, (sum, p) => sum + (partyType == 'customer'
            ? p.debitPaise - p.creditPaise
            : p.creditPaise - p.debitPaise));
  }

  int settlementAmountPaise({
    required String settlementId,
    required String partyId,
    required String partyType,
    required Iterable<FinanceTransaction> transactions,
    required Iterable<FinancePosting> postings,
  }) {
    final settlement = transactions.firstWhere(
      (t) => t.id == settlementId && t.status == 'posted',
      orElse: () => throw const FinanceAllocationException(
        'Settlement must be a posted transaction.',
      ),
    );
    if (settlement.transactionType !=
        (partyType == 'customer' ? 'customer_receipt' : 'supplier_payment')) {
      throw const FinanceAllocationException('Transaction is not a matching settlement.');
    }
    final accountId = partyType == 'customer'
        ? 'system:receivables'
        : 'system:payables';
    return postings
        .where((p) =>
            p.transactionId == settlementId &&
            p.accountId == accountId &&
            p.partyId == partyId)
        .fold(0, (sum, p) => sum + (partyType == 'customer'
            ? p.creditPaise - p.debitPaise
            : p.debitPaise - p.creditPaise));
  }

  Future<FinancePaymentAllocation> allocate({
    required String id,
    required String settlementTransactionId,
    required String invoiceTransactionId,
    required String partyId,
    required int amountPaise,
    required String partyType,
    required Iterable<FinanceTransaction> transactions,
    required Iterable<FinancePosting> postings,
  }) async {
    if (id.trim().isEmpty || amountPaise <= 0) {
      throw const FinanceAllocationException('Allocation ID and positive amount are required.');
    }
    if (partyType != 'customer' && partyType != 'supplier') {
      throw const FinanceAllocationException('Only customer and supplier allocations are supported.');
    }
    if (allocations.any((a) => a.id == id)) {
      throw const FinanceAllocationException('Allocation ID already exists.');
    }
    final invoiceAmount = invoiceAmountPaise(
      invoiceId: invoiceTransactionId,
      partyId: partyId,
      partyType: partyType,
      transactions: transactions,
      postings: postings,
    );
    final settlementAmount = settlementAmountPaise(
      settlementId: settlementTransactionId,
      partyId: partyId,
      partyType: partyType,
      transactions: transactions,
      postings: postings,
    );
    final posted = transactions.where((t) => t.status == 'posted').toList();
    final invoice = posted.firstWhere((t) => t.id == invoiceTransactionId);
    final settlement = posted.firstWhere((t) => t.id == settlementTransactionId);
    if (invoice.date.isAfter(settlement.date)) {
      throw const FinanceAllocationException('A settlement cannot be allocated to a future invoice.');
    }

    final existingInvoice = allocatedToInvoice(invoiceTransactionId, transactions: transactions);
    final existingSettlement = allocatedFromSettlement(settlementTransactionId, transactions: transactions);
    if (existingInvoice + amountPaise > invoiceAmount) {
      throw const FinanceAllocationException('Allocation exceeds the invoice outstanding amount.');
    }
    if (existingSettlement + amountPaise > settlementAmount) {
      throw const FinanceAllocationException('Allocation exceeds the unallocated settlement amount.');
    }

    final record = FinancePaymentAllocation(
      id: id,
      settlementTransactionId: settlementTransactionId,
      invoiceTransactionId: invoiceTransactionId,
      partyId: partyId,
      amountPaise: amountPaise,
      createdAt: DateTime.now(),
    );
    await _box.put(id, record.toMap());
    return record;
  }

  /// Allocations are append-only. Reversing a settlement/invoice makes its
  /// allocations ineffective; the historical records remain available.
}
