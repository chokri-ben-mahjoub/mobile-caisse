import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../data/purchase.dart';

class PurchasesProvider extends ChangeNotifier {
  PurchasesProvider(this._db) {
    load();
  }
  final AppDatabase _db;

  /// Newest first.
  List<Purchase> purchases = [];
  List<SupplierPayment> payments = [];

  List<SupplierAccount> get accounts => SupplierAccount.group(purchases, payments);

  /// Total still owed to suppliers.
  double get owed => round3(accounts.where((a) => a.owes).fold(0.0, (s, a) => s + a.balance));

  /// Purchases of the current month.
  double get monthTotal {
    final n = DateTime.now();
    return round3(purchases.where((p) => p.date.year == n.year && p.date.month == n.month).fold(0.0, (s, p) => s + p.total));
  }

  Future<void> load() async {
    purchases = await _db.purchases();
    payments = await _db.supplierPayments();
    notifyListeners();
  }

  /// Saves the receipt, adds the quantities to the stock and updates purchase prices.
  Future<void> add(Purchase p) async {
    await _db.insertPurchase(p);
    await load();
  }

  Future<void> pay(SupplierAccount a, double amount, {String note = ''}) async {
    await _db.insertSupplierPayment(
        SupplierPayment(supplier: a.name, phone: a.phone, amount: amount, date: DateTime.now(), note: note.trim()));
    await load();
  }

  Future<void> removePayment(SupplierPayment p) async {
    if (p.id == null) return;
    await _db.deleteSupplierPayment(p.id!);
    await load();
  }
}
