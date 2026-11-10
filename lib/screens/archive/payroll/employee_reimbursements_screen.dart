import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/hr_payroll_service.dart';

class EmployeeReimbursementsScreen extends StatelessWidget {
  const EmployeeReimbursementsScreen({super.key});

  String _money(int paise) => NumberFormat.simpleCurrency(locale: 'en_IN').format(paise / 100);

  int? _parsePaise(String value) {
    final raw = value.trim();
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(raw)) return null;
    final parts = raw.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null) return null;
    return whole * 100 + (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  }

  Future<void> _createClaim(BuildContext context) async {
    final employees = Hive.box<Employee>(Boxes.employees).values.where((e) => e.employmentStatus == 'active').toList();
    if (employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add an active employee before creating a reimbursement claim.')));
      return;
    }
    final categories = Hive.box<FinanceCategory>(Boxes.financeCategories).values.where((c) => c.active && c.kind == 'expense').toList();
    final amount = TextEditingController();
    final note = TextEditingController();
    String employeeId = employees.first.id;
    String categoryId = '';
    DateTime expenseDate = DateTime.now();
    final saved = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('New reimbursement claim'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(value: employeeId, decoration: const InputDecoration(labelText: 'Employee'), items: [for (final employee in employees) DropdownMenuItem(value: employee.id, child: Text(employee.name))], onChanged: (value) => setDialogState(() => employeeId = value ?? employeeId)),
          const SizedBox(height: 10),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Claim amount (INR)', prefixText: '₹ ')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: categoryId, decoration: const InputDecoration(labelText: 'Expense category'), items: [const DropdownMenuItem(value: '', child: Text('General operating expense')), for (final category in categories) DropdownMenuItem(value: category.id, child: Text(category.name))], onChanged: (value) => setDialogState(() => categoryId = value ?? '')),
          const SizedBox(height: 10),
          TextField(controller: note, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Description / business purpose')),
          TextButton.icon(onPressed: () async { final picked = await showDatePicker(context: dialogContext, initialDate: expenseDate, firstDate: DateTime(2000), lastDate: DateTime.now()); if (picked != null) setDialogState(() => expenseDate = picked); }, icon: const Icon(Icons.calendar_today_outlined), label: Text(DateFormat.yMMMd().format(expenseDate))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () { if ((_parsePaise(amount.text) ?? 0) > 0 && note.text.trim().isNotEmpty) Navigator.pop(dialogContext, true); }, child: const Text('Submit claim')),
        ],
      ),
    ));
    if (saved == true) {
      try {
        await HrPayrollService().submitReimbursement(employeeId: employeeId, amountPaise: _parsePaise(amount.text)!, expenseDate: expenseDate, categoryId: categoryId, note: note.text);
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reimbursement claim submitted.')));
      } catch (error) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit claim: $error')));
      }
    }
    amount.dispose(); note.dispose();
  }

  Future<void> _review(BuildContext context, Map claim, String decision) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(decision == 'approved' ? 'Approve reimbursement?' : 'Reject reimbursement?'),
      content: TextField(controller: reason, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: decision == 'rejected' ? 'Rejection reason (required)' : 'Review note (optional)')),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () { if (decision == 'approved' || reason.text.trim().isNotEmpty) Navigator.pop(dialogContext, true); }, child: Text(decision == 'approved' ? 'Approve' : 'Reject'))],
    ));
    if (confirmed == true) {
      try {
        await HrPayrollService().reviewReimbursement(claimId: claim['id'] as String, decision: decision, reason: reason.text);
      } catch (error) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not review claim: $error')));
      }
    }
    reason.dispose();
  }

  Future<void> _cancelClaim(BuildContext context, Map claim) async {
    final reason = TextEditingController();
    final hasPayment = (claim['paidPaise'] is int ? claim['paidPaise'] as int : 0) > 0;
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Cancel / reverse reimbursement'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (hasPayment) const Text('This reverses the settlement journals and records the funds as returned to the original cash/bank accounts. Only continue if the payment was refunded or was erroneous.'),
        const SizedBox(height: 10),
        TextField(controller: reason, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Reason (required)')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep claim')), FilledButton(onPressed: () { if (reason.text.trim().isNotEmpty) Navigator.pop(dialogContext, true); }, child: const Text('Reverse claim'))],
    ));
    if (confirmed == true) {
      try {
        await HrPayrollService().reverseReimbursementClaim(claimId: claim['id'] as String, reason: reason.text);
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reimbursement claim reversed.')));
      } catch (error) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not reverse reimbursement: $error')));
      }
    }
    reason.dispose();
  }
  Future<void> _pay(BuildContext context, Map claim) async {
    final amount = TextEditingController(text: (((claim['amountPaise'] as int) - (claim['paidPaise'] as int)) / 100).toStringAsFixed(2));
    final accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts).values.where((a) => a.active && a.accountType == 'asset' && a.currencyCode == 'INR').toList();
    if (accounts.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create an active INR cash or bank account first.'))); return; }
    String accountId = accounts.first.id;
    final saved = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Settle reimbursement'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Payment amount (INR)', prefixText: '₹ ')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: accountId, decoration: const InputDecoration(labelText: 'Pay from'), items: [for (final account in accounts) DropdownMenuItem(value: account.id, child: Text(account.name))], onChanged: (value) => setDialogState(() => accountId = value ?? accountId)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')), FilledButton(onPressed: () { if ((_parsePaise(amount.text) ?? 0) > 0) Navigator.pop(dialogContext, true); }, child: const Text('Record payment'))],
      ),
    ));
    if (saved == true) {
      try {
        await HrPayrollService().payReimbursement(claimId: claim['id'] as String, amountPaise: _parsePaise(amount.text)!, paymentAccountId: accountId);
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reimbursement payment posted.')));
      } catch (error) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not settle reimbursement: $error')));
      }
    }
    amount.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Hive.box<dynamic>('app_settings');
    final employees = Hive.box<Employee>(Boxes.employees);
    return Scaffold(
      appBar: AppBar(title: const Text('Employee reimbursements'), actions: [IconButton(onPressed: () => _createClaim(context), icon: const Icon(Icons.add), tooltip: 'New claim')]),
      body: ValueListenableBuilder<Box<dynamic>>(
        valueListenable: settings.listenable(keys: [HrPayrollService.employeeReimbursementsKey]),
        builder: (context, settingsBox, _) {
          final claims = HrPayrollService().reimbursements();
          if (claims.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.receipt_long_outlined, size: 42), const SizedBox(height: 10), const Text('No reimbursement claims'), const SizedBox(height: 12), FilledButton.icon(onPressed: () => _createClaim(context), icon: const Icon(Icons.add), label: const Text('Create claim'))]));
          return ListView(padding: const EdgeInsets.all(16), children: [
            for (final claim in claims)
              Card(child: ExpansionTile(
                title: Text(_money(claim['amountPaise'] is int ? claim['amountPaise'] as int : 0)),
                subtitle: Text('${employees.get(claim['employeeId'])?.name ?? 'Unknown employee'} · ${(claim['status'] ?? 'unknown').toString().toUpperCase()}'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  _detail('Expense date', claim['expenseDate']?.toString() ?? '—'),
                  _detail('Paid', _money(claim['paidPaise'] is int ? claim['paidPaise'] as int : 0)),
                  _detail('Outstanding', _money(((claim['amountPaise'] is int ? claim['amountPaise'] as int : 0) - (claim['paidPaise'] is int ? claim['paidPaise'] as int : 0)) < 0 ? 0 : (claim['amountPaise'] as int) - (claim['paidPaise'] as int))),
                  _detail('Description', claim['note']?.toString() ?? ''),
                  if (claim['reviewNote'] is String && (claim['reviewNote'] as String).isNotEmpty) _detail('Review note', claim['reviewNote'] as String),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (claim['status'] == 'submitted') OutlinedButton(onPressed: () => _review(context, claim, 'approved'), child: const Text('Approve')),
                    if (claim['status'] == 'submitted') OutlinedButton(onPressed: () => _review(context, claim, 'rejected'), child: const Text('Reject')),
                    if (claim['status'] == 'approved' || claim['status'] == 'partially_paid') FilledButton.icon(onPressed: () => _pay(context, claim), icon: const Icon(Icons.payments_outlined), label: const Text('Pay / settle')),
                    if (claim['status'] == 'approved' || claim['status'] == 'partially_paid' || claim['status'] == 'paid')
                      OutlinedButton.icon(onPressed: () => _cancelClaim(context, claim), icon: const Icon(Icons.undo_outlined), label: const Text('Cancel / reverse')),
                  ]),
                ],
              )),
          ]);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _createClaim(context), icon: const Icon(Icons.add), label: const Text('New claim')),
    );
  }

  Widget _detail(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [Expanded(child: Text(label)), const SizedBox(width: 12), Flexible(child: Text(value, textAlign: TextAlign.end))]));
}