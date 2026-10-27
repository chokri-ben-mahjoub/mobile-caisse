import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models.dart';
import 'report.dart';
import 'settings_store.dart';

const _blue = PdfColor.fromInt(0xFF2563EB);
const _indigo = PdfColor.fromInt(0xFF5B34D6);
const _ink = PdfColor.fromInt(0xFF0F172A);
const _muted = PdfColor.fromInt(0xFF64748B);
const _soft = PdfColor.fromInt(0xFFF1F5F9);
const _line = PdfColor.fromInt(0xFFE2E8F0);
const _green = PdfColor.fromInt(0xFF16A34A);
const _red = PdfColor.fromInt(0xFFDC2626);
const _cyan = PdfColor.fromInt(0xFF22D3EE);

/// Builds the activity report as a clean A4 PDF and returns the file.
class PdfReport {
  static Future<List<int>> build({
    required Report report,
    Report? previous,
    required AppSettings settings,
    required String periodLabel,
  }) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final medium = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Medium.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    final doc = pw.Document(
      title: 'Rapport d\'activité – ${settings.storeName}',
      author: settings.storeName,
      creator: 'Caisse POS',
      theme: pw.ThemeData.withFont(base: regular, bold: bold, italic: regular, boldItalic: bold),
    );
    final b = _Builder(report, previous, settings, periodLabel, medium);

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 40),
      header: (c) => c.pageNumber == 1 ? pw.SizedBox() : b.miniHeader(),
      footer: (c) => b.footer(c),
      build: (c) => [
        b.hero(),
        pw.SizedBox(height: 16),
        b.kpis(),
        pw.SizedBox(height: 18),
        b.revenueChart(),
        pw.SizedBox(height: 14),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: b.paymentSplit()),
          pw.SizedBox(width: 14),
          pw.Expanded(child: b.hours()),
        ]),
        pw.NewPage(),
        b.topProducts(),
        if (report.bySeller.isNotEmpty) ...[pw.SizedBox(height: 18), b.sellers()],
        pw.SizedBox(height: 14),
        b.notes(),
      ],
    ));
    return doc.save();
  }

  static Future<File> save(List<int> bytes, String name) async {
    final f = File('${(await getTemporaryDirectory()).path}/$name');
    return f.writeAsBytes(bytes, flush: true);
  }
}

class _Builder {
  _Builder(this.r, this.prev, this.s, this.period, this.medium);
  final Report r;
  final Report? prev;
  final AppSettings s;
  final String period;
  final pw.Font medium;

  final _df = DateFormat('dd/MM/yyyy');
  String get _range {
    final last = r.end.subtract(const Duration(days: 1));
    return r.start.year == last.year && r.start.month == last.month && r.start.day == last.day
        ? _df.format(r.start)
        : 'du ${_df.format(r.start)} au ${_df.format(last)}';
  }

  /// Amount with thousands grouped by a non-breaking space.
  String _m(double v) {
    final neg = v < 0;
    final parts = v.abs().toStringAsFixed(s.decimals).split('.');
    final g = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
    return '${neg ? '−' : ''}$g${parts.length > 1 ? ',${parts[1]}' : ''} ${s.currency}';
  }

  String _pct(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')} %';

  pw.Widget hero() => pw.Container(
        padding: const pw.EdgeInsets.all(20),
        decoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(16),
          gradient: const pw.LinearGradient(colors: [_blue, _indigo], begin: pw.Alignment.topLeft, end: pw.Alignment.bottomRight),
        ),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(s.storeName.isEmpty ? 'Ma boutique' : s.storeName,
                  style: pw.TextStyle(color: PdfColors.white, fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Rapport d\'activité', style: const pw.TextStyle(color: PdfColors.white, fontSize: 13)),
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFF5C7FEA), borderRadius: pw.BorderRadius.circular(9)),
                child: pw.Text('$period  ·  $_range', style: pw.TextStyle(color: PdfColors.white, fontSize: 10.5, font: medium)),
              ),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('CHIFFRE D\'AFFAIRES NET', style: const pw.TextStyle(color: PdfColor.fromInt(0xFFD6E0FF), fontSize: 8.5)),
            pw.SizedBox(height: 2),
            pw.Text(_m(r.net), style: pw.TextStyle(color: PdfColors.white, fontSize: 24, fontWeight: pw.FontWeight.bold)),
            if (prev != null && r.growthVs(prev!) != null) _growthChip(r.growthVs(prev!)!),
          ]),
        ]),
      );

  pw.Widget _growthChip(double g) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(9)),
        child: pw.Text('${g >= 0 ? '+' : '−'}${_pct(g.abs())} vs période précédente',
            style: pw.TextStyle(color: g >= 0 ? _green : _red, fontSize: 9, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _tile(String label, String value, {String? sub, PdfColor color = _ink}) => pw.Expanded(
        child: pw.Container(
          height: 76,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: _soft, borderRadius: pw.BorderRadius.circular(12)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label.toUpperCase(), style: const pw.TextStyle(color: _muted, fontSize: 8)),
            pw.SizedBox(height: 4),
            pw.Text(value, style: pw.TextStyle(color: color, fontSize: 15, fontWeight: pw.FontWeight.bold)),
            if (sub != null) ...[pw.SizedBox(height: 2), pw.Text(sub, style: const pw.TextStyle(color: _muted, fontSize: 8.5))],
          ]),
        ),
      );

  pw.Widget kpis() => pw.Column(children: [
        pw.Row(children: [
          _tile('Bénéfice', _m(r.profit), sub: r.net > 0 ? 'Marge ${_pct(r.margin)}' : null, color: _green),
          pw.SizedBox(width: 10),
          _tile('Tickets', '${r.salesCount}', sub: 'Panier moyen ${_m(r.avgBasket)}'),
          pw.SizedBox(width: 10),
          _tile('Articles vendus', '${r.itemsSold}'),
        ]),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          _tile('Ventes brutes', _m(r.gross)),
          pw.SizedBox(width: 10),
          _tile('Remises', r.discounts > 0 ? '−${_m(r.discounts)}' : _m(0)),
          pw.SizedBox(width: 10),
          _tile('Retours', r.refundsCount == 0 ? _m(0) : '−${_m(r.refunds)}',
              sub: r.refundsCount == 0 ? null : '${r.refundsCount} retour${r.refundsCount > 1 ? 's' : ''}', color: r.refundsCount == 0 ? _ink : _red),
        ]),
      ]);

  pw.Widget _title(String t, {String? hint}) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Container(width: 4, height: 14, decoration: pw.BoxDecoration(color: _blue, borderRadius: pw.BorderRadius.circular(2))),
          pw.SizedBox(width: 8),
          pw.Text(t, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink)),
          if (hint != null) ...[pw.Spacer(), pw.Text(hint, style: const pw.TextStyle(fontSize: 8.5, color: _muted))],
        ]),
      );

  /// Per-day bars; long periods are grouped by week so bars stay readable.
  pw.Widget revenueChart() {
    final days = r.days;
    final groups = <({String label, double v})>[];
    if (days.length <= 31) {
      for (final d in days) {
        groups.add((label: days.length <= 10 ? DateFormat('EEE d', 'fr_FR').format(d.day) : '${d.day.day}', v: d.revenue));
      }
    } else {
      for (var i = 0; i < days.length; i += 7) {
        final chunk = days.skip(i).take(7);
        groups.add((label: DateFormat('d/M').format(chunk.first.day), v: chunk.fold(0.0, (a, e) => a + e.revenue)));
      }
    }
    final maxV = groups.fold(0.0, (m, g) => g.v > m ? g.v : m);
    const h = 150.0;
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      _title('Évolution du chiffre d\'affaires', hint: days.length > 31 ? 'par semaine' : 'par jour'),
      pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(12, 14, 12, 8),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(12)),
        child: pw.Column(children: [
          pw.SizedBox(
            height: h + 14,
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              for (final g in groups)
                pw.Expanded(
                  child: pw.Padding(
                    padding: pw.EdgeInsets.symmetric(horizontal: groups.length > 20 ? 1 : 3),
                    child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                      if (groups.length <= 10 && g.v != 0)
                        pw.Text(s.decimals == 0 ? g.v.round().toString() : g.v.toStringAsFixed(g.v.abs() >= 100 ? 0 : 1),
                            style: const pw.TextStyle(fontSize: 7, color: _muted)),
                      pw.SizedBox(height: 2),
                      pw.Container(
                        height: maxV <= 0 ? 2 : (g.v <= 0 ? 2 : g.v / maxV * h),
                        decoration: pw.BoxDecoration(
                          color: g.v == maxV && maxV > 0 ? _indigo : _blue,
                          borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(3)),
                        ),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
          pw.Container(height: 1, color: _line),
          pw.SizedBox(height: 4),
          pw.Row(children: [
            for (final g in groups)
              pw.Expanded(child: pw.Center(child: pw.Text(g.label, style: const pw.TextStyle(fontSize: 6.5, color: _muted)))),
          ]),
        ]),
      ),
    ]);
  }

  pw.Widget paymentSplit() {
    final total = r.cash + r.qr;
    pw.Widget row(String l, double v, PdfColor c) {
      final share = total <= 0 ? 0.0 : (v / total).clamp(0.0, 1.0);
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(children: [
            pw.Text(l, style: pw.TextStyle(fontSize: 10, font: medium)),
            pw.Spacer(),
            pw.Text('${_m(v)}  ·  ${_pct(share * 100)}', style: const pw.TextStyle(fontSize: 9, color: _muted)),
          ]),
          pw.SizedBox(height: 4),
          pw.Stack(children: [
            pw.Container(height: 8, decoration: pw.BoxDecoration(color: _soft, borderRadius: pw.BorderRadius.circular(4))),
            pw.Container(
              height: 8,
              width: 230 * share,
              decoration: pw.BoxDecoration(color: c, borderRadius: pw.BorderRadius.circular(4)),
            ),
          ]),
        ]),
      );
    }

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      _title('Modes de paiement'),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(12)),
        child: pw.Column(children: [row('Espèces', r.cash, _green), row('QR code', r.qr, _blue)]),
      ),
    ]);
  }

  pw.Widget hours() {
    final peak = r.peakHour;
    final active = [for (var h = 0; h < 24; h++) if (r.byHour[h] != 0) h];
    final from = active.isEmpty ? 8 : active.first;
    final to = active.isEmpty ? 20 : active.last;
    final maxV = r.byHour.fold(0.0, (m, v) => v > m ? v : m);
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      _title('Heures de pointe', hint: peak == null ? null : 'pic à ${peak}h'),
      pw.Container(
        height: 84,
        padding: const pw.EdgeInsets.fromLTRB(10, 10, 10, 6),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(12)),
        child: pw.Column(children: [
          pw.Expanded(
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              for (var h = from; h <= to; h++)
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 1),
                    child: pw.Container(
                      height: maxV <= 0 || r.byHour[h] <= 0 ? 2 : r.byHour[h] / maxV * 44,
                      decoration: pw.BoxDecoration(
                        color: h == peak ? _indigo : _cyan,
                        borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(2)),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          pw.SizedBox(height: 3),
          pw.Row(children: [
            for (var h = from; h <= to; h++)
              pw.Expanded(child: pw.Center(child: pw.Text(((h - from) % 2 == 0) ? '$h' : '', style: const pw.TextStyle(fontSize: 6.5, color: _muted)))),
          ]),
        ]),
      ),
    ]);
  }

  pw.Widget _th(String t, {bool right = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: pw.Text(t.toUpperCase(),
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(fontSize: 7.5, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _td(String t, {bool right = false, PdfColor color = _ink, bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: pw.Text(t,
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
            maxLines: 1,
            style: pw.TextStyle(fontSize: 9.5, color: color, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  pw.Widget topProducts() {
    final top = r.top(15);
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      _title('Meilleures ventes', hint: 'classées par chiffre d\'affaires'),
      if (top.isEmpty)
        pw.Text('Aucune vente sur la période.', style: const pw.TextStyle(color: _muted, fontSize: 10))
      else
        pw.ClipRRect(
          horizontalRadius: 10,
          verticalRadius: 10,
          child: pw.Table(
            columnWidths: const {
              0: pw.FixedColumnWidth(28),
              1: pw.FlexColumnWidth(3.2),
              2: pw.FlexColumnWidth(1.1),
              3: pw.FlexColumnWidth(1.6),
              4: pw.FlexColumnWidth(1.6),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _blue),
                children: [_th('#'), _th('Produit'), _th('Qté', right: true), _th('CA', right: true), _th('Bénéfice', right: true)],
              ),
              for (var i = 0; i < top.length; i++)
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _soft),
                  children: [
                    _td('${i + 1}', color: _muted),
                    _td(top[i].name, bold: i < 3),
                    _td(fmtQty(top[i].qty, unit: top[i].unit), right: true),
                    _td(_m(top[i].revenue), right: true),
                    _td(top[i].profit == 0 ? '–' : _m(top[i].profit), right: true, color: top[i].profit > 0 ? _green : _muted),
                  ],
                ),
            ],
          ),
        ),
    ]);
  }

  pw.Widget sellers() {
    final e = r.bySeller.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = e.fold(0.0, (a, x) => a + x.value);
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      _title('Ventes par vendeur'),
      pw.Wrap(spacing: 10, runSpacing: 10, children: [
        for (final x in e)
          pw.Container(
            width: 160,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: _soft, borderRadius: pw.BorderRadius.circular(12)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(x.key, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text(_m(x.value), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _blue)),
              pw.Text(total <= 0 ? '' : _pct(x.value / total * 100), style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
            ]),
          ),
      ]),
    ]);
  }

  pw.Widget notes() => pw.Text(
        'Le chiffre d\'affaires net tient compte des remises et des retours.'
        '${r.hasUnknownCost ? ' Le bénéfice ne couvre que les articles dont le prix d\'achat est renseigné.' : ''}',
        style: const pw.TextStyle(fontSize: 8, color: _muted),
      );

  pw.Widget miniHeader() => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        margin: const pw.EdgeInsets.only(bottom: 10),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line))),
        child: pw.Row(children: [
          pw.Text(s.storeName.isEmpty ? 'Ma boutique' : s.storeName, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Spacer(),
          pw.Text('Rapport d\'activité · $_range', style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
        ]),
      );

  pw.Widget footer(pw.Context c) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line))),
        child: pw.Row(children: [
          pw.Text('Généré le ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())} avec Caisse POS',
              style: const pw.TextStyle(fontSize: 8, color: _muted)),
          pw.Spacer(),
          pw.Text('Page ${c.pageNumber} / ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
        ]),
      );
}
