import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mob_caisse/data/barcode_utils.dart';
import 'package:mob_caisse/data/credit.dart';
import 'package:mob_caisse/data/database.dart';
import 'package:mob_caisse/data/models.dart';
import 'package:mob_caisse/data/purchase.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Guards the schema: a typo in any CREATE TABLE used to crash the app at start-up.
  test('a fresh database opens and every table works', () async {
    final db = await AppDatabase.openAt(inMemoryDatabasePath);

    await db.upsertProduct(const Product(barcode: '111', name: 'Lait', price: 1.5, cost: 1, stock: 4, minStock: 2));
    await db.insertCredit(CreditEntry(customer: 'Sami', phone: '20123456', amount: 12.5, date: DateTime(2026, 10, 1)));
    final credits = await db.credits();
    expect(credits.single.customer, 'Sami');
    expect(credits.single.phone, '20123456');

    await db.insertPurchase(Purchase(
      date: DateTime(2026, 10, 2),
      supplier: 'Délice',
      invoice: 'BL-1',
      paid: 5,
      lines: const [PurchaseLine(barcode: '111', name: 'Lait', qty: 10, cost: 1.2)],
    ));
    final p = (await db.products()).single;
    expect(p.stock, 14); // 4 + 10 received
    expect(p.cost, 1.2); // purchase price follows the last purchase
    expect((await db.purchases()).single.supplier, 'Délice');

    await db.insertSupplierPayment(SupplierPayment(supplier: 'Délice', amount: 3, date: DateTime(2026, 10, 3)));
    expect((await db.supplierPayments()).single.amount, 3);
    expect(await db.quotes(), isEmpty);
  });

  // The same article scanned a second time must be recognised, even when the camera reads
  // the code a little differently (leading zero, missing check digit, linked by the cashier).
  test('a saved article is found again by variants of its code and by a linked code', () async {
    final db = await AppDatabase.openAt(inMemoryDatabasePath);
    await db.upsertProduct(const Product(barcode: '120211800111', name: 'Cahier', price: 2.5));
    await db.upsertProduct(const Product(barcode: '6191234567890', name: 'Eau', price: 0.8));

    expect((await db.productByBarcode('120211800111'))?.name, 'Cahier');
    expect((await db.productByBarcode('0120211800111'))?.name, 'Cahier'); // EAN-13 form of a UPC-A
    expect((await db.productByBarcode('12021180011'))?.name, 'Cahier'); // read without the check digit
    expect((await db.productByBarcode('1202118001119'))?.name, 'Cahier'); // read with an extra digit
    expect(await db.productByBarcode('999999999999'), isNull);

    // A code the cashier links to an article ("c'est le même article") is known from then on.
    expect(await db.productByBarcode('120211800199'), isNull);
    await db.addAlias('120211800199', '120211800111');
    expect((await db.productByBarcode('120211800199'))?.name, 'Cahier');
  });

  test('looks-like-same-code suggestions', () {
    expect(looksLikeSameCode('120211800111', '120211800112'), isTrue); // one digit differs
    expect(looksLikeSameCode('120211800111', '0120211800111'), isTrue); // leading zero
    expect(looksLikeSameCode('120211800111', '6191234567890'), isFalse);
    expect(looksLikeSameCode('1234', '1235'), isFalse); // too short to guess
    expect(editDistance('kitten', 'sitting'), 3);
  });

  test('a code is confirmed only after identical repeated reads (misreads are filtered out)', () {
    final c = ScanConsensus();
    final t = DateTime(2026, 10, 29, 12);
    Duration ms(int n) => Duration(milliseconds: n);

    // The camera alternates between misreads: nothing is accepted.
    expect(c.add('120211800111', now: t), isNull);
    expect(c.add('12021180011', now: t.add(ms(150))), isNull);
    expect(c.add('120211800112', now: t.add(ms(300))), isNull);
    // The true code comes back: accepted on its second read.
    expect(c.add('120211800111', now: t.add(ms(450))), '120211800111');
    // Votes start from zero after an acceptance.
    expect(c.add('120211800111', now: t.add(ms(600))), isNull);
    // Reads too far apart do not add up.
    expect(c.add('999999999999', now: t.add(ms(2000))), isNull);
    expect(c.add('999999999999', now: t.add(ms(4000))), isNull);
    expect(c.add('999999999999', now: t.add(ms(4300))), '999999999999');
  });
}
