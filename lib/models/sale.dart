import 'package:hive_ce/hive_ce.dart';
import './product.dart'; // Import Product model
import '../services/boxes.dart'; // Import Boxes
part 'sale.g.dart';

@HiveType(typeId: 5)
enum PaymentMethod {
  @HiveField(0)
  cash,
  @HiveField(1)
  card,
  @HiveField(2)
  upi,
}

@HiveType(typeId: 6)
class SaleItem extends HiveObject {
  SaleItem(); // Unnamed constructor
  @HiveField(0)
  late String productId;
  @HiveField(1)
  double qty = 1;
  @HiveField(2)
  double sellingPrice = 0;
  @HiveField(3)
  double costPrice = 0;
  @HiveField(4)
  double subtotal = 0;
  @HiveField(5)
  String unitLabel = 'pcs';
  @HiveField(6)
  String hsnCode = '';
  @HiveField(7)
  double? gstRate;
  @HiveField(8)
  double taxableAmount = 0.0;
  @HiveField(9)
  double cgstAmount = 0.0;
  @HiveField(10)
  double sgstAmount = 0.0;
  @HiveField(11)
  double igstAmount = 0.0;

  // Getters for reports
  String get productName =>
      Hive.box<Product>(Boxes.products).get(productId)?.name ??
      'Unknown Product';
  double get quantity => qty;
  double get totalAmount => subtotal;
  double get profit => (sellingPrice - costPrice) * qty;

  SaleItem.fromSaleItem(SaleItem other) {
    productId = other.productId;
    qty = other.qty;
    sellingPrice = other.sellingPrice;
    costPrice = other.costPrice;
    subtotal = other.subtotal;
    unitLabel = other.unitLabel;
    hsnCode = other.hsnCode;
    gstRate = other.gstRate;
    taxableAmount = other.taxableAmount;
    cgstAmount = other.cgstAmount;
    sgstAmount = other.sgstAmount;
    igstAmount = other.igstAmount;
  }

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'qty': qty,
        'sellingPrice': sellingPrice,
        'costPrice': costPrice,
        'subtotal': subtotal,
        'unitLabel': unitLabel,
        'hsnCode': hsnCode,
        'gstRate': gstRate,
        'taxableAmount': taxableAmount,
        'cgstAmount': cgstAmount,
        'sgstAmount': sgstAmount,
        'igstAmount': igstAmount,
      };

  static SaleItem fromJson(Map<String, dynamic> json) {
    return SaleItem()
      ..productId = json['productId'] as String
      ..qty = (json['qty'] as num).toDouble()
      ..sellingPrice = (json['sellingPrice'] as num).toDouble()
      ..costPrice = (json['costPrice'] as num).toDouble()
      ..subtotal = (json['subtotal'] as num).toDouble()
      ..unitLabel = json['unitLabel'] as String
      ..hsnCode = json['hsnCode'] as String? ?? ''
      ..gstRate = (json['gstRate'] as num?)?.toDouble()
      ..taxableAmount = (json['taxableAmount'] as num?)?.toDouble() ?? 0.0
      ..cgstAmount = (json['cgstAmount'] as num?)?.toDouble() ?? 0.0
      ..sgstAmount = (json['sgstAmount'] as num?)?.toDouble() ?? 0.0
      ..igstAmount = (json['igstAmount'] as num?)?.toDouble() ?? 0.0;
  }
}

@HiveType(typeId: 7)
class Sale extends HiveObject {
  @HiveField(0)
  late String id;
  @HiveField(1)
  late DateTime date;
  @HiveField(2)
  late List<SaleItem> items;
  @HiveField(3)
  double totalAmount = 0;
  @HiveField(4)
  double totalCost = 0;
  @HiveField(5)
  double profit = 0;
  @HiveField(6)
  PaymentMethod payment = PaymentMethod.cash;
  @HiveField(7)
  String customerName = '';
  @HiveField(8)
  String customerPhone = '';
  @HiveField(9)
  String userId = '';
  @HiveField(10)
  double discount = 0.0;
  @HiveField(11)
  bool gstEnabled = false;
  @HiveField(12)
  double gstRate = 0.0;
  @HiveField(13)
  double taxableAmount = 0.0;
  @HiveField(14)
  double cgstAmount = 0.0;
  @HiveField(15)
  double sgstAmount = 0.0;
  @HiveField(16)
  double igstAmount = 0.0;
  @HiveField(17)
  String customerGstin = '';
  @HiveField(18)
  bool interstateSale = false;
  @HiveField(19)
  bool gstInclusive = false;
  // Incremented whenever an existing invoice is edited; finance journals are revisioned.
  @HiveField(20)
  int financeRevision = 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
        'totalAmount': totalAmount,
        'totalCost': totalCost,
        'profit': profit,
        'payment': payment.name,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'userId': userId,
        'discount': discount,
        'gstEnabled': gstEnabled,
        'gstRate': gstRate,
        'taxableAmount': taxableAmount,
        'cgstAmount': cgstAmount,
        'sgstAmount': sgstAmount,
        'igstAmount': igstAmount,
        'customerGstin': customerGstin,
        'interstateSale': interstateSale,
        'gstInclusive': gstInclusive,
        'financeRevision': financeRevision,
      };

  static Sale fromJson(Map<String, dynamic> json) {
    return Sale()
      ..id = json['id'] as String
      ..date = DateTime.parse(json['date'] as String)
      ..items = (json['items'] as List)
          .map((item) => SaleItem.fromJson(item as Map<String, dynamic>))
          .toList()
      ..totalAmount = (json['totalAmount'] as num).toDouble()
      ..totalCost = (json['totalCost'] as num).toDouble()
      ..profit = (json['profit'] as num).toDouble()
      ..payment = PaymentMethod.values.firstWhere(
        (e) => e.name == json['payment'],
        orElse: () => PaymentMethod.cash,
      )
      ..customerName = json['customerName'] as String
      ..customerPhone = json['customerPhone'] as String
      ..userId = json['userId'] as String
      ..discount = (json['discount'] as num?)?.toDouble() ?? 0.0
      ..gstEnabled = json['gstEnabled'] as bool? ?? false
      ..gstRate = (json['gstRate'] as num?)?.toDouble() ?? 0.0
      ..taxableAmount = (json['taxableAmount'] as num?)?.toDouble() ?? 0.0
      ..cgstAmount = (json['cgstAmount'] as num?)?.toDouble() ?? 0.0
      ..sgstAmount = (json['sgstAmount'] as num?)?.toDouble() ?? 0.0
      ..igstAmount = (json['igstAmount'] as num?)?.toDouble() ?? 0.0
      ..customerGstin = json['customerGstin'] as String? ?? ''
      ..interstateSale = json['interstateSale'] as bool? ?? false
      ..gstInclusive = json['gstInclusive'] as bool? ?? false
      ..financeRevision = json['financeRevision'] as int? ?? 0;
  }
}
