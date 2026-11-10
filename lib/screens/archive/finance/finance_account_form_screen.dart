import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/finance_ledger_service.dart';
import '../../../widgets/responsive_page.dart';

class FinanceAccountFormScreen extends StatefulWidget {
  const FinanceAccountFormScreen({super.key, this.account});

  final FinanceAccount? account;

  @override
  State<FinanceAccountFormScreen> createState() =>
      _FinanceAccountFormScreenState();
}

class _FinanceAccountFormScreenState extends State<FinanceAccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _currency;
  late final TextEditingController _openingBalance;
  String _type = 'asset';
  String? _parentId;
  bool _active = true;
  bool _saving = false;

  bool get _isEditing => widget.account != null;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _name = TextEditingController(text: account?.name ?? '');
    _currency = TextEditingController(text: account?.currencyCode ?? 'INR');
    _openingBalance = TextEditingController();
    _type = account?.accountType ?? 'asset';
    _parentId = account?.parentId;
    _active = account?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _currency.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  int? _parsePaise(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 0;
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    final whole = int.tryParse(parts.first);
    if (whole == null) return null;
    final fraction = parts.length == 1
        ? 0
        : int.parse(parts[1].padRight(2, '0'));
    return whole * 100 + fraction;
  }

  bool _createsParentCycle(
    Box<FinanceAccount> accounts,
    String? parentId,
    String? accountId,
  ) {
    final visited = <String>{};
    var currentId = parentId;
    while (currentId != null) {
      if (currentId == accountId || !visited.add(currentId)) return true;
      currentId = accounts.get(currentId)?.parentId;
    }
    return false;
  }

  Future<void> _save(Box<FinanceAccount> accounts) async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final name = _name.text.trim();
    final currency = _currency.text.trim().toUpperCase();
    if (currency != 'INR') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only INR is supported by the current paise ledger.')),
      );
      return;
    }
    final openingPaise = _parsePaise(_openingBalance.text);
    if (openingPaise == null) return;
    if (widget.account == null &&
        openingPaise > 0 &&
        _type != 'asset' &&
        _type != 'liability') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening balances are supported only for asset and liability accounts.'),
        ),
      );
      return;
    }

    final duplicate = accounts.values.any((item) =>
        item.id != widget.account?.id &&
        item.name.trim().toLowerCase() == name.toLowerCase());
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An account with this name already exists.')),
      );
      return;
    }

    final existing = widget.account;
    final accountPostings =
        Hive.box<FinancePosting>(Boxes.financePostings).values;
    final hasPostings = existing != null &&
        accountPostings.any((line) => line.accountId == existing.id);
    final hasActiveChildren = existing != null &&
        accounts.values.any(
          (account) => account.parentId == existing.id && account.active,
        );
    if (existing != null &&
        existing.currencyCode != currency &&
        hasPostings) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Currency cannot change after journal postings exist.'),
        ),
      );
      return;
    }
    if (existing != null &&
        existing.accountType != _type &&
        (hasPostings || hasActiveChildren)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account type cannot change while postings or active child accounts exist.'),
        ),
      );
      return;
    }
    if (_createsParentCycle(accounts, _parentId, existing?.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This parent selection would create an account hierarchy cycle.')),
      );
      return;
    }
    if (_parentId != null && accounts.get(_parentId)?.accountType != _type) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Parent and child accounts must have the same account type.')),
      );
      return;
    }

    setState(() => _saving = true);
    String? createdId;
    try {
      if (existing == null) {
        final id = const Uuid().v4();
        createdId = id;
        await accounts.put(
          id,
          FinanceAccount(
            id: id,
            name: name,
            accountType: _type,
            parentId: _parentId,
            currencyCode: currency,
            active: _active,
          ),
        );

        if (openingPaise > 0) {
          final transactionId = 'finance:opening:$id';
          final openingEquity = 'system:opening-equity';
          final debitAccount =
              _type == 'asset' ? id : openingEquity;
          final creditAccount =
              _type == 'asset' ? openingEquity : id;
          await FinanceLedgerService().postTransaction(
            transaction: FinanceTransaction(
              id: transactionId,
              transactionNumber: 'OPEN-$id',
              transactionType: 'opening_balance',
              memo: 'Opening balance for $name',
              sourceType: 'account_opening',
              sourceId: id,
            ),
            postings: [
              FinancePosting(
                id: '$transactionId:debit',
                transactionId: transactionId,
                accountId: debitAccount,
                debitPaise: openingPaise,
              ),
              FinancePosting(
                id: '$transactionId:credit',
                transactionId: transactionId,
                accountId: creditAccount,
                creditPaise: openingPaise,
              ),
            ],
            accountsBox: accounts,
            transactionsBox:
                Hive.box<FinanceTransaction>(Boxes.financeTransactions),
            postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
            categoriesBox:
                Hive.box<FinanceCategory>(Boxes.financeCategories),
            partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
          );
        }
      } else {
        existing
          ..name = name
          ..accountType = _type
          ..parentId = _parentId
          ..currencyCode = currency
          ..active = _active;
        await accounts.put(existing.id, existing);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (createdId != null) {
        try {
          final hasJournal = Hive.box<FinanceTransaction>(
            Boxes.financeTransactions,
          ).values.any((item) =>
              item.sourceType == 'account_opening' && item.sourceId == createdId);
          final hasOrphanPostings = Hive.box<FinancePosting>(
            Boxes.financePostings,
          ).values.any((line) =>
              line.accountId == createdId ||
              line.transactionId == 'finance:opening:$createdId');
          if (!hasJournal && !hasOrphanPostings) {
            await accounts.delete(createdId);
          }
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save account: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffolResponsivePage(child: Scaffold((
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit account' : 'New account'),
      ),
      body: ValueListenableBuilder<Box<FinanceAccount>>(
        valueListenable:
            Hive.box<FinanceAccount>(Boxes.financeAccounts).listenable(),
        builder: (context, accounts, _) {
          final parents = accounts.values
              .where((item) =>
                  item.active &&
                  item.accountType == _type &&
                  item.id != widget.account?.id)
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          final accountPostings =
              Hive.box<FinancePosting>(Boxes.financePostings).values;
          final hasPostings = widget.account != null &&
              accountPostings.any(
                (line) => line.accountId == widget.account!.id,
              );
          final hasActiveChildren = widget.account != null &&
              accounts.values.any(
                (item) =>
                    item.parentId == widget.account!.id && item.active,
              );

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Account name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Enter an account name'
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(
                    labelText: 'Account type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'asset', child: Text('Asset')),
                    DropdownMenuItem(value: 'liability', child: Text('Liability')),
                    DropdownMenuItem(value: 'equity', child: Text('Equity')),
                    DropdownMenuItem(value: 'income', child: Text('Income')),
                    DropdownMenuItem(value: 'expense', child: Text('Expense')),
                  ],
                  onChanged: _isEditing &&
                          (hasPostings || hasActiveChildren)
                      ? null
                      : (value) => setState(() {
                            _type = value ?? _type;
                            _parentId = null;
                          }),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _parentId,
                  decoration: const InputDecoration(
                    labelText: 'Parent account (optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('No parent'),
                    ),
                    for (final parent in parents)
                      DropdownMenuItem(
                        value: parent.id,
                        child: Text(parent.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _parentId = value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _currency,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 3,
                  decoration: const InputDecoration(
                    labelText: 'Currency code',
                    hintText: 'INR',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      RegExp(r'^[A-Z]{3}$').hasMatch((value ?? '').trim().toUpperCase())
                          ? null
                          : 'Enter a 3-letter currency code',
                ),
                if (!_isEditing) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _openingBalance,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Opening balance (optional)',
                      prefixText: '₹ ',
                      helperText:
                          'Only asset and liability accounts can have an opening balance.',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final parsed = _parsePaise(value ?? '');
                      return parsed == null ? 'Enter a valid amount' : null;
                    },
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active account'),
                  subtitle: hasActiveChildren && _active
                      ? const Text(
                          'Move or archive active child accounts before archiving this parent.',
                        )
                      : null,
                  value: _active,
                  onChanged: (value) {
                    if (!value && hasActiveChildren) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Archive or reassign active child accounts first.',
                          ),
                        ),
                      );
                      return;
                    }
                    setState(() => _active = value);
                  },
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : () => _save(accounts),
                  child: Text(_saving ? 'Saving...' : 'Save account'),
                ),
              ],
            ),
          );
        },
      ),
    ));
  }
}
