/// Rounds to the millime (3 decimals), the finest unit of the dinar.
double round3(double v) => (v * 1000).round() / 1000;

/// Quantity as text: `3`, `0,350`; with a unit: `0,350 kg`.
String fmtQty(num q, {String unit = ''}) {
  final d = q.toDouble();
  var t = d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  t = t.replaceAll('.', ',');
  return unit.isEmpty ? t : '$t $unit';
}

class Product {
  final String barcode;
  final String name;

  /// Price per unit, or per kg when [byWeight].
  final double price;

  /// Purchase price; 0 = unknown.
  final double cost;

  /// Units (or kg) in stock; null = stock not tracked for this product.
  final double? stock;

  /// Alert threshold: low stock when stock <= minStock.
  final int minStock;

  /// `''` for a unit product, `'kg'` for a product sold by weight.
  final String unit;

  /// Shown in the quick-access row of the Caisse (bread, vegetables...).
  final bool favorite;

  const Product({
    required this.barcode,
    required this.name,
    required this.price,
    this.cost = 0,
    this.stock,
    this.minStock = 0,
    this.unit = '',
    this.favorite = false,
  });

  bool get byWeight => unit == 'kg';
  bool get tracked => stock != null;
  bool get lowStock => stock != null && stock! <= minStock;
  bool get outOfStock => stock != null && stock! <= 0;

  Product withStock(double stock) => Product(
        barcode: barcode,
        name: name,
        price: price,
        cost: cost,
        stock: stock < 0 ? 0 : stock,
        minStock: minStock,
        unit: unit,
        favorite: favorite,
      );

  Map<String, Object?> toMap() => {
        'barcode': barcode,
        'name': name,
        'price': price,
        'cost': cost,
        'stock': stock,
        'min_stock': minStock,
        'unit': unit,
        'favorite': favorite ? 1 : 0,
      };

  factory Product.fromMap(Map<String, Object?> m) => Product(
        barcode: m['barcode'] as String,
        name: m['name'] as String,
        price: (m['price'] as num).toDouble(),
        cost: (m['cost'] as num?)?.toDouble() ?? 0,
        stock: (m['stock'] as num?)?.toDouble(),
        minStock: (m['min_stock'] as num?)?.toInt() ?? 0,
        unit: (m['unit'] as String?) ?? '',
        favorite: ((m['favorite'] as num?) ?? 0) != 0,
      );
}

/// Totals shown at the top of the Stock tab.
class StockSummary {
  final int tracked;
  final int untracked;
  final int low;
  final int out;
  final double units;

  /// Stock valued at purchase price (products without one are left out) and at sale price.
  final double costValue;
  final double saleValue;

  const StockSummary({
    required this.tracked,
    required this.untracked,
    required this.low,
    required this.out,
    required this.units,
    required this.costValue,
    required this.saleValue,
  });

  factory StockSummary.from(List<Product> all) {
    final t = all.where((p) => p.tracked).toList();
    return StockSummary(
      tracked: t.length,
      untracked: all.length - t.length,
      low: t.where((p) => p.lowStock && !p.outOfStock).length,
      out: t.where((p) => p.outOfStock).length,
      units: t.fold(0.0, (s, p) => s + p.stock!),
      costValue: t.fold(0.0, (s, p) => s + p.stock! * p.cost),
      saleValue: t.fold(0.0, (s, p) => s + p.stock! * p.price),
    );
  }
}

class SaleLine {
  final String barcode;
  final String name;
  final double price;

  /// Quantity sold (kg for weighed items). Negative on a return.
  final double qty;

  /// Purchase price at the time of sale; 0 = unknown.
  final double cost;

  /// `''` or `'kg'`.
  final String unit;

  const SaleLine({
    required this.barcode,
    required this.name,
    required this.price,
    required this.qty,
    this.cost = 0,
    this.unit = '',
  });

  bool get byWeight => unit == 'kg';
  double get total => round3(price * qty);

  /// Number of articles this line counts for: its quantity, or 1 for a weighed item.
  int get articles => byWeight ? 1 : qty.abs().round();

  /// Profit of this line, or null when the purchase price is unknown.
  double? get profit => cost > 0 ? round3((price - cost) * qty) : null;

  SaleLine withQty(double q) =>
      SaleLine(barcode: barcode, name: name, price: price, qty: q, cost: cost, unit: unit);

  Map<String, Object?> toMap(int saleId) => {
        'sale_id': saleId,
        'barcode': barcode,
        'name': name,
        'price': price,
        'qty': qty,
        'cost': cost,
        'unit': unit,
      };

  factory SaleLine.fromMap(Map<String, Object?> m) => SaleLine(
        barcode: m['barcode'] as String,
        name: m['name'] as String,
        price: (m['price'] as num).toDouble(),
        qty: (m['qty'] as num).toDouble(),
        cost: (m['cost'] as num?)?.toDouble() ?? 0,
        unit: (m['unit'] as String?) ?? '',
      );
}

enum PayMethod { cash, qr, credit }

String payMethodLabel(PayMethod m) => switch (m) { PayMethod.cash => 'Espèces', PayMethod.qr => 'QR code', PayMethod.credit => 'Crédit' };

enum SaleKind { sale, refund }

enum DiscountType { amount, percent }

/// Order-level discount: a fixed amount or a percentage of the subtotal.
class Discount {
  final DiscountType type;
  final double value;
  const Discount(this.type, this.value);

  /// Discount in currency units for [subtotal], rounded to the millime
  /// and never above the subtotal.
  double amountFor(double subtotal) {
    final raw = type == DiscountType.percent ? subtotal * value / 100 : value;
    return round3(raw).clamp(0, subtotal).toDouble();
  }
}

class Sale {
  final int? id;
  final DateTime date;

  /// Net total (after discount). Negative for a return.
  final double total;
  final double discount;
  final PayMethod method;
  final double? received;
  final List<SaleLine> lines;

  /// Name of the user who made the sale (null when accounts are not enabled).
  final String? seller;

  /// `refund` for a return / cancellation: negative amounts and quantities.
  final SaleKind kind;

  /// The sale a return refers to.
  final int? refSaleId;
  final String? reason;

  /// Return only, not stored: put the returned items back in stock.
  final bool restock;

  const Sale({
    this.id,
    required this.date,
    required this.total,
    this.discount = 0,
    required this.method,
    this.received,
    required this.lines,
    this.seller,
    this.kind = SaleKind.sale,
    this.refSaleId,
    this.reason,
    this.restock = true,
  });

  bool get isRefund => kind == SaleKind.refund;
  int get itemCount => lines.fold(0, (s, l) => s + l.articles);
  double get subtotal => total + discount;

  /// Profit over the lines whose purchase price is known, minus the discount.
  double get profit {
    final known = lines.where((l) => l.profit != null);
    if (known.isEmpty) return 0;
    return known.fold(0.0, (s, l) => s + l.profit!) - discount;
  }

  bool get hasUnknownCost => lines.any((l) => l.cost <= 0);

  Sale withId(int id) => Sale(
        id: id,
        date: date,
        total: total,
        discount: discount,
        method: method,
        received: received,
        lines: lines,
        seller: seller,
        kind: kind,
        refSaleId: refSaleId,
        reason: reason,
        restock: restock,
      );

  /// What can still be returned from [original]: ordered quantity minus
  /// what [returned] (barcode -> positive quantity) already gave back.
  static Map<String, double> returnable(Sale original, Map<String, double> returned) => {
        for (final l in original.lines)
          l.barcode: ((l.qty - (returned[l.barcode] ?? 0)) * 1000).round() / 1000,
      };

  /// Builds the return of [qty] (barcode -> positive quantity) from [original].
  /// The refund is pro-rated on the order discount, so a customer gets back
  /// what they actually paid for those items.
  static Sale refundOf(
    Sale original,
    Map<String, double> qty, {
    required DateTime date,
    String? seller,
    String? reason,
    bool restock = true,
  }) {
    final lines = <SaleLine>[
      for (final l in original.lines)
        if ((qty[l.barcode] ?? 0) > 0) l.withQty(-(qty[l.barcode]!)),
    ];
    final gross = round3(lines.fold(0.0, (s, l) => s + l.total.abs()));
    final ratio = original.subtotal > 0 ? original.total / original.subtotal : 1.0;
    final net = round3(gross * ratio);
    return Sale(
      date: date,
      total: -net,
      discount: -round3(gross - net),
      method: original.method,
      lines: lines,
      seller: seller,
      kind: SaleKind.refund,
      refSaleId: original.id,
      reason: reason,
      restock: restock,
    );
  }
}

/// Totals of a set of sales and returns (for a cash closing).
class ClosingSummary {
  final int salesCount;
  final int refundsCount;

  /// Sales before discount.
  final double gross;
  final double discounts;

  /// Amount given back on returns (positive).
  final double refunds;

  /// Sales minus returns.
  final double net;

  /// Net amounts by payment method.
  final double cash;
  final double qr;
  final double profit;
  final Map<String, double> bySeller;

  const ClosingSummary({
    required this.salesCount,
    required this.refundsCount,
    required this.gross,
    required this.discounts,
    required this.refunds,
    required this.net,
    required this.cash,
    required this.qr,
    required this.profit,
    required this.bySeller,
  });

  factory ClosingSummary.from(List<Sale> all) {
    final sales = all.where((s) => !s.isRefund).toList();
    final refunds = all.where((s) => s.isRefund).toList();
    double sum(Iterable<Sale> l, double Function(Sale) f) => round3(l.fold(0.0, (a, s) => a + f(s)));
    final bySeller = <String, double>{};
    for (final s in all) {
      if (s.seller != null) bySeller.update(s.seller!, (v) => round3(v + s.total), ifAbsent: () => s.total);
    }
    return ClosingSummary(
      salesCount: sales.length,
      refundsCount: refunds.length,
      gross: sum(sales, (s) => s.subtotal),
      discounts: sum(sales, (s) => s.discount),
      refunds: -sum(refunds, (s) => s.total),
      net: sum(all, (s) => s.total),
      cash: sum(all.where((s) => s.method == PayMethod.cash), (s) => s.total),
      qr: sum(all.where((s) => s.method == PayMethod.qr), (s) => s.total),
      profit: sum(all, (s) => s.profit),
      bySeller: bySeller,
    );
  }
}

/// A saved cash closing (Z report).
class CashClosing {
  final int? id;
  final DateTime closedAt;
  final DateTime periodStart;
  final String? user;
  final double openingFloat;
  final double expectedCash;
  final double countedCash;

  /// Cash left in the till for the next day.
  final double floatLeft;
  final int salesCount;
  final int refundsCount;
  final double gross;
  final double discounts;
  final double refunds;
  final double net;
  final double cash;
  final double qr;
  final double profit;
  final String? note;

  const CashClosing({
    this.id,
    required this.closedAt,
    required this.periodStart,
    this.user,
    required this.openingFloat,
    required this.expectedCash,
    required this.countedCash,
    required this.floatLeft,
    required this.salesCount,
    required this.refundsCount,
    required this.gross,
    required this.discounts,
    required this.refunds,
    required this.net,
    required this.cash,
    required this.qr,
    required this.profit,
    this.note,
  });

  /// Counted minus expected: negative = cash missing.
  double get difference => round3(countedCash - expectedCash);

  Map<String, Object?> toMap() => {
        'closed_at': closedAt.toIso8601String(),
        'period_start': periodStart.toIso8601String(),
        'user_name': user,
        'opening_float': openingFloat,
        'expected_cash': expectedCash,
        'counted_cash': countedCash,
        'float_left': floatLeft,
        'sales_count': salesCount,
        'refunds_count': refundsCount,
        'gross': gross,
        'discounts': discounts,
        'refunds': refunds,
        'net': net,
        'cash': cash,
        'qr': qr,
        'profit': profit,
        'note': note,
      };

  factory CashClosing.fromMap(Map<String, Object?> m) {
    double d(String k) => (m[k] as num).toDouble();
    return CashClosing(
      id: m['id'] as int,
      closedAt: DateTime.parse(m['closed_at'] as String),
      periodStart: DateTime.parse(m['period_start'] as String),
      user: m['user_name'] as String?,
      openingFloat: d('opening_float'),
      expectedCash: d('expected_cash'),
      countedCash: d('counted_cash'),
      floatLeft: d('float_left'),
      salesCount: (m['sales_count'] as num).toInt(),
      refundsCount: (m['refunds_count'] as num).toInt(),
      gross: d('gross'),
      discounts: d('discounts'),
      refunds: d('refunds'),
      net: d('net'),
      cash: d('cash'),
      qr: d('qr'),
      profit: d('profit'),
      note: m['note'] as String?,
    );
  }
}

/// Access rights, stored as a bitmask. The Caisse tab is open to every user.
abstract final class Perm {
  static const products = 1;
  static const stock = 2;
  static const history = 4;
  static const settings = 8;
  static const discount = 16;
  static const refund = 32;
  static const closing = 64;
  static const all = 127;

  static const labels = {
    products: 'Produits',
    stock: 'Stock',
    history: 'Historique et bénéfice',
    settings: 'Réglages',
    discount: 'Remises',
    refund: 'Retours et annulations',
    closing: 'Clôture de caisse',
  };
}

enum Role {
  owner('Propriétaire', Perm.all),
  manager('Gérant', Perm.products | Perm.stock | Perm.history | Perm.discount | Perm.refund | Perm.closing),
  cashier('Caissier', 0);

  const Role(this.label, this.defaultPerms);
  final String label;
  final int defaultPerms;
}

/// A person who can sign in. Owners can do everything, including managing users.
class AppUser {
  final int? id;
  final String name;
  final String pinHash;
  final Role role;
  final int perms;

  const AppUser({this.id, required this.name, required this.pinHash, required this.role, required this.perms});

  bool get isOwner => role == Role.owner;
  bool can(int perm) => isOwner || (perms & perm) != 0;

  AppUser copyWith({String? name, String? pinHash, Role? role, int? perms}) => AppUser(
        id: id,
        name: name ?? this.name,
        pinHash: pinHash ?? this.pinHash,
        role: role ?? this.role,
        perms: perms ?? this.perms,
      );

  Map<String, Object?> toMap() => {'name': name, 'pin_hash': pinHash, 'role': role.name, 'perms': perms};

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
        id: m['id'] as int,
        name: m['name'] as String,
        pinHash: m['pin_hash'] as String,
        role: Role.values.byName(m['role'] as String),
        perms: m['perms'] as int,
      );
}

/// A cart put on hold, to be resumed later.
class HeldCart {
  final int id;
  final DateTime date;
  final List<SaleLine> lines;
  final Discount? discount;

  const HeldCart({required this.id, required this.date, required this.lines, this.discount});

  int get itemCount => lines.fold(0, (s, l) => s + l.articles);
  double get subtotal => round3(lines.fold(0.0, (s, l) => s + l.total));
  double get total => subtotal - (discount?.amountFor(subtotal) ?? 0);
}
