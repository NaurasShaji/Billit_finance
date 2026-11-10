# Finance and HR Upgrade Roadmap

Branch: `feature/finance-team-promotion`

This roadmap tracks implementation state. A checked implementation item is not a release-verified item until its tests and Android build pass in CI.

## Finance

### Persistence and accounting integrity
- [x] Sequential Hive schema migrations (legacy v1 → finance v2 → source-integration v3).
- [x] Add chart of accounts, transaction headers, postings, categories, and parties.
- [x] Persist accounting amounts as integer paise.
- [x] Enforce balanced debit/credit journals and immutable posted transaction snapshots.
- [x] Prevent duplicate source posting and duplicate transaction numbers.
- [x] Reverse posted transactions without mutating the original.
- [x] Include all finance boxes in Google Drive backup and restore.
- [x] Preserve finance data when restoring legacy backups without finance collections.
- [x] Validate finance backup references, category/account compatibility, reversals, and posted journal balance.
- [x] Add best-effort restore rollback across business and finance boxes.
- [ ] Regenerate/verify Hive adapters with build_runner and run all persistence tests.
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
- [ ] Add reconciliation report comparing source-record counts and totals with journal totals.
- [ ] Verify all create/edit/delete/restore paths on device.

### Finance workflows and reporting
- [x] Manual income entry.
- [x] Manual expense entry.
- [x] Manual cash/bank transfer entry.
- [x] Account normal-balance calculation.
- [x] Journal list and reversal action.
- [x] Journal-based period P&L and cash-flow summary.
- [x] Separate POS gross-profit estimate from accounting P&L.
- [ ] Opening balance setup and reconciliation workflow.
- [ ] Account creation, editing, archiving, and hierarchy management UI.
- [ ] Customer/supplier subledgers and receivables/payables settlements.
- [ ] Budget creation, period tracking, and variance reporting.
- [ ] Recurring income/expense templates and due-date processing.
- [ ] Exportable trial balance, P&L, cash-flow, and general-ledger reports.
- [ ] Transaction attachments, audit metadata, and approval rules.

## HR and Team

### Employee records
- [x] Existing employee records and daily/monthly wage types retained.
- [x] Employee-linked payroll expense records retained.
- [x] Employee profiles with employee code, contact details, joining date, status, department, designation, address, and emergency contact.
- [x] Department management and employee department/designation assignment.
- [ ] Employee documents and emergency contacts.

### Attendance and leave
- [x] Daily attendance records with present, absent, half-day, leave, and holiday states.
- [ ] Attendance calendar and monthly summaries.
- [x] Leave types, requests, overlap validation, approval/rejection, and attendance generation for approved leave.
- [ ] Leave balance accrual and policy configuration.
- [ ] Attendance-driven wage and salary calculations.

### Compensation and payroll
- [x] Partial salary/wage payments with outstanding balance calculations.
- [x] Payroll expense linked to employee ID.
- [ ] Salary structures with earnings, allowances, deductions, and effective dates.
- [ ] Payroll periods/runs with draft, approval, and paid states.
- [ ] Overtime and statutory deduction configuration.
- [ ] Salary advances and recovery schedules.
- [ ] Payslip generation and PDF export.
- [ ] Payroll journal posting with period/run references and reversal support.

## Release gates
- [ ] Run `dart run build_runner build --delete-conflicting-outputs`.
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
