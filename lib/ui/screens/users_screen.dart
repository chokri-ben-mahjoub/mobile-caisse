import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../logic/auth_provider.dart';
import '../pin_lock.dart';
import '../theme.dart';
import '../widgets.dart';

String _accessSummary(AppUser u) {
  if (u.isOwner) return 'Tous les accès et gestion des utilisateurs';
  final names = [for (final e in Perm.labels.entries) if (u.can(e.key)) e.value];
  return names.isEmpty ? 'Caisse uniquement' : 'Caisse, ${names.join(', ')}';
}

/// Owner-only list of user accounts.
class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  Future<void> _disable(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Désactiver les comptes ?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Tous les comptes seront supprimés et l\'app sera ouverte à tous, sans code PIN. '
              'Entrez votre code PIN pour confirmer.'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            obscureText: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Votre code PIN', counterText: ''),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44), backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, auth.verifyCurrentPin(ctrl.text)),
            child: const Text('Désactiver'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await auth.disableAccounts();
      if (context.mounted) Navigator.pop(context);
    } else if (ok == false && ctrl.text.isNotEmpty && context.mounted) {
      showMsg(context, 'Code PIN incorrect');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final pal = context.pal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Utilisateurs'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => _disable(context),
            itemBuilder: (_) => const [PopupMenuItem(value: 'off', child: Text('Désactiver les comptes'))],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserFormScreen())),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nouvel utilisateur'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: auth.users.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final u = auth.users[i];
          final me = u.id == auth.current?.id;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserFormScreen(user: u))),
              child: Ink(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: pal.card, borderRadius: BorderRadius.circular(20), boxShadow: pal.shadow),
                child: Row(children: [
                  UserAvatar(name: u.name),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(
                          child: Text(me ? '${u.name} (vous)' : u.name,
                              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: pal.soft, borderRadius: BorderRadius.circular(8)),
                          child: Text(u.role.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: pal.accent)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text(_accessSummary(u), style: TextStyle(fontSize: 13, color: pal.muted)),
                    ]),
                  ),
                  Icon(Icons.edit_outlined, color: pal.muted, size: 20),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Create or edit a user. With [firstOwner] it creates the owner account that
/// turns user accounts on.
class UserFormScreen extends StatefulWidget {
  const UserFormScreen({super.key, this.user, this.firstOwner = false});
  final AppUser? user;
  final bool firstOwner;

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user?.name ?? (widget.firstOwner ? 'Propriétaire' : ''));
  final _pin = TextEditingController();
  late Role _role = widget.firstOwner ? Role.owner : (widget.user?.role ?? Role.cashier);
  late int _perms = widget.user?.perms ?? (widget.firstOwner ? Perm.all : Role.cashier.defaultPerms);

  bool get _editing => widget.user != null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    final name = _name.text.trim();
    final pin = _pin.text.isEmpty ? null : _pin.text;

    if (widget.firstOwner) {
      await auth.createFirstOwner(name, pin!);
      nav.pop();
      return;
    }
    if (_editing) {
      final u = widget.user!;
      if (u.isOwner && _role != Role.owner && auth.ownerCount() <= 1) {
        showMsg(context, 'Il faut garder au moins un propriétaire.');
        return;
      }
      await auth.updateUser(u, name: name, role: _role, perms: _perms, pin: pin);
    } else {
      await auth.addUser(name, pin!, _role, _perms);
    }
    nav.pop();
  }

  Future<void> _delete() async {
    final auth = context.read<AuthProvider>();
    final u = widget.user!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer ${u.name} ?'),
        content: const Text('Ses ventes restent dans l\'historique.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44), backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    await auth.deleteUser(u);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isOwnerRole = _role == Role.owner;
    final self = widget.user?.id != null && widget.user!.id == auth.current?.id;
    final lastOwner = widget.user?.isOwner == true && auth.ownerCount() <= 1;
    final canDelete = _editing && !self && !lastOwner;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.firstOwner
            ? 'Compte propriétaire'
            : _editing
                ? 'Modifier l\'utilisateur'
                : 'Nouvel utilisateur'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (widget.firstOwner)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  'Ce compte protège l\'app : il aura tous les accès et pourra créer les autres utilisateurs. '
                  'Chacun se connectera ensuite avec son code PIN.',
                  style: TextStyle(color: context.pal.muted, height: 1.35),
                ),
              ),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nom'),
              validator: (v) {
                final n = (v ?? '').trim();
                if (n.isEmpty) return 'Nom requis';
                if (auth.nameTaken(n, exceptId: widget.user?.id)) return 'Ce nom existe déjà';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _pin,
              obscureText: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: _editing ? 'Nouveau code PIN (facultatif)' : 'Code PIN (4 chiffres)',
                counterText: '',
              ),
              validator: (v) {
                final t = v ?? '';
                if (_editing && t.isEmpty) return null;
                return t.length == 4 ? null : 'Le code doit avoir 4 chiffres';
              },
            ),
            if (!widget.firstOwner) ...[
              const SizedBox(height: 18),
              const Text('Rôle', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final r in Role.values)
                  ChoiceChip(
                    label: Text(r.label),
                    selected: _role == r,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      _role = r;
                      _perms = r.defaultPerms;
                    }),
                  ),
              ]),
              const SizedBox(height: 18),
              const Text('Accès', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              Text('La caisse est accessible à tous les utilisateurs.', style: TextStyle(color: context.pal.muted)),
              const SizedBox(height: 4),
              for (final e in Perm.labels.entries)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600)),
                  value: isOwnerRole || (_perms & e.key) != 0,
                  onChanged: isOwnerRole
                      ? null
                      : (v) => setState(() => _perms = v ? (_perms | e.key) : (_perms & ~e.key)),
                ),
              if (isOwnerRole)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Le propriétaire a tous les accès et gère les utilisateurs.',
                      style: TextStyle(color: context.pal.muted)),
                ),
            ],
            const SizedBox(height: 24),
            PrimaryButton(
              onPressed: _save,
              icon: Icons.check_circle_rounded,
              label: widget.firstOwner ? 'Activer les comptes' : 'Enregistrer',
            ),
            if (canDelete) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Supprimer cet utilisateur'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
