import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/finance_party_service.dart';
import 'finance_ageing_screen.dart';
import 'finance_party_statement_screen.dart';
import 'finance_payment_allocation_screen.dart';

class FinancePartiesScreen extends StatefulWidget {
  const FinancePartiesScreen({super.key});

  @override
  State<FinancePartiesScreen> createState() => _FinancePartiesScreenState();
}

class _FinancePartiesScreenState extends State<FinancePartiesScreen> {
  String _filter = 'customer';

  String _money(int paise) =>
      NumberFormat.simpleCurrency(locale: 'en_IN').format(paise.abs() / 100);

  String _balanceLabel(String partyType, int paise) {
    if (paise == 0) return _money(0);
    if (partyType == 'customer') {
      return paise > 0
          ? 'Due ${_money(paise)}'
          : 'Customer credit ${_money(paise)}';
    }
    return paise > 0
        ? 'Due ${_money(paise)}'
        : 'Advance ${_money(paise)}';
  }

  Future<void> _openForm([FinanceParty? party]) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FinancePartyFormScreen(party: party),
      ),
    );
  }

  Future<void> _archive(
    FinanceParty party,
    Iterable<FinanceTransaction> transactions,
    Iterable<FinancePosting> postings,
  ) async {
    try {
      await FinancePartyService().archiveParty(
        partyId: party.id,
        transactions: transactions,
        postings: postings,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not archive party: $error')),
        );
      }
    }
  }

  Future<void> _reactivate(FinanceParty party) async {
    final box = Hive.box<FinanceParty>(Boxes.financeParties);
    await box.put(
      party.id,
      FinanceParty(
        id: party.id,
        name: party.name,
        partyType: party.partyType,
        phone: party.phone,
        email: party.email,
        taxIdentifier: party.taxIdentifier,
        active: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers & suppliers'),
        actions: [
          IconButton(
            tooltip: 'Receivables / payables ageing',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const FinanceAgeingScreen(),
              ),
            ),
            icon: const Icon(Icons.analytics_outlined),
          ),
          IconButton(
            tooltip: 'Allocate payments to invoices',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const FinancePaymentAllocationScreen(),
              ),
            ),
            icon: const Icon(Icons.link),
          ),
          IconButton(
            tooltip: 'Add party',
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<FinanceParty>>(
        valueListenable:
            Hive.box<FinanceParty>(Boxes.financeParties).listenable(),
        builder: (context, partiesBox, _) =>
            ValueListenableBuilder<Box<FinanceTransaction>>(
          valueListenable: Hive.box<FinanceTransaction>(
            Boxes.financeTransactions,
          ).listenable(),
          builder: (context, transactionsBox, __) =>
              ValueListenableBuilder<Box<FinancePosting>>(
            valueListenable:
                Hive.box<FinancePosting>(Boxes.financePostings).listenable(),
            builder: (context, postingsBox, ___) {
              final parties = partiesBox.values
                  .where((party) => party.partyType == _filter)
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));
              final service = FinancePartyService();
              var totalOutstanding = 0;
              for (final party in parties.where((item) => item.active)) {
                totalOutstanding += service.balancePaise(
                  party: party,
                  transactions: transactionsBox.values,
                  postings: postingsBox.values,
                );
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: 'customer',
                        label: Text('Customers'),
                      ),
                      ButtonSegment(
                        value: 'supplier',
                        label: Text('Suppliers'),
                      ),
                      ButtonSegment(value: 'other', label: Text('Other')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (value) =>
                        setState(() => _filter = value.first),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: ListTile(
                      title: Text(
                        _filter == 'customer'
                            ? 'Receivables outstanding'
                            : _filter == 'supplier'
                                ? 'Payables outstanding'
                                : 'Other parties',
                      ),
                      trailing: Text(
                        _filter == 'other'
                            ? '—'
                            : _balanceLabel(_filter, totalOutstanding),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: totalOutstanding < 0
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (parties.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No parties in this group yet.'),
                    ),
                  for (final party in parties)
                    Card(
                      child: ListTile(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => FinancePartyStatementScreen(party: party),
                          ),
                        ),
                        title: Text(party.name),
                        subtitle: Text(
                          [
                            if (party.phone.isNotEmpty) party.phone,
                            if (party.email.isNotEmpty) party.email,
                            if (party.taxIdentifier.isNotEmpty)
                              'Tax ID: ${party.taxIdentifier}',
                            if (!party.active) 'ARCHIVED',
                          ].join(' • '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_filter != 'other')
                              Text(
                                _balanceLabel(
                                  party.partyType,
                                  service.balancePaise(
                                    party: party,
                                    transactions: transactionsBox.values,
                                    postings: postingsBox.values,
                                  ),
                                ),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  await _openForm(party);
                                } else if (value == 'archive') {
                                  await _archive(
                                    party,
                                    transactionsBox.values,
                                    postingsBox.values,
                                  );
                                } else if (value == 'reactivate') {
                                  await _reactivate(party);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                if (party.active)
                                  const PopupMenuItem(
                                    value: 'archive',
                                    child: Text('Archive'),
                                  )
                                else
                                  const PopupMenuItem(
                                    value: 'reactivate',
                                    child: Text('Reactivate'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class FinancePartyFormScreen extends StatefulWidget {
  const FinancePartyFormScreen({super.key, this.party});

  final FinanceParty? party;

  @override
  State<FinancePartyFormScreen> createState() => _FinancePartyFormScreenState();
}

class _FinancePartyFormScreenState extends State<FinancePartyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _taxIdentifier;
  late String _type;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final party = widget.party;
    _name = TextEditingController(text: party?.name ?? '');
    _phone = TextEditingController(text: party?.phone ?? '');
    _email = TextEditingController(text: party?.email ?? '');
    _taxIdentifier = TextEditingController(text: party?.taxIdentifier ?? '');
    _type = party?.partyType ?? 'customer';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _taxIdentifier.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await FinancePartyService().saveParty(
        id: widget.party?.id,
        name: _name.text,
        partyType: _type,
        phone: _phone.text,
        email: _email.text,
        taxIdentifier: _taxIdentifier.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save party: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPostings = widget.party != null &&
        Hive.box<FinancePosting>(Boxes.financePostings)
            .values
            .any((line) => line.partyId == widget.party!.id);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.party == null ? 'New party' : 'Edit party'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name / business name',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Enter a name'
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(
                labelText: 'Party type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'customer', child: Text('Customer')),
                DropdownMenuItem(value: 'supplier', child: Text('Supplier')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: hasPostings
                  ? null
                  : (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _taxIdentifier,
              decoration: const InputDecoration(
                labelText: 'GSTIN / tax identifier',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving...' : 'Save party'),
            ),
          ],
        ),
      ),
    );
  }
}
