# Finance Ledger Persistence Decision

Status: approved implementation direction for `feature/finance-team-promotion`

## 1. Decision

Build the finance module as an offline-first, append-only accounting journal backed by Hive CE. Do not use a mutable account balance or a single signed transaction amount as the accounting source of truth.

Use:
- Account records for the chart of accounts and account metadata.
- A transaction header for the business event (income, expense, transfer, opening balance, adjustment, or reversal).
- One or more posting lines for the debit/credit impact on accounts.
- Integer paise for all persisted monetary amounts.
- Reversal/correction records instead of editing or deleting posted financial history.

A posted journal transaction must balance: total debits equal total credits. Draft transactions may be incomplete, but they must not affect balances or reports.

## 2. Hive persistence types

Implemented on this branch with reserved Hive type IDs 10–14 and 21–22. The finance models use string-valued classification fields rather than persisted enums; never reuse IDs 1–21.

| Model | Purpose | Key persisted fields |
|---|---|---|
| `FinanceAccount` | Cash, bank, wallet, receivable, payable, equity, income, and expense accounts | id, name, accountType, parentId, currencyCode, active, createdAt |
| `FinanceTransaction` | Header for a financial event | id, transactionNumber, transactionType, status, date, memo, reference, sourceType, sourceId, createdAt, postedAt, reversedTransactionId |
| `FinancePosting` | Debit/credit line within a transaction | id, transactionId, accountId, debitPaise, creditPaise, partyId, categoryId, memo |
| `FinanceCategory` | User-configurable income/expense classification mapped to an account | id, name, kind, accountId, active |
| `FinanceParty` | Customer or supplier identity for subledger use | id, name, partyType, contact fields, tax identifier, active |
| `FinanceBudget` | Period budget mapped to an expense account and optional category | id, name, accountId, categoryId, periodStart, periodEnd, budgetPaise, active, notes, createdAt |
| `FinanceRecurringTemplate` | Reusable income/expense posting schedule | id, name, transactionType, debitAccountId, creditAccountId, amountPaise, interval, nextDueDate, endDate, categoryId, partyId, memo, active, createdAt |

Use separate boxes for accounts, transaction headers, posting lines, categories, parties, budgets, and recurring templates. Keep posting lines independently queryable by transaction/account/date; do not rely on embedding an unbounded posting list in one transaction object.

Implemented model fields are in `lib/models/finance_*.dart`; Hive CE adapter implementations are checked in alongside them; their output must be regenerated or verified with build_runner in a Flutter-enabled environment. Schema migration 1→2 creates the five initial finance boxes and seeds nine stable default accounts; migration 2→3 adds GST Payable and Salaries and Wages accounts. Migration 5→6 adds the finance budgets box; migration 6→7 adds recurring templates. The journal service validates balanced integer-paise entries, writes postings before marking a transaction posted, derives balances from posted lines, and creates exact reversal entries without mutating the original transaction. Google Drive backup export/restore now includes the seven finance boxes (including budgets and recurring templates) and validates cross-references, parent accounts, category/account types, reversal targets, budget account/category compatibility, and posted-entry balance before writes. `FinanceSourceSyncService` imports legacy POS sales, general expenses, and payroll expenses using integer-paise conversion, stable source keys, revision snapshots, and reversal entries on invoice edits/deletes. GST collected is posted to a liability account; payroll expense categories map to a dedicated salary account and employee party. Manual income, expense, and transfer entry plus journal, account-balance, P&L, cash-flow, source-reconciliation, and budget tracking and recurring-template screens are now present. Tests are authored but still require execution.

## 3. Posting rules

- Income: debit the receiving asset account; credit the appropriate income account.
- Expense: debit the appropriate expense account; credit the paying asset account.
- Transfer: debit the destination asset account; credit the source asset account.
- Opening balance: post against an opening-balance equity account; do not store an independently editable opening balance that can drift from the journal.
- Adjustment: require an explicit debit and credit account and a reason.
- Reversal: create a new transaction with the exact opposite postings and a reference to the original. Never mutate the original posted transaction.
- Every posted transaction must have at least two valid posting lines, positive amounts, no line with both debit and credit, and equal debit/credit totals.
- Account balances and reports are derived from posted journal lines. Cache totals only as rebuildable projections, never as the source of truth.
- Use a stable transaction ID and idempotency key/source reference to prevent duplicate posting during retries, imports, or POS synchronization.

## 4. Money and currency

Persist amounts as integer minor units (for INR, paise). Do not use Dart `double` for accounting source-of-truth amounts.

- UI and legacy model values may remain doubles temporarily at compatibility boundaries.
- Convert legacy values once using a documented rounding rule (two decimal places) and retain the original source record for traceability.
- Store an ISO 4217 currency code on the account or transaction context. Do not assume every future business uses INR.
- Reject negative posting amounts; direction is represented by debit/credit fields.

## 5. Compatibility with existing Billit data

Do not repurpose or remove existing `Sale`, `Expense`, `Employee`, or payroll payment storage.

- Existing POS sales remain in the `sales` box. When integrated, create journal postings linked to the sale ID using a unique source key so a retry cannot post the same sale twice.
- Existing expenses remain in the `expenses` box. Migrate/import each legacy expense into the journal with its original expense ID as the source reference; keep the legacy record until migration and reconciliation are verified.
- Payroll payments must eventually post as journal transactions and retain employee/payroll-period references.
- Legacy backup JSON remains supported. Extend its format additively with finance data and metadata; restore must recognize backups that do not contain the new keys.
- Do not derive accounting revenue by summing both the existing sales box and newly created sale journal postings. Reports must choose one canonical source or query the journal only.

## 6. Query and reporting approach

- Account balance: sum posted debits/credits according to account normal balance.
- Cash flow: filter postings to cash/bank asset accounts and group by date and transaction classification.
- Profit and loss: aggregate income and expense account postings for the selected period.
- Receivables/payables: use party-linked control accounts and allocated settlement postings; do not treat invoice totals as cash received.
- Keep POS gross profit (sale price less recorded item cost) separate from accounting profit and label it accordingly.

## 7. Migration and rollout sequence

1. [x] Add schema versioning and a migration runner without changing existing boxes. The runner is integrated into startup; legacy installations receive schema version 1.
2. [x] Add five finance models, Hive CE adapters, boxes, and schema migration 1→2 with default accounts. Persistence and migration tests are authored but still require execution.
3. [x] Seed the default chart of accounts, including GST and payroll accounts. Opening balances still require an explicit setup workflow.
4. [x] Import legacy expenses and payroll expenses with deterministic source keys; reconciliation tests are authored but not yet executed.
5. [x] Add POS sale posting with duplicate protection, GST split, revision tracking, and reversal on edit/delete; reconciliation tests are authored but not yet executed.
6. [x] Integrate payroll expense records into the salary expense ledger account while preserving existing payroll payment allocation.
7. [x] Add initial journal-based P&L, cash-flow, account-balance, and journal screens. Full release remains blocked on running the migration, backup, source-sync, and ledger tests.

## 8. Explicit non-goals for the first ledger slice

- Multi-currency conversion and exchange-rate gains/losses.
- Tax filing or statutory accounting automation.
- Bank-feed synchronization.
- Inventory valuation/COGS accounting beyond the existing POS gross-profit calculation.
- Multi-user concurrent posting and server-side synchronization.

These can be added later without changing the basic journal contract.
