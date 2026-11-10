# Finance & HR Implementation Checklist

Target: general-purpose Billit for small and medium businesses. Offline-first. Preserve existing POS, inventory, GST, invoice, printer, and Google Drive backup workflows.

Work branch: `feature/finance-team-promotion`


## Latest progress

- Completed Hive persistence audit: `docs/persistence_schema_audit.md`.
- Documented the offline-first journal architecture: `docs/finance_ledger_persistence_decision.md`.
- Added `SchemaMigrationService` and invoked it during startup after existing Hive boxes are opened.
- Added migration tests for legacy baseline assignment, sequential/idempotent execution, failed migrations, newer database versions, and missing migration steps.
- **Validation pending:** the migration tests have not yet been run; Flutter analyze and platform builds have not been run.
- Added `BackupRestoreService` to parse and validate all backup collections and nested sale items before any live Hive box is changed.
- Validation covers collection/object shapes, required fields, dates, finite numeric values, optional field types, and duplicate record IDs. Legacy optional fields retain their previous defaults.
- Added parser tests for legacy payload compatibility, malformed collections/items, duplicate IDs, non-finite values, and app-settings parsing.
- Moved Hive apply/rollback into `BackupRestoreService` and added real Hive-box integration tests for successful replacement, app-settings merge, malformed payload rejection without data loss, and legacy settings preservation.
- Restore now applies only the fully parsed payload, with snapshots retained for best-effort rollback if Hive writes fail.
- Existing export format, backup filename, Google Drive sign-in/transport, session box, and app-settings merge behavior remain unchanged.
- Added deterministic write-failure injection to the restore service and a Hive integration test that throws after all replacement writes, then verifies that all original business-data boxes, all five finance boxes, and app settings are restored.
- **Validation pending:** the parser/Hive tests (including the new rollback test), Flutter test suite, static analysis, and builds have not been run.
- Added finance ledger models and Hive adapters using type IDs 10–14: accounts, transaction headers, posting lines, categories, and parties.
- Added schema migrations 1→2 and 2→3 to create the five finance boxes and seed eleven deterministic accounts, including GST payable and salary expense.
- Added `FinanceLedgerService` validation and posting: integer-paise debit/credit lines, minimum two lines, balanced totals, account/category/party reference validation, unique transaction numbers/source IDs, and posted-only account balances.
- Added immutable reversal posting: exact opposite journal lines are appended and the original posted transaction is not modified.
- Added finance persistence/migration and ledger integrity tests. These are authored but have not been executed.
- Extended Google Drive backup export, parser, restore, snapshots, and rollback to include all five finance boxes. Legacy backups without finance keys preserve current finance data; partial finance collection sets, broken cross-references, duplicate transaction/source identifiers, invalid posting lines, and unbalanced posted entries are rejected before writes.
- Added schema v4 HR persistence for departments, employee attendance, and leave requests. Employee records now include code, contact details, department, designation, joining date, employment status, address, and notes. Attendance can be marked per employee/day; leave requests support overlap checks and approval/rejection, and approved leave creates locked attendance records. HR collections and extended employee profiles are included in backup/restore with validation and rollback tests. Added `FinanceSourceSyncService` for legacy POS sales, GST split, general expenses, and payroll expenses. Stable source IDs and `financeRevision` fields prevent duplicate imports and represent invoice edits as reversal plus replacement entries. Invoice/expense deletion creates reversals. Startup reconciliation reports failures and the Finance tab exposes retry. Manual income/expense/transfer entry and initial accounts, journal, P&L, and cash-flow screens are present. `build_runner`, formatting, analysis, tests, and Android build remain unverified.

## Phase 0 — Repository audit and safe foundation

- Began the Hive CE migration: replaced `hive`, `hive_flutter`, and `hive_generator` dependencies with `hive_ce` (`^2.23.2`), `hive_ce_flutter` (`2.3.4` pinned for Flutter 3.29.3), and `hive_ce_generator` (`1.11.3` pinned). Updated application, finance, HR, model, and test imports found during the branch audit.
- Added a branch-scoped GitHub Actions workflow to resolve dependencies, regenerate adapters, format Dart sources, commit the lockfile/generated outputs, analyze, test, and build the Android release. Added a guard against old Hive imports/dependencies.
- **Validation pending:** the lockfile has not yet been regenerated by `flutter pub get`; build_runner, formatting, analysis, tests, and Android build have not been observed passing. Hive CE compatibility with a copied real-world Hive v2 data directory remains a release gate.

- [x] Inspect current Finance and Team screens/services on this branch.
- [x] Inspect employee and expense persistence models.
- [x] Inspect Google Drive backup export/import compatibility.
- [x] Identify branch divergence from latest main (feature branch remains ahead of and behind main; integration remains pending).
- [x] Complete audit of Hive adapter registrations, box names, and startup initialization.
- [x] Document existing Hive type IDs, field IDs, and migration constraints. See [persistence schema audit](persistence_schema_audit.md).
- [x] Decide and document persistence strategy for the full finance ledger. See [finance ledger persistence decision](finance_ledger_persistence_decision.md).
- [x] Add versioned schema migration runner and migration tests (tests added; execution still pending).
- [x] Add snapshot-based rollback protection for partial Google Drive restore failures (best-effort; Hive has no multi-box transaction).
- [x] Validate the complete backup payload before mutating live boxes.
- [x] Add parser tests for legacy backup compatibility and malformed data.
- [x] Add Hive integration tests for restore application, malformed-payload data preservation, and legacy settings behavior.
- [x] Add a deterministic failure-injection test for rollback after a Hive write failure (authored; execution pending).
- [x] Fix the misplaced finance box constants declaration that prevented `Boxes.finance*` references from compiling.
- [x] Fix the immutable-posting test fixture so it constructs a new posting instead of mutating a final field.

## Phase 1 — Payroll correctness (in progress)

- [x] Calculate total payroll paid per employee within the active payroll period.
- [x] Calculate remaining amount due after one or more partial payments.
- [x] Do not mark an employee fully paid when only a partial payment exists.
- [x] Use remaining balance as the default amount in daily and monthly payroll screens.
- [x] Allow additional payments while a balance remains.
- [x] Reject payroll payments that exceed the outstanding balance.
- [x] Show partially-paid state and remaining balance in the Team screen.
- [x] Count fully paid employees (not payment records) in daily/monthly payroll summaries.
- [x] Pay only the outstanding balance from the Team quick-pay action.
- [x] Add unit tests for partial payment and overpayment calculations.
- [ ] Run Flutter tests and static analysis in a Flutter-enabled environment.
- [ ] Add widget tests for partial-payment states and repeated payments.
- [ ] Review daily-wage attendance semantics before broadening payroll calculations.

## Phase 2 — Finance core

- [x] Define initial account, transaction, posting, category, and party persistence models.
- [x] Add schema migration and default chart-of-accounts seed.
- [x] Implement initial balanced journal validation and posting service (service-level integrity only; UI workflows pending).
- [x] Extend Google Drive backup/restore and rollback to finance boxes (integration tests authored; execution pending).
- [x] Implement manual income, expense, and transfer journal workflows.
- [ ] Implement adjustment UI workflow.
- [ ] Add configurable categories and payment methods.
- [ ] Add transaction search, filtering, sorting, and date ranges.
- [ ] Add recurring transactions.
- [x] Add ledger integrity and balance tests (authored; execution pending).

## Phase 3 — Advanced Finance

- [ ] Customer and supplier records.
- [ ] Receivables and payables with due dates.
- [ ] Partial payment allocation and outstanding balances.
- [ ] Budgets and actual-versus-budget reports.
- [ ] Cash-flow and profit-and-loss reports.
- [x] Clearly distinguish POS gross-profit estimate from journal-based accounting profit.
- [ ] PDF and spreadsheet exports.

## Phase 4 — HR foundation

- [x] Expanded employee profiles and employment status.
- [x] Departments, designations, and employee numbers.
- [ ] Employment history and employee documents.
- [ ] Configurable employment and pay frequencies.

## Phase 5 — Attendance and leave

- [x] Daily attendance states and attendance corrections.
- [ ] Optional check-in/check-out.
- [x] Leave types, requests, and approval/rejection workflow.
- [ ] Leave balances, policy accrual, and attendance reports.

## Phase 6 — Payroll expansion

- [ ] Salary structures with effective dates.
- [ ] Allowances, overtime, bonuses, deductions, and reimbursements.
- [ ] Advances and loan repayments.
- [ ] Immutable payroll runs and approval workflow.
- [ ] Payslips and payroll history.
- [ ] Reversal/correction workflow.

## Phase 7 — Finance/HR integration

- [ ] Payroll liabilities and linked finance payments.
- [ ] Employee-linked advances and reimbursements.
- [ ] Cross-module reconciliation and reports.

## Phase 8 — UI/UX redesign

- [x] Add initial Finance ledger overview, accounts, and journal navigation.
- [ ] Complete Finance dashboard and navigation redesign.
- [ ] Finance ledger, accounts, receivables, payables, budgets, and reports screens.
- [ ] HR dashboard, employee directory, and profile redesign.
- [ ] Attendance, leave, payroll, and payslip screens.
- [ ] Responsive phone/tablet/desktop layouts.
- [ ] Light/dark theme review and consistent empty/error states.

## Phase 9 — Regression and release

- [ ] Run build_runner, Dart format, and Flutter analyze.
- [ ] Run all unit and widget tests.
- [ ] Build supported targets.
- [ ] Test upgrade with existing Billit data.
- [ ] Test old/new Google Drive backup and restore.
- [ ] Regression-test billing, inventory, GST, invoice preview/PDF/printing, and authentication.
- [ ] Verify offline operation and larger datasets.
- [ ] Open PR for review; do not merge without approval.

## Implementation rules

- Financial amounts must not be persisted using binary floating-point as the accounting source of truth.
- Posted transactions and payroll history must not be silently overwritten or deleted.
- Every persisted schema change requires migration and backup/restore coverage.
- UI code must not become the source of truth for calculations.
- A task is checked only after implementation; tests remain unchecked until actually run and passed.
