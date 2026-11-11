import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import '../services/invoice_template_service.dart';
import '../services/pdf_service.dart';
import '../services/boxes.dart';
import '../models/models.dart';
import 'package:printing/printing.dart';

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
                  value: size,
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
                  value: value['headerAlignment'],
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
                  value: value['footerAlignment'],
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
                  value: value['accent'],
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

  Sale _previewSale() {
    final products = Hive.isBoxOpen(Boxes.products)
        ? Hive.box<Product>(Boxes.products).values
            .where((product) => product.active)
            .take(3)
            .toList()
        : <Product>[];
    const quantities = [2.0, 1.0, 3.0];
    const fallbackPrices = [450.0, 180.0, 65.0];
    final items = <SaleItem>[];

    for (var i = 0; i < 3; i++) {
      final product = products.isEmpty ? null : products[i % products.length];
      final quantity = quantities[i];
      final rate = product?.sellingPrice ?? fallbackPrices[i];
      final subtotal = rate * quantity;
      final gstRate = product?.gstRate ?? 5.0;
      final tax = subtotal * gstRate / 100;
      items.add(SaleItem()
        ..productId = product?.id ?? '__billit_preview_$i'
        ..qty = quantity
        ..sellingPrice = rate
        ..costPrice = product?.costPrice ?? 0
        ..subtotal = subtotal
        ..unitLabel = product?.unit.name ?? 'pcs'
        ..hsnCode = product?.hsnCode ?? ''
        ..gstRate = gstRate
        ..taxableAmount = subtotal
        ..cgstAmount = tax / 2
        ..sgstAmount = tax / 2
        ..igstAmount = 0);
    }

    final subtotal = items.fold<double>(0, (sum, item) => sum + item.subtotal);
    final tax = items.fold<double>(
        0, (sum, item) => sum + item.cgstAmount + item.sgstAmount);
    return Sale()
      ..id = 'PREVIEW-0001'
      ..date = DateTime.now()
      ..items = items
      ..totalAmount = subtotal + tax
      ..totalCost = items.fold<double>(
          0, (sum, item) => sum + item.costPrice * item.qty)
      ..profit = subtotal -
          items.fold<double>(
              0, (sum, item) => sum + item.costPrice * item.qty)
      ..payment = PaymentMethod.upi
      ..customerName = 'Sample Customer'
      ..customerPhone = '9876543210'
      ..customerGstin = '32AAAPA1234A1Z5'
      ..discount = 0
      ..gstEnabled = true
      ..gstRate = 5
      ..taxableAmount = subtotal
      ..cgstAmount = tax / 2
      ..sgstAmount = tax / 2
      ..igstAmount = 0
      ..interstateSale = false
      ..gstInclusive = false;
  }

  @override
  Widget build(BuildContext context) {
    final pageWidth = size == 'A5' ? 420.0 : 595.0;
    final thermalWidth = size == '50mm' || size == '58mm' ? 164.0 : 227.0;
    final previewWidth =
        size == 'A4' || size == 'A5' ? pageWidth : thermalWidth;
    final previewKey = ValueKey('$size-${jsonEncode(value)}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Live preview - $size',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SizedBox(
          height: 620,
          child: PdfPreview(
            key: previewKey,
            build: (format) async {
              final result = await PdfService.buildInvoicePdf(
                _previewSale(),
                templateOverride: Map<String, dynamic>.from(value),
              );
              return result.bytes;
            },
            canChangePageFormat: false,
            canChangeOrientation: false,
            allowPrinting: false,
            allowSharing: false,
            maxPageWidth: previewWidth,
          ),
        ),
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
