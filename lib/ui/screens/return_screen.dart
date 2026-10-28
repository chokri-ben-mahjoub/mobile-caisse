import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/printer_service.dart';
import '../../data/settings_store.dart';
import '../../logic/auth_provider.dart';
import '../../logic/products_provider.dart';
import '../../logic/sales_provider.dart';
import '../../logic/settings_provider.dart';
import '../theme.dart';
import '../widgets.dart';

const _reasons = ['Erreur de caisse', 'Article défectueux', 'Client mécontent', 'Autre'];

/// Return of items, or cancellation of a whole ticket (select everything).
/// Creates a negative ticket linked to the original: totals, profit, cash
/// closing and stock all follow.
class ReturnScreen extends StatefulWidget {
  const ReturnScreen({super.key, required this.sale, required this.returned});
  final Sale sale;

  /// Quantities already returned for this sale (barcode -> positive quantity).
  final Map<String, double> returned;

  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  late final Map<String, double> _left = Sale.returnable(widget.sale, widget.returned);
  final Map<String, double> _qty = {};
  final Map<String, TextEditingController> _ctrls = {};
  String _reason = _reasons.first;
  bool _restock = true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _selected(String barcode) => _qty[barcode] ?? 0;

  void _set(SaleLine l, double v) {
    final max = _left[l.barcode] ?? 0;
    final q = round3(v.clamp(0, max).toDouble());
    setState(() {
      _qty[l.barcode] = q;
      if (l.byWeight) _ctrls[l.barcode]?.text = q == 0 ? '' : fmtQty(q);
    });
  }

  void _selectAll() {
    for (final l in widget.sale.lines) {
      _set(l, _left[l.barcode] ?? 0);
    }
  }

  Sale get _preview => Sale.refundOf(widget.sale, _qty, date: DateTime.now());
  bool get _any => _qty.values.any((v) => v > 0);

  Future<void> _confirm() async {
    final s = context.read<SettingsProvider>().settings;
    final refund = Sale.refundOf(
      widget.sale,
      _qty,
      date: DateTime.now(),
      seller: context.read<AuthProvider>().currentName,
      reason: _reason,
      restock: _restock,
    );
    final method = widget.sale.method == PayMethod.cash ? 'espèces' : widget.sale.method == PayMethod.credit ? 'crédit' : 'QR code';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Valider le retour ?'),
        content: Text('Rembourser ${s.money(refund.total.abs())} ($method) au client.\n'
            '${_restock ? 'Les articles sont remis en stock.' : 'Les articles ne sont pas remis en stock.'}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44), backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    final sales = context.read<SalesProvider>();
    final products = context.read<ProductsProvider>();
    final printer = context.read<PrinterService>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final saved = await sales.record(refund);
    await products.load(); // stock changed
    nav.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Retour enregistré : ${s.money(saved.total.abs())} à rembourser'),
        action: SnackBarAction(
          label: 'Imprimer',
          onPressed: () async {
            final err = await printer.printSale(saved, s);
            if (err != null) messenger.showSnackBar(SnackBar(content: Text(err)));
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().settings;
    final pal = context.pal;
    final preview = _any ? _preview : null;

    return Scaffold(
      appBar: AppBar(title: Text('Retour · ticket ${widget.sale.id}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Row(children: [
            Expanded(
              child: Text('Choisissez les articles rendus par le client.',
                  style: TextStyle(color: pal.muted, fontWeight: FontWeight.w600)),
            ),
            TextButton(onPressed: _selectAll, child: const Text('Tout rendre')),
          ]),
          const SizedBox(height: 6),
          for (final l in widget.sale.lines) _lineCard(l, s),
          const SizedBox(height: 14),
          Text('Motif', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: pal.ink)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final r in _reasons)
              ChoiceChip(
                label: Text(r),
                selected: _reason == r,
                showCheckmark: false,
                onSelected: (_) => setState(() => _reason = r),
              ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Remettre en stock', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('À désactiver si l\'article est abîmé'),
            value: _restock,
            onChanged: (v) => setState(() => _restock = v),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: pal.badBg, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              Text('À rembourser', style: TextStyle(fontWeight: FontWeight.w800, color: pal.badFg)),
              const Spacer(),
              Text(s.money(preview == null ? 0 : preview.total.abs()),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: pal.badFg)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Remboursement ${widget.sale.method == PayMethod.cash ? 'en espèces' : 'par QR code'}'
              '${widget.sale.discount > 0 ? ' · remise du ticket déduite au prorata' : ''}',
              style: TextStyle(color: pal.muted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            icon: Icons.assignment_return_rounded,
            label: 'Valider le retour',
            onPressed: (_any && !_saving) ? _confirm : null,
          ),
        ],
      ),
    );
  }

  Widget _lineCard(SaleLine l, AppSettings s) {
    final pal = context.pal;
    final left = _left[l.barcode] ?? 0;
    final done = round3(l.qty - left);
    final q = _selected(l.barcode);

    Widget stepper() => Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: pal.soft2, borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _stepBtn(Icons.remove_rounded, q > 0 ? () => _set(l, q - 1) : null),
            SizedBox(
              width: 34,
              child: Text(fmtQty(q), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            ),
            _stepBtn(Icons.add_rounded, q < left ? () => _set(l, q + 1) : null, filled: true),
          ]),
        );

    Widget weightField() {
      final c = _ctrls.putIfAbsent(l.barcode, () => TextEditingController());
      return SizedBox(
        width: 110,
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          onChanged: (v) {
            final n = double.tryParse(v.trim().replaceAll(',', '.')) ?? 0;
            setState(() => _qty[l.barcode] = round3(n.clamp(0, left).toDouble()));
          },
          decoration: const InputDecoration(labelText: 'Poids', suffixText: 'kg', isDense: true),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: pal.shadow,
          border: q > 0 ? Border.all(color: pal.badFg, width: 1.5) : null,
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                'Vendu ${fmtQty(l.qty, unit: l.unit)} · ${s.money(l.price)}${l.byWeight ? '/kg' : ''}'
                '${done > 0 ? ' · déjà rendu ${fmtQty(done, unit: l.unit)}' : ''}',
                style: TextStyle(color: pal.muted, fontSize: 12.5),
              ),
              if (left <= 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Tout a été rendu', style: TextStyle(color: pal.badFg, fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
            ]),
          ),
          if (left > 0) ...[
            const SizedBox(width: 8),
            l.byWeight ? weightField() : stepper(),
          ],
        ]),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap, {bool filled = false}) => Material(
        color: filled ? (onTap == null ? context.pal.soft : kBlue) : context.pal.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 22, color: filled ? Colors.white : (onTap == null ? context.pal.muted : context.pal.accent)),
          ),
        ),
      );
}
