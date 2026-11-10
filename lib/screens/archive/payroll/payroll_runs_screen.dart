import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/hr_payroll_service.dart';
import 'payroll_run_details_screen.dart';

class PayrollRunsScreen extends StatefulWidget {
  const PayrollRunsScreen({super.key});

  @override
  State<PayrollRunsScreen> createState() => _PayrollRunsScreenState();
}

class _PayrollRunsScreenState extends State<PayrollRunsScreen> {
  DateTime _month = DateTime.now();
  bool _generating = false;

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      helpText: 'Choose a date in the payroll month',
    );
    if (picked != null) setState(() => _month = picked);
  }

  Future<void> _generate() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final start = DateTime(_month.year, _month.month);
      final end = DateTime(_month.year, _month.month + 1, 0);
      final run = await HrPayrollService().generateRun(
        periodStart: start,
        periodEnd: end,
      );
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PayrollRunDetailsScreen(runId: run.id),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate payroll: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM yyyy');
    final currency = NumberFormat.simpleCurrency(locale: 'en_IN');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll runs'),
        actions: [
          IconButton(
            onPressed: _pickMonth,
            tooltip: 'Select payroll month',
            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Selected period: ${dateFormat.format(_month)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _generating ? null : _generate,
                  icon: _generating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.playlist_add_check),
                  label: Text(_generating ? 'Generating' : 'Generate run'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<Box<PayrollRun>>(
              valueListenable:
                  Hive.box<PayrollRun>(Boxes.payrollRuns).listenable(),
              builder: (context, box, _) {
                final runs = box.values.toList()
                  ..sort((a, b) => b.periodStart.compareTo(a.periodStart));
                if (runs.isEmpty) {
                  return const Center(
                    child: Text('No payroll runs have been generated.'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: runs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final run = runs[index];
                    return Card(
                      child: ListTile(
                        title: Text(
                          '${DateFormat('dd MMM yyyy').format(run.periodStart)} – '
                          '${DateFormat('dd MMM yyyy').format(run.periodEnd)}',
                        ),
                        subtitle: Text(
                          '${run.status.toUpperCase()} · '
                          'Gross ${currency.format(run.totalGrossPaise / 100)} · '
                          'Net ${currency.format(run.totalNetPaise / 100)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PayrollRunDetailsScreen(runId: run.id),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
