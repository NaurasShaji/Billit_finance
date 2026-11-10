import 'package:hive_ce/hive_ce.dart';

part 'finance_budget.g.dart';

/// A period budget for one expense account, optionally narrowed to a category.
/// Amounts are stored as integer paise.
@HiveType(typeId: 21)
class FinanceBudget extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String name;
  @HiveField(2)
  String accountId;
  @HiveField(3)
  String? categoryId;
  @HiveField(4)
  DateTime periodStart;
  @HiveField(5)
  DateTime periodEnd;
  @HiveField(6)
  int budgetPaise;
  @HiveField(7)
  bool active;
  @HiveField(8)
  String notes;
  @HiveField(9)
  DateTime createdAt;

  FinanceBudget({
    required this.id,
    required this.name,
    required this.accountId,
    this.categoryId,
    required this.periodStart,
    required this.periodEnd,
    required this.budgetPaise,
    this.active = true,
    this.notes = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
