import 'package:hive_ce/hive_ce.dart';

part 'salary_component.g.dart';

@HiveType(typeId: 18)
class SalaryComponent extends HiveObject {
  @HiveField(0)
  late String id;
  @HiveField(1)
  late String employeeId;
  @HiveField(2)
  late String name;
  @HiveField(3)
  late String componentType; // earning or deduction
  @HiveField(4)
  late int amountPaise;
  @HiveField(5)
  late DateTime effectiveFrom;
  @HiveField(6)
  DateTime? effectiveTo;
  @HiveField(7)
  bool active;

  SalaryComponent({
    required this.id,
    required this.employeeId,
    required this.name,
    required this.componentType,
    required this.amountPaise,
    required this.effectiveFrom,
    this.effectiveTo,
    this.active = true,
  });
}
