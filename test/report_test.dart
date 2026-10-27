import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:mob_caisse/data/demo_data.dart';
import 'package:mob_caisse/data/models.dart';
import 'package:mob_caisse/data/pdf_report.dart';
import 'package:mob_caisse/data/report.dart';
import 'package:mob_caisse/data/settings_store.dart';

Sale _sale(DateTime d, double total, List<SaleLine> lines,
        {double discount = 0, PayMethod m = PayMethod.cash, SaleKind kind = SaleKind.sale, String? seller}) =>
    Sale(date: d, total: total, discount: discount, method: m, lines: lines, kind: kind, seller: seller);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('report: net, profit, refunds, discount, payments, top products, hours', () {
    final start = DateTime(2026, 10, 1);
    final end = DateTime(2026, 10, 4);
    final sales = [
      _sale(DateTime(2026, 10, 1, 9), 4, [const SaleLine(barcode: 'A', name: 'Eau', price: 2, qty: 2, cost: 1)], seller: 'Sami'),
      _sale(DateTime(2026, 10, 2, 14), 9, [const SaleLine(barcode: 'B', name: 'Jus', price: 5, qty: 2, cost: 3)],
          discount: 1, m: PayMethod.qr),
      _sale(DateTime(2026, 10, 2, 15), -2, [const SaleLine(barcode: 'A', name: 'Eau', price: 2, qty: -1, cost: 1)],
          kind: SaleKind.refund),
    ];
    final r = Report.from(sales, start, end);
    expect(r.days.length, 3);
    expect(r.net, 11); // 4 + 9 - 2
    expect(r.salesCount, 2);
    expect(r.refundsCount, 1);
    expect(r.refunds, 2);
    expect(r.gross, 14); // 4 + (9+1)
    expect(r.discounts, 1);
    expect(r.cash, 2); // 4 - 2
    expect(r.qr, 9);
    expect(r.avgBasket, 6.5);
    expect(r.days[1].revenue, 7);
    expect(r.byHour[14], 9);
    expect(r.peakHour, 14);
    // profit: 2*1 + (2*2 - 1) + (-1*1 - 0)  = 2 + 3 - 1 = 4
    expect(r.profit, 4);
    final eau = r.products.firstWhere((p) => p.name == 'Eau');
    expect(eau.qty, 1);
    expect(r.top().first.name, 'Jus');
    expect(r.bySeller['Sami'], 4);
    expect(r.growthVs(Report.from([], start, end)), isNull);
  });

  test('period ranges', () {
    final now = DateTime(2026, 10, 27, 15);
    expect(StatPeriod.today.range(now).$1, DateTime(2026, 10, 27));
    expect(StatPeriod.week.range(now).$1, DateTime(2026, 10, 21));
    expect(StatPeriod.thisMonth.range(now).$1, DateTime(2026, 10, 1));
    final lm = StatPeriod.lastMonth.range(now);
    expect(lm.$1, DateTime(2026, 9, 1));
    expect(lm.$2, DateTime(2026, 10, 1));
    expect(StatPeriod.lastMonth.range(DateTime(2026, 1, 5)).$1, DateTime(2025, 12, 1));
  });

  testWidgets('pdf export builds for a month of demo data', (tester) async {
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      final now = DateTime(2026, 10, 27);
      final start = DateTime(2026, 10, 1);
      final end = DateTime(2026, 10, 28);
      final sales = DemoData.sales(DemoData.products(), now, days: 120);
      final settings = const AppSettings(storeName: 'Épicerie Chez Sami');
      for (final (a, b, label) in [
        (start, end, 'Ce mois'),
        (DateTime(2026, 10, 27), DateTime(2026, 10, 28), 'Aujourd\'hui'),
        (DateTime(2026, 1, 1), DateTime(2026, 6, 1), 'Personnalisé'),
        (DateTime(2025, 1, 1), DateTime(2025, 1, 2), 'Vide'),
      ]) {
        final r = Report.from(sales.where((s) => !s.date.isBefore(a) && s.date.isBefore(b)).toList(), a, b);
        final bytes = await PdfReport.build(report: r, previous: Report.from([], a, b), settings: settings, periodLabel: label);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        if (label == 'Ce mois') {
          final f = File('build/sample_report.pdf');
          await f.parent.create(recursive: true);
          await f.writeAsBytes(bytes);
        }
      }
    });
  });
}
