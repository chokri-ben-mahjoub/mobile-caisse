import 'database.dart';
import 'models.dart';

/// Cash closing (Z report): totals since the previous closing and the till count.
class ClosingService {
  ClosingService(this._db);
  final AppDatabase _db;

  /// Start of the period being closed: the last closing, or this morning
  /// (00:00) when there has never been one.
  Future<DateTime> periodStart() async {
    final last = await _db.lastClosing();
    if (last != null) return last.closedAt;
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Cash left in the till at the previous closing: today's opening float.
  Future<double> suggestedFloat() async => (await _db.lastClosing())?.floatLeft ?? 0;

  Future<ClosingSummary> summary(DateTime start, DateTime end) async =>
      ClosingSummary.from(await _db.salesBetween(start, end));

  /// Cash expected in the till: opening float plus net cash sales.
  static double expectedCash(double openingFloat, ClosingSummary s) => round3(openingFloat + s.cash);

  Future<CashClosing> close({
    required DateTime start,
    required DateTime end,
    required double openingFloat,
    required double countedCash,
    required double floatLeft,
    String? user,
    String? note,
  }) async {
    final s = await summary(start, end);
    final c = CashClosing(
      closedAt: end,
      periodStart: start,
      user: user,
      openingFloat: openingFloat,
      expectedCash: expectedCash(openingFloat, s),
      countedCash: countedCash,
      floatLeft: floatLeft,
      salesCount: s.salesCount,
      refundsCount: s.refundsCount,
      gross: s.gross,
      discounts: s.discounts,
      refunds: s.refunds,
      net: s.net,
      cash: s.cash,
      qr: s.qr,
      profit: s.profit,
      note: (note == null || note.trim().isEmpty) ? null : note.trim(),
    );
    final id = await _db.insertClosing(c);
    return CashClosing.fromMap({...c.toMap(), 'id': id});
  }

  Future<List<CashClosing>> history() => _db.closings();
}
