import 'dart:convert';

import 'package:billit/models/sale.dart';
import 'package:billit/models/product.dart';
import 'package:billit/services/boxes.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart' as usb;
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'payment_qr_service.dart';
import 'invoice_template_service.dart';
import '../utils/platform_support.dart';

import 'package:permission_handler/permission_handler.dart';

class ThermalPrinterService {
  // Keep raster graphics small enough for thermal-printer dot widths. Large
  // bitmaps can saturate Bluetooth/USB print buffers and cause later receipt
  // content (especially footer messages) to be truncated.
  static img.Image _fitReceiptImage(img.Image source, int maxWidth) {
    if (source.width <= maxWidth) return source;
    return img.copyResize(source, width: maxWidth);
  }

  static String _formatRupees(double value) {
    return 'Rs.${value.truncate()}';
  }

  static List<int> _totalLineBytes(String totalAmount) {
    const lineWidth = 48;
    const totalLabel = 'TOTAL:';
    final enlargedAmountFits =
        totalLabel.length + (totalAmount.length * 2) <= lineWidth;
    final amountWidth =
        enlargedAmountFits ? totalAmount.length * 2 : totalAmount.length;
    final padding =
        (lineWidth - totalLabel.length - amountWidth).clamp(0, lineWidth);

    final bytes = <int>[
      0x1B, 0x45, 0x01, // Bold on.
      0x1D, 0x21, 0x00, // Normal size for TOTAL:.
      ...('$totalLabel${' ' * padding}').codeUnits,
    ];

    if (enlargedAmountFits) {
      bytes.addAll([0x1D, 0x21, 0x11]); // Double width and height.
    }
    bytes.addAll(totalAmount.codeUnits);
    bytes.addAll([
      0x0A,
      0x1D, 0x21, 0x00, // Restore normal size.
      0x1B, 0x45, 0x00, // Bold off.
    ]);
    return bytes;
  }

  Future<List<BluetoothInfo>> getBondedDevices() async {
    try {
      await _requestPermissions();
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      return devices;
    } catch (e) {
      print('Error getting bonded devices: $e');
      return [];
    }
  }

  Future<void> _requestPermissions() async {
    if (!needsRuntimeBluetoothPermissions) return;
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    print("Permission statuses: $statuses");
  }

  Future<void> connect(BluetoothInfo device) async {
    try {
      await PrintBluetoothThermal.connect(macPrinterAddress: device.macAdress);
    } catch (e) {
      print('Connection error: $e');
      rethrow;
    }
  }

  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (e) {
      print('Error disconnecting printer: $e');
    }
  }

  Future<bool> get isConnected async {
    try {
      final result = await PrintBluetoothThermal.connectionStatus;
      return result;
    } catch (e) {
      print('Error checking printer connection: $e');
      return false;
    }
  }

  Future<bool> printInvoice(Sale sale) async {
    try {
      final settings = Hive.box<dynamic>('app_settings');
      final connectionType =
          settings.get('printer_connection_type', defaultValue: 'bluetooth');
      if (connectionType == 'usb') {
        return await _printToUsb(sale);
      }
      return await _attemptPrintToPairedDevice(sale);
    } catch (e) {
      print('Printing error: $e');
      return false;
    }
  }

  Future<bool> _printToUsb(Sale sale) async {
    final settings = Hive.box<dynamic>('app_settings');
    final vendorId = settings.get('usb_printer_vendor_id')?.toString();
    final productId = settings.get('usb_printer_product_id')?.toString();
    if (vendorId == null || productId == null) {
      throw Exception('Select a USB printer in Printer Settings first.');
    }

    final plugin = FlutterThermalPrinter.instance;
    usb.Printer? selectedPrinter;
    final subscription = plugin.devicesStream.listen((devices) {
      for (final device in devices) {
        if (device.connectionType == usb.ConnectionType.USB &&
            device.vendorId == vendorId &&
            device.productId == productId) {
          selectedPrinter = device;
          break;
        }
      }
    });

    try {
      await plugin.getPrinters(connectionTypes: [usb.ConnectionType.USB]);
      // USB discovery is asynchronous; allow Android to enumerate attached
      // devices and deliver its USB permission/device event.
      await Future<void>.delayed(const Duration(seconds: 2));
    } finally {
      await subscription.cancel();
    }

    final printer = selectedPrinter;
    if (printer == null) {
      throw Exception(
          'Saved USB printer was not found. Check the OTG cable and printer power.');
    }

    var connected = false;
    try {
      await plugin.connect(printer);
      connected = true;
      final ticket = await _generateTicketWithLogo(sale);
      await plugin.printData(printer, ticket, longData: true);
      return true;
    } finally {
      if (connected) {
        await plugin.disconnect(printer);
      }
    }
  }

  // Settings box key
  static const String _settingsBoxName = 'settings';
  static const String _printerMacKey = 'printer_mac_address';

  Future<void> savePrinter(String macAddress) async {
    final box = await Hive.openBox(_settingsBoxName);
    await box.put(_printerMacKey, macAddress);
    print('Saved printer MAC: $macAddress');
  }

  Future<String?> getSavedPrinter() async {
    final box = await Hive.openBox(_settingsBoxName);
    return box.get(_printerMacKey);
  }

  Future<bool> _attemptPrintToPairedDevice(Sale sale) async {
    try {
      // Get paired devices
      final devices = await getBondedDevices();

      if (devices.isEmpty) {
        print('No paired thermal printers found');
        return false;
      }

      print('Found ${devices.length} paired devices:');
      for (var d in devices) {
        print('- ${d.name} (${d.macAdress})');
      }

      // Check for saved printer
      final savedMac = await getSavedPrinter();
      print('Saved printer MAC: $savedMac');

      bool connected = await isConnected;

      // 1. Try saved printer first
      if (!connected && savedMac != null) {
        try {
          final savedDevice = devices.firstWhere((d) => d.macAdress == savedMac,
              orElse: () => devices
                  .first // Fallback (shouldn't happen if logic is correct, but safe)
              );

          if (savedDevice.macAdress == savedMac) {
            print(
                'Attempting to connect to SAVED printer: ${savedDevice.name}...');
            await connect(savedDevice);
            connected = await isConnected;
            print('Connection result for saved printer: $connected');
          }
        } catch (e) {
          print('Failed to connect to saved printer: $e');
        }
      }

      // 2. If not connected, try all devices one by one
      if (!connected && devices.isNotEmpty) {
        print('Not connected to saved printer, trying all devices...');
        for (var device in devices) {
          try {
            print(
                'Attempting to connect to: ${device.name} (${device.macAdress})...');
            await connect(device);
            connected = await isConnected;

            if (connected) {
              print('Successfully connected to ${device.name}');
              // Optionally auto-save this if it works? For now, let user choose explicitly.
              break;
            } else {
              print('Failed to connect to ${device.name}, trying next...');
            }
          } catch (e) {
            print('Error connecting to ${device.name}: $e');
          }
        }
      }

      if (!connected) {
        print('Could not establish connection to thermal printer');
        return false;
      }

      // Print using ESC/POS commands with logo
      print('Generating ticket for 80mm printer...');
      List<int> ticket = await _generateTicketWithLogo(sale);
      print('Sending ${ticket.length} bytes to printer...');
      final result = await PrintBluetoothThermal.writeBytes(ticket);
      print("Print result (data sent): $result");
      return result;
    } catch (e) {
      print('Error during printing: $e');
      rethrow;
    }
  }

  Future<List<int>> _generateTicketWithLogo(Sale sale) async {
    List<int> bytes = [];

    final template =
        InvoiceTemplateService.load(InvoiceTemplateService.selected);
    final is58mm = template['paperSize'] == '50mm' || template['paperSize'] == '58mm';
    final profile = await CapabilityProfile.load();
    final generator =
        Generator(is58mm ? PaperSize.mm58 : PaperSize.mm80, profile);

    bytes += generator.reset();

    final settings = Hive.box<dynamic>('app_settings');
    final businessName =
        settings.get('business_name', defaultValue: 'Business Name').toString();
    final businessAddress =
        settings.get('business_address', defaultValue: '').toString();
    final businessPhone =
        settings.get('business_phone', defaultValue: '').toString();
    final businessEmail =
        settings.get('business_email', defaultValue: '').toString();
    final businessGstin =
        settings.get('business_gstin', defaultValue: '').toString();
    final footerText =
        template['footerText']?.toString() ?? 'Thank you for your business.';
    final printLogoKey = is58mm
        ? 'business_logo_print_58_base64'
        : 'business_logo_print_80_base64';
    final logoBase64 = settings.get(printLogoKey) as String? ??
        settings.get('business_logo_base64') as String?;
    img.Image? invoiceLogo;
    if (template['showLogo'] == true &&
        logoBase64 != null &&
        logoBase64.isNotEmpty) {
      try {
        final decodedLogo = img.decodeImage(base64Decode(logoBase64));
        if (decodedLogo != null) {
          // Approx. 45% of the printable head width: a compact brand mark,
          // rather than a full-width banner.
          invoiceLogo = _fitReceiptImage(decodedLogo, is58mm ? 170 : 250);
        }
      } catch (_) {
        invoiceLogo = null;
      }
    }
    final configuredTitle = template['headerTitle']?.toString().trim() ?? '';
    final invoiceHeading = configuredTitle.isEmpty ||
            (configuredTitle == 'INVOICE' && sale.gstEnabled)
        ? (sale.gstEnabled ? 'TAX INVOICE' : 'INVOICE')
        : configuredTitle;
    final headerPosAlignment = template['headerAlignment'] == 'left'
        ? PosAlign.left
        : template['headerAlignment'] == 'right'
            ? PosAlign.right
            : PosAlign.center;
    final footerPosAlignment = template['footerAlignment'] == 'left'
        ? PosAlign.left
        : template['footerAlignment'] == 'right'
            ? PosAlign.right
            : PosAlign.center;

    if (is58mm) {
      if (invoiceLogo != null) bytes += generator.image(invoiceLogo);
      if (template['showBusinessName'] == true) {
        bytes += generator.text(businessName,
            styles: PosStyles(
                align: headerPosAlignment,
                bold: true,
                height: PosTextSize.size2));
      }
      if (template['showAddress'] == true && businessAddress.isNotEmpty) {
        bytes += generator.text(businessAddress,
            styles: PosStyles(align: headerPosAlignment));
      }
      if (template['showPhone'] == true && businessPhone.isNotEmpty) {
        bytes += generator.text(businessPhone,
            styles: PosStyles(align: headerPosAlignment));
      }
      if (template['showEmail'] == true && businessEmail.isNotEmpty) {
        bytes += generator.text(businessEmail,
            styles: PosStyles(align: headerPosAlignment));
      }
      if (template['showBusinessGstin'] == true && businessGstin.isNotEmpty) {
        bytes += generator.text('GSTIN: $businessGstin',
            styles: PosStyles(align: headerPosAlignment));
      }
      bytes += generator.text(invoiceHeading,
          styles: PosStyles(align: headerPosAlignment, bold: true));
      bytes += generator.text('ID: ${sale.id}');
      bytes += generator.text(
          'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(sale.date.toLocal())}');
      if (sale.customerName.isNotEmpty) {
        bytes += generator.text('Customer: ${sale.customerName}');
      }
      if (template['showCustomerGstin'] == true &&
          sale.customerGstin.isNotEmpty) {
        bytes += generator.text('GSTIN: ${sale.customerGstin}');
      }
      if (template['showCustomerPhone'] == true &&
          sale.customerPhone.isNotEmpty) {
        bytes += generator.text('Phone: ${sale.customerPhone}');
      }
      if (template['showPaymentMethod'] == true) {
        bytes += generator.text('Payment: ${sale.payment.name.toUpperCase()}');
      }
      // A compact boxed section heading makes the item block distinct on
      // narrow 50/58mm rolls. Item values remain stacked for legibility.
      bytes += generator.text('+------------------------------+');
      bytes += generator.text('|          ITEMS               |',
          styles: const PosStyles(bold: true));
      bytes += generator.text('+------------------------------+');
      final receiptColumns = (template['columns'] as List).cast<String>();
      const receiptLabels = {
        'serial': '#',
        'product': 'Item',
        'hsn': 'HSN',
        'quantity': 'Qty',
        'unit': 'Unit',
        'rate': 'Rate',
        'discount': 'Discount',
        'gst_rate': 'GST',
        'tax': 'Tax',
        'amount': 'Amount'
      };
      for (var i = 0; i < sale.items.length; i++) {
        final item = sale.items[i];
        final product = Hive.box<Product>(Boxes.products).get(item.productId);
        final rowValues = <String, String>{
          'serial': '${i + 1}',
          'product': product?.name ?? 'Unknown Product',
          'hsn': item.hsnCode.isNotEmpty
              ? item.hsnCode
              : (product?.hsnCode ?? '-'),
          'quantity': item.qty.toString(),
          'unit': item.unitLabel,
          'rate': _formatRupees(item.sellingPrice),
          'discount': '-',
          'gst_rate': sale.gstEnabled
              ? '${(item.gstRate ?? 0).toStringAsFixed(0)}%'
              : '-',
          'tax': sale.gstEnabled
              ? _formatRupees(
                  item.cgstAmount + item.sgstAmount + item.igstAmount)
              : '-',
          'amount': _formatRupees(item.subtotal),
        };
        for (final id in receiptColumns) {
          final label = ((template['columnLabels'] as Map?)?[id]
                      ?.toString()
                      .trim()
                      .isNotEmpty ==
                  true
              ? (template['columnLabels'] as Map)[id].toString()
              : receiptLabels[id] ?? id);
          final value = rowValues[id] ?? '';
          bytes += generator.text(id == 'product' ? value : '$label: $value');
        }
        // Keep product rows visually distinct on narrow receipts even when
        // the optional full table-border setting is disabled.
        bytes += generator.text('--------------------------------');
      }
      if (template['showTableBorders'] == true) {
        bytes += generator.text('--------------------------------');
      }
      final subtotal =
          sale.items.fold<double>(0, (sum, item) => sum + item.subtotal);
      bytes += generator.text('Subtotal: ${_formatRupees(subtotal)}');
      if (sale.discount > 0) {
        bytes += generator.text('Discount: -${_formatRupees(sale.discount)}');
      }
      if (sale.gstEnabled) {
        bytes +=
            generator.text('Taxable: ${_formatRupees(sale.taxableAmount)}');
        if (sale.interstateSale) {
          bytes += generator.text('IGST: ${_formatRupees(sale.igstAmount)}');
        } else {
          bytes += generator.text('CGST: ${_formatRupees(sale.cgstAmount)}');
          bytes += generator.text('SGST: ${_formatRupees(sale.sgstAmount)}');
        }
      }
      bytes += generator.text('================================',
          styles: const PosStyles(bold: true));
      bytes += generator.text('TOTAL: ${_formatRupees(sale.totalAmount)}',
          styles: const PosStyles(bold: true, height: PosTextSize.size2));
      if (template['showQr'] == true) {
        try {
          final qrBytes = await PaymentQrService.generateForSale(sale) ??
              await PaymentQrService.loadStaticQrFallback();
          if (qrBytes != null) {
            final decodedQr = img.decodeImage(qrBytes);
            if (decodedQr != null) {
              // Preserve QR module edges while limiting its physical print size.
              final qr = _fitReceiptImage(decodedQr, 150);
              bytes += generator.text('SCAN & PAY',
                  styles: const PosStyles(align: PosAlign.center, bold: true));
              bytes += generator.image(qr, align: PosAlign.center);
            }
          }
        } catch (e) {
          print('Error generating payment QR: $e');
        }
      }
      final receiptTerms = template['termsText']?.toString().trim() ?? '';
      if (footerText.trim().isNotEmpty || receiptTerms.isNotEmpty) {
        bytes += generator.text('--------------------------------');
      }
      if (footerText.trim().isNotEmpty) {
        bytes += generator.text(footerText.trim(),
            styles: PosStyles(align: footerPosAlignment));
      }
      if (receiptTerms.isNotEmpty) {
        bytes += generator.text(receiptTerms,
            styles: PosStyles(align: footerPosAlignment));
      }
      bytes += generator.feed(3);
      bytes += <int>[0x1D, 0x56, 0x00];
      return bytes;
    }

    // Currency symbol - fallback to Rs. if printer doesn't support ₹
    const String currencySymbol =
        'Rs.'; // Changed to Rs. to avoid encoding errors

    // Render the configured logo before the business name.
    if (invoiceLogo != null) bytes += generator.image(invoiceLogo);
    // Print the configured business name in the receipt header.
    if (template['showBusinessName'] == true) {
      bytes += generator.text(
        businessName,
        styles: PosStyles(
            align: headerPosAlignment,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2),
        linesAfter: 1,
      );
    }

    // Business contact info - centered
    if (template['showAddress'] == true && businessAddress.isNotEmpty) {
      bytes += generator.text(businessAddress,
          styles: PosStyles(align: headerPosAlignment));
    }
    if (template['showPhone'] == true && businessPhone.isNotEmpty) {
      bytes += generator.text('ph: $businessPhone',
          styles: PosStyles(align: headerPosAlignment));
    }
    if (template['showEmail'] == true && businessEmail.isNotEmpty) {
      bytes += generator.text(businessEmail,
          styles: PosStyles(align: headerPosAlignment));
    }
    if (template['showBusinessGstin'] == true && businessGstin.isNotEmpty) {
      bytes += generator.text('GSTIN: $businessGstin',
          styles: PosStyles(align: headerPosAlignment));
    }
    bytes += generator.text(invoiceHeading,
        styles: PosStyles(align: headerPosAlignment, bold: true));
    bytes += generator.text('');

    // Invoice details
    bytes += generator.text('ID: ${sale.id}');
    bytes += generator.text(
        'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(sale.date.toLocal())}');

    if (sale.customerName.isNotEmpty) {
      bytes += generator.text('Customer: ${sale.customerName}');
    }
    if (template['showCustomerGstin'] == true &&
        sale.customerGstin.isNotEmpty) {
      bytes += generator.text('Customer GSTIN: ${sale.customerGstin}');
    }
    if (template['showCustomerPhone'] == true &&
        sale.customerPhone.isNotEmpty) {
      bytes += generator.text('Phone: ${sale.customerPhone}');
    }
    if (template['showPaymentMethod'] == true) {
      bytes += generator.text('Payment: ${sale.payment.name.toUpperCase()}');
    }
    bytes += generator.text('');

    // Build the 80mm table from the selected template columns.
    final configuredColumns = (template['columns'] as List).cast<String>();
    const columnLabels = {
      'serial': '#',
      'product': 'ITEM',
      'hsn': 'HSN',
      'quantity': 'QTY',
      'unit': 'UNIT',
      'rate': 'RATE',
      'discount': 'DISC',
      'gst_rate': 'GST%',
      'tax': 'TAX',
      'amount': 'AMOUNT',
    };
    const preferredWidths = {
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
    final widths = <int>[];
    for (final id in configuredColumns) {
      widths.add(preferredWidths[id] ?? 6);
    }
    final preferredTotal = widths.fold<int>(0, (sum, width) => sum + width);
    if (preferredTotal > 48) {
      for (var i = 0; i < widths.length; i++) {
        widths[i] =
            (widths[i] * 48 / preferredTotal).floor().clamp(3, 48).toInt();
      }
    } else if (widths.isNotEmpty) {
      final productIndex = configuredColumns.indexOf('product');
      widths[productIndex >= 0 ? productIndex : widths.length - 1] +=
          48 - widths.fold<int>(0, (sum, width) => sum + width);
    }
    String fitCell(String value, int width, {bool left = false}) {
      final text = value.length > width ? value.substring(0, width) : value;
      return left ? text.padRight(width) : text.padLeft(width);
    }

    // Always frame the column headings. This is independent of the
    // optional table-borders setting so the receipt has a clear table start.
    final headerBorder =
        '+' + widths.map((width) => '-' * width).join('+') + '+';
    final headerRow = '|' + [
      for (var i = 0; i < configuredColumns.length; i++)
        fitCell(
            ((template['columnLabels'] as Map?)?[configuredColumns[i]]
                        ?.toString()
                        .trim()
                        .isNotEmpty ==
                    true
                ? (template['columnLabels'] as Map)[configuredColumns[i]]
                    .toString()
                : columnLabels[configuredColumns[i]] ?? configuredColumns[i]),
            widths[i],
            left: configuredColumns[i] == 'product'),
    ].join('|') + '|';
    bytes += generator.text(headerBorder);
    bytes += generator.text(headerRow,
        styles: const PosStyles(bold: true));
    bytes += generator.text(headerBorder);

    for (var itemIndex = 0; itemIndex < sale.items.length; itemIndex++) {
      final item = sale.items[itemIndex];
      final product = Hive.box<Product>(Boxes.products).get(item.productId);
      final values = <String, String>{
        'serial': '${itemIndex + 1}',
        'product': product?.name ?? 'Unknown Product',
        'hsn':
            item.hsnCode.isNotEmpty ? item.hsnCode : (product?.hsnCode ?? '-'),
        'quantity': item.qty.toString(),
        'unit': item.unitLabel,
        'rate': _formatRupees(item.sellingPrice),
        'discount': '-',
        'gst_rate': sale.gstEnabled
            ? '${(item.gstRate ?? 0).toStringAsFixed(0)}%'
            : '-',
        'tax': sale.gstEnabled
            ? _formatRupees(item.cgstAmount + item.sgstAmount + item.igstAmount)
            : '-',
        'amount': _formatRupees(item.subtotal),
      };
      bytes += generator.text([
        for (var i = 0; i < configuredColumns.length; i++)
          fitCell(values[configuredColumns[i]] ?? '', widths[i],
              left: configuredColumns[i] == 'product'),
      ].join());
      // Always separate products on 80mm receipts. The table-border
      // preference still controls the table/header rules, not row legibility.
      bytes += generator.text('-' * 48);
    }

    // Totals - better alignment for 80mm paper
    bytes += generator.text('================================================');

    final subtotalValue = sale.items.fold(0.0, (a, b) => a + b.subtotal);
    String subtotalAmount = _formatRupees(subtotalValue);
    // 48 chars total. "Subtotal:" is 9 chars. 48 - 9 = 39.
    String subtotalLine = 'Subtotal:${subtotalAmount.padLeft(39)}';
    bytes += generator.text(subtotalLine);

    if (sale.discount > 0) {
      String discountAmount = '-${_formatRupees(sale.discount)}';
      String discountLine = 'Discount:${discountAmount.padLeft(39)}';
      bytes += generator.text(discountLine);
    }

    if (sale.gstEnabled) {
      bytes += generator.text('Taxable value:'.padRight(24) +
          _formatRupees(sale.taxableAmount).padLeft(24));
      if (sale.interstateSale) {
        bytes += generator.text(
            'IGST:'.padRight(24) + _formatRupees(sale.igstAmount).padLeft(24));
      } else {
        bytes += generator.text(
            'CGST:'.padRight(24) + _formatRupees(sale.cgstAmount).padLeft(24));
        bytes += generator.text(
            'SGST:'.padRight(24) + _formatRupees(sale.sgstAmount).padLeft(24));
      }
    }

    bytes += generator.text('================================================');

    final totalAmount = _formatRupees(sale.totalAmount);
    bytes += _totalLineBytes(totalAmount);
    bytes += generator.text('');

    // Generate a bill-specific UPI QR when a UPI ID is configured;
    // otherwise use the optional static QR fallback.
    if (template['showQr'] == true) {
      try {
        final qrBytes = await PaymentQrService.generateForSale(sale) ??
            await PaymentQrService.loadStaticQrFallback();
        if (qrBytes != null) {
          final img.Image? decodedQr = img.decodeImage(qrBytes);
          if (decodedQr != null) {
            // A compact QR remains easy to scan and leaves room for the footer.
            final qrImage = _fitReceiptImage(decodedQr, 210);
            bytes += generator.text(
              'SCAN & PAY',
              styles: const PosStyles(align: PosAlign.center, bold: true),
            );
            bytes += generator.image(qrImage, align: PosAlign.center);
          }
        }
      } catch (e) {
        print('Error generating/printing payment QR: $e');
      }
    }

    // Footer
    final terms = template['termsText']?.toString().trim() ?? '';
    if (footerText.trim().isNotEmpty || terms.isNotEmpty) {
      bytes += generator.text('-' * 48);
    }
    if (footerText.trim().isNotEmpty) {
      bytes += generator.text(footerText.trim(),
          styles: PosStyles(align: footerPosAlignment));
    }
    if (terms.isNotEmpty) {
      bytes +=
          generator.text(terms, styles: PosStyles(align: footerPosAlignment));
    }
    bytes += generator.text('');

    // Feed the completed receipt before cutting so the final lines are printed.
    bytes += generator.feed(3);
    bytes += <int>[0x1D, 0x56, 0x00]; // GS V 0

    return bytes;
  }
}
