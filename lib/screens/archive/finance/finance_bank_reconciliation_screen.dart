import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/finance_bank_reconciliation_service.dart';
import '../../../widgets/finance_content_frame.dart';

class FinanceBankReconciliationScreen extends StatefulWidget {
  const FinanceBankReconciliationScreen({super.key});

  @override
  State<FinanceBankReconciliationScreen> createState() =>
      _FinanceBankReconciliationScreenState();
}

class _FinanceBankReconciliationScreenState
    extends State<FinanceBankReconciliationScreen> {
  final _service = FinanceBankReconciliationService();
  String? _accountId;
  bool _importing = false;

  String _money(int paise) =>
      NumberFormat.simpleCurrency(locale: 'en_IN').format(paise / 100);

  Future<void> _importStatement() async {
    if (_accountId == null) return;
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw const FinanceBankReconciliationException(
          'The selected CSV could not be read. Select a local file and retry.',
        );
      }
      final count = await _service.importCsv(
        accountId: _accountId!,
        csvText: utf8.decode(bytes, allowMalformed: false),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count statement transaction(s) imported.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import statement: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _match(Map<String, dynamic> line) async {
    final candidates = _service.candidatePostings(line);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No exact amount match was found within five days.'),
        ),
      );
      return;
    }
    final selected = await showDialog<
        ({FinanceTransaction transaction, FinancePosting posting})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Match ledger transaction'),
        content: SizedBox(
          width: 560,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: candidates.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final candidate = candidates[index];
              return ListTile(
                title: Text(candidate.transaction.transactionNumber),
                subtitle: Text(
                  '${DateFormat('dd MMM yyyy').format(candidate.transaction.date)} • '
                  '${candidate.transaction.memo.isEmpty ? candidate.posting.memo : candidate.transaction.memo}',
                ),
                trailing: Text(_money(
                  candidate.posting.debitPaise - candidate.posting.creditPaise,
                )),
                onTap: () => Navigator.pop(dialogContext, candidate),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    try {
      await _service.match(
        statementLineId: line['id'] as String,
        transactionId: selected.transaction.id,
        postingId: selected.posting.id,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not match transaction: $error')),
        );
      }
    }
  }

  Future<void> _unmatch(Map<String, dynamic> line) async {
    try {
      await _service.unmatch(line['id'] as String);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove match: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = Hive.box<FinanceAccount>(Boxes.financeAccounts);
    final settings = Hive.box<dynamic>('app_settings');
    return FinanceContentFrame(
      child: Scaffold(
        appBar: AppBar(title: const Text('Bank reconciliation')),
        body: ValueListenableBuilder<Box<FinanceAccount>>(
          valueListenable: accounts.listenable(),
          builder: (context, accountBox, _) {
            final bankAccounts = accountBox.values
                .where((account) =>
                    account.active &&
                    account.accountType == 'asset' &&
                    account.currencyCode == 'INR')
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name));
            if (_accountId == null ||
                !bankAccounts.any((account) => account.id == _accountId)) {
              _accountId = bankAccounts.isEmpty ? null : bankAccounts.first.id;
            }
            return ValueListenableBuilder<Box<dynamic>>(
              valueListenable: settings.listenable(
                keys: [FinanceBankReconciliationService.storageKey],
              ),
              builder: (context, _, __) {
                final lines = _accountId == null
                    ? <Map<String, dynamic>>[]
                    : _service.lines(accountId: _accountId);
                final matched = lines
                    .where((line) => line['status'] == 'matched')
                    .length;
                final unmatched = lines.length - matched;
                final matchedNet = lines
                    .where((line) => line['status'] == 'matched')
                    .fold<int>(
                      0,
                      (sum, line) => sum + (line['amountPaise'] as int),
                    );
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    DropdownButtonFormField<String>(
                      value: _accountId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Bank / wallet ledger account',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final account in bankAccounts)
                          DropdownMenuItem(
                            value: account.id,
                            child: Text(account.name),
                          ),
                      ],
                      onChanged: (value) => setState(() => _accountId = value),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _accountId == null || _importing
                                ? null
                                : _importStatement,
                            icon: _importing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.upload_file_outlined),
                            label: Text(_importing ? 'Importing...' : 'Import CSV'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'CSV columns: Date, Description, Reference (optional), Debit, Credit. '
                      'Alternatively use Date, Description, Reference, Amount; deposits are positive and withdrawals are negative. '
                      'Duplicate statement files are rejected.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: _summary('Statement lines', '${lines.length}')),
                                Expanded(child: _summary('Matched', '$matched')),
                                Expanded(child: _summary('Unmatched', '$unmatched')),
                              ],
                            ),
                            const Divider(height: 24),
                            Row(
                              children: [
                                const Expanded(child: Text('Net matched amount')),
                                Text(
                                  _money(matchedNet),
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Imported statement lines',
                        style: Theme.of(context).textTheme.titleMedium),
                    if (lines.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text('No statement lines imported for this account.'),
                        ),
                      ),
                    for (final line in lines)
                      Card(
                        child: ListTile(
                          title: Text(
                            (line['description'] as String?)?.isNotEmpty == true
                                ? line['description'] as String
                                : (line['reference'] as String?)?.isNotEmpty == true
                                    ? line['reference'] as String
                                    : 'Statement transaction',
                          ),
                          subtitle: Text(
                            '${DateFormat('dd MMM yyyy').format(DateTime.parse(line['date'] as String))}'
                            '${(line['reference'] as String?)?.isNotEmpty == true ? ' • ${line['reference']}' : ''}'
                            ' • ${line['status'] == 'matched' ? 'Matched' : 'Unmatched'}',
                          ),
                          isThreeLine: true,
                          trailing: SizedBox(
                            width: 132,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _money(line['amountPaise'] as int),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: (line['amountPaise'] as int) >= 0
                                        ? Theme.of(context).colorScheme.tertiary
                                        : Theme.of(context).colorScheme.error,
                                  ),
                                ),
                                TextButton(
                                  onPressed: line['status'] == 'matched'
                                      ? () => _unmatch(line)
                                      : () => _match(line),
                                  child: Text(
                                    line['status'] == 'matched' ? 'Unmatch' : 'Match',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _summary(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
