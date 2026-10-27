import 'models.dart';

enum StatPeriod {
  today('Aujourd\'hui'),
  week('7 jours'),
  month30('30 jours'),
  thisMonth('Ce mois'),
  lastMonth('Mois dernier'),
  custom('Personnalisé');

  final String label;
  const StatPeriod(this.label);

  /// `[start, end)` in local time, [custom] being supplied by the caller.
  (DateTime, DateTime) range(DateTime now, {(DateTime, DateTime)? custom}) {
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case StatPeriod.today:
        return (today, today.add(const Duration(days: 1)));
      case StatPeriod.week:
        return (today.subtract(const Duration(days: 6)), today.add(const Duration(days: 1)));
      case StatPeriod.month30:
        return (today.subtract(const Duration(days: 29)), today.add(const Duration(days: 1)));
      case StatPeriod.thisMonth:
        return (DateTime(now.year, now.month, 1), today.add(const Duration(days: 1)));
      case StatPeriod.lastMonth:
        return (DateTime(now.year, now.month - 1, 1), DateTime(now.year, now.month, 1));
      case StatPeriod.custom:
        return custom ?? (today, today.add(const Duration(days: 1)));
    }
  }
}

class ProductStat {
  final String name;
  final String unit;
  double qty = 0;
  double revenue = 0;
  double profit = 0;
  ProductStat(this.name, this.unit);
}

class DayStat {
  final DateTime day;
  double revenue = 0;
  double profit = 0;
  int count = 0;
  DayStat(this.day);
}

/// Activity figures over a period: sales minus returns, profit, best sellers,
/// per-day and per-hour curves. Pure computation, no database access.
class Report {
  final DateTime start;

  /// Exclusive.
  final DateTime end;

  /// Net revenue (sales minus returns, after discounts).
  final double net;

  /// Value of the sales before discounts.
  final double gross;
  final double discounts;

  /// Amount refunded to customers (positive).
  final double refunds;
  final double profit;
  final int salesCount;
  final int refundsCount;
  final double cash;
  final double qr;
  final int itemsSold;
  final bool hasUnknownCost;
  final List<DayStat> days;

  /// Net revenue per hour of the day (24 values).
  final List<double> byHour;
  final List<ProductStat> products;
  final Map<String, double> bySeller;

  /// Sum of the sale tickets (returns excluded), after discounts.
  final double salesTotal;

  const Report._({
    required this.start,
    required this.end,
    required this.net,
    required this.gross,
    required this.discounts,
    required this.refunds,
    required this.profit,
    required this.salesCount,
    required this.refundsCount,
    required this.cash,
    required this.qr,
    required this.itemsSold,
    required this.hasUnknownCost,
    required this.days,
    required this.byHour,
    required this.products,
    required this.bySeller,
    required this.salesTotal,
  });

  double get avgBasket => salesCount == 0 ? 0 : round3(salesTotal / salesCount);
  double get margin => net <= 0 ? 0 : profit / net * 100;
  bool get isEmpty => salesCount == 0 && refundsCount == 0;

  /// Best sellers by revenue.
  List<ProductStat> top([int n = 10]) => products.take(n).toList();

  /// Index of the busiest hour, or null without sales.
  int? get peakHour {
    var best = -1;
    var v = 0.0;
    for (var h = 0; h < 24; h++) {
      if (byHour[h] > v) {
        v = byHour[h];
        best = h;
      }
    }
    return best < 0 ? null : best;
  }

  /// Growth of [net] against [previous], in percent (null when no base).
  double? growthVs(Report previous) => previous.net <= 0 ? null : (net - previous.net) / previous.net * 100;

  factory Report.from(List<Sale> sales, DateTime start, DateTime end) {
    var net = 0.0, gross = 0.0, disc = 0.0, refunds = 0.0, profit = 0.0, cash = 0.0, qr = 0.0, salesTotal = 0.0;
    var nSales = 0, nRef = 0, items = 0;
    var unknown = false;
    final byDay = <DateTime, DayStat>{};
    var d = DateTime(start.year, start.month, start.day);
    while (d.isBefore(end)) {
      byDay[d] = DayStat(d);
      d = DateTime(d.year, d.month, d.day + 1);
    }
    final hours = List<double>.filled(24, 0);
    final prods = <String, ProductStat>{};
    final sellers = <String, double>{};

    for (final s in sales) {
      net += s.total;
      profit += s.profit;
      if (s.method == PayMethod.cash) {
        cash += s.total;
      } else {
        qr += s.total;
      }
      final ds = byDay[DateTime(s.date.year, s.date.month, s.date.day)];
      ds?.revenue += s.total;
      ds?.profit += s.profit;
      hours[s.date.hour] += s.total;
      if (s.seller != null) sellers.update(s.seller!, (v) => v + s.total, ifAbsent: () => s.total);
      if (s.isRefund) {
        nRef++;
        refunds -= s.total;
      } else {
        nSales++;
        gross += s.total + s.discount;
        disc += s.discount;
        salesTotal += s.total;
        ds?.count++;
        items += s.itemCount;
        if (s.hasUnknownCost) unknown = true;
      }
      for (final l in s.lines) {
        final p = prods.putIfAbsent(l.barcode, () => ProductStat(l.name, l.unit));
        p.qty += l.qty;
        p.revenue += l.total;
        p.profit += l.profit ?? 0;
      }
    }
    final list = prods.values.where((p) => p.qty > 0).toList()..sort((a, b) => b.revenue.compareTo(a.revenue));
    return Report._(
      start: start,
      end: end,
      net: round3(net),
      gross: round3(gross),
      discounts: round3(disc),
      refunds: round3(refunds),
      profit: round3(profit),
      salesCount: nSales,
      refundsCount: nRef,
      cash: round3(cash),
      qr: round3(qr),
      itemsSold: items,
      hasUnknownCost: unknown,
      days: byDay.values.toList(),
      byHour: hours.map(round3).toList(),
      products: list,
      bySeller: {for (final e in sellers.entries) e.key: round3(e.value)},
      salesTotal: round3(salesTotal),
    );
  }

}
