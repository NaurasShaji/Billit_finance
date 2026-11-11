import 'package:flutter/material.dart';

import 'finance_tab.dart';
import 'team_tab.dart';

/// Unified administration area for finance and human resources.
class FinanceHrTab extends StatelessWidget {
  const FinanceHrTab({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: scheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: TabBar(
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: scheme.onPrimary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  tabs: const [
                    Tab(
                      height: 42,
                      icon: Icon(Icons.account_balance_wallet_outlined, size: 18),
                      text: 'Finance',
                    ),
                    Tab(
                      height: 42,
                      icon: Icon(Icons.groups_outlined, size: 18),
                      text: 'HR & Payroll',
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                FinanceTab(),
                TeamTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
