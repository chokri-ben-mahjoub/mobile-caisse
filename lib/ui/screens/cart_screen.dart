import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../data/barcode_utils.dart';
import '../../data/models.dart';
import '../../logic/auth_provider.dart';
import '../../logic/cart_provider.dart';
import '../../logic/settings_provider.dart';
import '../../data/settings_store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'payment_screen.dart';
import 'product_form_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
  );
  bool _cameraOn = true;
  bool _busy = false; // a dialog / form is open: ignore detections
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _toast;
  bool _toastWarn = false;
  Timer? _toastTimer;

  @override
  void dispose() {
    _toastTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _flash(String text, {bool warn = false}) {
    setState(() {
      _toast = text;
      _toastWarn = warn;
    });
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _onCode(String code) async {
    if (_busy) return;
    // Same code seen again within 1.2 s is the same physical scan.
    final now = DateTime.now();
    if (code == _lastCode &&
        now.difference(_lastAt) < const Duration(milliseconds: 1200)) {
      _lastAt = now;
      return;
    }
    _lastCode = code;
    _lastAt = now;

    final cart = context.read<CartProvider>();
    final (result, product) = await cart.scan(code);
    if (!mounted) return;
    if (result == ScanResult.added) {
      final qty = cart.qtyOf(product!.barcode);
      if (product.tracked && qty > product.stock!) {
        _flash(
          '⚠ ${product.name} : stock insuffisant (${product.stock})',
          warn: true,
        );
      } else {
        _flash('✓ ${product.name} ajouté');
      }
      return;
    }
    _busy = true;
    final create = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.help_outline, size: 40),
        title: const Text('Produit inconnu'),
        content: Text(
          'Le code-barres $code n\'est pas dans votre base.\n\nVoulez-vous créer ce produit ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ignorer'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (create == true && mounted) {
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ProductFormScreen(barcode: code, addToCartAfterSave: true),
        ),
      );
      if (saved == true && mounted) _flash('✓ Produit créé et ajouté');
    }
    _busy = false;
    _lastAt = DateTime.now();
  }

  Future<void> _manualEntry() async {
    final ctrl = TextEditingController();
    _busy = true;
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Saisir un code-barres'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Code-barres'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    _busy = false;
    if (code != null && code.trim().isNotEmpty) {
      _lastCode = null;
      await _onCode(code.trim());
    }
  }

  Future<void> _discountDialog() async {
    final cart = context.read<CartProvider>();
    final s = context.read<SettingsProvider>().settings;
    var type = cart.discount?.type ?? DiscountType.percent;
    final ctrl = TextEditingController(
      text: cart.discount == null
          ? ''
          : cart.discount!.value.toString().replaceAll('.', ','),
    );
    final result = await showDialog<Discount?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
          final preview = v == null
              ? null
              : Discount(type, v).amountFor(cart.subtotal);
          return AlertDialog(
            title: const Text('Remise'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<DiscountType>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(
                      value: DiscountType.percent,
                      label: Text('Pourcentage %'),
                    ),
                    ButtonSegment(
                      value: DiscountType.amount,
                      label: Text('Montant ${s.currency}'),
                    ),
                  ],
                  selected: {type},
                  onSelectionChanged: (x) => setSt(() => type = x.first),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setSt(() {}),
                  decoration: InputDecoration(
                    labelText: type == DiscountType.percent
                        ? 'Pourcentage'
                        : 'Montant',
                  ),
                ),
                if (preview != null && preview > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Remise : −${s.money(preview)}  →  ${s.money(cart.subtotal - preview)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            actions: [
              if (cart.discount != null)
                TextButton(
                  onPressed: () => Navigator.pop(
                    ctx,
                    const Discount(DiscountType.amount, 0),
                  ),
                  child: const Text('Retirer'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
                onPressed: v == null || v <= 0
                    ? null
                    : () => Navigator.pop(ctx, Discount(type, v)),
                child: const Text('Appliquer'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null) cart.setDiscount(result);
  }

  Future<void> _showHeld() async {
    _busy = true;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Consumer2<CartProvider, SettingsProvider>(
        builder: (ctx, cart, st, _) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.6,
            ),
            child: cart.held.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('Aucun ticket en attente')),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Tickets en attente',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      for (final h in cart.held)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(
                              '${h.itemCount} article${h.itemCount > 1 ? 's' : ''} · ${st.settings.money(h.total)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${h.date.hour.toString().padLeft(2, '0')}:${h.date.minute.toString().padLeft(2, '0')} · '
                              '${h.lines.map((l) => l.name).take(3).join(', ')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => cart.deleteHeld(h),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(90, 40),
                                  ),
                                  onPressed: () async {
                                    if (!cart.isEmpty) {
                                      final ok = await showDialog<bool>(
                                        context: ctx,
                                        builder: (d) => AlertDialog(
                                          title: const Text(
                                            'Remplacer le panier actuel ?',
                                          ),
                                          content: const Text(
                                            "Mettez-le en attente d'abord pour le garder.",
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(d, false),
                                              child: const Text('Annuler'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(d, true),
                                              child: const Text('Remplacer'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (ok != true) return;
                                    }
                                    await cart.resume(h);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  },
                                  child: const Text('Reprendre'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
    _busy = false;
  }

  Future<void> _confirmClear() async {
    final cart = context.read<CartProvider>();
    if (cart.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vider le panier ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Vider'),
          ),
        ],
      ),
    );
    if (ok == true) cart.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final s = context.watch<SettingsProvider>().settings;
    final auth = context.watch<AuthProvider>();
    final lines = cart.lines;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    auth.enabled
                        ? InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: auth.logout,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: 15,
                                    color: context.pal.accent,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'Caisse · ${auth.currentName ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: context.pal.accent,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Text(
                            'Caisse',
                            style: TextStyle(
                              color: context.pal.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ],
                ),
              ),
              SoftIconButton(
                icon: Icons.keyboard_alt_outlined,
                tooltip: 'Saisir un code',
                onPressed: _manualEntry,
              ),
              SoftIconButton(
                icon: _cameraOn
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_outlined,
                tooltip: _cameraOn ? 'Couper la caméra' : 'Activer la caméra',
                onPressed: () => setState(() => _cameraOn = !_cameraOn),
              ),
              SoftIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Vider',
                color: const Color(0xFFDC2626),
                onPressed: _confirmClear,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TotalBanner(
            label: 'TOTAL À PAYER',
            amount: s.money(cart.total),
            sub: cart.discountAmount > 0
                ? 'Remise −${s.money(cart.discountAmount)}'
                : null,
            badge: '${cart.itemCount} article${cart.itemCount > 1 ? 's' : ''}',
          ),
        ),
        if (_cameraOn)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 176,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: (cap) {
                        final v = cap.barcodes.isEmpty
                            ? null
                            : cleanScan(cap.barcodes.first);
                        if (v != null) _onCode(v);
                      },
                      errorBuilder: (context, error) => const ColoredBox(
                        color: Colors.black87,
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Caméra indisponible.\nAutorisez la caméra dans les réglages Android.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const IgnorePointer(
                      child: CustomPaint(painter: _ViewfinderPainter()),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Row(
                        children: [
                          _ScannerButton(
                            icon: Icons.flashlight_on_rounded,
                            onPressed: () => _controller.toggleTorch(),
                          ),
                          const SizedBox(width: 6),
                          _ScannerButton(
                            icon: Icons.cameraswitch_rounded,
                            onPressed: () => _controller.switchCamera(),
                          ),
                        ],
                      ),
                    ),
                    if (_toast != null)
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 14,
                          ),
                          decoration: BoxDecoration(
                            color: _toastWarn
                                ? const Color(0xFFEA580C)
                                : const Color(0xFF16A34A),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            _toast!,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Articles scannés',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
              if (cart.held.isNotEmpty)
                SoftIconButton(
                  icon: Icons.pause_circle_outline_rounded,
                  tooltip: 'Tickets en attente',
                  badge: '${cart.held.length}',
                  onPressed: _showHeld,
                ),
              if (!cart.isEmpty) ...[
                SoftIconButton(
                  icon: Icons.pause_rounded,
                  tooltip: 'Mettre en attente',
                  onPressed: () async {
                    await cart.holdCurrent();
                    _flash('Ticket mis en attente');
                  },
                ),
                if (auth.can(Perm.discount))
                  SoftIconButton(
                    icon: Icons.sell_rounded,
                    tooltip: 'Remise',
                    color: cart.discount != null
                        ? const Color(0xFF16A34A)
                        : null,
                    onPressed: _discountDialog,
                  ),
              ],
            ],
          ),
        ),
        Expanded(
          child: cart.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: context.pal.soft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.qr_code_scanner_rounded,
                          size: 42,
                          color: context.pal.accent,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Scannez un produit',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Les articles apparaissent ici',
                        style: TextStyle(color: context.pal.muted),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  itemCount: lines.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) =>
                      _LineCard(line: lines[i], settings: s, cart: cart),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: PrimaryButton(
            icon: Icons.check_circle_rounded,
            label: 'Valider la commande',
            trailing: cart.isEmpty ? null : s.money(cart.total),
            onPressed: cart.isEmpty
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PaymentScreen()),
                  ),
          ),
        ),
      ],
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.settings,
    required this.cart,
  });
  final SaleLine line;
  final AppSettings settings;
  final CartProvider cart;

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, VoidCallback onTap, {bool filled = false}) =>
        Material(
          color: filled ? kBlue : context.pal.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(
                icon,
                color: filled ? Colors.white : context.pal.accent,
                size: 22,
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: context.pal.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: context.pal.shadow,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.pal.soft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              line.name.isEmpty
                  ? '?'
                  : line.name.characters.first.toUpperCase(),
              style: TextStyle(
                color: context.pal.accent,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${settings.money(line.price)} × ${line.qty}',
                  style: TextStyle(
                    color: context.pal.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  settings.money(line.total),
                  style: TextStyle(
                    color: context.pal.accent,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: context.pal.soft2,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                step(Icons.remove_rounded, () => cart.decrement(line.barcode)),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${line.qty}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                step(
                  Icons.add_rounded,
                  () => cart.increment(line.barcode),
                  filled: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerButton extends StatelessWidget {
  const _ScannerButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black38,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onPressed,
      child: SizedBox(
        width: 38,
        height: 38,
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    ),
  );
}

/// Corner brackets and a scan line over the camera preview.
class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      size.width * 0.14,
      size.height * 0.2,
      size.width * 0.72,
      size.height * 0.6,
    );
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const l = 26.0;
    for (final (cx, cy, dx, dy) in [
      (r.left, r.top, 1.0, 1.0),
      (r.right, r.top, -1.0, 1.0),
      (r.left, r.bottom, 1.0, -1.0),
      (r.right, r.bottom, -1.0, -1.0),
    ]) {
      canvas.drawLine(Offset(cx, cy), Offset(cx + dx * l, cy), p);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy + dy * l), p);
    }
    final line = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x00EF4444), Color(0xFFEF4444), Color(0x00EF4444)],
      ).createShader(Rect.fromLTWH(r.left, 0, r.width, 1))
      ..strokeWidth = 2.5;
    canvas.drawLine(
      Offset(r.left, size.height / 2),
      Offset(r.right, size.height / 2),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
