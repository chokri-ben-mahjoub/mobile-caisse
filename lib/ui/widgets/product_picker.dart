import 'package:flutter/material.dart' hide Text;
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../logic/products_provider.dart';
import '../i18n/text.dart';
import '../i18n/tr.dart';
import '../theme.dart';

/// Opens the searchable catalogue and returns the chosen product (null when dismissed).
Future<Product?> pickProduct(BuildContext context, {Set<String> exclude = const {}}) => showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ProductPicker(exclude: exclude),
    );

/// Searchable catalogue to pick the product received.
class ProductPicker extends StatefulWidget {
  const ProductPicker({super.key, this.exclude = const {}});
  final Set<String> exclude;

  @override
  State<ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<ProductPicker> {
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
              decoration: InputDecoration(hintText: tr('Nom ou code-barres'), prefixIcon: Icon(Icons.search_rounded)),
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
