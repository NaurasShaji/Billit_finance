import 'package:hive/hive.dart';
part 'finance_transaction.g.dart';

/// Posted records are immutable; corrections use reversing transactions.
@HiveType(typeId: 11)
class FinanceTransaction extends HiveObject {
  @HiveField(0) late String id;
  @HiveField(1) late String transactionNumber;
  /// income, expense, transfer, opening_balance, adjustment, or reversal.
  @HiveField(2) late String transactionType;
  /// draft, posted, or reversed.
  @HiveField(3) String status;
  @HiveField(4) DateTime date;
  @HiveField(5) String memo;
  @HiveField(6) String reference;
  @HiveField(7) String sourceType;
  @HiveField(8) String sourceId;
  @HiveField(9) DateTime createdAt;
  @HiveField(10) DateTime? postedAt;
  @HiveField(11) String? reversedTransactionId;

  FinanceTransaction({required this.id, required this.transactionNumber,
    required this.transactionType, this.status = 'draft', DateTime? date,
    this.memo = '', this.reference = '', this.sourceType = '', this.sourceId = '',
    DateTime? createdAt, this.postedAt, this.reversedTransactionId})
      : date = date ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();
}
