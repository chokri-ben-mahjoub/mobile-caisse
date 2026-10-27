import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../logic/cart_provider.dart';
import '../../logic/settings_provider.dart';
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
    if (code == _lastCode && now.difference(_lastAt) < const Duration(milliseconds: 1200)) {
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
        _flash('⚠ ${product.name} : stock insuffisant (${product.stock})', warn: true);
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
        content: Text('Le code-barres $code n\'est pas dans votre base.\n\nVoulez-vous créer ce produit ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ignorer')),
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
        MaterialPageRoute(builder: (_) => ProductFormScreen(barcode: code, addToCartAfterSave: true)),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
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
        text: cart.discount == null ? '' : cart.discount!.value.toString().replaceAll('.', ','));
    final result = await showDialog<Discount?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
          final preview = v == null ? null : Discount(type, v).amountFor(cart.subtotal);
          return AlertDialog(
            title: const Text('Remise'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<DiscountType>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: DiscountType.percent, label: Text('Pourcentage %')),
                    ButtonSegment(value: DiscountType.amount, label: Text('Montant ${s.currency}')),
                  ],
                  selected: {type},
                  onSelectionChanged: (x) => setSt(() => type = x.first),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setSt(() {}),
                  decoration: InputDecoration(labelText: type == DiscountType.percent ? 'Pourcentage' : 'Montant'),
                ),
                if (preview != null && preview > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('Remise : −${s.money(preview)}  →  ${s.money(cart.subtotal - preview)}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            actions: [
              if (cart.discount != null)
                TextButton(
                    onPressed: () => Navigator.pop(ctx, const Discount(DiscountType.amount, 0)),
                    child: const Text('Retirer')),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
                onPressed: v == null || v <= 0 ? null : () => Navigator.pop(ctx, Discount(type, v)),
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
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
            child: cart.held.isEmpty
                ? const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucun ticket en attente')))
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('Tickets en attente', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      ),
                      for (final h in cart.held)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(
                                '${h.itemCount} article${h.itemCount > 1 ? 's' : ''} · ${st.settings.money(h.total)}',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${h.date.hour.toString().padLeft(2, '0')}:${h.date.minute.toString().padLeft(2, '0')} · '
                              '${h.lines.map((l) => l.name).take(3).join(', ')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => cart.deleteHeld(h),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
                                onPressed: () async {
                                  if (!cart.isEmpty) {
                                    final ok = await showDialog<bool>(
                                      context: ctx,
                                      builder: (d) => AlertDialog(
                                        title: const Text('Remplacer le panier actuel ?'),
                                        content: const Text("Mettez-le en attente d'abord pour le garder."),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
                                          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remplacer')),
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
                            ]),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
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

    return Column(
      children: [
        AppBar(
          title: Text(s.storeName),
          actions: [
            IconButton(tooltip: 'Saisir un code', icon: const Icon(Icons.keyboard_alt_outlined), onPressed: _manualEntry),
            IconButton(
              tooltip: _cameraOn ? 'Couper la caméra' : 'Activer la caméra',
              icon: Icon(_cameraOn ? Icons.videocam : Icons.videocam_off_outlined),
              onPressed: () => setState(() => _cameraOn = !_cameraOn),
            ),
            IconButton(tooltip: 'Vider', icon: const Icon(Icons.delete_outline), onPressed: _confirmClear),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TotalBanner(label: 'TOTAL', sub: cart.discountAmount > 0
                ? '${cart.itemCount} articles · remise −${s.money(cart.discountAmount)}'
                : '${cart.itemCount} articles', amount: s.money(cart.total)),
        ),
        if (_cameraOn)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 170,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: (cap) {
                        final v = cap.barcodes.isEmpty ? null : cap.barcodes.first.rawValue;
                        if (v != null && v.isNotEmpty) _onCode(v);
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
                    Center(child: Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 24), color: Colors.redAccent)),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Row(children: [
                        IconButton(
                          color: Colors.white,
                          icon: const Icon(Icons.flashlight_on_outlined),
                          onPressed: () => _controller.toggleTorch(),
                        ),
                        IconButton(
                          color: Colors.white,
                          icon: const Icon(Icons.cameraswitch_outlined),
                          onPressed: () => _controller.switchCamera(),
                        ),
                      ]),
                    ),
                    if (_toast != null)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(color: _toastWarn ? Colors.orange.shade800 : Colors.green.shade700, borderRadius: BorderRadius.circular(8)),
                          child: Text(_toast!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text('Articles scannés', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              if (cart.held.isNotEmpty)
                IconButton(
                  tooltip: 'Tickets en attente',
                  icon: Badge(label: Text('${cart.held.length}'), child: const Icon(Icons.pause_circle_outline)),
                  onPressed: _showHeld,
                ),
              if (!cart.isEmpty) ...[
                IconButton(
                  tooltip: 'Mettre en attente',
                  icon: const Icon(Icons.pause_circle_filled_outlined),
                  onPressed: () async {
                    await cart.holdCurrent();
                    _flash('Ticket mis en attente');
                  },
                ),
                IconButton(
                  tooltip: 'Remise',
                  icon: Icon(Icons.sell_outlined, color: cart.discount != null ? Colors.green.shade700 : null),
                  onPressed: _discountDialog,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: cart.isEmpty
              ? const Center(child: Text('Scannez un produit pour commencer', style: TextStyle(color: Colors.black54)))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: cart.lines.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final l = cart.lines[i];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text('${s.money(l.price)} → ${s.money(l.total)}',
                                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                ],
                              ),
                            ),
                            IconButton.filledTonal(
                              onPressed: () => cart.decrement(l.barcode),
                              icon: const Icon(Icons.remove),
                            ),
                            SizedBox(
                              width: 32,
                              child: Text('${l.qty}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                            ),
                            IconButton.filled(
                              onPressed: () => cart.increment(l.barcode),
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: cart.isEmpty
                ? null
                : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentScreen())),
            icon: const Icon(Icons.check),
            label: const Text('Valider la commande'),
          ),
        ),
      ],
    );
  }
}
