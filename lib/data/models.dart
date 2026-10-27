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

  const Sale({
    this.id,
    required this.date,
    required this.total,
    this.discount = 0,
    required this.method,
    this.received,
    required this.lines,
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
