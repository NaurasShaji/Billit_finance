import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'tabs/billing_tab.dart';
import 'tabs/dashboard_tab.dart';
import 'tabs/products_tab.dart';
import 'tabs/reports_tab.dart';
import 'tabs/finance_tab.dart';
import 'tabs/team_tab.dart';
import 'settings_screen.dart';
import '../widgets/responsive_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  late AuthService _authService; // Declare AuthService

  @override
  void initState() {
    super.initState();
    _authService = context.read<AuthService>(); // Initialize AuthService
  }

  void _showHelpFaqDialog() {
    final isAdmin = _authService.isAdmin;
    final searchController = TextEditingController();
    final faqs = <({String category, String question, String answer})>[
      (
        category: 'Billing',
        question: 'How do I create a bill?',
        answer:
            'Open Billing, add products to the cart, adjust quantities, apply a discount if needed, choose the payment method and complete the sale. The saved bill is available in your sales records.',
      ),
      (
        category: 'Billing',
        question: 'Can I change a bill after saving it?',
        answer:
            'Open the saved sale from the available sales records and use the edit action if it is available. Voiding a bill is restricted to admins.',
      ),
      (
        category: 'Billing',
        question: 'How are GST and discounts handled?',
        answer:
            'Add the discount before completing the sale. Billit calculates the taxable value and applicable GST from the product tax settings. Interstate sales use IGST; eligible local sales use CGST and SGST.',
      ),
      (
        category: 'Inventory',
        question: 'How do I add or edit a product?',
        answer:
            'Open Inventory and choose Add Product. To update an existing item, open it and choose Edit. Set its selling price, unit, stock and applicable tax details.',
      ),
      (
        category: 'Inventory',
        question: 'Does stock update automatically?',
        answer:
            'Yes. Completing a bill reduces stock for the products sold. You can also open a product and use Restock / Adjust quantity to record a manual change. Positive values increase stock; negative values decrease it.',
      ),
      (
        category: 'Inventory',
        question: 'Can I use different units such as pcs and kg?',
        answer:
            'Yes. Set the unit while adding or editing a product. The selected unit is shown wherever that product quantity is displayed.',
      ),
      (
        category: 'Inventory',
        question: 'How do I import products in bulk?',
        answer:
            'Admins can open Settings > Business Tools > Product Management > Bulk Add Products (Excel). Use the provided import format and keep the required column names and values intact.',
      ),
      (
        category: 'Reports',
        question: 'Where can I download sales and GST reports?',
        answer:
            'Open Reports & Statements to choose a day or date range and export the available sales statements, GST sales registers, item registers and expense registers.',
      ),
      (
        category: 'Finance & Team',
        question: 'How do I record an expense?',
        answer:
            'Admins can open Finance and tap Expense. Pick a category, enter the amount and an optional note. Finance shows net profit for today, this month or this year.',
      ),
      (
        category: 'Finance & Team',
        question: 'How do I pay salaries and daily wages?',
        answer:
            'Open Team to see who is paid and who is due. Tap Pay beside an employee to record their salary or day\'s wage, or use Pay salaries / Pay daily wages to adjust the amount first.',
      ),
      (
        category: 'Finance & Team',
        question: 'How do I add or edit employees?',
        answer:
            'Open Team and tap Manage to add an employee, change their pay, or remove them. Tap any employee card to see their payment history.',
      ),
      (
        category: 'Invoices',
        question: 'How do I customise my invoice?',
        answer:
            'Open Settings > Invoice Customisation to adjust the available invoice layout, content, footer and payment display options. Check the preview before saving your changes.',
      ),
      (
        category: 'Invoices',
        question: 'How do I share an invoice on WhatsApp?',
        answer:
            'Use the WhatsApp action on a saved sale. Billit prepares the invoice as a PDF for sharing. WhatsApp must be available on your device.',
      ),
      (
        category: 'Invoices',
        question: 'How does the UPI QR code work?',
        answer:
            'Configure your UPI ID in invoice settings and enable Show UPI QR when available. The invoice QR contains the sale amount and invoice reference. Customers should verify the payment in your UPI app before treating it as paid.',
      ),
      (
        category: 'Account & Data',
        question: 'How do I change my password?',
        answer:
            'Open Settings > Business Tools > Account & Settings > Change Password. Password changes are managed by the admin account.',
      ),
      (
        category: 'Account & Data',
        question: 'How do I recover the admin password?',
        answer:
            'Choose Forgot Password on the login screen and complete the security-question verification to set a new admin password.',
      ),
      (
        category: 'Account & Data',
        question: 'How do I back up or restore business data?',
        answer:
            'Admins can open Settings > Business Tools > Data Management > Backup & Restore and connect Google Drive. Keep a recent backup before restoring: restore replaces the current business data.',
      ),
      (
        category: 'Access',
        question: 'What can a worker account access?',
        answer:
            'Worker access is limited to day-to-day operations. Admin-only functions such as business settings, business tools, finance and payroll are restricted.',
      ),
    ];

    final categories = ['All', ...{for (final faq in faqs) faq.category}];
    String selectedCategory = 'All';
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredFaqs = faqs.where((faq) {
            final matchesCategory =
                selectedCategory == 'All' || faq.category == selectedCategory;
            final query = searchQuery.trim().toLowerCase();
            final matchesSearch = query.isEmpty ||
                faq.question.toLowerCase().contains(query) ||
                faq.answer.toLowerCase().contains(query) ||
                faq.category.toLowerCase().contains(query);
            return matchesCategory && matchesSearch;
          }).toList();

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 20, 14, 18),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.55),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.support_agent_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Help Centre',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Guides and answers for using Billit',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                    child: TextField(
                      controller: searchController,
                      onChanged: (value) =>
                          setDialogState(() => searchQuery = value),
                      decoration: InputDecoration(
                        hintText: 'Search help topics',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searchQuery.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  searchController.clear();
                                  setDialogState(() => searchQuery = '');
                                },
                                icon: const Icon(Icons.close),
                              ),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      scrollDirection: Axis.horizontal,
                      itemCount: categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final category = categories[index];
                        final selected = category == selectedCategory;
                        return ChoiceChip(
                          label: Text(category),
                          selected: selected,
                          onSelected: (_) => setDialogState(
                            () => selectedCategory = category,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filteredFaqs.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.search_off_rounded,
                                    size: 38,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 10),
                                  const Text('No matching help topics'),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Try another search or category.',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                            children: [
                              if (searchQuery.isEmpty &&
                                  selectedCategory == 'All') ...[
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.lightbulb_outline_rounded,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          isAdmin
                                              ? 'Start with Billing and Inventory. Use Reports for exports, Finance for expenses and profit, Team for employees and payroll, and Settings > Business Tools for backups and account management.'
                                              : 'Start with Billing and Inventory. Ask your admin if you need access to restricted settings or business tools.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              for (final faq in filteredFaqs)
                                Card(
                                  elevation: 0,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerLow,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: BorderSide(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                    ),
                                  ),
                                  child: ExpansionTile(
                                    tilePadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 2,
                                    ),
                                    childrenPadding:
                                        const EdgeInsets.fromLTRB(14, 0, 14, 16),
                                    title: Text(
                                      faq.question,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(faq.category),
                                    children: [
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          faq.answer,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(height: 1.45),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Close'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(searchController.dispose);
  }

  List<IconData> _navigationIcons({
    required bool isAdmin,
    required String style,
  }) {
    final isFilled = style == 'filled';
    final isRounded = style == 'rounded';

    final overview = isFilled
        ? Icons.dashboard
        : isRounded
            ? Icons.dashboard_rounded
            : Icons.dashboard_outlined;
    final billing = isFilled
        ? Icons.receipt
        : isRounded
            ? Icons.receipt_rounded
            : Icons.receipt_long_outlined;
    final inventory = isFilled
        ? Icons.inventory
        : isRounded
            ? Icons.inventory_2_rounded
            : Icons.inventory_2_outlined;
    final reports = isFilled
        ? Icons.bar_chart
        : isRounded
            ? Icons.bar_chart_rounded
            : Icons.bar_chart_outlined;
    final finance = isFilled
        ? Icons.account_balance_wallet
        : isRounded
            ? Icons.account_balance_wallet_rounded
            : Icons.account_balance_wallet_outlined;
    final team = isFilled
        ? Icons.groups
        : isRounded
            ? Icons.groups_rounded
            : Icons.groups_outlined;

    return isAdmin
        ? [overview, billing, inventory, reports, finance, team]
        : [overview, billing, inventory, reports];
  }

  List<String> _navigationKeys(bool isAdmin) => isAdmin
      ? ['overview', 'billing', 'inventory', 'reports', 'finance', 'team']
      : ['overview', 'billing', 'inventory', 'reports'];

  IconData _iconFromChoice(String choice, IconData fallback) {
    switch (choice) {
      case 'home':
        return Icons.home_outlined;
      case 'dashboard':
        return Icons.dashboard_outlined;
      case 'grid':
        return Icons.grid_view_rounded;
      case 'receipt':
        return Icons.receipt_long_outlined;
      case 'cart':
        return Icons.shopping_cart_outlined;
      case 'calculator':
        return Icons.calculate_outlined;
      case 'inventory':
        return Icons.inventory_2_outlined;
      case 'box':
        return Icons.widgets_outlined;
      case 'package':
        return Icons.inventory_2_outlined;
      case 'warehouse':
        return Icons.warehouse_outlined;
      case 'chart':
        return Icons.bar_chart_outlined;
      case 'analytics':
        return Icons.analytics_outlined;
      case 'trending':
        return Icons.trending_up_outlined;
      case 'wallet':
        return Icons.account_balance_wallet_outlined;
      case 'savings':
        return Icons.savings_outlined;
      case 'people':
        return Icons.groups_outlined;
      case 'badge':
        return Icons.badge_outlined;
      case 'archive':
        return Icons.archive_outlined;
      case 'folder':
        return Icons.folder_open_outlined;
      case 'history':
        return Icons.history;
      default:
        return fallback;
    }
  }

  List<IconData> _applyCustomNavigationIcons(
    List<IconData> defaults,
    List<String> keys,
    Map<dynamic, dynamic> overrides,
  ) {
    return List<IconData>.generate(defaults.length, (index) {
      final key = keys[index];
      return _iconFromChoice(overrides[key]?.toString() ?? '', defaults[index]);
    });
  }

  Widget _buildBottomNavigation({
    required List<String> labels,
    required List<IconData> icons,
    required int selectedIndex,
    required String style,
    required ValueChanged<int> onSelect,
  }) {
    if (style == 'classic') {
      return NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelect,
        destinations: [
          for (var i = 0; i < labels.length; i++)
            NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
        ],
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final floating = style == 'floating';
    return Container(
      margin:
          floating ? const EdgeInsets.fromLTRB(12, 0, 12, 10) : EdgeInsets.zero,
      padding: EdgeInsets.fromLTRB(8, floating ? 8 : 4, 8,
          MediaQuery.paddingOf(context).bottom > 0 ? 4 : 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(floating ? 24 : 0),
        boxShadow: floating
            ? [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 4))
              ]
            : null,
        border: style == 'underline'
            ? Border(
                top: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.6)))
            : null,
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
                  decoration: BoxDecoration(
                    color: style == 'floating' && i == selectedIndex
                        ? scheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icons[i],
                        size: 23,
                        color: i == selectedIndex
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: i == selectedIndex
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: i == selectedIndex
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      if (style == 'underline')
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.only(top: 4),
                          height: 3,
                          width: i == selectedIndex ? 22 : 0,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = _authService.isAdmin;

    final List<String> labels = isAdmin
        ? ['Overview', 'Billing', 'Inventory', 'Reports', 'Finance', 'Team']
        : ['Overview', 'Billing', 'Inventory', 'Reports'];

    final settingsBox = Hive.box<dynamic>('app_settings');
    final navigationIconStyle = settingsBox
        .get('navigation_icon_style', defaultValue: 'outlined')
        .toString();

    final List<IconData> defaultIcons = _navigationIcons(
      isAdmin: isAdmin,
      style: navigationIconStyle,
    );
    final navigationKeys = _navigationKeys(isAdmin);
    final rawOverrides = settingsBox
        .get('navigation_icon_overrides', defaultValue: <String, String>{});
    final navigationOverrides =
        rawOverrides is Map ? rawOverrides : <String, String>{};
    final List<IconData> icons = _applyCustomNavigationIcons(
      defaultIcons,
      navigationKeys,
      navigationOverrides,
    );

    final List<Widget> tabs = [
      DashboardTab(
        showFinancials: isAdmin,
        onOpenBilling: () => setState(() => _index = 1),
        onOpenProducts: () => setState(() => _index = 2),
        onOpenReports: () => setState(() => _index = 3),
        onOpenFinance: isAdmin ? () => setState(() => _index = 4) : null,
      ),
      const BillingTab(),
      const ProductsTab(),
      const ReportsTab(),
      if (isAdmin) ...[
        const FinanceTab(),
        const TeamTab(),
      ],
    ];

    // Ensure _index is within bounds for worker
    if (!isAdmin && _index >= tabs.length) {
      _index =
          0; // Default to Billing tab for worker if current index is out of bounds
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: ValueListenableBuilder<Box<dynamic>>(
          valueListenable: Hive.box<dynamic>('app_settings').listenable(),
          builder: (context, settings, _) {
            final appName = settings
                .get('app_name', defaultValue: 'Billit')
                .toString();
            final logoBase64 = settings.get('app_logo_base64') as String?;
            Widget? logo;
            if (logoBase64 != null && logoBase64.isNotEmpty) {
              try {
                logo = ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(base64Decode(logoBase64),
                      width: 32, height: 32, fit: BoxFit.contain),
                );
              } catch (_) {
                logo = null;
              }
            }
            return Row(
              children: [
                if (logo != null) ...[
                  logo,
                  const SizedBox(width: 8)
                ] else ...[
                  ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SvgPicture.asset('assets/icon/billit_logo.svg',
                          width: 34, height: 34)),
                  const SizedBox(width: 8)
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(appName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      Text(labels[_index],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    isAdmin: isAdmin,
                    onHelp: () {
                      // Keep SettingsScreen on the navigation stack while
                      // showing Help & FAQ. Closing the dialog then returns
                      // directly to the Settings section instead of Home.
                      _showHelpFaqDialog();
                    },
                    onLogout: () {
                      Navigator.of(context).pop();
                      context.read<AuthService>().logout();
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= ResponsiveBreakpoints.desktop) {
            return ValueListenableBuilder<Box<dynamic>>(
              valueListenable:
                  Hive.box<dynamic>('app_settings').listenable(),
              builder: (context, settings, _) {
                final iconStyle = settings
                    .get('navigation_icon_style', defaultValue: 'outlined')
                    .toString();
                final raw = settings.get('navigation_icon_overrides',
                    defaultValue: <String, String>{});
                final overrides = raw is Map ? raw : <String, String>{};
                final railIcons = _applyCustomNavigationIcons(
                  _navigationIcons(isAdmin: isAdmin, style: iconStyle),
                  navigationKeys,
                  overrides,
                );
                return Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _index,
                      onDestinationSelected: (i) => setState(() => _index = i),
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (var i = 0; i < labels.length; i++)
                          NavigationRailDestination(
                            icon: Icon(railIcons[i]),
                            label: Text(labels[i]),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: ResponsivePage(
                        maxWidth: 1600,
                        child: IndexedStack(index: _index, children: tabs),
                      ),
                    ),
                  ],
                );
              },
            );
          }
          return IndexedStack(index: _index, children: tabs);
        },
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width <
              ResponsiveBreakpoints.desktop
          ? ValueListenableBuilder<Box<dynamic>>(
              valueListenable: Hive.box<dynamic>('app_settings').listenable(),
              builder: (context, settings, _) => _buildBottomNavigation(
                labels: labels,
                icons: _applyCustomNavigationIcons(
                  _navigationIcons(
                    isAdmin: isAdmin,
                    style: settings
                        .get('navigation_icon_style', defaultValue: 'outlined')
                        .toString(),
                  ),
                  _navigationKeys(isAdmin),
                  settings.get('navigation_icon_overrides',
                          defaultValue: <String, String>{}) is Map
                      ? settings.get('navigation_icon_overrides',
                          defaultValue: <String, String>{}) as Map
                      : <String, String>{},
                ),
                selectedIndex: _index,
                style: settings
                    .get('navigation_style', defaultValue: 'classic')
                    .toString(),
                onSelect: (i) => setState(() => _index = i),
              ),
            )
          : null,
    );
  }
}
