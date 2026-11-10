import 'package:hive_ce/hive_ce.dart';

part 'employee_attendance.g.dart';

@HiveType(typeId: 16)
class EmployeeAttendance extends HiveObject {
  @HiveField(0)
  late String id;
  @HiveField(1)
  late String employeeId;
  @HiveField(2)
  late DateTime date;
  @HiveField(3)
  late String status; // present, absent, half_day, leave, holiday
  @HiveField(4)
  DateTime? checkIn;
  @HiveField(5)
  DateTime? checkOut;
  @HiveField(6)
  String notes;
  @HiveField(7)
  DateTime updatedAt;

  EmployeeAttendance({
    required this.id,
    required this.employeeId,
    required this.date,
    required this.status,
    this.checkIn,
    this.checkOut,
    this.notes = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();
}
