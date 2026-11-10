import 'package:hive_ce/hive_ce.dart';

part 'hr_department.g.dart';

@HiveType(typeId: 15)
class HrDepartment extends HiveObject {
  @HiveField(0)
  late String id;
  @HiveField(1)
  late String name;
  @HiveField(2)
  String description;
  @HiveField(3)
  bool active;
  @HiveField(4)
  DateTime createdAt;

  HrDepartment({
    required this.id,
    required this.name,
    this.description = '',
    this.active = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
