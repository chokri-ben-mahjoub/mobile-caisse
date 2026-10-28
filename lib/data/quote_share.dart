import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pdf_quote.dart';
import 'pdf_report.dart';
import 'quote.dart';
import 'settings_store.dart';

/// Ways to hand a quote to the customer: WhatsApp, SMS, e-mail, PDF share, save/print.
class QuoteShare {
  QuoteShare(this.quote, this.settings);
  final Quote quote;
  final AppSettings settings;

  /// Country code prepended to 8-digit local numbers (Tunisia).
  static const defaultCountryCode = '216';

  /// International digits for wa.me / SMS: `+33 6 12…` → `33612…`, `20 123 456` → `21620123456`.
  static String? internationalNumber(String raw) {
    var d = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (d.isEmpty) return null;
    if (d.startsWith('+')) return d.substring(1).replaceAll('+', '');
    if (d.startsWith('00')) return d.substring(2);
    if (d.length == 8) return '$defaultCountryCode$d';
    return d;
  }

  /// Friendly text with the key figures, used for WhatsApp / SMS / e-mail bodies.
  String message() {
    final df = DateFormat('dd/MM/yyyy');
    final b = StringBuffer()
      ..writeln('Bonjour${quote.customer.isEmpty ? '' : ' ${quote.customer}'},')
      ..writeln()
      ..writeln('Voici votre devis ${quote.number} de ${settings.storeName} :')
      ..writeln();
    for (final l in quote.lines.take(8)) {
      final q = l.qty == l.qty.roundToDouble() ? l.qty.toStringAsFixed(0) : l.qty.toString().replaceAll('.', ',');
      b.writeln('• ${l.name} × $q${l.byWeight ? ' kg' : ''} — ${settings.money(l.total)}');
    }
    if (quote.lines.length > 8) b.writeln('• … et ${quote.lines.length - 8} autre(s) article(s)');
    b.writeln();
    if (quote.discountAmount > 0) b.writeln('Remise : −${settings.money(quote.discountAmount)}');
    b
      ..writeln('TOTAL : ${settings.money(quote.total)}')
      ..writeln('Valable jusqu\'au ${df.format(quote.validUntil)}.')
      ..writeln()
      ..write('Merci de votre confiance !');
    return b.toString();
  }

  String get subject => 'Devis ${quote.number} – ${settings.storeName}';

  Future<List<int>> pdfBytes() => PdfQuote.build(quote: quote, settings: settings);

  /// Opens a WhatsApp chat with the customer (or the contact picker when no phone) with [message] prefilled.
  Future<bool> whatsapp() {
    final n = internationalNumber(quote.phone);
    final uri = Uri.parse('https://wa.me/${n ?? ''}?text=${Uri.encodeComponent(message())}');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<bool> sms() {
    final n = internationalNumber(quote.phone);
    final uri = Uri(scheme: 'sms', path: n == null ? '' : '+$n', queryParameters: {'body': message()});
    return launchUrl(uri);
  }

  Future<bool> email([String to = '']) {
    final uri = Uri(scheme: 'mailto', path: to, queryParameters: {'subject': subject, 'body': message()});
    return launchUrl(uri);
  }

  /// System share sheet with the PDF attached: WhatsApp, Gmail, Drive, Bluetooth…
  Future<void> sharePdf() async {
    final f = await PdfReport.save(await pdfBytes(), 'devis-${quote.number}.pdf');
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path, mimeType: 'application/pdf')],
      subject: subject,
      text: message(),
    ));
  }

  /// Opens the system print dialog, whose "Enregistrer au format PDF" saves the file on the phone.
  Future<void> saveOrPrint() => Printing.layoutPdf(
        name: 'devis-${quote.number}.pdf',
        format: PdfPageFormat.a4,
        onLayout: (_) async => Uint8List.fromList(await pdfBytes()),
      );
}
