import 'package:mobile_scanner/mobile_scanner.dart';

/// EAN-8 / UPC-A / EAN-13 check digit validation.
bool hasValidCheckDigit(String code) {
  if (!RegExp(r'^\d+$').hasMatch(code)) return false;
  final n = code.length;
  if (n != 8 && n != 12 && n != 13) return true; // other lengths: no check digit rule
  var sum = 0;
  for (var k = 0; k < n - 1; k++) {
    final digit = code.codeUnitAt(n - 2 - k) - 48;
    sum += digit * (k.isEven ? 3 : 1);
  }
  return (10 - sum % 10) % 10 == code.codeUnitAt(n - 1) - 48;
}

/// The trimmed value of a scanned barcode, or null when the read is empty or
/// a retail code (EAN/UPC) whose check digit is wrong, i.e. a camera misread.
String? cleanScan(Barcode b) {
  final v = b.rawValue?.trim();
  if (v == null || v.isEmpty) return null;
  final retail = b.format == BarcodeFormat.ean13 ||
      b.format == BarcodeFormat.ean8 ||
      b.format == BarcodeFormat.upcA;
  if (retail && !hasValidCheckDigit(v)) return null;
  return v;
}

/// Number of single-character edits between [a] and [b] (insert, delete, replace).
int editDistance(String a, String b) {
  if (a == b) return 0;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// True when two barcodes are most likely the same article read differently: same digits
/// up to leading zeros, a missing / wrong check digit, or one misread digit.
bool looksLikeSameCode(String a, String b) {
  String bare(String x) => x.replaceFirst(RegExp(r'^0+'), '');
  final x = bare(a), y = bare(b);
  if (x.length < 8 || y.length < 8) return false;
  return editDistance(x, y) <= 2;
}

/// Accepts a barcode only once the camera has read the SAME value several times in a row.
///
/// A single camera frame can misread a code (one digit off, a missing check digit), and every
/// misread looks like a new article. Waiting for [need] identical reads within [window] filters
/// those out: the misreads differ from each other, the true code repeats.
class ScanConsensus {
  ScanConsensus({this.need = 2, this.window = const Duration(milliseconds: 1200)});
  final int need;
  final Duration window;

  final Map<String, int> _votes = {};
  DateTime _since = DateTime.fromMillisecondsSinceEpoch(0);

  /// Feeds one read; returns the code when it is confirmed, otherwise null.
  String? add(String code, {DateTime? now}) {
    final t = now ?? DateTime.now();
    if (t.difference(_since) > window) {
      _votes.clear();
      _since = t;
    }
    final n = (_votes[code] ?? 0) + 1;
    _votes[code] = n;
    if (n >= need) {
      _votes.clear();
      return code;
    }
    return null;
  }

  void reset() => _votes.clear();
}
