import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../data/quote.dart';

class QuotesProvider extends ChangeNotifier {
  QuotesProvider(this._db) {
    load();
  }
  final AppDatabase _db;

  List<Quote> quotes = [];

  Future<void> load() async {
    quotes = await _db.quotes();
    notifyListeners();
  }

  /// Saves a quote built from [lines]; returns it with its number.
  Future<Quote> create({
    required List<SaleLine> lines,
    Discount? discount,
    String customer = '',
    String phone = '',
    String note = '',
    int validDays = 15,
    String? seller,
  }) async {
    final q = Quote(
      date: DateTime.now(),
      validDays: validDays,
      customer: customer.trim(),
      phone: phone.trim(),
      note: note.trim(),
      seller: seller,
      lines: lines,
      discount: discount,
    );
    final id = await _db.insertQuote(q);
    await load();
    return q.copyWith(id: id);
  }

  Future<void> setStatus(Quote q, QuoteStatus s) async {
    await _db.setQuoteStatus(q.id!, s);
    await load();
  }

  Future<void> delete(Quote q) async {
    await _db.deleteQuote(q.id!);
    await load();
  }

  /// Pending quotes that are still valid.
  int get openCount {
    final now = DateTime.now();
    return quotes.where((q) => q.status == QuoteStatus.pending && !q.isExpired(now)).length;
  }
}
