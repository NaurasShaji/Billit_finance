import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../utils/theme_colors.dart';
import '../widgets/responsive_page.dart';

/// Appearance & personalisation.
///
/// Settings are grouped into four tabs (Colour, Style, Navigation, Display).
/// On wide windows a live preview of the real theme is pinned on the right;
/// on narrow screens it appears at the top of the Colour and Style tabs.
/// All settings keys are unchanged from the previous version.
class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key});

  static const _palettes = <String, Color>{
    'green': Color(0xFF25855A),
    'blue': Color(0xFF2864C5),
    'purple': Color(0xFF7651B5),
    'amber': Color(0xFFB77916),
    'teal': Color(0xFF168A8A),
    'rose': Color(0xFFB83280),
    'indigo': Color(0xFF4F46B8),
    'slate': Color(0xFF475569),
    'coral': Color(0xFFD45D45),
    'ocean': Color(0xFF087EAA),
  };

  static const _paletteNames = <String, String>{
    'green': 'Classic Green',
    'blue': 'Classic Blue',
    'purple': 'Royal Purple',
    'amber': 'Warm Amber',
    'teal': 'Calm Teal',
    'rose': 'Rose',
    'indigo': 'Indigo',
    'slate': 'Slate',
    'coral': 'Coral',
    'ocean': 'Ocean',
  };

  static const _defaults = <String, dynamic>{
    'app_theme': 'green',
    'theme_mode': 'system',
    'ui_density': 'comfortable',
    'product_view': 'list',
    'navigation_style': 'classic',
    'navigation_icon_style': 'outlined',
    'surface_style': 'outlined',
    'app_bar_style': 'surface',
    'font_style': 'system',
    'background_style': 'tinted',
    'input_style': 'filled',
    'button_style': 'filled',
    'text_scale': 1.0,
    'corner_radius': 16.0,
    'low_stock_threshold': 10,
  };

  Future<void> _save(String key, dynamic value) async {
    await Hive.box<dynamic>('app_settings').put(key, value);
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset appearance?'),
        content: const Text(
            'Colours, layout, navigation and text size go back to the defaults. Your products and invoices are not affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Hive.box<dynamic>('app_settings').putAll(<String, dynamic>{
        ..._defaults,
        'navigation_icon_overrides': <String, String>{},
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: Hive.box<dynamic>('app_settings').listenable(),
      builder: (context, box, _) {
        final s = _Values(box);
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Appearance & Personalisation'),
              actions: [
                IconButton(
                  tooltip: 'Reset appearance',
                  icon: const Icon(Icons.restart_alt),
                  onPressed: () => _confirmReset(context),
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    constraints.maxWidth >= ResponsiveBreakpoints.desktop;
                final paletteName =
                    _paletteNames[s.theme] ?? _paletteNames['green']!;
                final preview = _PreviewPanel(
                  paletteName: paletteName,
                  modeLabel:
                      '${s.themeMode[0].toUpperCase()}${s.themeMode.substring(1)} mode',
                );

                final tabs = Column(
                  children: [
                    Material(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: const Align(
                        alignment: Alignment.centerLeft,
                        child: TabBar(
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          tabs: [
                            Tab(
                                icon: Icon(Icons.palette_outlined),
                                text: 'Colour'),
                            Tab(
                                icon: Icon(Icons.style_outlined),
                                text: 'Style'),
                            Tab(
                                icon: Icon(Icons.explore_outlined),
                                text: 'Navigation'),
                            Tab(
                                icon: Icon(Icons.text_fields),
                                text: 'Display'),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _tabPage([
                            if (!wide) preview,
                            ..._colourSections(context, s),
                          ]),
                          _tabPage([
                            if (!wide) preview,
                            ..._styleSections(context, s),
                          ]),
                          _tabPage(_navigationSections(context, s)),
                          _tabPage(_displaySections(context, s)),
                        ],
                      ),
                    ),
                  ],
                );

                if (!wide) return tabs;
                return Row(
                  children: [
                    Expanded(child: tabs),
                    VerticalDivider(
                      width: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    SizedBox(
                      width: 380,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: preview,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// One scrollable tab page, centred and width-limited on big screens.
  Widget _tabPage(List<Widget> children) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: ListView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            for (final child in children) ...[
              child,
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Colour tab
  // ---------------------------------------------------------------------
  List<Widget> _colourSections(BuildContext context, _Values s) {
    return [
      _SettingsSection(
        title: 'Accent colour',
        subtitle: 'Navigation and highlight colour.',
        trailing: _PillLabel(_paletteNames[s.theme] ?? 'Classic Green'),
        child: Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            for (final entry in _palettes.entries)
              _SwatchTile(
                color: entry.value,
                label: _paletteNames[entry.key]!,
                selected: entry.key == s.theme,
                onTap: () => _save('app_theme', entry.key),
              ),
          ],
        ),
      ),
      _SettingsSection(
        title: 'Light or dark',
        subtitle: 'System, light or dark mode.',
        child: _FullWidthSegments<String>(
          value: s.themeMode,
          onChanged: (v) => _save('theme_mode', v),
          segments: const [
            ButtonSegment(
                value: 'system',
                icon: Icon(Icons.settings_brightness),
                label: Text('System')),
            ButtonSegment(
                value: 'light',
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Light')),
            ButtonSegment(
                value: 'dark',
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Dark')),
          ],
        ),
      ),
      _SettingsSection(
        title: 'Page background',
        subtitle: 'Background colour.',
        child: _FullWidthSegments<String>(
          value: s.background,
          onChanged: (v) => _save('background_style', v),
          segments: const [
            ButtonSegment(
                value: 'tinted',
                icon: Icon(Icons.gradient),
                label: Text('Tinted')),
            ButtonSegment(
                value: 'plain',
                icon: Icon(Icons.crop_square),
                label: Text('Plain')),
          ],
        ),
      ),
      _SettingsSection(
        title: 'Top bar',
        subtitle: 'Choose a subtle or brand-colour header.',
        child: _OptionGrid<String>(
          value: s.appBar,
          onChanged: (v) => _save('app_bar_style', v),
          minTileWidth: 220,
          options: [
            _Opt('surface', 'Surface',
                subtitle: 'Subtle, blends with the page.',
                visual: _barVisual(context, brand: false)),
            _Opt('brand', 'Brand colour',
                subtitle: 'Strong accent-colour header.',
                visual: _barVisual(context, brand: true)),
          ],
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------------
  // Style tab
  // ---------------------------------------------------------------------
  List<Widget> _styleSections(BuildContext context, _Values s) {
    return [
      _SettingsSection(
        title: 'Corner style',
        subtitle: 'Corner radius.',
        child: _OptionGrid<double>(
          value: s.radius,
          onChanged: (v) => _save('corner_radius', v),
          minTileWidth: 170,
          options: [
            _Opt(8.0, 'Sharp', visual: _cornerVisual(context, 8)),
            _Opt(16.0, 'Rounded', visual: _cornerVisual(context, 16)),
            _Opt(24.0, 'Pill-like', visual: _cornerVisual(context, 24)),
          ],
        ),
      ),
      _SettingsSection(
        title: 'Cards and panels',
        subtitle: 'Shadows and borders.',
        child: _OptionGrid<String>(
          value: s.surface,
          onChanged: (v) => _save('surface_style', v),
          minTileWidth: 170,
          options: [
            _Opt('outlined', 'Outlined',
                subtitle: 'Subtle borders.',
                visual: _surfaceVisual(context, 'outlined')),
            _Opt('elevated', 'Elevated',
                subtitle: 'Soft shadows.',
                visual: _surfaceVisual(context, 'elevated')),
            _Opt('flat', 'Flat',
                subtitle: 'No borders or shadows.',
                visual: _surfaceVisual(context, 'flat')),
          ],
        ),
      ),
      _SettingsSection(
        title: 'Buttons',
        subtitle: 'Primary button style.',
        child: _OptionGrid<String>(
          value: s.button,
          onChanged: (v) => _save('button_style', v),
          minTileWidth: 170,
          options: [
            _Opt('filled', 'Filled',
                subtitle: 'Strong accent colour.',
                visual: _buttonVisual(context, 'filled')),
            _Opt('tonal', 'Tonal',
                subtitle: 'Softer colour.',
                visual: _buttonVisual(context, 'tonal')),
            _Opt('minimal', 'Minimal',
                subtitle: 'Low emphasis.',
                visual: _buttonVisual(context, 'minimal')),
          ],
        ),
      ),
      _SettingsSection(
        title: 'Input fields',
        subtitle: 'Field style.',
        child: _OptionGrid<String>(
          value: s.input,
          onChanged: (v) => _save('input_style', v),
          minTileWidth: 220,
          options: [
            _Opt('filled', 'Filled', visual: _inputVisual(context, true)),
            _Opt('outlined', 'Outlined', visual: _inputVisual(context, false)),
          ],
        ),
      ),
      _SettingsSection(
        title: 'Typography',
        subtitle: 'App font.',
        child: _OptionGrid<String>(
          value: s.font,
          onChanged: (v) => _save('font_style', v),
          minTileWidth: 170,
          options: [
            _Opt('system', 'System',
                subtitle: 'Clean sans-serif.',
                visual: _fontVisual(context, _fontFamilies['system']!)),
            _Opt('serif', 'Serif',
                subtitle: 'Classic and formal.',
                visual: _fontVisual(context, _fontFamilies['serif']!)),
            _Opt('monospace', 'Mono',
                subtitle: 'Fixed-width digits.',
                visual: _fontVisual(context, _fontFamilies['monospace']!)),
          ],
        ),
      ),
    ];
  }

  static const _fontFamilies = <String, String>{
    'system': 'sans-serif',
    'serif': 'serif',
    'monospace': 'monospace',
  };

  // ---------------------------------------------------------------------
  // Navigation tab
  // ---------------------------------------------------------------------
  List<Widget> _navigationSections(BuildContext context, _Values s) {
    return [
      _SettingsSection(
        title: 'Navigation bar style',
        subtitle: 'Navigation layout.',
        child: _OptionGrid<String>(
          value: s.navStyle,
          onChanged: (v) => _save('navigation_style', v),
          minTileWidth: 230,
          options: const [
            _Opt('classic', 'Classic',
                subtitle: 'Standard Material bar.', icon: Icons.view_day_outlined),
            _Opt('floating', 'Floating',
                subtitle: 'Rounded, with a highlight.',
                icon: Icons.space_dashboard_outlined),
            _Opt('underline', 'Underline',
                subtitle: 'Slim active indicator.', icon: Icons.horizontal_rule),
            _Opt('minimal', 'Minimal',
                subtitle: 'Icons and labels only.', icon: Icons.more_horiz),
          ],
        ),
      ),
      _SettingsSection(
        title: 'Icon style',
        subtitle: 'Use one icon style.',
        child: _OptionGrid<String>(
          value: s.navIconStyle,
          onChanged: (v) => _save('navigation_icon_style', v),
          minTileWidth: 170,
          options: const [
            _Opt('outlined', 'Outlined',
                subtitle: 'Light line icons.', icon: Icons.dashboard_outlined),
            _Opt('rounded', 'Rounded',
                subtitle: 'Soft shapes.', icon: Icons.dashboard_rounded),
            _Opt('filled', 'Filled',
                subtitle: 'Bold solid icons.', icon: Icons.dashboard),
          ],
        ),
      ),
      _SettingsSection(
        title: 'Individual icons',
        subtitle: 'Customise each navigation icon.',
        trailing: TextButton.icon(
          onPressed: () =>
              _save('navigation_icon_overrides', <String, String>{}),
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('Reset'),
        ),
        child: Column(
          children: [
            _navigationIconPicker(context, 'Overview', 'overview',
                Icons.dashboard_outlined, s.iconOverrides),
            const Divider(height: 24),
            _navigationIconPicker(context, 'Billing', 'billing',
                Icons.receipt_long_outlined, s.iconOverrides),
            const Divider(height: 24),
            _navigationIconPicker(context, 'Inventory', 'inventory',
                Icons.inventory_2_outlined, s.iconOverrides),
            const Divider(height: 24),
            _navigationIconPicker(context, 'Reports', 'reports',
                Icons.bar_chart_outlined, s.iconOverrides),
            const Divider(height: 24),
            _navigationIconPicker(context, 'Finance', 'finance',
                Icons.account_balance_wallet_outlined, s.iconOverrides),
            const Divider(height: 24),
            _navigationIconPicker(context, 'Team', 'team',
                Icons.groups_outlined, s.iconOverrides),
          ],
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------------
  // Display tab
  // ---------------------------------------------------------------------
  List<Widget> _displaySections(BuildContext context, _Values s) {
    final scheme = Theme.of(context).colorScheme;
    return [
      _SettingsSection(
        title: 'Text size',
        subtitle: 'Make text easier to read.',
        trailing: _PillLabel('${(s.textScale * 100).round()}%'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final preset in const <MapEntry<String, double>>[
                  MapEntry('Small', 0.9),
                  MapEntry('Default', 1.0),
                  MapEntry('Large', 1.1),
                  MapEntry('Extra large', 1.2),
                ])
                  ChoiceChip(
                    label: Text(preset.key),
                    selected: (s.textScale - preset.value).abs() < 0.001,
                    onSelected: (_) => _save('text_scale', preset.value),
                  ),
              ],
            ),
            Slider(
              min: 0.9,
              max: 1.2,
              divisions: 6,
              value: s.textScale.clamp(0.9, 1.2).toDouble(),
              label: '${(s.textScale * 100).round()}%',
              onChanged: (value) => _save('text_scale', value),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.subtleFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Sample text · Invoice total ₹1,250.00',
                style: TextStyle(color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
      _SettingsSection(
        title: 'Display density',
        subtitle: 'More room, or more rows on screen.',
        child: _OptionGrid<String>(
          value: s.density,
          onChanged: (v) => _save('ui_density', v),
          minTileWidth: 220,
          options: const [
            _Opt('comfortable', 'Comfortable',
                subtitle: 'More spacing; easier to tap.',
                icon: Icons.space_dashboard_outlined),
            _Opt('compact', 'Compact',
                subtitle: 'Fits more rows on screen.',
                icon: Icons.view_compact_alt_outlined),
          ],
        ),
      ),
      _SettingsSection(
        title: 'Product catalogue',
        subtitle: 'How inventory items are shown.',
        child: _OptionGrid<String>(
          value: s.productView,
          onChanged: (v) => _save('product_view', v),
          minTileWidth: 220,
          options: const [
            _Opt('list', 'List',
                subtitle: 'One product per row.', icon: Icons.view_list_outlined),
            _Opt('grid', 'Grid',
                subtitle: 'Cards side by side.', icon: Icons.grid_view_rounded),
          ],
        ),
      ),
      _SettingsSection(
        title: 'Low-stock alert',
        subtitle: 'Low-stock alert threshold.',
        trailing: _PillLabel('${s.lowStock.round()} units'),
        child: Slider(
          min: 1,
          max: 100,
          divisions: 99,
          value: s.lowStock.clamp(1.0, 100.0).toDouble(),
          label: '${s.lowStock.round()}',
          onChanged: (value) => _save('low_stock_threshold', value.round()),
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------------
  // Small visual samples shown inside the option tiles
  // ---------------------------------------------------------------------
  Widget _barVisual(BuildContext context, {required bool brand}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      height: 30,
      decoration: BoxDecoration(
        color: brand ? scheme.primary : context.panelColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        height: 5,
        width: 22,
        decoration: BoxDecoration(
          color: brand ? scheme.onPrimary : scheme.onSurfaceVariant,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  Widget _cornerVisual(BuildContext context, double radius) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 50,
      height: 34,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        border: Border.all(color: scheme.primary, width: 2),
        borderRadius: BorderRadius.circular(radius * 0.75),
      ),
    );
  }

  Widget _surfaceVisual(BuildContext context, String style) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 50,
      height: 34,
      decoration: BoxDecoration(
        color: style == 'flat' ? scheme.surfaceContainerHighest : context.panelColor,
        borderRadius: BorderRadius.circular(8),
        border: style == 'outlined'
            ? Border.all(color: scheme.outline.withValues(alpha: 0.6))
            : null,
        boxShadow: style == 'elevated'
            ? [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.28),
                  blurRadius: 7,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
    );
  }

  Widget _buttonVisual(BuildContext context, String style) {
    final scheme = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    switch (style) {
      case 'tonal':
        bg = scheme.secondaryContainer;
        fg = scheme.onSecondaryContainer;
        break;
      case 'minimal':
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurface;
        break;
      default:
        bg = scheme.primary;
        fg = scheme.onPrimary;
    }
    return Container(
      width: 56,
      height: 28,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        'Pay',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget _inputVisual(BuildContext context, bool filled) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      height: 28,
      decoration: BoxDecoration(
        color: filled ? scheme.surfaceContainerHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.7)),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        height: 4,
        width: 26,
        decoration: BoxDecoration(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _fontVisual(BuildContext context, String family) {
    return SizedBox(
      width: 50,
      child: Text(
        'Aa',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: family,
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _navigationIconPicker(
    BuildContext context,
    String label,
    String settingKey,
    IconData fallback,
    Map<String, String> overrides,
  ) {
    const choices = <String, String>{
      'default': 'Default',
      'home': 'Home',
      'dashboard': 'Dashboard',
      'grid': 'Grid',
      'receipt': 'Receipt',
      'cart': 'Shopping cart',
      'calculator': 'Calculator',
      'inventory': 'Inventory',
      'box': 'Boxes',
      'package': 'Package',
      'warehouse': 'Warehouse',
      'chart': 'Bar chart',
      'analytics': 'Analytics',
      'trending': 'Trending',
      'wallet': 'Wallet',
      'savings': 'Savings',
      'people': 'People',
      'badge': 'Badge',
      'archive': 'Archive',
      'folder': 'Folder',
      'history': 'History',
    };
    const icons = <String, IconData>{
      'home': Icons.home_outlined,
      'dashboard': Icons.dashboard_outlined,
      'grid': Icons.grid_view_rounded,
      'receipt': Icons.receipt_long_outlined,
      'cart': Icons.shopping_cart_outlined,
      'calculator': Icons.calculate_outlined,
      'inventory': Icons.inventory_2_outlined,
      'box': Icons.widgets_outlined,
      'warehouse': Icons.warehouse_outlined,
      'chart': Icons.bar_chart_outlined,
      'analytics': Icons.analytics_outlined,
      'trending': Icons.trending_up_outlined,
      'wallet': Icons.account_balance_wallet_outlined,
      'savings': Icons.savings_outlined,
      'people': Icons.groups_outlined,
      'badge': Icons.badge_outlined,
      'archive': Icons.archive_outlined,
      'folder': Icons.folder_open_outlined,
      'history': Icons.history,
    };
    final selected = overrides[settingKey] ?? 'default';
    return Row(
      children: [
        SizedBox(
          width: 104,
          child: Row(
            children: [
              Icon(selected == 'default'
                  ? fallback
                  : icons[selected] ?? fallback),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: choices.containsKey(selected) ? selected : 'default',
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Icon',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: choices.entries
                .map((entry) => DropdownMenuItem<String>(
                      value: entry.key,
                      child: Row(
                        children: [
                          if (entry.key != 'default') ...[
                            Icon(icons[entry.key], size: 19),
                            const SizedBox(width: 10),
                          ] else ...[
                            Icon(fallback, size: 19),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                              child: Text(entry.value,
                                  overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ))
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              final updated = Map<String, String>.from(overrides);
              if (value == 'default') {
                updated.remove(settingKey);
              } else {
                updated[settingKey] = value;
              }
              _save('navigation_icon_overrides', updated);
            },
          ),
        ),
      ],
    );
  }
}

// =========================================================================
// Reusable building blocks (private to this screen)
// =========================================================================

/// Snapshot of every appearance setting, read once per rebuild.
class _Values {
  _Values(Box<dynamic> box)
      : theme = box.get('app_theme', defaultValue: 'green').toString(),
        themeMode = box.get('theme_mode', defaultValue: 'system').toString(),
        density =
            box.get('ui_density', defaultValue: 'comfortable').toString(),
        productView = box.get('product_view', defaultValue: 'list').toString(),
        textScale =
            (box.get('text_scale', defaultValue: 1.0) as num).toDouble(),
        radius =
            (box.get('corner_radius', defaultValue: 16.0) as num).toDouble(),
        lowStock = (box.get('low_stock_threshold', defaultValue: 10) as num)
            .toDouble(),
        navStyle =
            box.get('navigation_style', defaultValue: 'classic').toString(),
        navIconStyle = box
            .get('navigation_icon_style', defaultValue: 'outlined')
            .toString(),
        surface =
            box.get('surface_style', defaultValue: 'outlined').toString(),
        appBar = box.get('app_bar_style', defaultValue: 'surface').toString(),
        font = box.get('font_style', defaultValue: 'system').toString(),
        background =
            box.get('background_style', defaultValue: 'tinted').toString(),
        input = box.get('input_style', defaultValue: 'filled').toString(),
        button = box.get('button_style', defaultValue: 'filled').toString(),
        iconOverrides = _overrides(
            box.get('navigation_icon_overrides', defaultValue: <String, String>{}));

  final String theme;
  final String themeMode;
  final String density;
  final String productView;
  final double textScale;
  final double radius;
  final double lowStock;
  final String navStyle;
  final String navIconStyle;
  final String surface;
  final String appBar;
  final String font;
  final String background;
  final String input;
  final String button;
  final Map<String, String> iconOverrides;

  static Map<String, String> _overrides(dynamic raw) =>
      raw is Map ? Map<String, String>.from(raw) : <String, String>{};
}

/// A titled card that groups related settings.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                      Text(
                        title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing!,
                ],
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

/// Small rounded label showing the current value of a section.
class _PillLabel extends StatelessWidget {
  const _PillLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// Colour swatch with its name underneath.
class _SwatchTile extends StatelessWidget {
  const _SwatchTile({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onColor = color.computeLuminance() > 0.55 ? Colors.black : Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 84,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? scheme.onSurface : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: selected
                      ? Icon(Icons.check, color: onColor, size: 22)
                      : null,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color:
                        selected ? scheme.onSurface : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Segmented control that stretches across the card.
class _FullWidthSegments<T> extends StatelessWidget {
  const _FullWidthSegments({
    required this.value,
    required this.onChanged,
    required this.segments,
  });

  final T value;
  final ValueChanged<T> onChanged;
  final List<ButtonSegment<T>> segments;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<T>(
      segments: segments,
      selected: {value},
      onSelectionChanged: (values) => onChanged(values.first),
      showSelectedIcon: false,
      expandedInsets: EdgeInsets.zero,
    );
  }
}

/// One choice in an [_OptionGrid].
class _Opt<T> {
  const _Opt(this.value, this.label, {this.subtitle, this.icon, this.visual});

  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final Widget? visual;
}

/// Responsive grid of selectable option tiles (replaces tall radio lists).
class _OptionGrid<T> extends StatelessWidget {
  const _OptionGrid({
    required this.options,
    required this.value,
    required this.onChanged,
    this.minTileWidth = 200,
  });

  final List<_Opt<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final fit = ((constraints.maxWidth + gap) / (minTileWidth + gap)).floor();
        var columns = fit < 1 ? 1 : fit;
        if (columns > options.length) columns = options.length;
        final tileWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final option in options)
              SizedBox(
                width: tileWidth,
                child: _OptionTile(
                  label: option.label,
                  subtitle: option.subtitle,
                  icon: option.icon,
                  visual: option.visual,
                  selected: option.value == value,
                  onTap: () => onChanged(option.value),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.visual,
  });

  final String label;
  final String? subtitle;
  final IconData? icon;
  final Widget? visual;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final leading = visual ??
        (icon != null
            ? Icon(
                icon,
                size: 26,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              )
            : null);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                SizedBox(width: 56, child: Center(child: leading)),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: scheme.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// A miniature, non-interactive screen built from the REAL theme widgets, so
/// every change above is visible immediately.
class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.paletteName, required this.modeLabel});

  final String paletteName;
  final String modeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(Icons.visibility_outlined,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'Live preview',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$paletteName · $modeLabel',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          IgnorePointer(
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 56,
                    child: AppBar(
                      primary: false,
                      automaticallyImplyLeading: false,
                      title: const Text('Billit'),
                      actions: [
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.notifications_none),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                  Container(
                    color: theme.scaffoldBackgroundColor,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Today's sales",
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '₹12,480',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          margin: EdgeInsets.zero,
                          child: Column(
                            children: [
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: scheme.primaryContainer,
                                  foregroundColor: scheme.onPrimaryContainer,
                                  child: const Icon(Icons.inventory_2_outlined),
                                ),
                                title: const Text('Wireless mouse'),
                                subtitle: const Text('24 units in stock'),
                                trailing: const Text('₹850',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: scheme.secondaryContainer,
                                  foregroundColor: scheme.onSecondaryContainer,
                                  child: const Icon(Icons.shopping_bag_outlined),
                                ),
                                title: const Text('Notebook pack'),
                                subtitle: const Text('6 packs in stock'),
                                trailing: const Text('₹120',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const TextField(
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: 'Customer name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: () {},
                                child: const Text('Pay'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {},
                                child: const Text('Hold'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            const Chip(label: Text('Paid')),
                            FilterChip(
                              label: const Text('GST'),
                              selected: true,
                              onSelected: (_) {},
                            ),
                            const Chip(label: Text('Low stock')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Switch(value: true, onChanged: (_) {}),
                            const SizedBox(width: 4),
                            const Text('Print receipt'),
                            const Spacer(),
                            Checkbox(value: true, onChanged: (_) {}),
                          ],
                        ),
                      ],
                    ),
                  ),
                  NavigationBar(
                    selectedIndex: 0,
                    onDestinationSelected: (_) {},
                    destinations: const [
                      NavigationDestination(
                          icon: Icon(Icons.dashboard_outlined),
                          label: 'Overview'),
                      NavigationDestination(
                          icon: Icon(Icons.receipt_long_outlined),
                          label: 'Billing'),
                      NavigationDestination(
                          icon: Icon(Icons.inventory_2_outlined),
                          label: 'Inventory'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
