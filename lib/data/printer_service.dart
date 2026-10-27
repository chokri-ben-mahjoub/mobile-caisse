import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'models.dart';
import 'settings_store.dart';

/// Bluetooth thermal printer (58 mm, ESC/POS).
class PrinterService {
  static const _cols = 32;

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

  /// Connects and sends [build]'s bytes. Returns null on success, otherwise a French error message.
  Future<String?> _print(AppSettings s, Future<List<int>> Function(Generator g) build) async {
    if (s.printerMac.isEmpty) return 'Aucune imprimante choisie (Réglages).';
    if (!await PrintBluetoothThermal.bluetoothEnabled) return 'Bluetooth désactivé.';
    if (!await connect(s.printerMac)) return 'Connexion à l\'imprimante impossible.';
    final g = Generator(PaperSize.mm58, await CapabilityProfile.load());
    final ok = await PrintBluetoothThermal.writeBytes(await build(g));
    return ok ? null : 'Échec de l\'impression.';
  }

  /// Receipt of a sale, or the ticket of a return.
  Future<String?> printSale(Sale sale, AppSettings s) => _print(s, (g) async => _receiptBytes(g, sale, s));

  /// Cash closing report (Z).
  Future<String?> printClosing(CashClosing c, AppSettings s) => _print(s, (g) async => _closingBytes(g, c, s));

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

  /// `label` on the left, `value` on the right of a 32-column line.
  static String _row(String label, String value) {
    final pad = (_cols - label.length - value.length).clamp(1, _cols);
    return '$label${' ' * pad}$value';
  }

  List<int> _receiptBytes(Generator g, Sale sale, AppSettings s) {
    final bytes = <int>[];
    String money(double v) => v.toStringAsFixed(s.decimals);

    bytes.addAll(g.reset());
    bytes.addAll(g.text(_ascii(s.storeName),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2)));
    if (sale.isRefund) {
      bytes.addAll(g.text('TICKET DE RETOUR', styles: const PosStyles(align: PosAlign.center, bold: true)));
    }
    bytes.addAll(g.text(DateFormat('dd/MM/yyyy HH:mm').format(sale.date),
        styles: const PosStyles(align: PosAlign.center)));
    if (sale.id != null) {
      bytes.addAll(g.text('Ticket n ${sale.id}', styles: const PosStyles(align: PosAlign.center)));
    }
    if (sale.isRefund && sale.refSaleId != null) {
      bytes.addAll(g.text('Ticket d\'origine n ${sale.refSaleId}', styles: const PosStyles(align: PosAlign.center)));
    }
    if (sale.isRefund && sale.reason != null && sale.reason!.isNotEmpty) {
      bytes.addAll(g.text(_ascii('Motif: ${sale.reason}'), styles: const PosStyles(align: PosAlign.center)));
    }
    if (sale.seller != null && sale.seller!.isNotEmpty) {
      bytes.addAll(g.text(_ascii('Vendeur: ${sale.seller}'), styles: const PosStyles(align: PosAlign.center)));
    }
    bytes.addAll(g.text('-' * _cols));

    for (final l in sale.lines) {
      bytes.addAll(g.text(_ascii(l.name)));
      final unitPrice = l.byWeight ? '${money(l.price)}/kg' : money(l.price);
      bytes.addAll(g.text(_row('${fmtQty(l.qty, unit: l.unit)} x $unitPrice', money(l.total))));
    }

    bytes.addAll(g.text('-' * _cols));
    if (sale.discount != 0) {
      bytes.addAll(g.text('Sous-total  ${money(sale.subtotal)}', styles: const PosStyles(align: PosAlign.right)));
      bytes.addAll(g.text('Remise  ${money(-sale.discount)}', styles: const PosStyles(align: PosAlign.right)));
    }
    bytes.addAll(g.text(_ascii('${sale.isRefund ? 'REMBOURSE' : 'TOTAL'}  ${money(sale.total.abs())} ${s.currency}'),
        styles: const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2, width: PosTextSize.size2)));
    if (!sale.isRefund && sale.method == PayMethod.cash && sale.received != null && sale.received! > 0) {
      bytes.addAll(g.text('Recu: ${money(sale.received!)}', styles: const PosStyles(align: PosAlign.right)));
      final change = (sale.received! - sale.total).clamp(0, double.infinity);
      bytes.addAll(g.text('Rendu: ${money(change.toDouble())}', styles: const PosStyles(align: PosAlign.right)));
    }
    bytes.addAll(g.text(sale.method == PayMethod.cash ? 'Paiement: especes' : 'Paiement: QR code',
        styles: const PosStyles(align: PosAlign.right)));
    bytes.addAll(g.feed(1));
    bytes.addAll(g.text(sale.isRefund ? 'A bientot !' : 'Merci de votre visite !',
        styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(g.feed(3));
    bytes.addAll(g.cut());
    return bytes;
  }

  List<int> _closingBytes(Generator g, CashClosing c, AppSettings s) {
    final bytes = <int>[];
    String money(double v) => v.toStringAsFixed(s.decimals);
    String signed(double v) => '${v > 0 ? '+' : ''}${money(v)}';
    final fmt = DateFormat('dd/MM HH:mm');

    bytes.addAll(g.reset());
    bytes.addAll(g.text(_ascii(s.storeName), styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
    bytes.addAll(g.text('CLOTURE DE CAISSE (Z)', styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(g.text('Du ${fmt.format(c.periodStart)}', styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(g.text('au ${fmt.format(c.closedAt)}', styles: const PosStyles(align: PosAlign.center)));
    if (c.user != null && c.user!.isNotEmpty) {
      bytes.addAll(g.text(_ascii('Par: ${c.user}'), styles: const PosStyles(align: PosAlign.center)));
    }
    bytes.addAll(g.text('-' * _cols));
    bytes.addAll(g.text(_row('Ventes (${c.salesCount})', money(c.gross))));
    if (c.discounts > 0) bytes.addAll(g.text(_row('Remises', '-${money(c.discounts)}')));
    if (c.refundsCount > 0) bytes.addAll(g.text(_row('Retours (${c.refundsCount})', '-${money(c.refunds)}')));
    bytes.addAll(g.text(_row('TOTAL NET', '${money(c.net)} ${s.currency}'), styles: const PosStyles(bold: true)));
    bytes.addAll(g.text('-' * _cols));
    bytes.addAll(g.text(_row('Especes', money(c.cash))));
    bytes.addAll(g.text(_row('QR code', money(c.qr))));
    bytes.addAll(g.text(_row('Benefice', money(c.profit))));
    bytes.addAll(g.text('-' * _cols));
    bytes.addAll(g.text(_row('Fond de caisse', money(c.openingFloat))));
    bytes.addAll(g.text(_row('Especes attendues', money(c.expectedCash))));
    bytes.addAll(g.text(_row('Especes comptees', money(c.countedCash))));
    bytes.addAll(g.text(_row('ECART', signed(c.difference)), styles: const PosStyles(bold: true)));
    bytes.addAll(g.text(_row('Laisse en caisse', money(c.floatLeft))));
    if (c.note != null && c.note!.isNotEmpty) {
      bytes.addAll(g.text('-' * _cols));
      bytes.addAll(g.text(_ascii('Note: ${c.note}')));
    }
    bytes.addAll(g.feed(3));
    bytes.addAll(g.cut());
    return bytes;
  }
}
