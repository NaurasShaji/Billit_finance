import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import '../../models/models.dart';
import '../../services/boxes.dart';
import '../widgets/app_components.dart';

class ProductSelectionScreen extends StatefulWidget {
  const ProductSelectionScreen({super.key, this.initialQuery});

  /// Optional text to pre-fill the search box with.
  final String? initialQuery;

  @override
  State<ProductSelectionScreen> createState() => _ProductSelectionScreenState();
}

class _ProductSelectionScreenState extends State<ProductSelectionScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory;
  UnitType? _selectedUnitType;
  bool _showOnlyInStock = false;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

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

    final initial = widget.initialQuery?.trim();
    if (initial != null && initial.isNotEmpty) {
      _searchController.text = initial;
      _searchQuery = initial;
    }
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });

    _slideController.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedCategory = null;
      _selectedUnitType = null;
      _showOnlyInStock = false;
    });
  }

  /// Applies current filters consistently to displayed results and barcode scans.
  List<Product> _applyFilters(Iterable<Product> source) {
    final q = _searchQuery.trim().toLowerCase();
    return source.where((p) {
      if (!p.active) return false;
      final matchesSearch = q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q) ||
          p.subCategory.toLowerCase().contains(q) ||
          (p.barcode ?? '').toLowerCase().contains(q);
      final matchesCategory =
          _selectedCategory == null || p.category == _selectedCategory;
      final matchesUnit =
          _selectedUnitType == null || p.unit == _selectedUnitType;
      final matchesStock = !_showOnlyInStock || p.stock > 0;
      return matchesSearch && matchesCategory && matchesUnit && matchesStock;
    }).toList();
  }

  /// Supports USB barcode scanners that submit a value followed by Enter.
  void _submitSearch() {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return;
    final matches = _applyFilters(Hive.box<Product>(Boxes.products).values);
    final exact = matches
        .where((p) => (p.barcode ?? '').trim().toLowerCase() == q)
        .toList();
    final product = exact.isNotEmpty
        ? exact.first
        : (matches.length == 1 ? matches.first : null);
    if (product != null && product.stock > 0) {
      Navigator.of(context).pop(product);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Scaffold(
      resizeToAvoidBottomInset: true, // Ensures resizing when keyboard appears
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Select Products',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: theme.primaryColor,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _clearFilters,
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear filters',
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          // Keep search and filters fixed while the product results scroll.
          child: Column(
            children: [
              Material(
                color: theme.primaryColor,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSearchSection(theme, isTablet),
                    _buildFilterSection(theme, isTablet),
                    Container(
                      height: 16,
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildProductsList(theme, isTablet)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchSection(ThemeData theme, bool isTablet) {
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);
    final horizontalPadding = isTablet ? 24.0 : 16.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 12),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          autofocus: isDesktop,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _submitSearch(),
          decoration: InputDecoration(
            hintText: 'Search by name, barcode or category...',
            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            prefixIcon: Icon(Icons.search, color: theme.primaryColor, size: 24),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(tooltip: 'Clear', 
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSection(ThemeData theme, bool isTablet) {
    final productsBox = Hive.box<Product>(Boxes.products);
    final categories = productsBox.values
        .where((p) => p.active)
        .map((p) => p.category)
        .toSet()
        .toList()
      ..sort();

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 24.0 : 16.0,
        vertical: 8.0,
      ),
      child: Column(
        children: [
          // Filter chips row
          Row(
            children: [
              Expanded(
                child: _buildFilterChip(
                  'Category',
                  _selectedCategory ?? 'All Categories',
                  Icons.category,
                  () => _showCategoryPicker(categories),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFilterChip(
                  'Unit',
                  _selectedUnitType?.name ?? 'All Units',
                  Icons.straighten,
                  () => _showUnitPicker(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Stock filter
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.3)),
            ),
            child: CheckboxListTile(
              title: Text(
                'Show only in-stock items',
                style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 14),
              ),
              value: _showOnlyInStock,
              onChanged: (value) {
                setState(() {
                  _showOnlyInStock = value ?? false;
                });
              },
              checkColor: theme.primaryColor,
              activeColor: Theme.of(context).colorScheme.onPrimary,
              side: BorderSide(color: Theme.of(context).colorScheme.onPrimary),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
      String label, String value, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.onPrimary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.keyboard_arrow_down,
                color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7), size: 18),
          ],
        ),
      ),
    );
  }

  void _showCategoryPicker(List<String> categories) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select Category',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              ...['All Categories', ...categories].map((category) {
                final isSelected = category == 'All Categories'
                    ? _selectedCategory == null
                    : _selectedCategory == category;
                return ListTile(
                  title: Text(category),
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: Theme.of(context).primaryColor,
                  ),
                  onTap: () {
                    setState(() {
                      _selectedCategory =
                          category == 'All Categories' ? null : category;
                    });
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showUnitPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select Unit Type',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              ...[null, ...UnitType.values].map((unitType) {
                final label = unitType?.name ?? 'All Units';
                final isSelected = _selectedUnitType == unitType;
                return ListTile(
                  title: Text(label),
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: Theme.of(context).primaryColor,
                  ),
                  onTap: () {
                    setState(() {
                      _selectedUnitType = unitType;
                    });
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProductsList(ThemeData theme, bool isTablet) {
    return ValueListenableBuilder(
      valueListenable: Hive.box<Product>(Boxes.products).listenable(),
      builder: (context, Box<Product> box, _) {
        final filteredProducts = _applyFilters(box.values);

        if (filteredProducts.isEmpty) {
          return _buildEmptyState();
        }

        return Column(
          children: [
            // Results header
            Container(
              padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
              child: Row(
                children: [
                  Text(
                    '${filteredProducts.length} product${filteredProducts.length == 1 ? '' : 's'} found',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (_hasActiveFilters())
                    TextButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear'),
                    ),
                ],
              ),
            ),

            // Products grid/list - now scrollable within available space
            Flexible(
              child: isTablet
                  ? _buildProductsGrid(filteredProducts, theme)
                  : _buildProductsListView(filteredProducts, theme),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProductsGrid(List<Product> products, ThemeData theme) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisExtent: 170 * textScaleFactor(context),
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return _buildProductCard(product, theme, isGrid: true);
      },
    );
  }

  Widget _buildProductsListView(List<Product> products, ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildProductCard(product, theme, isGrid: false),
        );
      },
    );
  }

  Widget _buildProductCard(Product product, ThemeData theme,
      {required bool isGrid}) {
    final isOutOfStock = product.stock <= 0;
    final isLowStock = product.stock > 0 && product.stock <= 5;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isOutOfStock
            ? null
            : () {
                Navigator.of(context).pop(product);
              },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isOutOfStock ? Theme.of(context).colorScheme.surfaceContainerHighest : Theme.of(context).colorScheme.surface,
          ),
          child: isGrid
              ? _buildGridContent(product, theme, isOutOfStock, isLowStock)
              : _buildListContent(product, theme, isOutOfStock, isLowStock),
        ),
      ),
    );
  }

  Widget _buildGridContent(
      Product product, ThemeData theme, bool isOutOfStock, bool isLowStock) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                product.name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: isOutOfStock ? Theme.of(context).colorScheme.outline : Theme.of(context).colorScheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _buildStockBadge(product, isOutOfStock, isLowStock),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          product.category,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '₹${product.sellingPrice.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: isOutOfStock ? Theme.of(context).colorScheme.outline : theme.primaryColor,
                  ),
                ),
                Text(
                  'per ${product.unit.name}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            Container(
              decoration: BoxDecoration(
                color: isOutOfStock ? Theme.of(context).colorScheme.outlineVariant : theme.primaryColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: Icon(
                  isOutOfStock ? Icons.block : Icons.add_shopping_cart,
                  color: Theme.of(context).colorScheme.onPrimary,
                  size: 20,
                ),
                onPressed: isOutOfStock
                    ? null
                    : () {
                        Navigator.of(context).pop(product);
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildListContent(
      Product product, ThemeData theme, bool isOutOfStock, bool isLowStock) {
    return Row(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: theme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.inventory_2,
            color: theme.primaryColor,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: isOutOfStock ? Theme.of(context).colorScheme.outline : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  _buildStockBadge(product, isOutOfStock, isLowStock),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                product.category,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '₹${product.sellingPrice.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isOutOfStock ? Theme.of(context).colorScheme.outline : theme.primaryColor,
                    ),
                  ),
                  Text(
                    ' per ${product.unit.name}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isOutOfStock ? Theme.of(context).colorScheme.outlineVariant : theme.primaryColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: Icon(
              isOutOfStock ? Icons.block : Icons.add_shopping_cart,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            onPressed: isOutOfStock
                ? null
                : () {
                    Navigator.of(context).pop(product);
                  },
          ),
        ),
      ],
    );
  }

  Widget _buildStockBadge(Product product, bool isOutOfStock, bool isLowStock) {
    if (isOutOfStock) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Out of Stock',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onError,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (isLowStock) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Low: ${product.stock.toInt()}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${product.stock.toInt()} in stock',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
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
              'No products found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search or filters',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _clearFilters,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear Filters'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasActiveFilters() {
    return _searchQuery.isNotEmpty ||
        _selectedCategory != null ||
        _selectedUnitType != null ||
        _showOnlyInStock;
  }
}
