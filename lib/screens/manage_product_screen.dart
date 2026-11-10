import 'package:flutter/material.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/boxes.dart';
import '../utils/platform_support.dart';
import 'barcode_scanner_screen.dart';
import '../widgets/responsive_page.dart';

class ManageProductScreen extends StatefulWidget {
  final Product? product;

  const ManageProductScreen({super.key, this.product});

  @override
  State<ManageProductScreen> createState() => _ManageProductScreenState();
}

class _ManageProductScreenState extends State<ManageProductScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _sellingPriceController;
  late final TextEditingController _costPriceController;
  late final TextEditingController _stockController;
  late final TextEditingController _categoryController;
  late final TextEditingController _subCategoryController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _hsnController;
  late final TextEditingController _gstRateController;
  late UnitType _selectedUnit;
  bool _isLoading = false;
  double _profitMargin = 0;
  bool _showProfitMargin = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _sellingPriceController = TextEditingController(
        text: widget.product?.sellingPrice.toString() ?? '0');
    _costPriceController = TextEditingController(
        text: widget.product?.costPrice.toString() ?? '0');
    _stockController =
        TextEditingController(text: widget.product?.stock.toString() ?? '0');
    _categoryController =
        TextEditingController(text: widget.product?.category ?? 'General');
    _subCategoryController =
        TextEditingController(text: widget.product?.subCategory ?? '');
    _barcodeController =
        TextEditingController(text: widget.product?.barcode ?? '');
    _hsnController = TextEditingController(text: widget.product?.hsnCode ?? '');
    _gstRateController =
        TextEditingController(text: widget.product?.gstRate?.toString() ?? '');
    _selectedUnit = widget.product?.unit ?? UnitType.pcs;

    // Calculate initial profit margin
    _calculateProfitMargin();

    // Add listeners for price changes
    _sellingPriceController.addListener(_calculateProfitMargin);
    _costPriceController.addListener(_calculateProfitMargin);
  }

  void _calculateProfitMargin() {
    final selling = double.tryParse(_sellingPriceController.text) ?? 0;
    final cost = double.tryParse(_costPriceController.text) ?? 0;
    setState(() {
      _profitMargin = selling - cost;
      _showProfitMargin = cost > 0;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sellingPriceController.dispose();
    _costPriceController.dispose();
    _stockController.dispose();
    _categoryController.dispose();
    _subCategoryController.dispose();
    _barcodeController.dispose();
    _hsnController.dispose();
    _gstRateController.dispose();
    super.dispose();
  }

  Future<void> _scanProductBarcode() async {
    if (!isCameraScannerSupported) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Camera unavailable. Enter or scan the barcode manually.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (value != null && mounted) {
      setState(() => _barcodeController.text = value);
    }
  }

  Future<void> _saveProduct() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a product name'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final gstRateText = _gstRateController.text.trim();
    final gstRate = gstRateText.isEmpty ? null : double.tryParse(gstRateText);
    if (gstRateText.isNotEmpty &&
        (gstRate == null || gstRate < 0 || gstRate > 100)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Enter 0–100, or leave blank for the default.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final box = Hive.box<Product>(Boxes.products);
      final barcode = _barcodeController.text.trim();
      final duplicate = barcode.isNotEmpty &&
          box.values.any((existing) =>
              existing.id != widget.product?.id &&
              existing.barcode?.trim() == barcode);
      if (duplicate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('That barcode is already assigned to another product.')),
        );
        return;
      }
      final product = widget.product ?? Product()
        ..id = widget.product?.id ?? const Uuid().v4()
        ..active = true;

      product
        ..name = _nameController.text
        ..sellingPrice = double.tryParse(_sellingPriceController.text) ?? 0
        ..costPrice = double.tryParse(_costPriceController.text) ?? 0
        ..stock = double.tryParse(_stockController.text) ?? 0
        ..category = _categoryController.text
        ..subCategory = _subCategoryController.text
        ..barcode = barcode.isEmpty ? null : barcode
        ..hsnCode = _hsnController.text.trim()
        ..gstRate = gstRate
        ..unit = _selectedUnit;

      if (widget.product == null) {
        await box.put(product.id, product);
      } else {
        await product.save();
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(widget.product == null
                    ? 'Product added successfully!'
                    : 'Product updated successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      'Error ${widget.product == null ? 'adding' : 'updating'} product: $e'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showDeleteConfirmation(BuildContext context) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.warning_amber_rounded,
                      color: Colors.red),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Delete Product?',
                    style: TextStyle(fontSize: 20),
                  ),
                ),
              ],
            ),
            content: Text(
              'Are you sure you want to delete "${widget.product!.name}"? This action cannot be undone.',
              style: const TextStyle(fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.delete_forever),
                label: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted) return;

    if (confirm) {
      await widget.product!.delete();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.delete_forever, color: Colors.white),
              SizedBox(width: 12),
              Text('Product deleted successfully'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget content,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.55)),
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
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            content,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.product != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        title: Text(isEditing ? 'Edit ${widget.product!.name}' : 'Add Product'),
        elevation: 0,
        centerTitle: false,
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _saveProduct,
              icon: const Icon(Icons.save_rounded),
              tooltip: 'Save Product',
            ),
        ],
      ),
      body: ResponsivePage(
          maxWidth: 900,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Basic Info Card
                _buildSectionCard(
                  title: 'Basic Information',
                  icon: Icons.info_outline,
                  content: Column(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Product Name',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.inventory_2_outlined),
                          hintText: 'Enter product name',
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _categoryController,
                              decoration: InputDecoration(
                                labelText: 'Category',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                prefixIcon: const Icon(Icons.category_outlined),
                                hintText: 'e.g., Flowers',
                              ),
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _subCategoryController,
                              decoration: InputDecoration(
                                labelText: 'Sub-category (Optional)',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                prefixIcon:
                                    const Icon(Icons.subdirectory_arrow_right),
                                hintText: 'e.g., Roses',
                              ),
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                _buildSectionCard(
                  title: 'Barcode',
                  icon: Icons.qr_code_scanner,
                  content: TextFormField(
                    controller: _barcodeController,
                    decoration: InputDecoration(
                      labelText: 'Barcode / SKU',
                      hintText:
                          'Scan or enter the barcode.',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.qr_code_2),
                      suffixIcon: IconButton(
                        onPressed: _isLoading ? null : _scanProductBarcode,
                        icon: const Icon(Icons.qr_code_scanner),
                        tooltip: 'Scan barcode with camera',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _buildSectionCard(
                  title: 'Tax Classification',
                  icon: Icons.receipt_long_outlined,
                  content: Column(
                    children: [
                      TextFormField(
                        controller: _hsnController,
                        decoration: InputDecoration(
                          labelText: 'HSN / SAC code (optional)',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.numbers),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _gstRateController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Product GST rate (%)',
                          helperText:
                              'Blank = default GST; 0 = zero-rated.',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.percent),
                        ),
                        validator: (value) {
                          final rate = double.tryParse(value?.trim() ?? '');
                          if (rate == null || rate < 0 || rate > 100) {
                            return 'Enter a rate from 0 to 100';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Pricing Card
                _buildSectionCard(
                  title: 'Pricing Details',
                  icon: Icons.payments_outlined,
                  content: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _sellingPriceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Selling Price',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                prefixIcon: const Icon(Icons.sell_outlined),
                                prefixText: '₹',
                                hintText: '0.00',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _costPriceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Cost Price',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                prefixIcon:
                                    const Icon(Icons.shopping_cart_outlined),
                                prefixText: '₹',
                                hintText: '0.00',
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_showProfitMargin) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _profitMargin > 0
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .tertiaryContainer,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _profitMargin > 0
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.25)
                                  : Theme.of(context)
                                      .colorScheme
                                      .tertiary
                                      .withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _profitMargin > 0
                                    ? Icons.trending_up
                                    : Icons.trending_down,
                                color: _profitMargin > 0
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.tertiary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Profit Margin: ₹${_profitMargin.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: _profitMargin > 0
                                      ? Colors.green
                                      : Colors.orange,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Inventory Card
                _buildSectionCard(
                  title: 'Inventory Details',
                  icon: Icons.inventory_2_outlined,
                  content: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _stockController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Stock',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.inventory_2_outlined),
                            hintText: '0',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<UnitType>(
                          initialValue: _selectedUnit,
                          decoration: InputDecoration(
                            labelText: 'Unit',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.straighten),
                          ),
                          items: UnitType.values
                              .map((unit) => DropdownMenuItem(
                                    value: unit,
                                    child: Text(unit.name.toUpperCase()),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedUnit = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // Action Buttons Section
                const SizedBox(height: 40),
                Row(
                  children: [
                    // Save Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _saveProduct,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          _isLoading
                              ? 'Saving...'
                              : (isEditing ? 'Update Product' : 'Save Product'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    // Delete Button (only for existing products)
                    if (widget.product != null) ...[
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () => _showDeleteConfirmation(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          side: BorderSide(color: theme.colorScheme.error),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.delete_forever, size: 20),
                        label: const Text(
                          'Delete',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          )),
    );
  }
}
