import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/boxes.dart';
import '../../services/finance_source_sync_service.dart';
import '../../services/whatsapp_service.dart';
import '../../widgets/whatsapp_icon.dart';
import '../../utils/platform_support.dart';
import '../../services/auth_service.dart';
import '../../services/cart_service.dart';
import '../../services/pdf_service.dart'; // Import the new PDF service
import '../../services/invoice_service.dart'; // Import for generateInvoice function
import '../edit_invoice_screen.dart'; // Added import for EditInvoiceScreen
import '../../widgets/shopping_cart_section.dart';
import '../../widgets/print_option_dialog.dart';
import '../../widgets/responsive_page.dart';
import '../product_selection_screen.dart';
import '../barcode_scanner_screen.dart';

class BillingTab extends StatefulWidget {
  const BillingTab({super.key});
  @override
  State<BillingTab> createState() => _BillingTabState();
}

class _BillingTabState extends State<BillingTab> with TickerProviderStateMixin {
  late CartService _cartService;
  final TextEditingController _customerName = TextEditingController();
  final TextEditingController _customerPhone = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _barcodeInputController = TextEditingController();
  final TextEditingController _customerGstin = TextEditingController();
  final FocusNode _scanFocus = FocusNode();
  bool _tabVisible = true;
  bool _routeCurrent = true;
  bool _processing = false;
  int _freqSalesLen = -1;
  List<String> _freqIds = const [];
  bool _applyGst = false;
  bool _interstateSale = false;
  bool _gstInclusive = false;
  AnimationController? _animationController;
  Animation<double>? _fadeAnimation;

  // Add these getters that delegate to CartService
  List<SaleItem> get items => _cartService.items;
  PaymentMethod get _method => _cartService.paymentMethod;
  double get _discount => _cartService.discount;
  double get total => _cartService.total;
  double get cost => _cartService.cost;
  double get profit => _cartService.profit;
  int get itemCount => _cartService.itemCount;
  Color get _primaryColor => Theme.of(context).colorScheme.primary;
  Color get _errorColor => Theme.of(context).colorScheme.error;
  Color get _successColor => Colors.green.shade700;
  Color get _warningColor => Colors.orange.shade700;
  Color get _cardColor => Theme.of(context).colorScheme.surface;
  Color get _textPrimary => Theme.of(context).colorScheme.onSurface;
  Color get _textSecondary => Theme.of(context).colorScheme.onSurfaceVariant;

  bool get _gstAvailable {
    final settings = Hive.box<dynamic>('app_settings');
    final registration = settings
        .get('gst_registration_type', defaultValue: 'regular')
        .toString();
    return (settings.get('gst_enabled', defaultValue: false) as bool) &&
        registration == 'regular';
  }

  double get _gstRate =>
      (Hive.box<dynamic>('app_settings').get('gst_rate', defaultValue: 0.0)
              as num)
          .toDouble();
  double _money(double value) => (value * 100).roundToDouble() / 100;
  double get _subtotal =>
      _money(items.fold(0.0, (sum, item) => sum + item.subtotal));
  double _lineGrossAfterDiscount(SaleItem item) {
    if (_subtotal <= 0) return 0.0;
    final allocatedDiscount = _discount * item.subtotal / _subtotal;
    return _money((item.subtotal - allocatedDiscount)
        .clamp(0.0, double.infinity)
        .toDouble());
  }

  double _lineTaxableAmount(SaleItem item) {
    final gross = _lineGrossAfterDiscount(item);
    if (!_applyGst || !_gstInclusive) return gross;
    final rate = _lineGstRate(item);
    return rate <= 0 ? gross : _money(gross / (1 + rate / 100.0));
  }

  double get _taxableAmount => _applyGst
      ? _money(items.fold<double>(
          0.0, (sum, item) => sum + _lineTaxableAmount(item)))
      : _money((_subtotal - _discount).clamp(0.0, double.infinity).toDouble());
  double _lineTaxAmount(SaleItem item) {
    if (!_applyGst) return 0.0;
    final rate = _lineGstRate(item);
    final taxable = _lineTaxableAmount(item);
    return _gstInclusive
        ? _lineGrossAfterDiscount(item) - taxable
        : _money(taxable * rate / 100.0);
  }

  double _lineGstRate(SaleItem item) {
    final productRate =
        Hive.box<Product>(Boxes.products).get(item.productId)?.gstRate;
    return productRate ?? _gstRate;
  }

  double get _gstAmount => !_applyGst
      ? 0.0
      : _money(items.fold<double>(
          0.0,
          (sum, item) => sum + _lineTaxAmount(item),
        ));
  double _lineCgst(SaleItem item) =>
      _applyGst && !_interstateSale ? _money(_lineTaxAmount(item) / 2) : 0.0;
  double _lineSgst(SaleItem item) => _applyGst && !_interstateSale
      ? _money(_lineTaxAmount(item) - _lineCgst(item))
      : 0.0;
  double _lineIgst(SaleItem item) =>
      _applyGst && _interstateSale ? _lineTaxAmount(item) : 0.0;
  double get _cgstAmount =>
      _money(items.fold<double>(0.0, (sum, item) => sum + _lineCgst(item)));
  double get _sgstAmount =>
      _money(items.fold<double>(0.0, (sum, item) => sum + _lineSgst(item)));
  double get _igstAmount =>
      _money(items.fold<double>(0.0, (sum, item) => sum + _lineIgst(item)));
  double get _grandTotal => _money(_applyGst && _gstInclusive
      ? _subtotal - _discount
      : _taxableAmount + _gstAmount);
  double get _estimatedProfit => _taxableAmount - cost;

  @override
  void initState() {
    super.initState();
    _cartService = CartService();
    final gstSettings = Hive.box<dynamic>('app_settings');
    _gstInclusive =
        gstSettings.get('gst_price_inclusive', defaultValue: false) as bool;
    _interstateSale = gstSettings.get('gst_default_interstate_sale',
        defaultValue: false) as bool;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeInOut),
    );
    _animationController?.forward();

    // Initialize controllers with cart service data
    _customerName.text = _cartService.customerName;
    _customerPhone.text = _cartService.customerPhone;
    _discountController.text = _cartService.discount.toString();

    // Listen to cart changes
    _cartService.addListener(_onCartChanged);
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _scanFocus.dispose();
    _cartService.removeListener(_onCartChanged);
    _animationController?.dispose();
    _customerName.dispose();
    _customerPhone.dispose();
    _discountController.dispose();
    _barcodeInputController.dispose();
    _customerGstin.dispose();
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // Get current cart quantity for a product
  double _getCartQuantity(String productId) {
    return _cartService.getCartQuantity(productId);
  }

  // Get available stock for a product (stock - cart quantity)
  double _getAvailableStock(Product product) {
    return _cartService.getAvailableStock(product);
  }

  // Check if we can add more quantity to cart
  bool _canAddToCart(Product product, double quantityToAdd) {
    return _cartService.canAddToCart(product, quantityToAdd);
  }

  InputDecoration _getInputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: _primaryColor, size: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _errorColor),
      ),
      fillColor: _cardColor,
      filled: true,
      labelStyle: TextStyle(color: _textSecondary, fontSize: 14),
      hintStyle:
          TextStyle(color: _textSecondary.withValues(alpha: 0.6), fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, {Widget? action}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _primaryColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _buildPaymentMethodTile(
      PaymentMethod method, String label, IconData icon) {
    final isSelected = _method == method;
    return InkWell(
      onTap: () {
        _cartService.updatePaymentMethod(method);
        setState(() {});
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? _primaryColor.withValues(alpha: 0.1) : _cardColor,
          border: Border.all(
            color: isSelected ? _primaryColor : Theme.of(context).colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? _primaryColor : _textSecondary,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? _primaryColor : _textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
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
                'Cannot add $productName. Only ${availableStock.toStringAsFixed(1)} units available.',
              ),
            ),
          ],
        ),
        backgroundColor: _warningColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _handleScannedBarcode(String rawValue) async {
    final barcode = rawValue.trim();
    if (barcode.isEmpty) return;
    final products =
        Hive.box<Product>(Boxes.products).values.where((p) => p.active);
    Product? match;
    for (final product in products) {
      if (product.barcode?.trim() == barcode) {
        match = product;
        break;
      }
    }
    _barcodeInputController.clear();
    if (match == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'No product is assigned to barcode "$barcode". Add it in Product Management first.'),
        backgroundColor: _warningColor,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final product = match;
    final increment =
        (product.unit == UnitType.kg || product.unit == UnitType.sqft)
            ? 0.5
            : 1.0;
    if (!_canAddToCart(product, increment)) {
      _showStockLimitMessage(product.name, _getAvailableStock(product));
      return;
    }
    final item = SaleItem()
      ..productId = product.id
      ..qty = increment
      ..sellingPrice = product.sellingPrice
      ..costPrice = product.costPrice
      ..subtotal = product.sellingPrice * increment
      ..unitLabel = product.unit.name;
    _cartService.addItem(item);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Added ${product.name} to the bill'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _openCameraBarcodeScanner() async {
    if (!isCameraScannerSupported) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Camera scanning is not available on this platform. Use a USB barcode scanner or type the barcode.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (value != null && mounted) await _handleScannedBarcode(value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Shortcuts are only active while this tab is the visible one and no
    // dialog / pushed page sits on top of it.
    _tabVisible = TickerMode.of(context);
    _routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
  }

  // ---------------------------------------------------------------------
  // Keyboard shortcuts
  //   F2            focus the scan / quick-add field
  //   F3 | Ctrl+F   browse products
  //   Ctrl+Enter    complete the sale
  //   Ctrl+P        print the most recent invoice
  //   Esc           clear the scan field
  // ---------------------------------------------------------------------
  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!mounted || !_tabVisible || !_routeCurrent) return false;
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;

    if (key == LogicalKeyboardKey.f2) {
      _focusScanField();
      return true;
    }
    if (key == LogicalKeyboardKey.f3 ||
        (ctrl && key == LogicalKeyboardKey.keyF)) {
      _openProductPicker();
      return true;
    }
    if (ctrl &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      if (items.isNotEmpty && !_processing) _handleCheckout();
      return true;
    }
    if (ctrl && key == LogicalKeyboardKey.keyP) {
      _printLastInvoice();
      return true;
    }
    if (key == LogicalKeyboardKey.escape && _scanFocus.hasFocus) {
      _barcodeInputController.clear();
      _scanFocus.unfocus();
      return true;
    }
    return false;
  }

  void _focusScanField() {
    _scanFocus.requestFocus();
    _barcodeInputController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _barcodeInputController.text.length,
    );
  }

  void _addProductToCart(Product product) {
    final increment =
        (product.unit == UnitType.kg || product.unit == UnitType.sqft)
            ? 0.5
            : 1.0;
    if (_canAddToCart(product, increment)) {
      final item = SaleItem()
        ..productId = product.id
        ..qty = increment
        ..sellingPrice = product.sellingPrice
        ..costPrice = product.costPrice
        ..subtotal = product.sellingPrice * increment
        ..unitLabel = product.unit.name;
      _cartService.addItem(item);
    } else {
      _showStockLimitMessage(product.name, _getAvailableStock(product));
    }
  }

  Future<void> _openProductPicker({String? query}) async {
    final selected = await Navigator.of(context).push<Product>(
      MaterialPageRoute(
        builder: (_) => ProductSelectionScreen(initialQuery: query),
      ),
    );
    if (selected != null && mounted) _addProductToCart(selected);
  }

  /// Enter in the quick-add field: an exact barcode adds that product, a name
  /// with a single match adds it, several matches open the product list with
  /// the text pre-filled.
  Future<void> _handleScanSubmit(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    final lower = text.toLowerCase();
    final active = Hive.box<Product>(Boxes.products)
        .values
        .where((p) => p.active)
        .toList();

    final isBarcode = active.any((p) => (p.barcode ?? '').trim() == text);
    final byName =
        active.where((p) => p.name.toLowerCase().contains(lower)).toList();

    if (isBarcode || byName.isEmpty) {
      await _handleScannedBarcode(text);
    } else if (byName.length == 1) {
      _barcodeInputController.clear();
      _addProductToCart(byName.first);
    } else {
      _barcodeInputController.clear();
      await _openProductPicker(query: text);
    }
    if (mounted) _scanFocus.requestFocus();
  }

  Future<void> _printSale(Sale sale) async {
    final printOption = await showPrintOptionDialog(context, sale);
    if (printOption != null) {
      await _handlePrintInvoice(sale, printOption);
    }
  }

  Future<void> _printLastInvoice() async {
    final sales = Hive.box<Sale>(Boxes.sales).values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (sales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No invoices to print yet.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    await _printSale(sales.first);
  }

  Future<void> _editSale(Sale sale) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => EditInvoiceScreen(sale: sale)),
    );
    if (result == true && mounted) setState(() {});
  }

  Future<void> _confirmDeleteSale(Sale sale) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Invoice?'),
            content:
                Text('Are you sure you want to delete invoice ${sale.id}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirm) await _deleteInvoice(sale);
  }

  // ---------------------------------------------------------------------
  // UI building blocks
  // ---------------------------------------------------------------------
  ColorScheme get _cs => Theme.of(context).colorScheme;

  Color get _successText => Theme.of(context).brightness == Brightness.dark
      ? Colors.green.shade300
      : Colors.green.shade700;

  static const List<FontFeature> _tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  Widget _card({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: _cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _cs.outlineVariant),
      ),
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _shortcutHint() {
    Widget chip(String keys, String label) {
      return Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _cs.outlineVariant),
              ),
              child: Text(
                keys,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: _cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Wrap(
      runSpacing: 6,
      children: [
        chip('F2', 'Scan / quick add'),
        chip('F3', 'Browse products'),
        chip('Ctrl+Enter', 'Complete sale'),
        chip('Ctrl+P', 'Print last invoice'),
        chip('Esc', 'Clear field'),
      ],
    );
  }

  Widget _buildScanCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Quick Add', Icons.qr_code_scanner),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _barcodeInputController,
                  focusNode: _scanFocus,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _handleScanSubmit,
                  decoration: _getInputDecoration(
                    label: 'Scan barcode or type a product name',
                    icon: Icons.qr_code_2,
                    hint: 'Press Enter to add  (F2 to focus)',
                  ),
                ),
              ),
              if (isCameraScannerSupported) ...[
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Scan with camera',
                  onPressed: _openCameraBarcodeScanner,
                  icon: const Icon(Icons.camera_alt),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'USB scanner: press Enter. One match adds automatically; multiple matches show results.',
            style: TextStyle(fontSize: 12, color: _textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildCartSection(List<Product> products) {
    return ShoppingCartSection(
      items: items,
      products: products,
      onClearAll: () {
        _cartService.clearCart();
        _customerName.clear();
        _customerPhone.clear();
        _discountController.clear();
        _customerGstin.clear();
        setState(() {
          _applyGst = false;
          _interstateSale = false;
        });
      },
      onAddProduct: _addProductToCart,
      onUpdateCartItem: (item, product, index) {
        item.subtotal = item.qty * item.sellingPrice;
        _cartService.updateItem(index, item);
      },
      onRemoveCartItem: (item, product, index) {
        _cartService.removeItem(index);
      },
    );
  }

  Widget _buildCustomerCard() {
    return _card(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Customer Information', Icons.person_outline),
          const SizedBox(height: 16),
          TextField(
            controller: _customerName,
            textInputAction: TextInputAction.next,
            decoration: _getInputDecoration(
              label: 'Customer Name',
              icon: Icons.person_outline,
              hint: 'Optional',
            ),
            onChanged: (value) {
              _cartService.updateCustomerInfo(value, _customerPhone.text);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _customerPhone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            decoration: _getInputDecoration(
              label: 'Phone Number',
              icon: Icons.phone_outlined,
              hint: 'Optional',
            ),
            onChanged: (value) {
              _cartService.updateCustomerInfo(_customerName.text, value);
            },
          ),
          const SizedBox(height: 20),
          _buildSectionHeader('Payment Method', Icons.payment_outlined),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildPaymentMethodTile(
                  PaymentMethod.cash,
                  'Cash',
                  Icons.payments_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPaymentMethodTile(
                  PaymentMethod.card,
                  'Card',
                  Icons.credit_card_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPaymentMethodTile(
                  PaymentMethod.upi,
                  'UPI',
                  Icons.qr_code_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsCard() {
    return _card(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Discount & Tax', Icons.discount_outlined),
          const SizedBox(height: 16),
          TextField(
            controller: _discountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _getInputDecoration(
              label: 'Discount Amount',
              icon: Icons.discount_outlined,
              hint: 'Enter discount amount (optional)',
            ),
            onChanged: (value) {
              final discount = double.tryParse(value) ?? 0.0;
              final clampedDiscount = discount.clamp(0.0, _subtotal);
              _cartService.updateDiscount(clampedDiscount);
            },
          ),
          const SizedBox(height: 12),
          if (_gstAvailable) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Apply GST'),
              subtitle: const Text('Tax is calculated after discount.'),
              value: _applyGst,
              onChanged: (value) => setState(() {
                _applyGst = value;
                if (value) {
                  _gstInclusive = Hive.box<dynamic>('app_settings')
                      .get('gst_price_inclusive', defaultValue: false) as bool;
                }
              }),
            ),
            if (_applyGst) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Interstate sale (IGST)'),
                subtitle: const Text('Leave unchecked for CGST + SGST.'),
                value: _interstateSale,
                onChanged: (value) =>
                    setState(() => _interstateSale = value ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Prices already include GST'),
                subtitle: const Text(
                    'GST is included in the listed price.'),
                value: _gstInclusive,
                onChanged: (value) =>
                    setState(() => _gstInclusive = value ?? false),
              ),
              TextField(
                controller: _customerGstin,
                textCapitalization: TextCapitalization.characters,
                decoration: _getInputDecoration(
                  label: 'Customer GSTIN (optional)',
                  icon: Icons.verified_outlined,
                  hint: 'For B2B invoices',
                ),
              ),
            ],
          ] else
            Text(
              'GST is off. An admin can enable it in settings.',
              style: TextStyle(fontSize: 12, color: _textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
    double size = 14,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: size, color: _cs.onSurfaceVariant),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: size,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: color ?? _cs.onSurface,
              fontFeatures: _tabularFigures,
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkoutButton({bool compact = false}) {
    final enabled = items.isNotEmpty && !_processing;
    return FilledButton.icon(
      onPressed: enabled ? _handleCheckout : null,
      icon: const Icon(Icons.check_circle_outline),
      label: Text(compact ? 'Complete Sale' : 'Complete Sale  (Ctrl+Enter)'),
      style: FilledButton.styleFrom(
        minimumSize: Size(compact ? 170 : double.infinity, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Totals + (optionally) the Complete Sale button.
  Widget _buildSummaryCard(
    NumberFormat cur,
    String invoiceId, {
    required bool showButton,
  }) {
    return _card(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _summaryRow('Invoice ID', invoiceId, size: 13),
          Divider(height: 20, color: _cs.outlineVariant),
          _summaryRow('Subtotal', cur.format(_subtotal)),
          _summaryRow('Estimated profit', cur.format(_estimatedProfit),
              color: _successText),
          if (_discount > 0)
            _summaryRow('Discount', '-${cur.format(_discount)}'),
          if (_applyGst) ...[
            _summaryRow('Taxable value', cur.format(_taxableAmount)),
            if (!_interstateSale) ...[
              _summaryRow('CGST', cur.format(_cgstAmount)),
              _summaryRow('SGST', cur.format(_sgstAmount)),
            ] else
              _summaryRow('IGST', cur.format(_igstAmount)),
          ],
          Divider(height: 24, color: _cs.outlineVariant),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Total',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _cs.onSurface,
                ),
              ),
              Text(
                cur.format(_grandTotal),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: _cs.primary,
                  fontFeatures: _tabularFigures,
                ),
              ),
            ],
          ),
          if (showButton) ...[
            const SizedBox(height: 16),
            _checkoutButton(),
          ],
        ],
      ),
    );
  }

  /// Pinned bar for narrow layouts: always visible total + action.
  Widget _buildCompactCheckoutBar(NumberFormat cur) {
    return Material(
      color: _cs.surface,
      elevation: 8,
      shadowColor: _cs.shadow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$itemCount item${itemCount == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontSize: 12, color: _cs.onSurfaceVariant),
                    ),
                    Text(
                      cur.format(_grandTotal),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _cs.primary,
                        fontFeatures: _tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              _checkoutButton(compact: true),
            ],
          ),
        ),
      ),
    );
  }


  // ---------------------------------------------------------------------
  // Frequently sold items (one-tap add) and right-click menu for invoices
  // ---------------------------------------------------------------------
  List<Product> _frequentProducts(List<Product> products) {
    final salesBox = Hive.box<Sale>(Boxes.sales);
    if (salesBox.length != _freqSalesLen) {
      final counts = <String, int>{};
      for (final sale in salesBox.values) {
        for (final item in sale.items) {
          counts[item.productId] = (counts[item.productId] ?? 0) + 1;
        }
      }
      final ids = counts.keys.toList()
        ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
      _freqIds = ids.take(24).toList();
      _freqSalesLen = salesBox.length;
    }
    final byId = {for (final p in products) p.id: p};
    final result = <Product>[];
    for (final id in _freqIds) {
      final product = byId[id];
      if (product != null && product.stock > 0) result.add(product);
      if (result.length >= 8) break;
    }
    return result;
  }

  List<Widget> _quickAddSection(List<Product> products, NumberFormat cur) {
    final frequent = _frequentProducts(products);
    if (frequent.isEmpty) return const [];

    return [
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Frequently Sold', Icons.bolt_outlined),
            const SizedBox(height: 12),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: frequent.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final product = frequent[index];
                  return SizedBox(
                    width: 184,
                    child: Material(
                      color: _cs.surfaceContainerHighest.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _addProductToCart(product),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                product.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      cur.format(product.sellingPrice),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _cs.primary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: _cs.primary,
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Icon(
                                      Icons.add,
                                      size: 19,
                                      color: _cs.onPrimary,
                                    ),
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
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Swipe to see more',
              style: TextStyle(
                fontSize: 11,
                color: _cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  Future<void> _showSaleMenu(Offset position, Sale sale) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem<String>(
          value: 'whatsapp',
          child: Row(children: [
            WhatsAppIcon(size: 18),
            SizedBox(width: 12),
            Text('Send on WhatsApp'),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'print',
          child: Row(children: [
            Icon(Icons.print, size: 18),
            SizedBox(width: 12),
            Text('Print'),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit, size: 18),
            SizedBox(width: 12),
            Text('Edit'),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete, size: 18),
            SizedBox(width: 12),
            Text('Delete'),
          ]),
        ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'whatsapp':
        await WhatsAppService.sendInvoice(context, sale);
        break;
      case 'print':
        await _printSale(sale);
        break;
      case 'edit':
        await _editSale(sale);
        break;
      case 'delete':
        await _confirmDeleteSale(sale);
        break;
    }
  }

  Widget _buildHistoryRow(Sale sale, NumberFormat cur) {
    final dateText = DateFormat('MMM dd, yyyy - hh:mm a').format(sale.date);
    final amount = Text(
      cur.format(sale.totalAmount),
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: _cs.primary,
        fontFeatures: _tabularFigures,
      ),
    );

    final whatsappAction = IconButton(
      tooltip: 'Send on WhatsApp',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: const WhatsAppIcon(size: 24),
      onPressed: () => WhatsAppService.sendInvoice(context, sale),
    );
    final printAction = IconButton(
      tooltip: 'Print invoice',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: Icon(Icons.print_outlined, color: _cs.primary),
      onPressed: () => _printSale(sale),
    );
    final editAction = IconButton(
      tooltip: 'Edit invoice',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: Icon(Icons.edit_outlined, color: _cs.primary),
      onPressed: () => _editSale(sale),
    );
    final deleteAction = IconButton(
      tooltip: 'Delete invoice',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: Icon(Icons.delete_outline, color: _cs.error),
      onPressed: () => _confirmDeleteSale(sale),
    );

    final row = LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: EdgeInsets.all(compact ? 14 : 10),
          decoration: BoxDecoration(
            color: _cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            sale.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        amount,
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      dateText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: _cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Divider(height: 1, color: _cs.outlineVariant),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        whatsappAction,
                        printAction,
                        editAction,
                        deleteAction,
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sale.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: _cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    amount,
                    const SizedBox(width: 8),
                    whatsappAction,
                    printAction,
                    editAction,
                    deleteAction,
                  ],
                ),
        );
      },
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) =>
          _showSaleMenu(details.globalPosition, sale),
      child: row,
    );
  }

  Widget _buildHistoryCard(List<Sale> recentSales, NumberFormat cur) {
    return _card(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Invoice History', Icons.history),
          const SizedBox(height: 12),
          if (recentSales.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No recent invoices.',
                  style: TextStyle(color: _cs.onSurfaceVariant),
                ),
              ),
            )
          else
            ...recentSales.map((sale) => _buildHistoryRow(sale, cur)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = Hive.box<Product>(Boxes.products)
        .values
        .where((p) => p.active)
        .toList();
    final cur = NumberFormat.simpleCurrency(locale: 'en_IN');
    final invoiceSettings = Hive.box<dynamic>('app_settings');
    final savedPrefix = invoiceSettings
        .get('invoice_prefix', defaultValue: 'INV')
        .toString()
        .trim()
        .toUpperCase();
    final invoicePrefix = savedPrefix.isEmpty ? 'INV' : savedPrefix;
    final nextInvoiceNumber =
        (invoiceSettings.get('next_invoice_number', defaultValue: 1) as num)
            .toInt();
    final invoiceDatePart = DateFormat('yyyyMM').format(DateTime.now());
    final invoiceIdPreview =
        '$invoicePrefix-$invoiceDatePart-${nextInvoiceNumber.toString().padLeft(5, "0")}';

    // Last 5 invoices, newest first.
    final allSales = Hive.box<Sale>(Boxes.sales).values.toList()
      ..sort((a, b) => b.date.millisecondsSinceEpoch
          .compareTo(a.date.millisecondsSinceEpoch));
    final recentSales = allSales.take(5).toList();

    final body = LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= ResponsiveBreakpoints.desktop;

        if (wide) {
          // Two panes: products + cart on the left; customer, options and a
          // pinned total / Complete Sale panel on the right.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _shortcutHint(),
                      const SizedBox(height: 12),
                      _buildScanCard(),
                      const SizedBox(height: 16),
                      ..._quickAddSection(products, cur),
                      _buildCartSection(products),
                      const SizedBox(height: 24),
                      _buildHistoryCard(recentSales, cur),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 400,
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                        child: Column(
                          children: [
                            _buildCustomerCard(),
                            if (items.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _buildOptionsCard(),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 16, 16),
                      child: _buildSummaryCard(cur, invoiceIdPreview,
                          showButton: true),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        // Narrow: single column with a pinned total bar.
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCustomerCard(),
                    const SizedBox(height: 16),
                    _buildScanCard(),
                    const SizedBox(height: 16),
                    ..._quickAddSection(products, cur),
                    _buildCartSection(products),
                    const SizedBox(height: 16),
                    if (items.isNotEmpty) ...[
                      _buildOptionsCard(),
                      const SizedBox(height: 16),
                      _buildSummaryCard(cur, invoiceIdPreview,
                          showButton: false),
                      const SizedBox(height: 16),
                    ],
                    const SizedBox(height: 16),
                    _buildHistoryCard(recentSales, cur),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            if (items.isNotEmpty) _buildCompactCheckoutBar(cur),
          ],
        );
      },
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: null,
      body: _fadeAnimation != null
          ? FadeTransition(opacity: _fadeAnimation!, child: body)
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Future<void> _handleCheckout() async {
    if (_processing || items.isEmpty) return;
    setState(() => _processing = true);
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Processing sale...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final productsBox = Hive.box<Product>(Boxes.products);
      for (final item in items) {
        final product = productsBox.get(item.productId);
        final taxable = _lineTaxableAmount(item);
        final rate = _applyGst ? _lineGstRate(item) : 0.0;
        item
          ..hsnCode = product?.hsnCode ?? ''
          ..gstRate = rate
          ..taxableAmount = taxable
          ..cgstAmount = _lineCgst(item)
          ..sgstAmount = _lineSgst(item)
          ..igstAmount = _lineIgst(item);
      }
      final salesBox = Hive.box<Sale>(Boxes.sales);
      final invoiceSettings = Hive.box<dynamic>('app_settings');
      final prefix = invoiceSettings
          .get('invoice_prefix', defaultValue: 'INV')
          .toString()
          .trim()
          .toUpperCase();
      final safePrefix = prefix.isEmpty ? 'INV' : prefix;
      final nextNumber =
          (invoiceSettings.get('next_invoice_number', defaultValue: 1) as num)
              .toInt();
      final datePart = DateFormat('yyyyMM').format(DateTime.now());
      final id =
          '$safePrefix-$datePart-${nextNumber.toString().padLeft(5, "0")}';
      await invoiceSettings.put('next_invoice_number', nextNumber + 1);

      final sale = Sale()
        ..id = id
        ..date = DateTime.now()
        ..items = items.map((e) => e).toList()
        ..totalAmount = _grandTotal
        ..totalCost = cost
        ..profit = _estimatedProfit
        ..payment = _method
        ..customerName = _customerName.text.trim()
        ..customerPhone = _customerPhone.text.trim()
        ..discount = _discount
        ..gstEnabled = _applyGst
        ..gstRate = _applyGst ? _gstRate : 0.0
        ..taxableAmount = _taxableAmount
        ..cgstAmount = _cgstAmount
        ..sgstAmount = _sgstAmount
        ..igstAmount = _igstAmount
        ..customerGstin = _customerGstin.text.trim().toUpperCase()
        ..interstateSale = _interstateSale
        ..gstInclusive = _applyGst && _gstInclusive
        ..userId = context.read<AuthService>().currentUser?.id ?? '';

      await salesBox.put(sale.id, sale);

      // Update product stock
      for (final item in items) {
        final product = productsBox.get(item.productId);
        if (product != null) {
          product.stock = (product.stock - item.qty).clamp(0, double.infinity);
          await product.save();
        }
      }

      // Journal sync is retryable at next startup; it must not undo a completed POS sale.
      try {
        await FinanceSourceSyncService().syncSale(
          sale: sale,
          accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts),
          transactionsBox: Hive.box<FinanceTransaction>(Boxes.financeTransactions),
          postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
          categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
          partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
        );
      } catch (financeError) {
        await FinanceSourceSyncService.recordIssue(
          Hive.box<dynamic>('app_settings'),
          'Sale ${sale.id}: $financeError',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sale saved; finance journal sync will retry on next launch: $financeError'),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
      }

      // Show print option selection dialog
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        final printOption = await showPrintOptionDialog(context, sale);

        if (printOption != null) {
          await _handlePrintInvoice(sale, printOption);
        }

        _cartService.clearCart();
        _customerName.clear();
        _customerPhone.clear();
        _discountController.clear();
        _customerGstin.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Sale completed successfully!'),
                      Text('Invoice ID: $id',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: _successColor,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing sale: $e'),
            backgroundColor: _errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // Handle printing invoice based on selected option
  Future<void> _handlePrintInvoice(Sale sale, PrintOption printOption) async {
    try {
      final invoiceService = InvoiceService();

      if (printOption == PrintOption.thermal) {
        // Generate thermal printer format
        await invoiceService.generateInvoice(sale, useThermalPrinter: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Thermal format generated successfully!'),
                ],
              ),
              backgroundColor: _successColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
      } else {
        // Non-GST sales should go straight to a normal invoice PDF.
        // Only GST-enabled sales need a choice between normal and tax invoice.
        var includeGst = false;
        if (sale.gstEnabled) {
          final selectedType = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Choose PDF type'),
              content: const Text(
                  'Choose invoice type.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Normal PDF'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('GST Tax Invoice'),
                ),
              ],
            ),
          );
          if (selectedType == null) return;
          includeGst = selectedType;
        }

        final sharePdf = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Invoice PDF'),
            content: const Text('How would you like to send the invoice?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Save PDF'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share PDF'),
              ),
            ],
          ),
        );
        if (sharePdf == null) return;
        await PdfService.generateInvoice(
          sale,
          includeGST: includeGst,
          share: sharePdf,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Text(sharePdf
                      ? 'Invoice PDF ready to share!'
                      : 'Invoice PDF saved!'),
                ],
              ),
              backgroundColor: _successColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating invoice: $e'),
            backgroundColor: _errorColor,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  // New method to delete an invoice
  Future<void> _deleteInvoice(Sale sale) async {
    final salesBox = Hive.box<Sale>(Boxes.sales);
    final productsBox = Hive.box<Product>(Boxes.products);

    // Reverse immutable journal history before deleting the operational invoice.
    try {
      await FinanceSourceSyncService().reverseSale(
        sale: sale,
        accountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts),
        transactionsBox: Hive.box<FinanceTransaction>(Boxes.financeTransactions),
        postingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
        categoriesBox: Hive.box<FinanceCategory>(Boxes.financeCategories),
        partiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
      );
    } catch (financeError) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invoice was not deleted because its journal reversal failed: $financeError'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Remove sale from Hive
    await salesBox.delete(sale.id);

    // Update product stocks
    for (final item in sale.items) {
      final product = productsBox.get(item.productId);
      if (product != null) {
        product.stock = (product.stock + item.qty).clamp(0, double.infinity);
        await product.save();
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.delete_forever, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Invoice ${sale.id} deleted successfully.',
              ),
            ),
          ],
        ),
        backgroundColor: _errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    setState(() {}); // Refresh the UI
  }
}
