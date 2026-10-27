import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/models.dart';

enum ScanResult { added, unknown }

class CartProvider extends ChangeNotifier {
  CartProvider(this._db) {
    refreshHeld();
  }
  final AppDatabase _db;

  final Map<String, SaleLine> _lines = {};
  Discount? discount;
  List<HeldCart> held = [];

  List<SaleLine> get lines => _lines.values.toList();
  int get itemCount => _lines.values.fold(0, (s, l) => s + l.qty);
  double get subtotal => _lines.values.fold(0.0, (s, l) => s + l.total);
  double get discountAmount => discount?.amountFor(subtotal) ?? 0;
  double get total => subtotal - discountAmount;
  bool get isEmpty => _lines.isEmpty;
  int qtyOf(String barcode) => _lines[barcode]?.qty ?? 0;

  /// Adds the product for [barcode]; a repeated scan increments the quantity.
  Future<(ScanResult, Product?)> scan(String barcode) async {
    final product = await _db.productByBarcode(barcode);
    if (product == null) return (ScanResult.unknown, null);
    add(product);
    return (ScanResult.added, product);
  }

  void add(Product p) {
    final cur = _lines[p.barcode];
    _lines[p.barcode] = SaleLine(
      barcode: p.barcode,
      name: p.name,
      price: p.price,
      qty: (cur?.qty ?? 0) + 1,
      cost: p.cost,
    );
    notifyListeners();
  }

  void increment(String barcode) {
    final l = _lines[barcode];
    if (l == null) return;
    _lines[barcode] = l.withQty(l.qty + 1);
    notifyListeners();
  }

  void decrement(String barcode) {
    final l = _lines[barcode];
    if (l == null) return;
    if (l.qty <= 1) {
      _lines.remove(barcode);
      if (_lines.isEmpty) discount = null;
    } else {
      _lines[barcode] = l.withQty(l.qty - 1);
    }
    notifyListeners();
  }

  void setDiscount(Discount? d) {
    discount = (d == null || d.value <= 0) ? null : d;
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    discount = null;
    notifyListeners();
  }

  // ---- held carts ----
  Future<void> refreshHeld() async {
    held = await _db.heldCarts();
    notifyListeners();
  }

  /// Puts the current cart on hold and empties it.
  Future<void> holdCurrent() async {
    if (_lines.isEmpty) return;
    await _db.holdCart(lines, discount);
    clear();
    await refreshHeld();
  }

  /// Replaces the current cart by the held one, which is then removed from the list.
  Future<void> resume(HeldCart h) async {
    _lines
      ..clear()
      ..addEntries(h.lines.map((l) => MapEntry(l.barcode, l)));
    discount = h.discount;
    await _db.deleteHeld(h.id);
    await refreshHeld();
  }

  Future<void> deleteHeld(HeldCart h) async {
    await _db.deleteHeld(h.id);
    await refreshHeld();
  }
}
