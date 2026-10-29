import 'package:flutter/material.dart' hide Text;
import '../i18n/text.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/quote.dart';
import '../../data/quote_share.dart';
import '../../logic/cart_provider.dart';
import '../../logic/quotes_provider.dart';
import '../../logic/settings_provider.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets.dart';
import 'quote_share_sheet.dart';
import '../i18n/tr.dart';
import '../i18n/date_fmt.dart';

Color quoteColor(Quote q, DateTime now) {
  if (q.isExpired(now)) return const Color(0xFF64748B);
  return switch (q.status) {
    QuoteStatus.pending => const Color(0xFFF59E0B),
    QuoteStatus.accepted => const Color(0xFF16A34A),
    QuoteStatus.refused => const Color(0xFFDC2626),
  };
}

String quoteStatusLabel(Quote q, DateTime now) => q.isExpired(now) ? 'Expiré' : q.status.label;

/// Detail page of a quote: hero total, validity countdown, customer, lines, totals and actions.
class QuoteDetailScreen extends StatefulWidget {
  const QuoteDetailScreen({super.key, required this.quote});
  final Quote quote;

  @override
  State<QuoteDetailScreen> createState() => _QuoteDetailScreenState();
}

class _QuoteDetailScreenState extends State<QuoteDetailScreen> {
  Quote _live(BuildContext context) {
    final list = context.watch<QuotesProvider>().quotes;
    return list.firstWhere((x) => x.id == widget.quote.id, orElse: () => widget.quote);
  }

  void _send(Quote q) =>
      showQuoteShareSheet(context, QuoteShare(q, context.read<SettingsProvider>().settings));

  Future<void> _convert(Quote q) async {
    final cart = context.read<CartProvider>();
    if (!cart.isEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remplacer le panier ?'),
          content: const Text('Le panier actuel sera remplacé par les articles du devis.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Remplacer')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    cart.loadLines(q.lines, q.discount);
    await context.read<QuotesProvider>().setStatus(q, QuoteStatus.accepted);
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    cashierRequest.value++;
  }

  Future<void> _delete(Quote q) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce devis ?'),
        content: Text('${q.number} sera définitivement supprimé.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<QuotesProvider>().delete(q);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final q = _live(context);
    final s = context.watch<SettingsProvider>().settings;
    final pal = context.pal;
    final now = DateTime.now();
    final col = quoteColor(q, now);
    final df = DateFmt('dd MMM yyyy');
    final left = q.daysLeft(now);
    final elapsed = q.validDays == 0 ? 1.0 : ((q.validDays - left) / q.validDays).clamp(0.0, 1.0);

    Widget card({required Widget child, EdgeInsets? padding}) => Container(
          width: double.infinity,
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(22), boxShadow: pal.shadow),
          child: child,
        );

    Widget tile(IconData icon, String label, String value, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(20), boxShadow: pal.shadow),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: (color ?? pal.accent).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, size: 19, color: color ?? pal.accent),
                ),
                const SizedBox(height: 10),
                Text(label, style: TextStyle(color: pal.muted, fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        );

    Widget step(String title, String sub, {required bool done, bool last = false, Color? color}) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: done ? (color ?? pal.accent) : pal.soft2,
                      shape: BoxShape.circle,
                      border: Border.all(color: color ?? pal.accent, width: 2),
                    ),
                    child: done ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                  ),
                  if (!last) Expanded(child: Container(width: 2, color: pal.border)),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(sub, style: TextStyle(color: pal.muted, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(q.number),
        actions: [
          IconButton(
            tooltip: tr('Envoyer le devis'),
            icon: const Icon(Icons.send_rounded),
            onPressed: () => _send(q),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final prov = context.read<QuotesProvider>();
              switch (v) {
                case 'accepted':
                  await prov.setStatus(q, QuoteStatus.accepted);
                case 'refused':
                  await prov.setStatus(q, QuoteStatus.refused);
                case 'pending':
                  await prov.setStatus(q, QuoteStatus.pending);
                case 'delete':
                  await _delete(q);
              }
            },
            itemBuilder: (_) => [
              if (q.status != QuoteStatus.accepted) const PopupMenuItem(value: 'accepted', child: Text('Marquer accepté')),
              if (q.status != QuoteStatus.refused) const PopupMenuItem(value: 'refused', child: Text('Marquer refusé')),
              if (q.status != QuoteStatus.pending) const PopupMenuItem(value: 'pending', child: Text('Remettre en attente')),
              const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // hero
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: kHeroGradient,
              borderRadius: BorderRadius.circular(28),
              boxShadow: accentShadow(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 9, height: 9, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(quoteStatusLabel(q, now),
                            style: TextStyle(color: col, fontWeight: FontWeight.w900, fontSize: 13)),
                      ]),
                    ),
                    const Spacer(),
                    Text(df.format(q.date), style: const TextStyle(color: Color(0xFFBFD4FF), fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 18),
                const Text('TOTAL DU DEVIS',
                    style: TextStyle(color: Color(0xFFBFD4FF), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(s.money(q.total),
                      style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: -1)),
                ),
                const SizedBox(height: 4),
                Text(
                  '${q.itemCount} article${q.itemCount > 1 ? 's' : ''}'
                  '${q.discountAmount > 0 ? ' · remise −${s.money(q.discountAmount)}' : ''}',
                  style: const TextStyle(color: Color(0xFFD6E4FF), fontWeight: FontWeight.w700),
                ),
                if (q.status == QuoteStatus.pending) ...[
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: elapsed,
                      minHeight: 8,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation(left < 0 ? const Color(0xFFFCA5A5) : left <= 3 ? const Color(0xFFFCD34D) : Colors.white),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    left < 0
                        ? 'Expiré depuis ${-left} jour${-left > 1 ? 's' : ''}'
                        : left == 0
                            ? 'Expire aujourd\'hui'
                            : 'Expire dans $left jour${left > 1 ? 's' : ''} · le ${df.format(q.validUntil)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            tile(Icons.person_rounded, 'Client', q.customer.isEmpty ? 'Non renseigné' : q.customer),
            const SizedBox(width: 12),
            tile(Icons.phone_rounded, 'Téléphone', q.phone.isEmpty ? '—' : q.phone, color: const Color(0xFF16A34A)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            tile(Icons.event_rounded, 'Validité', '${q.validDays} jours', color: const Color(0xFFF59E0B)),
            const SizedBox(width: 12),
            tile(Icons.badge_rounded, 'Établi par', q.seller ?? 'Caisse', color: const Color(0xFF8B5CF6)),
          ]),
          const SizedBox(height: 14),
          // lines
          card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Articles (${q.lines.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                for (var i = 0; i < q.lines.length; i++) ...[
                  if (i > 0) Divider(height: 18, color: pal.border),
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: pal.soft, borderRadius: BorderRadius.circular(13)),
                        child: Text(q.lines[i].name.isEmpty ? '?' : q.lines[i].name.characters.first.toUpperCase(),
                            style: TextStyle(color: pal.accent, fontWeight: FontWeight.w900, fontSize: 18)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(q.lines[i].name,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text('${fmtQty(q.lines[i].qty, unit: q.lines[i].unit)} × ${s.money(q.lines[i].price)}',
                                style: TextStyle(color: pal.muted, fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                      ),
                      Text(s.money(q.lines[i].total),
                          style: TextStyle(color: pal.accent, fontWeight: FontWeight.w900, fontSize: 15)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          // totals
          card(
            child: Column(
              children: [
                _row('Sous-total', s.money(q.subtotal), pal.muted),
                if (q.discountAmount > 0) ...[
                  const SizedBox(height: 8),
                  _row(
                    q.discount?.type == DiscountType.percent ? 'Remise (${fmtQty(q.discount!.value)} %)' : 'Remise',
                    '−${s.money(q.discountAmount)}',
                    const Color(0xFF16A34A),
                  ),
                ],
                Divider(height: 24, color: pal.border),
                Row(
                  children: [
                    const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const Spacer(),
                    Text(s.money(q.total), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: pal.accent)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // timeline
          card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Suivi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 14),
                step('Devis créé', '${DateFmt('dd/MM/yyyy HH:mm').format(q.date)}${q.seller == null ? '' : ' · ${q.seller}'}', done: true),
                step(
                  q.isExpired(now) ? 'Offre expirée' : 'Offre valable',
                  'jusqu\'au ${DateFmt('dd/MM/yyyy').format(q.validUntil)}',
                  done: q.isExpired(now),
                  color: q.isExpired(now) ? const Color(0xFF64748B) : const Color(0xFFF59E0B),
                ),
                step(
                  switch (q.status) {
                    QuoteStatus.pending => 'Réponse du client',
                    QuoteStatus.accepted => 'Accepté par le client',
                    QuoteStatus.refused => 'Refusé par le client',
                  },
                  q.status == QuoteStatus.pending ? 'en attente' : 'décision enregistrée',
                  done: q.status != QuoteStatus.pending,
                  last: true,
                  color: q.status == QuoteStatus.refused ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                ),
              ],
            ),
          ),
          if (q.note.isNotEmpty) ...[
            const SizedBox(height: 14),
            card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Remarques', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(q.note, style: TextStyle(color: pal.muted, fontWeight: FontWeight.w600, height: 1.4)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          PrimaryButton(
            icon: Icons.point_of_sale_rounded,
            label: 'Convertir en vente',
            trailing: s.money(q.total),
            onPressed: () => _convert(q),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _send(q),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Envoyer · WhatsApp, e-mail, PDF'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
      ),
    );
  }

  Widget _row(String a, String b, Color c) => Row(
        children: [
          Text(a, style: TextStyle(color: c, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(b, style: TextStyle(color: c, fontWeight: FontWeight.w800)),
        ],
      );
}
