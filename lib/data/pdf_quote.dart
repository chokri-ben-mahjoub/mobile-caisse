import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models.dart';
import 'quote.dart';
import 'settings_store.dart';

const _blue = PdfColor.fromInt(0xFF2563EB);
const _indigo = PdfColor.fromInt(0xFF5B34D6);
const _ink = PdfColor.fromInt(0xFF0F172A);
const _muted = PdfColor.fromInt(0xFF64748B);
const _soft = PdfColor.fromInt(0xFFF1F5F9);
const _line = PdfColor.fromInt(0xFFE2E8F0);
const _green = PdfColor.fromInt(0xFF16A34A);

/// A4 quote: header, customer block, lines table, totals, conditions and a signature box.
class PdfQuote {
  static Future<List<int>> build({required Quote quote, required AppSettings settings}) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    final doc = pw.Document(
      title: 'Devis ${quote.number}',
      author: settings.storeName,
      creator: 'Caisse POS',
      theme: pw.ThemeData.withFont(base: regular, bold: bold, italic: regular, boldItalic: bold),
    );
    final df = DateFormat('dd/MM/yyyy');

    String m(double v) {
      final parts = v.abs().toStringAsFixed(settings.decimals).split('.');
      final g = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
      return '${v < 0 ? '−' : ''}$g${parts.length > 1 ? ',${parts[1]}' : ''} ${settings.currency}';
    }

    String qty(SaleLine l) => (l.qty == l.qty.roundToDouble() ? l.qty.toStringAsFixed(0) : l.qty.toString().replaceAll('.', ',')) +
        (l.byWeight ? ' kg' : '');

    pw.Widget info(String label, String value) => pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: _soft, borderRadius: pw.BorderRadius.circular(10)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(label, style: const pw.TextStyle(color: _muted, fontSize: 8.5)),
              pw.SizedBox(height: 3),
              pw.Text(value, style: pw.TextStyle(color: _ink, fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
        );

    pw.Widget cell(String t, {bool head = false, pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: pw.Text(t,
              textAlign: align,
              style: pw.TextStyle(
                fontSize: head ? 9 : 10,
                color: head ? PdfColors.white : _ink,
                fontWeight: head ? pw.FontWeight.bold : pw.FontWeight.normal,
              )),
        );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 40),
      footer: (c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('${settings.storeName} · Devis ${quote.number}', style: const pw.TextStyle(color: _muted, fontSize: 8)),
        pw.Text('Page ${c.pageNumber}/${c.pagesCount}', style: const pw.TextStyle(color: _muted, fontSize: 8)),
      ]),
      build: (c) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(20),
          decoration: pw.BoxDecoration(
            borderRadius: pw.BorderRadius.circular(16),
            gradient: const pw.LinearGradient(colors: [_blue, _indigo], begin: pw.Alignment.topLeft, end: pw.Alignment.bottomRight),
          ),
          child: pw.Row(children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(settings.storeName.isEmpty ? 'Ma boutique' : settings.storeName,
                    style: pw.TextStyle(color: PdfColors.white, fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('DEVIS', style: pw.TextStyle(color: const PdfColor.fromInt(0xFFBFD4FF), fontSize: 11, fontWeight: pw.FontWeight.bold, letterSpacing: 2)),
              ]),
            ),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text(quote.number, style: pw.TextStyle(color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Émis le ${df.format(quote.date)}', style: const pw.TextStyle(color: PdfColor.fromInt(0xFFBFD4FF), fontSize: 10)),
            ]),
          ]),
        ),
        pw.SizedBox(height: 14),
        pw.Row(children: [
          info('Client', quote.customer.isEmpty ? '—' : quote.customer),
          pw.SizedBox(width: 8),
          info('Téléphone', quote.phone.isEmpty ? '—' : quote.phone),
          pw.SizedBox(width: 8),
          info('Valable jusqu\'au', df.format(quote.validUntil)),
          pw.SizedBox(width: 8),
          info('Établi par', quote.seller ?? settings.storeName),
        ]),
        pw.SizedBox(height: 16),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(5),
            1: pw.FlexColumnWidth(1.6),
            2: pw.FlexColumnWidth(2.2),
            3: pw.FlexColumnWidth(2.4),
          },
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.6)),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _blue, borderRadius: pw.BorderRadius.circular(8)),
              children: [
                cell('Désignation', head: true),
                cell('Qté', head: true, align: pw.TextAlign.right),
                cell('Prix unit.', head: true, align: pw.TextAlign.right),
                cell('Total', head: true, align: pw.TextAlign.right),
              ],
            ),
            for (final l in quote.lines)
              pw.TableRow(children: [
                cell(l.name),
                cell(qty(l), align: pw.TextAlign.right),
                cell(m(l.price), align: pw.TextAlign.right),
                cell(m(l.total), align: pw.TextAlign.right),
              ]),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Container(
            width: 230,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(color: _soft, borderRadius: pw.BorderRadius.circular(12)),
            child: pw.Column(children: [
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('Sous-total', style: const pw.TextStyle(color: _muted, fontSize: 10)),
                pw.Text(m(quote.subtotal), style: const pw.TextStyle(fontSize: 10)),
              ]),
              if (quote.discountAmount > 0) ...[
                pw.SizedBox(height: 5),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('Remise', style: const pw.TextStyle(color: _green, fontSize: 10)),
                  pw.Text('−${m(quote.discountAmount)}', style: const pw.TextStyle(color: _green, fontSize: 10)),
                ]),
              ],
              pw.Divider(color: _line),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('TOTAL', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text(m(quote.total), style: pw.TextStyle(color: _blue, fontSize: 15, fontWeight: pw.FontWeight.bold)),
              ]),
            ]),
          ),
        ),
        if (quote.note.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text('Remarques', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(quote.note, style: const pw.TextStyle(color: _muted, fontSize: 10)),
        ],
        pw.SizedBox(height: 22),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Text(
              'Ce devis est valable ${quote.validDays} jours à compter de sa date d\'émission. '
              'Les prix sont susceptibles d\'évoluer après cette date.',
              style: const pw.TextStyle(color: _muted, fontSize: 9),
            ),
          ),
          pw.SizedBox(width: 24),
          pw.Container(
            width: 190,
            height: 78,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(10)),
            child: pw.Text('Bon pour accord — date et signature', style: const pw.TextStyle(color: _muted, fontSize: 9)),
          ),
        ]),
      ],
    ));
    return doc.save();
  }
}
