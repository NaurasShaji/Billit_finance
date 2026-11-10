import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../services/boxes.dart';
import '../manage_product_screen.dart';
import '../../widgets/app_components.dart';

class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key});
  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> {
  final TextEditingController _searchController = TextEditingController();
  String query = '';
  UnitType? unitFilter;
  String category = 'All';
  String subCategory = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesQuery(Product p, String q) {
    if (q.isEmpty) return true;
    return p.name.toLowerCase().contains(q) ||
        p.category.toLowerCase().contains(q) ||
        p.subCategory.toLowerCase().contains(q) ||
        p.hsnCode.toLowerCase().contains(q) ||
        (p.barcode ?? '').toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ValueListenableBuilder<Box<Product>>(
        valueListenable: Hive.box<Product>(Boxes.products).listenable(),
        builder: (context, box, _) {
          final all = box.values.where((p) => p.active).toList();
          final categories = <String>[
            'All',
            ...({for (final p in all) p.category}.toList()..sort()),
          ];
          final subcats = <String>[
            'All',
            ...({
              for (final p in all)
                if ((category == 'All' || p.category == category) &&
                    p.subCategory.trim().isNotEmpty)
                  p.subCategory
            }.toList()
              ..sort()),
          ];

          // Avoid invalid DropdownButton values after product edits/deletions.
          final effectiveCategory =
              categories.contains(category) ? category : 'All';
          final effectiveSub =
              subcats.contains(subCategory) ? subCategory : 'All';
          final q = query.trim().toLowerCase();
          final filtered = all.where((p) {
            final unitMatches = unitFilter == null || p.unit == unitFilter;
            final categoryMatches = effectiveCategory == 'All' ||
                p.category == effectiveCategory;
            final subCategoryMatches =
                effectiveSub == 'All' || p.subCategory == effectiveSub;
            return _matchesQuery(p, q) &&
                unitMatches &&
                categoryMatches &&
                subCategoryMatches;
          }).toList();

          return Column(
            children: [
              _buildHeader(
                theme,
                categories: categories,
                subcats: subcats,
                effectiveCategory: effectiveCategory,
                effectiveSub: effectiveSub,
                count: filtered.length,
              ),
              Expanded(
                child: ValueListenableBuilder<Box<dynamic>>(
                  valueListenable:
                      Hive.box<dynamic>('app_settings').listenable(),
                  builder: (context, settings, _) {
                    final view = settings
                        .get('product_view', defaultValue: 'list')
                        .toString();
                    return CustomScrollView(
                      key: const PageStorageKey<String>('inventory-scroll'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        if (filtered.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _buildEmptyState(),
                          )
                        else if (view == 'grid')
                          _buildGridView(filtered)
                        else
                          _buildListView(filtered),
                        const SliverToBoxAdapter(child: SizedBox(height: 96)),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme, {
    required List<String> categories,
    required List<String> subcats,
    required String effectiveCategory,
    required String effectiveSub,
    required int count,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search,
                  color: theme.colorScheme.onSurfaceVariant),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => query = '');
                      },
                    ),
              hintText: 'Search name, barcode, category or HSN...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              // Keep all three filters in one row. Each control takes an
              // equal share of the available width, so the containers shrink
              // with the device instead of stacking or overflowing.
              final gap = constraints.maxWidth < 380 ? 6.0 : 10.0;
              final categoryFilter = _buildFilterDropdown<String>(
                value: effectiveCategory,
                items: categories,
                label: 'Category',
                onChanged: (value) => setState(() {
                  category = value ?? 'All';
                  subCategory = 'All';
                }),
              );
              final subCategoryFilter = _buildFilterDropdown<String>(
                value: effectiveSub,
                items: subcats,
                label: 'Sub-category',
                onChanged: (value) =>
                    setState(() => subCategory = value ?? 'All'),
              );
              final unitDropdown = _buildFilterDropdown<UnitType?>(
                value: unitFilter,
                items: [null, ...UnitType.values],
                label: 'Unit',
                onChanged: (value) => setState(() => unitFilter = value),
                itemBuilder: (item) => Text(
                  item == null ? 'All units' : item.name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              );
              return Row(
                children: [
                  Expanded(child: categoryFilter),
                  SizedBox(width: gap),
                  Expanded(child: subCategoryFilter),
                  SizedBox(width: gap),
                  Expanded(child: unitDropdown),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            '$count products found',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown<T>({
    required T value,
    required List<T> items,
    required String label,
    required Function(T?) onChanged,
    Widget Function(T)? itemBuilder,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: itemBuilder != null
                        ? itemBuilder(item)
                        : Text(
                            item?.toString() ?? 'All',
                            style: const TextStyle(fontSize: 12),
                          ),
                  ))
              .toList(),
          onChanged: onChanged,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
      ),
    );
  }

  bool get _hasActiveFilters =>
      query.trim().isNotEmpty ||
      unitFilter != null ||
      category != 'All' ||
      subCategory != 'All';

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      query = '';
      unitFilter = null;
      category = 'All';
      subCategory = 'All';
    });
  }

  Widget _buildEmptyState() {
    final filtered = _hasActiveFilters;
    return AppEmptyState(
      icon: filtered ? Icons.search_off : Icons.inventory_2_outlined,
      title: filtered ? 'No products match' : 'No products yet',
      message: filtered
          ? 'Try a different search or clear the filters.'
          : 'Add your first product to start billing.',
      actions: [
        if (filtered)
          FilledButton.tonalIcon(
            onPressed: _clearFilters,
            icon: const Icon(Icons.filter_alt_off),
            label: const Text('Clear filters'),
          ),
        FilledButton.icon(
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add),
          label: const Text('Add product'),
        ),
      ],
    );
  }

  Widget _buildGridView(List<Product> products) {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 300,
          mainAxisExtent: 230 * textScaleFactor(context),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          final threshold = (Hive.box<dynamic>('app_settings')
                  .get('low_stock_threshold', defaultValue: 10) as num)
              .toDouble();
          final lowStock = product.stock <= threshold;
          final theme = Theme.of(context);
          return Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: InkWell(
              onTap: () => _showProductDetails(product),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                        if (product.barcode?.isNotEmpty == true)
                          const Tooltip(
                              message: 'Barcode assigned',
                              child: Icon(Icons.qr_code_2, size: 18)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('₹${product.sellingPrice.toStringAsFixed(2)}',
                        style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.primary)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: lowStock
                                  ? theme.colorScheme.errorContainer
                                  : theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${product.stock.toStringAsFixed(product.stock == product.stock.roundToDouble() ? 0 : 1)} ${product.unit.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: lowStock
                                    ? theme.colorScheme.onErrorContainer
                                    : theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit product',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _openEditor(product: product),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildListView(List<Product> products) {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index.isOdd) return const SizedBox(height: 12);
            final product = products[index ~/ 2];
            final threshold = (Hive.box<dynamic>('app_settings')
                    .get('low_stock_threshold', defaultValue: 10) as num)
                .toDouble();
            return _buildListCard(product, product.stock <= threshold);
          },
          childCount: products.isEmpty ? 0 : products.length * 2 - 1,
        ),
      ),
    );
  }

  Widget _buildListCard(Product product, bool isLowStock) {
    return GestureDetector(
      onTap: () => _showProductDetails(product),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color:
                  Theme.of(context).colorScheme.shadow.withValues(alpha: 0.08),
              spreadRadius: 1,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Product Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      product.category,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '₹${product.sellingPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isLowStock
                                ? Theme.of(context).colorScheme.errorContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${product.stock} ${product.unit.name}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isLowStock
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Action Buttons
              Column(
                children: [
                  IconButton(tooltip: 'Edit', 
                    onPressed: () => _openEditor(product: product),
                    icon: Icon(Icons.edit,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                  IconButton(tooltip: 'Delete', 
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Product?'),
                              content: Text(
                                  'Are you sure you want to delete "${product.name}"?'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel')),
                                ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete')),
                              ],
                            ),
                          ) ??
                          false;
                      if (confirm) {
                        await product.delete();
                        setState(() {});
                      }
                    },
                    icon: const Icon(Icons.delete, color: Colors.red),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProductDetails(Product product) {
    final threshold = (Hive.box<dynamic>('app_settings')
            .get('low_stock_threshold', defaultValue: 10) as num)
        .toDouble();
    final isLowStock = product.stock <= threshold;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              color: Theme.of(context).primaryColor,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                product.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: (MediaQuery.sizeOf(context).width * 0.82)
              .clamp(260.0, 400.0)
              .toDouble(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category
              _buildDetailRow(
                  'Category', product.category, Icons.category_outlined),
              const SizedBox(height: 16),

              // Sub-Category (if exists)
              if (product.subCategory.isNotEmpty)
                Column(
                  children: [
                    _buildDetailRow('Sub-Category', product.subCategory,
                        Icons.subdirectory_arrow_right),
                    const SizedBox(height: 16),
                  ],
                ),

              // Selling Price
              _buildDetailRow(
                  'Selling Price',
                  '₹${product.sellingPrice.toStringAsFixed(2)}',
                  Icons.sell_outlined,
                  Colors.green),
              const SizedBox(height: 16),

              // Cost Price
              _buildDetailRow(
                  'Cost Price',
                  '₹${product.costPrice.toStringAsFixed(2)}',
                  Icons.shopping_cart_outlined,
                  Colors.blue),
              const SizedBox(height: 16),

              // Stock
              _buildDetailRow(
                'Stock',
                '${product.stock.toStringAsFixed(product.unit == UnitType.kg ? 1 : 0)} ${product.unit.name}',
                Icons.inventory_2_outlined,
                isLowStock ? Colors.orange : Colors.green,
              ),
              const SizedBox(height: 16),

              // Profit Margin
              if (product.costPrice > 0)
                Column(
                  children: [
                    _buildDetailRow(
                      'Profit Margin',
                      '₹${(product.sellingPrice - product.costPrice).toStringAsFixed(2)}',
                      Icons.trending_up_outlined,
                      Colors.green,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _adjustStock(product),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Restock / Adjust quantity'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _showStockHistory(product),
                  icon: const Icon(Icons.history),
                  label: const Text('View stock adjustment history'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _openEditor(product: product);
            },
            icon: const Icon(Icons.edit),
            label: const Text('Edit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _adjustStock(Product product) async {
    final controller = TextEditingController();
    final delta = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Adjust stock · ${product.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current stock: ${product.stock} ${product.unit.name}'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: 'Quantity change',
                helperText: '+ve: stock increase · -ve: stock decrease',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null || value == 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Enter a non-zero quantity change.')),
                );
                return;
              }
              if (product.stock + value < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Stock cannot become negative.')),
                );
                return;
              }
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Update stock'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (delta == null || !mounted) return;
    final previousStock = product.stock;
    product.stock += delta;
    await product.save();

    final settings = Hive.box<dynamic>('app_settings');
    final history = (settings
            .get('inventory_adjustments', defaultValue: <dynamic>[]) as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
    history.add({
      'productId': product.id,
      'productName': product.name,
      'date': DateTime.now().toIso8601String(),
      'delta': delta,
      'previousStock': previousStock,
      'newStock': product.stock,
      'unit': product.unit.name,
    });
    if (history.length > 500) {
      history.removeRange(0, history.length - 500);
    }
    await settings.put('inventory_adjustments', history);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Stock updated for ${product.name}. New stock: ${product.stock} ${product.unit.name}.')),
    );
  }

  Future<void> _showStockHistory(Product product) async {
    final settings = Hive.box<dynamic>('app_settings');
    final history = (settings
            .get('inventory_adjustments', defaultValue: <dynamic>[]) as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .where((entry) => entry['productId'] == product.id)
        .toList()
      ..sort((a, b) => DateTime.parse(b['date'] as String)
          .compareTo(DateTime.parse(a['date'] as String)));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Stock history · ${product.name}'),
        content: SizedBox(
          width: (MediaQuery.sizeOf(context).width * 0.84)
              .clamp(260.0, 460.0)
              .toDouble(),
          height: (MediaQuery.sizeOf(context).height * 0.55)
              .clamp(240.0, 360.0)
              .toDouble(),
          child: history.isEmpty
              ? const Center(
                  child: Text(
                      'No manual stock adjustments have been recorded yet.'))
              : ListView.separated(
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = history[index];
                    final delta = (entry['delta'] as num).toDouble();
                    final date =
                        DateTime.parse(entry['date'] as String).toLocal();
                    final quantity = delta.abs().toStringAsFixed(
                        delta.abs() == delta.abs().roundToDouble() ? 0 : 2);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: delta >= 0
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.errorContainer,
                        child: Icon(delta >= 0 ? Icons.add : Icons.remove),
                      ),
                      title: Text(
                          '${delta >= 0 ? '+' : '-'}$quantity ${entry['unit']}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                          '${DateFormat('d MMM yyyy, h:mm a').format(date)}\n${(entry['previousStock'] as num).toString()} → ${(entry['newStock'] as num).toString()} ${entry['unit']}'),
                      isThreeLine: true,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon,
      [Color? valueColor]) {
    return Row(
      children: [
        Icon(
          icon,
          color: Colors.grey[600],
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: valueColor ?? Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openEditor({Product? product}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ManageProductScreen(product: product),
      ),
    );
    if (mounted) setState(() {});
  }
}
