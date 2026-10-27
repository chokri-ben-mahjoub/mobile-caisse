import 'dart:math';

import 'models.dart';

/// Mock products and sales for demonstrating the app to a prospective customer.
class DemoData {
  DemoData._();

  // name, price, cost, stock (null = not tracked), alert threshold
  static const _catalog = <(String, double, double, int?, int)>[
    ('Eau minérale 1,5 L', 0.800, 0.550, 120, 24),
    ('Lait demi-écrémé 1 L', 1.450, 1.250, 60, 12),
    ('Café Délice 250 g', 4.500, 3.600, 40, 8),
    ('Biscuits chocolat', 2.250, 1.700, 35, 10),
    ("Huile d'olive 1 L", 18.900, 16.500, 4, 6),
    ('Pain de mie', 2.100, 1.600, 18, 5),
    ('Sucre 1 kg', 1.350, 1.100, 50, 10),
    ('Farine 1 kg', 1.200, 0.950, 45, 10),
    ('Spaghetti 500 g', 1.150, 0.900, 70, 15),
    ('Couscous moyen 1 kg', 2.400, 1.950, 38, 8),
    ('Riz 1 kg', 3.200, 2.700, 30, 8),
    ('Tomate concentrée 400 g', 2.800, 2.200, 26, 6),
    ("Thon à l'huile 160 g", 5.200, 4.300, 33, 8),
    ('Harissa 380 g', 2.950, 2.300, 22, 6),
    ('Yaourt nature x4', 2.600, 2.100, 0, 4),
    ('Fromage fondu 8 portions', 3.300, 2.700, 20, 5),
    ("Jus d'orange 1 L", 3.200, 2.600, 28, 6),
    ('Boisson gazeuse 1 L', 2.000, 1.600, 54, 12),
    ('Thé vert 100 g', 3.800, 3.000, 24, 5),
    ('Œufs plateau de 6', 2.700, 2.300, 16, 4),
    ('Savon 125 g', 1.500, 1.000, 40, 10),
    ('Liquide vaisselle 750 ml', 4.900, 3.900, 14, 4),
    ('Papier toilette x4', 5.600, 4.600, 9, 10),
    ('Chips 100 g', 1.900, 1.400, 36, 8),
    ('Chocolat tablette 100 g', 3.500, 2.800, 25, 6),
    ('Dattes Deglet Nour 500 g', 9.500, 7.800, 12, 4),
  ];

  /// Valid EAN-13 for demo product [i]: 6199 + 8-digit index + check digit.
  static String barcode(int i) {
    final base = '6199${(i + 1).toString().padLeft(8, '0')}';
    var sum = 0;
    for (var k = 0; k < 12; k++) {
      sum += (base.codeUnitAt(k) - 48) * (k.isEven ? 1 : 3);
    }
    return '$base${(10 - sum % 10) % 10}';
  }

  static List<Product> products() => [
        for (var i = 0; i < _catalog.length; i++)
          Product(
            barcode: barcode(i),
            name: _catalog[i].$1,
            price: _catalog[i].$2,
            cost: _catalog[i].$3,
            stock: _catalog[i].$4,
            minStock: _catalog[i].$5,
          ),
      ];

  /// About [days] days of plausible sales ending [now] (today included).
  /// Deterministic for a given [seed].
  static List<Sale> sales(List<Product> products, DateTime now, {int days = 14, int seed = 7}) {
    final rnd = Random(seed);
    final out = <Sale>[];
    for (var d = days - 1; d >= 0; d--) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: d));
      final isToday = d == 0;
      final weekend = day.weekday == DateTime.friday || day.weekday == DateTime.saturday;
      final count = isToday ? 6 + rnd.nextInt(3) : (weekend ? 10 : 7) + rnd.nextInt(5);

      // Opening hours 08:00-20:00; today only up to a few minutes ago.
      final startMin = 8 * 60;
      var endMin = 20 * 60;
      if (isToday) endMin = max(startMin + 30, (now.hour * 60 + now.minute) - 2);
      final minutes = List.generate(count, (_) => startMin + rnd.nextInt(max(1, endMin - startMin)))..sort();

      for (final m in minutes) {
        final n = 1 + rnd.nextInt(5);
        final picked = <Product>{};
        while (picked.length < n) {
          picked.add(products[rnd.nextInt(products.length)]);
        }
        final lines = [
          for (final p in picked)
            SaleLine(
              barcode: p.barcode,
              name: p.name,
              price: p.price,
              qty: 1 + (rnd.nextInt(4) == 0 ? rnd.nextInt(3) : 0),
              cost: p.cost,
            ),
        ];
        final subtotal = lines.fold(0.0, (s, l) => s + l.total);
        final discount = rnd.nextInt(10) == 0 ? (subtotal * 0.1 * 1000).round() / 1000 : 0.0;
        final total = subtotal - discount;
        final cash = rnd.nextInt(100) < 70;
        out.add(Sale(
          date: day.add(Duration(minutes: min(m, 23 * 60 + 59))),
          total: total,
          discount: discount,
          method: cash ? PayMethod.cash : PayMethod.qr,
          received: cash ? (total / 5).ceil() * 5.0 : null,
          lines: lines,
        ));
      }
    }
    return out;
  }
}
