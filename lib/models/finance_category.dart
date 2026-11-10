import 'package:hive_ce/hive_ce.dart';
part 'finance_category.g.dart';

@HiveType(typeId: 13)
class FinanceCategory extends HiveObject {
  @HiveField(0) late String id;
  @HiveField(1) late String name;
  /// income or expense.
  @HiveField(2) late String kind;
  @HiveField(3) late String accountId;
  @HiveField(4) bool active;

  FinanceCategory({required this.id, required this.name, required this.kind,
    required this.accountId, this.active = true});
}
