import 'package:hive_ce/hive_ce.dart';
part 'product.g.dart';

@HiveType(typeId: 3)
enum UnitType {
  @HiveField(0)
  pcs,
  @HiveField(1)
  kg,
  @HiveField(2)
  sqft,
}

@HiveType(typeId: 4)
class Product extends HiveObject {
  @HiveField(0)
  late String id;
  @HiveField(1)
  late String name;
  @HiveField(2)
  double sellingPrice = 0; // customer price
  @HiveField(3)
  double costPrice = 0; // purchase price
  @HiveField(4)
  double stock = 0;
  @HiveField(5)
  UnitType unit = UnitType.pcs;
  @HiveField(6)
  String category = 'General';
  @HiveField(7)
  String subCategory = '';
  @HiveField(8)
  bool active = true;
  @HiveField(9)
  String? barcode;
  @HiveField(10)
  String hsnCode = '';
  @HiveField(11)
  double? gstRate;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sellingPrice': sellingPrice,
        'costPrice': costPrice,
        'stock': stock,
        'unit': unit.name,
        'category': category,
        'subCategory': subCategory,
        'active': active,
        'barcode': barcode,
        'hsnCode': hsnCode,
        'gstRate': gstRate,
      };

  static Product fromJson(Map<String, dynamic> json) {
    return Product()
      ..id = json['id'] as String
      ..name = json['name'] as String
      ..sellingPrice = (json['sellingPrice'] as num).toDouble()
      ..costPrice = (json['costPrice'] as num).toDouble()
      ..stock = (json['stock'] as num).toDouble()
      ..unit = UnitType.values.firstWhere(
        (e) => e.name == json['unit'],
        orElse: () => UnitType.pcs,
      )
      ..category = json['category'] as String
      ..subCategory = json['subCategory'] as String
      ..active = json['active'] as bool? ?? true
      ..barcode = json['barcode'] as String?
      ..hsnCode = json['hsnCode'] as String? ?? ''
      ..gstRate = (json['gstRate'] as num?)?.toDouble();
  }
}
