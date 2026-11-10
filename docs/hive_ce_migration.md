# Hive CE Migration

## Scope

Billit replaces the original `hive`, `hive_flutter`, and `hive_generator`
packages with the maintained Hive Community Edition packages:

- Runtime: `hive_ce`
- Flutter integration: `hive_ce_flutter`
- Adapter generator: `hive_ce_generator`

The app currently targets Flutter 3.29.3 in CI. The Flutter integration is
pinned to 2.3.4 to stay compatible with that toolchain; do not raise it to the
2.4/2.5 line without first raising and validating the Flutter SDK version.

## Data compatibility requirements

Hive CE is the continuation of Hive v2 and is intended to retain the existing
Hive v2 storage format. This migration must remain an in-place engine/package
replacement, not a box reset or data conversion.

The following persisted identifiers are part of the compatibility contract:

- Existing box names remain unchanged.
- Existing Type IDs 1–20 remain unchanged.
- Existing field IDs remain unchanged and are never reused.
- Existing enum numeric values remain unchanged.
- Additive model fields require a new field ID and a backward-compatible
  default when reading records written by an older app.
- Google Drive JSON backup remains a separate format and must continue to
  support backups created before finance and HR collections existed.

Do not delete, rename, clear, or recreate existing business boxes during this
migration. Do not add a one-time database reset to work around adapter errors.

## Code changes

Package imports are changed as follows:

| Previous | Hive CE |
|---|---|
| `package:hive/hive.dart` | `package:hive_ce/hive_ce.dart` |
| `package:hive_flutter/hive_flutter.dart` | `package:hive_ce_flutter/hive_ce_flutter.dart` |
| `package:hive_flutter/adapters.dart` | `package:hive_ce_flutter/adapters.dart` |

Adapter annotations and registration continue to use the Hive v2-style API.
Generated adapters must be regenerated with the CE generator; do not maintain
hand-edited generated adapter files.

## Validation before release

Run on a Flutter-enabled environment:

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release
```

Also perform a real-device persistence check using a copy of an existing
Billit data directory:

1. Install/run the old build and create representative users, products, sales,
   expenses, employees, and settings.
2. Copy the app data directory and keep the original untouched.
3. Open the copied data with the Hive CE build.
4. Verify record counts, IDs, enum values, dates, nested sale items, stock,
   expenses, employee/payroll data, and settings.
5. Export a Google Drive JSON backup, restore it into a clean test install,
   and verify legacy backup behavior.
6. Confirm that the app does not create empty replacement boxes or silently
   lose data when an adapter fails to read a record.

The automated test suite and CI build are necessary but do not replace this
real-data compatibility test. No production database should be opened with a
new release until this check passes.
