import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
}
