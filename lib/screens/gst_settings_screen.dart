import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import '../widgets/responsive_page.dart';
import '../widgets/settings_components.dart';

class GstSettingsScreen extends StatefulWidget {
  const GstSettingsScreen({super.key});

  @override
  State<GstSettingsScreen> createState() => _GstSettingsScreenState();
}

class _GstSettingsScreenState extends State<GstSettingsScreen> {
  late final Box<dynamic> _settings;
  late bool _gstEnabled;
  late bool _gstInclusive;
  late bool _defaultInterstate;
  late String _registrationType;
  late String _stateCode;
  late final TextEditingController _defaultRate;
  bool _saving = false;
  bool _dirty = false;

  static const _states = <String, String>{
    '01': 'Jammu and Kashmir',
    '02': 'Himachal Pradesh',
    '03': 'Punjab',
    '04': 'Chandigarh',
    '05': 'Uttarakhand',
    '06': 'Haryana',
    '07': 'Delhi',
    '08': 'Rajasthan',
    '09': 'Uttar Pradesh',
    '10': 'Bihar',
    '11': 'Sikkim',
    '12': 'Arunachal Pradesh',
    '13': 'Nagaland',
    '14': 'Manipur',
    '15': 'Mizoram',
    '16': 'Tripura',
    '17': 'Meghalaya',
    '18': 'Assam',
    '19': 'West Bengal',
    '20': 'Jharkhand',
    '21': 'Odisha',
    '22': 'Chhattisgarh',
    '23': 'Madhya Pradesh',
    '24': 'Gujarat',
    '26': 'Dadra and Nagar Haveli and Daman and Diu',
    '27': 'Maharashtra',
    '28': 'Andhra Pradesh (old code)',
    '29': 'Karnataka',
    '30': 'Goa',
    '31': 'Lakshadweep',
    '32': 'Kerala',
    '33': 'Tamil Nadu',
    '34': 'Puducherry',
    '35': 'Andaman and Nicobar Islands',
    '36': 'Telangana',
    '37': 'Andhra Pradesh',
    '38': 'Ladakh',
  };

  @override
  void initState() {
    super.initState();
    _settings = Hive.box<dynamic>('app_settings');
    _registrationType = _settings
        .get('gst_registration_type', defaultValue: 'regular')
        .toString();
    if (!const ['regular', 'composition', 'unregistered']
        .contains(_registrationType)) {
      _registrationType = 'regular';
    }
    _gstEnabled = _settings.get('gst_enabled', defaultValue: false) as bool;
    _gstInclusive =
        _settings.get('gst_price_inclusive', defaultValue: false) as bool;
    _defaultInterstate = _settings.get('gst_default_interstate_sale',
        defaultValue: false) as bool;
    _stateCode =
        _settings.get('business_state_code', defaultValue: '32').toString();
    if (!_states.containsKey(_stateCode)) _stateCode = '32';
    if (_registrationType != 'regular') _gstEnabled = false;
    _defaultRate = TextEditingController(
      text: (_settings.get('gst_rate', defaultValue: 0.0) as num).toString(),
    )..addListener(_markDirty);
  }

  void _markDirty() {
    if (mounted) setState(() => _dirty = true);
  }

  void _change(VoidCallback update) {
    setState(() {
      update();
      _dirty = true;
    });
  }

  @override
  void dispose() {
    _defaultRate.removeListener(_markDirty);
    _defaultRate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rate = double.tryParse(_defaultRate.text.trim());
    if (rate == null || rate < 0 || rate > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter a valid default GST rate from 0 to 100.')),
      );
      return;
    }
    if (_registrationType != 'regular' && _gstEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Tax invoices require regular GST registration.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _settings.putAll({
        'gst_registration_type': _registrationType,
        'gst_enabled': _registrationType == 'regular' && _gstEnabled,
        'gst_price_inclusive': _gstInclusive,
        'gst_rate': rate,
        'business_state_code': _stateCode,
        'gst_default_interstate_sale': _defaultInterstate,
      });
      if (!mounted) return;
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'GST settings saved. Verify rates before invoicing.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    final isRegular = _registrationType == 'regular';
    final rate = double.tryParse(_defaultRate.text.trim()) ?? 0;
    const sampleBase = 1000.0;
    final sampleTax = sampleBase * rate / 100;
    final displayedTax = _gstInclusive ? sampleBase - sampleBase / (1 + rate / 100) : sampleTax;
    final displayedTotal = _gstInclusive ? sampleBase : sampleBase + sampleTax;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && _dirty && await confirmDiscardChanges(context) && context.mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('GST Settings')),
        body: ResponsivePage(
          maxWidth: 850,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              SettingsSection(
                title: 'Registration',
                subtitle: 'Set your GST profile and business state.',
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _registrationType,
                      decoration: _decoration('GST registration type', Icons.business_outlined),
                      items: const [
                        DropdownMenuItem(value: 'regular', child: Text('Regular GST taxpayer')),
                        DropdownMenuItem(value: 'composition', child: Text('Composition scheme')),
                        DropdownMenuItem(value: 'unregistered', child: Text('Not GST registered')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        _change(() {
                          _registrationType = value;
                          if (value != 'regular') _gstEnabled = false;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _stateCode,
                      decoration: _decoration('Business state / UT', Icons.location_on_outlined),
                      items: _states.entries.map((entry) => DropdownMenuItem(
                        value: entry.key, child: Text('${entry.key} — ${entry.value}'),
                      )).toList(),
                      onChanged: (value) { if (value != null) _change(() => _stateCode = value); },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Seller GSTIN state code must match this state.',
                        style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SettingsSection(
                title: 'Billing behaviour',
                subtitle: 'Set how GST is applied.',
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable GST calculations'),
                      subtitle: Text(isRegular
                        ? 'Allow GST to be applied during billing.'
                        : 'Available only for regular GST registration.'),
                      value: _gstEnabled && isRegular,
                      onChanged: isRegular ? (value) => _change(() => _gstEnabled = value) : null,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Catalogue prices include GST'),
                      subtitle: const Text('Can be changed on each bill.'),
                      value: _gstInclusive,
                      onChanged: (value) => _change(() => _gstInclusive = value),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Default to interstate sale (IGST)'),
                      subtitle: const Text('Default only. Check place of supply per sale.'),
                      value: _defaultInterstate,
                      onChanged: (value) => _change(() => _defaultInterstate = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SettingsSection(
                title: 'Tax defaults',
                subtitle: 'Used when a product has no GST rate.',
                child: Column(
                  children: [
                    TextFormField(
                      controller: _defaultRate,
                      enabled: _gstEnabled && isRegular,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _decoration('Fallback GST rate (%)', Icons.percent),
                    ),
                    const SizedBox(height: 8),
                    Text('Product GST rates and HSN codes override these defaults.',
                      style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SettingsSection(
                title: 'Example calculation',
                subtitle: 'Example using ₹1,000 taxable value.',
                child: Column(
                  children: [
                    _previewRow('Taxable value', '₹${sampleBase.toStringAsFixed(2)}'),
                    _previewRow('GST rate', '${rate.toStringAsFixed(2)}%'),
                    _previewRow('GST portion', '₹${displayedTax.toStringAsFixed(2)}'),
                    const Divider(height: 18),
                    _previewRow('Example total', '₹${displayedTotal.toStringAsFixed(2)}', emphasize: true),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_gstInclusive ? 'GST is included in the sample price.' : 'GST is added to the sample taxable value.',
                        style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const SettingsSection(
                title: 'Compliance note',
                child: Text('Billit does not certify GST compliance or file returns. Composition taxpayers must not collect GST separately. Verify HSN/SAC, rates and filing obligations with a tax professional.'),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SettingsSaveBar(
          dirty: _dirty, saving: _saving, onSave: _save, saveLabel: 'Save GST settings',
        ),
      ),
    );
  }

  Widget _previewRow(String label, String value, {bool emphasize = false}) {
    final style = Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: emphasize ? style?.copyWith(fontWeight: FontWeight.w700) : style)),
          Text(value, style: emphasize ? style?.copyWith(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary) : style),
        ],
      ),
    );
  }
}
