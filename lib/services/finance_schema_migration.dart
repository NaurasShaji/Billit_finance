import 'package:hive_ce/hive_ce.dart';

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

  /// Adds dedicated accounts used by legacy POS, expense and payroll imports.
  static SchemaMigration get versionTwoToThree => SchemaMigration(
        fromVersion: 2,
        toVersion: 3,
        apply: (_) async {
          final accounts = await Hive.openBox<FinanceAccount>(
            Boxes.financeAccounts,
          );
          final defaults = <FinanceAccount>[
            FinanceAccount(
              id: 'system:gst-payable',
              name: 'GST Payable',
              accountType: 'liability',
            ),
            FinanceAccount(
              id: 'system:salary-expense',
              name: 'Salaries and Wages',
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

  /// Adds department, attendance, and leave persistence for the HR foundation.
  static SchemaMigration get versionThreeToFour => SchemaMigration(
        fromVersion: 3,
        toVersion: 4,
        apply: (_) async {
          final departments =
              await Hive.openBox<HrDepartment>(Boxes.hrDepartments);
          await Hive.openBox<EmployeeAttendance>(Boxes.employeeAttendance);
          await Hive.openBox<LeaveRequest>(Boxes.leaveRequests);
          if (!departments.containsKey('system:general')) {
            await departments.put(
              'system:general',
              HrDepartment(
                id: 'system:general',
                name: 'General',
                description: 'Default department',
              ),
            );
          }
        },
      );

  /// Adds salary components, payroll runs, and immutable payslip snapshots.
  static SchemaMigration get versionFourToFive => SchemaMigration(
        fromVersion: 4,
        toVersion: 5,
        apply: (_) async {
          await Hive.openBox<SalaryComponent>(Boxes.salaryComponents);
          await Hive.openBox<PayrollRun>(Boxes.payrollRuns);
          await Hive.openBox<Payslip>(Boxes.payslips);
        },
      );

  /// Adds budget persistence without changing existing journal or HR boxes.
  static SchemaMigration get versionFiveToSix => SchemaMigration(
        fromVersion: 5,
        toVersion: 6,
        apply: (_) async {
          await Hive.openBox<FinanceBudget>(Boxes.financeBudgets);
        },
      );

  /// Adds recurring transaction templates; generated entries remain in the journal.
  static SchemaMigration get versionSevenToEight => SchemaMigration(
        fromVersion: 7,
        toVersion: 8,
        apply: (_) async {
          await Hive.openBox<Map>(Boxes.financePaymentAllocations);
        },
      );

  static SchemaMigration get versionSixToSeven => SchemaMigration(
        fromVersion: 6,
        toVersion: 7,
        apply: (_) async {
          await Hive.openBox<FinanceRecurringTemplate>(
            Boxes.financeRecurringTemplates,
          );
        },
      );
}
