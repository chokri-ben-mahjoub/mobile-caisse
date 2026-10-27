import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../data/barcode_utils.dart';
import '../../data/models.dart';
import '../../logic/cart_provider.dart';
import '../../logic/products_provider.dart';

/// Add or edit a product. Pops `true` when saved.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product, this.barcode, this.addToCartAfterSave = false});
  final Product? product;
  final String? barcode;
  final bool addToCartAfterSave;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _barcode = TextEditingController(text: widget.product?.barcode ?? widget.barcode ?? '');
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _price = TextEditingController(
      text: widget.product == null ? '' : widget.product!.price.toString().replaceAll('.', ','));

  late final _cost = TextEditingController(
      text: (widget.product?.cost ?? 0) > 0 ? widget.product!.cost.toString().replaceAll('.', ',') : '');
  late bool _track = widget.product?.tracked ?? false;
  late final _stock = TextEditingController(text: widget.product?.stock?.toString() ?? '');
  late final _minStock = TextEditingController(text: (widget.product?.minStock ?? 0).toString());

  bool get _editing => widget.product != null;

  static double? _num(String v) => double.tryParse(v.trim().replaceAll(',', '.'));

  String? _marginText() {
    final price = _num(_price.text), cost = _num(_cost.text);
    if (price == null || cost == null || cost <= 0) return null;
    final m = price - cost;
    return 'Marge : ${m.toStringAsFixed(3).replaceAll('.', ',')} (${(m / price * 100).toStringAsFixed(0)} %)';
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _ScanOnceScreen()),
    );
    if (code != null) setState(() => _barcode.text = code);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final p = Product(
      barcode: _barcode.text.trim(),
      name: _name.text.trim(),
      price: _num(_price.text)!,
      cost: _num(_cost.text) ?? 0,
      stock: _track ? (int.tryParse(_stock.text.trim()) ?? 0) : null,
      minStock: _track ? (int.tryParse(_minStock.text.trim()) ?? 0) : 0,
    );
    final products = context.read<ProductsProvider>();
    final cart = context.read<CartProvider>();
    final nav = Navigator.of(context);
    await products.save(p);
    if (widget.addToCartAfterSave) cart.add(p);
    nav.pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                  labelText: 'Code-barres',
                  suffixIcon: _editing
                      ? null
                      : IconButton(icon: const Icon(Icons.photo_camera_outlined), onPressed: _scan),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Code-barres requis' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nom du produit'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Prix'),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                  return (n == null || n < 0) ? 'Prix invalide' : null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: "Prix d'achat (facultatif)",
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
                title: const Text('Suivre le stock'),
                value: _track,
                onChanged: (v) => setState(() => _track = v),
              ),
              if (_track)
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _stock,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Stock actuel'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _minStock,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Alerte à partir de'),
                    ),
                  ),
                ]),
              const SizedBox(height: 24),
              FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Enregistrer')),
            ],
          ),
        ),
      );
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
