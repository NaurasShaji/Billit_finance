# Billit Finance & HR Redesign — Implementation Checklist

## Product decisions

- [x] Target small and medium-sized businesses.
- [x] Offline-first; core workflows must not require internet access.
- [x] Complete Finance and HR scope, delivered incrementally.
- [x] Preserve existing POS, inventory, GST, invoice, printer, and Google Drive backup workflows.
- [x] Implement on a new branch from the latest `main`; do not merge into `main without review.

## Phase 0 — Repository and data audit

- [ ] Map current Finance, Team, payroll, expense, employee, sales, and settings screens.
- [ ] Inspect all existing Hive models, generated adapters, box names, and type IDs.
- [ ] Trace every existing expense and payroll write/read path.
- [ ] Trace Google Drive backup serialization, restore, and legacy-backup compatibility.
- [ ] Identify all navigation, role/access-control, and dashboard dependencies.
- [ ] Review the old `feature/finance-team-promotion` branch and selectively identify reusable code; do not merge it wholesale.
- [ ] Record existing data formats and migration constraints.
- [ ] Decide the local persistence strategy (Hive hardening versus SQLite/Drift) based on transaction, query, migration, and backup requirements.
- [ ] Write the approved schema and migration plan before changing persisted models.

## Phase 1 — Shared foundation

- [ ] Define business settings: currency, locale, financial year, timezone, and business profile.
- [ ] Define stable IDs, timestamps, audit metadata, and soft-delete/reversal conventions.
- [ ] Add repository interfaces and isolate persistence from UI/business logic.
- [ ] Add versioned database/schema migrations.
- [ ] Add safe local transaction/batch-write boundaries for multi-record operations.
- [ ] Preserve compatibility with existing Billit data and Google Drive backups.
- [ ] Add migration and backup/restore regression tests.

## Phase 2 — Finance core

- [ ] Build account management (cash, bank, and configurable account types).
- [ ] Build a unified transaction ledger for income, expenses, transfers, and adjustments.
- [ ] Add configurable income and expense categories.
- [ ] Support payment methods, references, notes, attachments, and transaction dates.
- [ ] Add transaction search, filters, sorting, and date-range navigation.
- [ ] Add recurring transaction definitions and due-date handling.
- [ ] Prevent silent deletion of posted financial records; use reversals/adjustments.
- [ ] Reconcile opening balances and account balances against ledger entries.
- [ ] Add unit tests for transaction and balance calculations.

## Phase 3 — Finance advanced workflows and reports

- [ ] Add customer and supplier records.
- [ ] Add receivables and payable records with due dates and statuses.
- [ ] Support partial payments and payment allocation across outstanding balances.
- [ ] Handle overdue balances and payment history.
- [ ] Add budgets by period and category, with actual-versus-budget reporting.
- [ ] Add correctly labelled income/expense, cash-flow, and profit-and-loss reports.
- [ ] Clearly distinguish POS gross profit from accounting net profit.
- [ ] Add PDF and spreadsheet exports.
- [ ] Add reconciliation and report-calculation tests.

## Phase 4 — HR foundation

- [ ] Expand employee profiles: contact details, employee number, joining date, status, department, and designation.
- [ ] Support daily wage, monthly salary, hourly, and configurable employment types where appropriate.
- [ ] Add employee documents and employment history.
- [ ] Add department and designation management.
- [ ] Add employee lifecycle actions (active, inactive, terminated) without deleting historical payroll data.
- [ ] Add employee data validation and persistence tests.

## Phase 5 — Attendance and leave

- [ ] Implement daily attendance with present, absent, half-day, and holiday states.
- [ ] Support check-in/check-out where enabled by the business.
- [ ] Add attendance correction with audit history.
- [ ] Add configurable leave types and leave policies.
- [ ] Add leave requests, approval/rejection, and leave balances.
- [ ] Add attendance and leave summaries.
- [ ] Test date boundaries, duplicate attendance, and payroll-period inputs.

## Phase 6 — Payroll

- [ ] Define salary structures and effective dates.
- [ ] Support earnings: base pay, allowances, overtime, bonuses, and reimbursements.
- [ ] Support deductions, advances, and loan repayments.
- [ ] Create immutable payroll runs by pay period with calculation snapshots.
- [ ] Calculate daily/monthly/hourly pay from the configured rules and approved attendance.
- [ ] Support full and partial payroll payments with explicit allocations.
- [ ] Keep unpaid balances outstanding until fully settled.
- [ ] Generate payslips and payroll history.
- [ ] Add payroll approval and correction/reversal workflows.
- [ ] Test partial payments, advances, deductions, employee changes, and period boundaries.

## Phase 7 — Finance and HR integration

- [ ] Convert approved payroll runs into payroll liabilities.
- [ ] Record actual salary payments as linked finance transactions.
- [ ] Link advances, reimbursements, and employee-related expenses to employees.
- [ ] Ensure attendance informs payroll but does not itself create financial transactions.
- [ ] Ensure reversals update linked records consistently.
- [ ] Add cross-module reconciliation tests.

## Phase 8 — UI/UX redesign

- [ ] Redesign Finance overview and navigation.
- [ ] Build dedicated transaction, account, receivable, payable, budget, and report screens.
- [ ] Redesign HR overview and employee directory/profile screens.
- [ ] Build dedicated attendance, leave, payroll, and payslip screens.
- [ ] Standardize forms, validation, filters, date pickers, tables, and empty/error states.
- [ ] Support phone, tablet, and desktop layouts.
- [ ] Verify light and dark themes.
- [ ] Keep destructive/financial actions explicit and confirmable.
- [ ] Align visual language with the existing Billit A4 invoice redesign.

## Phase 9 — Quality, migration, and release

- [ ] Run Dart formatting and Flutter static analysis.
- [ ] Run all existing and new unit/widget tests.
- [ ] Build supported release targets.
- [ ] Test upgrade from existing Hive data with realistic business records.
- [ ] Test backup and restore with old and new backup formats.
- [ ] Verify POS, inventory, GST, invoice preview/PDF/printing, and authentication are unaffected.
- [ ] Test offline operation with network disabled.
- [ ] Test large transaction and employee datasets.
- [ ] Review data integrity, rounding, date/time handling, and duplicate-write protection.
- [ ] Prepare release notes and a rollback/migration recovery procedure.
- [ ] Open a pull request for review; do not merge without approval.

## Engineering rules

- Store monetary values as integer minor units or a precise decimal representation; do not use binary floating-point for persisted accounting amounts.
- Keep UI widgets free of financial business rules.
- Use one source of truth for balances and payroll calculations.
- Preserve historical payroll calculations and posted transaction history.
- Every financial write must be validated and safely persisted.
- All new persisted fields require migration and backup/restore coverage.
- Do not claim a phase is complete until its tests and acceptance checks pass.

## Current status

- [x] Product direction confirmed: small/medium, offline-first, complete scope.
- [x] Dedicated implementation branch created from the current `main`.
- [ ] Repository audit complete.
- [ ] Persistence strategy and schema approved.
- [ ] Implementation started.
