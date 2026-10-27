import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mob_caisse/ui/theme.dart';
import 'package:mob_caisse/ui/widgets.dart';
import 'package:mob_caisse/data/backup_service.dart';
import 'package:mob_caisse/data/barcode_utils.dart';
import 'package:mob_caisse/data/demo_data.dart';
import 'package:mob_caisse/data/models.dart';
import 'package:mob_caisse/data/settings_store.dart';
import 'package:mob_caisse/logic/auth_provider.dart';
import 'package:mob_caisse/ui/pin_lock.dart';

void main() {
  test('quantities: whole numbers, decimals and units format like a till', () {
    expect(fmtQty(3), '3');
    expect(fmtQty(0.35), '0,35');
    expect(fmtQty(1.5), '1,5');
    expect(fmtQty(2.0), '2');
    expect(fmtQty(0.35, unit: 'kg'), '0,35 kg');
    expect(fmtQty(1.250), '1,25');
  });

  test('weighed line: price per kg times weight, rounded to the millime', () {
    const l = SaleLine(barcode: 'T', name: 'Tomates', price: 1.8, qty: 0.35, unit: 'kg');
    expect(l.total, 0.63);
    expect(l.byWeight, true);
    expect(l.articles, 1); // a weighed item counts once
    expect(const SaleLine(barcode: 'F', name: 'Fromage', price: 22, qty: 0.125, unit: 'kg').total, 2.75);
    expect(const SaleLine(barcode: 'E', name: 'Eau', price: 0.8, qty: 3).articles, 3);
    final back = SaleLine.fromMap({...l.toMap(1), 'qty': 0.35});
    expect(back.unit, 'kg');
    expect(back.qty, 0.35);
  });

  group('returns', () {
    // 2 x 5.000 + 1 x 10.000 = 20.000, 10 % off -> paid 18.000
    final original = Sale(
      id: 42,
      date: DateTime(2026, 10, 27, 10),
      total: 18,
      discount: 2,
      method: PayMethod.cash,
      lines: const [
        SaleLine(barcode: 'A', name: 'A', price: 5, qty: 2, cost: 3),
        SaleLine(barcode: 'B', name: 'B', price: 10, qty: 1, cost: 6),
      ],
    );

    test('partial return is refunded pro-rata of the discount', () {
      final r = Sale.refundOf(original, {'A': 1}, date: DateTime(2026, 10, 27, 11), seller: 'Ali', reason: 'Erreur');
      expect(r.isRefund, true);
      expect(r.refSaleId, 42);
      expect(r.lines.single.qty, -1);
      expect(r.total, -4.5); // 5.000 x 0.9
      expect(r.discount, -0.5);
      expect(r.subtotal, -5);
      expect(r.method, PayMethod.cash);
      expect(r.profit, closeTo(-(5 - 3) + 0.5, 0.0001)); // gives back the margin, less the discount share
    });

    test('returning everything cancels the sale exactly', () {
      final r = Sale.refundOf(original, {'A': 2, 'B': 1}, date: DateTime(2026, 10, 27, 11));
      expect(r.total, -18);
      expect(r.discount, -2);
      expect(r.profit, closeTo(-original.profit, 0.0001));
    });

    test('what is already returned cannot be returned twice', () {
      expect(Sale.returnable(original, {'A': 1}), {'A': 1, 'B': 1});
      expect(Sale.returnable(original, {'A': 2, 'B': 1}), {'A': 0, 'B': 0});
    });

    test('weighed items can be returned by weight', () {
      final kg = Sale(
        id: 7,
        date: DateTime(2026),
        total: 3.6,
        method: PayMethod.qr,
        lines: const [SaleLine(barcode: 'T', name: 'Tomates', price: 1.8, qty: 2, unit: 'kg')],
      );
      final r = Sale.refundOf(kg, {'T': 0.5}, date: DateTime(2026));
      expect(r.lines.single.qty, -0.5);
      expect(r.total, -0.9);
      expect(Sale.returnable(kg, {'T': 0.5})['T'], 1.5);
    });
  });

  group('cash closing', () {
    final sales = [
      Sale(date: DateTime(2026, 10, 27, 9), total: 20, method: PayMethod.cash, seller: 'Ali', lines: const [
        SaleLine(barcode: 'A', name: 'A', price: 10, qty: 2, cost: 6),
      ]),
      Sale(date: DateTime(2026, 10, 27, 10), total: 9, discount: 1, method: PayMethod.qr, seller: 'Sana', lines: const [
        SaleLine(barcode: 'B', name: 'B', price: 10, qty: 1, cost: 6),
      ]),
      Sale(
        date: DateTime(2026, 10, 27, 11),
        total: -10,
        method: PayMethod.cash,
        seller: 'Ali',
        kind: SaleKind.refund,
        lines: const [SaleLine(barcode: 'A', name: 'A', price: 10, qty: -1, cost: 6)],
      ),
    ];

    test('summary nets returns out of sales, by payment method', () {
      final s = ClosingSummary.from(sales);
      expect(s.salesCount, 2);
      expect(s.refundsCount, 1);
      expect(s.gross, 30); // before discount
      expect(s.discounts, 1);
      expect(s.refunds, 10);
      expect(s.net, 19);
      expect(s.cash, 10); // 20 - 10
      expect(s.qr, 9);
      expect(s.bySeller, {'Ali': 10, 'Sana': 9});
      // sale 1: (10-6)*2 = 8; sale 2: (10-6) - 1 discount = 3; return: (10-6)*-1 = -4
      expect(s.profit, closeTo(7, 0.0001));
    });

    test('difference is counted minus expected', () {
      CashClosing c(double counted) => CashClosing(
            closedAt: DateTime(2026, 10, 27, 20),
            periodStart: DateTime(2026, 10, 27),
            openingFloat: 50,
            expectedCash: 60,
            countedCash: counted,
            floatLeft: 50,
            salesCount: 2,
            refundsCount: 1,
            gross: 30,
            discounts: 1,
            refunds: 10,
            net: 19,
            cash: 10,
            qr: 9,
            profit: 6,
          );
      expect(c(58.5).difference, -1.5); // missing
      expect(c(61).difference, 1); // too much
      expect(c(60).difference, 0);
      final back = CashClosing.fromMap({...c(58.5).toMap(), 'id': 5});
      expect(back.id, 5);
      expect(back.difference, -1.5);
      expect(back.periodStart, DateTime(2026, 10, 27));
    });
  });

  test('managers can return and close the till, cashiers cannot', () {
    expect(Role.manager.defaultPerms & Perm.refund, isNonZero);
    expect(Role.manager.defaultPerms & Perm.closing, isNonZero);
    expect(Role.cashier.defaultPerms & (Perm.refund | Perm.closing), 0);
    expect(Perm.all, 127);
    expect(Perm.labels.keys.fold(0, (a, b) => a | b), Perm.all);
  });

  test('CSV import: unit column marks weighed products', () {
    const csv = 'Code-barres;Nom;Prix;Unité\n111;Tomates;1,8;kg\n222;Eau;0,8;\n';
    final r = BackupService.parseProducts(csv);
    expect(r.hasUnit, true);
    expect(r.items.firstWhere((p) => p.barcode == '111').byWeight, true);
    expect(r.items.firstWhere((p) => p.barcode == '222').byWeight, false);
    expect(BackupService.parseProducts('1;A;2\n').hasUnit, false);
  });

  test('demo data has weighed products, a favourite and a bread without stock tracking', () {
    final p = DemoData.products();
    expect(p.where((x) => x.byWeight).length, greaterThanOrEqualTo(4));
    expect(p.where((x) => x.favorite).length, greaterThanOrEqualTo(5));
    final bread = p.firstWhere((x) => x.name == 'Baguette');
    expect(bread.tracked, false);
    final sales = DemoData.sales(p, DateTime(2026, 10, 27, 15));
    expect(sales.any((s) => s.lines.any((l) => l.byWeight && l.qty != l.qty.roundToDouble())), true);
  });

  test('roles and access: owner everything, manager preset, cashier only the Caisse', () {
    const hash = 'x';
    final owner = AppUser(name: 'O', pinHash: hash, role: Role.owner, perms: 0);
    final manager = AppUser(name: 'M', pinHash: hash, role: Role.manager, perms: Role.manager.defaultPerms);
    final cashier = AppUser(name: 'C', pinHash: hash, role: Role.cashier, perms: Role.cashier.defaultPerms);
    for (final p in Perm.labels.keys) {
      expect(owner.can(p), true); // owner ignores the stored mask
    }
    expect(manager.can(Perm.products) && manager.can(Perm.stock) && manager.can(Perm.history), true);
    expect(manager.can(Perm.discount), true);
    expect(manager.can(Perm.settings), false);
    expect(cashier.can(Perm.products) || cashier.can(Perm.history) || cashier.can(Perm.discount), false);
    // custom access on a cashier: discounts only
    expect(cashier.copyWith(perms: Perm.discount).can(Perm.discount), true);
    expect(cashier.copyWith(perms: Perm.discount).can(Perm.settings), false);
    // map round trip
    final back = AppUser.fromMap({...manager.toMap(), 'id': 3});
    expect(back.role, Role.manager);
    expect(back.perms, manager.perms);
    expect(back.id, 3);
  });

  test('pin hash is stable, differs per PIN, and never contains the PIN', () {
    expect(AuthProvider.hashPin('1234'), AuthProvider.hashPin('1234'));
    expect(AuthProvider.hashPin('1234') == AuthProvider.hashPin('1235'), false);
    expect(AuthProvider.hashPin('1234').contains('1234'), false);
  });

  testWidgets('PIN pad accepts a 4-digit code and resets on a wrong one', (tester) async {
    final tried = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Center(
          child: PinPad(onComplete: (pin) {
            tried.add(pin);
            return pin == '4321';
          }),
        ),
      ),
    ));
    for (final d in ['1', '2', '3', '4']) {
      await tester.tap(find.text(d));
    }
    await tester.pump();
    expect(tried, ['1234']); // wrong -> pad reset
    for (final d in ['4', '3', '2', '1']) {
      await tester.tap(find.text(d));
    }
    await tester.pump();
    expect(tried, ['1234', '4321']);
  });

  test('stock summary: counts, units and values; withStock never goes negative', () {
    final all = [
      const Product(barcode: '1', name: 'A', price: 5, cost: 3, stock: 10, minStock: 2), // ok
      const Product(barcode: '2', name: 'B', price: 4, cost: 2, stock: 2, minStock: 2), // low
      const Product(barcode: '3', name: 'C', price: 6, stock: 0, minStock: 1), // out (no cost)
      const Product(barcode: '4', name: 'D', price: 9), // not tracked
    ];
    final s = StockSummary.from(all);
    expect(s.tracked, 3);
    expect(s.untracked, 1);
    expect(s.low, 1); // out of stock is counted apart
    expect(s.out, 1);
    expect(s.units, 12);
    expect(s.costValue, 10 * 3 + 2 * 2);
    expect(s.saleValue, 10 * 5 + 2 * 4);
    expect(all[0].withStock(-5).stock, 0);
    expect(all[3].withStock(7).tracked, true);
  });

  test('demo data: valid unique EAN-13 codes, coherent sales, nothing in the future', () {
    final products = DemoData.products();
    final codes = products.map((p) => p.barcode).toSet();
    expect(codes.length, products.length);
    expect(codes.every((c) => c.length == 13 && hasValidCheckDigit(c)), true);
    expect(products.any((p) => p.lowStock), true); // shows the stock alert
    expect(products.any((p) => p.stock == 0), true);

    final now = DateTime(2026, 10, 27, 14, 30);
    final sales = DemoData.sales(products, now);
    expect(sales.length, greaterThan(80));
    expect(sales.every((s) => !s.date.isAfter(now)), true);
    expect(sales.every((s) => s.total > 0 && s.lines.isNotEmpty), true);
    for (final s in sales) {
      final sum = s.lines.fold(0.0, (a, l) => a + l.total);
      expect((sum - s.discount - s.total).abs() < 0.0001, true);
      expect(s.lines.every((l) => codes.contains(l.barcode)), true);
    }
    expect(sales.where((s) => s.date.day == now.day).isNotEmpty, true); // today has sales
    // deterministic
    expect(DemoData.sales(products, now).length, sales.length);
  });

  test('money formatting uses configured decimals and currency', () {
    expect(const AppSettings().money(16.95), '16,950 DT');
    expect(const AppSettings(decimals: 2, currency: 'EUR').money(3), '3,00 EUR');
  });

  test('CSV import: header, ; separator, comma decimals, bad rows skipped', () {
    const csv = '﻿Code-barres;Nom;Prix\n6191;"Lait; 1 L";1,350\n6192;Pain;2.100\n;Sans code;1\n6193;Eau;abc\n';
    final r = BackupService.parseProducts(csv);
    expect(r.items.map((p) => p.barcode), ['6191', '6192']);
    expect(r.items.first.name, 'Lait; 1 L');
    expect(r.items.first.price, 1.35);
    expect(r.skipped, 2);
    expect(r.hasCost, false);
    expect(r.hasStock, false);
  });

  test('CSV import: no header, comma separator', () {
    final r = BackupService.parseProducts('111,Cafe,4.5\n222,Sucre,1.2');
    expect(r.items.length, 2);
    expect(r.skipped, 0);
  });

  test('CSV import: cost, stock and alert columns', () {
    const csv = "Code-barres;Nom;Prix;Prix d'achat;Stock;Seuil alerte\n111;Cafe;4,5;3,2;10;3\n222;Sucre;1;;;\n";
    final r = BackupService.parseProducts(csv);
    expect(r.hasCost, true);
    expect(r.hasStock, true);
    expect(r.items[0].cost, 3.2);
    expect(r.items[0].stock, 10);
    expect(r.items[0].minStock, 3);
    expect(r.items[1].cost, 0);
    expect(r.items[1].stock, isNull);
  });

  testWidgets('dark theme exposes its palette and renders the shared widgets', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: Builder(builder: (context) {
        expect(Theme.of(context).brightness, Brightness.dark);
        expect(context.pal.card, AppPalette.dark.card);
        return const Scaffold(body: SoftCard(child: Text('ok')));
      }),
    ));
    expect(find.text('ok'), findsOneWidget);
  });

  testWidgets('hero total, CTA and header buttons fit a 360 px phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Column(children: [
          Row(children: [
            const Expanded(child: Text('Épicerie Chokri avec un très long nom de magasin', overflow: TextOverflow.ellipsis)),
            SoftIconButton(icon: Icons.keyboard, onPressed: () {}),
            SoftIconButton(icon: Icons.videocam, onPressed: () {}),
            SoftIconButton(icon: Icons.delete, onPressed: () {}),
          ]),
          const TotalBanner(label: 'TOTAL À PAYER', amount: '1 234 567,890 DT', sub: 'Remise −10,000 DT', badge: '128 articles'),
          PrimaryButton(label: 'Valider la commande', icon: Icons.check, trailing: '1 234 567,890 DT', onPressed: () {}),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
  });

  test('check digit validation rejects misreads', () {
    expect(hasValidCheckDigit('6191234567890'), false);
    expect(hasValidCheckDigit('4006381333931'), true); // EAN-13
    expect(hasValidCheckDigit('036000291452'), true); // UPC-A
    expect(hasValidCheckDigit('96385074'), true); // EAN-8
    expect(hasValidCheckDigit('4006381333932'), false);
    expect(hasValidCheckDigit('ABC123'), false);
  });

  test('discount: percent, amount, clamped to subtotal', () {
    expect(const Discount(DiscountType.percent, 10).amountFor(20), 2);
    expect(const Discount(DiscountType.percent, 33.333).amountFor(1), 0.333);
    expect(const Discount(DiscountType.amount, 5).amountFor(20), 5);
    expect(const Discount(DiscountType.amount, 50).amountFor(20), 20);
  });

  test('sale with discount: subtotal and profit', () {
    final sale = Sale(date: DateTime(2026), total: 8, discount: 2, method: PayMethod.cash, lines: const [
      SaleLine(barcode: '1', name: 'A', price: 5, qty: 2, cost: 3),
    ]);
    expect(sale.subtotal, 10);
    expect(sale.profit, 2); // (5-3)*2 - 2
  });

  test('held cart total applies discount', () {
    final h = HeldCart(
      id: 1,
      date: DateTime(2026),
      lines: const [SaleLine(barcode: '1', name: 'A', price: 10, qty: 2)],
      discount: const Discount(DiscountType.percent, 10),
    );
    expect(h.total, 18);
    expect(h.itemCount, 2);
  });

  test('profit ignores lines without purchase price; low stock flag', () {
    final sale = Sale(date: DateTime(2026), total: 14, method: PayMethod.cash, lines: const [
      SaleLine(barcode: '1', name: 'A', price: 5, qty: 2, cost: 3),
      SaleLine(barcode: '2', name: 'B', price: 4, qty: 1),
    ]);
    expect(sale.profit, 4);
    expect(sale.hasUnknownCost, true);
    expect(const Product(barcode: '1', name: 'A', price: 1, stock: 2, minStock: 2).lowStock, true);
    expect(const Product(barcode: '1', name: 'A', price: 1).lowStock, false);
  });

  test('qr template substitutes amount', () {
    expect(const AppSettings().qrData(2.5), 'https://pay.exemple.tn/?m=2.500');
  });
}
