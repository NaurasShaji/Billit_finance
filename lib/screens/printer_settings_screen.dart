import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../services/thermal_printer_service.dart';
import '../widgets/responsive_page.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final ThermalPrinterService _printerService = ThermalPrinterService();
  final FlutterThermalPrinter _usbPlugin = FlutterThermalPrinter.instance;
  StreamSubscription<List<Printer>>? _usbSubscription;

  List<BluetoothInfo> _bluetoothDevices = [];
  List<Printer> _usbDevices = [];
  String _connectionType = 'bluetooth';
  String? _savedMacAddress;
  String? _savedUsbVendorId;
  String? _savedUsbProductId;
  bool _isLoading = true;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _usbSubscription?.cancel();
    _usbPlugin.stopScan();
    super.dispose();
  }

  Future<void> _loadData() async {
    final settings = Hive.box<dynamic>('app_settings');
    _connectionType =
        settings.get('printer_connection_type', defaultValue: 'bluetooth');
    _savedUsbVendorId = settings.get('usb_printer_vendor_id')?.toString();
    _savedUsbProductId = settings.get('usb_printer_product_id')?.toString();
    _savedMacAddress = await _printerService.getSavedPrinter();
    if (_connectionType == 'usb') {
      await _scanUsbDevices();
    } else {
      await _scanBluetoothDevices();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _setConnectionType(String type) async {
    await Hive.box<dynamic>('app_settings')
        .put('printer_connection_type', type);
    if (!mounted) return;
    setState(() {
      _connectionType = type;
      _isLoading = true;
    });
    if (type == 'usb') {
      await _scanUsbDevices();
    } else {
      await _scanBluetoothDevices();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _scanBluetoothDevices() async {
    if (mounted) setState(() => _isScanning = true);
    try {
      final devices = await _printerService.getBondedDevices();
      if (mounted) setState(() => _bluetoothDevices = devices);
    } catch (e) {
      _showMessage('Could not scan Bluetooth printers: $e');
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _scanUsbDevices() async {
    if (mounted) setState(() => _isScanning = true);
    await _usbSubscription?.cancel();
    _usbSubscription = _usbPlugin.devicesStream.listen((devices) {
      if (!mounted) return;
      setState(() {
        _usbDevices = devices
            .where((device) =>
                device.connectionType == ConnectionType.USB &&
                device.vendorId != null &&
                device.productId != null)
            .toList();
      });
    });
    try {
      await _usbPlugin.getPrinters(
        connectionTypes: [ConnectionType.USB],
      );
      await Future<void>.delayed(const Duration(seconds: 2));
    } catch (e) {
      _showMessage('Could not scan USB printers: $e');
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _saveBluetoothPrinter(BluetoothInfo device) async {
    await _printerService.savePrinter(device.macAdress);
    if (!mounted) return;
    setState(() => _savedMacAddress = device.macAdress);
    _showMessage('Default printer set to ${device.name}');
  }

  Future<void> _saveUsbPrinter(Printer device) async {
    if (device.vendorId == null || device.productId == null) {
      _showMessage('This USB device did not provide printer identifiers.');
      return;
    }
    final settings = Hive.box<dynamic>('app_settings');
    await settings.put('usb_printer_vendor_id', device.vendorId);
    await settings.put('usb_printer_product_id', device.productId);
    await settings.put('usb_printer_name', device.name ?? 'USB printer');
    if (!mounted) return;
    setState(() {
      _savedUsbVendorId = device.vendorId;
      _savedUsbProductId = device.productId;
    });
    _showMessage('Default USB printer set to ${device.name ?? 'USB printer'}');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isUsb = _connectionType == 'usb';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Settings'),
        actions: [
          IconButton(
            tooltip: 'Refresh printers',
            onPressed: _isScanning
                ? null
                : (isUsb ? _scanUsbDevices : _scanBluetoothDevices),
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ResponsivePage(
        maxWidth: 900,
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Connection type',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        value: 'bluetooth',
                        groupValue: _connectionType,
                        onChanged: (value) {
                          if (value != null) _setConnectionType(value);
                        },
                        secondary: const Icon(Icons.bluetooth),
                        title: const Text('Bluetooth'),
                        subtitle: const Text(
                            'Connect to a paired Bluetooth printer.'),
                      ),
                      const Divider(height: 1),
                      RadioListTile<String>(
                        value: 'usb',
                        groupValue: _connectionType,
                        onChanged: (value) {
                          if (value != null) _setConnectionType(value);
                        },
                        secondary: const Icon(Icons.usb),
                        title: const Text('Wired USB (OTG)'),
                        subtitle: const Text(
                            'Connect by USB OTG.'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  isUsb ? 'Available USB printers' : 'Paired Bluetooth printers',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (isUsb)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Connect and power on the USB printer before scanning.',
                      ),
                    ),
                  ),
                if (isUsb && _usbDevices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        'No USB printer found. Check OTG, cable and power.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                if (!isUsb && _bluetoothDevices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        'No paired printer. Pair it in Android settings.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                if (isUsb)
                  for (final device in _usbDevices)
                    _usbDeviceTile(device)
                else
                  for (final device in _bluetoothDevices)
                    _bluetoothDeviceTile(device),
              ],
            ),
      ),
    );
  }

  Widget _bluetoothDeviceTile(BluetoothInfo device) {
    final selected = device.macAdress == _savedMacAddress;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.bluetooth),
        title: Text(device.name),
        subtitle: Text(device.macAdress),
        trailing: selected
            ? const Icon(Icons.check_circle, color: Colors.green)
            : TextButton(
                onPressed: () => _saveBluetoothPrinter(device),
                child: const Text('Select'),
              ),
        onTap: () => _saveBluetoothPrinter(device),
      ),
    );
  }

  Widget _usbDeviceTile(Printer device) {
    final selected = device.vendorId == _savedUsbVendorId &&
        device.productId == _savedUsbProductId;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.usb),
        title: Text(device.name ?? 'USB device'),
        subtitle: Text(
          'Vendor ID: ${device.vendorId}  •  Product ID: ${device.productId}',
        ),
        trailing: selected
            ? const Icon(Icons.check_circle, color: Colors.green)
            : TextButton(
                onPressed: () => _saveUsbPrinter(device),
                child: const Text('Select'),
              ),
        onTap: () => _saveUsbPrinter(device),
      ),
    );
  }
}
