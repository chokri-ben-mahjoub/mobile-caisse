import 'package:flutter/foundation.dart';

import '../data/database.dart';
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

  Future<void> load() async {
    products = await _db.products(query: _query, onlyLow: onlyLow);
    lowCount = await _db.lowStockCount();
    notifyListeners();
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
