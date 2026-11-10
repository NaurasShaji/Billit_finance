import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../services/boxes.dart';
import '../../services/finance_source_sync_service.dart';
import '../../services/invoice_service.dart'; // Added import
import './product_selection_screen.dart';
import '../widgets/responsive_page.dart';

class EditInvoiceScreen extends StatefulWidget {
  final Sale sale;
  final bool isViewOnly;

  const EditInvoiceScreen(
      {super.key, required this.sale, this.isViewOnly = false});

  @override
  State<EditInvoiceScreen> createState() => _EditInvoiceScreenState();
}

class _EditInvoiceScreenState extends State<EditInvoiceScreen>
    with TickerProviderStateMixin {
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController =
      TextEditingController();
  final TextEditingController _customerGstinController =
      TextEditingController();
  PaymentMethod _selectedPaymentMethod = PaymentMethod.cash;
  final List<SaleItem> _editedItems = [];
  final TextEditingController _discountController = TextEditingController();
  double _discount = 0.0;
  bool _isSaving = false;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  final InvoiceService _invoiceService =
      InvoiceService(); // Instantiated InvoiceService

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _customerNameController.text = widget.sale.customerName;
    _customerPhoneController.text = widget.sale.customerPhone;
    _customerGstinController.text = widget.sale.customerGstin;
    _selectedPaymentMethod = widget.sale.payment;
    _editedItems.addAll(widget.sale.items.map((e) => SaleItem.fromSaleItem(e)));
    _discountController.text = widget.sale.discount.toStringAsFixed(2);
    _discount = widget.sale.discount;

    _discountController.addListener(() {
      setState(() {
        _discount = double.tryParse(_discountController.text) ?? 0.0;
        if (_discount < 0) _discount = 0.0;
        if (_discount > _currentSubtotal) _discount = _currentSubtotal;
      });
    });

    _slideController.forward();
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerGstinController.dispose();
    _discountController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  double _money(double value) => (value * 100).roundToDouble() / 100;
  double get _currentSubtotal =>
      _money(_editedItems.fold(0.0, (a, it) => a + it.subtotal));
  double _grossAfterDiscount(SaleItem item) {
    if (_currentSubtotal <= 0) return 0.0;
    return _money((item.subtotal - _discount * item.subtotal / _currentSubtotal)
        .clamp(0.0, double.infinity)
        .toDouble());
  }

  double _rateForItem(SaleItem item) {
    if (item.gstRate != null) return item.gstRate!;
    final productRate =
        Hive.box<Product>(Boxes.products).get(item.productId)?.gstRate;
    return productRate ?? widget.sale.gstRate;
  }

  double _taxableForItem(SaleItem item) {
    final gross = _grossAfterDiscount(item);
    if (!widget.sale.gstEnabled || !widget.sale.gstInclusive) return gross;
    final rate = _rateForItem(item);
    return rate <= 0 ? gross : _money(gross / (1 + rate / 100.0));
  }

  double _taxForItem(SaleItem item) {
    if (!widget.sale.gstEnabled) return 0.0;
    final gross = _grossAfterDiscount(item);
    final taxable = _taxableForItem(item);
    return widget.sale.gstInclusive
        ? gross - taxable
        : _money(taxable * _rateForItem(item) / 100.0);
  }

  double get _currentTaxable => _money(_editedItems.fold<double>(
      0.0, (sum, item) => sum + _taxableForItem(item)));
  double get _currentGst => _money(
      _editedItems.fold<double>(0.0, (sum, item) => sum + _taxForItem(item)));
  double _lineCgst(SaleItem item) =>
      widget.sale.gstEnabled && !widget.sale.interstateSale
          ? _money(_taxForItem(item) / 2)
          : 0.0;
  double _lineSgst(SaleItem item) =>
      widget.sale.gstEnabled && !widget.sale.interstateSale
          ? _money(_taxForItem(item) - _lineCgst(item))
          : 0.0;
  double _lineIgst(SaleItem item) =>
      widget.sale.gstEnabled && widget.sale.interstateSale
          ? _taxForItem(item)
          : 0.0;
  double get _currentCgst => _money(
      _editedItems.fold<double>(0.0, (sum, item) => sum + _lineCgst(item)));
  double get _currentSgst => _money(
      _editedItems.fold<double>(0.0, (sum, item) => sum + _lineSgst(item)));
  double get _currentIgst => _money(
      _editedItems.fold<double>(0.0, (sum, item) => sum + _lineIgst(item)));
  double get _currentTotal =>
      _money(widget.sale.gstEnabled && !widget.sale.gstInclusive
          ? _currentTaxable + _currentGst
          : _currentSubtotal - _discount);
  double get _currentCost =>
      _editedItems.fold(0.0, (a, it) => a + (it.costPrice * it.qty));
  double get _currentProfit => _currentTaxable - _currentCost;

  double _getAvailableStock(Product product, SaleItem? currentItem) {
    final originalQty = currentItem?.qty ?? 0.0;
    final cartQty = _editedItems
        .where((item) => item.productId == product.id && item != currentItem)
        .fold(0.0, (a, b) => a + b.qty);
    return product.stock + originalQty - cartQty;
  }

  bool _canAddMoreToCart(
      Product product, SaleItem? currentItem, double quantityToAdd) {
    return _getAvailableStock(product, currentItem) >= quantityToAdd;
  }

  void _showStockLimitMessage(String productName, double availableStock) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                  'Cannot add $productName. Only ${availableStock.toStringAsFixed(1)} units available.'),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);

    try {
      for (final item in _editedItems) {
        final product = Hive.box<Product>(Boxes.products).get(item.productId);
        final taxable = _taxableForItem(item);
        item
          ..hsnCode = product?.hsnCode ?? item.hsnCode
          ..gstRate = widget.sale.gstEnabled ? _rateForItem(item) : 0.0
          ..taxableAmount = taxable
          ..cgstAmount = _lineCgst(item)
          ..sgstAmount = _lineSgst(item)
          ..igstAmount = _lineIgst(item);
      }

      widget.sale
        ..customerName = _customerNameController.text.trim()
        ..customerPhone = _customerPhoneController.text.trim()
        ..customerGstin = _customerGstinController.text.trim().toUpperCase()
        ..payment = _selectedPaymentMethod
        ..items = _editedItems.toList()
        ..totalAmount = _currentTotal
        ..totalCost = _currentCost
        ..profit = _currentProfit
        ..taxableAmount = _currentTaxable
        ..cgstAmount = _currentCgst
        ..sgstAmount = _currentSgst
        ..igstAmount = _currentIgst
        ..discount = _discount
        ..financeRevision += 1;

      await widget.sale.save();

      // A new immutable journal revision reverses the previous invoice snapshot.
      try {
        await FinanceSourceSyncService().syncSale(
          sale: widget.sale,
          accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts),
          transactionsBox: Hive.box<FinanceTransaction>(Boxes.financeTransactions),
          postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
          categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
          partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
        );
      } catch (financeError) {
        await FinanceSourceSyncService.recordIssue(
          Hive.box<dynamic>('app_settings'),
          'Sale ${widget.sale.id}: $financeError',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invoice updated; finance journal sync will retry on next launch: $financeError'),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
      }

      if (mounted) {
        _showSuccessMessage('Invoice updated successfully');
        await Future.delayed(const Duration(seconds: 1));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving changes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmAndPrint() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Print Invoice'),
        content: const Text('Do you want to print this invoice?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Print'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      generateInvoice(widget.sale);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cur = NumberFormat.simpleCurrency(locale: 'en_IN');
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          widget.isViewOnly ? 'Invoice Details' : 'Edit Invoice',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => _confirmAndPrint(),
            icon: const Icon(Icons.print),
            tooltip: 'Print Invoice',
          ),
          if (!widget.isViewOnly)
            Container(
              margin: const EdgeInsets.only(right: 16),
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: theme.primaryColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: _isSaving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(theme.primaryColor),
                        ),
                      )
                    : const Icon(Icons.save, size: 18),
                label: Text(_isSaving ? 'Saving...' : 'Save'),
              ),
            ),
        ],
      ),
      body: ResponsivePage(
          maxWidth: 1100,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Invoice Header
                  _buildInvoiceHeader(theme),
                  const SizedBox(height: 20),

                  // Customer Details Section
                  _buildCustomerSection(theme, isTablet),
                  const SizedBox(height: 20),

                  // Items Section
                  _buildItemsSection(theme, cur, isTablet),
                  const SizedBox(height: 20),

                  // Discount Section
                  _buildDiscountSection(theme),
                  const SizedBox(height: 20),

                  // Totals Summary
                  _buildTotalsSection(theme, cur),
                  const SizedBox(height: 20),

                  // Save Button
                  if (!widget.isViewOnly) _buildSaveButton(theme),
                ],
              ),
            ),
          )),
    );
  }

  Widget _buildInvoiceHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor.withValues(alpha: 0.8),
            theme.primaryColor,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.receipt_long,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Invoice',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'ID: ${widget.sale.id}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                Text(
                  DateFormat('MMM dd, yyyy • hh:mm a').format(widget.sale.date),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerSection(ThemeData theme, bool isTablet) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isTablet ? 24.0 : 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Colors.blue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Customer Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            isTablet
                ? Row(
                    children: [
                      Expanded(child: _buildCustomerNameField()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildCustomerPhoneField()),
                    ],
                  )
                : Column(
                    children: [
                      _buildCustomerNameField(),
                      const SizedBox(height: 16),
                      _buildCustomerPhoneField(),
                    ],
                  ),
            if (widget.sale.gstEnabled) ...[
              const SizedBox(height: 16),
              _buildCustomerGstinField(),
            ],
            const SizedBox(height: 20),
            _buildPaymentMethodSection(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customer Name',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: TextField(
            controller: _customerNameController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(borderSide: BorderSide.none),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              hintText: 'Enter customer name',
            ),
            readOnly: widget.isViewOnly,
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Phone Number',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: TextField(
            controller: _customerPhoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.phone_outlined),
              border: OutlineInputBorder(borderSide: BorderSide.none),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              hintText: 'Enter phone number',
            ),
            readOnly: widget.isViewOnly,
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerGstinField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Customer GSTIN (optional)',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700])),
        const SizedBox(height: 8),
        TextField(
          controller: _customerGstinController,
          textCapitalization: TextCapitalization.characters,
          readOnly: widget.isViewOnly,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.verified_outlined),
            border: OutlineInputBorder(),
            hintText: 'Enter customer GSTIN for B2B invoice',
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethodSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment Method',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: PaymentMethod.values.map((method) {
            final isSelected = _selectedPaymentMethod == method;
            return Expanded(
              child: GestureDetector(
                onTap: widget.isViewOnly
                    ? null
                    : () {
                        setState(() {
                          _selectedPaymentMethod = method;
                        });
                      },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.primaryColor.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? theme.primaryColor
                          : Colors.grey.withValues(alpha: 0.3),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: isSelected ? theme.primaryColor : Colors.grey,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        method.name.toUpperCase(),
                        style: TextStyle(
                          color: isSelected
                              ? theme.primaryColor
                              : Colors.grey[700],
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildItemsSection(ThemeData theme, NumberFormat cur, bool isTablet) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isTablet ? 24.0 : 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.shopping_cart,
                    color: Colors.green,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Items (${_editedItems.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!widget.isViewOnly)
                  ElevatedButton.icon(
                    onPressed: _addProduct,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_editedItems.isEmpty)
              _buildEmptyItemsState()
            else
              ..._buildItemsList(cur, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyItemsState() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No items in this invoice',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.isViewOnly
                ? 'This invoice has no items'
                : 'Tap "Add" to add products to this invoice',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildItemsList(NumberFormat cur, ThemeData theme) {
    final productsBox = Hive.box<Product>(Boxes.products);

    return _editedItems.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final product = productsBox.get(item.productId);
      if (product == null) return const SizedBox.shrink();

      return AnimatedContainer(
        duration: Duration(milliseconds: 100 + (index * 50)),
        margin: const EdgeInsets.only(bottom: 16),
        child: _buildItemCard(item, product, index, cur, theme),
      );
    }).toList();
  }

  Widget _buildItemCard(SaleItem item, Product product, int index,
      NumberFormat cur, ThemeData theme) {
    final increment = product.unit == UnitType.kg ? 0.5 : 1.0;
    final decrement = product.unit == UnitType.kg ? 0.5 : 1.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.inventory_2,
                    color: theme.primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        product.category,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.isViewOnly)
                  IconButton(tooltip: 'Delete', 
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _editedItems.removeAt(index);
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Price Field
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Unit Price',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.3)),
                        ),
                        child: TextFormField(
                          initialValue: item.sellingPrice.toStringAsFixed(2),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            prefixText: '₹',
                            border:
                                OutlineInputBorder(borderSide: BorderSide.none),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 16),
                          ),
                          readOnly: widget.isViewOnly,
                          onChanged: (value) {
                            setState(() {
                              final newPrice = double.tryParse(value) ?? 0.0;
                              item.sellingPrice = newPrice;
                              item.subtotal = item.qty * newPrice;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Quantity Controls
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      IconButton(tooltip: 'Remove', 
                        icon: const Icon(Icons.remove, size: 20),
                        onPressed: widget.isViewOnly
                            ? null
                            : () {
                                setState(() {
                                  if (item.qty > decrement) {
                                    item.qty -= decrement;
                                    item.subtotal =
                                        item.qty * item.sellingPrice;
                                  }
                                });
                              },
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          item.qty.toStringAsFixed(
                              product.unit == UnitType.kg ? 1 : 0),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(tooltip: 'Add', 
                        icon: const Icon(Icons.add, size: 20),
                        onPressed: widget.isViewOnly
                            ? null
                            : (_canAddMoreToCart(product, item, increment)
                                ? () {
                                    setState(() {
                                      item.qty += increment;
                                      item.subtotal =
                                          item.qty * item.sellingPrice;
                                    });
                                  }
                                : null),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${item.qty.toStringAsFixed(product.unit == UnitType.kg ? 1 : 0)} ${product.unit.name}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                Text(
                  'Subtotal: ${cur.format(item.subtotal)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountSection(ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.local_offer,
                    color: Colors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Discount',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Discount Amount',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: TextField(
                    controller: _discountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      prefixText: '₹',
                      prefixIcon: Icon(Icons.money_off),
                      border: OutlineInputBorder(borderSide: BorderSide.none),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      hintText: 'Enter discount amount',
                    ),
                    readOnly: widget.isViewOnly,
                    onChanged: (value) {
                      setState(() {
                        _discount = double.tryParse(value) ?? 0.0;
                        if (_discount < 0) _discount = 0.0;
                        if (_discount > _currentSubtotal) {
                          _discount = _currentSubtotal;
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsSection(ThemeData theme, NumberFormat cur) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.primaryColor.withValues(alpha: 0.05),
              theme.primaryColor.withValues(alpha: 0.1),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.receipt,
                      color: theme.primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Summary',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildSummaryRow('Subtotal', cur.format(_currentSubtotal)),
              _buildSummaryRow('Discount', '- ${cur.format(_discount)}',
                  isDiscount: true),
              if (widget.sale.gstEnabled) ...[
                _buildSummaryRow('Taxable value', cur.format(_currentTaxable)),
                if (widget.sale.interstateSale)
                  _buildSummaryRow('IGST', cur.format(_currentIgst))
                else ...[
                  _buildSummaryRow('CGST', cur.format(_currentCgst)),
                  _buildSummaryRow('SGST', cur.format(_currentSgst)),
                ],
              ],
              const Divider(thickness: 2),
              _buildSummaryRow('Total', cur.format(_currentTotal),
                  isTotal: true, theme: theme),
              const SizedBox(height: 8),
              _buildSummaryRow('Profit', cur.format(_currentProfit),
                  isProfit: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value,
      {bool isTotal = false,
      bool isDiscount = false,
      bool isProfit = false,
      ThemeData? theme}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 18 : 16,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: isTotal
                  ? (theme?.primaryColor ?? Colors.black)
                  : Colors.black87,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 20 : 16,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
              color: isTotal
                  ? (theme?.primaryColor ?? Colors.black)
                  : isDiscount
                      ? Colors.orange
                      : isProfit
                          ? Colors.green
                          : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _saveChanges,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.save),
        label: Text(
          _isSaving ? 'Saving Changes...' : 'Save Changes',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _addProduct() async {
    final selectedProduct = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ProductSelectionScreen(),
      ),
    );

    if (selectedProduct != null && selectedProduct is Product) {
      final p = selectedProduct;
      final increment = p.unit == UnitType.kg ? 0.5 : 1.0;

      if (_canAddMoreToCart(p, null, increment)) {
        final it = SaleItem()
          ..productId = p.id
          ..qty = increment
          ..sellingPrice = p.sellingPrice
          ..costPrice = p.costPrice
          ..subtotal = p.sellingPrice * increment
          ..unitLabel = p.unit.name;
        setState(() => _editedItems.add(it));
      } else {
        _showStockLimitMessage(p.name, _getAvailableStock(p, null));
      }
    }
  }
}
