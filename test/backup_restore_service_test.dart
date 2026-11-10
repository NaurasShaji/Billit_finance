import 'package:flutter_test/flutter_test.dart';
import 'package:billit/services/backup_restore_service.dart';
import 'package:billit/models/product.dart';
import 'package:billit/models/sale.dart';

void main() {
  const service = BackupRestoreService();

  group('BackupRestoreService', () {
    test('accepts legacy backups with omitted optional fields', () {
      final payload = service.parse({
        'users': [
          {
            'id': 'u1',
            'username': 'admin',
            'password': 'hash',
            'userType': 'admin',
          },
        ],
        'products': [
          {
            'id': 'p1',
            'name': 'Notebook',
            'sellingPrice': 50,
            'costPrice': 30,
            'stock': 10,
          },
        ],
        'sales': [
          {
            'id': 's1',
            'date': '2026-01-02T10:00:00.000',
            'items': [
              {
                'productId': 'p1',
                'qty': 2,
                'sellingPrice': 50,
                'costPrice': 30,
                'subtotal': 100,
              },
            ],
            'totalAmount': 100,
            'totalCost': 60,
            'profit': 40,
            'payment': 'cash',
          },
        ],
        'expenses': [
          {
            'id': 'e1',
            'date': '2026-01-02T12:00:00.000',
            'category': 'Travel',
            'amount': 25,
          },
        ],
        'employees': [
          {
            'id': 'emp1',
            'name': 'Employee',
            'type': 'daily',
            'wage': 500,
          },
        ],
      });

      expect(payload.users, hasLength(1));
      expect(payload.products.single.unit, UnitType.pcs);
      expect(payload.products.single.category, 'General');
      expect(payload.sales.single.payment, PaymentMethod.cash);
      expect(payload.sales.single.items.single.unitLabel, 'pcs');
      expect(payload.sales.single.items.single.taxableAmount, 0);
      expect(payload.expenses.single.description, '');
      expect(payload.employees.single.attendance, 0);
      expect(payload.employees.single.salaryPaid, isFalse);
      expect(payload.appSettings, isNull);
    });

    test('rejects a non-list collection before returning a payload', () {
      expect(
        () => service.parse({'products': {'id': 'not-a-list'}}),
        throwsFormatException,
      );
    });

    test('rejects malformed nested sale items', () {
      expect(
        () => service.parse({
          'sales': [
            {
              'id': 's1',
              'date': '2026-01-02',
              'items': ['invalid'],
              'totalAmount': 1,
              'totalCost': 1,
              'profit': 0,
            },
          ],
        }),
        throwsFormatException,
      );
    });

    test('rejects duplicate IDs rather than silently overwriting records', () {
      final product = {
        'id': 'p1',
        'name': 'Notebook',
        'sellingPrice': 50,
        'costPrice': 30,
        'stock': 10,
      };
      expect(
        () => service.parse({
          'products': [product, product],
        }),
        throwsFormatException,
      );
    });

    test('rejects non-finite numeric values', () {
      expect(
        () => service.parse({
          'products': [
            {
              'id': 'p1',
              'name': 'Notebook',
              'sellingPrice': double.infinity,
              'costPrice': 30,
              'stock': 10,
            },
          ],
        }),
        throwsFormatException,
      );
    });

    test('treats backups without finance collections as legacy', () {
      final payload = service.parse({'users': [], 'products': []});
      expect(payload.financeAccounts, isNull);
      expect(payload.financeTransactions, isNull);
    });

    test('rejects a partial finance backup collection set', () {
      expect(
        () => service.parse({
          'financeAccounts': [],
          'financeTransactions': [],
        }),
        throwsFormatException,
      );
    });

    test('rejects budgets that reference unknown or non-expense accounts', () {
      expect(
        () => service.parse({
          'financeAccounts': [],
          'financeTransactions': [],
          'financePostings': [],
          'financeCategories': [],
          'financeParties': [],
          'financeBudgets': [
            {
              'id': 'budget-1',
              'name': 'Rent budget',
              'accountId': 'missing-account',
              'periodStart': '2026-11-01T00:00:00.000',
              'periodEnd': '2026-11-30T00:00:00.000',
              'budgetPaise': 100000,
            },
          ],
        }),
        throwsFormatException,
      );
    });

    test('rejects posted finance transactions with unbalanced postings', () {
      expect(
        () => service.parse({
          'financeAccounts': [
            {
              'id': 'cash',
              'name': 'Cash',
              'accountType': 'asset',
            },
            {
              'id': 'expense',
              'name': 'Expense',
              'accountType': 'expense',
            },
          ],
          'financeTransactions': [
            {
              'id': 'txn',
              'transactionNumber': 'TXN-1',
              'transactionType': 'expense',
              'status': 'posted',
              'date': '2026-01-01T00:00:00.000',
            },
          ],
          'financePostings': [
            {
              'id': 'debit',
              'transactionId': 'txn',
              'accountId': 'expense',
              'debitPaise': 100,
              'creditPaise': 0,
            },
            {
              'id': 'credit',
              'transactionId': 'txn',
              'accountId': 'cash',
              'debitPaise': 0,
              'creditPaise': 90,
            },
          ],
          'financeCategories': [],
          'financeParties': [],
        }),
        throwsFormatException,
      );
    });

    test('rejects fractional paise values in finance postings', () {
      expect(
        () => service.parse({
          'financeAccounts': [],
          'financeTransactions': [],
          'financePostings': [
            {
              'id': 'line',
              'transactionId': 'txn',
              'accountId': 'cash',
              'debitPaise': 10.5,
              'creditPaise': 0,
            },
          ],
          'financeCategories': [],
          'financeParties': [],
        }),
        throwsFormatException,
      );
    });

    test('preserves provided app settings as a map', () {
      final payload = service.parse({
        'appSettings': {'theme': 'dark', 'showLogo': true},
      });
      expect(payload.appSettings, {'theme': 'dark', 'showLogo': true});
    });
  });
}
