import 'package:flutter/material.dart' hide Text;
import '../i18n/text.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../data/barcode_utils.dart';
import '../../data/models.dart';
import '../../logic/products_provider.dart';
import '../theme.dart';
import '../i18n/tr.dart';

/// Add or edit a product. Pops the saved [Product] (null if cancelled).
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product, this.barcode});
  final Product? product;
  final String? barcode;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _barcode = TextEditingController(text: widget.product?.barcode ?? widget.barcode ?? '');
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _price = TextEditingController(text: _fmt(widget.product?.price));
  late final _cost = TextEditingController(text: (widget.product?.cost ?? 0) > 0 ? _fmt(widget.product!.cost) : '');
  late bool _track = widget.product?.tracked ?? false;
  late bool _byWeight = widget.product?.byWeight ?? false;
  late bool _favorite = widget.product?.favorite ?? false;
  late final _stock = TextEditingController(text: widget.product?.stock == null ? '' : fmtQty(widget.product!.stock!));
  late final _minStock = TextEditingController(text: (widget.product?.minStock ?? 0).toString());

  bool get _editing => widget.product != null;

  static String _fmt(double? v) => v == null ? '' : v.toString().replaceAll('.', ',');
  static double? _num(String v) => double.tryParse(v.trim().replaceAll(',', '.'));

  String? _marginText() {
    final price = _num(_price.text), cost = _num(_cost.text);
    if (price == null || cost == null || cost <= 0 || price <= 0) return null;
    final m = price - cost;
    return 'Marge : ${m.toStringAsFixed(3).replaceAll('.', ',')}${_byWeight ? ' / kg' : ''} (${(m / price * 100).toStringAsFixed(0)} %)';
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _ScanOnceScreen()),
    );
    if (code != null) setState(() => _barcode.text = code);
  }

  /// Internal code for products without a barcode (bread, vegetables...).
  static String _internalCode() => 'INT${DateTime.now().millisecondsSinceEpoch % 100000000}';

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final code = _barcode.text.trim().isEmpty ? _internalCode() : _barcode.text.trim();
    final p = Product(
      barcode: code,
      name: _name.text.trim(),
      price: _num(_price.text)!,
      cost: _num(_cost.text) ?? 0,
      stock: _track ? (_num(_stock.text) ?? 0) : null,
      minStock: _track ? (int.tryParse(_minStock.text.trim()) ?? 0) : 0,
      unit: _byWeight ? 'kg' : '',
      favorite: _favorite,
    );
    final products = context.read<ProductsProvider>();
    final nav = Navigator.of(context);
    await products.save(p);
    nav.pop(p);
  }

  @override
  Widget build(BuildContext context) {
    final decimalOnly = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Modifier le produit' : 'Nouveau produit')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _barcode,
              readOnly: _editing,
              decoration: InputDecoration(
                labelText: tr('Code-barres'),
                helperText: _editing ? null : 'Laissez vide pour un produit sans code-barres (code interne)',
                suffixIcon: _editing
                    ? null
                    : IconButton(icon: const Icon(Icons.photo_camera_outlined), onPressed: _scan),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('Nom du produit')),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vendu au poids', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Le prix est au kilo, le poids est saisi à la vente'),
              value: _byWeight,
              onChanged: (v) => setState(() => _byWeight = v),
            ),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [decimalOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: _byWeight ? 'Prix au kg' : 'Prix'),
              validator: (v) {
                final n = _num(v ?? '');
                return (n == null || n < 0) ? 'Prix invalide' : null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [decimalOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _byWeight ? "Prix d'achat au kg (facultatif)" : "Prix d'achat (facultatif)",
                helperText: _marginText(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = _num(v);
                return (n == null || n < 0) ? 'Prix invalide' : null;
              },
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Accès rapide sur la Caisse', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Un bouton pour ajouter ce produit sans le scanner'),
              value: _favorite,
              onChanged: (v) => setState(() => _favorite = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Suivre le stock', style: TextStyle(fontWeight: FontWeight.w600)),
              value: _track,
              onChanged: (v) => setState(() => _track = v),
            ),
            if (_track)
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _stock,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [decimalOnly],
                    decoration: InputDecoration(labelText: _byWeight ? 'Stock actuel (kg)' : 'Stock actuel'),
                    validator: (v) => _num(v ?? '') == null ? 'Requis' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _minStock,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(labelText: tr('Alerte à partir de')),
                  ),
                ),
              ]),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kBlue),
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanOnceScreen extends StatefulWidget {
  const _ScanOnceScreen();

  @override
  State<_ScanOnceScreen> createState() => _ScanOnceScreenState();
}

class _ScanOnceScreenState extends State<_ScanOnceScreen> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scanner un code-barres')),
        body: MobileScanner(
          onDetect: (cap) {
            final v = cap.barcodes.isEmpty ? null : cleanScan(cap.barcodes.first);
            if (!_done && v != null) {
              _done = true;
              Navigator.pop(context, v);
            }
          },
        ),
      );
}
