import 'package:hive_ce/hive_ce.dart';

import '../models/models.dart';
import 'boxes.dart';

class FinancePartyException implements Exception {
  const FinancePartyException(this.message);
  final String message;

  @override
  String toString() => 'FinancePartyException: $message';
}

class FinancePartyService {
  Future<FinanceParty> saveParty({
    String? id,
    required String name,
    required String partyType,
    String phone = '',
    String email = '',
    String taxIdentifier = '',
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const FinancePartyException('Party name is required.');
    }
    if (!{'customer', 'supplier', 'other'}.contains(partyType)) {
      throw const FinancePartyException(
        'Party type must be customer, supplier, or other.',
      );
    }
    final box = Hive.box<FinanceParty>(Boxes.financeParties);
    final partyId = id ?? 'party:${DateTime.now().microsecondsSinceEpoch}';
    final existing = box.get(partyId);
    if (existing != null &&
        existing.partyType != partyType &&
        Hive.box<FinancePosting>(Boxes.financePostings)
            .values
            .any((line) => line.partyId == partyId)) {
      throw const FinancePartyException(
        'Party type cannot change after journal postings exist.',
      );
    }
    final duplicate = box.values.any((item) =>
        item.id != partyId &&
        item.partyType == partyType &&
        item.name.trim().toLowerCase() == cleanName.toLowerCase());
    if (duplicate) {
      throw const FinancePartyException(
        'A party with this name and type already exists.',
      );
    }

    final party = FinanceParty(
      id: partyId,
      name: cleanName,
      partyType: partyType,
      phone: phone.trim(),
      email: email.trim(),
      taxIdentifier: taxIdentifier.trim(),
      active: existing?.active ?? true,
    );
    await box.put(party.id, party);
    return party;
  }

  int balancePaise({
    required FinanceParty party,
    required Iterable<FinanceTransaction> transactions,
    required Iterable<FinancePosting> postings,
  }) {
    final postedIds = transactions
        .where((transaction) => transaction.status == 'posted')
        .map((transaction) => transaction.id)
        .toSet();
    final accountId = party.partyType == 'customer'
        ? 'system:receivables'
        : party.partyType == 'supplier'
            ? 'system:payables'
            : null;
    if (accountId == null) return 0;
    var debit = 0;
    var credit = 0;
    for (final line in postings) {
      if (line.partyId != party.id ||
          line.accountId != accountId ||
          !postedIds.contains(line.transactionId)) {
        continue;
      }
      debit += line.debitPaise;
      credit += line.creditPaise;
    }
    return party.partyType == 'customer' ? debit - credit : credit - debit;
  }

  Future<void> archiveParty({
    required String partyId,
    required Iterable<FinanceTransaction> transactions,
    required Iterable<FinancePosting> postings,
  }) async {
    final box = Hive.box<FinanceParty>(Boxes.financeParties);
    final party = box.get(partyId);
    if (party == null) {
      throw const FinancePartyException('Party was not found.');
    }
    if (balancePaise(
          party: party,
          transactions: transactions,
          postings: postings,
        ) !=
        0) {
      throw const FinancePartyException(
        'Settle the outstanding balance before archiving this party.',
      );
    }
    await box.put(
      party.id,
      FinanceParty(
        id: party.id,
        name: party.name,
        partyType: party.partyType,
        phone: party.phone,
        email: party.email,
        taxIdentifier: party.taxIdentifier,
        active: false,
      ),
    );
  }
}
