import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/models.dart';

/// `weighed`: the product is sold by weight, the screen must ask for the weight.
enum ScanResult { added, unknown, weighed }

class CartProvider extends ChangeNotifier {
  CartProvider(this._db) {
    refreshHeld();
  }
  final AppDatabase _db;

  final Map<String, SaleLine> _lines = {};
  Discount? discount;
  List<HeldCart> held = [];

  List<SaleLine> get lines => _lines.values.toList();

  /// Articles in the cart (a weighed item counts for one).
  int get itemCount => _lines.values.fold(0, (s, l) => s + l.articles);
  double get subtotal => round3(_lines.values.fold(0.0, (s, l) => s + l.total));
  double get discountAmount => discount?.amountFor(subtotal) ?? 0;
  double get total => round3(subtotal - discountAmount);
  bool get isEmpty => _lines.isEmpty;
  double qtyOf(String barcode) => _lines[barcode]?.qty ?? 0;

  /// Looks the product up. Unit products are added straight away; a weighed
  /// product is returned with [ScanResult.weighed] so the caller can ask the weight.
  Future<(ScanResult, Product?)> scan(String barcode) async {
    final product = await _db.productByBarcode(barcode);
    if (product == null) return (ScanResult.unknown, null);
    if (product.byWeight) return (ScanResult.weighed, product);
    add(product);
    return (ScanResult.added, product);
  }

  /// Adds [qty] of [p] (1 unit, or a weight in kg for weighed products).
  void add(Product p, {double qty = 1}) {
    final cur = _lines[p.barcode];
    _lines[p.barcode] = SaleLine(
      barcode: p.barcode,
      name: p.name,
      price: p.price,
      qty: round3((cur?.qty ?? 0) + qty),
      cost: p.cost,
      unit: p.unit,
    );
    notifyListeners();
  }

  /// A one-off article that is not in the product base (no barcode, odd price).
  void addFree({required String name, required double price, double qty = 1}) {
    final key = 'LIBRE-${DateTime.now().microsecondsSinceEpoch}';
    _lines[key] = SaleLine(barcode: key, name: name, price: price, qty: qty);
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
      remove(barcode);
      return;
    }
    _lines[barcode] = l.withQty(l.qty - 1);
    notifyListeners();
  }

  /// Sets the quantity (weight) of a line; zero or less removes it.
  void setQty(String barcode, double q) {
    final l = _lines[barcode];
    if (l == null) return;
    if (q <= 0) {
      remove(barcode);
      return;
    }
    _lines[barcode] = l.withQty(round3(q));
    notifyListeners();
  }

  void remove(String barcode) {
    _lines.remove(barcode);
    if (_lines.isEmpty) discount = null;
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

  /// Replaces the current cart by [lines] (e.g. a quote turned into a sale).
  void loadLines(List<SaleLine> newLines, Discount? d) {
    _lines
      ..clear()
      ..addEntries(newLines.map((l) => MapEntry(l.barcode, l)));
    discount = d;
    notifyListeners();
  }

  Future<void> deleteHeld(HeldCart h) async {
    await _db.deleteHeld(h.id);
    await refreshHeld();
  }
}
