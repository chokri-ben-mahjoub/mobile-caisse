import 'package:flutter/material.dart' hide Text;
import '../i18n/text.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models.dart';
import '../../data/pdf_report.dart';
import '../../data/report.dart';
import '../../data/report_service.dart';
import '../../data/settings_store.dart';
import '../../logic/settings_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import '../i18n/tr.dart';
import '../i18n/date_fmt.dart';

/// Activity statistics over a period, with a polished PDF export.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  StatPeriod _period = StatPeriod.week;
  (DateTime, DateTime)? _custom;
  Report? _report;
  Report? _prev;
  bool _exporting = false;
  int? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) get _range => _period.range(DateTime.now(), custom: _custom);

  Future<void> _load() async {
    final svc = context.read<ReportService>();
    final (a, b) = _range;
    final r = await svc.load(a, b);
    final p = await svc.loadPrevious(a, b);
    if (!mounted) return;
    setState(() {
      _report = r;
      _prev = p;
      _selected = null;
    });
  }

  Future<void> _pick(StatPeriod p) async {
    if (p == StatPeriod.custom) {
      final now = DateTime.now();
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 3),
        lastDate: now,
        initialDateRange: DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
        locale: Localizations.localeOf(context),
      );
      if (r == null) return;
      final s = DateTime(r.start.year, r.start.month, r.start.day);
      final e = DateTime(r.end.year, r.end.month, r.end.day).add(const Duration(days: 1));
      if (e.difference(s).inDays > 366) {
        if (mounted) showMsg(context, 'Période limitée à un an');
        return;
      }
      _custom = (s, e);
    }
    setState(() => _period = p);
    await _load();
  }

  String get _label {
    final (a, b) = _range;
    final f = DateFmt('dd/MM/yyyy');
    final last = b.subtract(const Duration(days: 1));
    return a.year == last.year && a.month == last.month && a.day == last.day ? f.format(a) : '${f.format(a)} → ${f.format(last)}';
  }

  Future<void> _export() async {
    final r = _report;
    if (r == null || _exporting) return;
    final settings = context.read<SettingsProvider>().settings;
    setState(() => _exporting = true);
    try {
      final bytes = await PdfReport.build(report: r, previous: _prev, settings: settings, periodLabel: _period.label);
      final stamp = DateFormat('yyyyMMdd').format(r.start);
      final f = await PdfReport.save(bytes, 'rapport_$stamp.pdf');
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/pdf')], subject: 'Rapport d\'activité'));
    } catch (e) {
      if (mounted) showMsg(context, 'Export impossible : $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().settings;
    final pal = context.pal;
    final r = _report;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiques'),
        actions: [
          IconButton(
            tooltip: tr('Exporter en PDF'),
            onPressed: r == null || _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.picture_as_pdf_rounded),
          ),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            children: [
              for (final p in StatPeriod.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(p.label),
                    selected: _period == p,
                    showCheckmark: false,
                    onSelected: (_) => _pick(p),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: r == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10, left: 4),
                      child: Text(_label, style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700)),
                    ),
                    _hero(r, s),
                    const SizedBox(height: 12),
                    _kpis(r, s),
                    const SizedBox(height: 12),
                    _chart(r, s),
                    const SizedBox(height: 12),
                    _payments(r, s),
                    const SizedBox(height: 12),
                    _top(r, s),
                    if (r.peakHour != null) ...[const SizedBox(height: 12), _hours(r)],
                    if (r.bySeller.isNotEmpty) ...[const SizedBox(height: 12), _sellers(r, s)],
                    if (r.hasUnknownCost)
                      Padding(
                        padding: const EdgeInsets.only(top: 12, left: 4),
                        child: Text('Le bénéfice ne couvre que les articles dont le prix d\'achat est renseigné.',
                            style: TextStyle(color: pal.muted, fontSize: 12)),
                      ),
                  ],
                ),
        ),
      ]),
      bottomNavigationBar: r == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: PrimaryButton(
                  icon: Icons.picture_as_pdf_rounded,
                  label: _exporting ? 'Création du PDF…' : 'Exporter le rapport PDF',
                  onPressed: _exporting || r.isEmpty ? null : _export,
                ),
              ),
            ),
    );
  }

  Widget _hero(Report r, AppSettings s) {
    final g = _prev == null ? null : r.growthVs(_prev!);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: kHeroGradient, borderRadius: BorderRadius.circular(24), boxShadow: context.pal.shadow),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('CHIFFRE D\'AFFAIRES NET', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(s.money(r.net), style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          _pill('Bénéfice ${s.money(r.profit)}', Colors.white24, Colors.white),
          if (g != null)
            _pill('${g >= 0 ? '▲ +' : '▼ −'}${g.abs().toStringAsFixed(1).replaceAll('.', ',')} % vs période préc.',
                Colors.white, g >= 0 ? const Color(0xFF15803D) : const Color(0xFFB91C1C)),
        ]),
      ]),
    );
  }

  Widget _pill(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13)),
      );

  Widget _kpis(Report r, AppSettings s) {
    Widget tile(IconData i, String l, String v, {String? sub, Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: context.pal.card, borderRadius: BorderRadius.circular(20), boxShadow: context.pal.shadow),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(i, size: 20, color: color ?? context.pal.accent),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(v, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color ?? context.pal.ink)),
              ),
              Text(l, style: TextStyle(color: context.pal.muted, fontSize: 12, fontWeight: FontWeight.w600)),
              if (sub != null) Text(sub, style: TextStyle(color: context.pal.muted, fontSize: 11)),
            ]),
          ),
        );
    return Column(children: [
      Row(children: [
        tile(Icons.receipt_long_rounded, 'Tickets', '${r.salesCount}', sub: 'panier ${s.money(r.avgBasket)}'),
        const SizedBox(width: 10),
        tile(Icons.trending_up_rounded, 'Marge', r.net > 0 ? '${r.margin.toStringAsFixed(1).replaceAll('.', ',')} %' : '–',
            color: context.pal.goodFg),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        tile(Icons.sell_outlined, 'Remises', s.money(r.discounts)),
        const SizedBox(width: 10),
        tile(Icons.assignment_return_outlined, 'Retours', r.refundsCount == 0 ? s.money(0) : '−${s.money(r.refunds)}',
            sub: r.refundsCount == 0 ? null : '${r.refundsCount} retour${r.refundsCount > 1 ? 's' : ''}',
            color: r.refundsCount == 0 ? null : context.pal.badFg),
      ]),
    ]);
  }

  Widget _chart(Report r, AppSettings s) {
    final pal = context.pal;
    final days = r.days;
    final sel = _selected != null && _selected! < days.length ? days[_selected!] : null;
    final maxV = days.fold(0.0, (m, d) => d.revenue > m ? d.revenue : m);
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Évolution', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: pal.ink)),
          const Spacer(),
          Text(sel == null ? 'Touchez une barre' : '${DateFmt('EEE d MMM').format(sel.day)} · ${s.money(sel.revenue)}',
              style: TextStyle(color: sel == null ? pal.muted : pal.accent, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          height: 150,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < days.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selected = _selected == i ? null : i),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: days.length > 20 ? 1 : 3),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        height: maxV <= 0 || days[i].revenue <= 0 ? 4 : 6 + days[i].revenue / maxV * 144,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                          color: _selected == i
                              ? kBlue
                              : (days[i].revenue == maxV && maxV > 0 ? const Color(0xFF5B34D6) : pal.soft),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Text(DateFmt('d MMM').format(days.first.day), style: TextStyle(color: pal.muted, fontSize: 11)),
          const Spacer(),
          Text(DateFmt('d MMM').format(days.last.day), style: TextStyle(color: pal.muted, fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _bar(String l, double v, double total, Color c, String value) {
    final share = total <= 0 ? 0.0 : (v / total).clamp(0.0, 1.0);
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(l, style: TextStyle(fontWeight: FontWeight.w700, color: pal.ink)),
          const Spacer(),
          Text(value, style: TextStyle(color: pal.muted, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: share, minHeight: 9, color: c, backgroundColor: pal.soft2),
        ),
      ]),
    );
  }

  Widget _payments(Report r, AppSettings s) {
    final total = r.cash + r.qr;
    String pct(double v) => total <= 0 ? '0 %' : '${(v / total * 100).round()} %';
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Modes de paiement', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.pal.ink)),
        _bar('Espèces', r.cash, total, context.pal.goodFg, '${s.money(r.cash)} · ${pct(r.cash)}'),
        _bar('QR code', r.qr, total, kBlue, '${s.money(r.qr)} · ${pct(r.qr)}'),
      ]),
    );
  }

  Widget _top(Report r, AppSettings s) {
    final pal = context.pal;
    final top = r.top(8);
    final best = top.isEmpty ? 0.0 : top.first.revenue;
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Meilleures ventes', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: pal.ink)),
        if (top.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 10), child: Text('Aucune vente sur la période', style: TextStyle(color: pal.muted))),
        for (var i = 0; i < top.length; i++)
          _bar('${i + 1}. ${top[i].name}', top[i].revenue, best, i == 0 ? const Color(0xFF5B34D6) : kBlue,
              '${fmtQty(top[i].qty, unit: top[i].unit)} · ${s.money(top[i].revenue)}'),
      ]),
    );
  }

  Widget _hours(Report r) {
    final pal = context.pal;
    final peak = r.peakHour!;
    final maxV = r.byHour.fold(0.0, (m, v) => v > m ? v : m);
    final active = [for (var h = 0; h < 24; h++) if (r.byHour[h] != 0) h];
    final from = active.first, to = active.last;
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Heures de pointe', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: pal.ink)),
          const Spacer(),
          Text('pic à ${peak}h', style: TextStyle(color: pal.accent, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 80,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var h = from; h <= to; h++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: maxV <= 0 || r.byHour[h] <= 0 ? 3 : 4 + r.byHour[h] / maxV * 76,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        color: h == peak ? const Color(0xFF5B34D6) : const Color(0xFF22D3EE),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text('${from}h', style: TextStyle(color: pal.muted, fontSize: 11)),
          const Spacer(),
          Text('${to}h', style: TextStyle(color: pal.muted, fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _sellers(Report r, AppSettings s) {
    final e = r.bySeller.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = e.fold(0.0, (a, x) => a + x.value);
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Par vendeur', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.pal.ink)),
        for (final x in e) _bar(x.key, x.value, total, kBlue, s.money(x.value)),
      ]),
    );
  }
}
