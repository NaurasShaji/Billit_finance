import 'package:hive_ce/hive_ce.dart';
part 'finance_posting.g.dart';

/// Monetary values are integer minor units (paise).
@HiveType(typeId: 12)
class FinancePosting {
  @HiveField(0) final String id;
  @HiveField(1) final String transactionId;
  @HiveField(2) final String accountId;
  @HiveField(3) final int debitPaise;
  @HiveField(4) final int creditPaise;
  @HiveField(5) final String? partyId;
  @HiveField(6) final String? categoryId;
  @HiveField(7) final String memo;

  FinancePosting({required this.id, required this.transactionId,
    required this.accountId, this.debitPaise = 0, this.creditPaise = 0,
    this.partyId, this.categoryId, this.memo = ''});
}
