import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/hr_payroll_service.dart';

class EmployeeAdvanceReconciliationScreen extends StatelessWidget {
  const EmployeeAdvanceReconciliationScreen({super.key});

  static const _advanceAccountId = HrPayrollService.employeeAdvanceAccountId;

  String _money(int paise) =>
      NumberFormat.simpleCurrency(locale: 'en_IN').format(paise / 100);

  int _amount(Object? value) => value is int && value >= 0 ? value : 0;

  List<FinancePosting> _linesFor(
    Box<FinancePosting> postings,
    String transactionId,
  ) =>
      postings.values.where((line) => line.transactionId == transactionId).toList();

  bool _matchesJournal({
    required FinanceTransaction transaction,
    required List<FinancePosting> lines,
    required String debitAccountId,
    required String creditAccountId,
    required int amountPaise,
  }) {
    if (transaction.status != 'posted' || lines.length != 2) return false;
    final debit = lines.where((line) => line.accountId == debitAccountId).toList();
    final credit = lines.where((line) => line.accountId == creditAccountId).toList();
    return debit.length == 1 &&
        credit.length == 1 &&
        debit.single.debitPaise == amountPaise &&
        debit.single.creditPaise == 0 &&
        credit.single.creditPaise == amountPaise &&
        credit.single.debitPaise == 0;
  }

  bool _matchesPayrollAccrualJournal({
    required FinanceTransaction transaction,
    required List<FinancePosting> lines,
    required int minimumAmountPaise,
  }) {
    if (transaction.status != 'posted' || lines.length < 2) return false;
    final salaryDebits = lines.where((line) =>
        line.accountId == 'system:salary-expense' && line.debitPaise > 0).toList();
    final advanceCredits = lines.where((line) =>
        line.accountId == _advanceAccountId && line.creditPaise > 0).toList();
    if (salaryDebits.length != 1 || advanceCredits.length != 1) return false;
    final advanceCredit = advanceCredits.single;
    final debitTotal = lines.fold<int>(0, (sum, line) => sum + line.debitPaise);
    final creditTotal = lines.fold<int>(0, (sum, line) => sum + line.creditPaise);
    return advanceCredit.creditPaise >= minimumAmountPaise &&
        advanceCredit.debitPaise == 0 &&
        salaryDebits.single.creditPaise == 0 &&
        debitTotal > 0 && debitTotal == creditTotal;
  }

  @override
  Widget build(BuildContext context) {
    final settings = Hive.box<dynamic>('app_settings');
    final employees = Hive.box<Employee>(Boxes.employees);
    final transactions = Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    final postings = Hive.box<FinancePosting>(Boxes.financePostings);

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
          builder: (context, transactionBox, __) =>
              ValueListenableBuilder<Box<FinancePosting>>(
            valueListenable: postings.listenable(),
            builder: (context, postingBox, ___) {
              final summary = HrPayrollService().advanceReconciliation();
              final raw = settingsBox.get(HrPayrollService.advanceSettingsKey);
              final rows = <Widget>[];
              var advanceCount = 0;
              var issueProblemCount = 0;
              var repaymentProblemCount = 0;
              var malformedCount = 0;

              if (raw is Map) {
                for (final entry in raw.entries) {
                  final employee = employees.get(entry.key);
                  if (entry.value is! List) {
                    malformedCount++;
                    continue;
                  }
                  for (final value in entry.value as List) {
                    if (value is! Map || value['id'] is! String) {
                      malformedCount++;
                      continue;
                    }
                    final item = value;
                    final advanceId = item['id'] as String;
                    advanceCount++;
                    final principal = _amount(item['principalPaise']);
                    final outstanding = _amount(item['outstandingPaise']);
                    final repaymentValues = item['repayments'];
                    final repayments = repaymentValues is List
                        ? repaymentValues.whereType<Map>().toList()
                        : <Map>[];
                    if (repaymentValues != null && repaymentValues is! List) {
                      malformedCount++;
                    }

                    final issueJournals = transactionBox.values.where((tx) =>
                        tx.sourceType == 'employee_advance_issue' &&
                        tx.sourceId == advanceId).toList();
                    final openingJournals = transactionBox.values.where((tx) =>
                        tx.sourceType == 'employee_advance_opening_balance' &&
                        tx.sourceId == advanceId).toList();
                    var issueValid = false;
                    var openingValid = false;
                    if (openingJournals.length == 1) {
                      openingValid = _matchesJournal(
                        transaction: openingJournals.single,
                        lines: _linesFor(postingBox, openingJournals.single.id),
                        debitAccountId: _advanceAccountId,
                        creditAccountId: 'system:opening-equity',
                        amountPaise: principal,
                      );
                    }
                    if (issueJournals.length == 1) {
                      final issueLines = _linesFor(postingBox, issueJournals.single.id);
                      final creditLines = issueLines.where((line) => line.creditPaise > 0).toList();
                      issueValid = creditLines.length == 1 &&
                          _matchesJournal(
                            transaction: issueJournals.single,
                            lines: issueLines,
                            debitAccountId: _advanceAccountId,
                            creditAccountId: creditLines.single.accountId,
                            amountPaise: principal,
                          );
                    }

                    var missingManual = 0;
                    var invalidManual = 0;
                    var manualCount = 0;
                    final payrollRecoveryAmounts = <String, int>{};
                    var malformedPayrollRepayments = 0;
                    for (final repayment in repayments) {
                      final source = repayment['source'];
                      if (source == 'payroll') {
                        final payslipId = repayment['payslipId'];
                        final amount = repayment['amountPaise'];
                        if (payslipId is! String || amount is! int || amount <= 0) {
                          malformedPayrollRepayments++;
                        } else {
                          payrollRecoveryAmounts.update(
                            payslipId,
                            (existing) => existing + amount,
                            ifAbsent: () => amount,
                          );
                        }
                      }
                      if (source != 'manual' || repayment['id'] is! String) continue;
                      manualCount++;
                      final linked = transactionBox.values.where((tx) =>
                          tx.sourceType == 'employee_advance_repayment' &&
                          tx.sourceId == repayment['id']).toList();
                      if (linked.isEmpty) {
                        missingManual++;
                      } else if (linked.length != 1) {
                        invalidManual++;
                      } else {
                        final linkedLines = _linesFor(postingBox, linked.single.id);
                        final debitLines = linkedLines.where((line) => line.debitPaise > 0).toList();
                        if (debitLines.length != 1 ||
                            !_matchesJournal(
                              transaction: linked.single,
                              lines: linkedLines,
                              debitAccountId: debitLines.length == 1 ? debitLines.single.accountId : '',
                              creditAccountId: _advanceAccountId,
                              amountPaise: _amount(repayment['amountPaise']),
                            )) {
                          invalidManual++;
                        }
                      }
                    }

                    final payrollJournals = transactionBox.values.where((tx) =>
                        tx.sourceType == 'payroll_accrual' &&
                        payrollRecoveryAmounts.containsKey(tx.sourceId)).toList();
                    final duplicatePayrollJournals =
                        payrollJournals.map((tx) => tx.sourceId).toSet().length != payrollJournals.length;
                    final linkedPayrollIds = payrollJournals.map((tx) => tx.sourceId).toSet();
                    final missingPayrollJournals = payrollRecoveryAmounts.keys
                        .where((id) => !linkedPayrollIds.contains(id)).length;
                    var invalidPayrollJournals = 0;
                    for (final payslipId in linkedPayrollIds) {
                      final linked = payrollJournals.where((tx) => tx.sourceId == payslipId).toList();
                      if (linked.length != 1) {
                        invalidPayrollJournals++;
                        continue;
                      }
                      final linkedLines = _linesFor(postingBox, linked.single.id);
                      if (!_matchesPayrollAccrualJournal(
                        transaction: linked.single,
                        lines: linkedLines,
                        minimumAmountPaise: payrollRecoveryAmounts[payslipId]!,
                      )) {
                        invalidPayrollJournals++;
                      }
                    }
                    final openingProblem = openingJournals.length > 1 ||
                        (openingJournals.length == 1 && !openingValid) ||
                        (issueValid && openingValid);
                    final issueProblem = issueJournals.length > 1 ||
                        openingProblem || (!issueValid && !openingValid);
                    final repaymentProblem = missingManual > 0 ||
                        invalidManual > 0 || malformedPayrollRepayments > 0 ||
                        duplicatePayrollJournals || missingPayrollJournals > 0 ||
                        invalidPayrollJournals > 0;
                    if (issueProblem) issueProblemCount++;
                    if (repaymentProblem) repaymentProblemCount++;

                    final issueLabel = issueJournals.isNotEmpty
                        ? issueJournals.length > 1
                            ? 'Duplicate issue journals (${issueJournals.length})'
                            : issueValid
                                ? 'Issue journal: ${issueJournals.single.transactionNumber}'
                                : 'Issue journal is unposted or does not match principal'
                        : openingJournals.length > 1
                            ? 'Duplicate opening-balance journals'
                            : openingValid
                                ? 'Opening balance: ${openingJournals.single.transactionNumber}'
                                : 'Missing issue/opening-balance journal';

                    rows.add(Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ExpansionTile(
                        title: Text(item['description'] is String
                            ? item['description'] as String
                            : 'Employee advance'),
                        subtitle: Text(
                          '${employee?.name ?? 'Unknown employee'} · Outstanding ${_money(outstanding)}',
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          _detail('Advance ID', advanceId),
                          _detail('Principal', _money(principal)),
                          _detail('Outstanding', _money(outstanding)),
                          _detail('Status', item['status'] is String ? item['status'] as String : 'unknown'),
                          _detail('Issue date', item['issueDate'] is String ? item['issueDate'] as String : '—'),
                          _detail('Issue journal', issueLabel),
                          _detail('Opening-balance journal count', openingJournals.length.toString()),
                          _detail('Manual repayment records', manualCount.toString()),
                          _detail('Missing manual journals', missingManual.toString()),
                          _detail('Invalid/duplicate manual journals', invalidManual.toString()),
                          _detail('Payroll recovery records', payrollRecoveryAmounts.length.toString()),
                          _detail('Linked payroll recovery journals', payrollJournals.length.toString()),
                          _detail('Missing payroll recovery journals', missingPayrollJournals.toString()),
                          _detail('Invalid payroll recovery journals', invalidPayrollJournals.toString()),
                          _detail('Malformed payroll repayment records', malformedPayrollRepayments.toString()),
                          if (duplicatePayrollJournals || missingPayrollJournals > 0 || invalidPayrollJournals > 0 || malformedPayrollRepayments > 0)
                            const ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.warning_amber_rounded),
                              title: Text('Duplicate payroll recovery journals detected'),
                            ),
                          if (missingManual > 0 || invalidManual > 0 || issueProblem)
                            const ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.warning_amber_rounded),
                              title: Text('Journal coverage requires investigation'),
                            ),
                          if (issueJournals.isEmpty && openingJournals.isEmpty && repayments.isEmpty && outstanding > 0)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () => _recordOpeningBalance(
                                  context,
                                  employeeId: entry.key.toString(),
                                  advanceId: advanceId,
                                  outstandingPaise: outstanding,
                                ),
                                icon: const Icon(Icons.account_balance_outlined),
                                label: const Text('Record verified opening balance'),
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () => _correctAdvanceBalance(
                                context,
                                employeeId: entry.key.toString(),
                                advanceId: advanceId,
                                outstandingPaise: outstanding,
                                issueDate: DateTime.tryParse(item['issueDate']?.toString() ?? '') ?? DateTime.now(),
                              ),
                              icon: const Icon(Icons.edit_note_outlined),
                              label: const Text('Correct verified balance'),
                            ),
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
                                title: Text(_money(_amount(repayment['amountPaise']))),
                                subtitle: Text('${repayment['source'] ?? 'unknown'} · ${repayment['date'] ?? ''}'),
                                trailing: repayment['source'] == 'manual'
                                    ? Icon(transactionBox.values.any((tx) =>
                                        tx.sourceType == 'employee_advance_repayment' &&
                                        tx.sourceId == repayment['id'])
                                        ? Icons.check_circle_outline
                                        : Icons.warning_amber_rounded)
                                    : const Icon(Icons.receipt_long_outlined),
                              ),
                          ],
                        ],
                      ),
                    ));
                  }
                }
              } else if (raw != null) {
                malformedCount++;
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
                            Icon(
                              balanced ? Icons.verified_outlined : Icons.warning_amber_rounded,
                              color: balanced ? Colors.green : Theme.of(context).colorScheme.error,
                            ),
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
                          _detail('Issue-journal exceptions', issueProblemCount.toString()),
                          _detail('Repayment-journal exceptions', repaymentProblemCount.toString()),
                          _detail('Malformed register records', malformedCount.toString()),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'This report is diagnostic only. A zero aggregate difference does not prove that each advance is correctly journalled. Do not post a balancing adjustment to force the total to zero. Historical advances require verified opening-balance treatment, and posted corrections must use immutable reversals with matching HR-register corrections.',
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
      ),
    );
  }


  Future<void> _correctAdvanceBalance(
    BuildContext context, {
    required String employeeId,
    required String advanceId,
    required int outstandingPaise,
    required DateTime issueDate,
  }) async {
    final accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts).values
        .where((account) => account.active && account.currencyCode == 'INR' && account.id != _advanceAccountId)
        .toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create an active INR offset account before correcting an advance.')));
      return;
    }
    final amountController = TextEditingController(text: (outstandingPaise / 100).toStringAsFixed(2));
    final reasonController = TextEditingController();
    String? offsetAccountId = accounts.first.id;
    DateTime effectiveDate = DateTime.now();
    int? parsePaise(String value) {
      final match = RegExp(r'^\d+(?:\.\d{1,2})?$').firstMatch(value.trim());
      if (match == null) return null;
      final parts = value.trim().split('.');
      final whole = int.tryParse(parts[0]);
      if (whole == null) return null;
      final fraction = parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0'));
      return whole * 100 + fraction;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Correct advance balance'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current HR balance: ${_money(outstandingPaise)}'),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Verified outstanding balance (INR)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: offsetAccountId,
                  decoration: const InputDecoration(labelText: 'Correction offset account', border: OutlineInputBorder()),
                  items: [for (final account in accounts) DropdownMenuItem(value: account.id, child: Text('${account.name} · ${account.accountType}'))],
                  onChanged: (value) => setDialogState(() => offsetAccountId = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Reason for correction', hintText: 'Explain the verified discrepancy', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(context: dialogContext, initialDate: effectiveDate, firstDate: DateTime(issueDate.year, issueDate.month, issueDate.day), lastDate: DateTime.now(), helpText: 'Correction effective date');
                    if (picked != null) setDialogState(() => effectiveDate = picked);
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('Effective date: ${DateFormat.yMMMd().format(effectiveDate)}'),
                ),
                const Text('This posts an immutable adjustment journal and updates the HR register. It does not rewrite or delete prior journals. Select the offset account based on the verified cause.'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final amount = parsePaise(amountController.text);
                if (amount == null || reasonController.text.trim().isEmpty || offsetAccountId == null) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Post correction'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && context.mounted) {
      final amount = parsePaise(amountController.text);
      if (amount == null || offsetAccountId == null) return;
      try {
        await HrPayrollService().correctEmployeeAdvanceBalance(employeeId: employeeId, advanceId: advanceId, correctedOutstandingPaise: amount, effectiveDate: effectiveDate, reason: reasonController.text, offsetAccountId: offsetAccountId!);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Advance balance correction posted.')));
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not correct advance balance: $error')));
      }
    }
    amountController.dispose();
    reasonController.dispose();
  }
  Future<void> _recordOpeningBalance(
    BuildContext context, {
    required String employeeId,
    required String advanceId,
    required int outstandingPaise,
  }) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Opening balance effective date',
    );
    if (date == null || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Post advance opening balance?'),
        content: Text(
          'This will debit Employee Advances and credit Opening Balance Equity by ${_money(outstandingPaise)} as of ${DateFormat.yMMMd().format(date)}. It will not recreate historical cash movements. Only continue if this is the verified outstanding balance at the selected cut-off date.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Post opening balance'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await HrPayrollService().recordLegacyAdvanceOpeningBalance(
        employeeId: employeeId,
        advanceId: advanceId,
        asOfDate: date,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opening balance journal posted.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not post opening balance: $error')),
      );
    }
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