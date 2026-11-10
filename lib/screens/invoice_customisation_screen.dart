import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import '../services/invoice_template_service.dart';

class InvoiceCustomisationScreen extends StatefulWidget {
  const InvoiceCustomisationScreen({super.key});
  @override
  State<InvoiceCustomisationScreen> createState() =>
      _InvoiceCustomisationScreenState();
}

class _InvoiceCustomisationScreenState
    extends State<InvoiceCustomisationScreen> {
  late String size;
  late Map<String, dynamic> value;
  bool saving = false;
  bool preview = true;
  String? namedSelection;
  @override
  void initState() {
    super.initState();
    size = InvoiceTemplateService.selected;
    value = InvoiceTemplateService.load(size);
  }

  void setValue(String k, dynamic v) => setState(() => value[k] = v);
  void selectSize(String v) {
    setState(() {
      size = v;
      value = InvoiceTemplateService.load(v);
      namedSelection = null;
    });
  }

  List<String> get selected => (value['columns'] as List).cast<String>();
  void toggleColumn(String id, bool enabled) {
    final next = List<String>.from(selected);
    if (enabled && !next.contains(id)) next.add(id);
    if (!enabled) next.remove(id);
    setValue('columns', next);
  }


  Future<String?> _askTemplateName(String title, String initial) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Template name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.pop(dialogContext, name);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> duplicateTemplate() async {
    final current = value['name']?.toString() ?? 'Template';
    final name = await _askTemplateName('Duplicate template', '$current Copy');
    if (name == null || name.isEmpty) return;
    if (InvoiceTemplateService.namedTemplates(size).containsKey(name)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('A template named "$name" already exists.')),
      );
      return;
    }
    await InvoiceTemplateService.saveNamedTemplate(size, name, value);
    if (!mounted) return;
    setState(() {
      value = {...value, 'name': name};
      namedSelection = name;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Template "$name" duplicated')),
    );
  }

  Future<void> renameTemplate() async {
    final current = value['name']?.toString() ?? 'Template';
    final name = await _askTemplateName('Rename template', current);
    if (name == null || name.isEmpty) return;
    final previous = namedSelection;
    final existingNames = InvoiceTemplateService.namedTemplates(size).keys;
    if (previous != name && existingNames.contains(name)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('A template named "$name" already exists.')),
      );
      return;
    }
    if (previous != null && previous != name) {
      await InvoiceTemplateService.deleteNamedTemplate(size, previous);
      await InvoiceTemplateService.saveNamedTemplate(size, name, value);
    }
    setState(() {
      value = {...value, 'name': name};
      namedSelection = previous == null ? null : name;
    });
    await save();
  }

  Future<void> deleteSelectedTemplate() async {
    final name = namedSelection;
    if (name == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete saved template?'),
        content: Text('Delete "$name" from the saved $size templates?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await InvoiceTemplateService.deleteNamedTemplate(size, name);
    if (!mounted) return;
    setState(() => namedSelection = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Template "$name" deleted')),
    );
  }

  Future<void> loadNamedTemplate(String name) async {
    final templates = InvoiceTemplateService.namedTemplates(size);
    final selected = templates[name];
    if (selected == null) return;
    setState(() {
      value = {...InvoiceTemplateService.defaults(size), ...selected};
      namedSelection = name;
    });
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await InvoiceTemplateService.save(size, value);
      if (namedSelection != null) {
        await InvoiceTemplateService.saveNamedTemplate(size, namedSelection!, value);
      }
      await InvoiceTemplateService.select(size);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$size template saved')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> restore() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Restore default?'),
                content: Text(
                    'Replace the customised $size template with its original default?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Restore'))
                ]));
    if (ok == true) {
      await InvoiceTemplateService.restore(size);
      setState(() => value = InvoiceTemplateService.load(size));
    }
  }

  Widget section(String title, List<Widget> children) => Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...children
          ])));
  Widget toggle(String k, String label) => SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value[k] == true,
      onChanged: (v) => setValue(k, v));
  Widget field(String k, String label, {int lines = 1}) => TextFormField(
      key: ValueKey('$size-$k'),
      initialValue: value[k]?.toString() ?? '',
      maxLines: lines,
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()),
      onChanged: (v) => setValue(k, v));
  @override
  Widget build(BuildContext context) {
    final compact = size == '50mm' || size == '58mm' || size == '80mm';
    final warnings = InvoiceTemplateService.validate(value);
    return Scaffold(
        appBar: AppBar(title: const Text('Invoice Customisation'), actions: [
          IconButton(
              onPressed: restore,
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Restore defaults'),
          IconButton(
              onPressed: () => setState(() => preview = !preview),
              icon: const Icon(Icons.preview),
              tooltip: 'Toggle preview')
        ]),
        body: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 900;
          final editor = ListView(padding: const EdgeInsets.all(16), children: [
            section('Paper & template', [
              DropdownButtonFormField<String>(
                  initialValue: size,
                  decoration: const InputDecoration(
                      labelText: 'Default paper size',
                      border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: '50mm', child: Text('50mm POS (384-dot)')),
                    DropdownMenuItem(value: '58mm', child: Text('58mm POS')),
                    DropdownMenuItem(value: '80mm', child: Text('80mm POS')),
                    DropdownMenuItem(value: 'A5', child: Text('A5')),
                    DropdownMenuItem(value: 'A4', child: Text('A4'))
                  ],
                  onChanged: (v) {
                    if (v != null) selectSize(v);
                  }),
              const SizedBox(height: 10),
              field('name', 'Template name'),
              DropdownButtonFormField<String>(
                value: namedSelection,
                decoration: const InputDecoration(
                  labelText: 'Load saved template',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final name in InvoiceTemplateService.namedTemplates(size).keys)
                    DropdownMenuItem(value: name, child: Text(name)),
                ],
                onChanged: (name) {
                  if (name != null) loadNamedTemplate(name);
                },
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: duplicateTemplate,
                    icon: const Icon(Icons.copy),
                    label: const Text('Duplicate'),
                  ),
                  OutlinedButton.icon(
                    onPressed: renameTemplate,
                    icon: const Icon(Icons.drive_file_rename_outline),
                    label: const Text('Rename'),
                  ),
                  if (namedSelection != null)
                    OutlinedButton.icon(
                      onPressed: deleteSelectedTemplate,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete saved'),
                    ),
                ],
              ),
              const Text(
                  'Templates are saved per paper size. Select the printer in Printer Settings.')
            ]),
            section('Header', [
              field('headerTitle', 'Invoice heading'),
              DropdownButtonFormField<String>(
                  initialValue: value['headerAlignment'],
                  decoration: const InputDecoration(
                      labelText: 'Header alignment',
                      border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'left', child: Text('Left')),
                    DropdownMenuItem(value: 'center', child: Text('Centre')),
                    DropdownMenuItem(value: 'right', child: Text('Right'))
                  ],
                  onChanged: (v) {
                    if (v != null) setValue('headerAlignment', v);
                  }),
              toggle('showLogo', 'Show logo'),
              toggle('showBusinessName', 'Show business name'),
              toggle('showAddress', 'Show address'),
              toggle('showPhone', 'Show phone'),
              toggle('showEmail', 'Show email'),
              toggle('showBusinessGstin', 'Show business GSTIN'),
              toggle('showCustomerPhone', 'Show customer phone'),
              toggle('showCustomerGstin', 'Show customer GSTIN')
            ]),
            section('Table columns', [
              const Text(
                  'Select and reorder invoice columns.'),
              for (final col in InvoiceTemplateService.columns)
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(col['id']),
                    title: Text(col['label']!),
                    onChanged: (v) => toggleColumn(col['id']!, v == true)),
              if (selected.length > 1)
                ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: (oldIndex, newIndex) {
                      final next = List<String>.from(selected);
                      if (newIndex > oldIndex) newIndex--;
                      final item = next.removeAt(oldIndex);
                      next.insert(newIndex, item);
                      setValue('columns', next);
                    },
                    children: [
                      for (final id in selected)
                        ListTile(
                            key: ValueKey('order-$id'),
                            dense: true,
                            leading: const Icon(Icons.drag_handle),
                            title: Text(InvoiceTemplateService.columns
                                .firstWhere((e) => e['id'] == id)['label']!))
                    ]),
              if (selected.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Customise column headings',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 10),
              ],
              for (final id in selected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextFormField(
                    key: ValueKey('label-$size-$id'),
                    initialValue:
                        (value['columnLabels'] as Map?)?[id]?.toString() ??
                            InvoiceTemplateService.columns
                                .firstWhere((e) => e['id'] == id)['label']!,
                    decoration: InputDecoration(
                      labelText:
                          '${InvoiceTemplateService.columns.firstWhere((e) => e['id'] == id)['label']!} column label',
                      floatingLabelBehavior: FloatingLabelBehavior.auto,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 20,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final labels = Map<String, dynamic>.from(
                          (value['columnLabels'] as Map?) ?? {});
                      labels[id] = v;
                      setValue('columnLabels', labels);
                    },
                  ),
                ),
              toggle('showTableBorders', 'Show table borders')
            ]),
            section('Footer', [
              field('footerText', 'Footer message', lines: 2),
              field('termsText', 'Terms and conditions', lines: 3),
              toggle('showPaymentMethod', 'Show payment method'),
              toggle('showQr', 'Show UPI QR when available'),
              if (!compact) toggle('showAmountInWords', 'Show amount in words'),
              DropdownButtonFormField<String>(
                  initialValue: value['footerAlignment'],
                  decoration: const InputDecoration(
                      labelText: 'Footer alignment',
                      border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'left', child: Text('Left')),
                    DropdownMenuItem(value: 'center', child: Text('Centre')),
                    DropdownMenuItem(value: 'right', child: Text('Right'))
                  ],
                  onChanged: (v) {
                    if (v != null) setValue('footerAlignment', v);
                  })
            ]),
            section('Typography & spacing', [
              if (!compact) ...[
                Text(
                    'Font size: ${(value['fontSize'] as num).toStringAsFixed(1)} pt'),
                Slider(
                    min: 7,
                    max: 18,
                    divisions: 22,
                    value: ((value['fontSize'] as num).toDouble())
                        .clamp(7.0, 18.0),
                    onChanged: (v) => setValue('fontSize', v)),
                Text(
                    'Page margins: ${(value['marginMm'] as num).toStringAsFixed(1)} mm'),
                Slider(
                    min: 0,
                    max: 25,
                    divisions: 25,
                    value: ((value['marginMm'] as num).toDouble())
                        .clamp(0.0, 25.0),
                    onChanged: (v) => setValue('marginMm', v))
              ] else
                const Text(
                    'Thermal printers use native fonts and margins. PDFs use this layout.'),
              DropdownButtonFormField<String>(
                  initialValue: value['accent'],
                  decoration: const InputDecoration(
                      labelText: 'Accent colour', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'blue', child: Text('Blue')),
                    DropdownMenuItem(value: 'green', child: Text('Green')),
                    DropdownMenuItem(value: 'purple', child: Text('Purple')),
                    DropdownMenuItem(value: 'teal', child: Text('Teal')),
                    DropdownMenuItem(value: 'orange', child: Text('Orange')),
                    DropdownMenuItem(value: 'black', child: Text('Monochrome'))
                  ],
                  onChanged: (v) {
                    if (v != null) setValue('accent', v);
                  })
            ]),
            if (warnings.isNotEmpty)
              section('Layout guidance', [
                for (final w in warnings)
                  ListTile(
                      dense: true,
                      leading:
                          const Icon(Icons.warning_amber, color: Colors.orange),
                      title: Text(w))
              ]),
            FilledButton.icon(
                onPressed: saving || selected.isEmpty ? null : save,
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: const Text('Save template')),
            const SizedBox(height: 24)
          ]);
          final view =
              TemplatePreview(size: size, value: value, warnings: warnings);
          if (wide) {
            return Row(children: [
              Expanded(flex: 5, child: editor),
              if (preview) const VerticalDivider(width: 1),
              if (preview)
                Expanded(
                    flex: 4,
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20), child: view))
            ]);
          }
          return Column(children: [
            if (preview)
              Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16), child: view)),
            if (preview) const Divider(),
            Expanded(flex: 5, child: editor)
          ]);
        }));
  }
}

class TemplatePreview extends StatelessWidget {
  final String size;
  final Map<String, dynamic> value;
  final List<String> warnings;

  const TemplatePreview({
    super.key,
    required this.size,
    required this.value,
    required this.warnings,
  });

  String _label(String id) {
    final custom = (value['columnLabels'] as Map?)?[id]?.toString().trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return InvoiceTemplateService.columns
        .firstWhere((column) => column['id'] == id,
            orElse: () => {'label': id})['label']!;
  }

  String _sampleCell(String id, int row) {
    const products = ['Basmati Rice 5kg', 'Sunflower Oil 1L', 'Wheat Flour 2kg'];
    const rates = ['₹450.00', '₹180.00', '₹65.00'];
    const amounts = ['₹900.00', '₹180.00', '₹195.00'];
    switch (id) {
      case 'serial':
        return '${row + 1}';
      case 'product':
        return products[row];
      case 'hsn':
        return ['1006', '1512', '1101'][row];
      case 'quantity':
        return ['2', '1', '3'][row];
      case 'unit':
        return ['kg', 'L', 'kg'][row];
      case 'rate':
        return rates[row];
      case 'discount':
        return '—';
      case 'gst_rate':
        return '5%';
      case 'tax':
        return ['₹45.00', '₹9.00', '₹9.75'][row];
      case 'amount':
        return amounts[row];
      default:
        return '';
    }
  }

  Widget _thermalPreview(BuildContext context, double width) {
    final columns = (value['columns'] as List).cast<String>();
    final visibleColumns =
        columns.isEmpty ? <String>['product', 'amount'] : columns;
    final compact = size == '50mm' || size == '58mm';
    final headerAlign = value['headerAlignment'] == 'left'
        ? TextAlign.left
        : value['headerAlignment'] == 'right'
            ? TextAlign.right
            : TextAlign.center;
    final footerAlign = value['footerAlignment'] == 'left'
        ? TextAlign.left
        : value['footerAlignment'] == 'right'
            ? TextAlign.right
            : TextAlign.center;
    final borderColor = Colors.black87;
    final thermalText = TextStyle(
      fontFamily: 'monospace',
      fontSize: compact ? 8 : 9,
      height: 1.15,
      color: Colors.black,
    );
    Widget rule() => Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: borderColor,
        );
    int flexFor(String id) => id == 'product'
        ? (compact ? 4 : 5)
        : id == 'amount'
            ? 2
            : 1;
    Widget tableLine(int row, {bool heading = false}) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final id in visibleColumns)
              Expanded(
                flex: flexFor(id),
                child: Text(
                  heading ? _label(id) : _sampleCell(id, row),
                  maxLines: heading ? 2 : 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: id == 'product' ? TextAlign.left : TextAlign.right,
                  style: thermalText.copyWith(
                    fontWeight:
                        heading ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
          ],
        );

    return Center(
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade400),
          boxShadow: const [
            BoxShadow(color: Color(0x18000000), blurRadius: 8)
          ],
        ),
        child: DefaultTextStyle(
          style: thermalText,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value['showLogo'] == true) _thermalLogoPreview(),
              if (value['showBusinessName'] == true)
                Text('Your Business Name',
                    textAlign: headerAlign,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black)),
              if (value['showAddress'] == true)
                Text('Your business address',
                    textAlign: headerAlign,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 8,
                        color: Colors.black)),
              if (value['showPhone'] == true)
                Text('Phone: Your phone number',
                    textAlign: headerAlign,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 8,
                        color: Colors.black)),
              if (value['showEmail'] == true)
                Text('Email: Your business email',
                    textAlign: headerAlign,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 8, color: Colors.black)),
              if (value['showBusinessGstin'] == true)
                Text('GSTIN: Your GSTIN',
                    textAlign: headerAlign,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 8,
                        color: Colors.black)),
              rule(),
              Text(value['headerTitle']?.toString() ?? 'INVOICE',
                  textAlign: headerAlign,
                  style: thermalText.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Invoice: INV-2026-0042\nDate: 01/11/2026  10:42 AM\nCustomer: Arun Kumar',
                  style: thermalText,
                ),
              ),
              if (value['showCustomerPhone'] == true)
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Phone: +91 98470 12345',
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9,
                            color: Colors.black))),
              if (value['showCustomerGstin'] == true)
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Customer GSTIN: 32AAAPA1234A1Z5',
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9,
                            color: Colors.black))),
              if (value['showPaymentMethod'] == true)
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Payment: UPI',
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9,
                            color: Colors.black))),
              rule(),
              tableLine(0, heading: true),
              rule(),
              for (var row = 0; row < 3; row++) ...[
                tableLine(row),
                if (row != 2) const SizedBox(height: 3),
              ],
              rule(),
              _thermalTotal('Subtotal', '₹1,275.00'),
              _thermalTotal('Discount', '₹0.00'),
              _thermalTotal('Taxable value', '₹1,275.00'),
              _thermalTotal('CGST', '₹31.88'),
              _thermalTotal('SGST', '₹31.87'),
              rule(),
              _thermalTotal('GRAND TOTAL', '₹1,338.75', bold: true),
              if (value['showQr'] == true) ...[
                const SizedBox(height: 7),
                const Icon(Icons.qr_code_2, size: 44, color: Colors.black),
                const Text('SCAN & PAY',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.black)),
              ],
              if ((value['footerText']?.toString().isNotEmpty ?? false))
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(value['footerText'].toString(),
                      textAlign: footerAlign,
                      style: thermalText.copyWith(
                          fontWeight: FontWeight.bold)),
                ),
              if ((value['termsText']?.toString().isNotEmpty ?? false))
                Text(value['termsText'].toString(),
                    textAlign: footerAlign, style: thermalText),
              const SizedBox(height: 5),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thermalLogoPreview() {
    try {
      final settings = Hive.box<dynamic>('app_settings');
      final key = size == '80mm'
          ? 'business_logo_print_80_base64'
          : 'business_logo_print_58_base64';
      final encoded = settings.get(key)?.toString() ??
          settings.get('business_logo_base64')?.toString() ??
          '';
      if (encoded.isEmpty) {
        return const Padding(
          padding: EdgeInsets.only(bottom: 5),
          child: Icon(Icons.storefront, size: 34, color: Colors.black),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Center(
          child: Image.memory(
            base64Decode(encoded),
            width: size == '80mm' ? 150 : 100,
            height: 54,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.storefront, size: 34, color: Colors.black),
          ),
        ),
      );
    } catch (_) {
      return const Icon(Icons.storefront, size: 34, color: Colors.black);
    }
  }

  Widget _thermalTotal(String label, String amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    color: Colors.black,
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ),
          Text(amount,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9,
                  color: Colors.black,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  Widget _pagePreview(BuildContext context, double width) {
    final columns = (value['columns'] as List).cast<String>();
    final visibleColumns = columns.isEmpty
        ? <String>['serial', 'product', 'quantity', 'rate', 'amount']
        : columns;
    final alignment = value['headerAlignment'] == 'right'
        ? CrossAxisAlignment.end
        : value['headerAlignment'] == 'center'
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start;
    final footerAlign = value['footerAlignment'] == 'left'
        ? TextAlign.left
        : value['footerAlignment'] == 'right'
            ? TextAlign.right
            : TextAlign.center;
    final border = value['showTableBorders'] == true
        ? TableBorder.all(color: Colors.grey.shade300, width: 0.7)
        : TableBorder(
            horizontalInside:
                BorderSide(color: Colors.grey.shade200, width: 0.5));
    final tableRows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(color: Color(0xFFE9EEF5)),
        children: [
          for (final id in visibleColumns)
            Padding(
              padding: const EdgeInsets.all(5),
              child: Text(_label(id),
                  style: const TextStyle(
                      fontSize: 8, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      for (var row = 0; row < 3; row++)
        TableRow(
          children: [
            for (final id in visibleColumns)
              Padding(
                padding: const EdgeInsets.all(5),
                child: Text(_sampleCell(id, row),
                    style: const TextStyle(fontSize: 8)),
              ),
          ],
        ),
    ];

    return Center(
      child: Container(
        width: width,
        padding: EdgeInsets.all((value['marginMm'] as num).toDouble() + 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade400),
          boxShadow: const [
            BoxShadow(color: Color(0x18000000), blurRadius: 8)
          ],
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.black, fontSize: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: alignment,
                      children: [
                        if (value['showLogo'] == true)
                          const Icon(Icons.storefront, size: 32),
                        if (value['showBusinessName'] == true)
                          const Text('Your Business Name',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                        if (value['showAddress'] == true)
                          const Text('Your business address'),
                        if (value['showPhone'] == true)
                          const Text('Phone: Your phone number'),
                        if (value['showEmail'] == true)
                          const Text('Email: Your business email'),
                        if (value['showBusinessGstin'] == true)
                          const Text('GSTIN: Your GSTIN',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border.all(color: Colors.blueGrey),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(value['headerTitle']?.toString() ?? 'INVOICE',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        const Text('Invoice: INV-2026-0042'),
                        const Text('Date: 01 Nov 2026, 10:42 AM'),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 22, color: Colors.black54),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('BILL TO',
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.black54)),
                    const SizedBox(height: 3),
                    const Text('Arun Kumar',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                    if (value['showCustomerPhone'] == true)
                      const Text('Phone: +91 98470 12345'),
                    if (value['showCustomerGstin'] == true)
                      const Text('Customer GSTIN: 32AAAPA1234A1Z5'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Table(border: border, children: tableRows),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (value['showPaymentMethod'] == true)
                          const Text('Payment method: UPI'),
                        const SizedBox(height: 10),
                        if (value['footerText'].toString().isNotEmpty)
                          Text(value['footerText'].toString(),
                              textAlign: footerAlign,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        if (value['termsText'].toString().isNotEmpty)
                          Text(value['termsText'].toString(),
                              textAlign: footerAlign),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 145,
                    child: Column(
                      children: [
                        _pageTotal('Subtotal', '₹1,275.00'),
                        _pageTotal('Discount', '₹0.00'),
                        _pageTotal('Taxable value', '₹1,275.00'),
                        _pageTotal('CGST', '₹31.88'),
                        _pageTotal('SGST', '₹31.87'),
                        const Divider(color: Colors.black54),
                        _pageTotal('GRAND TOTAL', '₹1,338.75', bold: true),
                      ],
                    ),
                  ),
                ],
              ),
              if (value['showQr'] == true)
                const Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Icon(Icons.qr_code_2, size: 52),
                  ),
                ),
              if (value['showAmountInWords'] == true)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300)),
                  child: const Text(
                    'Amount in words: One Thousand Three Hundred Thirty Eight Rupees and Seventy Five Paise Only',
                    style: TextStyle(fontSize: 8, fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageTotal(String label, String amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 8,
                      fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
          const SizedBox(width: 5),
          Text(amount,
              style: TextStyle(
                  fontSize: 8,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = size == '50mm' || size == '58mm' || size == '80mm';
    final width = (size == '50mm' || size == '58mm')
        ? 205.0
        : size == '80mm'
            ? 300.0
            : size == 'A5'
                ? 360.0
                : 440.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Live preview - $size',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        compact
            ? _thermalPreview(context, width)
            : _pagePreview(context, width),
        for (final warning in warnings)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Warning: $warning',
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}
