import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../services/invoice_service.dart';

class PrinterSelectionDialog extends StatefulWidget {
  const PrinterSelectionDialog({super.key});

  @override
  State<PrinterSelectionDialog> createState() => _PrinterSelectionDialogState();
}

class _PrinterSelectionDialogState extends State<PrinterSelectionDialog> {
  final InvoiceService _invoiceService = InvoiceService();
  List<BluetoothInfo> _devices = [];
  BluetoothInfo? _selectedDevice;
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      setState(() {
        _isLoading = true;
        _error = '';
      });

      final devices = await _invoiceService.getAvailablePrinters();

      setState(() {
        _devices = devices;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading printers: \$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _connectPrinter(BluetoothInfo device) async {
    try {
      setState(() {
        _error = '';
        _isLoading = true;
      });

      await _invoiceService.connectPrinter(device);

      setState(() {
        _selectedDevice = device;
        _isLoading = false;
      });

      if (mounted) {
        Navigator.of(context).pop(true); // Return success
      }
    } catch (e) {
      setState(() {
        _error = 'Error connecting to printer: \$e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Printer'),
      content: SizedBox(
        width: double.maxFinite,
        child: _buildContent(),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(false); // Return failure
          },
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isLoading ? null : _loadDevices,
          child: const Text('Refresh'),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error.isNotEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error,
            style: const TextStyle(color: Colors.red),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadDevices,
            child: const Text('Retry'),
          ),
        ],
      );
    }

    if (_devices.isEmpty) {
      return const Center(
        child: Text(
          'No printers found.\nMake sure your printer is paired with this device.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        final isSelected = _selectedDevice?.macAdress == device.macAdress;

        return ListTile(
          title: Text(device.name),
          subtitle: Text(device.macAdress),
          leading: Icon(
            Icons.print,
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
          ),
          selected: isSelected,
          onTap: () => _connectPrinter(device),
        );
      },
    );
  }
}
