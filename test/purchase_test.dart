import 'package:flutter_test/flutter_test.dart';

import 'package:mob_caisse/data/purchase.dart';

PurchaseLine line(double q, double c) => PurchaseLine(barcode: '1', name: 'Lait', qty: q, cost: c);

Purchase buy(String who, List<PurchaseLine> lines, double paid, int daysAgo, {String phone = ''}) => Purchase(
      date: DateTime.now().subtract(Duration(days: daysAgo)),
      supplier: who,
      phone: phone,
      lines: lines,
      paid: paid,
    );

void main() {
  test('purchase totals, owed and settled', () {
    final p = buy('Délice', [line(10, 1.2), line(4, 2.5)], 12, 0);
    expect(p.total, 22);
    expect(p.owed, 10);
    expect(p.settled, isFalse);
    expect(p.articles, 14);
    expect(buy('Délice', [line(1, 5)], 5, 0).settled, isTrue);
    expect(buy('Délice', [line(1, 5)], 9, 0).owed, 0); // overpaid never negative
  });

  test('purchase survives a map round trip with its lines', () {
    final p = Purchase(
      date: DateTime(2026, 10, 1, 9),
      supplier: 'Délice',
      phone: '2012',
      invoice: 'BL-42',
      lines: const [PurchaseLine(barcode: '9', name: 'Farine', qty: 2.5, cost: 1.1, unit: 'kg')],
      paid: 1,
      note: 'n',
    );
    final q = Purchase.fromMap({...p.toMap(), 'id': 5});
    expect((q.id, q.supplier, q.invoice, q.paid, q.note), (5, 'Délice', 'BL-42', 1, 'n'));
    expect(q.lines.single.name, 'Farine');
    expect(q.lines.single.qty, 2.5);
    expect(q.lines.single.unit, 'kg');
    expect(q.total, p.total);
  });

  test('supplier accounts group by name and subtract payments', () {
    final accounts = SupplierAccount.group([
      buy('délice', [line(10, 2)], 5, 1), // owes 15
      buy('Délice', [line(5, 2)], 0, 3, phone: '2012'), // owes 10
      buy('Sodipa', [line(1, 4)], 4, 2), // settled
    ], [
      SupplierPayment(supplier: 'Délice', amount: 10, date: DateTime.now()),
    ]);
    expect(accounts.length, 2);
    final d = accounts.first;
    expect(d.name.toLowerCase(), 'délice');
    expect(d.purchased, 30);
    expect(d.balance, 15);
    expect(d.phone, '2012');
    expect(d.owes, isTrue);
    expect(accounts.last.owes, isFalse);
  });
}
