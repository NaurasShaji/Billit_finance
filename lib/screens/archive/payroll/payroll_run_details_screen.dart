import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/hr_payroll_service.dart';
import 'payslip_details_screen.dart';

class PayrollRunDetailsScreen extends StatefulWidget {
  const PayrollRunDetailsScreen({super.key, required this.runId});

  final String runId;

  @override
  State<PayrollRunDetailsScreen> createState() =>
      _PayrollRunDetailsScreenState();
}

class _PayrollRunDetailsScreenState extends State<PayrollRunDetailsScreen> {
  final _currency = NumberFormat.simpleCurrency(locale: 'en_IN');

  Future<void> _approve(PayrollRun run) async {
    try {
      await HrPayrollService().approveRun(run.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payroll run approved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not approve payroll: $error')),
        );
      }
    }
  }

  int? _parsePaise(String raw) {
    final value = raw.trim();
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null) return null;
    final fraction =
        parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0'));
    return whole * 100 + fraction;
  }

  Future<void> _pay(Payslip slip) async {
    final amount = TextEditingController(
      text: (slip.outstandingPaise / 100).toStringAsFixed(2),
    );
    final paid = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Record payslip payment'),
        content: TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount',
            prefixText: '₹ ',
            helperText:
                'Outstanding: ${_currency.format(slip.outstandingPaise / 100)}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Record payment'),
          ),
        ],
      ),
    );

    if (paid == true) {
      final amountPaise = _parsePaise(amount.text);
      if (amountPaise == null || amountPaise <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter a valid positive amount.')),
          );
        }
      } else {
        try {
          await HrPayrollService().payPayslip(
            payslipId: slip.id,
            amountPaise: amountPaise,
          );
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not record payment: $error')),
            );
          }
        }
      }
    }
    amount.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runBox = Hive.box<PayrollRun>(Boxes.payrollRuns);
    final slipsBox = Hive.box<Payslip>(Boxes.payslips);
    final employeesBox = Hive.box<Employee>(Boxes.employees);
    return ValueListenableBuilder<Box<PayrollRun>>(
      valueListenable: runBox.listenable(keys: [widget.runId]),
      builder: (context, runs, _) {
        final run = runs.get(widget.runId);
        if (run == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Payroll run')),
            body: const Center(child: Text('Payroll run not found.')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Payroll run'),
            actions: [
              if (run.status == 'draft')
                TextButton(
                  onPressed: () => _approve(run),
                  child: const Text('Approve'),
                ),
            ],
          ),
          body: ValueListenableBuilder<Box<Payslip>>(
            valueListenable: slipsBox.listenable(),
            builder: (context, box, _) {
              final slips = box.values
                  .where((slip) => slip.payrollRunId == run.id)
                  .toList()
                ..sort((a, b) => a.employeeId.compareTo(b.employeeId));
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${DateFormat('dd MMM yyyy').format(run.periodStart)} – '
                            '${DateFormat('dd MMM yyyy').format(run.periodEnd)}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Chip(label: Text(run.status.toUpperCase())),
                          const Divider(height: 24),
                          _total('Gross pay', run.totalGrossPaise),
                          _total('Deductions', run.totalDeductionsPaise),
                          _total('Net pay', run.totalNetPaise),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Payslips (${slips.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final slip in slips)
                    Card(
                      child: ListTile(
                        title: Text(
                          employeesBox.get(slip.employeeId)?.name ??
                              'Unknown employee',
                        ),
                        subtitle: Text(
                          '${slip.status.toUpperCase()} · '
                          'Base ${_currency.format(slip.basePaise / 100)} · '
                          'Net ${_currency.format(slip.netPaise / 100)}'
                          '${slip.payType == 'daily' ? ' · ${slip.payableDays} payable days' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'view') {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PayslipDetailsScreen(payslipId: slip.id),
                                ),
                              );
                            } else if (value == 'pay') {
                              _pay(slip);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'view',
                              child: Text('View payslip'),
                            ),
                            if (run.status != 'draft' &&
                                slip.outstandingPaise > 0)
                              const PopupMenuItem(
                                value: 'pay',
                                child: Text('Record payment'),
                              ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              _currency.format(slip.outstandingPaise / 100),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _total(String label, int paise) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              _currency.format(paise / 100),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}
