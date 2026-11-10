import 'package:hive_ce/hive_ce.dart';

part 'finance_recurring_template.g.dart';

/// A reusable schedule that posts an immutable journal entry when due.
@HiveType(typeId: 22)
class FinanceRecurringTemplate extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String name;
  @HiveField(2)
  String transactionType;
  @HiveField(3)
  String debitAccountId;
  @HiveField(4)
  String creditAccountId;
  @HiveField(5)
  int amountPaise;
  @HiveField(6)
  String interval;
  @HiveField(7)
  DateTime nextDueDate;
  @HiveField(8)
  DateTime? endDate;
  @HiveField(9)
  String? categoryId;
  @HiveField(10)
  String? partyId;
  @HiveField(11)
  String memo;
  @HiveField(12)
  bool active;
  @HiveField(13)
  DateTime createdAt;

  FinanceRecurringTemplate({
    required this.id,
    required this.name,
    required this.transactionType,
    required this.debitAccountId,
    required this.creditAccountId,
    required this.amountPaise,
    required this.interval,
    required this.nextDueDate,
    this.endDate,
    this.categoryId,
    this.partyId,
    this.memo = '',
    this.active = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
