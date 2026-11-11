import 'package:hive_ce/hive_ce.dart';

import '../models/models.dart';
import 'boxes.dart';
import 'finance_ledger_service.dart';

/// Keeps product average cost and the inventory control account aligned.
class FinanceInventoryService {
  FinanceInventoryService({FinanceLedgerService? ledger})
      : _ledger = ledger ?? FinanceLedgerService();

  final FinanceLedgerService _ledger;

  static const openingTransactionId = 'finance:inventory:opening:baseline-v1';

  int _paise(double amount, String label) {
    if (!amount.isFinite || amount < 0) {
      throw FinanceLedgerException('$label must be a valid non-negative amount.');
    }
    return (amount * 100).round();
  }

  Future<void> initializeOpeningInventory({
    required Iterable<Product> products,
    required Box<FinanceAccount> accountsBox,
    required Box<FinanceTransaction> transactionsBox,
    required Box<FinancePosting> postingsBox,
  }) async {
    if (transactionsBox.containsKey(openingTransactionId)) return;

    var currentStockValuePaise = 0;
    for (final product in products) {
      if (product.stock < 0 || product.costPrice < 0 ||
          !product.stock.isFinite || !product.costPrice.isFinite) {
        throw FinanceLedgerException(
          'Product ${product.name} has invalid stock or average cost.',
        );
      }
      currentStockValuePaise += _paise(
        product.stock * product.costPrice,
        'Inventory value for ${product.name}',
      );
    }

    var existingInventoryBalance = 0;
    for (final posting in postingsBox.values) {
      if (posting.accountId == 'system:inventory') {
        existingInventoryBalance += posting.debitPaise - posting.creditPaise;
      }
    }
    final openingAdjustment =
        currentStockValuePaise - existingInventoryBalance;
    if (openingAdjustment == 0) return;

    final amount = openingAdjustment.abs();
    final inventoryDebit = openingAdjustment > 0;
    await _ledger.postTransaction(
      transaction: FinanceTransaction(
        id: openingTransactionId,
        transactionNumber: 'INV-OPENING-BASELINE-V1',
        transactionType: 'opening_balance',
        memo: 'Opening inventory valuation baseline',
        reference: 'Inventory migration',
        sourceType: 'inventory_opening',
        sourceId: 'baseline-v1',
      ),
      postings: [
        FinancePosting(
          id: '$openingTransactionId:inventory',
          transactionId: openingTransactionId,
          accountId: 'system:inventory',
          debitPaise: inventoryDebit ? amount : 0,
          creditPaise: inventoryDebit ? 0 : amount,
          memo: 'Opening inventory value',
        ),
        FinancePosting(
          id: '$openingTransactionId:equity',
          transactionId: openingTransactionId,
          accountId: 'system:opening-equity',
          debitPaise: inventoryDebit ? 0 : amount,
          creditPaise: inventoryDebit ? amount : 0,
          memo: 'Opening inventory offset',
        ),
      ],
      accountsBox: accountsBox,
      transactionsBox: transactionsBox,
      postingsBox: postingsBox,
    );
  }

  Future<void> receiveStock({
    required Product product,
    required double quantity,
    required double unitCost,
    required String offsetAccountId,
    required Box<FinanceAccount> accountsBox,
    required Box<FinanceTransaction> transactionsBox,
    required Box<FinancePosting> postingsBox,
  }) async {
    if (!quantity.isFinite || quantity <= 0 ||
        !unitCost.isFinite || unitCost <= 0) {
      throw const FinanceLedgerException(
        'Received quantity and unit cost must both be greater than zero.',
      );
    }
    if (!product.stock.isFinite || product.stock < 0 ||
        !product.costPrice.isFinite || product.costPrice < 0) {
      throw FinanceLedgerException('Product ${product.name} has invalid inventory values.');
    }
    final offset = accountsBox.get(offsetAccountId);
    if (offset == null || !offset.active || offset.currencyCode != 'INR' ||
        (!{'asset', 'liability'}.contains(offset.accountType) &&
            offset.id != 'system:opening-equity') ||
        offset.id == 'system:inventory') {
      throw const FinanceLedgerException(
        'Choose an active INR cash, bank, wallet, payable, or opening-equity account as the stock receipt offset.',
      );
    }

    final oldStock = product.stock;
    final oldCost = product.costPrice;
    final nextStock = oldStock + quantity;
    final nextCost = oldStock <= 0
        ? unitCost
        : ((oldStock * oldCost) + (quantity * unitCost)) / nextStock;
    final amountPaise = _paise(quantity * unitCost, 'Stock receipt value');
    if (amountPaise <= 0) {
      throw const FinanceLedgerException('Stock receipt value rounds to zero.');
    }

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final transactionId = 'finance:inventory:receipt:${product.id}:$stamp';
    final transactionNumber = 'INV-REC-$stamp';
    product
      ..stock = nextStock
      ..costPrice = nextCost;
    await product.save();
    try {
      await _ledger.postTransaction(
        transaction: FinanceTransaction(
          id: transactionId,
          transactionNumber: transactionNumber,
          transactionType: 'adjustment',
          memo: 'Stock received: ${product.name}',
          reference: product.id,
          sourceType: 'inventory_receipt',
          sourceId: transactionId,
        ),
        postings: [
          FinancePosting(
            id: '$transactionId:inventory',
            transactionId: transactionId,
            accountId: 'system:inventory',
            debitPaise: amountPaise,
            memo: 'Inventory received · ${product.name}',
          ),
          FinancePosting(
            id: '$transactionId:offset',
            transactionId: transactionId,
            accountId: offset.id,
            creditPaise: amountPaise,
            memo: 'Stock purchase offset',
          ),
        ],
        accountsBox: accountsBox,
        transactionsBox: transactionsBox,
        postingsBox: postingsBox,
      );
    } catch (_) {
      product
        ..stock = oldStock
        ..costPrice = oldCost;
      await product.save();
      rethrow;
    }
  }

  Future<void> writeOffStock({
    required Product product,
    required double quantity,
    required Box<FinanceAccount> accountsBox,
    required Box<FinanceTransaction> transactionsBox,
    required Box<FinancePosting> postingsBox,
  }) async {
    if (!quantity.isFinite || quantity <= 0 || quantity > product.stock) {
      throw const FinanceLedgerException(
        'Write-off quantity must be greater than zero and cannot exceed available stock.',
      );
    }
    final amountPaise = _paise(quantity * product.costPrice, 'Inventory write-off');
    if (amountPaise <= 0) {
      throw const FinanceLedgerException(
        'Inventory write-off value is zero. Set a valid average cost first.',
      );
    }
    final oldStock = product.stock;
    final transactionId =
        'finance:inventory:writeoff:${product.id}:${DateTime.now().microsecondsSinceEpoch}';
    product.stock = oldStock - quantity;
    await product.save();
    try {
      await _ledger.postTransaction(
        transaction: FinanceTransaction(
          id: transactionId,
          transactionNumber: 'INV-WO-${DateTime.now().microsecondsSinceEpoch}',
          transactionType: 'adjustment',
          memo: 'Inventory write-off: ${product.name}',
          reference: product.id,
          sourceType: 'inventory_writeoff',
          sourceId: transactionId,
        ),
        postings: [
          FinancePosting(
            id: '$transactionId:expense',
            transactionId: transactionId,
            accountId: 'system:inventory-adjustment',
            debitPaise: amountPaise,
            memo: 'Inventory shrinkage / write-off',
          ),
          FinancePosting(
            id: '$transactionId:inventory',
            transactionId: transactionId,
            accountId: 'system:inventory',
            creditPaise: amountPaise,
            memo: 'Inventory relieved · ${product.name}',
          ),
        ],
        accountsBox: accountsBox,
        transactionsBox: transactionsBox,
        postingsBox: postingsBox,
      );
    } catch (_) {
      product.stock = oldStock;
      await product.save();
      rethrow;
    }
  }
}
