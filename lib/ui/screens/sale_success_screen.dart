import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import '../i18n/text.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../data/printer_service.dart';
import '../../data/quote_share.dart';
import '../../data/settings_store.dart';
import '../../logic/settings_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import '../i18n/tr.dart';

/// Plain-text receipt, used for the WhatsApp / SMS receipt.
String saleReceiptText(Sale sale, AppSettings s) {
  final b = StringBuffer()
    ..writeln('🧾 ${s.storeName}')
    ..writeln('Ticket ${sale.id ?? ''} · ${DateFormat('dd/MM/yyyy HH:mm', 'fr_FR').format(sale.date)}')
    ..writeln();
  for (final l in sale.lines.take(15)) {
    b.writeln('• ${l.name} × ${fmtQty(l.qty)}${l.byWeight ? ' kg' : ''} — ${s.money(l.total)}');
  }
  if (sale.lines.length > 15) b.writeln('• … et ${sale.lines.length - 15} autre(s)');
  b.writeln();
  if (sale.discount > 0) b.writeln('Remise : −${s.money(sale.discount)}');
  b
    ..writeln('TOTAL : ${s.money(sale.total)}')
    ..writeln('Paiement : ${payMethodLabel(sale.method)}')
    ..writeln()
    ..write('Merci de votre visite !');
  return b.toString();
}

/// Celebration screen shown once a sale is saved: animated check, confetti, receipt actions.
class SaleSuccessScreen extends StatefulWidget {
  const SaleSuccessScreen({super.key, required this.sale});
  final Sale sale;

  @override
  State<SaleSuccessScreen> createState() => _SaleSuccessScreenState();
}

class _SaleSuccessScreenState extends State<SaleSuccessScreen> with TickerProviderStateMixin {
  late final _check = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  late final _confetti = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();
  late final _particles = _makeParticles();
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
  }

  @override
  void dispose() {
    _check.dispose();
    _confetti.dispose();
    super.dispose();
  }

  List<_Particle> _makeParticles() {
    final r = math.Random(7);
    const colors = [Color(0xFF2563EB), Color(0xFF12A150), Color(0xFFFBBF24), Color(0xFFFB7185), Color(0xFFA78BFA), Color(0xFF22D3EE)];
    return List.generate(46, (i) {
      final a = -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.25;
      return _Particle(
        angle: a,
        speed: 260 + r.nextDouble() * 380,
        size: 6 + r.nextDouble() * 7,
        color: colors[i % colors.length],
        spin: (r.nextDouble() - 0.5) * 12,
        round: i % 3 == 0,
      );
    });
  }

  Future<void> _whatsapp() async {
    final s = context.read<SettingsProvider>().settings;
    final c = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Envoyer le reçu'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: tr('Téléphone du client'), helperText: tr('Vide = choisir un contact dans WhatsApp')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('WhatsApp')),
        ],
      ),
    );
    if (phone == null || !mounted) return;
    final n = QuoteShare.internationalNumber(phone);
    final uri = Uri.parse('https://wa.me/${n ?? ''}?text=${Uri.encodeComponent(saleReceiptText(widget.sale, s))}');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) showMsg(context, "WhatsApp n'est pas installé");
    } catch (e) {
      if (mounted) showMsg(context, 'Action impossible : $e');
    }
  }

  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);
    final err = await context.read<PrinterService>().printSale(widget.sale, context.read<SettingsProvider>().settings);
    if (!mounted) return;
    setState(() => _printing = false);
    showMsg(context, err ?? 'Reçu imprimé');
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final s = context.watch<SettingsProvider>().settings;
    final sale = widget.sale;
    final change = sale.method == PayMethod.cash && sale.received != null ? round3(sale.received! - sale.total) : 0.0;
    const green = Color(0xFF12A150);

    return Scaffold(
      backgroundColor: pal.bg,
      body: Stack(children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _confetti,
              builder: (_, _) => CustomPaint(painter: _ConfettiPainter(_particles, _confetti.value)),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(children: [
              const Spacer(flex: 2),
              ScaleTransition(
                scale: CurvedAnimation(parent: _check, curve: const Interval(0, 0.6, curve: Curves.elasticOut)),
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [Color(0xFF34D673), green], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: [BoxShadow(color: green.withValues(alpha: 0.4), blurRadius: 30, offset: const Offset(0, 12))],
                  ),
                  child: AnimatedBuilder(
                    animation: _check,
                    builder: (_, _) => CustomPaint(painter: _CheckPainter(Curves.easeOut.transform(((_check.value - 0.35) / 0.55).clamp(0, 1)))),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Text(sale.method == PayMethod.credit ? 'Mis sur le compte !' : 'Vente encaissée !',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: sale.total),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Text(s.money(v),
                    style: TextStyle(fontSize: 46, fontWeight: FontWeight.w900, letterSpacing: -1.5, color: pal.accent)),
              ),
              const SizedBox(height: 6),
              Text(
                'Ticket ${sale.id ?? ''} · ${sale.itemCount} article${sale.itemCount > 1 ? 's' : ''} · ${payMethodLabel(sale.method)}',
                style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700),
              ),
              if (change > 0.0005) ...[
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  decoration: BoxDecoration(color: pal.goodBg, borderRadius: BorderRadius.circular(20)),
                  child: Column(children: [
                    Text('MONNAIE À RENDRE', style: TextStyle(color: pal.goodFg, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
                    const SizedBox(height: 2),
                    Text(s.money(change), style: TextStyle(color: pal.goodFg, fontWeight: FontWeight.w900, fontSize: 30)),
                  ]),
                ),
              ],
              const Spacer(flex: 3),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _whatsapp,
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('Reçu WhatsApp'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _printing ? null : _print,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Imprimer'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              PrimaryButton(
                onPressed: () => Navigator.pop(context),
                icon: Icons.add_shopping_cart_rounded,
                label: 'Nouvelle vente',
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Particle {
  _Particle({required this.angle, required this.speed, required this.size, required this.color, required this.spin, required this.round});
  final double angle, speed, size, spin;
  final Color color;
  final bool round;
}

/// Confetti bursting from behind the check mark, falling with gravity and fading out.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, this.t);
  final List<_Particle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.30);
    final secs = t * 2.6;
    for (final p in particles) {
      final dx = math.cos(p.angle) * p.speed * secs * (1 - 0.25 * t);
      final dy = math.sin(p.angle) * p.speed * secs + 420 * secs * secs;
      final alpha = (1 - ((t - 0.6) / 0.4).clamp(0.0, 1.0));
      final paint = Paint()..color = p.color.withValues(alpha: alpha);
      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(p.spin * secs);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55), const Radius.circular(2)), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// Check mark drawn progressively.
class _CheckPainter extends CustomPainter {
  _CheckPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final a = Offset(size.width * 0.30, size.height * 0.52);
    final b = Offset(size.width * 0.44, size.height * 0.66);
    final c = Offset(size.width * 0.72, size.height * 0.37);
    final path = Path()..moveTo(a.dx, a.dy);
    final l1 = (b - a).distance, l2 = (c - b).distance;
    final drawn = progress * (l1 + l2);
    if (drawn <= l1) {
      final p = a + (b - a) * (drawn / l1);
      path.lineTo(p.dx, p.dy);
    } else {
      path.lineTo(b.dx, b.dy);
      final p = b + (c - b) * ((drawn - l1) / l2);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}
