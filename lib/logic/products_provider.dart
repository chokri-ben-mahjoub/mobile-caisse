import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/demo_data.dart';
import '../data/models.dart';

class ProductsProvider extends ChangeNotifier {
  ProductsProvider(this._db) {
    load();
  }
  final AppDatabase _db;

  List<Product> products = [];
  int lowCount = 0;
  bool onlyLow = false;
  String _query = '';

  bool hasDemo = false;

  /// Every product, ignoring the Produits screen search (used by the Stock tab).
  List<Product> all = [];

  /// Adds [delta] units (negative to remove) to a tracked product's stock.
  Future<void> adjustStock(Product p, double delta) => setStock(p, round3((p.stock ?? 0) + delta));

  /// Sets the stock of [p] to [value] (never below 0) and starts tracking it.
  Future<void> setStock(Product p, double value) async {
    await _db.setStock(p.barcode, value);
    await load();
  }

  /// Products shown in the quick-access row of the Caisse.
  List<Product> get favorites => all.where((p) => p.favorite).toList();

  Future<void> load() async {
    products = await _db.products(query: _query, onlyLow: onlyLow);
    all = await _db.products();
    lowCount = await _db.lowStockCount();
    hasDemo = await _db.hasDemo();
    notifyListeners();
  }

  /// Loads the demo catalogue and ~2 weeks of sales (see [DemoData]).
  Future<void> loadDemo() async {
    final items = DemoData.products();
    await _db.insertDemo(items, DemoData.sales(items, DateTime.now()));
    await load();
  }

  /// Removes everything created by [loadDemo]; real data is kept.
  Future<void> clearDemo() async {
    await _db.clearDemo();
    await load();
  }

  Future<void> search(String q) {
    _query = q;
    return load();
  }

  Future<void> setOnlyLow(bool v) {
    onlyLow = v;
    return load();
  }

  Future<void> save(Product p) async {
    await _db.upsertProduct(p);
    await load();
  }

  Future<void> delete(String barcode) async {
    await _db.deleteProduct(barcode);
    await load();
  }
}
