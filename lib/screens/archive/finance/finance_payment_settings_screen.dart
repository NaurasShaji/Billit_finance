import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/finance_source_sync_service.dart';
import '../../../widgets/responsive_page.dart';

/// Configures which INR asset account receives each POS payment method.
class FinancePaymentSettingsScreen extends StatefulWidget {
  const FinancePaymentSettingsScreen({super.key});

  @override
  State<FinancePaymentSettingsScreen> createState() =>
      _FinancePaymentSettingsScreenState();
}

class _FinancePaymentSettingsScreenState
    extends State<FinancePaymentSettingsScreen> {
  final Map<String, String?> _selected = {
    'cash': null,
    'card': null,
    'upi': null,
  };
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final raw = Hive.box<dynamic>('app_settings').get(
      FinanceSourceSyncService.paymentAccountSettingsKey,
    );
    if (raw is Map) {
      for (final method in _selected.keys) {
        final id = raw[method]?.toString();
        if (id != null) _selected[method] = id;
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final mapping = <String, String>{};
    for (final method in _selected.keys) {
      final id = _selected[method];
      if (id == null || id.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Select an account for ${method.toUpperCase()} payments.')),
        );
        return;
      }
      mapping[method] = id;
    }

    setState(() => _saving = true);
    try {
      await FinanceSourceSyncService().savePaymentAccountMapping(
        mapping: mapping,
        accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts),
        settingsBox: Hive.box<dynamic>('app_settings'),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('POS payment accounts saved.')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save payment accounts: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsivePage(child: Scaffold(
      appBar: AppBar(title: const Text('POS payment accounts')),
      body: ValueListenableBuilder<Box<FinanceAccount>>(
        valueListenable:
            Hive.box<FinanceAccount>(Boxes.financeAccounts).listenable(),
        builder: (context, accountsBox, _) {
          final accounts = accountsBox.values
              .where((account) =>
                  account.active &&
                  account.accountType == 'asset' &&
                  account.currencyCode == 'INR')
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          if (accounts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Create an active INR cash, bank, or wallet asset account first.'),
              ),
            );
          }
          for (final method in _selected.keys.toList()) {
            if (!accounts.any((account) => account.id == _selected[method])) {
              _selected[method] = method == 'cash'
                  ? (accounts.any((a) => a.id == 'system:cash')
                      ? 'system:cash'
                      : null)
                  : (accounts.any((a) => a.id == 'system:bank')
                      ? 'system:bank'
                      : null);
            }
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Choose where POS receipts are recorded. This affects new journal syncs; existing posted entries are not rewritten.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              for (final method in _selected.keys) ...[
                DropdownButtonFormField<String>(
                  value: _selected[method],
                  decoration: InputDecoration(
                    labelText: switch (method) {
                      'cash' => 'Cash payments',
                      'card' => 'Card payments',
                      _ => 'UPI payments',
                    },
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final account in accounts)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _selected[method] = value),
                ),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving...' : 'Save payment accounts'),
              ),
            ],
          );
        },
      ),
    ));
  }
}
