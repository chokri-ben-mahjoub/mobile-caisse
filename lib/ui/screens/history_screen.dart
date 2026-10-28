import 'package:flutter/material.dart' hide Text;
import '../i18n/text.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/printer_service.dart';
import '../../logic/auth_provider.dart';
import '../../logic/sales_provider.dart';
import '../../logic/settings_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import 'closing_screen.dart';
import 'credits_screen.dart';
import 'quotes_screen.dart';
import 'return_screen.dart';
import 'stats_screen.dart';
import '../i18n/tr.dart';
import '../i18n/date_fmt.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SalesProvider>();
    final s = context.watch<SettingsProvider>().settings;
    final auth = context.watch<AuthProvider>();
    final dayLabel = DateFmt('dd/MM/yyyy').format(prov.day);
    final pal = context.pal;

    // Day total per seller (only when sales carry a seller name).
    final bySeller = <String, double>{};
    for (final sale in prov.sales) {
      if (sale.seller != null) {
        bySeller.update(sale.seller!, (v) => round3(v + sale.total), ifAbsent: () => sale.total);
      }
    }

    final subParts = <String>[
      '${prov.salesCount} vente${prov.salesCount > 1 ? 's' : ''}',
      if (prov.refundsCount > 0) 'retours −${s.money(prov.refundsTotal)}',
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
        actions: [
          IconButton(
            tooltip: tr('Crédit clients'),
            icon: const Icon(Icons.account_balance_wallet_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreditsScreen())),
          ),
          IconButton(
            tooltip: tr('Devis'),
            icon: const Icon(Icons.description_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuotesScreen())),
          ),
          IconButton(
            tooltip: tr('Statistiques et rapport PDF'),
            icon: const Icon(Icons.insights_rounded),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen())),
          ),
          if (auth.can(Perm.closing))
            IconButton(
              tooltip: tr('Clôture de caisse'),
              icon: const Icon(Icons.lock_clock_rounded),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClosingScreen())),
            ),
        ],
      ),
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
            child: TotalBanner(label: 'TOTAL DU JOUR', sub: subParts.join(' · '), amount: s.money(prov.total)),
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
          if (bySeller.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final e in bySeller.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        avatar: const Icon(Icons.person_outline_rounded, size: 18),
                        label: Text('${e.key} · ${s.money(e.value)}'),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: prov.sales.isEmpty
                ? Center(child: Text('Aucune vente ce jour', style: TextStyle(color: pal.muted)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                    itemCount: prov.sales.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final sale = prov.sales[i];
                      final refund = sale.isRefund;
                      return Card(
                        child: ListTile(
                          onTap: () => _showSale(context, sale),
                          title: Text(
                            '${refund ? 'Retour' : 'Ticket'} ${sale.id} · ${DateFmt('HH:mm').format(sale.date)}',
                            style: TextStyle(fontWeight: FontWeight.w700, color: refund ? pal.badFg : null),
                          ),
                          subtitle: Text(
                            '${sale.itemCount} article${sale.itemCount > 1 ? 's' : ''}'
                            '${refund && sale.refSaleId != null ? ' · ticket ${sale.refSaleId}' : ''}'
                            ' · ${payMethodLabel(sale.method)}'
                            '${sale.seller != null ? ' · ${sale.seller}' : ''}',
                          ),
                          trailing: Text(s.money(sale.total),
                              style: TextStyle(fontWeight: FontWeight.w800, color: refund ? pal.badFg : null)),
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

  Future<void> _showSale(BuildContext context, Sale sale) async {
    final s = context.read<SettingsProvider>().settings;
    final printer = context.read<PrinterService>();
    final salesProv = context.read<SalesProvider>();
    final canRefund = context.read<AuthProvider>().can(Perm.refund);

    // What was already given back on this sale (for a normal sale only).
    final returned = !sale.isRefund && sale.id != null ? await salesProv.returnedQty(sale.id!) : <String, double>{};
    final left = Sale.returnable(sale, returned);
    final fullyReturned = !sale.isRefund && sale.lines.every((l) => (left[l.barcode] ?? 0) <= 0);
    final anyReturned = returned.values.any((v) => v > 0);
    if (!context.mounted) return;
    final pal = context.pal;

    await showModalBottomSheet<void>(
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
              Text(
                '${sale.isRefund ? 'Retour' : 'Ticket'} ${sale.id} · ${DateFmt('dd/MM/yyyy HH:mm').format(sale.date)}',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: sale.isRefund ? pal.badFg : null),
              ),
              if (sale.isRefund && sale.refSaleId != null)
                Text('Retour du ticket ${sale.refSaleId}', style: TextStyle(color: pal.muted, fontWeight: FontWeight.w600)),
              if (sale.reason != null && sale.reason!.isNotEmpty)
                Text('Motif : ${sale.reason}', style: TextStyle(color: pal.muted, fontWeight: FontWeight.w600)),
              if (sale.seller != null)
                Text('Vendeur : ${sale.seller}', style: TextStyle(color: pal.muted, fontWeight: FontWeight.w600)),
              if (fullyReturned || anyReturned)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: pal.badBg, borderRadius: BorderRadius.circular(8)),
                    child: Text(fullyReturned ? 'Entièrement retourné' : 'Partiellement retourné',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: pal.badFg)),
                  ),
                ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final l in sale.lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Expanded(child: Text('${fmtQty(l.qty, unit: l.unit)} × ${l.name}')),
                          Text(s.money(l.total)),
                        ]),
                      ),
                  ],
                ),
              ),
              const Divider(),
              Row(children: [
                Text(sale.isRefund ? 'REMBOURSÉ' : 'TOTAL', style: const TextStyle(fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(s.money(sale.total.abs()), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ]),
              if (sale.discount != 0)
                Row(children: [
                  Text('Remise', style: TextStyle(color: pal.muted)),
                  const Spacer(),
                  Text('−${s.money(sale.discount.abs())}', style: TextStyle(color: pal.muted)),
                ]),
              if (sale.lines.any((l) => l.cost > 0))
                Row(children: [
                  Text('Bénéfice', style: TextStyle(color: pal.muted)),
                  const Spacer(),
                  Text(s.money(sale.profit), style: TextStyle(color: pal.muted)),
                ]),
              const SizedBox(height: 12),
              if (!sale.isRefund && canRefund && !fullyReturned) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: pal.badFg),
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: const Text('Retour / annuler le ticket'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ReturnScreen(sale: sale, returned: returned)),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
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
