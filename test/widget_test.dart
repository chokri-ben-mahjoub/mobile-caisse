import 'package:flutter_test/flutter_test.dart';
import 'package:mob_caisse/data/backup_service.dart';
import 'package:mob_caisse/data/models.dart';
import 'package:mob_caisse/data/settings_store.dart';

void main() {
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
