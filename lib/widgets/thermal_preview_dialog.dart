import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import '../models/models.dart';
import '../services/boxes.dart';
import '../services/invoice_template_service.dart';
import '../services/payment_qr_service.dart';

class ThermalPreviewDialog extends StatelessWidget {
  final Sale sale;
  const ThermalPreviewDialog({super.key, required this.sale});

  static const _labels = <String, String>{
    'serial': '#', 'product': 'Item', 'hsn': 'HSN', 'quantity': 'Qty',
    'unit': 'Unit', 'rate': 'Rate', 'discount': 'Discount',
    'gst_rate': 'GST', 'tax': 'Tax', 'amount': 'Amount',
  };

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final compact = screen.width < 600;
    final template = InvoiceTemplateService.load(InvoiceTemplateService.selected);
    final is58mm = template['paperSize'] == '50mm' || template['paperSize'] == '58mm';
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 8 : 20),
      child: SizedBox(
        width: compact ? screen.width * .96 : 520,
        height: screen.height * (compact ? .9 : .86),
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 18),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.receipt_long_outlined),
              const SizedBox(width: 10),
              Expanded(child: Text('Thermal Receipt Preview · ${template['paperSize']}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              IconButton(onPressed: () => Navigator.of(context).pop(false), icon: const Icon(Icons.close)),
            ]),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Expanded(child: SingleChildScrollView(child: Center(
              child: Container(
                width: is58mm ? 218 : 300,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))]),
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.black, fontFamily: 'monospace', fontSize: 10, height: 1.35),
                  child: _buildReceipt(template, is58mm),
                ),
              ),
            ))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton.icon(onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.print), label: const Text('Print Now'))),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _buildReceipt(Map<String, dynamic> template, bool is58mm) {
    final settings = Hive.box<dynamic>('app_settings');
    final name = settings.get('business_name', defaultValue: '').toString().trim();
    final address = settings.get('business_address', defaultValue: '').toString().trim();
    final phone = settings.get('business_phone', defaultValue: '').toString().trim();
    final email = settings.get('business_email', defaultValue: '').toString().trim();
    final gstin = settings.get('business_gstin', defaultValue: '').toString().trim();
    final footer = template['footerText']?.toString() ?? '';
    final terms = template['termsText']?.toString() ?? '';
    final headerAlign = _alignment(template['headerAlignment']);
    final footerAlign = _alignment(template['footerAlignment']);
    final configuredTitle = template['headerTitle']?.toString().trim() ?? '';
    final title = configuredTitle.isEmpty || (configuredTitle == 'INVOICE' && sale.gstEnabled)
        ? (sale.gstEnabled ? 'TAX INVOICE' : 'INVOICE') : configuredTitle;
    final rawColumns = template['columns'];
    final columns = rawColumns is List
        ? rawColumns.map((e) => e.toString()).where(_labels.containsKey).toList()
        : <String>['product', if (!is58mm) 'rate', 'quantity', 'amount'];
    final customLabels = template['columnLabels'] is Map
        ? Map<String, dynamic>.from(template['columnLabels'] as Map) : <String, dynamic>{};
    final borders = template['showTableBorders'] == true;
    final logoKey = is58mm
        ? 'business_logo_print_58_base64'
        : 'business_logo_print_80_base64';
    final logo = settings.get(logoKey)?.toString() ??
        settings.get('business_logo_base64')?.toString() ??
        '';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (template['showLogo'] == true && logo.isNotEmpty) _buildLogo(logo),
      if (template['showBusinessName'] == true && name.isNotEmpty) _aligned(name, headerAlign, bold: true, size: 15),
      if (template['showAddress'] == true && address.isNotEmpty) _aligned(address, headerAlign),
      if (template['showPhone'] == true && phone.isNotEmpty) _aligned(is58mm ? phone : 'ph: $phone', headerAlign),
      if (template['showEmail'] == true && email.isNotEmpty) _aligned(email, headerAlign),
      if (template['showBusinessGstin'] == true && gstin.isNotEmpty) _aligned('GSTIN: $gstin', headerAlign),
      const SizedBox(height: 7),
      _aligned(title, headerAlign, bold: true, size: 12),
      const SizedBox(height: 5),
      _info('ID:', sale.id),
      _info('Date:', DateFormat('dd/MM/yyyy HH:mm').format(sale.date.toLocal())),
      if (sale.customerName.isNotEmpty) _info('Customer:', sale.customerName),
      if (template['showCustomerGstin'] == true && sale.customerGstin.isNotEmpty) _info('Customer GSTIN:', sale.customerGstin),
      if (template['showCustomerPhone'] == true && sale.customerPhone.isNotEmpty) _info('Phone:', sale.customerPhone),
      if (template['showPaymentMethod'] == true) _info('Payment:', sale.payment.name.toUpperCase()),
      const SizedBox(height: 6),
      if (is58mm) ...sale.items.asMap().entries.map((entry) {
        final item = entry.value;
        final product = Hive.box<Product>(Boxes.products).get(item.productId);
        final values = _itemValues(entry.key, item, product);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (columns.contains('product')) Text(values['product'] ?? ''),
            for (final id in columns.where((id) => id != 'product'))
              Text('${customLabels[id]?.toString().trim().isNotEmpty == true ? customLabels[id] : (_labels[id] ?? id)}: ${values[id] ?? ''}'),
            if (borders) const Divider(color: Colors.black26, height: 6),
          ]),
        );
      }),
      if (!is58mm) ...[
        if (borders) const Divider(color: Colors.black, height: 1),
        _build80Header(columns, customLabels),
        if (borders) const Divider(color: Colors.black, height: 1),
        ...sale.items.asMap().entries.map((entry) {
          final item = entry.value;
          final product = Hive.box<Product>(Boxes.products).get(item.productId);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(_format80Row(columns, _itemValues(entry.key, item, product)),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 8.5)),
          );
        }),
      ],
      if (borders) const Divider(color: Colors.black, height: 1),
      const SizedBox(height: 5),
      _total('Subtotal:', _money(sale.items.fold<double>(0, (sum, item) => sum + item.subtotal))),
      if (sale.discount > 0) _total('Discount:', '-${_money(sale.discount)}'),
      if (sale.gstEnabled) ...[
        _total('Taxable:', _money(sale.taxableAmount)),
        if (sale.interstateSale) _total('IGST:', _money(sale.igstAmount))
        else ...[_total('CGST:', _money(sale.cgstAmount)), _total('SGST:', _money(sale.sgstAmount))],
      ],
      const Divider(color: Colors.black, thickness: 1.2, height: 12),
      _total('TOTAL:', _money(sale.totalAmount), bold: true, size: 14),
      if (template['showQr'] == true)
        FutureBuilder<Uint8List?>(
          future: _loadPaymentQr(),
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null || bytes.isEmpty) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  const Text(
                    'SCAN & PAY',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9),
                  ),
                  const SizedBox(height: 4),
                  Image.memory(bytes, width: 112, height: 112, fit: BoxFit.contain),
                ],
              ),
            );
          },
        ),
      const SizedBox(height: 10),
      if (footer.trim().isNotEmpty) _aligned(footer, footerAlign, bold: true),
      if (terms.trim().isNotEmpty) ...[const SizedBox(height: 5), _aligned(terms, footerAlign)],
    ]);
  }

  Future<Uint8List?> _loadPaymentQr() async {
    try {
      return await PaymentQrService.generateForSale(sale) ??
          await PaymentQrService.loadStaticQrFallback();
    } catch (_) {
      return null;
    }
  }

  Widget _buildLogo(String value) {
    try {
      return Padding(padding: const EdgeInsets.only(bottom: 6),
        child: Center(child: Image.memory(base64Decode(value), height: 58, fit: BoxFit.contain)));
    } catch (_) { return const SizedBox.shrink(); }
  }

  Map<String, String> _itemValues(int index, SaleItem item, Product? product) => {
    'serial': '${index + 1}',
    'product': product?.name ?? 'Unknown Product',
    'hsn': item.hsnCode.isNotEmpty ? item.hsnCode : (product?.hsnCode ?? '-'),
    'quantity': item.qty.toString(),
    'unit': item.unitLabel,
    'rate': _money(item.sellingPrice),
    'discount': '-',
    'gst_rate': sale.gstEnabled ? '${(item.gstRate ?? 0).toStringAsFixed(0)}%' : '-',
    'tax': sale.gstEnabled ? _money(item.cgstAmount + item.sgstAmount + item.igstAmount) : '-',
    'amount': _money(item.subtotal),
  };

  Widget _build80Header(List<String> columns, Map<String, dynamic> custom) {
    const defaults = <String, String>{
      'serial': '#', 'product': 'ITEM', 'hsn': 'HSN', 'quantity': 'QTY',
      'unit': 'UNIT', 'rate': 'RATE', 'discount': 'DISC', 'gst_rate': 'GST%',
      'tax': 'TAX', 'amount': 'AMOUNT',
    };
    final labels = columns.map((id) {
      final value = custom[id]?.toString().trim() ?? '';
      return value.isNotEmpty ? value : (defaults[id] ?? id);
    }).toList();
    return Text(_format80Cells(columns, labels),
      style: const TextStyle(fontFamily: 'monospace', fontSize: 8.5, fontWeight: FontWeight.bold));
  }

  String _format80Row(List<String> columns, Map<String, String> values) =>
      _format80Cells(columns, columns.map((id) => values[id] ?? '').toList());

  String _format80Cells(List<String> columns, List<String> values) {
    const preferred = <String, int>{
      'serial': 3, 'product': 20, 'hsn': 7, 'quantity': 5, 'unit': 4,
      'rate': 9, 'discount': 7, 'gst_rate': 5, 'tax': 8, 'amount': 10,
    };
    final widths = columns.map((id) => preferred[id] ?? 6).toList();
    final total = widths.fold<int>(0, (sum, width) => sum + width);
    if (total > 48) {
      for (var i = 0; i < widths.length; i++) {
        widths[i] = (widths[i] * 48 / total).floor().clamp(3, 48);
      }
    } else if (widths.isNotEmpty) {
      final productIndex = columns.indexOf('product');
      widths[productIndex >= 0 ? productIndex : widths.length - 1] +=
          48 - widths.fold<int>(0, (sum, width) => sum + width);
    }
    return List.generate(columns.length, (i) {
      final value = values[i];
      final width = widths[i];
      final fitted = value.length > width ? value.substring(0, width) : value;
      return columns[i] == 'product' ? fitted.padRight(width) : fitted.padLeft(width);
    }).join();
  }

  Widget _tableHeader(List<String> columns, Map<String, dynamic> custom) =>
      _tableRow(columns, (id) {
        final label = custom[id]?.toString().trim() ?? '';
        return label.isNotEmpty ? label : (_labels[id] ?? id);
      }, bold: true);

  Widget _tableRow(List<String> columns, String Function(String) valueFor, {bool bold = false}) {
    if (columns.isEmpty) return const SizedBox.shrink();
    const weights = <String, int>{'serial': 2, 'product': 8, 'hsn': 4, 'quantity': 4, 'unit': 3,
      'rate': 5, 'discount': 5, 'gst_rate': 3, 'tax': 5, 'amount': 5};
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: columns.map((id) {
      final right = const {'rate', 'discount', 'tax', 'amount'}.contains(id);
      final center = const {'serial', 'quantity', 'unit', 'gst_rate'}.contains(id);
      return Expanded(flex: weights[id] ?? 4, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Text(valueFor(id), textAlign: right ? TextAlign.right : center ? TextAlign.center : TextAlign.left,
          softWrap: id == 'product', overflow: TextOverflow.visible,
          style: TextStyle(fontFamily: 'monospace', fontSize: 8.5, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      ));
    }).toList());
  }

  Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9)),
      const SizedBox(width: 5), Expanded(child: Text(value, style: const TextStyle(fontSize: 9))),
    ]),
  );

  Widget _total(String label, String value, {bool bold = false, double size = 9}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: size)),
      Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: size)),
    ]),
  );

  Widget _aligned(String value, TextAlign align, {bool bold = false, double size = 9}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Text(value, textAlign: align, style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
  );

  TextAlign _alignment(dynamic value) {
    switch (value?.toString()) {
      case 'left': return TextAlign.left;
      case 'right': return TextAlign.right;
      default: return TextAlign.center;
    }
  }

  String _money(double value) => 'Rs.${value.toStringAsFixed(2)}';
}

Future<bool?> showThermalPreviewDialog(BuildContext context, Sale sale) {
  return showDialog<bool>(context: context, builder: (context) => ThermalPreviewDialog(sale: sale));
}
