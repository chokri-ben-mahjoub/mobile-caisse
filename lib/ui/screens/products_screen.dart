import 'package:flutter/material.dart' hide Text;
import '../i18n/text.dart';
import 'package:provider/provider.dart';

import '../../data/backup_service.dart';
import '../../data/models.dart';
import '../../logic/products_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import '../../logic/settings_provider.dart';
import 'product_form_screen.dart';
import '../i18n/tr.dart';

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ProductsProvider>();
    final s = context.watch<SettingsProvider>().settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Produits'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              final backup = context.read<BackupService>();
              final products = context.read<ProductsProvider>();
              try {
                if (v == 'import') {
                  final r = await backup.importProductsFromPicker();
                  if (r != null) {
                    await products.load();
                    if (context.mounted) {
                      showMsg(context,
                          '${r.imported} produit(s) importé(s)${r.skipped > 0 ? ', ${r.skipped} ligne(s) ignorée(s)' : ''}');
                    }
                  }
                } else {
                  await backup.shareProductsCsv();
                }
              } catch (e) {
                if (context.mounted) showMsg(context, 'Erreur : $e');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('Importer depuis un fichier CSV')),
              PopupMenuItem(value: 'export', child: Text('Exporter les produits (CSV)')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductFormScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau produit'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: prov.search,
              decoration: InputDecoration(
                hintText: tr('Rechercher un nom ou un code'),
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (prov.lowCount > 0 || prov.onlyLow)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilterChip(
                  avatar: Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade800),
                  label: Text('Stock bas (${prov.lowCount})'),
                  selected: prov.onlyLow,
                  onSelected: prov.setOnlyLow,
                ),
              ),
            ),
          Expanded(
            child: prov.products.isEmpty
                ? Center(child: Text('Aucun produit', style: TextStyle(color: context.pal.muted)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                    itemCount: prov.products.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final p = prov.products[i];
                      return Card(
                        child: ListTile(
                          onTap: () => Navigator.push(
                              context, MaterialPageRoute(builder: (_) => ProductFormScreen(product: p))),
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Row(children: [
                            Flexible(child: Text(p.barcode, overflow: TextOverflow.ellipsis)),
                            if (p.tracked) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: p.lowStock ? context.pal.badBg : context.pal.goodBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  p.stock == 0 ? 'Épuisé' : 'Stock : ${fmtQty(p.stock ?? 0, unit: p.unit)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: p.lowStock ? context.pal.badFg : context.pal.goodFg,
                                  ),
                                ),
                              ),
                            ],
                          ]),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(p.byWeight ? '${s.money(p.price)}/kg' : s.money(p.price), style: const TextStyle(fontWeight: FontWeight.w800)),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text('Supprimer « ${p.name} » ?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
                                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
                                      ],
                                    ),
                                  );
                                  if (ok == true) prov.delete(p.barcode);
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
