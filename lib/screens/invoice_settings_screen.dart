import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';
import '../services/whatsapp_service.dart';
import '../widgets/whatsapp_icon.dart';
import '../widgets/responsive_page.dart';
import '../widgets/settings_components.dart';
import '../services/thermal_logo_service.dart';

Future<List<Uint8List>> _prepareThermalLogosInBackground(Uint8List bytes) async {
  return [
    ThermalLogoService.for58mm(bytes),
    ThermalLogoService.for80mm(bytes),
  ];
}

class InvoiceSettingsScreen extends StatefulWidget {
  const InvoiceSettingsScreen({super.key});

  @override
  State<InvoiceSettingsScreen> createState() => _InvoiceSettingsScreenState();
}

class _InvoiceSettingsScreenState extends State<InvoiceSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Box<dynamic> _settings;
  late final TextEditingController _appName;
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _gstin;
  late final TextEditingController _invoicePrefix;
  late final TextEditingController _nextInvoiceNumber;
  late final TextEditingController _upiId;
  late final TextEditingController _upiPayeeName;
  late final TextEditingController _upiNotePrefix;
  late String _invoiceAccent;
  late final TextEditingController _invoiceFooter;
  late final TextEditingController _waCountryCode;
  late final TextEditingController _waTemplate;

  Uint8List? _appLogoBytes;
  Uint8List? _invoiceLogoBytes;
  Uint8List? _printLogo58Bytes;
  Uint8List? _printLogo80Bytes;
  Uint8List? _paymentQrBytes;
  bool _clearAppLogo = false;
  bool _clearInvoiceLogo = false;
  bool _clearPaymentQr = false;
  bool _saving = false;
  bool _dirty = false;
  bool _processingInvoiceLogo = false;

  @override
  void initState() {
    super.initState();
    _settings = Hive.box<dynamic>('app_settings');
    _appName = TextEditingController(
        text:
            _settings.get('app_name', defaultValue: 'Billit').toString());
    _name = TextEditingController(
        text: _settings.get('business_name', defaultValue: '').toString());
    _address = TextEditingController(
        text: _settings.get('business_address', defaultValue: '').toString());
    _phone = TextEditingController(
        text: _settings.get('business_phone', defaultValue: '').toString());
    _email = TextEditingController(
        text: _settings.get('business_email', defaultValue: '').toString());
    _gstin = TextEditingController(
        text: _settings.get('business_gstin', defaultValue: '').toString());
    _invoicePrefix = TextEditingController(
        text: _settings.get('invoice_prefix', defaultValue: 'INV').toString());
    _nextInvoiceNumber = TextEditingController(
        text: (_settings.get('next_invoice_number', defaultValue: 1) as num)
            .toInt()
            .toString());
    _upiId = TextEditingController(
        text: _settings.get('upi_id', defaultValue: '').toString());
    _upiPayeeName = TextEditingController(
        text: _settings.get('upi_payee_name', defaultValue: '').toString());
    _upiNotePrefix = TextEditingController(
        text: _settings
            .get('upi_note_prefix', defaultValue: 'Invoice')
            .toString());
    _invoiceAccent =
        _settings.get('invoice_accent', defaultValue: 'blue').toString();
    if (!const ['blue', 'green', 'purple', 'teal', 'orange', 'pink', 'indigo']
        .contains(_invoiceAccent)) {
      _invoiceAccent = 'blue';
    }
    _invoiceFooter = TextEditingController(
        text: _settings
            .get('invoice_footer_text',
                defaultValue: 'Thank you for your business.')
            .toString());
    _waCountryCode = TextEditingController(
        text: _settings.get('whatsapp_country_code', defaultValue: '91').toString());
    final savedWhatsAppTemplate =
        _settings.get('whatsapp_message_template', defaultValue: '').toString();
    _waTemplate = TextEditingController(
        text: savedWhatsAppTemplate.trim().isEmpty
            ? WhatsAppService.defaultTemplate
            : savedWhatsAppTemplate);
    _appLogoBytes = _decodeImage('app_logo_base64');
    _invoiceLogoBytes = _decodeImage('business_logo_base64');
    _printLogo58Bytes = _decodeImage('business_logo_print_58_base64');
    _printLogo80Bytes = _decodeImage('business_logo_print_80_base64');
    _ensurePrintReadyLogos();
    _paymentQrBytes = _decodeImage('payment_qr_base64');
    _appName.addListener(_markDirty);
    _name.addListener(_markDirty);
    _address.addListener(_markDirty);
    _phone.addListener(_markDirty);
    _email.addListener(_markDirty);
    _gstin.addListener(_markDirty);
    _invoicePrefix.addListener(_markDirty);
    _nextInvoiceNumber.addListener(_markDirty);
    _upiId.addListener(_markDirty);
    _upiPayeeName.addListener(_markDirty);
    _upiNotePrefix.addListener(_markDirty);
    _invoiceFooter.addListener(_markDirty);
    _waCountryCode.addListener(_markDirty);
    _waTemplate.addListener(_markDirty);
  }

  Uint8List? _decodeImage(String key) {
    final saved = _settings.get(key) as String?;
    if (saved == null || saved.isEmpty) return null;
    try {
      return base64Decode(saved);
    } catch (_) {
      return null;
    }
  }

  void _markDirty() {
    if (mounted) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _appName.removeListener(_markDirty);
    _name.removeListener(_markDirty);
    _address.removeListener(_markDirty);
    _phone.removeListener(_markDirty);
    _email.removeListener(_markDirty);
    _gstin.removeListener(_markDirty);
    _invoicePrefix.removeListener(_markDirty);
    _nextInvoiceNumber.removeListener(_markDirty);
    _upiId.removeListener(_markDirty);
    _upiPayeeName.removeListener(_markDirty);
    _upiNotePrefix.removeListener(_markDirty);
    _invoiceFooter.removeListener(_markDirty);
    _waCountryCode.removeListener(_markDirty);
    _waTemplate.removeListener(_markDirty);
    _appName.dispose();
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
    _gstin.dispose();
    _invoicePrefix.dispose();
    _nextInvoiceNumber.dispose();
    _upiId.dispose();
    _upiPayeeName.dispose();
    _upiNotePrefix.dispose();
    _invoiceFooter.dispose();
    _waCountryCode.dispose();
    _waTemplate.dispose();
    super.dispose();
  }

  Future<void> _ensurePrintReadyLogos() async {
    final original = _invoiceLogoBytes;
    if (original == null ||
        (_printLogo58Bytes != null && _printLogo80Bytes != null)) {
      return;
    }
    try {
      final converted = await compute(_prepareThermalLogosInBackground, original);
      if (!mounted || !identical(_invoiceLogoBytes, original)) return;
      setState(() {
        _printLogo58Bytes = converted[0];
        _printLogo80Bytes = converted[1];
      });
      await _settings.put('business_logo_print_58_base64', base64Encode(converted[0]));
      await _settings.put('business_logo_print_80_base64', base64Encode(converted[1]));
    } catch (e) {
      debugPrint('Could not prepare existing invoice logo for thermal printing: $e');
    }
  }

  Future<void> _pickImage(String key) async {
    if (key == 'invoice' && _processingInvoiceLogo) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read the selected image. Try another file.')),
        );
        return;
      }

      if (key == 'invoice') {
        final extension = file.extension?.toLowerCase();
        if (!const {'png', 'jpg', 'jpeg', 'webp'}.contains(extension)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Choose a PNG, JPG, JPEG or WebP image.')),
          );
          return;
        }
        if (bytes.lengthInBytes > 20 * 1024 * 1024) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This image is too large. Choose an image smaller than 20 MB.')),
          );
          return;
        }

        setState(() => _processingInvoiceLogo = true);
        try {
          // The image conversion is CPU-intensive. Run it off the UI isolate
          // so selecting a large phone photo does not freeze the app.
          final printLogos = await compute(_prepareThermalLogosInBackground, bytes);
          if (!mounted) return;
          setState(() {
            _dirty = true;
            _invoiceLogoBytes = bytes;
            _printLogo58Bytes = printLogos[0];
            _printLogo80Bytes = printLogos[1];
            _clearInvoiceLogo = false;
          });
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not process invoice logo: $error')),
            );
          }
        } finally {
          if (mounted) setState(() => _processingInvoiceLogo = false);
        }
        return;
      }

      setState(() {
        _dirty = true;
        if (key == 'app') {
          _appLogoBytes = bytes;
          _clearAppLogo = false;
        } else {
          _paymentQrBytes = bytes;
          _clearPaymentQr = false;
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not select image: $error')),
        );
      }
    }
  }

  void _removeImage(String key) {
    setState(() {
      _dirty = true;
      if (key == 'app') {
        _appLogoBytes = null;
        _clearAppLogo = true;
      } else if (key == 'invoice') {
        _invoiceLogoBytes = null;
        _clearInvoiceLogo = true;
      } else {
        _paymentQrBytes = null;
        _clearPaymentQr = true;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final nextInvoiceNumber = int.tryParse(_nextInvoiceNumber.text.trim());
    if (nextInvoiceNumber == null || nextInvoiceNumber < 1) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Next invoice number must be a positive integer.')),
      );
      return;
    }

    await _settings.putAll({
      'app_name': _appName.text.trim(),
      'invoice_accent': _invoiceAccent,
      'invoice_footer_text': _invoiceFooter.text.trim(),
      'whatsapp_country_code': _waCountryCode.text.replaceAll(RegExp(r'\D'), ''),
      'whatsapp_message_template': _waTemplate.text.trim(),
      'upi_id': _upiId.text.trim(),
      'upi_payee_name': _upiPayeeName.text.trim(),
      'upi_note_prefix': _upiNotePrefix.text.trim().isEmpty
          ? 'Invoice'
          : _upiNotePrefix.text.trim(),
      'business_name': _name.text.trim(),
      'business_address': _address.text.trim(),
      'business_phone': _phone.text.trim(),
      'business_email': _email.text.trim(),
      'business_gstin': _gstin.text.trim().toUpperCase(),
      'invoice_prefix': _invoicePrefix.text.trim().isEmpty
          ? 'INV'
          : _invoicePrefix.text.trim().toUpperCase(),
      'next_invoice_number': nextInvoiceNumber,
    });
    await _saveImage('app_logo_base64', _appLogoBytes, _clearAppLogo);
    await _saveImage(
        'business_logo_base64', _invoiceLogoBytes, _clearInvoiceLogo);
    if (_invoiceLogoBytes != null) {
      try {
        _printLogo58Bytes ??= ThermalLogoService.for58mm(_invoiceLogoBytes!);
        _printLogo80Bytes ??= ThermalLogoService.for80mm(_invoiceLogoBytes!);
        await _settings.put(
            'business_logo_print_58_base64', base64Encode(_printLogo58Bytes!));
        await _settings.put(
            'business_logo_print_80_base64', base64Encode(_printLogo80Bytes!));
      } catch (e) {
        if (mounted) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not prepare print logo: $e')),
          );
        }
        return;
      }
    } else if (_clearInvoiceLogo) {
      await _settings.delete('business_logo_print_58_base64');
      await _settings.delete('business_logo_print_80_base64');
      _printLogo58Bytes = null;
      _printLogo80Bytes = null;
    }
    await _saveImage('payment_qr_base64', _paymentQrBytes, _clearPaymentQr);

    if (!mounted) return;
    setState(() { _saving = false; _dirty = false; });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('App, business, UPI and invoice settings saved')),
    );
  }

  Future<void> _saveImage(
      String key, Uint8List? bytes, bool shouldClear) async {
    if (bytes != null) {
      await _settings.put(key, base64Encode(bytes));
    } else if (shouldClear) {
      if (key == 'payment_qr_base64') {
        await _settings.put(key, '');
      } else {
        await _settings.delete(key);
      }
    }
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      );

  Widget _imageSetting({
    required String title,
    required String description,
    required String key,
    required Uint8List? bytes,
    required IconData placeholderIcon,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 84,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: bytes == null
                      ? Icon(placeholderIcon, size: 32)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(bytes,
                              width: 82, height: 70, fit: BoxFit.contain),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(bytes == null
                        ? 'No image selected'
                        : 'Image selected')),
                if (key == 'invoice' && _processingInvoiceLogo)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    tooltip: 'Choose image',
                    onPressed: () => _pickImage(key),
                    icon: const Icon(Icons.upload_file)),
                IconButton(
                    tooltip: 'Remove image',
                    onPressed: bytes == null || (key == 'invoice' && _processingInvoiceLogo) ? null : () => _removeImage(key),
                    icon: const Icon(Icons.delete_outline)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, result) async {
          if (!didPop && _dirty && await confirmDiscardChanges(context) && context.mounted) {
            setState(() => _dirty = false);
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('App & Invoice Settings'),
            bottom: const TabBar(
              isScrollable: false,
              labelPadding: EdgeInsets.zero,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              tabs: [
                Tab(icon: Icon(Icons.store_outlined), text: 'Business'),
                Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Invoice'),
                Tab(icon: Icon(Icons.payments_outlined), text: 'Payments'),
                Tab(icon: Icon(Icons.apps_outlined), text: 'Application'),
              ],
            ),
          ),
          body: ResponsivePage(
            maxWidth: 900,
            child: Form(
              key: _formKey,
              child: TabBarView(
                children: [
                  _settingsTab([
                    SettingsSection(
                      title: 'Business details',
                      subtitle: 'Shown on invoices and receipts.',
                      child: Column(children: [
                        TextFormField(controller: _name, decoration: _decoration('Business / shop name', Icons.store),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter business name' : null),
                        const SizedBox(height: 12),
                        TextFormField(controller: _address, maxLines: 2, decoration: _decoration('Business address', Icons.location_on_outlined)),
                        const SizedBox(height: 12),
                        TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: _decoration('Phone number', Icons.phone_outlined)),
                        const SizedBox(height: 12),
                        TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: _decoration('Email (optional)', Icons.email_outlined),
                          validator: (v) {
                            final value = v?.trim() ?? '';
                            if (value.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) return 'Enter a valid email address';
                            return null;
                          }),
                        const SizedBox(height: 12),
                        TextFormField(controller: _gstin, textCapitalization: TextCapitalization.characters, decoration: _decoration('Business GSTIN (optional)', Icons.verified_outlined)),
                      ]),
                    ),
                  ]),
                  _settingsTab([
                    SettingsSection(
                      title: 'Invoice design',
                      subtitle: 'Invoice branding.',
                      child: Column(children: [
                        DropdownButtonFormField<String>(
                          initialValue: _invoiceAccent,
                          decoration: _decoration('Invoice accent colour', Icons.format_color_fill_outlined),
                          items: const [
                            DropdownMenuItem(value: 'blue', child: Text('Classic Blue')),
                            DropdownMenuItem(value: 'green', child: Text('Classic Green')),
                            DropdownMenuItem(value: 'purple', child: Text('Classic Purple')),
                            DropdownMenuItem(value: 'teal', child: Text('Teal')),
                            DropdownMenuItem(value: 'orange', child: Text('Warm Orange')),
                            DropdownMenuItem(value: 'pink', child: Text('Pink')),
                            DropdownMenuItem(value: 'indigo', child: Text('Indigo')),
                          ],
                          onChanged: (value) { if (value != null) setState(() { _invoiceAccent = value; _dirty = true; }); },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(controller: _invoiceFooter, maxLines: 2, maxLength: 120,
                          decoration: _decoration('Invoice footer message', Icons.notes_outlined)),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    _imageSetting(
                      title: 'Invoice / bill logo',
                      description: 'Used on PDFs and receipts.',
                      key: 'invoice', bytes: _invoiceLogoBytes, placeholderIcon: Icons.receipt_long,
                    ),
                    const SizedBox(height: 12),
                    SettingsSection(
                      title: 'Invoice numbering',
                      child: Column(children: [
                        TextFormField(controller: _invoicePrefix, textCapitalization: TextCapitalization.characters,
                          decoration: _decoration('Invoice number prefix', Icons.tag)),
                        const SizedBox(height: 12),
                        TextFormField(controller: _nextInvoiceNumber, keyboardType: TextInputType.number,
                          decoration: _decoration('Next invoice number', Icons.format_list_numbered),
                          validator: (value) {
                            final number = int.tryParse(value?.trim() ?? '');
                            if (number == null || number < 1) return 'Enter a positive whole number';
                            return null;
                          }),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    _invoicePreview(),
                    const SizedBox(height: 12),
                    _whatsappSection(),
                  ]),
                  _settingsTab([
                    SettingsSection(
                      title: 'Dynamic UPI payment QR',
                      subtitle: 'QR includes the invoice ID and exact total.',
                      child: Column(children: [
                        TextFormField(controller: _upiId,
                          decoration: _decoration('UPI ID / VPA (e.g. shop@bank)', Icons.account_balance_wallet_outlined),
                          validator: (value) {
                            final upi = value?.trim() ?? '';
                            if (upi.isNotEmpty && (!upi.contains('@') || upi.contains(' '))) return 'Enter a valid UPI ID or leave it blank';
                            return null;
                          }),
                        const SizedBox(height: 12),
                        TextFormField(controller: _upiPayeeName, decoration: _decoration('Payee / business name', Icons.storefront_outlined)),
                        const SizedBox(height: 12),
                        TextFormField(controller: _upiNotePrefix, maxLength: 30, decoration: _decoration('Payment note prefix', Icons.notes_outlined)),
                        const SizedBox(height: 8),
                        Text('Generated locally. Verify payment in your UPI app; Billit does not process payments.',
                          style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    _imageSetting(
                      title: 'Static payment QR fallback',
                      description: 'Used only when no UPI ID is set.',
                      key: 'qr', bytes: _paymentQrBytes, placeholderIcon: Icons.qr_code_2,
                    ),
                  ]),
                  _settingsTab([
                    SettingsSection(
                      title: 'Application identity',
                      subtitle: 'App name and logo.',
                      child: Column(children: [
                        TextFormField(controller: _appName, decoration: _decoration('App name', Icons.apps),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter an app name' : null),
                        const SizedBox(height: 8),
                        Text('Launcher name changes require a new build.',
                          style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    _imageSetting(
                      title: 'Application logo',
                      description: 'App logo; separate from the invoice logo.',
                      key: 'app', bytes: _appLogoBytes, placeholderIcon: Icons.apps,
                    ),
                  ]),
                ],
              ),
            ),
          ),
          bottomNavigationBar: SettingsSaveBar(
            dirty: _dirty, saving: _saving, onSave: _save, saveLabel: 'Save settings',
          ),
        ),
      ),
    );
  }

  Widget _settingsTab(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: children,
    );
  }

  Widget _whatsappSection() {
    final scheme = Theme.of(context).colorScheme;
    return SettingsSection(
      title: 'WhatsApp invoice message',
      subtitle: "Opens the customer's chat. Attach the saved PDF manually.",
      trailing: const WhatsAppIcon(size: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _waCountryCode,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: _decoration('Default country code', Icons.public).copyWith(
              helperText: 'Country code for 10-digit numbers.',
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _waTemplate,
            maxLines: 4,
            maxLength: 500,
            decoration: _decoration('WhatsApp message', Icons.chat_outlined).copyWith(
              helperText: 'Tags: {name}, {shop}, {invoice}, {total}, {date}.',
              alignLabelWithHint: true,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _waTemplate.text = WhatsAppService.defaultTemplate,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Restore default'),
            ),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([_waTemplate, _name, _invoicePrefix, _nextInvoiceNumber]),
            builder: (context, _) {
              final preview = WhatsAppService.renderTemplate(
                _waTemplate.text.trim().isEmpty
                    ? WhatsAppService.defaultTemplate
                    : _waTemplate.text,
                name: 'Priya',
                shop: _name.text.trim().isEmpty ? 'Your shop' : _name.text.trim(),
                invoice: '${_invoicePrefix.text.trim().isEmpty ? 'INV' : _invoicePrefix.text.trim().toUpperCase()}-00001',
                total: '₹680.00',
                date: DateFormat('d MMM yyyy').format(DateTime.now()),
              );
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: WhatsAppIcon.brandGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: WhatsAppIcon.brandGreen.withValues(alpha: 0.3)),
                ),
                child: Text(preview, style: TextStyle(color: scheme.onSurface)),
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Attach the saved PDF in WhatsApp.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _invoicePreview() {
    final accent = <String, Color>{
      'blue': Colors.blue, 'green': Colors.green, 'purple': Colors.purple,
      'teal': Colors.teal, 'orange': Colors.orange, 'pink': Colors.pink,
      'indigo': Colors.indigo,
    }[_invoiceAccent] ?? Colors.blue;
    final invoiceNo = '${_invoicePrefix.text.trim().isEmpty ? 'INV' : _invoicePrefix.text.trim().toUpperCase()}-${_nextInvoiceNumber.text.trim().isEmpty ? '1' : _nextInvoiceNumber.text.trim()}';
    return SettingsSection(
      title: 'Live invoice preview',
      subtitle: 'Sample preview.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (_invoiceLogoBytes != null)
              Image.memory(_invoiceLogoBytes!, width: 48, height: 48, fit: BoxFit.contain)
            else
              Icon(Icons.receipt_long_outlined, size: 40, color: accent),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name.text.trim().isEmpty ? 'Your business name' : _name.text.trim(),
                style: TextStyle(fontWeight: FontWeight.w800, color: accent, fontSize: 17)),
              Text(_address.text.trim().isEmpty ? 'Business address' : _address.text.trim(),
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
            ])),
          ]),
          const Divider(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('INVOICE', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            Text(invoiceNo, style: TextStyle(fontWeight: FontWeight.w700, color: accent)),
          ]),
          const SizedBox(height: 14),
          const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Sample item'), Text('₹1,000.00'),
          ]),
          const Divider(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('₹1,000.00', style: TextStyle(fontWeight: FontWeight.w800, color: accent)),
          ]),
          if (_invoiceFooter.text.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Center(child: Text(_invoiceFooter.text.trim(), textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall)),
          ],
        ]),
      ),
    );
  }
}
