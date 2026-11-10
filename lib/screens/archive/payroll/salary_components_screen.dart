import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/hr_payroll_service.dart';
import '../../../services/hr_service.dart';

class SalaryComponentsScreen extends StatelessWidget {
  const SalaryComponentsScreen({super.key, required this.employee});

  final Employee employee;

  int? _parsePaise(String raw) {
    final value = raw.trim();
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null) return null;
    final fraction = parts.length == 1
        ? 0
        : int.parse(parts[1].padRight(2, '0'));
    return whole * 100 + fraction;
  }

  Future<void> _add(BuildContext context) async {
    final name = TextEditingController();
    final amount = TextEditingController();
    String type = 'earning';
    DateTime effectiveFrom = DateTime.now();
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add salary component'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Component name'),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Enter a name'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(value: 'earning', child: Text('Allowance / earning')),
                      DropdownMenuItem(value: 'deduction', child: Text('Deduction')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => type = value ?? type),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount per payroll run',
                      prefixText: '₹ ',
                    ),
                    validator: (value) {
                      final paise = _parsePaise(value ?? '');
                      return paise == null || paise <= 0
                          ? 'Enter a positive amount'
                          : null;
                    },
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: effectiveFrom,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(
                          const Duration(days: 365 * 5),
                        ),
                      );
                      if (picked != null) {
                        setDialogState(() => effectiveFrom = picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      'Effective from ${DateFormat('dd MMM yyyy').format(effectiveFrom)}',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Save component'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      try {
        await HrPayrollService().addSalaryComponent(
          employeeId: employee.id,
          name: name.text,
          componentType: type,
          amountPaise: _parsePaise(amount.text)!,
          effectiveFrom: effectiveFrom,
        );
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save component: $error')),
          );
        }
      }
    }
    name.dispose();
    amount.dispose();
  }

  Future<void> _changeBasePay(BuildContext context) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    DateTime effectiveDate = DateTime.now().add(const Duration(days: 1));
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Schedule base-pay change'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'New base pay', prefixText: '₹ '),
                  validator: (value) {
                    final paise = _parsePaise(value ?? '');
                    return paise == null || paise <= 0 ? 'Enter a positive amount' : null;
                  },
                ),
                const SizedBox(height: 10),
                TextField(controller: note, decoration: const InputDecoration(labelText: 'Reason / note')),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: effectiveDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (picked != null) setDialogState(() => effectiveDate = picked);
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text('Effective ${DateFormat('dd MMM yyyy').format(effectiveDate)}'),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true);
            }, child: const Text('Schedule change')),
          ],
        ),
      ),
    );
    if (saved == true) {
      try {
        await HrPayrollService().addBasePayChange(
          employeeId: employee.id,
          basePaise: _parsePaise(amount.text)!,
          effectiveDate: effectiveDate,
          note: note.text,
        );
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Base-pay change scheduled.')),
        );
      } catch (error) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not schedule base-pay change: $error')),
        );
      }
    }
    amount.dispose();
    note.dispose();
  }

  Future<void> _saveAsStructure(BuildContext context, List<SalaryComponent> components) async {
    final name = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save reusable salary structure'),
        content: TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Structure name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, name.text.trim().isNotEmpty), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      try {
        await HrService().saveSalaryStructure(
          name: name.text,
          components: components.where((item) => item.active).map((item) => {
            'name': item.name,
            'componentType': item.componentType,
            'amountPaise': item.amountPaise,
          }).toList(),
        );
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Salary structure saved for reuse.')),
        );
      } catch (error) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save salary structure: $error')),
        );
      }
    }
    name.dispose();
  }

  Future<void> _applyStructure(BuildContext context) async {
    final structures = HrService().salaryStructures();
    if (structures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No reusable salary structures saved yet.')),
      );
      return;
    }
    String? selected = structures.keys.first;
    DateTime effectiveDate = DateTime.now().add(const Duration(days: 1));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Apply salary structure'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: selected,
              decoration: const InputDecoration(labelText: 'Structure'),
              items: structures.entries.map((entry) => DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value['name'] as String),
              )).toList(),
              onChanged: (value) => setDialogState(() => selected = value),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: effectiveDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (picked != null) setDialogState(() => effectiveDate = picked);
              },
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text('Effective ${DateFormat('dd MMM yyyy').format(effectiveDate)}'),
            ),
            const SizedBox(height: 8),
            const Text('This adds a dated copy of the structure components to this employee. Existing components are not overwritten.'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, selected != null), child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (confirmed == true && selected != null) {
      try {
        await HrService().applySalaryStructure(
          employeeId: employee.id,
          structureId: selected!,
          effectiveFrom: effectiveDate,
        );
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Salary structure applied.')),
        );
      } catch (error) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not apply salary structure: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency(locale: 'en_IN');
    return Scaffold(
      appBar: AppBar(
        title: Text('Salary structure · ${employee.name}'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Salary tools',
            onSelected: (value) {
              if (value == 'base_pay') _changeBasePay(context);
              if (value == 'save_structure') {
                final items = Hive.box<SalaryComponent>(Boxes.salaryComponents).values
                    .where((item) => item.employeeId == employee.id && item.active).toList();
                _saveAsStructure(context, items);
              }
              if (value == 'apply_structure') _applyStructure(context);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'base_pay', child: Text('Schedule base-pay change')),
              PopupMenuItem(value: 'save_structure', child: Text('Save components as structure')),
              PopupMenuItem(value: 'apply_structure', child: Text('Apply saved structure')),
            ],
          ),
          IconButton(
            onPressed: () => _add(context),
            tooltip: 'Add component',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<SalaryComponent>>(
        valueListenable:
            Hive.box<SalaryComponent>(Boxes.salaryComponents).listenable(),
        builder: (context, box, _) {
          final components = box.values
              .where((component) => component.employeeId == employee.id)
              .toList()
            ..sort((a, b) => b.effectiveFrom.compareTo(a.effectiveFrom));
          if (components.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No allowances or deductions configured.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _add(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add component'),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: components.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final component = components[index];
              return Card(
                child: ListTile(
                  title: Text(component.name),
                  subtitle: Text(
                    '${component.componentType.toUpperCase()} · '
                    'Effective ${DateFormat('dd MMM yyyy').format(component.effectiveFrom)}'
                    '${component.active ? '' : ' · ARCHIVED'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(currency.format(component.amountPaise / 100)),
                      if (component.active)
                        IconButton(
                          tooltip: 'Archive component',
                          onPressed: () async {
                            await HrPayrollService()
                                .archiveSalaryComponent(component.id);
                          },
                          icon: const Icon(Icons.archive_outlined),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Add component'),
      ),
    );
  }
}
