import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/closing_service.dart';
import '../../data/models.dart';
import '../../data/printer_service.dart';
import '../../data/settings_store.dart';
import '../../logic/auth_provider.dart';
import '../../logic/settings_provider.dart';
import '../theme.dart';
import '../widgets.dart';

final _stamp = DateFormat('dd/MM HH:mm');

double? _parse(String v) => double.tryParse(v.trim().replaceAll(',', '.'));

/// "+1,500" / "-2,000" / "0,000": a signed amount for cash differences.
String _signed(AppSettings s, double v) => '${v > 0 ? '+' : ''}${s.money(v)}';

Widget _row(BuildContext context, String label, String value, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: bold ? null : context.pal.muted)),
        ),
        Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w700, fontSize: bold ? 17 : 15, color: color)),
      ]),
    );

/// Outcome of the till count, with colour: exact, too much, or missing.
({String text, Color color}) _diffLook(BuildContext context, AppSettings s, double diff) {
  if (diff.abs() < 0.0005) return (text: 'Caisse juste', color: context.pal.goodFg);
  return diff > 0
      ? (text: '${_signed(s, diff)} en trop', color: const Color(0xFFEA580C))
      : (text: '${s.money(diff.abs())} manquant', color: context.pal.badFg);
}

/// Cash closing: totals since the last closing and the till count.
class ClosingScreen extends StatefulWidget {
  const ClosingScreen({super.key});

  @override
  State<ClosingScreen> createState() => _ClosingScreenState();
}

class _ClosingScreenState extends State<ClosingScreen> {
  final _opening = TextEditingController();
  final _counted = TextEditingController();
  final _left = TextEditingController();
  final _note = TextEditingController();

  DateTime? _start;
  late DateTime _end = DateTime.now();
  ClosingSummary? _summary;
  bool _saving = false;
  bool _leftTouched = false;

  @override
  void initState() {
    super.initState();
    _load(firstTime: true);
  }

  Future<void> _load({bool firstTime = false}) async {
    final svc = context.read<ClosingService>();
    final start = await svc.periodStart();
    final end = DateTime.now();
    final summary = await svc.summary(start, end);
    final float = firstTime ? await svc.suggestedFloat() : null;
    if (!mounted) return;
    setState(() {
      _start = start;
      _end = end;
      _summary = summary;
      if (float != null) {
        _opening.text = float == 0 ? '' : _fmt(float);
      }
    });
  }

  static String _fmt(double v) => v.toString().replaceAll('.', ',');

  double get _openingValue => _parse(_opening.text) ?? 0;
  double get _expected => ClosingService.expectedCash(_openingValue, _summary!);

  Future<void> _validate() async {
    final s = context.read<SettingsProvider>().settings;
    final counted = _parse(_counted.text);
    if (counted == null) {
      showMsg(context, 'Entrez les espèces comptées dans la caisse.');
      return;
    }
    final diff = round3(counted - _expected);
    final look = _diffLook(context, s, diff);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Valider la clôture ?'),
        content: Text('Total net : ${s.money(_summary!.net)}\n'
            'Espèces attendues : ${s.money(_expected)}\n'
            'Espèces comptées : ${s.money(counted)}\n'
            'Résultat : ${look.text}\n\n'
            'La clôture ne peut plus être modifiée. Les ventes suivantes iront dans la prochaine.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final svc = context.read<ClosingService>();
    final user = context.read<AuthProvider>().currentName;
    final nav = Navigator.of(context);
    final closing = await svc.close(
      start: _start!,
      end: _end,
      openingFloat: _openingValue,
      countedCash: counted,
      floatLeft: _parse(_left.text) ?? (_leftTouched ? 0 : _openingValue),
      user: user,
      note: _note.text,
    );
    nav.pushReplacement(MaterialPageRoute(builder: (_) => ClosingDetailScreen(closing: closing, justClosed: true)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().settings;
    final sum = _summary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clôture de caisse'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
          IconButton(
            tooltip: 'Clôtures précédentes',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClosingsListScreen())),
          ),
        ],
      ),
      body: sum == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                TotalBanner(
                  label: 'TOTAL NET',
                  amount: s.money(sum.net),
                  sub: 'Depuis ${_stamp.format(_start!)} · arrêté à ${DateFormat('HH:mm').format(_end)}',
                  badge: '${sum.salesCount} vente${sum.salesCount > 1 ? 's' : ''}',
                ),
                const SizedBox(height: 14),
                SoftCard(
                  child: Column(children: [
                    _row(context, 'Ventes', s.money(sum.gross)),
                    if (sum.discounts > 0) _row(context, 'Remises', '−${s.money(sum.discounts)}'),
                    if (sum.refundsCount > 0)
                      _row(context, 'Retours (${sum.refundsCount})', '−${s.money(sum.refunds)}', color: context.pal.badFg),
                    const Divider(height: 18),
                    _row(context, 'Espèces', s.money(sum.cash)),
                    _row(context, 'QR code', s.money(sum.qr)),
                    _row(context, 'Bénéfice', s.money(sum.profit)),
                    if (sum.bySeller.isNotEmpty) ...[
                      const Divider(height: 18),
                      for (final e in sum.bySeller.entries) _row(context, e.key, s.money(e.value)),
                    ],
                  ]),
                ),
                const SizedBox(height: 14),
                SoftCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Caisse espèces', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    _moneyField(_opening, 'Fond de caisse (début)', s),
                    const SizedBox(height: 4),
                    _row(context, 'Espèces attendues', s.money(_expected), bold: true),
                    const SizedBox(height: 8),
                    _moneyField(_counted, 'Espèces comptées', s, autofocus: true),
                    const SizedBox(height: 12),
                    _diffBox(s),
                    const SizedBox(height: 12),
                    _moneyField(_left, 'Laissé en caisse pour demain', s, onTouched: () => _leftTouched = true),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _note,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Note (facultatif)'),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                Text('Ne faites plus de vente pendant la clôture : elles iraient dans la suivante.',
                    style: TextStyle(color: context.pal.muted, fontSize: 12)),
                const SizedBox(height: 14),
                PrimaryButton(
                  icon: Icons.lock_clock_rounded,
                  label: 'Valider la clôture',
                  onPressed: _saving ? null : _validate,
                ),
              ],
            ),
    );
  }

  Widget _moneyField(TextEditingController c, String label, AppSettings s,
          {bool autofocus = false, VoidCallback? onTouched}) =>
      TextField(
        controller: c,
        autofocus: autofocus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        onChanged: (_) {
          onTouched?.call();
          setState(() {});
        },
        decoration: InputDecoration(labelText: label, suffixText: s.currency),
      );

  Widget _diffBox(AppSettings s) {
    final counted = _parse(_counted.text);
    if (counted == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: context.pal.soft2, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, color: context.pal.muted),
          const SizedBox(width: 10),
          Expanded(child: Text('Comptez les espèces pour voir l\'écart', style: TextStyle(color: context.pal.muted))),
        ]),
      );
    }
    final diff = round3(counted - _expected);
    final look = _diffLook(context, s, diff);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: look.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Text('Écart', style: TextStyle(fontWeight: FontWeight.w700, color: look.color)),
        const Spacer(),
        Text(look.text, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: look.color)),
      ]),
    );
  }
}

/// A saved closing: read-only report that can be printed.
class ClosingDetailScreen extends StatelessWidget {
  const ClosingDetailScreen({super.key, required this.closing, this.justClosed = false});
  final CashClosing closing;
  final bool justClosed;

  Future<void> _print(BuildContext context) async {
    final s = context.read<SettingsProvider>().settings;
    final err = await context.read<PrinterService>().printClosing(closing, s);
    if (context.mounted) showMsg(context, err ?? 'Rapport imprimé');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().settings;
    final c = closing;
    final look = _diffLook(context, s, c.difference);

    return Scaffold(
      appBar: AppBar(title: Text(justClosed ? 'Caisse clôturée' : 'Clôture du ${DateFormat('dd/MM/yyyy').format(c.closedAt)}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (justClosed)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: context.pal.goodBg, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Icon(Icons.check_circle_rounded, color: context.pal.goodFg),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Clôture enregistrée. Imprimez le rapport Z pour le classer.',
                      style: TextStyle(color: context.pal.goodFg, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          TotalBanner(
            label: 'TOTAL NET',
            amount: s.money(c.net),
            sub: '${_stamp.format(c.periodStart)} → ${_stamp.format(c.closedAt)}',
            badge: '${c.salesCount} vente${c.salesCount > 1 ? 's' : ''}',
          ),
          const SizedBox(height: 14),
          SoftCard(
            child: Column(children: [
              _row(context, 'Ventes', s.money(c.gross)),
              if (c.discounts > 0) _row(context, 'Remises', '−${s.money(c.discounts)}'),
              if (c.refundsCount > 0) _row(context, 'Retours (${c.refundsCount})', '−${s.money(c.refunds)}'),
              const Divider(height: 18),
              _row(context, 'Espèces', s.money(c.cash)),
              _row(context, 'QR code', s.money(c.qr)),
              _row(context, 'Bénéfice', s.money(c.profit)),
            ]),
          ),
          const SizedBox(height: 14),
          SoftCard(
            child: Column(children: [
              _row(context, 'Fond de caisse', s.money(c.openingFloat)),
              _row(context, 'Espèces attendues', s.money(c.expectedCash)),
              _row(context, 'Espèces comptées', s.money(c.countedCash)),
              _row(context, 'Écart', look.text, bold: true, color: look.color),
              _row(context, 'Laissé en caisse', s.money(c.floatLeft)),
              if (c.user != null) _row(context, 'Clôturé par', c.user!),
              if (c.note != null) _row(context, 'Note', c.note!),
            ]),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _print(context),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimer le rapport Z'),
          ),
        ],
      ),
    );
  }
}

/// Previous closings, newest first.
class ClosingsListScreen extends StatelessWidget {
  const ClosingsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().settings;
    final pal = context.pal;

    return Scaffold(
      appBar: AppBar(title: const Text('Clôtures précédentes')),
      body: FutureBuilder<List<CashClosing>>(
        future: context.read<ClosingService>().history(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) {
            return Center(child: Text('Aucune clôture pour le moment', style: TextStyle(color: pal.muted)));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final c = list[i];
              final look = _diffLook(context, s, c.difference);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClosingDetailScreen(closing: c))),
                  child: Ink(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(20), boxShadow: pal.shadow),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_stamp.format(c.closedAt), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          Text('${c.salesCount} vente${c.salesCount > 1 ? 's' : ''}${c.user != null ? ' · ${c.user}' : ''}',
                              style: TextStyle(color: pal.muted, fontSize: 13)),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(s.money(c.net), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        Text(look.text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: look.color)),
                      ]),
                    ]),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
