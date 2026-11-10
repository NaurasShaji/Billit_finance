import 'package:hive/hive.dart';
part 'finance_posting.g.dart';

/// Monetary values are integer minor units (paise).
@HiveType(typeId: 12)
class FinancePosting extends HiveObject {
  @HiveField(0) late String id;
  @HiveField(1) late String transactionId;
  @HiveField(2) late String accountId;
  @HiveField(3) int debitPaise;
  @HiveField(4) int creditPaise;
  @HiveField(5) String? partyId;
  @HiveField(6) String? categoryId;
  @HiveField(7) String memo;

  FinancePosting({required this.id, required this.transactionId,
    required this.accountId, this.debitPaise = 0, this.creditPaise = 0,
    this.partyId, this.categoryId, this.memo = ''});
}
