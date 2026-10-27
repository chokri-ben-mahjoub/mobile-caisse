import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'models.dart';
import 'settings_store.dart';

/// Bluetooth thermal printer (58 mm, ESC/POS).
class PrinterService {
  Future<bool> ensurePermissions() async {
    final res = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    return res.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<List<BluetoothInfo>> pairedDevices() async {
    if (!await ensurePermissions()) return [];
    return PrintBluetoothThermal.pairedBluetooths;
  }

  Future<bool> connect(String mac) async {
    if (mac.isEmpty || !await ensurePermissions()) return false;
    if (await PrintBluetoothThermal.connectionStatus) return true;
    return PrintBluetoothThermal.connect(macPrinterAddress: mac);
  }

  Future<bool> disconnect() => PrintBluetoothThermal.disconnect;

  /// Returns null on success, otherwise a French error message.
  Future<String?> printSale(Sale sale, AppSettings s) async {
    if (s.printerMac.isEmpty) return 'Aucune imprimante choisie (Réglages).';
    if (!await PrintBluetoothThermal.bluetoothEnabled) return 'Bluetooth désactivé.';
    if (!await connect(s.printerMac)) return 'Connexion à l\'imprimante impossible.';
    final ok = await PrintBluetoothThermal.writeBytes(await _receiptBytes(sale, s));
    return ok ? null : 'Échec de l\'impression.';
  }

  Future<String?> printTest(AppSettings s) {
    final test = Sale(
      date: DateTime.now(),
      total: 1,
      method: PayMethod.cash,
      lines: const [SaleLine(barcode: '0', name: 'Ticket de test', price: 1, qty: 1)],
    );
    return printSale(test, s);
  }

  // Most thermal printers have no French code page by default: strip accents.
  static String _ascii(String t) {
    const from = 'àâäáãçèéêëìíîïñòóôöõùúûüýÿÀÂÄÁÇÈÉÊËÌÍÎÏÑÒÓÔÖÙÚÛÜÝœŒ€';
    const to = 'aaaaaceeeeiiiinooooouuuuyyAAAACEEEEIIIINOOOOUUUUYoOE';
    final b = StringBuffer();
    for (final r in t.runes) {
      final c = String.fromCharCode(r);
      final i = from.indexOf(c);
      b.write(i >= 0 ? to[i] : (r < 128 ? c : '?'));
    }
    return b.toString();
  }

  Future<List<int>> _receiptBytes(Sale sale, AppSettings s) async {
    final profile = await CapabilityProfile.load();
    final g = Generator(PaperSize.mm58, profile);
    const cols = 32;
    final bytes = <int>[];
    String money(double v) => v.toStringAsFixed(s.decimals);

    bytes.addAll(g.reset());
    bytes.addAll(g.text(_ascii(s.storeName),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2)));
    bytes.addAll(g.text(DateFormat('dd/MM/yyyy HH:mm').format(sale.date),
        styles: const PosStyles(align: PosAlign.center)));
    if (sale.id != null) {
      bytes.addAll(g.text('Ticket n° ${sale.id}'.replaceAll('°', ''), styles: const PosStyles(align: PosAlign.center)));
    }
    bytes.addAll(g.text('-' * cols));

    for (final l in sale.lines) {
      bytes.addAll(g.text(_ascii(l.name)));
      final left = '${l.qty} x ${money(l.price)}';
      final right = money(l.total);
      final pad = (cols - left.length - right.length).clamp(1, cols);
      bytes.addAll(g.text('$left${' ' * pad}$right'));
    }

    bytes.addAll(g.text('-' * cols));
    if (sale.discount > 0) {
      bytes.addAll(g.text('Sous-total  ${money(sale.subtotal)}', styles: const PosStyles(align: PosAlign.right)));
      bytes.addAll(g.text('Remise  -${money(sale.discount)}', styles: const PosStyles(align: PosAlign.right)));
    }
    bytes.addAll(g.text(_ascii('TOTAL  ${money(sale.total)} ${s.currency}'),
        styles: const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2, width: PosTextSize.size2)));
    if (sale.method == PayMethod.cash && sale.received != null && sale.received! > 0) {
      bytes.addAll(g.text('Recu: ${money(sale.received!)}', styles: const PosStyles(align: PosAlign.right)));
      final change = (sale.received! - sale.total).clamp(0, double.infinity);
      bytes.addAll(g.text('Rendu: ${money(change.toDouble())}', styles: const PosStyles(align: PosAlign.right)));
    }
    bytes.addAll(g.text(sale.method == PayMethod.cash ? 'Paiement: especes' : 'Paiement: QR code',
        styles: const PosStyles(align: PosAlign.right)));
    bytes.addAll(g.feed(1));
    bytes.addAll(g.text('Merci de votre visite !', styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(g.feed(3));
    bytes.addAll(g.cut());
    return bytes;
  }
}
