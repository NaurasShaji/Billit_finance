# Finance & HR Implementation Checklist

Target: general-purpose Billit for small and medium businesses. Offline-first. Preserve existing POS, inventory, GST, invoice, printer, and Google Drive backup workflows.

Work branch: `feature/finance-team-promotion`

## Phase 0 — Repository audit and safe foundation

- [x] Inspect current Finance and Team screens/services on this branch.
- [x] Inspect employee and expense persistence models.
- [x] Inspect Google Drive backup export/import compatibility.
- [x] Identify branch divergence from latest main (this branch is currently 9 commits ahead and 5 behind; integration remains pending).
- [x] Complete audit of Hive adapter registrations, box names, and startup initialization.
- [x] Document existing Hive type IDs, field IDs, and migration constraints. See [persistence schema audit](persistence_schema_audit.md).
- [ ] Decide and document persistence strategy for the full finance ledger.
- [ ] Add versioned schema migrations and migration tests.
- [ ] Make restore transactional/safe against partial imports.
- [ ] Preserve legacy backup restore compatibility.

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

- [ ] Define account and opening-balance models.
- [ ] Implement unified income, expense, transfer, and adjustment ledger.
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
