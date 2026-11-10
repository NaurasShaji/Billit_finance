import 'package:hive/hive.dart';
part 'finance_account.g.dart';

/// A chart-of-accounts entry. Balances are derived from posted journal lines.
@HiveType(typeId: 10)
class FinanceAccount extends HiveObject {
  @HiveField(0) late String id;
  @HiveField(1) late String name;
  /// asset, liability, equity, income, or expense.
  @HiveField(2) late String accountType;
  @HiveField(3) String? parentId;
  @HiveField(4) String currencyCode;
  @HiveField(5) bool active;
  @HiveField(6) DateTime createdAt;

  FinanceAccount({required this.id, required this.name, required this.accountType,
    this.parentId, this.currencyCode = 'INR', this.active = true, DateTime? createdAt})
      : createdAt = createdAt ?? DateTime.now();
}
