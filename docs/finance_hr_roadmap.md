# Finance and HR Upgrade Roadmap

Branch: `feature/finance-team-promotion`

This roadmap tracks implementation state. A checked implementation item is not a release-verified item until its tests and Android build pass in CI.

## Finance

### Persistence and accounting integrity
- [x] Sequential Hive schema migrations (legacy v1 → finance v2/v3 → HR v4/v5 → budgets v6, recurring templates v7).
- [x] Add chart of accounts, transaction headers, postings, categories, and parties.
- [x] Persist accounting amounts as integer paise.
- [x] Enforce balanced debit/credit journals and immutable posted transaction snapshots.
- [x] Prevent duplicate source posting and duplicate transaction numbers.
- [x] Reverse posted transactions without mutating the original.
- [x] Include all finance boxes, including budgets and recurring templates, in Google Drive backup and restore.
- [x] Preserve finance data when restoring legacy backups without finance collections.
- [x] Validate finance backup references, category/account compatibility, reversals, and posted journal balance.
- [x] Add best-effort restore rollback across business and finance boxes.
- [x] Replace Hive runtime, Flutter integration, and adapter generator dependencies in pubspec.yaml with Hive CE packages.
- [x] Migrate the application, model, service, finance screen, and persistence-test imports inspected so far to Hive CE.
- [ ] Audit every Dart source and generated adapter for remaining legacy Hive imports or API incompatibilities.
- [ ] Regenerate all Hive adapters with hive_ce_generator; manually maintained adapter files are not yet verified against generator output.
- [ ] Resolve dependencies and refresh/commit pubspec.lock (the current lockfile has not yet been regenerated for Hive CE).
- [x] Document in-place storage compatibility requirements and real-device validation steps.
- [ ] Run all persistence tests, including budget and recurring-template models.
- [x] Add journal reporting coverage for reversal of internal transfers in cash-flow totals.
- [ ] Confirm the refreshed pubspec.lock is committed and dependency resolution is clean.
- [ ] Verify existing production Hive v2 data opens unchanged with Hive CE on a test device.
- [ ] Verify rollback behavior under actual device storage failures.

### POS and expense integration
- [x] Import legacy sales with stable source keys and integer-paise amounts.
- [x] Split GST collected from sales revenue and post GST to a liability account.
- [x] Route cash receipts to Cash and card/UPI receipts to Bank.
- [x] Import general expenses and payroll expenses into separate expense accounts.
- [x] Link payroll expense postings to employee parties.
- [x] Prevent duplicate posting during startup reconciliation.
- [x] Track sale/expense revisions and reverse older journal snapshots.
- [x] Reverse journal history before deleting POS invoices or expenses.
- [x] Add retry visibility for startup reconciliation errors.
- [x] Add reconciliation report comparing source-record counts and totals with journal totals, including failed startup syncs.
- [ ] Verify all create/edit/delete/restore paths on device.

### Finance workflows and reporting
- [x] Manual income entry.
- [x] Manual expense entry.
- [x] Manual cash/bank transfer entry.
- [x] Account normal-balance calculation.
- [x] Journal list and reversal action.
- [x] Journal-based period P&L and cash-flow summary.
- [x] Separate POS gross-profit estimate from accounting P&L.
- [x] Opening balance entry when creating asset/liability accounts.
- [ ] Opening balance reconciliation and adjustment workflow.
- [x] Account creation, editing, archiving, and hierarchy management UI.
- [x] Customer/supplier subledgers and receivables/payables settlements with partial receipts/payments.
- [ ] Persisted invoice-level payment allocation (current ageing report calculates FIFO settlement allocation at report time; this is not stored).
- [x] Optional receivable/payable due dates and ageing report with current, 1–30, 31–60, 61–90, and 90+ day buckets; FIFO settlements are calculated against the oldest eligible invoice.
- [x] Budget creation, period tracking, and actual-versus-budget tracking from posted journal entries (tests authored; execution pending).
- [x] Recurring income/expense templates with startup/manual due-date processing, stable idempotency keys, and month-end cadence handling (tests authored; execution pending).
- [x] Trial balance, P&L, and cash-flow reports with PDF and Excel workbook export.
- [x] Search posted journal entries by transaction number, memo, type, reference, and source ID; filter by transaction type and inclusive date range; sort by date, amount, or transaction number. UI and test validation pending.
- [ ] General-ledger detail report and date-range filtering.
- [ ] Transaction attachments, audit metadata, and approval rules.

## HR and Team

### Employee records
- [x] Existing employee records and daily/monthly wage types retained.
- [x] Employee-linked payroll expense records retained.
- [x] Employee profiles with employee code, contact details, joining date, status, department, designation, address, and emergency contact.
- [x] Department management and employee department/designation assignment.
- [x] Emergency contact field.
- [ ] Employee document storage and access controls.

### Attendance and leave
- [x] Daily attendance records with present, absent, half-day, leave, and holiday states.
- [x] Attendance date selection/calendar view and monthly attendance summaries.
- [x] Leave types, requests, overlap validation, approval/rejection, and attendance generation for approved leave.
- [ ] Leave balance accrual and policy configuration.
- [ ] Attendance-driven wage and salary calculations.

### Compensation and payroll
- [x] Partial salary/wage payments with outstanding balance calculations.
- [x] Payroll expense linked to employee ID.
- [x] Employee-specific earning/deduction components with effective dates.
- [ ] Reusable salary structures, grade templates, and effective-dated base pay changes.
- [x] Payroll periods/runs with draft, approval, and paid states.
- [ ] Overtime and statutory deduction configuration.
- [ ] Salary advances and recovery schedules.
- [x] Immutable payslip snapshots generated for each payroll run.
- [x] Payslip PDF/print output.
- [x] Journal posting for payroll payments with run/payslip references through source-linked expense records.
- [ ] Payroll accrual journal, payroll liability settlement, and reversal workflow.

## Release gates
- [ ] Run `dart run build_runner build --delete-conflicting-outputs` using hive_ce_generator.
- [ ] Run `dart format --set-exit-if-changed .`.
- [ ] Run `flutter analyze` with zero errors.
- [ ] Run `flutter test` with all tests passing.
- [ ] Build Android release APK successfully.
- [ ] Install and exercise POS sale, invoice edit/delete, expenses, payroll, finance journal, backup, and restore on a real Android device.
- [ ] Verify existing Google Drive OAuth/backup behavior remains unchanged.
- [ ] Review the final branch diff and obtain explicit approval before any merge to `main`.

## Known limitations

- Hive has no transaction spanning multiple boxes. Posting and restore use ordered writes plus best-effort rollback; power loss or storage failure during rollback can still require backup recovery.
- Source records remain the operational source of truth. Journal entries are immutable accounting snapshots; edits are represented by reversal plus a new revision.
- Cash/card/UPI settlement is currently mapped to Cash or Bank. Card/UPI clearing accounts and bank reconciliation are not yet implemented.
- COGS/inventory valuation is intentionally not posted because Billit does not yet maintain a complete inventory valuation ledger.
- No multi-user concurrent posting, bank feeds, tax filing, FX revaluation, or statutory payroll compliance is included in the current scope.
- All code and tests added in this branch remain unverified by a Flutter toolchain until the release gates above pass.

## Current execution status (2026-11-10)

The Hive CE migration is **in progress, not complete**. pubspec.yaml now declares hive_ce, hive_ce_flutter, and hive_ce_generator, and imports in the core models, startup, backup/restore service, finance services/screens, and several application screens/tests have been switched. The existing pubspec.lock is still stale and has not been regenerated. Adapter generation, full repository import/API audit, dependency resolution, formatting, analysis, tests, Android build, and existing-data device compatibility have not been verified. Do not treat the Hive CE migration as release-ready until every gate above passes.
