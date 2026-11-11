import 'package:hive_ce_flutter/hive_ce_flutter.dart';

class InvoiceTemplateService {
  static const storageKey = 'invoice_templates_v1';
  static const selectedPaperKey = 'invoice_default_paper_size';
  static const paperSizes = ['50mm', '58mm', '80mm', 'A5', 'A4'];
  static const columns = <Map<String, String>>[
    {'id': 'serial', 'label': 'Sl. No.'},
    {'id': 'product', 'label': 'Product'},
    {'id': 'hsn', 'label': 'HSN/SAC'},
    {'id': 'quantity', 'label': 'Qty'},
    {'id': 'unit', 'label': 'Unit'},
    {'id': 'rate', 'label': 'Rate'},
    {'id': 'discount', 'label': 'Discount'},
    {'id': 'gst_rate', 'label': 'GST %'},
    {'id': 'tax', 'label': 'Tax'},
    {'id': 'amount', 'label': 'Amount'},
  ];


  static const namedStorageKey = 'invoice_named_templates_v1';

  static Map<String, Map<String, dynamic>> namedTemplates(String size) {
    final raw = Hive.box<dynamic>('app_settings').get(namedStorageKey);
    if (raw is! Map) return <String, Map<String, dynamic>>{};
    final bySize = raw[size];
    if (bySize is! Map) return <String, Map<String, dynamic>>{};
    return {
      for (final entry in bySize.entries)
        entry.key.toString(): Map<String, dynamic>.from(entry.value as Map),
    };
  }

  static Future<void> saveNamedTemplate(
      String size, String name, Map<String, dynamic> template) async {
    final box = Hive.box<dynamic>('app_settings');
    final raw = box.get(namedStorageKey);
    final all = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final bySize = all[size] is Map
        ? Map<String, dynamic>.from(all[size] as Map)
        : <String, dynamic>{};
    bySize[name] = {...defaults(size), ...template, 'name': name, 'paperSize': size};
    all[size] = bySize;
    await box.put(namedStorageKey, all);
  }

  static Future<void> deleteNamedTemplate(String size, String name) async {
    final box = Hive.box<dynamic>('app_settings');
    final raw = box.get(namedStorageKey);
    if (raw is! Map || raw[size] is! Map) return;
    final all = Map<String, dynamic>.from(raw);
    final bySize = Map<String, dynamic>.from(all[size] as Map)..remove(name);
    all[size] = bySize;
    await box.put(namedStorageKey, all);
  }

  static Map<String, dynamic> defaults(String size) {
    final compact = size == '50mm' || size == '58mm' || size == '80mm';
    return {
      'name': 'Default $size',
      'paperSize': size,
      'headerTitle': 'INVOICE',
      'footerText': 'Thank you for your business.',
      'termsText': '',
      'showLogo': size == '80mm' || !compact,
      'showBusinessName': true,
      'showAddress': true,
      'showPhone': true,
      'showEmail': !compact,
      'showBusinessGstin': true,
      'showCustomerPhone': true,
      'showCustomerGstin': true,
      'showPaymentMethod': true,
      'showQr': true,
      'showAmountInWords': !compact,
      'showTableBorders': !compact,
      'headerAlignment': compact ? 'center' : 'left',
      'footerAlignment': 'center',
      'fontSize': (size == '50mm' || size == '58mm')
          ? 7.0
          : compact
              ? 8.0
              : 9.0,
      'marginMm': compact ? 2.0 : 10.0,
      'accent': 'blue',
      // Default thermal layout preserves the original ITEM / PRICE / QTY / AMT order.
      'columns': (size == '50mm' || size == '58mm')
          ? ['product', 'quantity', 'amount']
          : size == '80mm'
              ? ['product', 'rate', 'quantity', 'amount']
              : size == 'A5'
                  ? [
                      'serial',
                      'product',
                      'quantity',
                      'rate',
                      'gst_rate',
                      'amount'
                    ]
                  : [
                      'serial',
                      'product',
                      'hsn',
                      'quantity',
                      'rate',
                      'gst_rate',
                      'tax',
                      'amount'
                    ],
      'columnLabels': <String, String>{},
    };
  }

  static Map<String, dynamic> loadAll() {
    final raw = Hive.box<dynamic>('app_settings').get(storageKey);
    final saved =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return {
      for (final size in paperSizes)
        size: saved[size] is Map
            ? {
                ...defaults(size),
                ...Map<String, dynamic>.from(saved[size]),
                'paperSize': size
              }
            : defaults(size)
    };
  }

  static Map<String, dynamic> load(String size) =>
      Map<String, dynamic>.from(loadAll()[size] as Map);
  static String get selected => paperSizes
          .contains(Hive.box<dynamic>('app_settings').get(selectedPaperKey))
      ? Hive.box<dynamic>('app_settings').get(selectedPaperKey).toString()
      : '80mm';

  static Future<void> save(String size, Map<String, dynamic> template) async {
    final all = loadAll();
    all[size] = {...defaults(size), ...template, 'paperSize': size};
    await Hive.box<dynamic>('app_settings').put(storageKey, all);
  }

  static Future<void> select(String size) async {
    if (paperSizes.contains(size)) {
      await Hive.box<dynamic>('app_settings').put(selectedPaperKey, size);
    }
  }

  static Future<void> restore(String size) async {
    final all = loadAll();
    all[size] = defaults(size);
    await Hive.box<dynamic>('app_settings').put(storageKey, all);
  }

  static List<String> validate(Map<String, dynamic> value) {
    final size = value['paperSize'].toString();
    final compact = size == '50mm' || size == '58mm' || size == '80mm';
    final selected = (value['columns'] as List?)?.cast<String>() ?? <String>[];
    const widths58 = {
      'serial': 2,
      'product': 14,
      'hsn': 6,
      'quantity': 5,
      'unit': 4,
      'rate': 7,
      'discount': 6,
      'gst_rate': 5,
      'tax': 7,
      'amount': 10
    };
    const widths80 = {
      'serial': 3,
      'product': 20,
      'hsn': 7,
      'quantity': 5,
      'unit': 4,
      'rate': 9,
      'discount': 7,
      'gst_rate': 5,
      'tax': 8,
      'amount': 10
    };
    const widthsA5 = {
      'serial': 4,
      'product': 24,
      'hsn': 10,
      'quantity': 7,
      'unit': 6,
      'rate': 11,
      'discount': 9,
      'gst_rate': 7,
      'tax': 11,
      'amount': 12
    };
    const widthsA4 = {
      'serial': 5,
      'product': 32,
      'hsn': 12,
      'quantity': 9,
      'unit': 7,
      'rate': 13,
      'discount': 11,
      'gst_rate': 8,
      'tax': 13,
      'amount': 14
    };
    final widths = (size == '50mm' || size == '58mm')
        ? widths58
        : size == '80mm'
            ? widths80
            : size == 'A5'
                ? widthsA5
                : widthsA4;
    final used = selected.fold<int>(0, (sum, id) => sum + (widths[id] ?? 6));
    final limit = (size == '50mm' || size == '58mm')
        ? 32
        : size == '80mm'
            ? 48
            : size == 'A5'
                ? 82
                : 130;
    final warnings = <String>[];
    if (selected.isEmpty) warnings.add('Add at least one table column.');
    if (selected.toSet().length != selected.length) {
      warnings.add('Remove duplicate table columns.');
    }
    if (compact && used > limit) {
      warnings.add(
          'Selected columns may exceed printable width. Hide optional columns or choose a wider paper size.');
    }
    final font = (value['fontSize'] as num).toDouble();
    if (font < ((size == '50mm' || size == '58mm') ? 6 : 7)) {
      warnings.add('Font size is below the recommended readable minimum.');
    }
    if (font > (compact ? 12 : 18)) {
      warnings.add('Font size may cause wrapping or page overflow.');
    }
    final margin = (value['marginMm'] as num).toDouble();
    if (compact && margin > 5) {
      warnings.add('Large margins reduce usable thermal paper width.');
    }
    final header = value['headerTitle']?.toString() ?? '';
    if (compact && header.length > 24) {
      warnings.add(
          'Long invoice heading may wrap or exceed the thermal receipt width.');
    }
    if (compact && value['footerText'].toString().length > 80) {
      warnings.add('Long footer may wrap across several receipt lines.');
    }
    if (compact && value['termsText'].toString().length > 100) {
      warnings.add(
          'Long terms and conditions may make the thermal receipt unusually long.');
    }
    return warnings;
  }
}
