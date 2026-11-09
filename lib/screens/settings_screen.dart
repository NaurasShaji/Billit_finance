import 'package:flutter/material.dart';

import 'appearance_settings_screen.dart';
import 'gst_settings_screen.dart';
import 'invoice_settings_screen.dart';
import 'invoice_customisation_screen.dart';
import 'printer_settings_screen.dart';
import 'tabs/archive_tab.dart';
import '../utils/theme_colors.dart';
import '../widgets/responsive_page.dart';

class SettingsScreen extends StatelessWidget {
  final bool isAdmin;
  final VoidCallback onHelp;
  final VoidCallback onLogout;

  const SettingsScreen({
    super.key,
    required this.isAdmin,
    required this.onHelp,
    required this.onLogout,
  });

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final sections = <_SettingsSection>[
      if (isAdmin)
        _SettingsSection(
          heading: 'Business',
          items: [
            _SettingsItem(
              icon: Icons.receipt_long_outlined,
              title: 'App & Invoice Settings',
              subtitle: 'Business and invoice details',
              onTap: () => _open(context, const InvoiceSettingsScreen()),
            ),
            _SettingsItem(
              icon: Icons.design_services_outlined,
              title: 'Invoice Customisation',
              subtitle:
                  'Invoice layout and templates',
              onTap: () => _open(context, const InvoiceCustomisationScreen()),
            ),
            _SettingsItem(
              icon: Icons.percent_outlined,
              title: 'GST Settings',
              subtitle: 'Configure GST and tax defaults',
              onTap: () => _open(context, const GstSettingsScreen()),
            ),
            _SettingsItem(
              icon: Icons.handyman_outlined,
              title: 'Business Tools',
              subtitle: 'Bulk import, exports, backup and account',
              onTap: () => _open(context, const ArchiveTab(standalone: true)),
            ),
          ],
        ),
      _SettingsSection(
        heading: 'Personalisation & Devices',
        items: [
          _SettingsItem(
            icon: Icons.palette_outlined,
            title: 'Appearance & Personalisation',
            subtitle: 'Theme and layout',
            onTap: () => _open(context, const AppearanceSettingsScreen()),
          ),
          _SettingsItem(
            icon: Icons.print_outlined,
            title: 'Printer Settings',
            subtitle: 'Printer setup',
            onTap: () => _open(context, const PrinterSettingsScreen()),
          ),
        ],
      ),
      _SettingsSection(
        heading: 'Support & Account',
        items: [
          _SettingsItem(
            icon: Icons.help_outline_rounded,
            title: 'Help & FAQ',
            subtitle: 'Help and FAQs',
            onTap: onHelp,
          ),
          _SettingsItem(
            icon: Icons.logout_rounded,
            title: 'Logout',
            subtitle: 'Sign out of this account',
            isDestructive: true,
            onTap: onLogout,
          ),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ResponsivePage(
        maxWidth: 820,
        child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
          children: [
            Text(
              'Customise Billit',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Business, app and device settings.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 26),
            ...sections.map((section) => Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.heading.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: context.panelColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < section.items.length; i++) ...[
                              _SettingsTile(item: section.items[i]),
                              if (i != section.items.length - 1)
                                Divider(
                                  height: 1,
                                  indent: 68,
                                  endIndent: 14,
                                  color: scheme.outlineVariant,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
      ),
    );
  }
}

class _SettingsSection {
  final String heading;
  final List<_SettingsItem> items;

  const _SettingsSection({required this.heading, required this.items});
}

class _SettingsItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });
}

class _SettingsTile extends StatelessWidget {
  final _SettingsItem item;

  const _SettingsTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = item.isDestructive ? scheme.error : scheme.onSurface;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: (item.isDestructive ? scheme.error : scheme.primary)
              .withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(item.icon, color: foreground, size: 22),
      ),
      title: Text(
        item.title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
      subtitle: Text(item.subtitle),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: scheme.onSurface.withValues(alpha: 0.42),
      ),
      onTap: item.onTap,
    );
  }
}
