# Hive CE Persistence Audit

Branch audited: `feature/finance-team-promotion`

## Startup and box initialization

Startup is centralized in `lib/main.dart`:

1. `WidgetsFlutterBinding.ensureInitialized()` runs before storage initialization.
2. Web uses `Hive.initFlutter()`; other platforms initialize Hive under the application documents directory.
3. All twenty-one adapters listed below are registered before any typed box is opened.
4. Typed boxes opened at startup:
   - `users` — `Box<User>`
   - `products` — `Box<Product>`
   - `sales` — `Box<Sale>`
   - `expenses` — `Box<Expense>`
   - `employees` — `Box<Employee>`
5. Finance boxes created by schema migration 1→2 and 5→6:
   - `finance_accounts` — `Box<FinanceAccount>`
   - `finance_transactions` — `Box<FinanceTransaction>`
   - `finance_postings` — `Box<FinancePosting>`
   - `finance_categories` — `Box<FinanceCategory>`
   - `finance_parties` — `Box<FinanceParty>`
   - `finance_budgets` — `Box<FinanceBudget>`
6. Dynamic boxes opened at startup:
   - `session`
   - `app_settings`

All seventeen typed box names are centralized in `lib/services/boxes.dart`. The two dynamic box names remain string literals in startup and backup code.

## Hive CE adapter registry

| Type ID | Adapter / persisted type | Field IDs |
|---:|---|---|
| 1 | `UserType` enum | 0 admin, 1 worker |
| 2 | `User` | 0–5 |
| 3 | `UnitType` enum | 0 pcs, 1 kg, 2 sqft |
| 4 | `Product` | 0–11 |
| 5 | `PaymentMethod` enum | 0 cash, 1 card, 2 upi |
| 6 | `SaleItem` | 0–11 |
| 7 | `Sale` | 0–20 (field 20: finance revision) |
| 8 | `Expense` | 0–6 (field 6: finance revision) |
| 9 | `Employee` | 0–15 (profile fields 6–15 added in schema v4) |
| 10 | `FinanceAccount` | 0–6 |
| 11 | `FinanceTransaction` | 0–11 |
| 12 | `FinancePosting` | 0–7 |
| 13 | `FinanceCategory` | 0–4 |
| 14 | `FinanceParty` | 0–6 |
| 15 | `HrDepartment` | 0–4 |
| 16 | `EmployeeAttendance` | 0–7 |
| 17 | `LeaveRequest` | 0–9 |
| 18 | `SalaryComponent` | 0–8 |
| 19 | `PayrollRun` | 0–9 |
| 20 | `Payslip` | 0–11 |
| 21 | `FinanceBudget` | 0–9 |

Type ID 0 is unused. IDs 1–21 are now reserved. Finance models use string-valued classifications rather than persisted enums, keeping each new model to one Hive type ID. Do not reuse any type ID, including IDs belonging to enums.

## Compatibility and migration constraints

- Hive field IDs are the persisted schema. Never renumber or reuse an existing field ID.
- Additive fields must use a new field ID and have a backward-compatible default in the generated Hive CE adapter. Regenerate adapters after model changes; do not hand-edit generated files.
- `Expense.employeeId` is the newest additive field (ID 5) and is nullable, so records written before it existed can be read as null.
- `Product`, `SaleItem`, and `Sale` generated readers contain defaults for several newer optional fields. Other fields are read with strict casts and have no migration fallback.
- `Employee` fields 0–5 are all read as required values. Changing this model needs explicit compatibility handling for older records.
- Enum values are persisted by numeric index. Do not reorder or remove enum values; append new values only, or implement an explicit migration.
- `SchemaMigrationService` stores the application schema version under `app_settings.schema_version` and runs during startup after existing boxes are opened. Installations without a marker are assigned legacy baseline version 1. Current schema version is 6 (finance v2/v3, HR v4/v5, budgets v6).
- The migration runner enforces sequential one-version steps, rejects invalid/future versions and missing/duplicate steps, and advances the stored version only after a migration callback succeeds. Migration callbacks must be idempotent because Hive has no cross-box transaction.
- Finance schema migrations 1→2 and 2→3 create the five initial finance boxes and seed eleven deterministic accounts. HR migrations 3→4 and 4→5 add HR and payroll boxes. Migration 5→6 creates `finance_budgets`. Migration, journal, HR, and budget tests are authored but have not yet been executed.
- Adapter registration and box opening remain explicit calls in `main()`; adapter uniqueness/registration coverage is still pending.
- `session` and `app_settings` are dynamic key/value stores and have no typed schema enforcement. Their keys and value formats need a separately maintained migration contract.
- Google Drive backup uses a manually serialized JSON format, not Hive binary files. Backup compatibility must be maintained separately from Hive CE adapter compatibility.

## Finance implementation constraints

The finance persistence layer has `FinanceAccount`, `FinanceTransaction`, `FinancePosting`, `FinanceCategory`, `FinanceParty`, and `FinanceBudget` models in separate Hive boxes. Type IDs 10–14 and 21 are reserved. `FinanceLedgerService` validates balanced integer-paise journal entries and calculates posted-only raw debit-minus-credit account balances. Google Drive backup export, parsing, restore snapshots, and rollback now cover these six finance boxes; test execution remains pending. Do not repurpose `Expense`, `Sale`, or payroll payment records as a ledger. Preserve existing boxes and their field IDs. Prefer integer minor units (paise) or a documented decimal representation for accounting source-of-truth amounts rather than binary floating-point.

## Follow-up work

- Register an explicit schema migration before introducing each new persisted finance schema version.
- Add adapter registry/type-ID uniqueness tests and run migration tests using representative legacy records.
- Google Drive backup export, parser, restore snapshots, and rollback now include all six finance boxes, including budget definitions; the integration tests are authored but still need execution.
- `Sale.financeRevision` and `Expense.financeRevision` are additive Hive fields for immutable journal revision tracking; keep their generated Hive CE adapters and backup serializers in sync.
- Run the restore and finance persistence tests before release.
- Centralize dynamic box names and document the keys owned by each module.
