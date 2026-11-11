import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:share_plus/share_plus.dart';
import '../models/models.dart';
import './boxes.dart';
import './payment_qr_service.dart';
import './invoice_template_service.dart';

class InvoicePdf {
  const InvoicePdf({required this.bytes, required this.filename});
  final Uint8List bytes;
  final String filename;
}

class PdfService {
  // Thermal printer configurations
  static const double thermalWidth58mm = 164.0; // 58mm width
  static const double thermalWidth80mm = 227.0; // 80mm width

  static Future<void> generateInvoice(
    Sale sale, {
    ThermalSize thermalSize = ThermalSize.mm80,
    bool includeHeader = true,
    bool includeFooter = true,
    bool includeGST = true,
    bool fullPage = true,
    bool share = false,
  }) async {
    final pdf = await buildInvoicePdf(
      sale,
      thermalSize: thermalSize,
      includeHeader: includeHeader,
      includeFooter: includeFooter,
      includeGST: includeGST,
      fullPage: fullPage,
    );
    if (share) {
      await Share.shareXFiles(
        [
          XFile.fromData(
            pdf.bytes,
            mimeType: 'application/pdf',
            name: pdf.filename,
          ),
        ],
        subject: pdf.filename,
      );
      return;
    }
    await FilePicker.platform.saveFile(
      dialogTitle: 'Save invoice PDF',
      fileName: pdf.filename,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: pdf.bytes,
    );
  }

  /// Builds the configured invoice PDF without opening a save/share dialog.
  static Future<InvoicePdf> buildInvoicePdf(
    Sale sale, {
    ThermalSize thermalSize = ThermalSize.mm80,
    bool includeHeader = true,
    bool includeFooter = true,
    bool includeGST = true,
    bool fullPage = true,
    bool forceA4 = false,
    Map<String, dynamic>? templateOverride,
  }) async {
    final doc = pw.Document();
    // The customisation screen supplies its unsaved values here so the live
    // preview uses the exact same PDF layout as the final invoice.
    final template = templateOverride ??
        InvoiceTemplateService.load(InvoiceTemplateService.selected);
    // Some delivery channels (e.g. WhatsApp invoices) require a consistent
    // full-page document regardless of the printer's configured paper size.
    final paperSize =
        forceA4 ? 'A4' : template['paperSize'].toString();
    final isThermal = paperSize == '50mm' || paperSize == '58mm' || paperSize == '80mm';
    final effectiveThermalSize =
        (paperSize == '50mm' || paperSize == '58mm') ? ThermalSize.mm58 : ThermalSize.mm80;
    final marginMm = (template['marginMm'] as num).toDouble();
    final marginPoints = marginMm * 72 / 25.4;
    final useFullPage = fullPage && !isThermal;
    // Full-page invoices draw the UPI QR as crisp vector art; a raster image
    // is only used for an uploaded static QR or the thermal receipt.
    String? qrData;
    if (useFullPage) {
      try {
        final candidate = PaymentQrService.paymentUriForSale(sale);
        // Validate the payload before handing it to the PDF painter. A very
        // long or malformed UPI URI must not prevent invoice generation.
        if (candidate != null) PaymentQrService.moduleMatrix(candidate);
        qrData = candidate;
      } catch (_) {
        qrData = null;
      }
    }
    final qrImage = qrData != null ? null : await _loadPaymentQrImage(sale);

    if (useFullPage) {
      final pageFormat = paperSize == 'A5' ? PdfPageFormat.a5 : PdfPageFormat.a4;
      final content = _buildFullPageInvoice(
        sale,
        includeHeader: includeHeader,
        includeFooter: includeFooter,
        includeGST: includeGST,
        isA5: paperSize == 'A5',
        qrImage: qrImage,
        qrData: qrData,
        template: template,
      );
      // Both A4 and A5 use the same visual system and paginate naturally.
      // Do not scale a long A5 invoice to one page: that makes the text
      // unreadable and defeats the configured font-size setting.
      doc.addPage(
        pw.MultiPage(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.all(marginPoints),
          build: (context) => content,
        ),
      );
    } else {
      final double pageWidth = effectiveThermalSize == ThermalSize.mm58
          ? thermalWidth58mm
          : thermalWidth80mm;
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            pageWidth,
            double.infinity,
            marginLeft: marginPoints,
            marginRight: marginPoints,
            marginTop: marginPoints,
            marginBottom: marginPoints,
          ),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: _buildThermalReceipt(
              sale,
              effectiveThermalSize,
              qrImage,
              includeHeader,
              includeFooter,
            ),
          ),
        ),
      );
    }

    final filename =
        '${includeGST && sale.gstEnabled ? 'gst_invoice' : 'invoice'}_${sale.id}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    return InvoicePdf(
      bytes: Uint8List.fromList(await doc.save()),
      filename: filename,
    );
  }

  static List<pw.Widget> _buildFullPageInvoice(
    Sale sale, {
    required bool includeHeader,
    required bool includeFooter,
    required bool includeGST,
    required bool isA5,
    pw.ImageProvider? qrImage,
    String? qrData,
    required Map<String, dynamic> template,
  }) {
    final settings = Hive.box<dynamic>('app_settings');
    final businessName =
        settings.get('business_name', defaultValue: 'Business Name').toString();
    final accent =
        _invoiceAccentColor(template['accent']?.toString() ?? 'blue');
    final footerText = template['footerText']?.toString().trim() ??
        'Thank you for your business.';
    final businessAddress =
        settings.get('business_address', defaultValue: '').toString();
    final businessPhone =
        settings.get('business_phone', defaultValue: '').toString();
    final businessEmail =
        settings.get('business_email', defaultValue: '').toString();
    final businessGstin =
        settings.get('business_gstin', defaultValue: '').toString();
    pw.ImageProvider? businessLogo;
    final logoBase64 = settings.get('business_logo_base64') as String?;
    if (logoBase64 != null && logoBase64.isNotEmpty) {
      try {
        businessLogo = pw.MemoryImage(base64Decode(logoBase64));
      } catch (_) {
        businessLogo = null;
      }
    }
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ');
    // Non-breaking space keeps "Rs." and the amount on the same line.
    String money(double v) =>
        currency.format(v).replaceAll(RegExp(r'[ \u00A0]'), '\u00A0');
    final subtotal =
        sale.items.fold<double>(0, (sum, item) => sum + item.subtotal);
    final taxable = sale.gstEnabled
        ? sale.taxableAmount
        : (subtotal - sale.discount).clamp(0.0, double.infinity).toDouble();
    final taxTotal = sale.cgstAmount + sale.sgstAmount + sale.igstAmount;
    final displayGst = includeGST && sale.gstEnabled;
    final configuredTitle = template['headerTitle']?.toString().trim() ?? '';
    final invoiceTitle =
        configuredTitle.isEmpty || (configuredTitle == 'INVOICE' && displayGst)
            ? (displayGst ? 'TAX INVOICE' : 'INVOICE')
            : configuredTitle;
    final productsBox = Hive.box<Product>(Boxes.products);
    final configuredColumns = (template['columns'] as List).cast<String>();
    final columnLabels = (template['columnLabels'] as Map?) ?? const {};

    // ---- Layout metrics -------------------------------------------------
    // One layout, scaled for A5. Sized so 10 products fit on a single page
    // for both paper sizes (A4 additionally flows onto a 2nd page if needed).
    final s = isA5 ? 0.72 : 1.0;
    final fs = (template['fontSize'] as num).toDouble() * (isA5 ? 0.92 : 1.0);
    final rowHeight = isA5 ? 16.5 : 28.0;
    final headerRowHeight = isA5 ? 18.0 : 28.0;
    // A4 keeps the designed minimum table height; A5 does not insert
    // artificial blank rows that would force the entire invoice to shrink.
    final minRows = isA5 ? sale.items.length : 10;

    final ink = PdfColor.fromInt(0xFF1F2933);
    final muted = PdfColor.fromInt(0xFF6B7280);
    final line = PdfColor.fromInt(0xFFE2E8F0);
    final tint = _tint(accent, 0.93);

    // ---- Small building blocks -----------------------------------------
    pw.Widget sectionLabel(String text) => pw.Text(text,
        style: pw.TextStyle(
            fontSize: fs * 0.78,
            fontWeight: pw.FontWeight.bold,
            color: accent,
            letterSpacing: 0.9));

    pw.Widget card({required pw.Widget child, PdfColor? fill}) =>
        pw.Container(
          padding:
              pw.EdgeInsets.symmetric(horizontal: 10 * s, vertical: 8 * s),
          decoration: pw.BoxDecoration(
            color: fill ?? PdfColors.white,
            border: pw.Border.all(color: line, width: 0.8),
            borderRadius: pw.BorderRadius.circular(6 * s),
          ),
          child: child,
        );

    pw.Widget metaRow(String label, String value) => pw.Padding(
          padding: pw.EdgeInsets.symmetric(vertical: 1.6 * s),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label,
                  style: pw.TextStyle(
                      fontSize: fs * 0.75,
                      color: muted,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 0.6)),
              pw.SizedBox(width: 8 * s),
              pw.Expanded(
                child: pw.Text(value,
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                        fontSize: fs,
                        color: ink,
                        fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
        );

    // ---- Header: logo + business identity (left), title + meta (right) --
    final logoHeight = isA5 ? 54.0 : 88.0;
    pw.Widget? logoTile;
    if (template['showLogo'] == true && businessLogo != null) {
      final w = businessLogo.width;
      final h = businessLogo.height;
      final aspect = (w != null && h != null && h > 0) ? w / h : 1.0;
      final logoWidth =
          (logoHeight * aspect).clamp(logoHeight * 0.85, logoHeight * 2.4);
      logoTile = pw.Container(
        width: logoWidth.toDouble(),
        height: logoHeight,
        padding: pw.EdgeInsets.all(4 * s),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border.all(color: line, width: 0.8),
          borderRadius: pw.BorderRadius.circular(8 * s),
        ),
        child: pw.Image(businessLogo, fit: pw.BoxFit.contain),
      );
    }

    final headerAlignment = template['headerAlignment'] == 'center'
        ? pw.CrossAxisAlignment.center
        : template['headerAlignment'] == 'right'
            ? pw.CrossAxisAlignment.end
            : pw.CrossAxisAlignment.start;
    final headerTextAlign = template['headerAlignment'] == 'center'
        ? pw.TextAlign.center
        : template['headerAlignment'] == 'right'
            ? pw.TextAlign.right
            : pw.TextAlign.left;
    final identity = pw.Column(
      crossAxisAlignment: headerAlignment,
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        if (template['showBusinessName'] == true)
          pw.Text(businessName,
              textAlign: headerTextAlign,
              style: pw.TextStyle(
                  fontSize: fs * (isA5 ? 1.7 : 2.0),
                  fontWeight: pw.FontWeight.bold,
                  color: ink)),
        pw.SizedBox(height: 3 * s),
        if (template['showAddress'] == true && businessAddress.isNotEmpty)
          pw.Text(businessAddress,
              textAlign: headerTextAlign,
              style: pw.TextStyle(fontSize: fs * 0.95, color: muted)),
        ...(() {
          final phone = (template['showPhone'] == true && businessPhone.isNotEmpty)
              ? 'Phone: $businessPhone'
              : '';
          final email = (template['showEmail'] == true && businessEmail.isNotEmpty)
              ? 'Email: $businessEmail'
              : '';
          final lines = isA5 && phone.isNotEmpty && email.isNotEmpty
              ? ['$phone  |  $email']
              : [phone, email];
          return [
            for (final line in lines)
              if (line.isNotEmpty)
                pw.Text(line,
                    textAlign: headerTextAlign,
                    style: pw.TextStyle(fontSize: fs * 0.95, color: muted)),
          ];
        })(),
        if (template['showBusinessGstin'] == true && businessGstin.isNotEmpty)
          pw.Padding(
            padding: pw.EdgeInsets.only(top: 2 * s),
            child: pw.Text('GSTIN: $businessGstin',
                textAlign: headerTextAlign,
                style: pw.TextStyle(
                    fontSize: fs * 0.95,
                    color: ink,
                    fontWeight: pw.FontWeight.bold)),
          ),
      ],
    );

    final titleBlock = pw.SizedBox(
      width: isA5 ? 142 : 182,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(invoiceTitle,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                  fontSize: fs * (isA5 ? 1.75 : 2.1),
                  fontWeight: pw.FontWeight.bold,
                  color: accent,
                  letterSpacing: 1.0)),
          pw.SizedBox(height: 6 * s),
          pw.Container(
            padding:
                pw.EdgeInsets.symmetric(horizontal: 9 * s, vertical: 6 * s),
            decoration: pw.BoxDecoration(
              color: tint,
              borderRadius: pw.BorderRadius.circular(6 * s),
            ),
            child: pw.Column(children: [
              metaRow('INVOICE NO', sale.id),
              metaRow('DATE', DateFormat('dd MMM yyyy').format(sale.date.toLocal())),
              metaRow('TIME', DateFormat('hh:mm a').format(sale.date.toLocal())),
            ]),
          ),
        ],
      ),
    );

    // ---- Bill-to / payment cards ---------------------------------------
    final billTo = pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          sectionLabel('BILL TO'),
          pw.SizedBox(height: 4 * s),
          pw.Text(
              sale.customerName.isEmpty
                  ? 'Walk-in customer'
                  : sale.customerName,
              style: pw.TextStyle(
                  fontSize: fs * 1.25,
                  fontWeight: pw.FontWeight.bold,
                  color: ink)),
          if (template['showCustomerPhone'] == true &&
              sale.customerPhone.isNotEmpty)
            pw.Text('Phone: ${sale.customerPhone}',
                style: pw.TextStyle(fontSize: fs, color: muted)),
          if (template['showCustomerGstin'] == true &&
              sale.customerGstin.isNotEmpty)
            pw.Text('GSTIN: ${sale.customerGstin}',
                style: pw.TextStyle(fontSize: fs, color: muted)),
        ],
      );
    final showPaymentCard = template['showPaymentMethod'] == true || displayGst;
    final paymentCard = pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          sectionLabel('PAYMENT'),
          pw.SizedBox(height: 4 * s),
          if (template['showPaymentMethod'] == true)
            pw.Text(sale.payment.name.toUpperCase(),
                style: pw.TextStyle(
                    fontSize: fs * 1.25,
                    fontWeight: pw.FontWeight.bold,
                    color: ink)),
          if (displayGst)
            pw.Text(
                sale.interstateSale
                    ? 'Interstate supply (IGST)'
                    : 'Intrastate supply (CGST + SGST)',
                style: pw.TextStyle(fontSize: fs * 0.95, color: muted)),
        ],
      );

    // ---- Items table (always shows at least 10 rows) -------------------
    String qtyText(double q) => q == q.roundToDouble()
        ? q.toInt().toString()
        : q.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

    String cellValue(int i, String id) {
      final item = sale.items[i];
      final product = productsBox.get(item.productId);
      switch (id) {
        case 'serial':
          return '${i + 1}';
        case 'product':
          return product?.name ?? 'Unknown Product';
        case 'hsn':
          return item.hsnCode.isNotEmpty ? item.hsnCode : (product?.hsnCode ?? '-');
        case 'quantity':
          return qtyText(item.qty);
        case 'unit':
          return item.unitLabel;
        case 'rate':
          return money(item.sellingPrice);
        case 'discount':
          // Sale discounts are stored at invoice level. Allocate the total
          // proportionally across lines for a meaningful per-row display.
          return subtotal > 0
              ? money(sale.discount * item.subtotal / subtotal)
              : money(0);
        case 'gst_rate':
          return displayGst ? '${(item.gstRate ?? 0.0).toStringAsFixed(2)}%' : '-';
        case 'tax':
          return displayGst
              ? money(item.cgstAmount + item.sgstAmount + item.igstAmount)
              : '-';
        case 'amount':
          return money(displayGst
              ? item.taxableAmount +
                  item.cgstAmount +
                  item.sgstAmount +
                  item.igstAmount
              : item.subtotal);
        default:
          return '';
      }
    }

    String labelFor(String id) {
      final custom = columnLabels[id]?.toString().trim() ?? '';
      return custom.isNotEmpty ? custom : _invoiceColumnLabel(id);
    }

    pw.Alignment alignFor(String id) {
      switch (id) {
        case 'product':
          return pw.Alignment.centerLeft;
        case 'serial':
        case 'hsn':
        case 'unit':
        case 'quantity':
          return pw.Alignment.center;
        default:
          return pw.Alignment.centerRight;
      }
    }

    pw.TextAlign textAlignFor(String id) {
      switch (id) {
        case 'product':
          return pw.TextAlign.left;
        case 'serial':
        case 'hsn':
        case 'unit':
        case 'quantity':
          return pw.TextAlign.center;
        default:
          return pw.TextAlign.right;
      }
    }

    double flexFor(String id) => (isA5
            ? const {
                'serial': 0.7,
                'product': 3.0,
                'hsn': 1.2,
                'quantity': 0.9,
                'unit': 0.8,
                'rate': 1.5,
                'discount': 1.2,
                'gst_rate': 1.0,
                'tax': 1.4,
                'amount': 1.7,
              }
            : const {
                'serial': 0.55,
                'product': 4.2,
                'hsn': 1.2,
                'quantity': 0.9,
                'unit': 0.8,
                'rate': 1.4,
                'discount': 1.1,
                'gst_rate': 0.95,
                'tax': 1.3,
                'amount': 1.6,
              })[id] ??
        1.0;

    pw.Widget tableCell(String text, String id,
        {bool header = false, bool bold = false}) {
      return pw.Container(
        constraints: pw.BoxConstraints(
            minHeight: header ? headerRowHeight : rowHeight),
        alignment: alignFor(id),
        padding: pw.EdgeInsets.symmetric(horizontal: 7 * s, vertical: 3 * s),
        child: pw.Text(
          text,
          maxLines: id == 'product' ? 2 : 1,
          textAlign: textAlignFor(id),
          style: pw.TextStyle(
            fontSize: header ? fs * 0.9 : fs,
            fontWeight:
                (header || bold) ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: header ? PdfColors.white : ink,
            letterSpacing: header ? 0.4 : 0,
          ),
        ),
      );
    }

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(color: accent),
        children: [
          for (final id in configuredColumns)
            tableCell(labelFor(id).toUpperCase(), id, header: true),
        ],
      ),
      for (var i = 0; i < sale.items.length; i++)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: i.isEven ? PdfColors.white : tint,
            border: pw.Border(
                bottom: pw.BorderSide(color: line, width: 0.5)),
          ),
          children: [
            for (final id in configuredColumns)
              tableCell(cellValue(i, id), id,
                  bold: id == 'amount' || id == 'product'),
          ],
        ),
      // Empty rows keep the table the same height for short invoices.
      for (var i = sale.items.length; i < minRows; i++)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: i.isEven ? PdfColors.white : tint,
            border: pw.Border(
                bottom: pw.BorderSide(color: line, width: 0.5)),
          ),
          children: [
            for (final id in configuredColumns) tableCell('', id),
          ],
        ),
    ];

    // ---- Totals ---------------------------------------------------------
    final totalsWidth = isA5 ? 166.0 : 220.0;
    pw.Widget totalRow(String label, String value, {PdfColor? valueColor}) =>
        pw.Padding(
          padding:
              pw.EdgeInsets.symmetric(horizontal: 6 * s, vertical: 3 * s),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label,
                  style: pw.TextStyle(fontSize: fs, color: muted)),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: fs,
                      color: valueColor ?? ink,
                      fontWeight: pw.FontWeight.bold)),
            ],
          ),
        );

    final totals = pw.SizedBox(
      width: totalsWidth,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          totalRow('Subtotal', money(subtotal)),
          if (sale.discount > 0)
            totalRow('Discount', '-${money(sale.discount)}',
                valueColor: PdfColors.red700),
          if (displayGst) totalRow('Taxable value', money(taxable)),
          if (displayGst && !sale.interstateSale)
            totalRow('CGST', money(sale.cgstAmount)),
          if (displayGst && !sale.interstateSale)
            totalRow('SGST', money(sale.sgstAmount)),
          if (displayGst && sale.interstateSale)
            totalRow('IGST', money(sale.igstAmount)),
          if (displayGst) totalRow('Total GST', money(taxTotal)),
          pw.SizedBox(height: 5 * s),
          pw.Container(
            padding:
                pw.EdgeInsets.symmetric(horizontal: 10 * s, vertical: 9 * s),
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: pw.BorderRadius.circular(6 * s),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('GRAND TOTAL',
                    style: pw.TextStyle(
                        fontSize: fs * 0.9,
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.6)),
                pw.Text(money(sale.totalAmount),
                    style: pw.TextStyle(
                        fontSize: fs * 1.45,
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );

    // ---- QR card (vector => sharp at any zoom / print resolution) -------
    final qrSize = isA5 ? 82.0 : 128.0;
    pw.Widget? qrCard;
    if (template['showQr'] == true && (qrData != null || qrImage != null)) {
      qrCard = pw.Container(
        width: qrSize + 16 * s,
        padding: pw.EdgeInsets.all(8 * s),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border.all(color: line, width: 0.8),
          borderRadius: pw.BorderRadius.circular(8 * s),
        ),
        child: pw.Column(
          children: [
            sectionLabel('SCAN & PAY'),
            pw.SizedBox(height: 4 * s),
            qrData != null
                ? _vectorQr(qrData, qrSize)
                : pw.Image(qrImage!,
                    width: qrSize, height: qrSize, fit: pw.BoxFit.contain),
            if (!isA5) ...[
              pw.SizedBox(height: 4 * s),
              pw.Text(money(sale.totalAmount),
                  style: pw.TextStyle(
                      fontSize: fs * 0.9,
                      fontWeight: pw.FontWeight.bold,
                      color: ink)),
            ],
          ],
        ),
      );
    }

    final termsText = template['termsText']?.toString().trim() ?? '';
    final leftNotes = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (!isA5 && includeFooter && termsText.isNotEmpty) ...[
          sectionLabel('TERMS & CONDITIONS'),
          pw.SizedBox(height: 3 * s),
          pw.Text(termsText,
              style: pw.TextStyle(fontSize: fs * 0.9, color: muted)),
        ],
      ],
    );

    final footerAlign = template['footerAlignment'] == 'left'
        ? pw.TextAlign.left
        : template['footerAlignment'] == 'right'
            ? pw.TextAlign.right
            : pw.TextAlign.center;

    return [
      pw.Container(width: double.infinity, height: 6 * s, color: accent),
      if (includeHeader) ...[
        pw.SizedBox(height: 12 * s),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logoTile != null) ...[logoTile, pw.SizedBox(width: 12 * s)],
            pw.Expanded(child: identity),
            pw.SizedBox(width: 12 * s),
            titleBlock,
          ],
        ),
        pw.SizedBox(height: 12 * s),
      ] else
        pw.SizedBox(height: 10 * s),
      card(
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(flex: 3, child: billTo),
            if (showPaymentCard) ...[
              pw.SizedBox(width: 12 * s),
              pw.Expanded(flex: 2, child: paymentCard),
            ],
          ],
        ),
      ),
      pw.SizedBox(height: 12 * s),
      pw.Table(
        border: template['showTableBorders'] == true
            ? pw.TableBorder.all(color: line, width: 0.6)
            : null,
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        columnWidths: {
          for (var i = 0; i < configuredColumns.length; i++)
            i: pw.FlexColumnWidth(flexFor(configuredColumns[i])),
        },
        children: tableRows,
      ),
      pw.SizedBox(height: 12 * s),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (qrCard != null) ...[qrCard, pw.SizedBox(width: 12 * s)],
          pw.Expanded(child: leftNotes),
          pw.SizedBox(width: 12 * s),
          totals,
        ],
      ),
      if (isA5 && includeFooter && termsText.isNotEmpty) ...[
        pw.SizedBox(height: 8 * s),
        sectionLabel('TERMS & CONDITIONS'),
        pw.SizedBox(height: 2 * s),
        pw.Text(termsText, style: pw.TextStyle(fontSize: fs * 0.85, color: muted)),
      ],
      if (template['showAmountInWords'] == true) ...[
        pw.SizedBox(height: 10 * s),
        pw.Container(
          width: double.infinity,
          padding:
              pw.EdgeInsets.symmetric(horizontal: 10 * s, vertical: 7 * s),
          decoration: pw.BoxDecoration(
            color: tint,
            borderRadius: pw.BorderRadius.circular(6 * s),
          ),
          child: pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(
                  text: 'AMOUNT IN WORDS   ',
                  style: pw.TextStyle(
                      fontSize: fs * 0.78,
                      fontWeight: pw.FontWeight.bold,
                      color: accent,
                      letterSpacing: 0.9)),
              pw.TextSpan(
                  text: _amountInWords(sale.totalAmount),
                  style: pw.TextStyle(
                      fontSize: fs,
                      fontStyle: pw.FontStyle.italic,
                      color: ink)),
            ]),
          ),
        ),
      ],
      if (includeFooter) ...[
        pw.SizedBox(height: 10 * s),
        pw.Container(
          width: double.infinity,
          padding:
              pw.EdgeInsets.symmetric(horizontal: 10 * s, vertical: 7 * s),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: accent, width: 1.2)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (footerText.isNotEmpty)
                pw.Text(footerText,
                    textAlign: footerAlign,
                    style: pw.TextStyle(
                        fontSize: fs * 1.05,
                        fontWeight: pw.FontWeight.bold,
                        color: ink)),
              pw.SizedBox(height: 2 * s),
              pw.Text('This is a computer-generated invoice.',
                  textAlign: footerAlign,
                  style: pw.TextStyle(fontSize: fs * 0.8, color: muted)),
            ],
          ),
        ),
      ],
    ];
  }

  /// Draws a QR code as vector squares (with the standard 4-module quiet
  /// zone) so it stays perfectly sharp when printed or zoomed.
  static pw.Widget _vectorQr(String data, double size) {
    final modules = PaymentQrService.moduleMatrix(data);
    const quiet = 4;
    final cell = size / (modules.length + quiet * 2);
    return pw.CustomPaint(
      size: PdfPoint(size, size),
      painter: (PdfGraphics canvas, PdfPoint box) {
        canvas
          ..setFillColor(PdfColors.white)
          ..drawRect(0, 0, size, size)
          ..fillPath()
          ..setFillColor(PdfColors.black);
        for (var r = 0; r < modules.length; r++) {
          for (var c = 0; c < modules.length; c++) {
            if (modules[r][c]) {
              canvas.drawRect(
                  (c + quiet) * cell, size - (r + quiet + 1) * cell, cell, cell);
            }
          }
        }
        canvas.fillPath();
      },
    );
  }

  static PdfColor _tint(PdfColor c, double amount) => PdfColor(
        c.red + (1 - c.red) * amount,
        c.green + (1 - c.green) * amount,
        c.blue + (1 - c.blue) * amount,
      );

  static String _invoiceColumnLabel(String id) {
    const labels = {
      'serial': '#',
      'product': 'Description',
      'hsn': 'HSN/SAC',
      'quantity': 'Qty',
      'unit': 'Unit',
      'rate': 'Rate',
      'discount': 'Discount',
      'gst_rate': 'GST %',
      'tax': 'Tax',
      'amount': 'Amount',
    };
    return labels[id] ?? id;
  }

  static Future<pw.ImageProvider?> _loadPaymentQrImage(Sale sale) async {
    try {
      final dynamicQr = await PaymentQrService.generateForSale(sale);
      if (dynamicQr != null) return pw.MemoryImage(dynamicQr);
      final fallback = await PaymentQrService.loadStaticQrFallback();
      if (fallback != null) return pw.MemoryImage(fallback);
    } catch (_) {
      // An invalid or missing payment configuration should not block invoicing.
    }
    return null;
  }

  static PdfColor _invoiceAccentColor(String value) {
    switch (value) {
      case 'green':
        return PdfColor.fromInt(0xFF15803D);
      case 'purple':
        return PdfColor.fromInt(0xFF6D28D9);
      case 'teal':
        return PdfColor.fromInt(0xFF0F766E);
      case 'orange':
        return PdfColor.fromInt(0xFFC2410C);
      case 'pink':
        return PdfColor.fromInt(0xFFBE185D);
      case 'indigo':
        return PdfColor.fromInt(0xFF3730A3);
      case 'black':
        return PdfColor.fromInt(0xFF111827);
      case 'blue':
      default:
        return PdfColor.fromInt(0xFF1E40AF);
    }
  }

  static String _amountInWords(double amount) {
    final paiseTotal = (amount * 100).round();
    final rupees = paiseTotal ~/ 100;
    final paise = paiseTotal % 100;
    final parts = <String>['${_convertToWords(rupees)} Rupees'];
    if (paise > 0) parts.add('${_convertToWords(paise)} Paise');
    return '${parts.join(" and ")} Only';
  }

  static List<pw.Widget> _buildThermalReceipt(
    Sale sale,
    ThermalSize thermalSize,
    pw.ImageProvider? qrImage,
    bool includeHeader,
    bool includeFooter,
  ) {
    final bool is58mm = thermalSize == ThermalSize.mm58;
    final double contentWidth = is58mm ? 156 : 219;
    final double itemWidth = is58mm ? 78 : 106;
    final double qtyWidth = is58mm ? 18 : 22;
    final double rateWidth = is58mm ? 30 : 45;
    final double amountWidth = is58mm ? 30 : 46;
    final double fontSize = is58mm ? 6.5 : 8;
    final subtotal = sale.items.fold(0.0, (sum, item) => sum + item.subtotal);
    final settings = Hive.box<dynamic>('app_settings');
    final businessName =
        settings.get('business_name', defaultValue: 'Business Name').toString();
    final footerText = settings
        .get('invoice_footer_text',
            defaultValue: 'Thank you for your business.')
        .toString()
        .trim();
    final businessAddress =
        settings.get('business_address', defaultValue: '').toString();
    final businessPhone =
        settings.get('business_phone', defaultValue: '').toString();
    final businessGstin =
        settings.get('business_gstin', defaultValue: '').toString();

    return [
      if (includeHeader) ...[
        pw.Text(businessName,
            style: pw.TextStyle(
                fontSize: fontSize + 4, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center),
        if (businessAddress.isNotEmpty)
          pw.Text(businessAddress,
              style: pw.TextStyle(fontSize: fontSize),
              textAlign: pw.TextAlign.center),
        if (businessPhone.isNotEmpty)
          pw.Text(businessPhone,
              style: pw.TextStyle(fontSize: fontSize),
              textAlign: pw.TextAlign.center),
        if (businessGstin.isNotEmpty)
          pw.Text('GSTIN: $businessGstin',
              style: pw.TextStyle(fontSize: fontSize),
              textAlign: pw.TextAlign.center),
        pw.Text('INVOICE',
            style: pw.TextStyle(
                fontSize: fontSize + 1, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center),
        pw.SizedBox(height: 4),
      ],
      _thermalInfoRow('ID:', sale.id, fontSize),
      _thermalInfoRow('Date:',
          DateFormat('dd/MM/yyyy HH:mm').format(sale.date.toLocal()), fontSize),
      if (sale.customerName.isNotEmpty)
        _thermalInfoRow('Customer:',
            _truncateText(sale.customerName, is58mm ? 15 : 32), fontSize),
      if (sale.customerPhone.isNotEmpty)
        _thermalInfoRow('Phone:', sale.customerPhone, fontSize),
      _thermalInfoRow('Payment:', sale.payment.name.toUpperCase(), fontSize),
      _thermalSeparator(contentWidth),
      _thermalTableRow('ITEM', 'PRICE', 'QTY', 'AMT', itemWidth, rateWidth,
          qtyWidth, amountWidth, fontSize,
          bold: true),
      _thermalSeparator(contentWidth),
      ...sale.items.asMap().entries.expand((entry) {
        final itemNumber = entry.key + 1;
        final item = entry.value;
        final product = Hive.box<Product>(Boxes.products).get(item.productId);
        final productName = _truncateText(
            '$itemNumber. ${product?.name ?? 'Unknown Product'}',
            is58mm ? 15 : 24);
        final qty =
            item.qty.toStringAsFixed(product?.unit == UnitType.kg ? 1 : 0);
        final unitLabel = item.unitLabel.isNotEmpty
            ? item.unitLabel
            : (product?.unit.name ?? '');
        return <pw.Widget>[
          _thermalTableRow(
            productName,
            'Rs.${item.sellingPrice.toStringAsFixed(2)}',
            qty,
            'Rs.${item.subtotal.toStringAsFixed(2)}',
            itemWidth,
            rateWidth,
            qtyWidth,
            amountWidth,
            fontSize,          ),
          if (unitLabel.isNotEmpty)
            pw.Text('  Unit: $unitLabel',
                style: pw.TextStyle(fontSize: fontSize - 1)),
        ];
      }),
      _thermalSeparator(contentWidth),
      _thermalTotalRow('Subtotal:', 'Rs.${subtotal.toStringAsFixed(2)}',
          contentWidth, fontSize),
      if (sale.discount > 0)
        _thermalTotalRow('Discount:', '-Rs.${sale.discount.toStringAsFixed(2)}',
            contentWidth, fontSize),
      if (sale.gstEnabled) ...[
        _thermalTotalRow(
            'Taxable value:',
            'Rs.${sale.taxableAmount.toStringAsFixed(2)}',
            contentWidth,
            fontSize),
        if (sale.interstateSale)
          _thermalTotalRow('IGST:', 'Rs.${sale.igstAmount.toStringAsFixed(2)}',
              contentWidth, fontSize)
        else ...[
          _thermalTotalRow('CGST:', 'Rs.${sale.cgstAmount.toStringAsFixed(2)}',
              contentWidth, fontSize),
          _thermalTotalRow('SGST:', 'Rs.${sale.sgstAmount.toStringAsFixed(2)}',
              contentWidth, fontSize),
        ],
      ],
      _thermalSeparator(contentWidth, doubleLine: true),
      _thermalTotalRow('TOTAL:', 'Rs.${sale.totalAmount.toStringAsFixed(2)}',
          contentWidth, fontSize + 3,
          bold: true),
      if (qrImage != null) ...[
        pw.SizedBox(height: 5),
        pw.Text(
          'SCAN & PAY',
          style: pw.TextStyle(
            fontSize: fontSize + 1,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.Center(child: pw.Image(qrImage, width: is58mm ? 80 : 100)),
      ],
      if (includeFooter && footerText.isNotEmpty) ...[
        pw.SizedBox(height: 5),
        pw.Text(footerText.toUpperCase(),
            style: pw.TextStyle(
                fontSize: fontSize + 1, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center),
      ],
    ];
  }

  static pw.Widget _thermalInfoRow(
      String label, String value, double fontSize) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
            width: 56,
            child: pw.Text(label,
                style: pw.TextStyle(
                    fontSize: fontSize, fontWeight: pw.FontWeight.bold))),
        pw.Expanded(
            child: pw.Text(value, style: pw.TextStyle(fontSize: fontSize))),
      ],
    );
  }

  static pw.Widget _thermalTableRow(
    String item,
    String qty,
    String rate,
    String amount,
    double itemWidth,
    double qtyWidth,
    double rateWidth,
    double amountWidth,
    double fontSize, {
    bool bold = false,
  }) {
    final style = pw.TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
            width: itemWidth, child: pw.Text(item, style: style, maxLines: 1)),
        pw.SizedBox(
            width: rateWidth,
            child: pw.Text(rate, style: style, textAlign: pw.TextAlign.right)),
        pw.SizedBox(
            width: qtyWidth,
            child: pw.Text(qty, style: style, textAlign: pw.TextAlign.right)),
        pw.SizedBox(
            width: amountWidth,
            child:
                pw.Text(amount, style: style, textAlign: pw.TextAlign.right)),
      ],
    );
  }

  static pw.Widget _thermalTotalRow(
      String label, String value, double width, double fontSize,
      {bool bold = false}) {
    final style = pw.TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.max,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [pw.Text(label, style: style), pw.Text(value, style: style)],
    );
  }

  static pw.Widget _thermalSeparator(double width, {bool doubleLine = false}) {
    return pw.Container(
      width: width,
      height: doubleLine ? 1.2 : 0.7,
      color: PdfColors.black,
      margin: const pw.EdgeInsets.symmetric(vertical: 1),
    );
  }

  // Header Section optimized for both sizes
  static List<pw.Widget> _buildHeader(
      ThermalSize thermalSize, pw.ImageProvider? logoImage) {
    final bool isWide = thermalSize == ThermalSize.mm80;
    final bool is58mm = thermalSize == ThermalSize.mm58;

    return [
      // Company Logo container with proper aspect ratio
      pw.Container(
        width: double.infinity,
        height: is58mm
            ? 100
            : (isWide ? 140 : 120), // Taller box for better logo display
        padding: pw.EdgeInsets.symmetric(
          horizontal: is58mm ? 4 : 6,
          vertical: is58mm ? 8 : 10,
        ), // Asymmetric padding for better fit
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 2),
          borderRadius: pw.BorderRadius.circular(8),
          color: PdfColors.white,
        ),
        child: pw.Center(
          child: logoImage != null
              ? pw.Container(
                  width: double.infinity,
                  height: double.infinity,
                  child: pw.Image(
                    logoImage,
                    fit: pw.BoxFit
                        .contain, // Changed from fill to contain for better aspect ratio
                    alignment: pw.Alignment.center,
                  ),
                )
              : pw.Container(
                  constraints: pw.BoxConstraints(
                    maxWidth: double.infinity,
                    maxHeight: is58mm ? 40 : (isWide ? 65 : 50),
                  ),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        Hive.box<dynamic>('app_settings')
                            .get('business_name', defaultValue: '')
                            .toString()
                            .trim()
                            .isEmpty
                            ? 'INVOICE'
                            : Hive.box<dynamic>('app_settings')
                                .get('business_name', defaultValue: '')
                                .toString()
                                .trim(),
                        style: pw.TextStyle(
                          fontSize: is58mm ? 16 : (isWide ? 24 : 20),
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                ),
        ),
      ),
      pw.SizedBox(height: is58mm ? 6 : 10),
    ];
  }

  // Invoice Information Section optimized for 58mm
  static List<pw.Widget> _buildInvoiceInfo(Sale sale, ThermalSize thermalSize) {
    final bool isWide = thermalSize == ThermalSize.mm80;
    final bool is58mm = thermalSize == ThermalSize.mm58;

    return [
      // Invoice Title
      pw.Container(
        width: double.infinity,
        padding: pw.EdgeInsets.symmetric(
            vertical: is58mm ? 4 : 6, horizontal: is58mm ? 8 : 12),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey200,
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(
          'INVOICE',
          style: pw.TextStyle(
            fontSize: is58mm ? 10 : (isWide ? 14 : 12),
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ),
      pw.SizedBox(height: is58mm ? 4 : 8),

      // Invoice Details - always use column layout for 58mm
      pw.Container(
        width: double.infinity,
        child: is58mm || !isWide
            ? pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('ID:', sale.id, thermalSize),
                  _buildInfoRow(
                      'Date:',
                      DateFormat('dd/MM/yyyy HH:mm')
                          .format(sale.date.toLocal()),
                      thermalSize),
                  if (sale.customerName.isNotEmpty)
                    _buildInfoRow(
                        'Customer:',
                        _truncateText(sale.customerName, is58mm ? 15 : 20),
                        thermalSize),
                  if (sale.customerPhone.isNotEmpty)
                    _buildInfoRow('Phone:', sale.customerPhone, thermalSize),
                  _buildInfoRow(
                      'Payment:', sale.payment.name.toUpperCase(), thermalSize),
                ],
              )
            : pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildInfoRow('Invoice ID:', sale.id, thermalSize),
                        _buildInfoRow(
                            'Date:',
                            DateFormat('dd/MM/yyyy')
                                .format(sale.date.toLocal()),
                            thermalSize),
                        _buildInfoRow(
                            'Time:',
                            DateFormat('HH:mm:ss').format(sale.date.toLocal()),
                            thermalSize),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (sale.customerName.isNotEmpty)
                          _buildInfoRow(
                              'Customer:', sale.customerName, thermalSize),
                        if (sale.customerPhone.isNotEmpty)
                          _buildInfoRow(
                              'Phone:', sale.customerPhone, thermalSize),
                        _buildInfoRow('Payment:',
                            sale.payment.name.toUpperCase(), thermalSize),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      pw.SizedBox(height: is58mm ? 6 : 10),
    ];
  }

  // Items Section optimized for long item names and 58mm
  static List<pw.Widget> _buildItemsSection(
      Sale sale, ThermalSize thermalSize) {
    final bool isWide = thermalSize == ThermalSize.mm80;
    final bool is58mm = thermalSize == ThermalSize.mm58;
    final double fontSize = is58mm ? 7 : (isWide ? 9 : 8);
    final double headerFontSize = is58mm ? 8 : (isWide ? 10 : 9);

    return [
      // Items Header
      pw.Container(
        width: double.infinity,
        decoration: pw.BoxDecoration(
          color: PdfColors.grey800,
          borderRadius: pw.BorderRadius.circular(2),
        ),
        padding: pw.EdgeInsets.symmetric(
            vertical: is58mm ? 3 : 4, horizontal: is58mm ? 4 : 6),
        child: pw.Row(
          children: [
            pw.Expanded(
              flex: is58mm ? 3 : (isWide ? 6 : 4),
              child: pw.Text(
                'ITEM',
                style: pw.TextStyle(
                  fontSize: headerFontSize,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ),
            pw.Container(
              width: is58mm ? 20 : (isWide ? 30 : 25),
              alignment: pw.Alignment.center,
              child: pw.Text(
                'QTY',
                style: pw.TextStyle(
                  fontSize: headerFontSize,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Container(
              width: is58mm ? 30 : (isWide ? 40 : 35),
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'RATE',
                style: pw.TextStyle(
                  fontSize: headerFontSize,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.Container(
              width: is58mm ? 35 : (isWide ? 45 : 40),
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'AMT',
                style: pw.TextStyle(
                  fontSize: headerFontSize,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
      ),

      // Items List
      pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        ),
        child: pw.Column(
          children: [
            ...sale.items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return _buildItemRow(item, index, thermalSize);
            }),
          ],
        ),
      ),
      pw.SizedBox(height: is58mm ? 4 : 8),
    ];
  }

  // Individual Item Row optimized for 58mm and long names
  static pw.Widget _buildItemRow(
      SaleItem item, int index, ThermalSize thermalSize) {
    final bool isWide = thermalSize == ThermalSize.mm80;
    final bool is58mm = thermalSize == ThermalSize.mm58;
    final product = Hive.box<Product>(Boxes.products).get(item.productId);
    final productName = product?.name ?? 'Unknown Product';
    final qty = item.qty.toStringAsFixed(product?.unit == UnitType.kg ? 1 : 0);
    final unitLabel =
        item.unitLabel.isNotEmpty ? item.unitLabel : (product?.unit.name ?? '');

    // Force 15 character limit per line
    String firstLine = '';
    String secondLine = '';

    if (productName.length <= 15) {
      firstLine = productName;
    } else {
      firstLine = productName.substring(0, 15);
      if (productName.length > 30) {
        secondLine = '${productName.substring(15, 30)}..';
      } else {
        secondLine = productName.substring(15);
      }
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: index % 2 == 0 ? PdfColors.grey100 : PdfColors.white,
        border: const pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.3),
        ),
      ),
      padding: pw.EdgeInsets.symmetric(
          vertical: secondLine.isNotEmpty ? (is58mm ? 4 : 8) : (is58mm ? 3 : 6),
          horizontal: is58mm ? 4 : 6),
      child: is58mm
          ?
          // 58mm: Two-line layout for better readability
          pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Product name line
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        firstLine +
                            (secondLine.isNotEmpty ? '\n$secondLine' : ''),
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        maxLines: 2,
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 1),
                // Quantity, rate, amount line
                pw.Row(
                  children: [
                    if (unitLabel.isNotEmpty) ...[
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                          unitLabel,
                          style: const pw.TextStyle(
                            fontSize: 6,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ),
                    ] else
                      pw.Expanded(flex: 2, child: pw.Container()),
                    pw.Container(
                      width: 20,
                      alignment: pw.Alignment.center,
                      child: pw.Text(
                        qty,
                        style: const pw.TextStyle(fontSize: 7),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                    pw.Container(
                      width: 30,
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        item.sellingPrice.toStringAsFixed(2),
                        style: const pw.TextStyle(fontSize: 7),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                    pw.Container(
                      width: 35,
                      alignment: pw.Alignment.centerRight,
                      child: pw.Text(
                        item.subtotal.toStringAsFixed(2),
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ],
            )
          :
          // 80mm: Single-line layout
          pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: isWide ? 6 : 4,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        firstLine,
                        style: pw.TextStyle(
                          fontSize: isWide ? 9 : 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (secondLine.isNotEmpty)
                        pw.Text(
                          secondLine,
                          style: pw.TextStyle(
                            fontSize: isWide ? 9 : 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      if (unitLabel.isNotEmpty) ...[
                        pw.SizedBox(height: 1),
                        pw.Text(
                          'Unit: $unitLabel',
                          style: pw.TextStyle(
                            fontSize: isWide ? 7 : 6,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Container(
                  width: isWide ? 30 : 25,
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    qty,
                    style: pw.TextStyle(fontSize: isWide ? 9 : 8),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Container(
                  width: isWide ? 40 : 35,
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    'Rs.${item.sellingPrice.toStringAsFixed(2)}',
                    style: pw.TextStyle(fontSize: isWide ? 9 : 8),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.Container(
                  width: isWide ? 45 : 40,
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    'Rs.${item.subtotal.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: isWide ? 9 : 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            ),
    );
  }

  // Totals Section optimized for 58mm
  static List<pw.Widget> _buildTotalsSection(
      Sale sale, ThermalSize thermalSize, bool includeGST) {
    final bool isWide = thermalSize == ThermalSize.mm80;
    final bool is58mm = thermalSize == ThermalSize.mm58;
    final subtotal = sale.items.fold(0.0, (a, b) => a + b.subtotal);
    final gstAmount = includeGST && sale.gstEnabled
        ? sale.cgstAmount + sale.sgstAmount + sale.igstAmount
        : 0.0;

    // Font sizes based on printer width
    final double normalFontSize = is58mm ? 8 : (isWide ? 10 : 9);
    final double totalFontSize = is58mm ? 9 : (isWide ? 12 : 10);

    return [
      pw.Container(
        width: double.infinity,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
          borderRadius: pw.BorderRadius.circular(2),
        ),
        padding: pw.EdgeInsets.all(is58mm ? 4 : 8),
        child: pw.Column(
          children: [
            // Subtotal
            _buildCompactTotalRow(
                'Subtotal:', subtotal.toStringAsFixed(2), normalFontSize),

            if (sale.discount > 0) ...[
              pw.SizedBox(height: is58mm ? 1 : 2),
              _buildCompactTotalRow('Discount:',
                  '-${sale.discount.toStringAsFixed(2)}', normalFontSize,
                  valueColor: PdfColors.red),
            ],

            if (includeGST && sale.gstEnabled) ...[
              pw.SizedBox(height: is58mm ? 1 : 2),
              _buildCompactTotalRow('Taxable value:',
                  sale.taxableAmount.toStringAsFixed(2), normalFontSize),
              if (sale.interstateSale)
                _buildCompactTotalRow(
                    'IGST:', sale.igstAmount.toStringAsFixed(2), normalFontSize)
              else ...[
                _buildCompactTotalRow('CGST:',
                    sale.cgstAmount.toStringAsFixed(2), normalFontSize),
                _buildCompactTotalRow('SGST:',
                    sale.sgstAmount.toStringAsFixed(2), normalFontSize),
              ],
              _buildCompactTotalRow(
                  'Total GST:', gstAmount.toStringAsFixed(2), normalFontSize),
            ],

            pw.SizedBox(height: is58mm ? 2 : 4),
            pw.Container(
              width: double.infinity,
              height: 0.5,
              color: PdfColors.grey600,
            ),
            pw.SizedBox(height: is58mm ? 2 : 4),

            // Total amount - optimized for small width
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  is58mm ? 'TOTAL:' : 'TOTAL AMOUNT:',
                  style: pw.TextStyle(
                    fontSize: totalFontSize,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
                pw.Text(
                  'Rs.${sale.totalAmount.toStringAsFixed(2)}',
                  style: pw.TextStyle(
                    fontSize: totalFontSize,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
              ],
            ),

            // Amount in words - only for wider printers
            if (isWide) ...[
              pw.SizedBox(height: 6),
              pw.Container(
                width: double.infinity,
                child: pw.Text(
                  'Amount in Words: ${_convertToWords(sale.totalAmount.toInt())} Rupees Only',
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontStyle: pw.FontStyle.italic,
                    color: PdfColors.grey700,
                  ),
                  textAlign: pw.TextAlign.center,
                  maxLines: 2,
                ),
              ),
            ],
          ],
        ),
      ),
      pw.SizedBox(height: is58mm ? 6 : 10),
    ];
  }

  // Footer Section optimized for 58mm
  static List<pw.Widget> _buildFooter(ThermalSize thermalSize) {
    final bool isWide = thermalSize == ThermalSize.mm80;
    final bool is58mm = thermalSize == ThermalSize.mm58;

    return [
      // Thank you message
      pw.Container(
        width: double.infinity,
        padding: pw.EdgeInsets.symmetric(vertical: is58mm ? 4 : 6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              is58mm ? 'THANK YOU!' : 'THANK YOU FOR YOUR BUSINESS!',
              style: pw.TextStyle(
                fontSize: is58mm ? 8 : (isWide ? 10 : 9),
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.center,
            ),
            if (isWide) ...[
              pw.SizedBox(height: 4),
              pw.Text(
                'Visit us again for fresh flowers and plants',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColors.grey700,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ],
          ],
        ),
      ),

      pw.SizedBox(height: is58mm ? 4 : 8),

      // Timestamp
      pw.Text(
        'Printed: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now().toLocal())}',
        style: pw.TextStyle(
            fontSize: is58mm ? 5 : (isWide ? 7 : 6), color: PdfColors.grey600),
        textAlign: pw.TextAlign.center,
      ),

      pw.SizedBox(height: is58mm ? 6 : 10),
    ];
  }

  // Helper Methods
  static pw.Widget _buildInfoRow(
      String label, String value, ThermalSize thermalSize) {
    final bool isWide = thermalSize == ThermalSize.mm80;
    final bool is58mm = thermalSize == ThermalSize.mm58;

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: is58mm ? 40 : (isWide ? 70 : 50),
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: is58mm ? 7 : (isWide ? 9 : 8),
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: is58mm ? 7 : (isWide ? 9 : 8),
                color: PdfColors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Compact total row helper
  static pw.Widget _buildCompactTotalRow(
      String label, String value, double fontSize,
      {PdfColor? valueColor}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: fontSize,
            color: PdfColors.grey800,
          ),
        ),
        pw.Text(
          'Rs.$value',
          style: pw.TextStyle(
            fontSize: fontSize,
            color: valueColor ?? PdfColors.black,
            fontWeight: pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  // Text truncation helper
  static String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  // Simple number to words converter (for amounts)
  static String _convertToWords(int amount) {
    if (amount == 0) return 'Zero';
    if (amount < 0) return 'Minus ${_convertToWords(-amount)}';

    final parts = <String>[];
    if (amount >= 10000000) {
      parts.add('${_convertToWords(amount ~/ 10000000)} Crore');
      amount %= 10000000;
    }
    if (amount >= 100000) {
      parts.add('${_convertToWords(amount ~/ 100000)} Lakh');
      amount %= 100000;
    }
    if (amount >= 1000) {
      parts.add('${_convertToWords(amount ~/ 1000)} Thousand');
      amount %= 1000;
    }
    if (amount >= 100) {
      parts.add('${_convertToWords(amount ~/ 100)} Hundred');
      amount %= 100;
    }
    if (amount > 0) parts.add(_convertUnderHundred(amount));
    return parts.join(' ');
  }

  static String _convertUnderHundred(int amount) {
    const ones = [
      '',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine'
    ];
    const teens = [
      'Ten',
      'Eleven',
      'Twelve',
      'Thirteen',
      'Fourteen',
      'Fifteen',
      'Sixteen',
      'Seventeen',
      'Eighteen',
      'Nineteen'
    ];
    const tens = [
      '',
      '',
      'Twenty',
      'Thirty',
      'Forty',
      'Fifty',
      'Sixty',
      'Seventy',
      'Eighty',
      'Ninety'
    ];
    if (amount < 10) return ones[amount];
    if (amount < 20) return teens[amount - 10];
    final ten = tens[amount ~/ 10];
    final one = amount % 10;
    return one == 0 ? ten : '$ten ${ones[one]}';
  }
}

// Enum for thermal printer sizes
enum ThermalSize {
  mm58,
  mm80,
}

// Usage function
Future<void> generateInvoicePdf(Sale sale) async {
  await PdfService.generateInvoice(
    sale,
    thermalSize: ThermalSize.mm80,
    includeHeader: true,
    includeFooter: true,
    includeGST: true,
  );
}