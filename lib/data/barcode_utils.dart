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
