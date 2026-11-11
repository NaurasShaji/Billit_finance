import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../models/models.dart';
import './pdf_service.dart';
import './thermal_printer_service.dart';
import './invoice_template_service.dart';

class InvoiceService {
  final ThermalPrinterService _thermalPrinter = ThermalPrinterService();

  // Check if thermal printer is connected
  Future<bool> isThermalPrinterConnected() async {
    try {
      return await _thermalPrinter.isConnected;
    } catch (e) {
      print('Error checking printer connection: $e');
      return false;
    }
  }

  // Get list of available thermal printers
  Future<List<BluetoothInfo>> getAvailablePrinters() async {
    try {
      return await _thermalPrinter.getBondedDevices();
    } catch (e) {
      print('Error getting printers: $e');
      return [];
    }
  }

  // Connect to a thermal printer
  Future<void> connectPrinter(BluetoothInfo device) async {
    await _thermalPrinter.connect(device);
  }

  // Disconnect from thermal printer
  Future<void> disconnectPrinter() async {
    await _thermalPrinter.disconnect();
  }

  // Generate and print/share invoice
  Future<void> generateInvoice(
    Sale sale, {
    bool useThermalPrinter = false,
    bool includeHeader = true,
    bool includeFooter = true,
    bool includeGST = true,
    ThermalSize thermalSize = ThermalSize.mm80,
    bool sharePdf = false,
  }) async {
    if (useThermalPrinter &&
        (InvoiceTemplateService.selected == 'A4' ||
            InvoiceTemplateService.selected == 'A5')) {
      // Full-page formats are exported through the PDF print/share flow.
      await PdfService.generateInvoice(sale, share: sharePdf);
    } else if (useThermalPrinter) {
      // Thermal formats use the selected 58mm or 80mm ESC/POS layout.
      await _thermalPrinter.printInvoice(sale);
    } else {
      // Generate PDF for sharing
      await PdfService.generateInvoice(
        sale,
        thermalSize: thermalSize,
        includeHeader: includeHeader,
        includeFooter: includeFooter,
        includeGST: includeGST,
        share: sharePdf,
      );
    }
  }

  // Generate thermal printer invoice specifically
  Future<bool> printThermalInvoice(Sale sale) async {
    if (InvoiceTemplateService.selected == 'A4' ||
        InvoiceTemplateService.selected == 'A5') {
      await PdfService.generateInvoice(sale);
      return true;
    }
    return _thermalPrinter.printInvoice(sale);
  }

  // Generate PDF invoice specifically
  Future<void> generatePdfInvoice(
    Sale sale, {
    ThermalSize thermalSize = ThermalSize.mm80,
    bool includeHeader = true,
    bool includeFooter = true,
    bool includeGST = true,
    bool share = false,
  }) async {
    await PdfService.generateInvoice(
      sale,
      thermalSize: thermalSize,
      includeHeader: includeHeader,
      includeFooter: includeFooter,
      includeGST: includeGST,
      share: share,
    );
  }
}

// Top-level function for generating invoices (used by UI screens)
Future<void> generateInvoice(Sale sale) async {
  final invoiceService = InvoiceService();
  await invoiceService.generateInvoice(sale);
}
