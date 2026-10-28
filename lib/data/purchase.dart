import 'dart:convert';

import 'models.dart';

/// One product received from a supplier, at its purchase price.
class PurchaseLine {
  final String barcode;
  final String name;

  /// Quantity received (kg for weighed items).
  final double qty;

  /// Purchase price per unit (per kg).
  final double cost;
  final String unit;

  const PurchaseLine({
    required this.barcode,
    required this.name,
    required this.qty,
    required this.cost,
    this.unit = '',
  });

  double get total => round3(qty * cost);

  Map<String, Object?> toJson() => {'b': barcode, 'n': name, 'q': qty, 'c': cost, 'u': unit};

  static PurchaseLine fromJson(Map<String, dynamic> j) => PurchaseLine(
        barcode: j['b'] as String,
        name: j['n'] as String,
        qty: (j['q'] as num).toDouble(),
        cost: (j['c'] as num).toDouble(),
        unit: (j['u'] as String?) ?? '',
      );
}

/// A goods receipt from a supplier. Saving it adds the quantities to the stock
/// and updates the purchase price of each product.
class Purchase {
  final int? id;
  final DateTime date;
  final String supplier;
  final String phone;

  /// Supplier's delivery note / invoice number (optional).
  final String invoice;
  final List<PurchaseLine> lines;

  /// Amount already paid to the supplier at reception.
  final double paid;
  final String note;

  const Purchase({
    this.id,
    required this.date,
    required this.supplier,
    this.phone = '',
    this.invoice = '',
    required this.lines,
    this.paid = 0,
    this.note = '',
  });

  double get total => round3(lines.fold(0.0, (s, l) => s + l.total));
  double get owed => round3((total - paid).clamp(0, double.infinity).toDouble());
  bool get settled => owed <= 0.0005;
  int get articles => lines.fold(0, (s, l) => s + (l.unit == 'kg' ? 1 : l.qty.round()));

  Map<String, Object?> toMap() => {
        'date': date.toIso8601String(),
        'supplier': supplier,
        'phone': phone,
        'invoice': invoice,
        'paid': paid,
        'note': note,
        'lines': jsonEncode(lines.map((l) => l.toJson()).toList()),
      };

  static Purchase fromMap(Map<String, Object?> m) => Purchase(
        id: m['id'] as int?,
        date: DateTime.parse(m['date'] as String),
        supplier: m['supplier'] as String,
        phone: (m['phone'] as String?) ?? '',
        invoice: (m['invoice'] as String?) ?? '',
        paid: (m['paid'] as num).toDouble(),
        note: (m['note'] as String?) ?? '',
        lines: (jsonDecode(m['lines'] as String) as List)
            .map((e) => PurchaseLine.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Money given to a supplier later, to settle what is owed.
class SupplierPayment {
  final int? id;
  final String supplier;
  final String phone;
  final double amount;
  final DateTime date;
  final String note;

  const SupplierPayment({
    this.id,
    required this.supplier,
    this.phone = '',
    required this.amount,
    required this.date,
    this.note = '',
  });

  Map<String, Object?> toMap() =>
      {'supplier': supplier, 'phone': phone, 'amount': amount, 'date': date.toIso8601String(), 'note': note};

  static SupplierPayment fromMap(Map<String, Object?> m) => SupplierPayment(
        id: m['id'] as int?,
        supplier: m['supplier'] as String,
        phone: (m['phone'] as String?) ?? '',
        amount: (m['amount'] as num).toDouble(),
        date: DateTime.parse(m['date'] as String),
        note: (m['note'] as String?) ?? '',
      );
}

/// What we owe one supplier, built from purchases and payments.
class SupplierAccount {
  SupplierAccount(this.name, this.phone, this.purchases, this.payments);
  final String name;
  final String phone;

  /// Newest first.
  final List<Purchase> purchases;
  final List<SupplierPayment> payments;

  double get purchased => round3(purchases.fold(0.0, (s, p) => s + p.total));
  double get paid => round3(purchases.fold(0.0, (s, p) => s + p.paid) + payments.fold(0.0, (s, p) => s + p.amount));
  double get balance => round3(purchased - paid);
  bool get owes => balance > 0.0005;

  DateTime get lastActivity {
    final d = <DateTime>[...purchases.map((p) => p.date), ...payments.map((p) => p.date)]..sort();
    return d.last;
  }

  static List<SupplierAccount> group(List<Purchase> purchases, List<SupplierPayment> payments) {
    final names = <String, String>{};
    final phones = <String, String>{};
    final ps = <String, List<Purchase>>{};
    final pay = <String, List<SupplierPayment>>{};
    void note(String name, String phone) {
      final k = name.trim().toLowerCase();
      names.putIfAbsent(k, () => name.trim());
      if (phone.isNotEmpty) phones.putIfAbsent(k, () => phone);
    }

    for (final p in purchases) {
      note(p.supplier, p.phone);
      ps.putIfAbsent(p.supplier.trim().toLowerCase(), () => []).add(p);
    }
    for (final p in payments) {
      note(p.supplier, p.phone);
      pay.putIfAbsent(p.supplier.trim().toLowerCase(), () => []).add(p);
    }
    return names.keys
        .map((k) => SupplierAccount(names[k]!, phones[k] ?? '', ps[k] ?? [], pay[k] ?? []))
        .toList()
      ..sort((a, b) {
        final c = b.balance.compareTo(a.balance);
        return c != 0 ? c : b.lastActivity.compareTo(a.lastActivity);
      });
  }
}
