import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:mob_caisse/data/models.dart';
import 'package:mob_caisse/data/pdf_quote.dart';
import 'package:mob_caisse/data/quote.dart';
import 'package:mob_caisse/data/settings_store.dart';

Quote _quote({QuoteStatus status = QuoteStatus.pending, DateTime? date}) => Quote(
      id: 7,
      date: date ?? DateTime(2026, 10, 20, 10),
      validDays: 15,
      customer: 'Ali Ben Salah',
      phone: '20 123 456',
      note: 'Livraison incluse',
      seller: 'Sami',
      status: status,
      discount: const Discount(DiscountType.percent, 10),
      lines: const [
        SaleLine(barcode: 'A', name: 'Eau minérale', price: 0.8, qty: 10),
        SaleLine(barcode: 'T', name: 'Tomates', price: 1.8, qty: 2.5, unit: 'kg'),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('quote totals, number and validity', () {
    final q = _quote();
    expect(q.number, 'DV-2026-0007');
    expect(q.subtotal, 12.5); // 8 + 4.5
    expect(q.discountAmount, 1.25);
    expect(q.total, 11.25);
    expect(q.itemCount, 11); // 10 units + 1 weighed
    expect(q.validUntil, DateTime(2026, 11, 4));
    expect(q.daysLeft(DateTime(2026, 11, 1, 18)), 3);
    expect(q.isExpired(DateTime(2026, 11, 4)), false);
    expect(q.isExpired(DateTime(2026, 11, 5)), true);
    expect(_quote(status: QuoteStatus.accepted).isExpired(DateTime(2027)), false);
  });

  test('quote survives a database round trip', () {
    final back = Quote.fromMap(_quote(status: QuoteStatus.refused).toMap());
    expect(back.customer, 'Ali Ben Salah');
    expect(back.status, QuoteStatus.refused);
    expect(back.discount?.value, 10);
    expect(back.lines.length, 2);
    expect(back.lines[1].unit, 'kg');
    expect(back.total, 11.25);
  });

  testWidgets('quote pdf builds', (tester) async {
    await tester.runAsync(() async {
      await initializeDateFormatting('fr_FR');
      final bytes = await PdfQuote.build(quote: _quote(), settings: const AppSettings(storeName: 'Épicerie Chez Sami'));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final f = File('build/sample_quote.pdf');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes);
    });
  });
}
