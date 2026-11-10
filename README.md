# Billit

Billit is a point-of-sale and retail management app for billing, inventory, GST, reporting, backups, and printer workflows. It uses Hive for local data storage and includes billing, inventory, reporting, backup, and printer workflows.

![Billit app logo](assets/icon/billit_logo.svg)

## Features

### Billing and invoices

- Search the product catalog and add items to a shopping cart.
- Track quantities against available stock and prevent adding more than the remaining stock.
- Enter customer name and phone number, apply a discount, and choose Cash, Card, or UPI.
- Calculate the sale total, product cost, and profit; completing a sale records the invoice and updates stock.
- Browse saved invoices, edit or delete an invoice, and generate a PDF or print a receipt.
- Look up customers by name or phone number and review their past invoices.

### Products and inventory

- Add and edit products with a name, selling price, cost price, stock quantity, category, and subcategory.
- Organize products with category, subcategory, and unit filters; search by product name.
- Track products sold by pieces (`pcs`), kilograms (`kg`), or square feet (`sqft`).
- View the calculated difference between selling and cost prices while editing a product.

### Sales reports

- Review daily sales summaries; admins can also view monthly and yearly summaries and navigate to other reporting periods.
- See revenue, profit, and invoice counts for the selected reporting period.
- Browse recorded sales and access invoice actions from the report views.

### Finance and Team

Finance and Team are top-level tabs for admins.

Finance includes the existing POS/expense summary plus an accounting ledger:
- Record manual income, expenses, and cash/bank transfers.
- Review the chart of accounts, normal balances, and posted journal.
- View journal-based period income, expenses, accounting profit, and cash flow.
- POS sales, GST collected, general expenses, and payroll expenses are imported into the ledger with stable source references.
- Invoice edits and deletions create reversal entries instead of changing posted accounting history.
- POS gross profit remains separate from journal-based accounting profit.
- Legacy expense and POS records remain in their existing Hive boxes and continue to drive the operational screens.

Team includes employee profile and HR foundations:
- Manage employee codes, contact details, departments, designations, joining dates, employment status, and notes.
- Mark daily attendance as present, absent, half-day, leave, or holiday.
- Submit leave requests, prevent overlapping requests, and approve or reject them.
- Approved leave creates locked attendance records.
- Existing daily-wage/monthly-salary payroll and partial payment tracking remain available.
- Use built-in expense categories such as rent, utilities, transport, supplies, maintenance, and miscellaneous, or add a category.
- Browse expense history by day, month, or year; navigate between periods and filter salary expenses separately from other expenses.
- Add employees as daily-wage or monthly-salary staff, set their pay amount, edit their pay type or amount, and delete employee records.
- Record daily wage payments and monthly salary payments, with summaries of employees and payments for the current day or month. Each payment is linked to the employee by id, so renaming or duplicate names never mix up who was paid.
- Review payroll/expense totals by day, month, or year, including daily wages, monthly salaries, other expenses, and net expenses.

### Backup, printer, and account tools

- Back up products, sales, expenses, employees, settings, and all finance ledger records to Google Drive, browse available backups, and restore a selected backup.
- Configure recurring Google Drive backups by interval. Restoring replaces current business data, so keep a current backup before restoring.
- Scan paired Bluetooth devices and select a default thermal printer.
- Change account passwords through the admin account.
- Access the in-app Help and FAQ.

### Accounts and access

- Admin and worker accounts are seeded on first launch.
- Admins see the Overview, Billing, Inventory, Reports, Finance, and Team tabs. Backups, bulk import, report exports, customer lookup, and account tools are under Settings > Business Tools. Workers see the Billing, Products, and Reports tabs, with daily reports.

## Requirements

- Flutter SDK with Dart **3.6 or later**
- A supported Flutter target, such as Chrome or an Android device/emulator

## Getting started

1. Clone this repository and open the project directory:

   ```bash
   git clone <repository-url>
   cd <repository-directory>
   ```

2. Install dependencies:

   ```bash
   flutter pub get
   ```

3. Run the app:

   ```bash
   # Web
   flutter run -d chrome

   # Android (replace with your connected device or emulator ID)
   flutter run -d <device-id>
   ```

On first launch, the app creates these local accounts:

| Role | Username | Initial password |
| --- | --- | --- |
| Admin | `admin` | `admin123` |
| Worker | `worker` | `worker123` |

These are default credentials for a new local installation. Change the admin password after signing in, and do not use these credentials for a shared or production deployment.

## Development

Hive adapters are checked into `lib/models/`. After changing a Hive model, regenerate the adapters:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Run the test suite with:

```bash
flutter test
```

## Project structure

```text
lib/
  models/       Hive data models and generated adapters
  screens/      App screens and feature tabs
  services/     Authentication, billing, backups, PDFs, and printing
  widgets/      Reusable UI components
  main.dart     App initialization and root widget
test/           Flutter tests
assets/         App icons and other bundled assets
```

## Data and backups

The app stores business data locally with Hive. The accounting journal uses integer paise, balanced debit/credit postings, and reversal records for corrections. Export backups regularly and store them somewhere safe. Legacy backups without finance collections remain supported; restoring one preserves the current finance boxes. Google Drive backup requires signing in to a Google account and an available Google Sign-In configuration for the target platform.

## Android launcher icon

The Android launcher icon is generated from `assets/icon/billit_icon.png` using the
`flutter_launcher_icons` configuration in `pubspec.yaml`. After changing the
icon artwork or launcher-icon configuration, regenerate the Android resources:

```powershell
flutter pub get
dart run flutter_launcher_icons
flutter clean
flutter build apk --release
```

If an already-installed Android launcher continues showing the previous icon,
uninstall the old Billit app before installing the newly built APK. Some launchers
cache application icons.
