import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../services/boxes.dart';
import '../edit_invoice_screen.dart';
import '../../utils/theme_colors.dart';

class CustomerLookupScreen extends StatefulWidget {
  const CustomerLookupScreen({super.key});

  @override
  State<CustomerLookupScreen> createState() => _CustomerLookupScreenState();
}

class _CustomerLookupScreenState extends State<CustomerLookupScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Sale> _customerInvoices = [];
  List<Customer> _foundCustomers = [];
  bool _isLoading = false;

  // Initialize as nullable and check before use
  AnimationController? _animationController;
  Animation<double>? _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize animation controller first
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Then initialize the animation
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController!,
      curve: Curves.easeInOut,
    ));

    _searchController.addListener(_onSearchChanged);
    _searchCustomers('');
    _animationController!.forward();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _animationController?.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _isLoading = true;
    });

    // Add a small delay to debounce the search
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _searchCustomers(_searchController.text);
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  void _searchCustomers(String query) {
    final salesBox = Hive.box<Sale>(Boxes.sales);
    final allSales = salesBox.values.toList();
    final Set<String> uniqueCustomers = {};
    final List<Customer> customers = [];

    if (query.isEmpty) {
      for (final sale in allSales) {
        final customerIdentifier = '${sale.customerName}_${sale.customerPhone}';
        if (!uniqueCustomers.contains(customerIdentifier) &&
            sale.customerName.isNotEmpty) {
          uniqueCustomers.add(customerIdentifier);
          customers.add(Customer(
            name: sale.customerName,
            phone: sale.customerPhone,
          ));
        }
      }
    } else {
      for (final sale in allSales) {
        if (sale.customerName.toLowerCase().contains(query.toLowerCase()) ||
            sale.customerPhone.contains(query)) {
          final customerIdentifier =
              '${sale.customerName}_${sale.customerPhone}';
          if (!uniqueCustomers.contains(customerIdentifier)) {
            uniqueCustomers.add(customerIdentifier);
            customers.add(Customer(
              name: sale.customerName,
              phone: sale.customerPhone,
            ));
          }
        }
      }
    }

    setState(() {
      _foundCustomers = customers;
      _customerInvoices = [];
    });
  }

  void _viewCustomerInvoices(String customerName, String customerPhone) {
    final salesBox = Hive.box<Sale>(Boxes.sales);
    final invoices = salesBox.values
        .where((sale) =>
            sale.customerName == customerName &&
            sale.customerPhone == customerPhone)
        .toList();

    // Sort invoices by date (newest first)
    invoices.sort((a, b) => b.date.compareTo(a.date));

    setState(() {
      _customerInvoices = invoices;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _customerInvoices = [];
    });
    _searchCustomers('');
  }

  @override
  Widget build(BuildContext context) {
    final cur = NumberFormat.simpleCurrency(locale: 'en_IN');
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Customer Lookup',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_customerInvoices.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _clearSearch,
              tooltip: 'Back to customers',
            ),
        ],
      ),
      body: _fadeAnimation != null
          ? FadeTransition(
              opacity: _fadeAnimation!,
              child: _buildBody(cur, theme),
            )
          : _buildBody(
              cur, theme), // Fallback without animation if not initialized
    );
  }

  Widget _buildBody(NumberFormat cur, ThemeData theme) {
    return Column(
      children: [
        // Enhanced Search Bar - Single Layer
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.primaryColor,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
          ),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: context.panelColor,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Search customers by name or phone',
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 16,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: theme.primaryColor,
                      size: 22,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(tooltip: 'Clear', 
                            icon: Icon(
                              Icons.clear,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              _searchFocusNode.unfocus();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(
                        color: theme.primaryColor.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    filled:
                        false, // Disabled since container provides background
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (value) {
                    _searchFocusNode.unfocus();
                  },
                ),
              ),
              if (_customerInvoices.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _customerInvoices.first.customerName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: context.panelColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_customerInvoices.length} invoices',
                          style: TextStyle(
                            color: theme.primaryColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        // Content Area
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _buildContent(cur, theme),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(NumberFormat cur, ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_foundCustomers.isEmpty &&
        _customerInvoices.isEmpty &&
        _searchController.text.isNotEmpty) {
      return _buildEmptyState();
    }

    if (_foundCustomers.isNotEmpty && _customerInvoices.isEmpty) {
      return _buildCustomersList();
    }

    if (_customerInvoices.isNotEmpty) {
      return _buildInvoicesList(cur, theme);
    }

    return _buildEmptyState();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 80,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 20),
          Text(
            _searchController.text.isEmpty
                ? 'Start typing to search customers'
                : 'No customers found',
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_searchController.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Try searching with a different name or phone number',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCustomersList() {
    return ListView.builder(
      itemCount: _foundCustomers.length,
      itemBuilder: (context, index) {
        final customer = _foundCustomers[index];
        return AnimatedContainer(
          duration: Duration(milliseconds: 100 + (index * 50)),
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _viewCustomerInvoices(customer.name, customer.phone),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .primaryColor
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Icon(
                        Icons.person,
                        color: Theme.of(context).primaryColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customer.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            customer.phone.isNotEmpty
                                ? customer.phone
                                : 'No phone number',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Theme.of(context).colorScheme.outline,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInvoicesList(NumberFormat cur, ThemeData theme) {
    return ListView.builder(
      itemCount: _customerInvoices.length,
      itemBuilder: (context, index) {
        final invoice = _customerInvoices[index];
        return AnimatedContainer(
          duration: Duration(milliseconds: 100 + (index * 50)),
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => EditInvoiceScreen(
                      sale: invoice,
                      isViewOnly: true,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'ID: ${invoice.id}',
                            style: TextStyle(
                              color: theme.primaryColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          cur.format(invoice.totalAmount),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.green[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('MMM dd, yyyy - hh:mm a')
                              .format(invoice.date),
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: Theme.of(context).colorScheme.outline,
                          size: 16,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Helper class to represent a customer for display purposes
class Customer {
  final String name;
  final String phone;

  Customer({required this.name, required this.phone});
}
