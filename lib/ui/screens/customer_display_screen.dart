import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../logic/cart_provider.dart';
import '../../logic/sales_provider.dart';
import '../../logic/settings_provider.dart';
import '../i18n/text.dart';
import '../theme.dart';

/// Customer-facing screen: turn the phone toward the customer and they follow the basket live,
/// with big letters, the total, and a thank-you with the change after payment.
/// The customer can switch French / Arabic with the button in the corner; the cashier leaves
/// the mode by long-pressing the cross.
class CustomerDisplayScreen extends StatefulWidget {
  const CustomerDisplayScreen({super.key});

  @override
  State<CustomerDisplayScreen> createState() => _CustomerDisplayScreenState();
}

class _CustomerDisplayScreenState extends State<CustomerDisplayScreen> {
  late bool _ar = context.read<SettingsProvider>().settings.language == 'ar';
  Timer? _tick;

  /// How long the thank-you stays on screen after a sale.
  static const _thanksFor = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Re-evaluate the thank-you timeout.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Sale? _justPaid(SalesProvider sales, CartProvider cart) {
    if (!cart.isEmpty || sales.sales.isEmpty) return null;
    final s = sales.sales.first;
    if (s.isRefund || DateTime.now().difference(s.date) > _thanksFor) return null;
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final sales = context.watch<SalesProvider>();
    final settings = context.watch<SettingsProvider>().settings;
    final paid = _justPaid(sales, cart);

    final locale = Locale(_ar ? 'ar' : 'fr');
    final font = _ar ? 'Tajawal' : null;
    return PopScope(
      canPop: false,
      child: Localizations.override(
        context: context,
        locale: locale,
        child: DefaultTextStyle.merge(
          style: TextStyle(fontFamily: font, color: Colors.white),
          child: Scaffold(
            backgroundColor: const Color(0xFF0B1B4D),
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppAccent.current.deep, Color.lerp(AppAccent.current.deep, Colors.black, 0.6)!],
                ),
              ),
              child: SafeArea(
                child: Column(children: [
                  _header(settings.storeName),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      child: paid != null
                          ? _Thanks(key: const ValueKey('thanks'), sale: paid, money: settings.money)
                          : cart.isEmpty
                              ? const _Welcome(key: ValueKey('welcome'))
                              : _Basket(key: const ValueKey('basket'), cart: cart, money: settings.money),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(String store) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(store, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          ),
          // The customer picks the language of this screen.
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _ar = !_ar);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.translate_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 6),
                Text(_ar ? 'Français' : 'عربي', style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: _ar ? 'اضغط مطوّلا باش تخرج' : 'Maintenez pour quitter',
            child: GestureDetector(
              onLongPress: () => Navigator.pop(context),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
              ),
            ),
          ),
        ]),
      );
}

class _Welcome extends StatelessWidget {
  const _Welcome({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.12)),
              child: const Icon(Icons.shopping_basket_rounded, size: 60, color: Colors.white),
            ),
            const SizedBox(height: 26),
            const Text('Bienvenue', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('Vos articles apparaissent ici',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

class _Basket extends StatelessWidget {
  const _Basket({super.key, required this.cart, required this.money});
  final CartProvider cart;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final lines = cart.lines.reversed.toList(); // newest on top
    return Column(children: [
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          itemCount: lines.length,
          itemBuilder: (_, i) {
            final l = lines[i];
            final newest = i == 0;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: newest ? 0.20 : 0.10),
                borderRadius: BorderRadius.circular(20),
                border: newest ? Border.all(color: Colors.white38, width: 1.5) : null,
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('${fmtQty(l.qty, unit: l.unit)} × ${money(l.price)}',
                        style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(width: 10),
                Text(money(l.total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ]),
            );
          },
        ),
      ),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 22),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (cart.discountAmount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                const Text('Remise', style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.w800, fontSize: 17)),
                const Spacer(),
                Text('−${money(cart.discountAmount)}', style: const TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.w900, fontSize: 17)),
              ]),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${cart.itemCount} article${cart.itemCount > 1 ? 's' : ''}',
                style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800, fontSize: 16)),
            const Spacer(),
            const Text('TOTAL', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.5)),
          ]),
          const SizedBox(height: 2),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: cart.total, end: cart.total),
            duration: const Duration(milliseconds: 300),
            builder: (_, v, _) => FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(money(v), style: TextStyle(color: AppAccent.current.deep, fontSize: 58, fontWeight: FontWeight.w900, letterSpacing: -2)),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _Thanks extends StatelessWidget {
  const _Thanks({super.key, required this.sale, required this.money});
  final Sale sale;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final change = sale.method == PayMethod.cash && sale.received != null ? round3(sale.received! - sale.total) : 0.0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF34D673), Color(0xFF12A150)])),
            child: const Icon(Icons.check_rounded, size: 76, color: Colors.white),
          ),
          const SizedBox(height: 24),
          const Text('Merci !', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(money(sale.total), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
          if (change > 0.0005) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(22)),
              child: Column(children: [
                Text('Monnaie à rendre', style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w700)),
                Text(money(change), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
              ]),
            ),
          ],
          const SizedBox(height: 22),
          Text('À bientôt', style: TextStyle(fontSize: 20, color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
