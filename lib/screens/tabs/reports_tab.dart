import 'package:flutter/material.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../services/boxes.dart';
import '../../services/invoice_service.dart';
import '../../services/invoice_template_service.dart';
import '../../services/whatsapp_service.dart';
import '../../widgets/whatsapp_icon.dart';
import '../edit_invoice_screen.dart';

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  DateTime _dailyAnchor = DateTime.now();
  DateTime _monthlyAnchor = DateTime.now();
  DateTime _yearlyAnchor = DateTime.now();
  late bool _isAdmin;
  final Set<String> _printingSaleIds = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() {
      if (mounted) setState(() {});
    });
    _isAdmin = context.read<AuthService>().isAdmin;
    if (!_isAdmin) {
      _tab.index = 0;
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  DateTime get _currentAnchor {
    switch (_tab.index) {
      case 0:
        return _dailyAnchor;
      case 1:
        return _monthlyAnchor;
      case 2:
        return _yearlyAnchor;
      default:
        return _dailyAnchor;
    }
  }

  void _updateCurrentAnchor(DateTime newValue) {
    switch (_tab.index) {
      case 0:
        setState(() => _dailyAnchor = newValue);
        break;
      case 1:
        setState(() => _monthlyAnchor = newValue);
        break;
      case 2:
        setState(() => _yearlyAnchor = newValue);
        break;
    }
  }

  Future<void> _printSale(Sale sale) async {
    if (_printingSaleIds.contains(sale.id)) return;

    setState(() => _printingSaleIds.add(sale.id));
    final paperSize = InvoiceTemplateService.selected;
    final fullPage = paperSize == 'A4' || paperSize == 'A5';
    try {
      final printed = await InvoiceService().printThermalInvoice(sale);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            printed
                ? (fullPage
                    ? 'Invoice #${sale.id} opened as a $paperSize PDF for printing or sharing.'
                    : 'Invoice #${sale.id} sent to the thermal printer.')
                : 'Could not print invoice. Check the printer connection and try again.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to print invoice: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _printingSaleIds.remove(sale.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sales = Hive.box<Sale>(Boxes.sales).values.toList();
    final expenses = Hive.box<Expense>(Boxes.expenses).values.toList();

    return SingleChildScrollView(
      key: const PageStorageKey<String>('reports-scroll'),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          // Professional Header with Date Navigation
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                  offset: const Offset(0, 2),
                  blurRadius: 8,
                )
              ],
            ),
            child: Column(
              children: [
                // Date Navigation Row
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.3)),
                        ),
                        child: IconButton(
                          tooltip: 'Previous',
                          icon: Icon(Icons.chevron_left,
                              color: theme.colorScheme.primary),
                          onPressed: () =>
                              _updateCurrentAnchor(_previous(_currentAnchor)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.2)),
                          ),
                          child: TextButton.icon(
                            onPressed: _pickPeriod,
                            icon: Icon(Icons.calendar_today,
                                color: theme.colorScheme.primary, size: 20),
                            label: Text(
                              _tab.index == 0
                                  ? DateFormat('dd MMM yyyy')
                                      .format(_dailyAnchor)
                                  : _tab.index == 1
                                      ? DateFormat('MMMM yyyy')
                                          .format(_monthlyAnchor)
                                      : DateFormat('yyyy')
                                          .format(_yearlyAnchor),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.3)),
                        ),
                        child: IconButton(
                          tooltip: 'Next',
                          icon: Icon(Icons.chevron_right,
                              color: theme.colorScheme.primary),
                          onPressed: () =>
                              _updateCurrentAnchor(_next(_currentAnchor)),
                        ),
                      ),
                    ],
                  ),
                ),
                // Professional Tab Bar
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    controller: _tab,
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                    unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 14),
                    labelColor: Colors
                        .white, // Make selected tab text white for contrast
                    unselectedLabelColor: theme.colorScheme
                        .onSurface, // Make unselected tab text visible
                    indicator: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    tabs: _isAdmin
                        ? const [
                            Tab(text: 'Daily'),
                            Tab(text: 'Monthly'),
                            Tab(text: 'Yearly'),
                          ]
                        : const [
                            Tab(text: 'Daily'),
                          ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          if (_tab.index == 0 || !_isAdmin)
            _buildDaily(sales, expenses)
          else if (_tab.index == 1)
            _buildMonthly(sales, expenses)
          else
            _buildYearly(sales, expenses),
        ],
      ),
    );
  }

  Widget _card(String title, String value, IconData icon,
      {bool isNet = false}) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            offset: const Offset(0, 2),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isNet
                    ? (value.contains('-')
                        ? Colors.red.shade50
                        : Colors.green.shade50)
                    : theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isNet
                    ? (value.contains('-')
                        ? Colors.red.shade700
                        : Colors.green.shade700)
                    : theme.colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isNet && value.contains('-')
                          ? Colors.red.shade700
                          : theme.colorScheme.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, {String? subtitle}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: theme.colorScheme.onSurface,
              letterSpacing: -0.3,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _empty() {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 48,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No data available',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Data will appear here once transactions are recorded',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentBreakdown(List<Sale> periodSales, NumberFormat currency) {
    final totals = <PaymentMethod, double>{PaymentMethod.cash: 0, PaymentMethod.card: 0, PaymentMethod.upi: 0};
    final counts = <PaymentMethod, int>{PaymentMethod.cash: 0, PaymentMethod.card: 0, PaymentMethod.upi: 0};
    for (final sale in periodSales) {
      totals[sale.payment] = (totals[sale.payment] ?? 0) + sale.totalAmount;
      counts[sale.payment] = (counts[sale.payment] ?? 0) + 1;
    }
    final total = totals.values.fold<double>(0, (sum, value) => sum + value);
    final methods = <(PaymentMethod, String, IconData)>[
      (PaymentMethod.cash, 'Cash', Icons.payments_outlined),
      (PaymentMethod.card, 'Card', Icons.credit_card_outlined),
      (PaymentMethod.upi, 'UPI', Icons.qr_code_2),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Payment Method Breakdown', subtitle: 'Collected by payment method'),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(children: [
              for (var i = 0; i < methods.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(methods[i].$3),
                  title: Text(methods[i].$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${counts[methods[i].$1] ?? 0} transaction(s) · ${total > 0 ? ((totals[methods[i].$1] ?? 0) / total * 100).toStringAsFixed(1) : '0.0'}%'),
                  trailing: Text(currency.format(totals[methods[i].$1] ?? 0), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Total collected', style: TextStyle(fontWeight: FontWeight.w700)),
                trailing: Text(currency.format(total), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildDaily(List<Sale> sales, List<Expense> expenses) {
    final cur = NumberFormat.simpleCurrency(locale: 'en_IN');
    final daySales =
        sales.where((s) => _isSameDay(s.date, _dailyAnchor)).toList();
    final dayExpenses =
        expenses.where((e) => _isSameDay(e.date, _dailyAnchor)).toList();

    final revenue = daySales.fold(0.0, (a, s) => a + s.totalAmount);
    final grossProfit = daySales.fold(0.0, (a, s) => a + s.profit);
    final totalExpenses = dayExpenses.fold(0.0, (a, e) => a + e.amount);
    final netProfit = grossProfit - totalExpenses;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            'Daily Overview',
            subtitle: DateFormat('EEEE, MMMM d, yyyy').format(_dailyAnchor),
          ),
          _card('Total Revenue', cur.format(revenue), Icons.trending_up),
          _paymentBreakdown(daySales, cur),
          if (_isAdmin) ...[
            _card('Gross Profit', cur.format(grossProfit),
                Icons.account_balance_wallet),
          ],
          _card('Total Expenses', cur.format(totalExpenses),
              Icons.money_off_outlined),
          if (_isAdmin)
            _card('Net Profit', cur.format(netProfit), Icons.analytics,
                isNet: true),
          _card('Total Invoices', '${daySales.length}',
              Icons.receipt_long_outlined),
          if (daySales.isNotEmpty) ...[
            _sectionHeader('Today\'s Transactions'),
            ...daySales.map((sale) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.06),
                        offset: const Offset(0, 1),
                        blurRadius: 8,
                      ),
                    ],
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withValues(alpha: 0.1),
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 520;
                      final colors = Theme.of(context).colorScheme;
                      final amount = Text(
                        cur.format(sale.totalAmount),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: colors.primary,
                        ),
                      );
                      final whatsappButton = IconButton(
                        tooltip: 'Send on WhatsApp',
                        visualDensity: VisualDensity.compact,
                        constraints:
                            const BoxConstraints.tightFor(width: 44, height: 44),
                        icon: const WhatsAppIcon(size: 24),
                        onPressed: () =>
                            WhatsAppService.sendInvoice(context, sale),
                      );
                      final printButton = IconButton(
                        tooltip: 'Print invoice',
                        visualDensity: VisualDensity.compact,
                        constraints:
                            const BoxConstraints.tightFor(width: 44, height: 44),
                        onPressed: _printingSaleIds.contains(sale.id)
                            ? null
                            : () => _printSale(sale),
                        icon: _printingSaleIds.contains(sale.id)
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print_outlined),
                      );

                      if (compact) {
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => EditInvoiceScreen(
                                  sale: sale,
                                  isViewOnly: true,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Invoice #${sale.id}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    amount,
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  DateFormat('hh:mm a').format(sale.date),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Divider(height: 1, color: colors.outlineVariant),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [whatsappButton, printButton],
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.receipt, color: colors.primary),
                        ),
                        title: Text(
                          'Invoice #${sale.id}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          DateFormat('hh:mm a').format(sale.date),
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [amount, whatsappButton, printButton],
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => EditInvoiceScreen(
                                sale: sale,
                                isViewOnly: true,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                )),
          ],
          if (daySales.isEmpty && dayExpenses.isEmpty) _empty(),
        ],
      ),
    );
  }

  Widget _buildMonthly(List<Sale> sales, List<Expense> expenses) {
    final cur = NumberFormat.simpleCurrency(locale: 'en_IN');
    final m = DateTime(_monthlyAnchor.year, _monthlyAnchor.month);
    final mSales = sales.where((s) => _isSameMonth(s.date, m)).toList();
    final mExpenses = expenses.where((e) => _isSameMonth(e.date, m)).toList();

    final revenue = mSales.fold(0.0, (a, s) => a + s.totalAmount);
    final grossProfit = mSales.fold(0.0, (a, s) => a + s.profit);
    final totalExpenses = mExpenses.fold(0.0, (a, e) => a + e.amount);
    final netProfit = grossProfit - totalExpenses;

    final productStats = <String, Map<String, dynamic>>{};
    for (final sale in mSales) {
      for (final item in sale.items) {
        final productName = item.productName;
        if (productStats.containsKey(productName)) {
          productStats[productName]!['totalQuantity'] =
              (productStats[productName]!['totalQuantity'] as double) +
                  item.quantity;
          productStats[productName]!['totalRevenue'] =
              (productStats[productName]!['totalRevenue'] as double) +
                  item.totalAmount;
          productStats[productName]!['totalProfit'] =
              (productStats[productName]!['totalProfit'] as double) +
                  item.profit;
        } else {
          productStats[productName] = {
            'productName': productName,
            'totalQuantity': item.quantity,
            'totalRevenue': item.totalAmount,
            'totalProfit': item.profit,
          };
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            'Monthly Overview',
            subtitle: DateFormat('MMMM yyyy').format(_monthlyAnchor),
          ),
          _card('Total Revenue', cur.format(revenue), Icons.trending_up),
          _paymentBreakdown(mSales, cur),
          _card('Gross Profit', cur.format(grossProfit),
              Icons.account_balance_wallet),
          _card('Total Expenses', cur.format(totalExpenses),
              Icons.money_off_outlined),
          _card('Net Profit', cur.format(netProfit), Icons.analytics,
              isNet: true),
          _card('Total Invoices', '${mSales.length}',
              Icons.receipt_long_outlined),
          if (productStats.isNotEmpty) ...[
            _sectionHeader('Product Performance'),
            ...productStats.entries.map((entry) {
              final stats = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.06),
                      offset: const Offset(0, 2),
                      blurRadius: 12,
                    ),
                  ],
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.1),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.inventory_2_outlined,
                              color: Theme.of(context).colorScheme.secondary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              stats['productName'] ?? 'Unknown Product',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetric(
                              'Quantity Sold',
                              '${(stats['totalQuantity'] ?? 0.0).toStringAsFixed(1)}',
                              Icons.shopping_cart_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetric(
                              'Revenue',
                              cur.format(stats['totalRevenue'] ?? 0.0),
                              Icons.attach_money,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildMetric(
                        'Profit',
                        cur.format(stats['totalProfit'] ?? 0.0),
                        Icons.trending_up,
                        color: Colors.green,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
          if (mSales.isEmpty && mExpenses.isEmpty) _empty(),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value, IconData icon,
      {Color? color}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (color ?? theme.colorScheme.primary).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: color ?? theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color ?? theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearly(List<Sale> sales, List<Expense> expenses) {
    final cur = NumberFormat.simpleCurrency(locale: 'en_IN');
    final y = _yearlyAnchor.year;
    final ySales = sales.where((s) => s.date.year == y).toList();
    final yExpenses = expenses.where((e) => e.date.year == y).toList();

    final revenue = ySales.fold(0.0, (a, s) => a + s.totalAmount);
    final grossProfit = ySales.fold(0.0, (a, s) => a + s.profit);
    final totalExpenses = yExpenses.fold(0.0, (a, e) => a + e.amount);
    final netProfit = grossProfit - totalExpenses;

    final productStats = <String, Map<String, dynamic>>{};
    for (final sale in ySales) {
      for (final item in sale.items) {
        final productName = item.productName;
        if (productStats.containsKey(productName)) {
          productStats[productName]!['totalQuantity'] =
              (productStats[productName]!['totalQuantity'] as double) +
                  item.quantity;
          productStats[productName]!['totalRevenue'] =
              (productStats[productName]!['totalRevenue'] as double) +
                  item.totalAmount;
          productStats[productName]!['totalProfit'] =
              (productStats[productName]!['totalProfit'] as double) +
                  item.profit;
        } else {
          productStats[productName] = {
            'productName': productName,
            'totalQuantity': item.quantity,
            'totalRevenue': item.totalAmount,
            'totalProfit': item.profit,
          };
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            'Yearly Overview',
            subtitle: '${_yearlyAnchor.year}',
          ),
          _card('Total Revenue', cur.format(revenue), Icons.trending_up),
          _paymentBreakdown(ySales, cur),
          _card('Gross Profit', cur.format(grossProfit),
              Icons.account_balance_wallet),
          _card('Total Expenses', cur.format(totalExpenses),
              Icons.money_off_outlined),
          _card('Net Profit', cur.format(netProfit), Icons.analytics,
              isNet: true),
          _card('Total Invoices', '${ySales.length}',
              Icons.receipt_long_outlined),
          if (productStats.isNotEmpty) ...[
            _sectionHeader('Annual Product Performance'),
            ...productStats.entries.map((entry) {
              final stats = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.06),
                      offset: const Offset(0, 2),
                      blurRadius: 12,
                    ),
                  ],
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.1),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.inventory_2_outlined,
                              color: Theme.of(context).colorScheme.secondary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              stats['productName'] ?? 'Unknown Product',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetric(
                              'Quantity Sold',
                              '${(stats['totalQuantity'] ?? 0.0).toStringAsFixed(1)}',
                              Icons.shopping_cart_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetric(
                              'Revenue',
                              cur.format(stats['totalRevenue'] ?? 0.0),
                              Icons.attach_money,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildMetric(
                        'Profit',
                        cur.format(stats['totalProfit'] ?? 0.0),
                        Icons.trending_up,
                        color: Colors.green,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
          if (ySales.isEmpty && yExpenses.isEmpty) _empty(),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isSameMonth(DateTime a, DateTime m) =>
      a.year == m.year && a.month == m.month;

  DateTime _previous(DateTime d) {
    if (_tab.index == 0) {
      return d.subtract(const Duration(days: 1));
    } else if (_tab.index == 1) {
      final y = d.year;
      final m = d.month == 1 ? 12 : d.month - 1;
      final ny = d.month == 1 ? y - 1 : y;
      return DateTime(ny, m, 1);
    } else {
      return DateTime(d.year - 1, 1, 1);
    }
  }

  DateTime _next(DateTime d) {
    if (_tab.index == 0) {
      return d.add(const Duration(days: 1));
    } else if (_tab.index == 1) {
      final y = d.year;
      final m = d.month == 12 ? 1 : d.month + 1;
      final ny = d.month == 12 ? y + 1 : y;
      return DateTime(ny, m, 1);
    } else {
      return DateTime(d.year + 1, 1, 1);
    }
  }

  Future<void> _pickPeriod() async {
    if (_tab.index == 0) {
      final picked = await showDatePicker(
        context: context,
        initialDate: _dailyAnchor,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked != null) _updateCurrentAnchor(picked);
    } else if (_tab.index == 1 && _isAdmin) {
      final picked = await _showMonthYearPicker(
        context: context,
        initialYear: _monthlyAnchor.year,
        initialMonth: _monthlyAnchor.month,
      );
      if (picked != null) _updateCurrentAnchor(picked);
    } else if (_tab.index == 2 && _isAdmin) {
      final selected = await showDialog<int>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Select year'),
            content: SizedBox(
              width: 300,
              height: 300,
              child: YearPicker(
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDate: DateTime(_yearlyAnchor.year),
                selectedDate: DateTime(_yearlyAnchor.year),
                onChanged: (date) => Navigator.of(ctx).pop(date.year),
              ),
            ),
          );
        },
      );
      if (selected != null) _updateCurrentAnchor(DateTime(selected, 1, 1));
    }
  }

  Future<DateTime?> _showMonthYearPicker({
    required BuildContext context,
    required int initialYear,
    required int initialMonth,
  }) async {
    return showDialog<DateTime>(
      context: context,
      builder: (ctx) {
        int selectedYear = initialYear;
        int selectedMonth = initialMonth;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Select month and year'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 200,
                      child: YearPicker(
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialDate: DateTime(selectedYear),
                        selectedDate: DateTime(selectedYear),
                        onChanged: (date) {
                          setStateDialog(() {
                            selectedYear = date.year;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(12, (i) {
                        final m = i + 1;
                        final isSelected = m == selectedMonth;
                        return ChoiceChip(
                          label: Text(
                              DateFormat('MMM').format(DateTime(2000, m, 1))),
                          selected: isSelected,
                          onSelected: (_) {
                            setStateDialog(() {
                              selectedMonth = m;
                            });
                          },
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx)
                        .pop(DateTime(selectedYear, selectedMonth, 1));
                  },
                  child: const Text('Select'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
