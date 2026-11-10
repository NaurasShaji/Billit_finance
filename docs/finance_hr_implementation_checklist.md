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
- Added deterministic write-failure injection to the restore service and a Hive integration test that throws after all replacement writes, then verifies that all original business-data boxes, all seven finance boxes, and app settings are restored.
- **Validation pending:** the parser/Hive tests (including the new rollback test), Flutter test suite, static analysis, and builds have not been run.
- Added finance ledger models and Hive adapters using type IDs 10–14, 21, and 22: accounts, transaction headers, posting lines, categories, parties, budgets, and recurring templates.
- Added schema migrations 1→2 and 2→3 to create the five initial ledger boxes and seed eleven deterministic accounts, including GST payable and salary expense. Later migrations 5→6 and 6→7 add budget and recurring-template boxes.
- Added `FinanceLedgerService` validation and posting: integer-paise debit/credit lines, minimum two lines, balanced totals, account/category/party reference validation, unique transaction numbers/source IDs, and posted-only account balances.
- Added immutable reversal posting: exact opposite journal lines are appended and the original posted transaction is not modified.
- Added finance persistence/migration and ledger integrity tests. These are authored but have not been executed.
- Extended Google Drive backup export, parser, restore, snapshots, and rollback to include all seven finance boxes. Legacy backups without finance keys preserve current finance data; partial finance collection sets, broken cross-references, duplicate transaction/source identifiers, invalid posting lines, and unbalanced posted entries are rejected before writes.
- Added schema v4 HR persistence for departments, employee attendance, and leave requests. Employee records now include code, contact details, department, designation, joining date, employment status, address, and notes. Attendance can be marked per employee/day; leave requests support overlap checks and approval/rejection, and approved leave creates locked attendance records. HR collections and extended employee profiles are included in backup/restore with validation and rollback tests. Added `FinanceSourceSyncService` for legacy POS sales, GST split, general expenses, and payroll expenses. Stable source IDs and `financeRevision` fields prevent duplicate imports and represent invoice edits as reversal plus replacement entries. Invoice/expense deletion creates reversals. Startup reconciliation reports failures and the Finance tab exposes retry. Manual income/expense/transfer entry and initial accounts, journal, P&L, and cash-flow screens are present.
- Added configurable income/expense categories linked to ledger accounts, customer/supplier party records, receivable/payable postings, partial customer receipts and supplier payments, and party-level outstanding balances. Added service tests for partial settlements and archiving controls.
- Added recurring transaction templates with idempotent scheduled posting, month-end cadence handling, startup processing, manual processing, and a dedicated screen. Added recurring service tests.
- Added budget tracking and actual-versus-budget calculations, plus accounting reports for P&L, cash flow, and trial balance with PDF and Excel workbook export.
- Added a Hive CE persistence smoke test covering adapter Type IDs 1–22 and close/reopen persistence across legacy, finance, HR, budget, and recurring-template boxes.
- Added optional due dates to manual receivable/payable journal entries. The due date is persisted as an additive nullable Hive field and carried into posted transaction records. Due-date ageing and invoice-level allocation have since been implemented; adapter generation and migration compatibility remain unverified.
- Added a receivables/payables ageing report reachable from the customer/supplier directory. It shows open invoice balances and ageing buckets as of a selected date; persisted explicit allocations are applied first, then remaining legacy settlement balances are applied FIFO. Backup restore parsing preserves nullable transaction due dates. Adapter generation, backup export verification, and Flutter tests remain pending.
- Added account-wise General Ledger reporting with account selection, optional date range, opening balance, period debit/credit totals, closing balance, and transaction-level running balance. Linked it from the Accounts & Journal screen.
- Added customer/supplier statements with date-filtered opening/closing balances and running transaction balances. Linked them from the party directory.
- Added schema v8 and a primitive-map allocation store to avoid consuming a new Hive adapter type ID. Added a payment allocation service with immutable allocation records, partial allocation support, party/type/date validation, invoice and settlement over-allocation protection, and reversal-aware effective balances.
- Added an invoice allocation screen from the customer/supplier directory. Users can select a party, a posted receipt/payment, an outstanding invoice, and the amount to allocate; allocation history is shown below.
- Extended Google Drive backup export/restore and rollback snapshots for allocation history, including validation of linked transactions, party types, invoice/settlement types, positive amounts, and aggregate allocation limits. Older finance backups are rejected if restoring them would silently orphan existing allocations.
- Updated receivables/payables ageing to apply persisted invoice allocations first and retain FIFO only for unallocated legacy settlement amounts. Also ensured transaction due dates are included in backup export.
- Added customer/supplier statements from the party directory. Each statement derives its entries from posted receivable/payable journal lines and shows date-filtered opening balance, period movement, closing balance, and running balance per transaction.
- Invoice-level payment allocation is now persisted in the schema-v8 allocation store. The standalone allocation screen supports partial allocations and allocation history; ageing applies explicit allocations before applying any remaining legacy settlement balance FIFO. Backup export, validation, restore, and rollback include allocation records.
- **Payroll accounting integrity:** a payslip is no longer advanced to partially paid/paid when its source expense cannot be synchronized to the finance journal. The expense is retained with a reconciliation issue so the stable source ID can be retried without creating a duplicate payment.
- **Leave approval integrity:** approving a leave request now converts any pre-existing manually marked `leave` attendance records in the requested range into request-linked locked records. If attendance or request persistence fails, previously existing attendance records are restored as part of best-effort rollback. Added regression coverage for the manual-leave locking case; tests remain unexecuted.
- **Attendance time tracking:** daily attendance now exposes check-in/check-out time pickers for present employees. The service rejects checkout without check-in, checkout earlier than check-in, and timestamps outside the attendance date. Regression tests were added; they have not been run.
- **Leave policy and balances:** added configurable annual entitlements for each leave type, monthly accrual, and balance calculation against approved leave requests. The Leave Management screen exposes policy settings and current balances. Policies are stored in the existing app-settings backup payload, so no Hive adapter or schema migration is required. Current rules use calendar days and calendar-year accrual; carry-forward and holiday/weekend exclusions are not implemented. Regression coverage was authored but not run.
- **Attendance reporting:** added a date-range report linked from the daily attendance screen. It shows period-wide totals and per-employee status counts with payable-day calculations. Report UI and data updates are not yet tested.
- **Employment history:** employee profiles now support dated joining, designation, department, status, pay-change, and other history events. Entries are stored per employee in app settings, which is included in the existing backup payload. Added service regression coverage; tests remain unexecuted. Employee file/document uploads and access controls are still outstanding.
- **Allocation workflow update:** customer receipts and supplier payments now expose optional multi-invoice allocation rows in the transaction form. Each row is prevalidated against the invoice balance after existing explicit allocations and legacy FIFO settlements; total allocation cannot exceed the new settlement. Allocation records are batch-validated before persistence. If allocation persistence fails after journal posting, the form attempts an immutable reversal of the settlement. The separate allocation screen remains available for later allocation of advances.
- Tests, formatting, static analysis, and platform builds remain pending.
- Added unit tests for partial allocation, multi-invoice settlement splitting, batch over-allocation rejection without partial writes, legacy FIFO balance before new allocation, and reversal-aware allocation history. **Validation remains pending:** no Flutter commands have been run in this environment. The Hive CE workflow must regenerate `pubspec.lock` and adapters, then run formatting, analysis, tests, and Android build.

## Phase 0 — Repository audit and safe foundation

- Began the Hive CE migration: replaced `hive`, `hive_flutter`, and `hive_generator` dependencies with `hive_ce` (`^2.23.2`), `hive_ce_flutter` (`2.3.4` pinned for Flutter 3.29.3), and `hive_ce_generator` (`^1.12.1`). Updated application, finance, HR, model, and test imports found during the branch audit. Replaced legacy DropdownButtonFormField `initialValue` arguments with Flutter 3.29-compatible `value` arguments.
- Added a branch-scoped GitHub Actions workflow to resolve dependencies, regenerate adapters, reject legacy Hive references, format Dart sources, commit the lockfile/generated outputs, analyze, test, and build the Android release. Added a separate Android packaging workflow without duplicate lockfile commits.
- **Validation pending:** the checked-in lockfile still lists the old Hive packages until the Hive CE validation workflow runs `flutter pub get`; build_runner, formatting, analysis, tests, and Android build have not been observed passing. Added `hive_ce_persistence_smoke_test.dart` for Type ID uniqueness 1–22 and close/reopen persistence across legacy, finance, HR, budget, and recurring-template boxes. A copied real-world Hive v2 data directory still needs a device-level upgrade test. Hive CE compatibility with a copied real-world Hive v2 data directory remains a release gate.

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
- [x] Add service regression coverage for partial payments, repeated payments, bank-account selection, and invalid payment-account rejection. Widget-level interaction tests remain part of release validation.
- [x] Define daily-wage payable attendance semantics: present = 1 day, half-day = 0.5 day, absent/leave/holiday = 0 payable days. Paid leave and paid-holiday rules are not inferred automatically; shops must configure a separate earning component or approved payroll adjustment when applicable.

## Phase 2 — Finance core

- [x] Define initial account, transaction, posting, category, and party persistence models.
- [x] Add schema migration and default chart-of-accounts seed.
- [x] Implement balanced journal validation, immutable posting/reversal service, manual transaction UI, account management, and opening-balance journal entries.
- [x] Extend Google Drive backup/restore and rollback to finance boxes (integration tests authored; execution pending).
- [x] Implement manual income, expense, and transfer journal workflows.
- [x] Implement balanced journal adjustment entry UI workflow.
- [x] Add source-to-journal reconciliation report and retry action (tests authored; execution pending).
- [x] Add configurable income/expense categories with linked ledger accounts and category-aware manual journal entries.
- [x] Add configurable POS payment methods and account mapping for cash, card, and UPI. The Finance payment-account screen saves active INR asset-account mappings; startup and retry POS journal sync use them. Existing posted entries remain unchanged.
- [x] Add posted-journal search (transaction number, memo, type, reference, and source ID), transaction-type and inclusive date-range filters, and sorting by date, amount, or transaction number. Flutter tests and UI verification remain pending.
- [x] Add recurring transaction templates with daily/weekly/monthly/quarterly/yearly schedules, idempotent due processing, and month-end cadence handling (tests authored; execution pending).
- [x] Add ledger integrity and balance tests (authored; execution pending).

## Phase 3 — Advanced Finance

- [x] Customer and supplier records with contact and tax identifiers.
- [x] Receivables and payables linked to customer/supplier party records.
- [x] Optional due dates for manual receivable/payable entries and receivables/payables ageing report with current, 1–30, 31–60, 61–90, and 90+ day buckets. Report applies persisted explicit allocations first, then applies unallocated legacy settlement balances FIFO.
- [x] Partial customer receipts and supplier payments with party-level outstanding balances.
- [x] Persisted invoice-level payment allocation, partial allocation UI, allocation history, reversal-aware effective balances, and backup/restore support.
- [x] Integrate optional multi-invoice allocation into customer receipt and supplier payment creation; unallocated settlement amounts remain available as party advances.
- [x] Validate invoice balances against prior explicit allocations and legacy FIFO settlements before new explicit allocations; add regression coverage for legacy FIFO balance and batch over-allocation (tests authored, execution pending).
- [x] Budget creation, period tracking, and actual-versus-budget reporting from posted expense journal lines (tests authored; execution pending).
- [x] Journal-based cash-flow and profit-and-loss summaries.
- [x] Clearly distinguish POS gross-profit estimate from journal-based accounting profit.
- [x] Journal-based accounting report screen with profit-and-loss, cash-flow, and trial-balance views plus PDF/print export.
- [x] Excel workbook export for summary and trial balance.

## Phase 4 — HR foundation

- [x] Expanded employee profiles and employment status.
- [x] Departments, designations, and employee numbers.
- [x] Employee employment history events with type, title, effective date, notes, and per-employee persistence in the backed-up app-settings collection.
- [x] Employee document storage with PDF/PNG/JPG/DOC/DOCX allowlisting, a 2 MB per-file limit, administrator-only listing/download/upload/delete, and Google Drive backup/restore validation. Legacy backups that omit existing employee documents are rejected to prevent silent orphaning. Document data is stored as base64 in app settings; cloud backups therefore contain sensitive employee files and must be protected accordingly.
- [x] Emergency contact field in employee profiles.
- [x] Configurable employment types (permanent, contract, temporary, intern, part-time, casual) and pay frequencies (daily, weekly, fortnightly, monthly), persisted per employee in backed-up app settings. Monthly salary base pay is annualized and prorated by configured frequency; daily-wage employees remain attendance-based. Regression tests authored, not run.

## Phase 5 — Attendance and leave

- [x] Daily attendance states and attendance corrections.
- [x] Optional check-in/check-out controls in daily attendance, including time selection and persisted display. Service validation requires check-in before check-out, enforces chronological order, and keeps both timestamps on the attendance date. Regression tests authored; execution pending.
- [x] Leave types, requests, and approval/rejection workflow.
- [x] Configurable annual leave entitlements with monthly accrual from the later of 1 January or employee joining date; approved leave days reduce the current calendar-year balance. Policies and balances use the existing backed-up app-settings collection. Carry-forward and holiday/weekend exclusions remain outstanding.
- [x] Attendance report with selectable date range, per-employee present/half-day/absent/leave/holiday counts, payable-day totals, and period-wide totals.

## Phase 6 — Payroll expansion

- [x] Salary components with effective dates and earning/deduction types.
- [x] Allowances and deductions in payroll runs.
- [x] Dated overtime entries with hours and hourly rates, included in payroll gross and payslip totals; one-off dated bonuses with descriptions and amounts, included only in the payroll period containing their date. Both are backed up and restore-validated. Overtime approval workflow and reimbursements remain outstanding.
- [x] Employee advance register with principal/outstanding balances, instalment amount, first due date, manual repayments, repayment history, and profile UI; payroll-period instalments are snapshotted as deductions and recovered against the advance only when the payslip is fully settled. Backup/restore includes employee advances and pending payroll deduction snapshots with reference and balance validation. Tests/builds remain unrun.
- [x] Add the Employee Advances asset account through schema migration v9; post advance issuance (debit Employee Advances, credit selected INR asset account) and manual repayments (debit selected INR asset account, credit Employee Advances) as balanced, idempotency-keyed journal adjustments. The service accepts a cash/bank asset account ID; employee profile dialogs now let the operator select any active INR asset account for disbursement and repayment. Payroll instalment recoveries are still operational-only and are not yet journal-posted; reconciliation and reversal/correction remain open.
- [x] Journal payroll instalment recovery when the payslip is fully settled: debit Salaries and Wages (gross-up for the deduction) and credit Employee Advances. Posting is stable-source checked and must succeed before the payslip is marked paid; pending snapshots are validated against the outstanding advance before posting. Regression tests are authored, not run.
- [x] Add an operator-facing employee advance reconciliation report linked from Team. It compares the HR subledger with the posted Employee Advances control account and shows per-employee advance balances, issue-journal presence, manual repayment-journal presence, and payroll recovery journal counts.
- [x] Add controlled opening-balance posting for unrepaid legacy advances with no linked journal history; debit Employee Advances and credit Opening Balance Equity using an operator-confirmed cut-off date.
- [x] Add controlled advance balance correction with reason, effective date, offset account, immutable adjustment journal, idempotent retry, HR register update, and correction history. The workflow does not rewrite original journals; it posts an auditable adjustment against the operator-selected offset account.
- [x] Payroll runs with draft, approval, partial-payment, and paid states.
- [x] Payslip generation and payroll history.
- [x] Payslip PDF/print output.
- [x] Reversal/correction workflow for employee advances and approved/partially-paid payroll adjustments. Generic correction UI remains deferred.

## Phase 7 — Finance/HR integration

- [x] Payroll liabilities and linked finance payments. New payroll runs accrue gross salary once, credit net Payroll Payable and supported deduction controls, settle net payments against selected INR asset accounts, and retain a cash-basis compatibility path for previously approved runs.
- [x] Employee-linked advances, issuance, manual repayment, payroll instalment recovery, controlled balance correction, and subledger-to-journal reconciliation.
- [x] Employee reimbursement claims, approval/rejection, partial settlement, expense accrual, reimbursement payable control, and finance reconciliation.
- [x] Complete cross-module reconciliation for POS sales, expenses, payroll accruals/payments, employee advances, and reimbursement claims/liabilities. Bank-statement reconciliation and inventory COGS matching remain outside this source-to-journal report.

## Phase 8 — UI/UX redesign

- [x] Add initial Finance ledger overview, accounts, and journal navigation.
- [x] Upgrade Finance dashboard with journal-based accounting net profit, accounting expenses, net cash flow, and a clearly separated POS gross-profit estimate.
- [x] Finance ledger, account management, journal, P&L/cash-flow overview, and source reconciliation screens.
- [x] Budget tracking screen and budget form.
- [x] Recurring income/expense templates, schedule processing, and template archive screen.
- [x] Customer/supplier directory and party-level receivable/payable balances.
- [x] Initial Team dashboard, employee directory, department management, and employee profile screens.
- [x] Initial attendance, leave, payroll-run, salary-component, and payslip screens.
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


## Overtime payroll update

Employee profiles now allow dated overtime entries with hours and an hourly rate. Payroll generation includes overtime falling within the run period in gross pay and the payslip's allowance total. Entries are stored in the backed-up app-settings collection; restore validates employee references, dates, hours, rate, and amount. A regression test covers the overtime-to-payslip calculation but has not been run. Overtime is currently treated as payroll-eligible when entered; a separate approval/rejection workflow and statutory deduction rules are still outstanding. Existing salary components can represent one-off bonuses by adding an earning component named Bonus, but there is not yet a dedicated bonus workflow.

- One-off bonus entry and overtime capture are available from employee profiles. Both feed payroll generation and payslip allowance totals; both are included in the Google Drive HR settings backup payload with restore validation. Tests authored but not run.


## Employee advances and payroll recovery update

Employee profiles now support advance creation with a principal, instalment amount, issue date, and first due date. The service stores integer-paise balances and repayment entries for manual repayments. Payroll generation adds a due instalment to the payslip deduction total and persists a per-payslip deduction snapshot. The advance balance is reduced only after the payslip is fully paid (or approved with a zero net amount); partial salary payments do not prematurely recover the advance. Pending deductions are reserved against duplicate payroll runs. Google Drive backup includes advance records and deduction snapshots, with employee, advance, amount, date, and repayment-balance validation. Remaining work: advance disbursement and repayment are not yet posted to the finance journal, and there is no reversal/correction workflow for a paid payslip. Tests were not run.


Advance disbursement and manual repayment dialogs now expose active INR asset accounts as the payment/receipt account. The selected account ID is passed into the service and included in the corresponding balanced journal entry. Payroll instalment recovery still requires journal integration and control-account reconciliation.


Payroll recovery accounting update: when a payslip is fully settled, the system posts a balanced journal entry debiting Salaries and Wages and crediting Employee Advances for the withheld instalment. This grosses salary expense back up from the net cash-payment expense already recorded, while reducing the advance asset. The posting is keyed to the payslip and checked against any existing journal before retrying. Snapshot references and outstanding balances are validated before posting; the payslip is not marked paid if the recovery journal fails. A service-level reconciliation calculation compares the aggregate HR advance register to the posted Employee Advances control-account balance. An operator-facing reconciliation screen, historical opening-balance treatment, and correction/reversal controls remain open. Regression tests were added but not executed.


## Employee advance reconciliation report

Added a Team navigation entry for the employee advance reconciliation screen. The screen displays the aggregate HR subledger balance, posted Employee Advances control-account balance, and difference; it also lists each advance with principal, outstanding balance, issue-journal status, manual repayment-journal coverage, payroll recovery journal count, and repayment history. It flags missing issue/manual-repayment journals as potential legacy or unreconciled records. The screen is read-only by design: reversing a journal without applying a corresponding HR register correction would compound the mismatch. A controlled correction workflow and historical opening-balance migration remain outstanding. No tests, formatting, analysis, or builds were run.


## Employee advance reconciliation hardening

The reconciliation screen now handles missing, duplicate, unposted, and structurally mismatched issue journals without relying on a single-result lookup that could throw at runtime. Manual repayment coverage checks validate the linked journal's posted state, two-line structure, amount, and Employee Advances credit. The report separately counts missing and duplicate payroll recovery journals, surfaces malformed register entries, and refreshes when the finance posting box changes. A zero aggregate difference is explicitly distinguished from per-advance journal integrity. The screen remains read-only; no historical opening-balance journal or correction is posted automatically. No tests, formatting, analysis, or builds were run.


## Legacy employee advance opening balances

A controlled opening-balance action is now available for legacy advances that have a positive outstanding balance, no repayment history, and no linked issue/repayment/payroll journal. The operator selects an effective date and explicitly confirms the amount. The service posts a stable-source opening-balance journal: debit Employee Advances and credit Opening Balance Equity. It rejects duplicate register IDs, existing linked journal history, repayment history, invalid account configuration, and dates before the issue date or in the future. It does not recreate historical cash movements or auto-adjust records with partial journal history. The reconciliation report recognizes and validates the opening-balance journal. Regression tests cover successful posting, idempotent rejection, and repayment-history rejection; tests have not been run.


## Employee advance payroll journal diagnostics

Payroll recovery reconciliation now validates more than the presence of a source-linked journal. It checks posted status, the two-line journal structure, Salaries and Wages debit, Employee Advances credit, matching debit/credit amounts, and that the combined payslip recovery journal covers the individual advance repayment amount. The report also flags malformed payroll repayment records. A regression test covers a payslip recovering instalments from multiple advances into one combined journal. Tests remain unexecuted.


## Overtime approval workflow

New overtime entries are saved as pending and excluded from payroll until approved. The employee profile provides approve/reject controls; rejection requires a reason. Review decisions record a timestamp and note. Overtime entries cannot be added or reviewed once a payroll run snapshots their date, preventing retroactive changes to generated payslips. Existing overtime entries without a status remain treated as approved to preserve historical payroll behavior. Regression coverage checks pending exclusion, rejection, and prevention of re-approving a rejected entry; tests have not been run.


## Salary structure implementation update

- [x] Save active employee earning/deduction components as reusable named salary structures in app settings (included in the existing backup payload).
- [x] Apply a saved structure to an employee from an effective date; close prior active components on the preceding day and roll back partial writes best-effort.
- [x] Record effective-dated base-pay changes and include them in employment history.
- [x] Use the latest base-pay rate effective on the payroll run start date when generating a payslip.
- [x] Reject duplicate base-pay effective dates and changes overlapping a generated payroll period.
- [x] Author regression tests for salary structure replacement and future-dated base-pay changes (not run).
- [x] Add configurable salary grade bands, effective-dated employee grade assignment, grade-range enforcement, and mid-period base-pay proration across effective-dated salary changes.


## SME completion pass — 10 November 2026

Priority for the remaining Finance work is correctness and release safety, not additional modules:

1. Verify the current Hive CE branch with dependency resolution, adapter regeneration, formatting, analysis, tests, and Android release build. The latest recorded validation runs failed; no Finance checklist item is considered release-verified until a green run exists.
2. Close accounting correctness gaps: configurable POS payment destination mapping, payroll liability/payment linkage, employee advance corrections, and reversal-safe allocation/history.
3. Keep low-value enterprise scope deferred: multi-company accounting, complex approval chains, statutory payroll automation, and multi-user/cloud accounting.
4. Preserve existing POS, GST, inventory, invoice, printing, and Google Drive backup behaviour. Do not merge this branch to main until branch integration and legacy Hive data migration are tested.

This checklist records implementation only when code exists; validation items remain open until a passing CI run is observed.


### POS payment-account mapping

- [x] Persist cash/card/UPI destination account mapping in the existing app-settings backup collection.
- [x] Add a Finance screen to select active INR asset accounts for each POS payment method.
- [x] Apply configured mappings to startup and manual retry POS-to-journal synchronization, retaining the existing Cash/Bank defaults for shops that have not configured mappings.
- [x] Add service tests for a separate UPI wallet account and rejection of invalid non-asset mappings (tests authored; execution pending).
- [ ] Validate with Flutter test/analyze/build in CI.


### Payroll payment account selection

- [x] Add cash/bank/wallet account selection to the payslip payment dialog.
- [x] Validate that the selected account is active, INR, and an asset account before recording payment.
- [x] Pass the selected destination account to the payroll settlement journal and reject a mismatch before marking the payslip paid. New accrual-based payroll payments debit Payroll Payable and credit the selected active INR asset account; historical cash-basis payroll retains the legacy expense-sync path.
- [x] Cover bank posting and invalid expense-account rejection in payroll service regression tests (execution pending).
- [x] Payroll liability accrual and settlement are implemented as a separate accrual-based flow for new approvals, with a compatibility path for historical cash-basis runs.


## Payroll liability implementation — completed 10 November 2026

Newly approved payroll runs use accrual accounting:

1. Approval posts gross Salaries and Wages once, with credits to net Payroll Payable, Employee Advances for advance deductions, and Payroll Deductions Payable for other deductions.
2. Partial and final salary payments debit Payroll Payable and credit the operator-selected active INR asset account.
3. Advance recovery is reflected in the accrual journal and the HR advance subledger; the legacy gross-up recovery journal is retained only for historical cash-basis runs.
4. New payroll payments do not create ordinary Salary-Run Expense records. Previously approved cash-basis runs without an accrual journal retain the legacy payment path.
5. Stable source identities protect approval, partial settlement, retries, and payroll adjustments. Finance reconciliation compares payslip gross/net, posted accruals, settlements, and Payroll Payable balance.

Approved payroll adjustments post separate immutable journals and update the payslip and payroll-run snapshots with an audit record. The Payroll Deductions Payable account is available for subsequent statutory/third-party settlement through the existing journal adjustment workflow.

Release validation and regression tests remain pending and are intentionally owned by the repository owner.

## Finance and remaining HR implementation update — 10 November 2026

- Added schema v10 payroll liability accounts and schema v11 employee reimbursement payable control account.
- New payroll approvals post one stable accrual per payslip: Dr Salaries and Wages; Cr Payroll Payable for net salary; Cr Employee Advances for reserved advance deductions; and Cr Payroll Deductions Payable for other deductions. Partial salary payments debit Payroll Payable and credit the selected active INR asset account.
- Existing approved cash-basis payroll runs retain their previous expense-on-payment compatibility path. New accrual payroll payments no longer create duplicate salary Expense records.
- Payroll approval, payment, and adjustment journals use stable source identities and are included in payroll liability reconciliation. Approved payroll adjustments update payslip/run totals, retain an audit history, and can be reversed through an immutable journal reversal with payslip/run rollback.
- Employee advance balance correction is operator-controlled: verified target balance, effective date, reason, and offset account are required. The service posts a balanced adjustment and updates the HR subledger; previous journals remain immutable.
- Reimbursement claims support submission, approval/rejection, partial payment, settlement, and cancellation. Approval accrues the expense and reimbursement payable; each payment settles the payable against the selected cash/bank/wallet asset account. Cancellation reverses settlement journals first and then the accrual journal, with reconciliation checking reversal coverage.
- Finance dashboard now displays journal-based accounting net profit separately from the POS gross-profit estimate. Primary dashboard, accounting reports, and reconciliation views use a centered responsive content frame. Finance reconciliation includes payroll and reimbursement control-account balances.
- Salary grade bands and effective-dated grade assignments are stored in backed-up app settings. Base-pay changes and payroll generation enforce the assigned grade range. Monthly, weekly, fortnightly, daily-frequency, and daily-wage calculations prorate effective-dated base-pay changes within the payroll period.
- Tests, formatting, static analysis, builds, and CI were intentionally not run. Release validation remains with the repository owner.
