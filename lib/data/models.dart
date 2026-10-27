class Product {
  final String barcode;
  final String name;
  final double price;

  /// Purchase price; 0 = unknown.
  final double cost;

  /// Units in stock; null = stock not tracked for this product.
  final int? stock;

  /// Alert threshold: low stock when stock <= minStock.
  final int minStock;

  const Product({
    required this.barcode,
    required this.name,
    required this.price,
    this.cost = 0,
    this.stock,
    this.minStock = 0,
  });

  bool get tracked => stock != null;
  bool get lowStock => stock != null && stock! <= minStock;
  bool get outOfStock => stock != null && stock! <= 0;

  Product withStock(int stock) => Product(
        barcode: barcode,
        name: name,
        price: price,
        cost: cost,
        stock: stock < 0 ? 0 : stock,
        minStock: minStock,
      );

  Map<String, Object?> toMap() => {
        'barcode': barcode,
        'name': name,
        'price': price,
        'cost': cost,
        'stock': stock,
        'min_stock': minStock,
      };

  factory Product.fromMap(Map<String, Object?> m) => Product(
        barcode: m['barcode'] as String,
        name: m['name'] as String,
        price: (m['price'] as num).toDouble(),
        cost: (m['cost'] as num?)?.toDouble() ?? 0,
        stock: m['stock'] as int?,
        minStock: (m['min_stock'] as int?) ?? 0,
      );
}

/// Totals shown at the top of the Stock tab.
class StockSummary {
  final int tracked;
  final int untracked;
  final int low;
  final int out;
  final int units;

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
      units: t.fold(0, (s, p) => s + p.stock!),
      costValue: t.fold(0.0, (s, p) => s + p.stock! * p.cost),
      saleValue: t.fold(0.0, (s, p) => s + p.stock! * p.price),
    );
  }
}

class SaleLine {
  final String barcode;
  final String name;
  final double price;
  final int qty;

  /// Purchase price at the time of sale; 0 = unknown.
  final double cost;

  const SaleLine({
    required this.barcode,
    required this.name,
    required this.price,
    required this.qty,
    this.cost = 0,
  });

  double get total => price * qty;

  /// Profit of this line, or null when the purchase price is unknown.
  double? get profit => cost > 0 ? (price - cost) * qty : null;

  SaleLine withQty(int q) =>
      SaleLine(barcode: barcode, name: name, price: price, qty: q, cost: cost);

  Map<String, Object?> toMap(int saleId) => {
        'sale_id': saleId,
        'barcode': barcode,
        'name': name,
        'price': price,
        'qty': qty,
        'cost': cost,
      };

  factory SaleLine.fromMap(Map<String, Object?> m) => SaleLine(
        barcode: m['barcode'] as String,
        name: m['name'] as String,
        price: (m['price'] as num).toDouble(),
        qty: m['qty'] as int,
        cost: (m['cost'] as num?)?.toDouble() ?? 0,
      );
}

enum PayMethod { cash, qr }

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
    final r = (raw * 1000).round() / 1000;
    return r.clamp(0, subtotal).toDouble();
  }
}

class Sale {
  final int? id;
  final DateTime date;

  /// Net total (after discount).
  final double total;
  final double discount;
  final PayMethod method;
  final double? received;
  final List<SaleLine> lines;

  /// Name of the user who made the sale (null when accounts are not enabled).
  final String? seller;

  const Sale({
    this.id,
    required this.date,
    required this.total,
    this.discount = 0,
    required this.method,
    this.received,
    required this.lines,
    this.seller,
  });

  int get itemCount => lines.fold(0, (s, l) => s + l.qty);
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
      );
}

/// Access rights, stored as a bitmask. The Caisse tab is open to every user.
abstract final class Perm {
  static const products = 1;
  static const stock = 2;
  static const history = 4;
  static const settings = 8;
  static const discount = 16;
  static const all = 31;

  static const labels = {
    products: 'Produits',
    stock: 'Stock',
    history: 'Historique et bénéfice',
    settings: 'Réglages',
    discount: 'Remises',
  };
}

enum Role {
  owner('Propriétaire', Perm.all),
  manager('Gérant', Perm.products | Perm.stock | Perm.history | Perm.discount),
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

  int get itemCount => lines.fold(0, (s, l) => s + l.qty);
  double get subtotal => lines.fold(0.0, (s, l) => s + l.total);
  double get total => subtotal - (discount?.amountFor(subtotal) ?? 0);
}
