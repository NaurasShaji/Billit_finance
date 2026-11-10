import 'package:hive/hive.dart';

import '../models/models.dart';
import 'boxes.dart';
import 'schema_migration_service.dart';

/// Adds the first finance ledger boxes and a stable default chart of accounts.
/// Safe to retry: box creation is idempotent and defaults use deterministic IDs.
class FinanceSchemaMigration {
  static SchemaMigration get versionOneToTwo => SchemaMigration(
        fromVersion: 1,
        toVersion: 2,
        apply: (_) async {
          final accounts = await Hive.openBox<FinanceAccount>(
            Boxes.financeAccounts,
          );
          await Hive.openBox<FinanceTransaction>(Boxes.financeTransactions);
          await Hive.openBox<FinancePosting>(Boxes.financePostings);
          await Hive.openBox<FinanceCategory>(Boxes.financeCategories);
          await Hive.openBox<FinanceParty>(Boxes.financeParties);

          final defaults = <FinanceAccount>[
            FinanceAccount(
              id: 'system:cash',
              name: 'Cash',
              accountType: 'asset',
            ),
            FinanceAccount(
              id: 'system:bank',
              name: 'Bank',
              accountType: 'asset',
            ),
            FinanceAccount(
              id: 'system:receivables',
              name: 'Accounts Receivable',
              accountType: 'asset',
            ),
            FinanceAccount(
              id: 'system:payables',
              name: 'Accounts Payable',
              accountType: 'liability',
            ),
            FinanceAccount(
              id: 'system:opening-equity',
              name: 'Opening Balance Equity',
              accountType: 'equity',
            ),
            FinanceAccount(
              id: 'system:sales-income',
              name: 'Sales Revenue',
              accountType: 'income',
            ),
            FinanceAccount(
              id: 'system:other-income',
              name: 'Other Income',
              accountType: 'income',
            ),
            FinanceAccount(
              id: 'system:operating-expense',
              name: 'Operating Expenses',
              accountType: 'expense',
            ),
            FinanceAccount(
              id: 'system:cost-of-goods-sold',
              name: 'Cost of Goods Sold',
              accountType: 'expense',
            ),
          ];

          for (final account in defaults) {
            if (!accounts.containsKey(account.id)) {
              await accounts.put(account.id, account);
            }
          }
        },
      );
}
