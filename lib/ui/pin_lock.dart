import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../logic/auth_provider.dart';

/// Full-page numeric keypad shown instead of a protected tab while locked.
class PinLockView extends StatefulWidget {
  const PinLockView({super.key, required this.title});
  final String title;

  @override
  State<PinLockView> createState() => _PinLockViewState();
}

class _PinLockViewState extends State<PinLockView> {
  String _pin = '';
  bool _error = false;

  void _tap(String d) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += d;
      _error = false;
    });
    if (_pin.length == 4) {
      final ok = context.read<AuthProvider>().unlock(_pin);
      if (!ok) {
        HapticFeedback.heavyImpact();
        setState(() {
          _pin = '';
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget key(String d) => SizedBox(
          width: 76,
          height: 64,
          child: TextButton(
            style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () => _tap(d),
            child: Text(d, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
          ),
        );

    return Column(
      children: [
        AppBar(title: Text(widget.title)),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 40, color: cs.primary),
                  const SizedBox(height: 8),
                  const Text('Entrez le code PIN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 4; i++)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _pin.length ? cs.primary : Colors.transparent,
                            border: Border.all(color: _error ? cs.error : cs.primary, width: 2),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(
                    height: 28,
                    child: _error ? Text('Code incorrect', style: TextStyle(color: cs.error)) : null,
                  ),
                  for (final row in const [
                    ['1', '2', '3'],
                    ['4', '5', '6'],
                    ['7', '8', '9']
                  ])
                    Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) key(d)]),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 76, height: 64),
                      key('0'),
                      SizedBox(
                        width: 76,
                        height: 64,
                        child: IconButton(
                          icon: const Icon(Icons.backspace_outlined),
                          onPressed: () => setState(() {
                            if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
                          }),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Asks for a new 4-digit PIN (twice). Returns it, or null if cancelled.
Future<String?> askNewPin(BuildContext context) {
  final a = TextEditingController();
  final b = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Nouveau code PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (c, label) in [(a, 'Code PIN (4 chiffres)'), (b, 'Confirmer le code')])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: c,
                  obscureText: true,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: label, counterText: ''),
                ),
              ),
            if (error != null) Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () {
              if (a.text.length != 4) {
                setState(() => error = 'Le code doit avoir 4 chiffres');
              } else if (a.text != b.text) {
                setState(() => error = 'Les deux codes sont différents');
              } else {
                Navigator.pop(ctx, a.text);
              }
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    ),
  );
}
