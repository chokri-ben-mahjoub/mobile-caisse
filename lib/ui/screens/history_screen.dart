import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/printer_service.dart';
import '../../logic/sales_provider.dart';
import '../../logic/settings_provider.dart';
import '../widgets.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SalesProvider>();
    final s = context.watch<SettingsProvider>().settings;
    final dayLabel = DateFormat('dd/MM/yyyy').format(prov.day);

    return Scaffold(
      appBar: AppBar(title: const Text('Historique')),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => prov.shiftDay(-1)),
              Text(prov.isToday ? 'Aujourd\'hui · $dayLabel' : dayLabel,
                  style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: prov.isToday ? null : () => prov.shiftDay(1),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TotalBanner(label: 'TOTAL DU JOUR', sub: '${prov.sales.length} ventes', amount: s.money(prov.total)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _methodCard(
              Icons.trending_up,
              prov.hasUnknownCost ? "Bénéfice (articles avec prix d'achat)" : 'Bénéfice',
              s.money(prov.profit),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Expanded(child: _methodCard(Icons.payments_outlined, 'Espèces', s.money(prov.totalFor(PayMethod.cash)))),
                const SizedBox(width: 10),
                Expanded(child: _methodCard(Icons.qr_code_2, 'QR code', s.money(prov.totalFor(PayMethod.qr)))),
              ],
            ),
          ),
          Expanded(
            child: prov.sales.isEmpty
                ? const Center(child: Text('Aucune vente ce jour', style: TextStyle(color: Colors.black54)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                    itemCount: prov.sales.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final sale = prov.sales[i];
                      return Card(
                        child: ListTile(
                          onTap: () => _showSale(context, sale),
                          title: Text('Ticket ${sale.id} · ${DateFormat('HH:mm').format(sale.date)}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                              '${sale.itemCount} article${sale.itemCount > 1 ? 's' : ''} · ${sale.method == PayMethod.cash ? 'Espèces' : 'QR code'}'),
                          trailing: Text(s.money(sale.total), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _methodCard(IconData icon, String label, String value) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Icon(icon, size: 16), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 12))]),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
        ),
      );

  void _showSale(BuildContext context, Sale sale) {
    final s = context.read<SettingsProvider>().settings;
    final printer = context.read<PrinterService>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ticket ${sale.id} · ${DateFormat('dd/MM/yyyy HH:mm').format(sale.date)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final l in sale.lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Expanded(child: Text('${l.qty} × ${l.name}')),
                          Text(s.money(l.total)),
                        ]),
                      ),
                  ],
                ),
              ),
              const Divider(),
              Row(children: [
                const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(s.money(sale.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ]),
              if (sale.discount > 0)
                Row(children: [
                  const Text('Remise', style: TextStyle(color: Colors.black54)),
                  const Spacer(),
                  Text('−${s.money(sale.discount)}', style: const TextStyle(color: Colors.black54)),
                ]),
              if (sale.lines.any((l) => l.cost > 0))
                Row(children: [
                  const Text('Bénéfice', style: TextStyle(color: Colors.black54)),
                  const Spacer(),
                  Text(s.money(sale.profit), style: const TextStyle(color: Colors.black54)),
                ]),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.print_outlined),
                label: const Text('Réimprimer le ticket'),
                onPressed: () async {
                  final err = await printer.printSale(sale, s);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    showMsg(context, err ?? 'Ticket imprimé');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
