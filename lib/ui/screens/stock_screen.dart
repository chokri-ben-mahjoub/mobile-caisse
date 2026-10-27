import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../logic/products_provider.dart';
import '../../logic/settings_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import 'product_form_screen.dart';

enum _Filter { all, low, out, untracked }

/// Stock overview: totals, filters and a quick restock action.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  _Filter _filter = _Filter.all;
  String _query = '';

  // Severity order for the default list: out, low, ok, then untracked.
  static int _rank(Product p) => !p.tracked
      ? 3
      : p.outOfStock
          ? 0
          : p.lowStock
              ? 1
              : 2;

  List<Product> _visible(List<Product> all) {
    final q = _query.trim().toLowerCase();
    final list = all.where((p) {
      if (q.isNotEmpty && !p.name.toLowerCase().contains(q) && !p.barcode.contains(q)) return false;
      return switch (_filter) {
        _Filter.all => true,
        _Filter.low => p.tracked && p.lowStock && !p.outOfStock,
        _Filter.out => p.outOfStock,
        _Filter.untracked => !p.tracked,
      };
    }).toList()
      ..sort((a, b) {
        final r = _rank(a).compareTo(_rank(b));
        return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  Future<void> _restock(Product p) async {
    final prov = context.read<ProductsProvider>();
    var add = true;
    final ctrl = TextEditingController();
    final result = await showDialog<(bool, int)>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        final n = int.tryParse(ctrl.text.trim());
        final next = n == null ? null : (add ? (p.stock ?? 0) + n : n);
        return AlertDialog(
          title: Text(p.name),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Stock actuel : ${p.stock}', style: TextStyle(color: ctx.pal.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Ajouter')),
                ButtonSegment(value: false, label: Text('Corriger')),
              ],
              selected: {add},
              onSelectionChanged: (v) => setSt(() => add = v.first),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setSt(() {}),
              decoration: InputDecoration(labelText: add ? 'Quantité reçue' : 'Nouveau stock'),
            ),
            if (next != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Nouveau stock : $next', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
              onPressed: n == null ? null : () => Navigator.pop(ctx, (add, n)),
              child: const Text('Valider'),
            ),
          ],
        );
      }),
    );
    if (result == null) return;
    final (isAdd, n) = result;
    await (isAdd ? prov.adjustStock(p, n) : prov.setStock(p, n));
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ProductsProvider>();
    final s = context.watch<SettingsProvider>().settings;
    final sum = StockSummary.from(prov.all);
    final items = _visible(prov.all);
    final hasCost = sum.costValue > 0;

    Widget stat(String label, String value, Color color, _Filter f) {
      final selected = _filter == f;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _filter = selected ? _Filter.all : f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: context.pal.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? color : Colors.transparent, width: 2),
              boxShadow: context.pal.shadow,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.pal.muted)),
            ]),
          ),
        ),
      );
    }

    Widget chip(String label, _Filter f) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _filter == f,
            showCheckmark: false,
            onSelected: (_) => setState(() => _filter = f),
          ),
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
          child: Row(children: [
            const Expanded(child: Text('Stock', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5))),
            Text('${sum.units} unités', style: TextStyle(color: context.pal.muted, fontWeight: FontWeight.w700)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TotalBanner(
            label: hasCost ? 'VALEUR DU STOCK (ACHAT)' : 'VALEUR DU STOCK (VENTE)',
            amount: s.money(hasCost ? sum.costValue : sum.saleValue),
            sub: hasCost ? 'Valeur de vente : ${s.money(sum.saleValue)}' : 'Renseignez les prix d\'achat pour la valeur réelle',
            badge: '${sum.tracked} suivis',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            stat('Stock bas', '${sum.low}', const Color(0xFFEA580C), _Filter.low),
            const SizedBox(width: 10),
            stat('Épuisés', '${sum.out}', const Color(0xFFDC2626), _Filter.out),
            const SizedBox(width: 10),
            stat('Non suivis', '${sum.untracked}', context.pal.muted, _Filter.untracked),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(hintText: 'Rechercher un produit', prefixIcon: Icon(Icons.search)),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              chip('Tous (${prov.all.length})', _Filter.all),
              chip('Stock bas', _Filter.low),
              chip('Épuisés', _Filter.out),
              chip('Non suivis', _Filter.untracked),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    prov.all.isEmpty ? 'Aucun produit' : 'Rien à afficher pour ce filtre',
                    style: TextStyle(color: context.pal.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _StockTile(
                    product: items[i],
                    money: s.money,
                    onTap: () => items[i].tracked
                        ? _restock(items[i])
                        : Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(product: items[i]))),
                  ),
                ),
        ),
      ],
    );
  }
}

class _StockTile extends StatelessWidget {
  const _StockTile({required this.product, required this.money, required this.onTap});
  final Product product;
  final String Function(double) money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final pal = context.pal;
    final Color color;
    final String status;
    if (!p.tracked) {
      color = pal.muted;
      status = 'Non suivi';
    } else if (p.outOfStock) {
      color = const Color(0xFFDC2626);
      status = 'Épuisé';
    } else if (p.lowStock) {
      color = const Color(0xFFEA580C);
      status = 'Stock bas';
    } else {
      color = const Color(0xFF16A34A);
      status = 'En stock';
    }
    final level = !p.tracked
        ? 0.0
        : (p.stock! / (p.minStock > 0 ? p.minStock * 3 : (p.stock! > 0 ? p.stock! : 1))).clamp(0.0, 1.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(20), boxShadow: pal.shadow),
          child: Row(children: [
            Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
              child: Text(p.tracked ? '${p.stock}' : '–',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                    child: Text(status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
                  ),
                  if (p.tracked && p.minStock > 0) ...[
                    const SizedBox(width: 8),
                    Text('alerte à ${p.minStock}', style: TextStyle(fontSize: 12, color: pal.muted)),
                  ],
                ]),
                if (p.tracked) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: level,
                      minHeight: 6,
                      color: color,
                      backgroundColor: pal.soft2,
                    ),
                  ),
                  if (p.cost > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Valeur : ${money(p.stock! * p.cost)}', style: TextStyle(fontSize: 12, color: pal.muted)),
                    ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Touchez pour activer le suivi', style: TextStyle(fontSize: 12, color: pal.muted)),
                  ),
              ]),
            ),
            if (p.tracked) Icon(Icons.add_circle_outline_rounded, color: pal.accent, size: 28),
          ]),
        ),
      ),
    );
  }
}
