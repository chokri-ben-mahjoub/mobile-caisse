import 'package:flutter/material.dart' hide Text;
import '../i18n/text.dart';
import 'package:flutter/services.dart';

import '../../data/quote_share.dart';
import '../theme.dart';
import 'quote_preview_screen.dart';

/// Runs a share action and reports a failure (app missing, no handler…) in a snack bar.
Future<void> runShare(BuildContext context, Future<Object?> Function() action, {String? missing}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final r = await action();
    if (r == false) messenger.showSnackBar(SnackBar(content: Text(missing ?? 'Aucune application disponible pour cette action')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Action impossible : $e')));
  }
}

/// "Envoyer le devis": WhatsApp, SMS, e-mail, PDF share, download, preview.
Future<void> showQuoteShareSheet(BuildContext context, QuoteShare share) {
  final q = share.quote;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final pal = ctx.pal;

      Widget tile({
        required IconData icon,
        required String label,
        required String sub,
        required List<Color> colors,
        required VoidCallback onTap,
      }) =>
          Expanded(
            child: Material(
              color: pal.card,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), boxShadow: pal.shadow),
                  child: Column(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 5))],
                        ),
                        child: Icon(icon, color: Colors.white, size: 27),
                      ),
                      const SizedBox(height: 10),
                      Text(label, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(sub,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: pal.muted, fontSize: 11, fontWeight: FontWeight.w600, height: 1.2)),
                    ],
                  ),
                ),
              ),
            ),
          );

      void act(Future<Object?> Function() f, {String? missing}) {
        runShare(context, f, missing: missing);
      }

      final hasPhone = QuoteShare.internationalNumber(q.phone) != null;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Envoyer le devis', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                const SizedBox(height: 4),
                Text(
                  '${q.number} · ${q.customer.isEmpty ? 'client non renseigné' : q.customer}${q.phone.isEmpty ? '' : ' · ${q.phone}'}',
                  style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  tile(
                    icon: Icons.chat_rounded,
                    label: 'WhatsApp',
                    sub: hasPhone ? 'Message au client' : 'Choisir un contact',
                    colors: const [Color(0xFF34D673), Color(0xFF12A150)],
                    onTap: () {
                      Navigator.pop(ctx);
                      act(share.whatsapp, missing: 'WhatsApp n\'est pas installé');
                    },
                  ),
                  const SizedBox(width: 10),
                  tile(
                    icon: Icons.sms_rounded,
                    label: 'SMS',
                    sub: hasPhone ? 'Message au client' : 'Choisir un contact',
                    colors: const [Color(0xFF60A5FA), Color(0xFF2563EB)],
                    onTap: () {
                      Navigator.pop(ctx);
                      act(share.sms);
                    },
                  ),
                  const SizedBox(width: 10),
                  tile(
                    icon: Icons.email_rounded,
                    label: 'E-mail',
                    sub: 'Message prêt',
                    colors: const [Color(0xFFFB7185), Color(0xFFE11D48)],
                    onTap: () {
                      Navigator.pop(ctx);
                      act(share.email, missing: 'Aucune application e-mail');
                    },
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  tile(
                    icon: Icons.picture_as_pdf_rounded,
                    label: 'PDF',
                    sub: 'WhatsApp, Gmail, Drive…',
                    colors: const [Color(0xFFA78BFA), Color(0xFF6D28D9)],
                    onTap: () {
                      Navigator.pop(ctx);
                      act(share.sharePdf);
                    },
                  ),
                  const SizedBox(width: 10),
                  tile(
                    icon: Icons.download_rounded,
                    label: 'Télécharger',
                    sub: 'Enregistrer ou imprimer',
                    colors: const [Color(0xFFFBBF24), Color(0xFFEA580C)],
                    onTap: () {
                      Navigator.pop(ctx);
                      act(share.saveOrPrint);
                    },
                  ),
                  const SizedBox(width: 10),
                  tile(
                    icon: Icons.visibility_rounded,
                    label: 'Aperçu',
                    sub: 'Voir le PDF',
                    colors: const [Color(0xFF22D3EE), Color(0xFF0891B2)],
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => QuotePreviewScreen(share: share)));
                    },
                  ),
                ]),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: share.message()));
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copié')));
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copier le message'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
