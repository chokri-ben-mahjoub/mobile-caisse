import 'package:flutter/foundation.dart';

import '../data/credit.dart';
import '../data/database.dart';

class CreditsProvider extends ChangeNotifier {
  CreditsProvider(this._db) {
    load();
  }
  final AppDatabase _db;

  List<CreditEntry> entries = [];

  List<CreditAccount> get accounts => CreditAccount.group(entries);
  List<CreditAccount> get open => accounts.where((a) => a.balance > 0.0005).toList();
  double get outstanding => open.fold(0.0, (s, a) => s + a.balance);

  Future<void> load() async {
    entries = await _db.credits();
    notifyListeners();
  }

  Future<void> addDebt({required String customer, String phone = '', required double amount, int? saleId}) async {
    await _db.insertCredit(CreditEntry(
        customer: customer.trim(), phone: phone.trim(), amount: amount, date: DateTime.now(), saleId: saleId));
    await load();
  }

  Future<void> addPayment(CreditAccount a, double amount, {String note = ''}) async {
    await _db.insertCredit(
        CreditEntry(customer: a.name, phone: a.phone, amount: -amount, date: DateTime.now(), note: note.trim()));
    await load();
  }

  Future<void> remove(CreditEntry e) async {
    if (e.id == null) return;
    await _db.deleteCredit(e.id!);
    await load();
  }
}
