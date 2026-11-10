import 'package:hive/hive.dart';
part 'finance_party.g.dart';

@HiveType(typeId: 14)
class FinanceParty extends HiveObject {
  @HiveField(0) late String id;
  @HiveField(1) late String name;
  /// customer, supplier, employee, or other.
  @HiveField(2) late String partyType;
  @HiveField(3) String phone;
  @HiveField(4) String email;
  @HiveField(5) String taxIdentifier;
  @HiveField(6) bool active;

  FinanceParty({required this.id, required this.name, required this.partyType,
    this.phone = '', this.email = '', this.taxIdentifier = '', this.active = true});
}
