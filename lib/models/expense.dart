import 'package:hive/hive.dart';

part 'expense.g.dart';

@HiveType(typeId: 8)
class Expense extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  DateTime date;
  @HiveField(2)
  String category;
  @HiveField(3)
  double amount;
  @HiveField(4)
  String description;

  @HiveField(5)
  String? employeeId;

  // Reserved for immutable finance journal revisions.
  @HiveField(6)
  int financeRevision;

  Expense({
    required this.id,
    required this.date,
    required this.category,
    required this.amount,
    required this.description,
    this.employeeId,
    this.financeRevision = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'category': category,
        'amount': amount,
        'description': description,
        if (employeeId != null) 'employeeId': employeeId,
      };

  static Expense fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      category: json['category'] as String,
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] as String,
      employeeId: json['employeeId'] as String?,
    );
  }
}
