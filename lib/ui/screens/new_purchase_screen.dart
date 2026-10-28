import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/purchase.dart';
import '../../logic/products_provider.dart';
import '../../logic/purchases_provider.dart';
import '../../logic/settings_provider.dart';
import '../theme.dart';
import '../widgets.dart';

enum _Pay { full, partial, credit }

/// One line being edited: the product, with its quantity and purchase price fields.
class _Line {
  _Line(this.product)
      : qty = TextEditingController(text: '1'),
        cost = TextEditingController(text: product.cost > 0 ? _fmt(product.cost) : '');
  final Product product;
  final TextEditingController qty;
  final TextEditingController cost;

  static String _fmt(double v) => v.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '').replaceAll('.', ',');
  static double _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  double get q => _num(qty);
  double get c => _num(cost);
  double get total => round3(q * c);
  bool get valid => q > 0 && c > 0;

  void dispose() {
    qty.dispose();
    cost.dispose();
  }
}

/// New goods receipt: supplier, products with quantity and purchase price, payment.
class NewPurchaseScreen extends StatefulWidget {
  const NewPurchaseScreen({super.key});

  @override
  State<NewPurchaseScreen> createState() => _NewPurchaseScreenState();
}

class _NewPurchaseScreenState extends State<NewPurchaseScreen> {
  final _supplier = TextEditingController();
  final _phone = TextEditingController();
  final _invoice = TextEditingController();
  final _paid = TextEditingController();
  final _lines = <_Line>[];
  _Pay _pay = _Pay.full;
  bool _saving = false;

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _supplier.dispose();
    _phone.dispose();
    _invoice.dispose();
    _paid.dispose();
    super.dispose();
  }

  double get _total => round3(_lines.fold(0.0, (s, l) => s + l.total));
  double get _paidNow => switch (_pay) {
        _Pay.full => _total,
        _Pay.credit => 0,
        _Pay.partial => (double.tryParse(_paid.text.trim().replaceAll(',', '.')) ?? 0).clamp(0, _total).toDouble(),
      };

  Future<void> _addProduct() async {
    final picked = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductPicker(exclude: {for (final l in _lines) l.product.barcode}),
    );
    if (picked == null) return;
    setState(() => _lines.add(_Line(picked)));
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_supplier.text.trim().isEmpty) return showMsg(context, 'Indiquez le fournisseur');
    if (_lines.isEmpty) return showMsg(context, 'Ajoutez au moins un produit');
    if (_lines.any((l) => !l.valid)) return showMsg(context, 'Renseignez la quantité et le prix d\'achat de chaque produit');
    setState(() => _saving = true);
    final purchase = Purchase(
      date: DateTime.now(),
      supplier: _supplier.text.trim(),
      phone: _phone.text.trim(),
      invoice: _invoice.text.trim(),
      paid: _paidNow,
      lines: [
        for (final l in _lines)
          PurchaseLine(barcode: l.product.barcode, name: l.product.name, qty: l.q, cost: l.c, unit: l.product.unit),
      ],
    );
    final purchases = context.read<PurchasesProvider>();
    final products = context.read<ProductsProvider>();
    final settings = context.read<SettingsProvider>().settings;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await purchases.add(purchase);
    await products.load(); // stock and purchase prices changed
    HapticFeedback.mediumImpact();
    nav.pop();
    messenger.showSnackBar(SnackBar(
        content: Text('Réception enregistrée · ${purchase.articles} article${purchase.articles > 1 ? 's' : ''} en stock'
            '${purchase.owed > 0 ? ' · reste ${settings.money(purchase.owed)} à payer' : ''}')));
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final s = context.watch<SettingsProvider>().settings;
    final accounts = context.watch<PurchasesProvider>().accounts;
    final typed = _supplier.text.trim().toLowerCase();
    final suggestions = accounts.where((a) => typed.isEmpty || (a.name.toLowerCase().contains(typed) && a.name.toLowerCase() != typed)).take(8).toList();
    final owed = round3(_total - _paidNow);

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvel achat')),
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              SoftCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Fournisseur', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _supplier,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Nom du fournisseur', prefixIcon: Icon(Icons.storefront_rounded)),
                  ),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final a in suggestions)
                        ActionChip(
                          label: Text(a.name),
                          onPressed: () => setState(() {
                            _supplier.text = a.name;
                            _phone.text = a.phone;
                          }),
                        ),
                    ]),
                  ],
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Téléphone', prefixIcon: Icon(Icons.phone_rounded)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _invoice,
                        decoration: const InputDecoration(labelText: 'N° bon / facture', prefixIcon: Icon(Icons.tag_rounded)),
                      ),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: Text('Produits reçus', style: TextStyle(color: pal.muted, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
                ),
                FilledButton.tonalIcon(
                  onPressed: _addProduct,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Ajouter'),
                ),
              ]),
              const SizedBox(height: 8),
              if (_lines.isEmpty)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _addProduct,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: pal.border, width: 1.5),
                    ),
                    child: Column(children: [
                      Icon(Icons.add_box_rounded, size: 34, color: pal.accent),
                      const SizedBox(height: 6),
                      Text('Touchez pour ajouter un produit', style: TextStyle(color: pal.muted, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
              for (var i = 0; i < _lines.length; i++)
                Dismissible(
                  key: ObjectKey(_lines[i]),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.only(right: 22),
                    alignment: Alignment.centerRight,
                    decoration: BoxDecoration(color: pal.badBg, borderRadius: BorderRadius.circular(20)),
                    child: Icon(Icons.delete_rounded, color: pal.badFg),
                  ),
                  onDismissed: (_) => setState(() => _lines.removeAt(i).dispose()),
                  child: _lineCard(context, _lines[i], s.money),
                ),
              if (_lines.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Paiement', style: TextStyle(color: pal.muted, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
                const SizedBox(height: 8),
                SegmentedButton<_Pay>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: _Pay.full, icon: Icon(Icons.check_circle_outline_rounded), label: Text('Payé')),
                    ButtonSegment(value: _Pay.partial, icon: Icon(Icons.timelapse_rounded), label: Text('Acompte')),
                    ButtonSegment(value: _Pay.credit, icon: Icon(Icons.schedule_rounded), label: Text('À crédit')),
                  ],
                  selected: {_pay},
                  onSelectionChanged: (v) => setState(() => _pay = v.first),
                ),
                if (_pay == _Pay.partial) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _paid,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: 'Montant payé maintenant', suffixText: s.currency),
                  ),
                ],
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(color: pal.card, boxShadow: pal.shadow),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_lines.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Text('${_lines.length} produit${_lines.length > 1 ? 's' : ''}', style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (owed > 0.0005)
                      Text('Reste ${s.money(owed)} à payer', style: TextStyle(color: pal.badFg, fontWeight: FontWeight.w900))
                    else
                      Text('Entièrement payé', style: TextStyle(color: pal.goodFg, fontWeight: FontWeight.w900)),
                  ]),
                ),
              PrimaryButton(
                onPressed: _saving ? null : _save,
                icon: Icons.inventory_rounded,
                label: 'Enregistrer la réception',
                trailing: s.money(_total),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _lineCard(BuildContext context, _Line l, String Function(double) money) {
    final pal = context.pal;
    final p = l.product;
    final old = p.cost;
    final diff = old > 0 && l.c > 0 ? (l.c - old) / old : null;
    final stockAfter = round3((p.stock ?? 0) + l.q);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            Text(money(l.total), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: pal.accent)),
          ]),
          const SizedBox(height: 2),
          Text(
            'Stock : ${fmtQty(p.stock ?? 0, unit: p.unit)} → ${fmtQty(stockAfter, unit: p.unit)}',
            style: TextStyle(color: pal.goodFg, fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: l.qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: 'Quantité', suffixText: p.unit.isEmpty ? null : p.unit, isDense: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: l.cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: 'Prix d\'achat', suffixText: p.unit == 'kg' ? '/kg' : null, isDense: true),
              ),
            ),
          ]),
          if (diff != null && diff.abs() >= 0.005)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Icon(diff > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 16, color: diff > 0 ? pal.badFg : pal.goodFg),
                const SizedBox(width: 4),
                Text(
                  '${diff > 0 ? '+' : ''}${(diff * 100).toStringAsFixed(1).replaceAll('.', ',')} % vs dernier achat (${money(old)})',
                  style: TextStyle(color: diff > 0 ? pal.badFg : pal.goodFg, fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ]),
            ),
          if (l.c > 0 && p.price > 0 && p.price <= l.c)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('⚠ Prix de vente (${money(p.price)}) inférieur ou égal au prix d\'achat',
                  style: TextStyle(color: pal.badFg, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}

/// Searchable catalogue to pick the product received.
class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.exclude});
  final Set<String> exclude;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final q = _q.trim().toLowerCase();
    final list = context
        .watch<ProductsProvider>()
        .all
        .where((p) => !widget.exclude.contains(p.barcode) && (q.isEmpty || p.name.toLowerCase().contains(q) || p.barcode.contains(q)))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(hintText: 'Nom ou code-barres', prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text('Aucun produit', style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700)))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final p = list[i];
                      return ListTile(
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text('Stock : ${p.tracked ? fmtQty(p.stock!, unit: p.unit) : 'non suivi'}'),
                        trailing: p.lowStock ? Icon(Icons.warning_amber_rounded, color: pal.badFg) : null,
                        onTap: () => Navigator.pop(context, p),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
