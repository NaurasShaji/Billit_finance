import 'package:hive_ce/hive_ce.dart';
part 'finance_transaction.g.dart';

/// Posted records are immutable; corrections use reversing transactions.
@HiveType(typeId: 11)
class FinanceTransaction {
  @HiveField(0) final String id;
  @HiveField(1) final String transactionNumber;
  /// income, expense, transfer, customer_receipt, supplier_payment,
  /// opening_balance, adjustment, or reversal.
  @HiveField(2) final String transactionType;
  /// draft, posted, or reversed.
  @HiveField(3) final String status;
  @HiveField(4) final DateTime date;
  @HiveField(5) final String memo;
  @HiveField(6) final String reference;
  @HiveField(7) final String sourceType;
  @HiveField(8) final String sourceId;
  @HiveField(9) final DateTime createdAt;
  @HiveField(10) final DateTime? postedAt;
  @HiveField(11) final String? reversedTransactionId;

  FinanceTransaction({required this.id, required this.transactionNumber,
    required this.transactionType, this.status = 'draft', DateTime? date,
    this.memo = '', this.reference = '', this.sourceType = '', this.sourceId = '',
    DateTime? createdAt, this.postedAt, this.reversedTransactionId})
      : date = date ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();
}
