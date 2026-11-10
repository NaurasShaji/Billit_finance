import 'package:hive/hive.dart';

part 'payslip.g.dart';

@HiveType(typeId: 20)
class Payslip extends HiveObject {
  @HiveField(0)
  late String id;
  @HiveField(1)
  late String payrollRunId;
  @HiveField(2)
  late String employeeId;
  @HiveField(3)
  late String payType;
  @HiveField(4)
  int basePaise;
  @HiveField(5)
  int allowancesPaise;
  @HiveField(6)
  int deductionsPaise;
  @HiveField(7)
  double payableDays;
  @HiveField(8)
  int paidPaise;
  @HiveField(9)
  String status; // draft, approved, partially_paid, paid
  @HiveField(10)
  DateTime generatedAt;
  @HiveField(11)
  DateTime? paidAt;

  int get grossPaise => basePaise + allowancesPaise;
  int get netPaise => grossPaise - deductionsPaise;
  int get outstandingPaise => (netPaise - paidPaise).clamp(0, netPaise);

  Payslip({
    required this.id,
    required this.payrollRunId,
    required this.employeeId,
    required this.payType,
    required this.basePaise,
    this.allowancesPaise = 0,
    this.deductionsPaise = 0,
    this.payableDays = 0,
    this.paidPaise = 0,
    this.status = 'draft',
    DateTime? generatedAt,
    this.paidAt,
  }) : generatedAt = generatedAt ?? DateTime.now();
}
