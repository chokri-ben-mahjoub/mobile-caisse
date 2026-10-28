import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/quote.dart';
import '../../logic/auth_provider.dart';
import '../../logic/cart_provider.dart';
import '../../logic/quotes_provider.dart';
import '../../logic/settings_provider.dart';
import '../theme.dart';
import 'quote_detail_screen.dart';

/// Saves the current basket as a quote after asking customer, phone, validity and a note.
/// Returns true when a quote was created (the basket is then emptied).
Future<bool> createQuoteFromCart(BuildContext context) async {
  final cart = context.read<CartProvider>();
  if (cart.isEmpty) return false;
  final prov = context.read<QuotesProvider>();
  final seller = context.read<AuthProvider>().currentName;
  final name = TextEditingController();
  final phone = TextEditingController();
  final note = TextEditingController();
  var days = 15;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nouveau devis', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('${cart.itemCount} article${cart.itemCount > 1 ? 's' : ''} · ${ctx.read<SettingsProvider>().settings.money(cart.total)}',
                  style: TextStyle(color: ctx.pal.muted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nom du client', prefixIcon: Icon(Icons.person_rounded)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Téléphone', prefixIcon: Icon(Icons.phone_rounded)),
              ),
              const SizedBox(height: 14),
              Text('Validité', style: TextStyle(color: ctx.pal.muted, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final d in const [7, 15, 30, 60])
                    ChoiceChip(label: Text('$d jours'), selected: days == d, onSelected: (_) => set(() => days = d)),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Remarques (facultatif)', prefixIcon: Icon(Icons.notes_rounded)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.description_rounded),
                  label: const Text('Créer le devis'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (ok != true) return false;
  final q = await prov.create(
    lines: cart.lines,
    discount: cart.discount,
    customer: name.text,
    phone: phone.text,
    note: note.text,
    validDays: days,
    seller: seller,
  );
  cart.clear();
  if (context.mounted) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => QuoteDetailScreen(quote: q)));
  }
  return true;
}

enum _Filter { all, pending, accepted, refused, expired }

class QuotesScreen extends StatefulWidget {
  const QuotesScreen({super.key});

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  _Filter _f = _Filter.all;
  String _q = '';

  static const _labels = {
    _Filter.all: 'Tous',
    _Filter.pending: 'En attente',
    _Filter.accepted: 'Acceptés',
    _Filter.refused: 'Refusés',
    _Filter.expired: 'Expirés',
  };

  bool _match(Quote q, DateTime now) {
    final okF = switch (_f) {
      _Filter.all => true,
      _Filter.pending => q.status == QuoteStatus.pending && !q.isExpired(now),
      _Filter.accepted => q.status == QuoteStatus.accepted,
      _Filter.refused => q.status == QuoteStatus.refused,
      _Filter.expired => q.isExpired(now),
    };
    final t = _q.toLowerCase();
    return okF && (t.isEmpty || q.customer.toLowerCase().contains(t) || q.number.toLowerCase().contains(t) || q.phone.contains(t));
  }

  @override
  Widget build(BuildContext context) {
    final all = context.watch<QuotesProvider>().quotes;
    final s = context.watch<SettingsProvider>().settings;
    final pal = context.pal;
    final now = DateTime.now();
    final shown = all.where((q) => _match(q, now)).toList();
    final open = all.where((q) => q.status == QuoteStatus.pending && !q.isExpired(now));
    final won = all.where((q) => q.status == QuoteStatus.accepted);
    final df = DateFormat('dd/MM/yyyy');

    Widget stat(String label, String value, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(18), boxShadow: pal.shadow),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: pal.muted, fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value, style: TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Devis')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(children: [
              stat('En attente', '${open.length} · ${s.money(open.fold(0.0, (a, q) => a + q.total))}', const Color(0xFFF59E0B)),
              const SizedBox(width: 10),
              stat('Acceptés', '${won.length} · ${s.money(won.fold(0.0, (a, q) => a + q.total))}', const Color(0xFF16A34A)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search_rounded), hintText: 'Client, numéro, téléphone'),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              children: [
                for (final f in _Filter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(_labels[f]!), selected: _f == f, onSelected: (_) => setState(() => _f = f)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.description_outlined, size: 54, color: pal.muted),
                          const SizedBox(height: 12),
                          const Text('Aucun devis', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('Remplissez le panier à la Caisse puis touchez « Créer un devis ».',
                              textAlign: TextAlign.center, style: TextStyle(color: pal.muted)),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final q = shown[i];
                      final c = quoteColor(q, now);
                      final left = q.daysLeft(now);
                      return Material(
                        color: pal.card,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuoteDetailScreen(quote: q))),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: pal.shadow),
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 54,
                                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(q.customer.isEmpty ? 'Client non renseigné' : q.customer,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                      const SizedBox(height: 2),
                                      Text('${q.number} · ${df.format(q.date)} · ${q.itemCount} art.',
                                          style: TextStyle(color: pal.muted, fontWeight: FontWeight.w600, fontSize: 13)),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                        decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                                        child: Text(
                                          q.status == QuoteStatus.pending && !q.isExpired(now) && left <= 3
                                              ? 'En attente · J-$left'
                                              : quoteStatusLabel(q, now),
                                          style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(s.money(q.total), style: TextStyle(color: pal.accent, fontWeight: FontWeight.w900, fontSize: 16)),
                              ],
                            ),
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
