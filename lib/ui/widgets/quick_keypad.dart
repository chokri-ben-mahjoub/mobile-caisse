import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../logic/cart_provider.dart';
import '../../logic/settings_provider.dart';
import '../theme.dart';

/// Number pad for ringing up prices without a barcode: type the price, tap
/// "Ajouter", repeat. The sheet stays open so a whole basket goes in quickly.
class QuickKeypad extends StatefulWidget {
  const QuickKeypad({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const QuickKeypad(),
      );

  @override
  State<QuickKeypad> createState() => _QuickKeypadState();
}

class _QuickKeypadState extends State<QuickKeypad> {
  String _txt = '';
  int _count = 0;

  double? get _value => double.tryParse(_txt.isEmpty ? '' : _txt);

  void _key(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      if (k == '⌫') {
        if (_txt.isNotEmpty) _txt = _txt.substring(0, _txt.length - 1);
      } else if (k == '.') {
        if (!_txt.contains('.')) _txt = _txt.isEmpty ? '0.' : '$_txt.';
      } else {
        final dot = _txt.indexOf('.');
        if (dot >= 0 && _txt.length - dot > 3) return; // 3 decimals max
        if (_txt.length >= 9) return;
        _txt = _txt == '0' ? k : '$_txt$k';
      }
    });
  }

  void _add() {
    final v = _value;
    if (v == null || v <= 0) return;
    HapticFeedback.mediumImpact();
    context.read<CartProvider>().addFree(name: 'Article', price: v);
    setState(() {
      _txt = '';
      _count++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().settings;
    final cart = context.watch<CartProvider>();
    final pal = context.pal;
    final v = _value;
    final ok = v != null && v > 0;

    Widget key(String k, {Color? bg, Color? fg}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Material(
              color: bg ?? pal.card,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _key(k),
                child: SizedBox(
                  height: 58,
                  child: Center(
                    child: Text(k,
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: fg)),
                  ),
                ),
              ),
            ),
          ),
        );

    Widget row(List<String> ks) => Row(children: [for (final k in ks) key(k)]);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _count == 0 ? 'Clavier de prix' : '$_count ajouté${_count > 1 ? 's' : ''} · panier ${s.money(cart.total)}',
                    style: TextStyle(color: pal.muted, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Terminé')),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(16)),
              child: Text(
                _txt.isEmpty ? s.money(0) : '${_txt.replaceAll('.', ',')} ${s.currency}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: _txt.isEmpty ? pal.muted : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
            row(['1', '2', '3']),
            row(['4', '5', '6']),
            row(['7', '8', '9']),
            row(['.', '0', '⌫']),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: ok ? _add : null,
                icon: const Icon(Icons.add_rounded),
                label: Text(ok ? 'Ajouter ${s.money(v)}' : 'Ajouter'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
