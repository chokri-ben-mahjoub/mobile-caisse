import 'database.dart';
import 'report.dart';

class ReportService {
  ReportService(this._db);
  final AppDatabase _db;

  Future<Report> load(DateTime start, DateTime end) async => Report.from(await _db.salesBetween(start, end), start, end);

  /// Same length, immediately before [start] (used for the growth figure).
  Future<Report> loadPrevious(DateTime start, DateTime end) {
    final len = end.difference(start);
    return load(start.subtract(len), start);
  }
}
