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
    final posted = transactions == null ? null : {
      for (final t in transactions)
        if (t.status == 'posted') t.id: t,
    };
    final reversed = posted == null ? <String>{} : posted.values
        .where((t) => t.transactionType == 'reversal')
        .map((t) => t.reversedTransactionId).whereType<String>().toSet();
    if (reversed.contains(settlementId)) return 0;
    return allocations.where((a) =>
      a.settlementTransactionId == settlementId &&
      (posted == null || (posted.containsKey(a.invoiceTransactionId) && !reversed.contains(a.invoiceTransactionId)))
    ).fold(0, (sum, a) => sum + a.amountPaise);
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

  /// Computes the balance remaining after explicit allocations and legacy FIFO
  /// settlements. Excludes the settlement currently being allocated.
  int invoiceOutstandingPaise({
    required String invoiceId, required String partyId, required String partyType,
    required Iterable<FinanceTransaction> transactions, required Iterable<FinancePosting> postings,
    String? excludeSettlementId,
  }) {
    final tx = transactions.where((t)=>t.status=='posted').toList();
    final reversed = tx.where((t)=>t.transactionType=='reversal').map((t)=>t.reversedTransactionId).whereType<String>().toSet();
    final invoiceType = partyType=='customer' ? 'income' : 'expense';
    final settlementType = partyType=='customer' ? 'customer_receipt' : 'supplier_payment';
    final account = partyType=='customer' ? 'system:receivables' : 'system:payables';
    final invoiceBalances = <FinanceTransaction,int>{};
    for (final invoice in tx.where((t)=>t.transactionType==invoiceType && !reversed.contains(t.id))) {
      final gross = invoiceAmountPaise(invoiceId:invoice.id, partyId:partyId, partyType:partyType, transactions:tx, postings:postings);
      final explicit = allocations.where((a)=>a.invoiceTransactionId==invoice.id && a.partyId==partyId && !reversed.contains(a.settlementTransactionId)).fold<int>(0,(s,a)=>s+a.amountPaise);
      invoiceBalances[invoice]=gross>explicit ? gross-explicit : 0;
    }
    final settlements = <FinanceTransaction,int>{};
    for (final settlement in tx.where((t)=>t.transactionType==settlementType && !reversed.contains(t.id) && t.id!=excludeSettlementId)) {
      final gross = postings.where((p)=>p.transactionId==settlement.id && p.accountId==account && p.partyId==partyId).fold<int>(0,(s,p)=>s+(partyType=='customer' ? p.creditPaise-p.debitPaise : p.debitPaise-p.creditPaise));
      final explicit = allocations.where((a)=>a.settlementTransactionId==settlement.id && !reversed.contains(a.invoiceTransactionId) && !reversed.contains(a.settlementTransactionId)).fold<int>(0,(s,a)=>s+a.amountPaise);
      if (gross>explicit) settlements[settlement]=gross-explicit;
    }
    final invoiceOrder = invoiceBalances.keys.toList()..sort((a,b)=>a.date.compareTo(b.date));
    final settlementOrder = settlements.keys.toList()..sort((a,b)=>a.date.compareTo(b.date));
    for (final settlement in settlementOrder) {
      var available = settlements[settlement]!;
      for (final invoice in invoiceOrder) {
        if (available<=0) break;
        if (invoice.date.isAfter(settlement.date)) continue;
        final outstanding = invoiceBalances[invoice]!;
        final applied = available<outstanding ? available : outstanding;
        invoiceBalances[invoice]=outstanding-applied;
        available-=applied;
      }
    }
    final target = invoiceOrder.where((t)=>t.id==invoiceId).firstOrNull;
    if (target==null) throw const FinanceAllocationException('Invoice has no receivable/payable balance for this party.');
    return invoiceBalances[target] ?? 0;
  }
  /// Validates all rows before writing, so one invalid row cannot leave a
  /// partially-created multi-invoice allocation.
  Future<List<FinancePaymentAllocation>> allocateBatch({
    required String settlementTransactionId, required String partyId, required String partyType,
    required List<FinanceAllocationDraft> drafts,
    required Iterable<FinanceTransaction> transactions, required Iterable<FinancePosting> postings,
  }) async {
    if (drafts.isEmpty) return const [];
    if (partyType != 'customer' && partyType != 'supplier') throw const FinanceAllocationException('Only customer and supplier allocations are supported.');
    final tx = transactions.toList(), lines = postings.toList();
    final gross = settlementAmountPaise(settlementId:settlementTransactionId, partyId:partyId, partyType:partyType, transactions:tx, postings:lines);
    final settlement = tx.firstWhere((t) => t.id == settlementTransactionId);
    final existing = allocatedFromSettlement(settlementTransactionId, transactions:tx);
    final ids = <String>{}, totals = <String,int>{};
    var requestedTotal = 0;
    for (final d in drafts) {
      if (d.id.trim().isEmpty || !ids.add(d.id) || allocations.any((a)=>a.id==d.id) || d.amountPaise<=0) throw const FinanceAllocationException('Allocation rows need unique IDs and positive amounts.');
      final invoice = tx.firstWhere((t)=>t.id==d.invoiceTransactionId && t.status=='posted',orElse:()=>throw const FinanceAllocationException('Invoice must be posted.'));
      if (invoice.date.isAfter(settlement.date)) throw const FinanceAllocationException('A settlement cannot be allocated to a future invoice.');
      final balance = invoiceOutstandingPaise(invoiceId:invoice.id, partyId:partyId, partyType:partyType, transactions:tx, postings:lines, excludeSettlementId:settlementTransactionId);
      final requested = (totals[invoice.id] ?? 0) + d.amountPaise;
      if (requested > balance) throw FinanceAllocationException('Allocation exceeds actual outstanding for invoice ${invoice.transactionNumber}.');
      totals[invoice.id] = requested; requestedTotal += d.amountPaise;
    }
    if (existing + requestedTotal > gross) throw const FinanceAllocationException('Allocations exceed the unallocated settlement amount.');
    final createdAt = DateTime.now();
    final records = drafts.map((d)=>FinancePaymentAllocation(id:d.id, settlementTransactionId:settlementTransactionId, invoiceTransactionId:d.invoiceTransactionId, partyId:partyId, amountPaise:d.amountPaise, createdAt:createdAt)).toList(growable:false);
    final snapshot = Map<dynamic,dynamic>.from(_box.toMap());
    try { await _box.putAll({for (final a in records) a.id:a.toMap()}); }
    catch (_) { try { await _box.clear(); await _box.putAll(snapshot); } catch (_) {} rethrow; }
    return records;
  }
  Future<FinancePaymentAllocation> allocate({
    required String id, required String settlementTransactionId, required String invoiceTransactionId,
    required String partyId, required int amountPaise, required String partyType,
    required Iterable<FinanceTransaction> transactions, required Iterable<FinancePosting> postings,
  }) async {
    final result = await allocateBatch(
      settlementTransactionId:settlementTransactionId, partyId:partyId, partyType:partyType,
      drafts:[FinanceAllocationDraft(id:id, invoiceTransactionId:invoiceTransactionId, amountPaise:amountPaise)],
      transactions:transactions, postings:postings,
    );
    return result.single;
  }
  /// Allocations are append-only. Reversing a settlement/invoice makes its
  /// allocations ineffective; the historical records remain available.
}
