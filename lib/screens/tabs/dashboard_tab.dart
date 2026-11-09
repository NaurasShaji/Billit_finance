import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../services/boxes.dart';
import '../../utils/theme_colors.dart';

/// Time window shown on the overview.
enum _Period {
  today('Today', 'vs yesterday'),
  week('Last 7 days', 'vs previous 7 days'),
  days30('Last 30 days', 'vs previous 30 days'),
  month('This month', 'vs same days last month');

  const _Period(this.label, this.compareLabel);
  final String label;
  final String compareLabel;
}

class _Range {
  const _Range(this.start, this.end);
  final DateTime start; // inclusive
  final DateTime end; // exclusive
  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);
}

class _Totals {
  const _Totals({
    required this.revenue,
    required this.profit,
    required this.bills,
    required this.expenses,
  });
  final double revenue;
  final double profit;
  final int bills;
  final double expenses;
  double get net => profit - expenses;
  double get avgBill => bills == 0 ? 0 : revenue / bills;
}

class _DayRevenue {
  const _DayRevenue(this.day, this.revenue);
  final DateTime day;
  final double revenue;
}

class _Delta {
  const _Delta({required this.percent, required this.isNew, required this.upIsGood});
  final double? percent; // null when there is nothing to compare
  final bool isNew; // previous period was zero, this one is not
  final bool upIsGood;
}

class DashboardTab extends StatefulWidget {
  final bool showFinancials;
  final VoidCallback onOpenBilling;
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenReports;
  final VoidCallback? onOpenFinance;

  const DashboardTab({
    super.key,
    this.showFinancials = true,
    required this.onOpenBilling,
    required this.onOpenProducts,
    required this.onOpenReports,
    this.onOpenFinance,
  });

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  static const _Period _period = _Period.today;

  // Calendar-day arithmetic that is safe across daylight-saving changes.
  static DateTime _day(DateTime d, int offset) =>
      DateTime(d.year, d.month, d.day + offset);

  _Range _currentRange(DateTime today) {
    switch (_period) {
      case _Period.today:
        return _Range(today, _day(today, 1));
      case _Period.week:
        return _Range(_day(today, -6), _day(today, 1));
      case _Period.days30:
        return _Range(_day(today, -29), _day(today, 1));
      case _Period.month:
        return _Range(DateTime(today.year, today.month, 1), _day(today, 1));
    }
  }

  _Range _previousRange(DateTime today) {
    switch (_period) {
      case _Period.today:
        return _Range(_day(today, -1), today);
      case _Period.week:
        return _Range(_day(today, -13), _day(today, -6));
      case _Period.days30:
        return _Range(_day(today, -59), _day(today, -29));
      case _Period.month:
        final prevStart = DateTime(today.year, today.month - 1, 1);
        final prevMonthDays = DateTime(today.year, today.month, 0).day;
        final elapsed = today.day < prevMonthDays ? today.day : prevMonthDays;
        return _Range(
            prevStart, DateTime(prevStart.year, prevStart.month, elapsed + 1));
    }
  }

  _Totals _totals(List<Sale> sales, List<Expense> expenses, _Range range) {
    var revenue = 0.0;
    var profit = 0.0;
    var bills = 0;
    for (final sale in sales) {
      if (range.contains(sale.date)) {
        revenue += sale.totalAmount;
        profit += sale.profit;
        bills++;
      }
    }
    var spent = 0.0;
    for (final expense in expenses) {
      if (range.contains(expense.date)) spent += expense.amount;
    }
    return _Totals(revenue: revenue, profit: profit, bills: bills, expenses: spent);
  }

  _Delta? _delta(double current, double previous, {bool upIsGood = true}) {
    if (previous.abs() < 0.005) {
      if (current.abs() < 0.005) return null;
      return _Delta(percent: null, isNew: true, upIsGood: upIsGood);
    }
    return _Delta(
      percent: (current - previous) / previous.abs() * 100,
      isNew: false,
      upIsGood: upIsGood,
    );
  }

  /// Days shown in the trend chart for the selected period.
  List<DateTime> _trendDays(DateTime today) {
    int count;
    switch (_period) {
      case _Period.today:
      case _Period.week:
        count = 7;
        break;
      case _Period.days30:
        count = 30;
        break;
      case _Period.month:
        count = today.day;
        break;
    }
    return List.generate(count, (i) => _day(today, -(count - 1 - i)));
  }

  String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final settings = Hive.box<dynamic>('app_settings');
    final threshold =
        (settings.get('low_stock_threshold', defaultValue: 10) as num)
            .toDouble();
    final financial = widget.showFinancials;

    return Scaffold(
      body: ValueListenableBuilder<Box<Sale>>(
        valueListenable: Hive.box<Sale>(Boxes.sales).listenable(),
        builder: (context, salesBox, _) => ValueListenableBuilder<Box<Product>>(
          valueListenable: Hive.box<Product>(Boxes.products).listenable(),
          builder: (context, productsBox, __) =>
              ValueListenableBuilder<Box<Expense>>(
            valueListenable: Hive.box<Expense>(Boxes.expenses).listenable(),
            builder: (context, expensesBox, ___) {
              final allSales = salesBox.values.toList()
                ..sort((a, b) => b.date.compareTo(a.date));
              final expenses = expensesBox.values.toList();
              final range = _currentRange(today);
              final previous = _previousRange(today);
              final cur = _totals(allSales, expenses, range);
              final prev = _totals(allSales, expenses, previous);

              final activeProducts =
                  productsBox.values.where((p) => p.active).toList();
              final productNames = {for (final p in productsBox.values) p.id: p};
              final lowStock = activeProducts
                  .where((p) => p.stock <= threshold)
                  .toList()
                ..sort((a, b) => a.stock.compareTo(b.stock));

              // Revenue per calendar day (for the chart).
              final perDay = <DateTime, double>{};
              for (final sale in allSales) {
                final key = DateTime(sale.date.year, sale.date.month, sale.date.day);
                perDay[key] = (perDay[key] ?? 0) + sale.totalAmount;
              }
              final trend = [
                for (final d in _trendDays(today)) _DayRevenue(d, perDay[d] ?? 0),
              ];

              // Payment mix + best sellers for the selected period.
              final byMethod = <PaymentMethod, double>{};
              final byProduct = <String, _Sold>{};
              for (final sale in allSales) {
                if (!range.contains(sale.date)) continue;
                byMethod[sale.payment] =
                    (byMethod[sale.payment] ?? 0) + sale.totalAmount;
                for (final item in sale.items) {
                  final sold = byProduct.putIfAbsent(item.productId, () => _Sold());
                  sold.revenue += item.subtotal;
                  sold.qty += item.qty;
                  sold.unit = item.unitLabel;
                }
              }
              final topProducts = byProduct.entries.toList()
                ..sort((a, b) => b.value.revenue.compareTo(a.value.revenue));

              final periodTitle = _period == _Period.today
                  ? "Today's"
                  : _period == _Period.month
                      ? "This month's"
                      : _period.label;

              final metrics = <Widget>[
                if (financial)
                  _MetricCard(
                    title: '$periodTitle sales',
                    value: currency.format(cur.revenue),
                    subtitle: cur.bills == 0
                        ? 'No bills yet'
                        : '${cur.bills} bill${cur.bills == 1 ? '' : 's'} · avg ${currency.format(cur.avgBill)}',
                    icon: Icons.point_of_sale_outlined,
                    color: theme.colorScheme.primary,
                    delta: _delta(cur.revenue, prev.revenue),
                    compareLabel: _period.compareLabel,
                    onTap: widget.onOpenReports,
                  ),
                if (financial)
                  _MetricCard(
                    title: 'Estimated profit',
                    value: currency.format(cur.profit),
                    subtitle: 'Before expenses',
                    icon: Icons.trending_up_rounded,
                    color: Colors.green.shade700,
                    delta: _delta(cur.profit, prev.profit),
                    compareLabel: _period.compareLabel,
                    onTap: widget.onOpenReports,
                  ),
                if (financial)
                  _MetricCard(
                    title: 'Expenses',
                    value: currency.format(cur.expenses),
                    subtitle: 'Recorded expenses',
                    icon: Icons.account_balance_wallet_outlined,
                    color: Colors.deepOrange.shade600,
                    delta: _delta(cur.expenses, prev.expenses, upIsGood: false),
                    compareLabel: _period.compareLabel,
                    onTap: widget.onOpenFinance,
                  ),
                if (financial)
                  _MetricCard(
                    title: 'Net profit',
                    value: currency.format(cur.net),
                    subtitle: 'Profit minus expenses',
                    icon: Icons.savings_outlined,
                    color: cur.net >= 0
                        ? Colors.teal.shade700
                        : theme.colorScheme.error,
                    delta: _delta(cur.net, prev.net),
                    compareLabel: _period.compareLabel,
                    onTap: widget.onOpenFinance,
                  ),
                if (!financial)
                  _MetricCard(
                    title: '$periodTitle bills',
                    value: cur.bills.toString(),
                    subtitle: 'Saved transactions',
                    icon: Icons.receipt_long_outlined,
                    color: theme.colorScheme.primary,
                    delta: _delta(cur.bills.toDouble(), prev.bills.toDouble()),
                    compareLabel: _period.compareLabel,
                  ),
                if (!financial)
                  _MetricCard(
                    title: 'Active products',
                    value: activeProducts.length.toString(),
                    subtitle: '${lowStock.length} low in stock',
                    icon: Icons.inventory_2_outlined,
                    color: Colors.indigo.shade600,
                    onTap: widget.onOpenProducts,
                  ),
              ];

              final trendPanel = _Panel(
                title: 'Sales trend',
                subtitle: _period == _Period.days30
                    ? 'Daily revenue, last 30 days'
                    : _period == _Period.month
                        ? 'Daily revenue this month'
                        : 'Daily revenue, last 7 days',
                trailing: TextButton(
                    onPressed: widget.onOpenReports,
                    child: const Text('View reports')),
                child: _TrendChart(days: trend, currency: currency, today: today),
              );
              final paymentPanel = _Panel(
                title: 'Payment mix',
                subtitle: _period.label,
                child: _PaymentMix(byMethod: byMethod, currency: currency),
              );
              final topPanel = _Panel(
                title: 'Best sellers',
                subtitle: 'Top items by revenue · ${_period.label.toLowerCase()}',
                child: _TopProducts(
                  entries: topProducts.take(5).toList(),
                  products: productNames,
                  currency: currency,
                ),
              );
              final lowStockPanel = _Panel(
                title: 'Low-stock alerts',
                subtitle:
                    '${activeProducts.length} active products · ${lowStock.length} at or below ${threshold.toStringAsFixed(threshold == threshold.roundToDouble() ? 0 : 1)} units',
                trailing: TextButton(
                    onPressed: widget.onOpenProducts,
                    child: const Text('Inventory')),
                child: lowStock.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline,
                                color: Colors.green.shade700.adaptive(context)),
                            const SizedBox(width: 12),
                            const Expanded(
                                child: Text(
                                    'All active products are above the low-stock threshold.')),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          for (final product in lowStock.take(5))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              onTap: widget.onOpenProducts,
                              leading: CircleAvatar(
                                backgroundColor: theme.colorScheme.errorContainer,
                                foregroundColor:
                                    theme.colorScheme.onErrorContainer,
                                child: const Icon(Icons.inventory_2_outlined),
                              ),
                              title: Text(product.name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(product.category),
                              trailing: Text(
                                '${product.stock.toStringAsFixed(product.stock == product.stock.roundToDouble() ? 0 : 1)} ${product.unit.name}',
                                style: TextStyle(
                                    color: theme.colorScheme.error,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          if (lowStock.length > 5)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: widget.onOpenProducts,
                                child: Text('+${lowStock.length - 5} more'),
                              ),
                            ),
                        ],
                      ),
              );
              final recentPanel = _Panel(
                title: 'Recent bills',
                subtitle: 'Latest saved transactions',
                trailing: TextButton(
                    onPressed: widget.onOpenReports,
                    child: const Text('All reports')),
                child: allSales.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Your saved invoices will appear here.'),
                      )
                    : Column(
                        children: [
                          for (final sale in allSales.take(5))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              onTap: widget.onOpenReports,
                              leading: CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                foregroundColor:
                                    theme.colorScheme.onPrimaryContainer,
                                child: Icon(_paymentIcon(sale.payment)),
                              ),
                              title: Text(
                                  sale.customerName.trim().isEmpty
                                      ? 'Walk-in customer'
                                      : sale.customerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '${sale.id} · ${DateFormat('d MMM, h:mm a').format(sale.date.toLocal())}'),
                              trailing: Text(currency.format(sale.totalAmount),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                            ),
                        ],
                      ),
              );
              final actionsPanel = _Panel(
                title: 'Quick actions',
                subtitle: 'Jump to a common task',
                child: Column(
                  children: [
                    _QuickAction(
                        icon: Icons.add_shopping_cart,
                        title: 'Create a bill',
                        subtitle: 'Start a new checkout',
                        onTap: widget.onOpenBilling),
                    const Divider(height: 1),
                    _QuickAction(
                        icon: Icons.add_box_outlined,
                        title: 'Manage products',
                        subtitle: 'Prices, stock and barcodes',
                        onTap: widget.onOpenProducts),
                    const Divider(height: 1),
                    _QuickAction(
                        icon: Icons.bar_chart_rounded,
                        title: 'Open reports',
                        subtitle: 'Sales and GST summaries',
                        onTap: widget.onOpenReports),
                  ],
                ),
              );

              Widget pair(Widget a, Widget b, bool wide) => wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: a),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: b),
                      ],
                    )
                  : Column(children: [a, const SizedBox(height: 16), b]);

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_greeting(now)} · ${DateFormat('EEEE, d MMMM yyyy').format(now)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SetupChecklist(
                    hasProducts: activeProducts.isNotEmpty,
                    hasSales: allSales.isNotEmpty,
                    onOpenProducts: widget.onOpenProducts,
                    onOpenBilling: widget.onOpenBilling,
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1000
                          ? 4
                          : constraints.maxWidth >= 560
                              ? 2
                              : 1;
                      final cardWidth =
                          (constraints.maxWidth - (columns - 1) * 12) / columns;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final metric in metrics)
                            SizedBox(width: cardWidth, child: metric),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 820;
                      if (!financial) {
                        return pair(lowStockPanel, actionsPanel, wide);
                      }
                      return Column(
                        children: [
                          pair(trendPanel, paymentPanel, wide),
                          const SizedBox(height: 16),
                          pair(topPanel, lowStockPanel, wide),
                          const SizedBox(height: 16),
                          pair(recentPanel, actionsPanel, wide),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static IconData _paymentIcon(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.card:
        return Icons.credit_card_outlined;
      case PaymentMethod.upi:
        return Icons.qr_code_2;
      case PaymentMethod.cash:
        return Icons.payments_outlined;
    }
  }
}

class _Sold {
  double revenue = 0;
  double qty = 0;
  String unit = 'pcs';
}

// ===========================================================================
// Widgets
// ===========================================================================

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final _Delta? delta;
  final String? compareLabel;
  final VoidCallback? onTap;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.delta,
    this.compareLabel,
    this.onTap,
  });

  Widget _deltaRow(BuildContext context) {
    final theme = Theme.of(context);
    final d = delta;
    if (d == null) return const SizedBox.shrink();
    final scheme = theme.colorScheme;
    final label = compareLabel ?? '';
    if (d.isNew) {
      return Text('New · $label',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant));
    }
    final pct = d.percent!;
    final flat = pct.abs() < 0.5;
    final up = pct > 0;
    final good = flat ? null : (up == d.upIsGood);
    final Color tone = good == null
        ? scheme.onSurfaceVariant
        : good
            ? Colors.green.shade700.adaptive(context)
            : scheme.error;
    return Row(
      children: [
        Icon(
          flat
              ? Icons.remove
              : up
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
          size: 14,
          color: tone,
        ),
        const SizedBox(width: 2),
        Text(
          flat ? '0%' : '${pct.abs().toStringAsFixed(pct.abs() >= 100 ? 0 : 1)}%',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: tone, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, color: color),
                  ),
                  const Spacer(),
                  if (onTap != null)
                    Icon(Icons.arrow_outward,
                        size: 18, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 16),
              Text(title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(value,
                  style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (delta != null) ...[
                const SizedBox(height: 6),
                _deltaRow(context),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  const _Panel(
      {required this.title,
      required this.subtitle,
      required this.child,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// Bar chart of daily revenue with hover/long-press details.
class _TrendChart extends StatelessWidget {
  final List<_DayRevenue> days;
  final NumberFormat currency;
  final DateTime today;

  const _TrendChart(
      {required this.days, required this.currency, required this.today});

  String _short(double value) {
    if (value >= 10000) return '₹${(value / 1000).toStringAsFixed(0)}k';
    if (value >= 1000) return '₹${(value / 1000).toStringAsFixed(1)}k';
    return '₹${value.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxRevenue =
        days.fold<double>(0, (m, d) => d.revenue > m ? d.revenue : m);
    final total = days.fold<double>(0, (s, d) => s + d.revenue);
    if (maxRevenue <= 0) {
      return SizedBox(
        height: 150,
        child: Center(
          child: Text('Sales activity will appear here.',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      );
    }
    final compact = days.length > 7;
    final average = total / days.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Total ${currency.format(total)} · average ${currency.format(average)} a day',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 180,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Builder(builder: (context) {
                    final day = days[i];
                    final isToday = day.day == today;
                    final ratio = (day.revenue / maxRevenue).clamp(0.04, 1.0);
                    final showLabel = !compact ||
                        i % 5 == 0 ||
                        i == days.length - 1;
                    return Tooltip(
                      message:
                          '${DateFormat('EEE, d MMM').format(day.day)}\n${currency.format(day.revenue)}',
                      child: Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: compact ? 1.5 : 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (!compact && day.revenue > 0)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(_short(day.revenue),
                                    style: theme.textTheme.labelSmall,
                                    maxLines: 1),
                              ),
                            Container(
                              height: 105.0 * ratio.toDouble(),
                              decoration: BoxDecoration(
                                color: isToday
                                    ? scheme.primary
                                    : scheme.primary.withValues(alpha: 0.35),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 16,
                              child: showLabel
                                  ? Text(
                                      DateFormat(compact ? 'd' : 'E')
                                          .format(day.day),
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              fontWeight: isToday
                                                  ? FontWeight.w800
                                                  : null),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Stacked bar + legend for cash / card / UPI.
class _PaymentMix extends StatelessWidget {
  final Map<PaymentMethod, double> byMethod;
  final NumberFormat currency;

  const _PaymentMix({required this.byMethod, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = byMethod.values.fold<double>(0, (s, v) => s + v);
    if (total <= 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('Payments will appear here.',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    final rows = <(String, IconData, Color, PaymentMethod)>[
      ('Cash', Icons.payments_outlined, Colors.green.shade600, PaymentMethod.cash),
      ('Card', Icons.credit_card_outlined, Colors.blue.shade600, PaymentMethod.card),
      ('UPI', Icons.qr_code_2, Colors.orange.shade700, PaymentMethod.upi),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (final row in rows)
                  if ((byMethod[row.$4] ?? 0) > 0)
                    Expanded(
                      flex: ((byMethod[row.$4]! / total) * 1000)
                          .round()
                          .clamp(1, 1000)
                          .toInt(),
                      child: Container(color: row.$3),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: row.$3, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Icon(row.$2, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(row.$1)),
                Text(
                  currency.format(byMethod[row.$4] ?? 0),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${(((byMethod[row.$4] ?? 0) / total) * 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.end,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Top items by revenue for the selected period.
class _TopProducts extends StatelessWidget {
  final List<MapEntry<String, _Sold>> entries;
  final Map<String, Product> products;
  final NumberFormat currency;

  const _TopProducts(
      {required this.entries, required this.products, required this.currency});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('Best sellers will appear after your first sale.',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    final top = entries.first.value.revenue;
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        products[entries[i].key]?.name ?? 'Removed item',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: top <= 0
                              ? 0.0
                              : (entries[i].value.revenue / top)
                                  .clamp(0.0, 1.0)
                                  .toDouble(),
                          minHeight: 6,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      currency.format(entries[i].value.revenue),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      '${entries[i].value.qty.toStringAsFixed(entries[i].value.qty == entries[i].value.qty.roundToDouble() ? 0 : 1)} ${entries[i].value.unit}',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickAction(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// First-run checklist shown on the dashboard until the basics are done (or
/// the user dismisses it).
class _SetupChecklist extends StatefulWidget {
  final bool hasProducts;
  final bool hasSales;
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenBilling;

  const _SetupChecklist({
    required this.hasProducts,
    required this.hasSales,
    required this.onOpenProducts,
    required this.onOpenBilling,
  });

  @override
  State<_SetupChecklist> createState() => _SetupChecklistState();
}

class _SetupChecklistState extends State<_SetupChecklist> {
  static const _dismissedKey = 'setup_checklist_dismissed';

  bool get _dismissed =>
      Hive.box<dynamic>('app_settings').get(_dismissedKey, defaultValue: false)
          as bool;

  bool get _hasBusinessDetails {
    final settings = Hive.box<dynamic>('app_settings');
    return settings.get('business_name', defaultValue: '').toString().trim().isNotEmpty;
  }

  Future<void> _dismiss() async {
    await Hive.box<dynamic>('app_settings').put(_dismissedKey, true);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasBusiness = _hasBusinessDetails;
    final done = hasBusiness && widget.hasProducts && widget.hasSales;
    if (_dismissed || done) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    Widget step(bool complete, String title, String hint, {VoidCallback? onTap}) {
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          complete ? Icons.check_circle : Icons.radio_button_unchecked,
          color: complete ? cs.primary : cs.outline,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: complete ? TextDecoration.lineThrough : null,
            color: complete ? cs.onSurfaceVariant : cs.onSurface,
          ),
        ),
        subtitle: Text(hint),
        trailing: (!complete && onTap != null)
            ? const Icon(Icons.chevron_right)
            : null,
        onTap: complete ? null : onTap,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 0,
        color: cs.primaryContainer.withValues(alpha: 0.35),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Finish setting up',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hide checklist',
                    icon: const Icon(Icons.close),
                    onPressed: _dismiss,
                  ),
                ],
              ),
              step(
                hasBusiness,
                'Add your business details',
                'Settings > Invoice & GST: name, address, phone.',
              ),
              step(
                widget.hasProducts,
                'Add your first product',
                'Tap to open Products.',
                onTap: widget.onOpenProducts,
              ),
              step(
                widget.hasSales,
                'Make your first sale',
                'Tap to open Billing.',
                onTap: widget.onOpenBilling,
              ),
            ],
          ),
        ),
      ),
    );
  }
}