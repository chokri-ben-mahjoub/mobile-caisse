import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/biometric_service.dart';
import '../data/models.dart';
import '../logic/auth_provider.dart';
import '../logic/settings_provider.dart';
import 'theme.dart';

/// Four-dot PIN entry with a numeric keypad. [onComplete] returns whether the
/// PIN was accepted; on false the dots shake red and reset.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.onComplete, this.disabled = false});
  final bool Function(String pin) onComplete;
  final bool disabled;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  bool _error = false;

  void _tap(String d) {
    if (widget.disabled || _pin.length >= 4) return;
    setState(() {
      _pin += d;
      _error = false;
    });
    if (_pin.length == 4) {
      final ok = widget.onComplete(_pin);
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
          width: 80,
          height: 66,
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: context.pal.ink,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: widget.disabled ? null : () => _tap(d),
            child: Text(d, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 9),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? (_error ? cs.error : cs.primary) : Colors.transparent,
                  border: Border.all(color: _error ? cs.error : cs.primary, width: 2),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9']
        ])
          Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) key(d)]),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 80, height: 66),
            key('0'),
            SizedBox(
              width: 80,
              height: 66,
              child: IconButton(
                icon: const Icon(Icons.backspace_outlined),
                onPressed: widget.disabled
                    ? null
                    : () => setState(() {
                          if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
                        }),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Sign-in: pick a user, then enter the PIN.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  AppUser? _selected;
  Timer? _ticker;
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    context.read<BiometricService>().isAvailable().then((v) {
      if (mounted) setState(() => _bioAvailable = v);
    });
  }

  Future<void> _select(AppUser u) async {
    setState(() => _selected = u);
    // Ask for the fingerprint straight away when this user turned it on.
    if (_bioAvailable && context.read<AuthProvider>().bioEnabled(u)) await _useFingerprint();
  }

  Future<void> _useFingerprint() async {
    final u = _selected;
    if (u == null) return;
    final ok = await context.read<BiometricService>().authenticate('Connexion de ${u.name}');
    if (ok && mounted) context.read<AuthProvider>().loginBiometric(u);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // Refresh the lockout countdown every second while locked.
  void _watchLock() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || context.read<AuthProvider>().lockRemaining == 0) {
        t.cancel();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final store = context.watch<SettingsProvider>().settings.storeName;
    final locked = auth.lockRemaining;
    final pal = context.pal;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(gradient: kHeroGradient, borderRadius: BorderRadius.circular(22)),
                    child: const Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 38),
                  ),
                  const SizedBox(height: 14),
                  Text(store, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(_selected == null ? 'Qui êtes-vous ?' : 'Code PIN de ${_selected!.name}',
                      style: TextStyle(color: pal.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 22),
                  if (_selected == null)
                    for (final u in auth.users)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _select(u),
                            child: Ink(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(20), boxShadow: pal.shadow),
                              child: Row(children: [
                                UserAvatar(name: u.name),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(u.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                                    Text(u.role.label, style: TextStyle(color: pal.muted, fontWeight: FontWeight.w600)),
                                  ]),
                                ),
                                Icon(Icons.chevron_right_rounded, color: pal.muted),
                              ]),
                            ),
                          ),
                        ),
                      )
                  else ...[
                    if (locked > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text('Trop d\'essais. Réessayez dans $locked s',
                            style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
                      ),
                    PinPad(
                      disabled: locked > 0,
                      onComplete: (pin) {
                        final ok = context.read<AuthProvider>().login(_selected!, pin);
                        if (!ok && context.read<AuthProvider>().lockRemaining > 0) _watchLock();
                        return ok;
                      },
                    ),
                    if (_bioAvailable && auth.bioEnabled(_selected!) && locked == 0) ...[
                      const SizedBox(height: 6),
                      FilledButton.tonalIcon(
                        onPressed: _useFingerprint,
                        icon: const Icon(Icons.fingerprint_rounded, size: 26),
                        label: const Text('Utiliser l\'empreinte'),
                        style: FilledButton.styleFrom(minimumSize: const Size(220, 50)),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => setState(() => _selected = null),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Changer d\'utilisateur'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Round avatar with the user's initial.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.size = 48});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: context.pal.soft, shape: BoxShape.circle),
        child: Text(
          name.isEmpty ? '?' : name.characters.first.toUpperCase(),
          style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w900, color: context.pal.accent),
        ),
      );
}
