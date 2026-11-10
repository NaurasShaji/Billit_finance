import 'package:hive/hive.dart';

part 'leave_request.g.dart';

@HiveType(typeId: 17)
class LeaveRequest extends HiveObject {
  @HiveField(0)
  late String id;
  @HiveField(1)
  late String employeeId;
  @HiveField(2)
  late String leaveType;
  @HiveField(3)
  late DateTime startDate;
  @HiveField(4)
  late DateTime endDate;
  @HiveField(5)
  String reason;
  @HiveField(6)
  String status; // pending, approved, rejected, cancelled
  @HiveField(7)
  String reviewedBy;
  @HiveField(8)
  DateTime? reviewedAt;
  @HiveField(9)
  DateTime createdAt;

  LeaveRequest({
    required this.id,
    required this.employeeId,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    this.reason = '',
    this.status = 'pending',
    this.reviewedBy = '',
    this.reviewedAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
