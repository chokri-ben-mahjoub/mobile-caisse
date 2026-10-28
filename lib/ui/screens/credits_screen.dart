import 'package:flutter/material.dart' hide Text;
import '../i18n/text.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/credit.dart';
import '../../data/quote_share.dart';
import '../../data/settings_store.dart';
import '../../logic/credits_provider.dart';
import '../../logic/settings_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import '../i18n/tr.dart';

Color _ageColor(BuildContext context, int days) =>
    days >= 30 ? context.pal.badFg : (days >= 7 ? const Color(0xFFEA580C) : context.pal.goodFg);

/// "Crédit clients": who owes what, with payments and a WhatsApp reminder.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final s = context.watch<SettingsProvider>().settings;
    final prov = context.watch<CreditsProvider>();
    final open = prov.open;
    final settled = prov.accounts.where((a) => a.balance <= 0.0005).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Crédit clients')),
      body: prov.entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  "Aucun crédit pour le moment.\nChoisissez « Crédit » au moment du paiement pour mettre une vente sur le compte d'un client.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700, height: 1.4),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                TotalBanner(
                  label: 'À RÉCUPÉRER',
                  amount: s.money(prov.outstanding),
                  sub: '${open.length} client${open.length > 1 ? 's' : ''} avec un solde',
                ),
                const SizedBox(height: 14),
                for (final a in open) _AccountTile(account: a, settings: s),
                if (settled.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 0, 8),
                    child: Text('SOLDÉS', style: TextStyle(color: pal.muted, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
                  ),
                  for (final a in settled) _AccountTile(account: a, settings: s),
                ],
              ],
            ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account, required this.settings});
  final CreditAccount account;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final since = account.oldestUnpaid;
    final days = since == null ? 0 : DateTime.now().difference(since).inDays;
    final owes = account.balance > 0.0005;
    final c = owes ? _ageColor(context, days) : pal.goodFg;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: pal.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => showAccountSheet(context, account.name),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: pal.shadow),
            child: Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: pal.soft,
                child: Text(account.name.isEmpty ? '?' : account.name[0].toUpperCase(),
                    style: TextStyle(color: pal.accent, fontWeight: FontWeight.w900, fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(account.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    owes ? (days == 0 ? "depuis aujourd'hui" : 'depuis $days jour${days > 1 ? 's' : ''}') : 'Soldé',
                    style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ]),
              ),
              Text(settings.money(account.balance < 0 ? 0 : account.balance),
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: owes ? c : pal.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Detail of one customer's account with the payment and reminder actions.
Future<void> showAccountSheet(BuildContext context, String customer) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Consumer2<CreditsProvider, SettingsProvider>(
      builder: (ctx, prov, sp, _) {
        final pal = ctx.pal;
        final s = sp.settings;
        final matches = prov.accounts.where((a) => a.name.toLowerCase() == customer.toLowerCase());
        if (matches.isEmpty) return const SizedBox(height: 120);
        final a = matches.first;
        final owes = a.balance > 0.0005;
        final df = DateFormat('dd/MM/yyyy HH:mm');
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                if (a.phone.isNotEmpty) Text(a.phone, style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(owes ? 'Doit ${s.money(a.balance)}' : 'Compte soldé',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: owes ? pal.badFg : pal.goodFg)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: owes ? () => _pay(ctx, a, s) : null,
                      icon: const Icon(Icons.payments_rounded),
                      label: const Text('Encaisser'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: owes ? () => _remind(ctx, a, s) : null,
                      icon: const Icon(Icons.chat_rounded),
                      label: const Text('Relancer'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Text('HISTORIQUE', style: TextStyle(color: pal.muted, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
                const SizedBox(height: 6),
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final e in a.entries)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(e.isPayment ? Icons.south_west_rounded : Icons.north_east_rounded,
                            color: e.isPayment ? pal.goodFg : pal.badFg),
                        title: Text(e.isPayment ? 'Paiement reçu' : 'Achat à crédit${e.saleId != null ? ' · ticket ${e.saleId}' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text('${df.format(e.date)}${e.note.isEmpty ? '' : ' · ${e.note}'}'),
                        trailing: Text('${e.isPayment ? '−' : '+'}${s.money(e.amount.abs())}',
                            style: TextStyle(fontWeight: FontWeight.w900, color: e.isPayment ? pal.goodFg : pal.badFg)),
                        onLongPress: e.isPayment ? () => _confirmDelete(ctx, prov, e) : null,
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _confirmDelete(BuildContext context, CreditsProvider prov, CreditEntry e) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Annuler ce paiement ?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Annuler le paiement')),
      ],
    ),
  );
  if (ok == true) await prov.remove(e);
}

Future<void> _pay(BuildContext context, CreditAccount a, AppSettings s) async {
  final c = TextEditingController(text: a.balance.toStringAsFixed(s.decimals));
  final amount = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Paiement de ${a.name}'),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: tr('Montant reçu (${s.currency})'), helperText: tr('Reste dû : ${s.money(a.balance)}')),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.replaceAll(',', '.')) ?? 0),
          child: const Text('Encaisser'),
        ),
      ],
    ),
  );
  if (amount == null || amount <= 0 || !context.mounted) return;
  final paid = amount > a.balance ? a.balance : amount;
  await context.read<CreditsProvider>().addPayment(a, paid);
  HapticFeedback.mediumImpact();
  if (context.mounted) showMsg(context, '${s.money(paid)} encaissé');
}

Future<void> _remind(BuildContext context, CreditAccount a, AppSettings s) async {
  final msg = 'Bonjour ${a.name}, petit rappel amical : votre solde chez ${s.storeName} est de ${s.money(a.balance)}. '
      'Merci de passer le régler dès que possible. 🙏';
  final n = QuoteShare.internationalNumber(a.phone);
  final uri = Uri.parse('https://wa.me/${n ?? ''}?text=${Uri.encodeComponent(msg)}');
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showMsg(context, "WhatsApp n'est pas installé");
  } catch (e) {
    if (context.mounted) showMsg(context, 'Action impossible : $e');
  }
}
