import 'package:hive/hive.dart';

part 'payroll_run.g.dart';

@HiveType(typeId: 19)
class PayrollRun extends HiveObject {
  @HiveField(0)
  late String id;
  @HiveField(1)
  late DateTime periodStart;
  @HiveField(2)
  late DateTime periodEnd;
  @HiveField(3)
  String status; // draft, approved, paid
  @HiveField(4)
  DateTime createdAt;
  @HiveField(5)
  DateTime? approvedAt;
  @HiveField(6)
  DateTime? paidAt;
  @HiveField(7)
  int totalGrossPaise;
  @HiveField(8)
  int totalDeductionsPaise;
  @HiveField(9)
  int totalNetPaise;
  @HiveField(10)
  String memo;

  PayrollRun({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    this.status = 'draft',
    DateTime? createdAt,
    this.approvedAt,
    this.paidAt,
    this.totalGrossPaise = 0,
    this.totalDeductionsPaise = 0,
    this.totalNetPaise = 0,
    this.memo = '',
  }) : createdAt = createdAt ?? DateTime.now();
}
