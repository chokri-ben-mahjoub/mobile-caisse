import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/models.dart';

class SalesProvider extends ChangeNotifier {
  SalesProvider(this._db) {
    load();
  }
  final AppDatabase _db;

  DateTime day = DateTime.now();

  /// Sales and returns of [day], newest first.
  List<Sale> sales = [];

  /// Net of sales minus returns.
  double get total => round3(sales.fold(0.0, (s, e) => s + e.total));
  double get profit => round3(sales.fold(0.0, (s, e) => s + e.profit));
  bool get hasUnknownCost => sales.any((e) => !e.isRefund && e.hasUnknownCost);
  double totalFor(PayMethod m) => round3(sales.where((s) => s.method == m).fold(0.0, (s, e) => s + e.total));

  int get salesCount => sales.where((s) => !s.isRefund).length;
  int get refundsCount => sales.where((s) => s.isRefund).length;

  /// Amount given back on returns today (positive).
  double get refundsTotal => -round3(sales.where((s) => s.isRefund).fold(0.0, (s, e) => s + e.total));

  Future<void> load() async {
    sales = await _db.salesOfDay(day);
    notifyListeners();
  }

  Future<void> shiftDay(int delta) {
    day = day.add(Duration(days: delta));
    return load();
  }

  bool get isToday {
    final n = DateTime.now();
    return day.year == n.year && day.month == n.month && day.day == n.day;
  }

  Future<Sale> record(Sale sale) async {
    final saved = await _db.insertSale(sale);
    day = DateTime.now();
    await load();
    return saved;
  }

  /// Quantity already returned per article of sale [saleId].
  Future<Map<String, double>> returnedQty(int saleId) => _db.returnedQty(saleId);
}
