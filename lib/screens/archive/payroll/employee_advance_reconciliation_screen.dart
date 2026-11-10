import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/hr_payroll_service.dart';

class EmployeeAdvanceReconciliationScreen extends StatelessWidget {
  const EmployeeAdvanceReconciliationScreen({super.key});

  String _money(int paise) =>
      NumberFormat.simpleCurrency(locale: 'en_IN').format(paise / 100);

  @override
  Widget build(BuildContext context) {
    final settings = Hive.box<dynamic>('app_settings');
    final employees = Hive.box<Employee>(Boxes.employees);
    final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    return Scaffold(
      appBar: AppBar(title: const Text('Employee advance reconciliation')),
      body: ValueListenableBuilder<Box<dynamic>>(
        valueListenable: settings.listenable(keys: [
          HrPayrollService.advanceSettingsKey,
          HrPayrollService.advancePayrollKey,
        ]),
        builder: (context, settingsBox, _) =>
            ValueListenableBuilder<Box<FinanceTransaction>>(
          valueListenable: transactions.listenable(),
          builder: (context, transactionBox, __) {
            final summary = HrPayrollService().advanceReconciliation();
            final raw = settingsBox.get(HrPayrollService.advanceSettingsKey);
            final rows = <Widget>[];
            var legacyCount = 0;
            var advanceCount = 0;
            if (raw is Map) {
              for (final entry in raw.entries) {
                final employee = employees.get(entry.key);
                if (entry.value is! List) continue;
                final advances = (entry.value as List).whereType<Map>();
                for (final item in advances) {
                  if (item['id'] is! String) continue;
                  advanceCount++;
                  final advanceId = item['id'] as String;
                  final issue = transactionBox.values.where((tx) =>
                    tx.sourceType == 'employee_advance_issue' && tx.sourceId == advanceId).toList();
                  final repayments = (item['repayments'] as List? ?? []).whereType<Map>().toList();
                  final missingManual = repayments.where((repayment) {
                    if (repayment['source'] != 'manual' || repayment['id'] is! String) return false;
                    return !transactionBox.values.any((tx) =>
                      tx.sourceType == 'employee_advance_repayment' &&
                      tx.sourceId == repayment['id']);
                  }).length;
                  if (issue.isEmpty || missingManual > 0) legacyCount++;
                  final principal = item['principalPaise'] as int? ?? 0;
                  final outstanding = item['outstandingPaise'] as int? ?? 0;
                  final issueStatus = issue.isEmpty
                      ? 'Missing issue journal — legacy or unreconciled'
                      : issue.single.status == 'posted'
                          ? 'Issue journal: ${issue.single.transactionNumber}'
                          : 'Issue journal is not posted';
                  final payrollIds = repayments
                      .where((repayment) => repayment['source'] == 'payroll' && repayment['payslipId'] is String)
                      .map((repayment) => repayment['payslipId'] as String)
                      .toSet();
                  final payrollJournals = transactionBox.values.where((tx) =>
                    tx.sourceType == 'payroll_advance_recovery' && payrollIds.contains(tx.sourceId)).length;
                  rows.add(Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ExpansionTile(
                      title: Text(item['description'] as String? ?? 'Employee advance'),
                      subtitle: Text('${employee?.name ?? 'Unknown employee'} · Outstanding ${_money(outstanding)}'),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        _detail('Advance ID', advanceId),
                        _detail('Principal', _money(principal)),
                        _detail('Outstanding', _money(outstanding)),
                        _detail('Status', item['status'] as String? ?? 'unknown'),
                        _detail('Issue date', item['issueDate'] as String? ?? '—'),
                        _detail('Issue journal', issueStatus),
                        _detail('Repayment records', repayments.length.toString()),
                        _detail('Payroll recovery journals', payrollJournals.toString()),
                        if (missingManual > 0)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.warning_amber_rounded),
                            title: Text('$missingManual manual repayment journal(s) missing'),
                          ),
                        if (repayments.isNotEmpty) ...[
                          const Divider(),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Repayment history', style: Theme.of(context).textTheme.titleSmall),
                          ),
                          for (final repayment in repayments)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(_money(repayment['amountPaise'] as int? ?? 0)),
                              subtitle: Text('${repayment['source'] ?? 'unknown'} · ${repayment['date'] ?? ''}'),
                              trailing: repayment['source'] == 'manual'
                                  ? Icon(
                                      transactionBox.values.any((tx) =>
                                        tx.sourceType == 'employee_advance_repayment' &&
                                        tx.sourceId == repayment['id'])
                                        ? Icons.check_circle_outline
                                        : Icons.warning_amber_rounded,
                                    )
                                  : const Icon(Icons.receipt_long_outlined),
                            ),
                        ],
                      ],
                    ),
                  ));
                }
              }
            }
            final difference = summary['differencePaise'] ?? 0;
            final balanced = difference == 0;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(balanced ? Icons.verified_outlined : Icons.warning_amber_rounded,
                            color: balanced ? Colors.green : Theme.of(context).colorScheme.error),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                            balanced ? 'Control account matches HR register' : 'Advance balances do not reconcile',
                            style: Theme.of(context).textTheme.titleMedium,
                          )),
                        ]),
                        const SizedBox(height: 12),
                        _detail('HR subledger outstanding', _money(summary['subledgerPaise'] ?? 0)),
                        _detail('Employee Advances control account', _money(summary['journalPaise'] ?? 0)),
                        const Divider(),
                        _detail('Difference (journal − subledger)', _money(difference)),
                        _detail('Advance records', advanceCount.toString()),
                        _detail('Records with missing issue/manual journals', legacyCount.toString()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'Do not post a balancing adjustment solely to force this report to zero. Older advances may have been recorded before journal integration. Reconstruct their actual cash/bank disbursement and repayment history first. Posted journal corrections must use immutable reversals and matching HR-register corrections; this screen is currently diagnostic and does not modify either ledger.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Advance register', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (rows.isEmpty)
                  const Card(child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('No employee advances recorded'),
                  ))
                else
                  ...rows,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Expanded(child: Text(label)),
      const SizedBox(width: 12),
      Flexible(child: Text(value, textAlign: TextAlign.end)),
    ]),
  );
}
