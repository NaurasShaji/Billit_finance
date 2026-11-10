# Hive Persistence Audit

Branch audited: `feature/finance-team-promotion`

## Startup and box initialization

Startup is centralized in `lib/main.dart`:

1. `WidgetsFlutterBinding.ensureInitialized()` runs before storage initialization.
2. Web uses `Hive.initFlutter()`; other platforms initialize Hive under the application documents directory.
3. All fourteen adapters listed below are registered before any typed box is opened.
4. Typed boxes opened at startup:
   - `users` — `Box<User>`
   - `products` — `Box<Product>`
   - `sales` — `Box<Sale>`
   - `expenses` — `Box<Expense>`
   - `employees` — `Box<Employee>`
5. Finance boxes created by schema migration 1→2:
   - `finance_accounts` — `Box<FinanceAccount>`
   - `finance_transactions` — `Box<FinanceTransaction>`
   - `finance_postings` — `Box<FinancePosting>`
   - `finance_categories` — `Box<FinanceCategory>`
   - `finance_parties` — `Box<FinanceParty>`
6. Dynamic boxes opened at startup:
   - `session`
   - `app_settings`

All ten typed box names are centralized in `lib/services/boxes.dart`. The two dynamic box names remain string literals in startup and backup code.

## Hive adapter registry

| Type ID | Adapter / persisted type | Field IDs |
|---:|---|---|
| 1 | `UserType` enum | 0 admin, 1 worker |
| 2 | `User` | 0–5 |
| 3 | `UnitType` enum | 0 pcs, 1 kg, 2 sqft |
| 4 | `Product` | 0–11 |
| 5 | `PaymentMethod` enum | 0 cash, 1 card, 2 upi |
| 6 | `SaleItem` | 0–11 |
| 7 | `Sale` | 0–19 |
| 8 | `Expense` | 0–5 |
| 9 | `Employee` | 0–5 |
| 10 | `FinanceAccount` | 0–6 |
| 11 | `FinanceTransaction` | 0–11 |
| 12 | `FinancePosting` | 0–7 |
| 13 | `FinanceCategory` | 0–4 |
| 14 | `FinanceParty` | 0–6 |

Type ID 0 is unused. IDs 1–14 are now reserved. Finance models use string-valued classifications rather than persisted enums, keeping each new model to one Hive type ID. Do not reuse any type ID, including IDs belonging to enums.

## Compatibility and migration constraints

- Hive field IDs are the persisted schema. Never renumber or reuse an existing field ID.
- Additive fields must use a new field ID and have a backward-compatible default in the generated adapter. Regenerate adapters after model changes; do not hand-edit generated files.
- `Expense.employeeId` is the newest additive field (ID 5) and is nullable, so records written before it existed can be read as null.
- `Product`, `SaleItem`, and `Sale` generated readers contain defaults for several newer optional fields. Other fields are read with strict casts and have no migration fallback.
- `Employee` fields 0–5 are all read as required values. Changing this model needs explicit compatibility handling for older records.
- Enum values are persisted by numeric index. Do not reorder or remove enum values; append new values only, or implement an explicit migration.
- `SchemaMigrationService` now stores the application schema version under `app_settings.schema_version` and runs during startup after existing boxes are opened. Installations without a marker are assigned legacy baseline version 1.
- The migration runner enforces sequential one-version steps, rejects invalid/future versions and missing/duplicate steps, and advances the stored version only after a migration callback succeeds. Migration callbacks must be idempotent because Hive has no cross-box transaction.
- Finance schema migration 1→2 is registered at startup. It creates the five finance boxes and seeds nine default accounts using deterministic IDs. Finance migration and journal tests have been authored but have not yet been executed.
- Adapter registration and box opening remain explicit calls in `main()`; adapter uniqueness/registration coverage is still pending.
- `session` and `app_settings` are dynamic key/value stores and have no typed schema enforcement. Their keys and value formats need a separately maintained migration contract.
- Google Drive backup uses a manually serialized JSON format, not Hive binary files. Backup compatibility must be maintained separately from Hive adapter compatibility.

## Finance implementation constraints

The finance persistence layer now has `FinanceAccount`, `FinanceTransaction`, `FinancePosting`, `FinanceCategory`, and `FinanceParty` models in separate Hive boxes. Type IDs 10–14 are reserved. `FinanceLedgerService` validates balanced integer-paise journal entries and calculates posted-only raw debit-minus-credit account balances. Google Drive backup/restore does not yet cover these boxes. Do not repurpose `Expense`, `Sale`, or payroll payment records as a ledger. Preserve existing boxes and their field IDs. Prefer integer minor units (paise) or a documented decimal representation for accounting source-of-truth amounts rather than binary floating-point.

## Follow-up work

- Register an explicit schema migration before introducing each new persisted finance schema version.
- Add adapter registry/type-ID uniqueness tests and run migration tests using representative legacy records.
- Google Drive backup export, parser, restore snapshots, and rollback now include all five finance boxes; the integration tests are authored but still need execution.
- Run the restore and finance persistence tests before release.
- Centralize dynamic box names and document the keys owned by each module.
