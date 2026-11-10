import 'package:hive/hive.dart';

part 'employee.g.dart';

@HiveType(typeId: 9)
class Employee extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String name;
  @HiveField(2)
  String type; // 'daily' or 'monthly'
  @HiveField(3)
  double wage;
  @HiveField(4)
  int attendance; // For daily wages
  @HiveField(5)
  bool salaryPaid; // Legacy monthly payroll flag
  @HiveField(6)
  String employeeCode;
  @HiveField(7)
  String phone;
  @HiveField(8)
  String email;
  @HiveField(9)
  String? departmentId;
  @HiveField(10)
  String designation;
  @HiveField(11)
  DateTime? joiningDate;
  @HiveField(12)
  String employmentStatus;
  @HiveField(13)
  String emergencyContact;
  @HiveField(14)
  String address;
  @HiveField(15)
  String notes;

  Employee({
    required this.id,
    required this.name,
    required this.type,
    required this.wage,
    this.attendance = 0,
    this.salaryPaid = false,
    this.employeeCode = '',
    this.phone = '',
    this.email = '',
    this.departmentId,
    this.designation = '',
    this.joiningDate,
    this.employmentStatus = 'active',
    this.emergencyContact = '',
    this.address = '',
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'wage': wage,
        'attendance': attendance,
        'salaryPaid': salaryPaid,
        'employeeCode': employeeCode,
        'phone': phone,
        'email': email,
        'departmentId': departmentId,
        'designation': designation,
        'joiningDate': joiningDate?.toIso8601String(),
        'employmentStatus': employmentStatus,
        'emergencyContact': emergencyContact,
        'address': address,
        'notes': notes,
      };

  static Employee fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      wage: (json['wage'] as num).toDouble(),
      attendance: json['attendance'] as int,
      salaryPaid: json['salaryPaid'] as bool,
      employeeCode: json['employeeCode'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      departmentId: json['departmentId'] as String?,
      designation: json['designation'] as String? ?? '',
      joiningDate: json['joiningDate'] == null
          ? null
          : DateTime.parse(json['joiningDate'] as String),
      employmentStatus: json['employmentStatus'] as String? ?? 'active',
      emergencyContact: json['emergencyContact'] as String? ?? '',
      address: json['address'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
    );
  }
}
