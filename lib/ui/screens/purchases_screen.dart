import 'package:flutter/material.dart' hide Text;
import '../i18n/text.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../data/purchase.dart';
import '../../data/settings_store.dart';
import '../../logic/purchases_provider.dart';
import '../../logic/settings_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import 'new_purchase_screen.dart';
import '../i18n/tr.dart';
import '../i18n/date_fmt.dart';

const _orange = Color(0xFFEA580C);

/// Supplier purchases: goods receipts, what is owed, and one account per supplier.
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  bool _suppliers = false;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final s = context.watch<SettingsProvider>().settings;
    final prov = context.watch<PurchasesProvider>();
    final accounts = prov.accounts;
    final owing = accounts.where((a) => a.owes).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Achats fournisseurs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewPurchaseScreen())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nouvel achat', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          TotalBanner(
            label: 'À PAYER AUX FOURNISSEURS',
            amount: s.money(prov.owed),
            sub: 'Achats du mois : ${s.money(prov.monthTotal)}',
            badge: owing == 0 ? 'à jour' : '$owing fournisseur${owing > 1 ? 's' : ''}',
          ),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, icon: const Icon(Icons.inventory_rounded), label: Text('Réceptions (${prov.purchases.length})')),
              ButtonSegment(value: true, icon: const Icon(Icons.storefront_rounded), label: Text('Fournisseurs (${accounts.length})')),
            ],
            selected: {_suppliers},
            onSelectionChanged: (v) => setState(() => _suppliers = v.first),
          ),
          const SizedBox(height: 14),
          if (prov.purchases.isEmpty && prov.payments.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                "Aucun achat pour le moment.\nEnregistrez une réception : le stock et les prix d'achat se mettent à jour tout seuls.",
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700, height: 1.4),
              ),
            )
          else if (_suppliers)
            for (final a in accounts) _SupplierTile(account: a, settings: s)
          else
            for (final p in prov.purchases) _PurchaseTile(purchase: p, settings: s),
        ],
      ),
    );
  }
}

Widget _avatar(BuildContext context, String name) => CircleAvatar(
      radius: 22,
      backgroundColor: context.pal.soft,
      child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
          style: TextStyle(color: context.pal.accent, fontWeight: FontWeight.w900, fontSize: 18)),
    );

Widget _card(BuildContext context, {required VoidCallback onTap, required Widget child}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: context.pal.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: context.pal.shadow),
            child: child,
          ),
        ),
      ),
    );

Widget _pill(String text, Color fg, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 11)),
    );

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({required this.purchase, required this.settings});
  final Purchase purchase;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final p = purchase;
    final paidNothing = p.paid <= 0.0005;
    return _card(
      context,
      onTap: () => showPurchaseSheet(context, p),
      child: Row(children: [
        _avatar(context, p.supplier),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.supplier, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 2),
            Text(
              '${DateFmt('dd/MM/yyyy').format(p.date)} · ${p.articles} article${p.articles > 1 ? 's' : ''}'
              '${p.invoice.isEmpty ? '' : ' · N° ${p.invoice}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(settings.money(p.total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 4),
          p.settled
              ? _pill('PAYÉ', pal.goodFg, pal.goodBg)
              : _pill(paidNothing ? 'À CRÉDIT' : 'RESTE ${settings.money(p.owed)}', paidNothing ? pal.badFg : _orange,
                  paidNothing ? pal.badBg : _orange.withValues(alpha: 0.14)),
        ]),
      ]),
    );
  }
}

class _SupplierTile extends StatelessWidget {
  const _SupplierTile({required this.account, required this.settings});
  final SupplierAccount account;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final a = account;
    return _card(
      context,
      onTap: () => showSupplierSheet(context, a.name),
      child: Row(children: [
        _avatar(context, a.name),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 2),
            Text('${a.purchases.length} achat${a.purchases.length > 1 ? 's' : ''} · ${settings.money(a.purchased)}',
                style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700, fontSize: 12)),
          ]),
        ),
        a.owes
            ? Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(settings.money(a.balance), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: pal.badFg)),
                Text('à payer', style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700, fontSize: 11)),
              ])
            : _pill('À JOUR', pal.goodFg, pal.goodBg),
      ]),
    );
  }
}

Widget _sheetRow(BuildContext context, String label, String value, {Color? color, bool big = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(label, style: TextStyle(color: context.pal.muted, fontWeight: FontWeight.w700)),
        const Spacer(),
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: big ? 18 : 14, color: color)),
      ]),
    );

/// Detail of one goods receipt: lines with cost, totals and what is still owed.
Future<void> showPurchaseSheet(BuildContext context, Purchase p) {
  final s = context.read<SettingsProvider>().settings;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final pal = ctx.pal;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.supplier, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
              Text(
                '${DateFmt('dd/MM/yyyy HH:mm').format(p.date)}${p.invoice.isEmpty ? '' : ' · N° ${p.invoice}'}',
                style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final l in p.lines)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${fmtQty(l.qty, unit: l.unit)} × ${s.money(l.cost)}'),
                      trailing: Text(s.money(l.total), style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                ]),
              ),
              const Divider(height: 20),
              _sheetRow(ctx, 'Total', s.money(p.total), big: true),
              _sheetRow(ctx, 'Payé à la réception', s.money(p.paid), color: pal.goodFg),
              if (!p.settled) _sheetRow(ctx, 'Reste à payer', s.money(p.owed), color: pal.badFg),
              if (p.note.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(p.note, style: TextStyle(color: pal.muted, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 10),
              Text('Stock mis à jour à la réception.', style: TextStyle(color: pal.muted, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
    },
  );
}

/// One supplier's account: balance, payment and call actions, history of purchases and payments.
Future<void> showSupplierSheet(BuildContext context, String name) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Consumer2<PurchasesProvider, SettingsProvider>(
      builder: (ctx, prov, sp, _) {
        final pal = ctx.pal;
        final s = sp.settings;
        final m = prov.accounts.where((a) => a.name.toLowerCase() == name.toLowerCase());
        if (m.isEmpty) return const SizedBox(height: 120);
        final a = m.first;
        final df = DateFmt('dd/MM/yyyy');
        // Purchases and payments merged, newest first.
        final rows = <(DateTime, Widget)>[
          for (final p in a.purchases)
            (
              p.date,
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.north_east_rounded, color: pal.badFg),
                title: Text('Achat${p.invoice.isEmpty ? '' : ' N° ${p.invoice}'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${df.format(p.date)} · ${p.articles} article${p.articles > 1 ? 's' : ''}${p.paid > 0 ? ' · payé ${s.money(p.paid)}' : ''}'),
                trailing: Text('+${s.money(p.total)}', style: TextStyle(fontWeight: FontWeight.w900, color: pal.badFg)),
                onTap: () => showPurchaseSheet(ctx, p),
              )
            ),
          for (final p in a.payments)
            (
              p.date,
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.south_west_rounded, color: pal.goodFg),
                title: const Text('Règlement', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${df.format(p.date)}${p.note.isEmpty ? '' : ' · ${p.note}'}'),
                trailing: Text('−${s.money(p.amount)}', style: TextStyle(fontWeight: FontWeight.w900, color: pal.goodFg)),
                onLongPress: () => _confirmRemove(ctx, prov, p),
              )
            ),
        ]..sort((x, y) => y.$1.compareTo(x.$1));
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                if (a.phone.isNotEmpty) Text(a.phone, style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(a.owes ? 'On lui doit ${s.money(a.balance)}' : 'Compte à jour',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: a.owes ? pal.badFg : pal.goodFg)),
                Text('Total acheté : ${s.money(a.purchased)}', style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: a.owes ? () => _pay(ctx, a, s) : null,
                      icon: const Icon(Icons.payments_rounded),
                      label: const Text('Régler'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: a.phone.isEmpty ? null : () => launchUrl(Uri(scheme: 'tel', path: a.phone)),
                      icon: const Icon(Icons.call_rounded),
                      label: const Text('Appeler'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Text('HISTORIQUE', style: TextStyle(color: pal.muted, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
                const SizedBox(height: 6),
                Flexible(child: ListView(shrinkWrap: true, children: [for (final r in rows) r.$2])),
              ]),
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _confirmRemove(BuildContext context, PurchasesProvider prov, SupplierPayment p) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Annuler ce règlement ?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Annuler le règlement')),
      ],
    ),
  );
  if (ok == true) await prov.removePayment(p);
}

Future<void> _pay(BuildContext context, SupplierAccount a, AppSettings s) async {
  final c = TextEditingController(text: a.balance.toStringAsFixed(s.decimals));
  final note = TextEditingController();
  final amount = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Règlement à ${a.name}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: tr('Montant payé (${s.currency})'), helperText: tr('Reste dû : ${s.money(a.balance)}')),
        ),
        const SizedBox(height: 8),
        TextField(controller: note, decoration: InputDecoration(labelText: tr('Note (chèque, virement…)'))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.replaceAll(',', '.')) ?? 0),
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
  if (amount == null || amount <= 0 || !context.mounted) return;
  final paid = amount > a.balance ? a.balance : amount;
  await context.read<PurchasesProvider>().pay(a, paid, note: note.text);
  HapticFeedback.mediumImpact();
  if (context.mounted) showMsg(context, '${s.money(paid)} réglé à ${a.name}');
}
