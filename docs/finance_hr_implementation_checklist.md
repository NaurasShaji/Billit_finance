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
- Added deterministic write-failure injection to the restore service and a Hive integration test that throws after all replacement writes, then verifies that every original box and app settings are restored.
- **Validation pending:** the parser/Hive tests (including the new rollback test), Flutter test suite, static analysis, and builds have not been run.
- Added finance ledger models and Hive adapters using type IDs 10–14: accounts, transaction headers, posting lines, categories, and parties.
- Added schema migration 1→2 to create the five finance boxes and seed nine deterministic default accounts.
- Added `FinanceLedgerService` validation and posting: integer-paise debit/credit lines, minimum two lines, balanced totals, valid account references, unique transaction/source IDs, and posted-only account balance calculation.
- Added finance persistence/migration and ledger integrity tests. These are authored but have not been executed.
- **Important release gap:** Google Drive backup export/restore does not yet include the five finance boxes. Existing finance data must not be considered backup-protected until that integration and rollback coverage are implemented.
- **Next:** extend Google Drive backup/restore for finance data, then execute the full test suite and static analysis.

## Phase 0 — Repository audit and safe foundation

- [x] Inspect current Finance and Team screens/services on this branch.
- [x] Inspect employee and expense persistence models.
- [x] Inspect Google Drive backup export/import compatibility.
- [x] Identify branch divergence from latest main (this branch is currently 9 commits ahead and 5 behind; integration remains pending).
- [x] Complete audit of Hive adapter registrations, box names, and startup initialization.
- [x] Document existing Hive type IDs, field IDs, and migration constraints. See [persistence schema audit](persistence_schema_audit.md).
- [x] Decide and document persistence strategy for the full finance ledger. See [finance ledger persistence decision](finance_ledger_persistence_decision.md).
- [x] Add versioned schema migration runner and migration tests (tests added; execution still pending).
- [x] Add snapshot-based rollback protection for partial Google Drive restore failures (best-effort; Hive has no multi-box transaction).
- [x] Validate the complete backup payload before mutating live boxes.
- [x] Add parser tests for legacy backup compatibility and malformed data.
- [x] Add Hive integration tests for restore application, malformed-payload data preservation, and legacy settings behavior.
- [x] Add a deterministic failure-injection test for rollback after a Hive write failure (authored; execution pending).

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
- [ ] Extend Google Drive backup/restore and rollback to finance boxes.
- [ ] Implement income, expense, transfer, and adjustment UI workflows.
- [ ] Add configurable categories and payment methods.
- [ ] Add transaction search, filtering, sorting, and date ranges.
- [ ] Add recurring transactions.
- [ ] Add ledger integrity and balance tests.

## Phase 3 — Advanced Finance

- [ ] Customer and supplier records.
- [ ] Receivables and payables with due dates.
- [ ] Partial payment allocation and outstanding balances.
- [ ] Budgets and actual-versus-budget reports.
- [ ] Cash-flow and profit-and-loss reports.
- [ ] Clearly distinguish POS gross profit from accounting net profit.
- [ ] PDF and spreadsheet exports.

## Phase 4 — HR foundation

- [ ] Expanded employee profiles and employment status.
- [ ] Departments, designations, and employee numbers.
- [ ] Employment history and employee documents.
- [ ] Configurable employment and pay frequencies.

## Phase 5 — Attendance and leave

- [ ] Daily attendance states and attendance corrections.
- [ ] Optional check-in/check-out.
- [ ] Leave types, policies, requests, and approvals.
- [ ] Leave balances and attendance reports.

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

- [ ] Finance dashboard and navigation redesign.
- [ ] Finance ledger, accounts, receivables, payables, budgets, and reports screens.
- [ ] HR dashboard, employee directory, and profile redesign.
- [ ] Attendance, leave, payroll, and payslip screens.
- [ ] Responsive phone/tablet/desktop layouts.
- [ ] Light/dark theme review and consistent empty/error states.

## Phase 9 — Regression and release

- [ ] Dart format and Flutter analyze.
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
