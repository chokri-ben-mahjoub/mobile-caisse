import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../data/barcode_utils.dart';
import '../../data/models.dart';
import '../../logic/auth_provider.dart';
import '../../logic/cart_provider.dart';
import '../../logic/products_provider.dart';
import '../../logic/settings_provider.dart';
import '../../data/settings_store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/quick_keypad.dart';
import '../widgets/swipe_to_pay.dart';
import 'closing_screen.dart';
import 'payment_screen.dart';
import 'product_form_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  int _mult = 1;
  (String, double)? _last;
  String _q = '';
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
    switch (result) {
      case ScanResult.added:
        _announceAdded(product!);
        return;
      case ScanResult.weighed:
        await _addWeighed(product!);
        return;
      case ScanResult.unknown:
        break;
    }
    if (!mounted) return;
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
      final saved = await Navigator.push<Product>(
        context,
        MaterialPageRoute(builder: (_) => ProductFormScreen(barcode: code)),
      );
      if (saved != null && mounted) {
        if (saved.byWeight) {
          await _addWeighed(saved);
        } else {
          cart.add(saved);
          _flash('✓ Produit créé et ajouté');
        }
      }
    }
    _busy = false;
    _lastAt = DateTime.now();
  }

  /// Confirmation after a unit product was added; warns when stock runs short.
  void _announceAdded(Product product) {
    final qty = context.read<CartProvider>().qtyOf(product.barcode);
    if (product.tracked && qty > product.stock!) {
      _flash(
        '⚠ ${product.name} : stock insuffisant (${fmtQty(product.stock!, unit: product.unit)})',
        warn: true,
      );
    } else {
      _flash('✓ ${product.name} ajouté');
    }
  }

  /// Catalogue of every article as big tiles (favourites first) in a sheet that
  /// stays open, so a whole basket can be rung up with taps.
  void _openCatalog() {
    _q = '';
    _busy = true;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final cart = ctx.watch<CartProvider>();
          final s = ctx.watch<SettingsProvider>().settings;
          final all = ctx.watch<ProductsProvider>().all;
          final catalog = [
            ...all.where((p) => p.favorite),
            ...all.where((p) => !p.favorite),
          ].where((p) => _q.isEmpty || p.name.toLowerCase().contains(_q) || p.barcode.contains(_q)).toList();
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Articles',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                      ),
                      Text('${cart.itemCount} · ${s.money(cart.total)}',
                          style: TextStyle(color: ctx.pal.accent, fontWeight: FontWeight.w900, fontSize: 16)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: TextField(
                    onChanged: (v) => set(() => _q = v.trim().toLowerCase()),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Chercher un article',
                    ),
                  ),
                ),
                SizedBox(
                  height: 50,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    children: [
                      for (final n in const [1, 2, 3, 5, 10])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('×$n', style: const TextStyle(fontWeight: FontWeight.w900)),
                            selected: _mult == n,
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              set(() => _mult = n);
                            },
                          ),
                        ),
                      if (_last != null)
                        ActionChip(
                          avatar: const Icon(Icons.undo_rounded, size: 18),
                          label: const Text('Annuler'),
                          onPressed: () {
                            _undoLast();
                            set(() {});
                          },
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: catalog.isEmpty
                      ? Center(child: Text('Aucun article', style: TextStyle(color: ctx.pal.muted)))
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: LayoutBuilder(
                            builder: (ctx, c) {
                              const gap = 8.0;
                              final w = (c.maxWidth - gap * 2) / 3;
                              return Wrap(
                                spacing: gap,
                                runSpacing: gap + 2,
                                children: [
                                  for (final f in catalog)
                                    _QuickTile(
                                      product: f,
                                      width: w,
                                      price: s.money(f.price),
                                      inCart: cart.qtyOf(f.barcode),
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        _quickAdd(f);
                                      },
                                      onLongPress: f.byWeight || cart.qtyOf(f.barcode) <= 0
                                          ? null
                                          : () {
                                              HapticFeedback.mediumImpact();
                                              cart.decrement(f.barcode);
                                            },
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: PrimaryButton(
                    icon: Icons.check_rounded,
                    label: 'Terminé',
                    trailing: cart.isEmpty ? null : s.money(cart.total),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      _busy = false;
      _q = '';
    });
  }

  /// One tap on a quick-access product.
  Future<void> _quickAdd(Product p) async {
    if (p.byWeight) {
      await _addWeighed(p);
    } else {
      final n = _mult.toDouble();
      context.read<CartProvider>().add(p, qty: n);
      SystemSound.play(SystemSoundType.click);
      setState(() {
        _last = (p.barcode, n);
        _mult = 1;
      });
      _announceAdded(p);
    }
  }

  void _undoLast() {
    final l = _last;
    if (l == null) return;
    final cart = context.read<CartProvider>();
    final left = cart.qtyOf(l.$1) - l.$2;
    HapticFeedback.mediumImpact();
    cart.setQty(l.$1, left);
    setState(() => _last = null);
  }

  Future<void> _addWeighed(Product p) async {
    final w = await _askWeight(name: p.name, pricePerKg: p.price);
    if (w == null || !mounted) return;
    context.read<CartProvider>().add(p, qty: w);
    _announceAdded(p);
  }

  Future<void> _editWeight(SaleLine l) async {
    final w = await _askWeight(name: l.name, pricePerKg: l.price, initial: l.qty);
    if (w == null || !mounted) return;
    context.read<CartProvider>().setQty(l.barcode, w);
  }

  /// Asks the weight in kg (with 250 g / 500 g / 1 kg shortcuts) and shows the total.
  Future<double?> _askWeight({
    required String name,
    required double pricePerKg,
    double? initial,
  }) async {
    final s = context.read<SettingsProvider>().settings;
    final ctrl = TextEditingController(text: initial == null ? '' : fmtQty(initial));
    _busy = true;
    final w = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
          final ok = v != null && v > 0;
          return AlertDialog(
            icon: const Icon(Icons.scale_rounded, size: 36),
            title: Text(name, textAlign: TextAlign.center),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${s.money(pricePerKg)} / kg',
                    style: TextStyle(color: ctx.pal.muted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  onChanged: (_) => setSt(() {}),
                  onSubmitted: (_) {
                    if (ok) Navigator.pop(ctx, v);
                  },
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  decoration: const InputDecoration(labelText: 'Poids', suffixText: 'kg'),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final e in const {'250 g': 0.25, '500 g': 0.5, '1 kg': 1.0}.entries)
                      ActionChip(
                        label: Text(e.key),
                        onPressed: () => setSt(() => ctrl.text = fmtQty(e.value)),
                      ),
                  ],
                ),
                if (ok)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('Total : ${s.money(round3(v * pricePerKg))}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
                onPressed: ok ? () => Navigator.pop(ctx, v) : null,
                child: const Text('Ajouter'),
              ),
            ],
          );
        },
      ),
    );
    _busy = false;
    return w;
  }

  /// An article that is not in the base: name, price, quantity.
  Future<void> _addFreeArticle() async {
    final s = context.read<SettingsProvider>().settings;
    final name = TextEditingController();
    final price = TextEditingController();
    final qty = TextEditingController(text: '1');
    _busy = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final p = double.tryParse(price.text.trim().replaceAll(',', '.'));
          final q = double.tryParse(qty.text.trim().replaceAll(',', '.'));
          final valid = p != null && p > 0 && q != null && q > 0;
          return AlertDialog(
            icon: const Icon(Icons.add_shopping_cart_rounded, size: 36),
            title: const Text('Article libre'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nom (facultatif)', hintText: 'Article'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: price,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        onChanged: (_) => setSt(() {}),
                        decoration: InputDecoration(labelText: 'Prix', suffixText: s.currency),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: qty,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        onChanged: (_) => setSt(() {}),
                        decoration: const InputDecoration(labelText: 'Qté'),
                      ),
                    ),
                  ],
                ),
                if (valid)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('Total : ${s.money(round3(p * q))}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
                onPressed: valid ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Ajouter'),
              ),
            ],
          );
        },
      ),
    );
    _busy = false;
    if (ok != true || !mounted) return;
    final label = name.text.trim().isEmpty ? 'Article' : name.text.trim();
    context.read<CartProvider>().addFree(
          name: label,
          price: double.parse(price.text.trim().replaceAll(',', '.')),
          qty: double.parse(qty.text.trim().replaceAll(',', '.')),
        );
    _flash('✓ $label ajouté');
  }

  void _onMenu(String v) {
    switch (v) {
      case 'code':
        _manualEntry();
      case 'clear':
        _confirmClear();
      case 'closing':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ClosingScreen()));
    }
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
                icon: _cameraOn
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_outlined,
                tooltip: _cameraOn ? 'Couper la caméra' : 'Activer la caméra',
                onPressed: () => setState(() => _cameraOn = !_cameraOn),
              ),
              SoftIconButton(
                icon: Icons.grid_view_rounded,
                tooltip: 'Articles',
                onPressed: _openCatalog,
              ),
              SoftIconButton(
                icon: Icons.dialpad_rounded,
                tooltip: 'Clavier de prix (saisie rapide)',
                onPressed: () => QuickKeypad.show(context),
              ),
              SoftIconButton(
                icon: Icons.add_shopping_cart_rounded,
                tooltip: 'Article libre (sans code-barres)',
                onPressed: _addFreeArticle,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: PopupMenuButton<String>(
                  tooltip: 'Plus',
                  onSelected: _onMenu,
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'code', child: Text('Saisir un code-barres')),
                    const PopupMenuItem(value: 'clear', child: Text('Vider le panier')),
                    if (auth.can(Perm.closing))
                      const PopupMenuItem(value: 'closing', child: Text('Clôture de caisse')),
                  ],
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: context.pal.card,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: context.pal.shadow,
                    ),
                    child: Icon(Icons.more_vert_rounded, color: context.pal.accent, size: 22),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_cameraOn)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 224,
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
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Articles scannés',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.3)),
                    Text(
                      cart.discountAmount > 0
                          ? '${cart.itemCount} article${cart.itemCount > 1 ? 's' : ''} · remise −${s.money(cart.discountAmount)}'
                          : '${cart.itemCount} article${cart.itemCount > 1 ? 's' : ''}',
                      style: TextStyle(color: context.pal.muted, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('TOTAL À PAYER',
                      style: TextStyle(
                          color: context.pal.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                  Text(s.money(cart.total),
                      style: TextStyle(
                          color: context.pal.accent, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
                ],
              ),
            ],
          ),
        ),
        if (cart.held.isNotEmpty || !cart.isEmpty)
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              children: [
                if (cart.held.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.pause_circle_outline_rounded, size: 18),
                      label: Text('En attente (${cart.held.length})'),
                      onPressed: _showHeld,
                    ),
                  ),
                if (!cart.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.pause_rounded, size: 18),
                      label: const Text('Mettre en attente'),
                      onPressed: () async {
                        await cart.holdCurrent();
                        _flash('Ticket mis en attente');
                      },
                    ),
                  ),
                if (!cart.isEmpty && auth.can(Perm.discount))
                  ActionChip(
                    avatar: Icon(Icons.sell_rounded,
                        size: 18, color: cart.discount != null ? const Color(0xFF16A34A) : null),
                    label: Text(cart.discount != null ? 'Remise active' : 'Remise'),
                    onPressed: _discountDialog,
                  ),
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
                        'Scannez ou touchez un article',
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
                      _LineCard(
                    line: lines[i],
                    settings: s,
                    cart: cart,
                    onEditWeight: () => _editWeight(lines[i]),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Row(
            children: [
              Material(
                color: context.pal.card,
                borderRadius: BorderRadius.circular(30),
                child: InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: _openCatalog,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: context.pal.shadow,
                    ),
                    child: Icon(Icons.grid_view_rounded, color: context.pal.accent, size: 26),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SwipeToPay(
            label: cart.isEmpty ? 'Ajoutez des articles' : 'Glisser pour encaisser',
            trailing: cart.isEmpty ? null : s.money(cart.total),
            onConfirm: cart.isEmpty
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PaymentScreen()),
                  ),
          ),
              ),
            ],
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
    this.onEditWeight,
  });
  final SaleLine line;
  final AppSettings settings;
  final CartProvider cart;
  final VoidCallback? onEditWeight;

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

    final weightPill = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: context.pal.soft2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onEditWeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.scale_rounded, size: 18, color: context.pal.accent),
                  const SizedBox(width: 6),
                  Text(
                    fmtQty(line.qty, unit: 'kg'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        step(Icons.close_rounded, () => cart.remove(line.barcode)),
      ],
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
                  '${settings.money(line.price)}${line.byWeight ? '/kg' : ''} × ${fmtQty(line.qty, unit: line.unit)}',
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
          line.byWeight
              ? weightPill
              : Container(
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
                    fmtQty(line.qty),
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


/// Big one-tap tile of the quick-access grid: tap adds one, long press removes
/// one, and the badge shows what is already in the basket.
class _QuickTile extends StatefulWidget {
  const _QuickTile({
    required this.product,
    required this.width,
    required this.price,
    required this.inCart,
    required this.onTap,
    this.onLongPress,
  });

  final Product product;
  final double width;
  final String price;
  final double inCart;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<_QuickTile> createState() => _QuickTileState();
}

class _QuickTileState extends State<_QuickTile> {
  static const _hues = [
    Color(0xFF3B82F6), Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFFF97316),
    Color(0xFF10B981), Color(0xFF06B6D4), Color(0xFFEAB308), Color(0xFFEF4444),
  ];
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final p = widget.product;
    final hue = _hues[p.name.codeUnits.fold(0, (a, b) => a + b) % _hues.length];
    final active = widget.inCart > 0;
    return AnimatedScale(
      scale: _down ? 0.94 : 1,
      duration: const Duration(milliseconds: 90),
      child: SizedBox(
        width: widget.width,
        height: 76,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  color: active ? hue.withValues(alpha: 0.16) : pal.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: active ? hue : Colors.transparent, width: 1.6),
                  boxShadow: pal.shadow,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: widget.onTap,
                    onLongPress: widget.onLongPress,
                    onHighlightChanged: (v) => setState(() => _down = v),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [hue, hue.withValues(alpha: 0.65)]),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: p.byWeight
                                  ? const Icon(Icons.scale_rounded, size: 13, color: Colors.white)
                                  : Text(p.name.isEmpty ? '?' : p.name.characters.first.toUpperCase(),
                                      style: const TextStyle(
                                          color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          Text('${widget.price}${p.byWeight ? '/kg' : ''}',
                              style: TextStyle(color: hue, fontWeight: FontWeight.w900, fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (active)
              Positioned(
                top: -7,
                right: -4,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: hue, borderRadius: BorderRadius.circular(10)),
                    child: Text(fmtQty(widget.inCart, unit: p.byWeight ? p.unit : ''),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
