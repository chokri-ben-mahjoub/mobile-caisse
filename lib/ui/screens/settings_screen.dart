import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/backup_service.dart';
import '../../data/printer_service.dart';
import '../../data/settings_store.dart';
import '../../logic/auth_provider.dart';
import '../../logic/cart_provider.dart';
import '../../logic/products_provider.dart';
import '../../logic/sales_provider.dart';
import '../../logic/settings_provider.dart';
import '../theme.dart';
import '../widgets.dart';
import 'demo_codes_screen.dart';
import 'users_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppSettings _initial = context.read<SettingsProvider>().settings;
  late final _store = TextEditingController(text: _initial.storeName);
  late final _currency = TextEditingController(text: _initial.currency);
  late final _qr = TextEditingController(text: _initial.qrTemplate);
  late int _decimals = _initial.decimals;

  AppSettings _current() => context.read<SettingsProvider>().settings.copyWith(
        storeName: _store.text.trim().isEmpty ? 'Ma boutique' : _store.text.trim(),
        currency: _currency.text.trim().isEmpty ? 'DT' : _currency.text.trim(),
        decimals: _decimals,
        qrTemplate: _qr.text.trim(),
      );

  Future<void> _save() async {
    await context.read<SettingsProvider>().update(_current());
    if (mounted) showMsg(context, 'Réglages enregistrés');
  }

  Future<void> _choosePrinter() async {
    final printer = context.read<PrinterService>();
    final prov = context.read<SettingsProvider>();
    final devices = await printer.pairedDevices();
    if (!mounted) return;
    if (devices.isEmpty) {
      showMsg(context, 'Aucune imprimante associée. Associez-la d\'abord dans les réglages Bluetooth Android.');
      return;
    }
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choisir l\'imprimante'),
        children: [
          for (var i = 0; i < devices.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, i),
              child: ListTile(
                leading: const Icon(Icons.print),
                title: Text(devices[i].name),
                subtitle: Text(devices[i].macAdress),
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await prov.update(prov.settings.copyWith(printerMac: devices[picked].macAdress, printerName: devices[picked].name));
    }
  }

  Future<void> _reloadAfterDemo() async {
    final cart = context.read<CartProvider>();
    final sales = context.read<SalesProvider>();
    cart.clear();
    await cart.refreshHeld();
    await sales.load();
  }

  Future<void> _loadDemo() => _run(() async {
        await context.read<ProductsProvider>().loadDemo();
        await _reloadAfterDemo();
        if (mounted) showMsg(context, 'Données de démo chargées');
      });

  Future<void> _clearDemo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer les données de démo ?'),
        content: const Text('Les produits et ventes de démonstration seront supprimés, '
            'ainsi que les ventes faites avec ces produits. Vos vraies données ne sont pas touchées.'),
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
    await _run(() async {
      await context.read<ProductsProvider>().clearDemo();
      await _reloadAfterDemo();
      if (mounted) showMsg(context, 'Données de démo supprimées');
    });
  }

  Widget _demoSection() {
    final hasDemo = context.watch<ProductsProvider>().hasDemo;
    if (!hasDemo) {
      return OutlinedButton.icon(
        onPressed: _loadDemo,
        icon: const Icon(Icons.science_outlined),
        label: const Text('Charger des données de démo'),
      );
    }
    return Column(children: [
      OutlinedButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DemoCodesScreen())),
        icon: const Icon(Icons.qr_code_2),
        label: const Text('Codes-barres de démo à scanner'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
        onPressed: _clearDemo,
        icon: const Icon(Icons.delete_sweep_outlined),
        label: const Text('Supprimer les données de démo'),
      ),
    ]);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showMsg(context, 'Erreur : $e');
    }
  }

  Future<void> _restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurer une sauvegarde ?'),
        content: const Text('Les produits et ventes actuels seront remplacés par ceux de la sauvegarde.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final backup = context.read<BackupService>();
    final products = context.read<ProductsProvider>();
    final sales = context.read<SalesProvider>();
    final cart = context.read<CartProvider>();
    final auth = context.read<AuthProvider>();
    try {
      if (await backup.restoreFromPicker()) {
        cart.clear();
        await products.load();
        await sales.load();
        await auth.load(); // accounts come from the backup too
        if (mounted) showMsg(context, 'Sauvegarde restaurée');
      }
    } on FormatException {
      if (mounted) showMsg(context, 'Ce fichier n\'est pas une sauvegarde Caisse.');
    } catch (e) {
      if (mounted) showMsg(context, 'Erreur : $e');
    }
  }

  Widget _accountsSection() {
    final auth = context.watch<AuthProvider>();
    final pal = context.pal;
    if (!auth.enabled) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.group_add_outlined),
          label: const Text('Activer les comptes utilisateurs'),
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const UserFormScreen(firstOwner: true))),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text('Créez des caissiers et des gérants avec un code PIN et des accès limités.',
              style: TextStyle(fontSize: 12, color: pal.muted)),
        ),
      ]);
    }
    return Column(children: [
      if (auth.isOwner)
        OutlinedButton.icon(
          icon: const Icon(Icons.manage_accounts_outlined),
          label: Text('Gérer les utilisateurs (${auth.users.length})'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UsersScreen())),
        ),
      if (auth.isOwner) const SizedBox(height: 10),
      OutlinedButton.icon(
        icon: const Icon(Icons.lock_outline),
        label: Text('Verrouiller · connecté : ${auth.currentName ?? ''}'),
        onPressed: auth.logout,
      ),
    ]);
  }

  Future<void> _test() async {
    await context.read<SettingsProvider>().update(_current());
    if (!mounted) return;
    final err = await context.read<PrinterService>().printTest(context.read<SettingsProvider>().settings);
    if (mounted) showMsg(context, err ?? 'Ticket de test envoyé');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().settings;
    final primary = Theme.of(context).colorScheme.primary;
    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(t, style: TextStyle(color: primary, fontWeight: FontWeight.w800, letterSpacing: 1)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          header('MAGASIN'),
          TextField(controller: _store, decoration: const InputDecoration(labelText: 'Nom du magasin (sur le ticket)')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _currency, decoration: const InputDecoration(labelText: 'Devise'))),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _decimals,
                decoration: const InputDecoration(labelText: 'Décimales'),
                items: const [0, 1, 2, 3].map((d) => DropdownMenuItem(value: d, child: Text('$d'))).toList(),
                onChanged: (v) => setState(() => _decimals = v ?? 3),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _qr,
            decoration: const InputDecoration(
              labelText: 'Lien / texte du QR de paiement',
              helperText: '{amount} est remplacé par le total',
            ),
          ),
          header('APPARENCE'),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'system', icon: Icon(Icons.phone_android_rounded), label: Text('Système')),
              ButtonSegment(value: 'light', icon: Icon(Icons.light_mode_rounded), label: Text('Clair')),
              ButtonSegment(value: 'dark', icon: Icon(Icons.dark_mode_rounded), label: Text('Sombre')),
              ButtonSegment(value: 'auto', icon: Icon(Icons.brightness_auto_rounded), label: Text('Auto')),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => context.read<SettingsProvider>().update(s.copyWith(themeMode: v.first)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              s.themeMode == 'auto'
                  ? 'Mode sombre automatique de ${AppSettings.autoDarkStart} h à ${AppSettings.autoDarkEnd} h, clair le reste du temps.'
                  : 'Auto : sombre le soir (${AppSettings.autoDarkStart} h – ${AppSettings.autoDarkEnd} h), plus reposant pour les yeux au comptoir.',
              style: TextStyle(color: context.pal.muted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          header('IMPRIMANTE THERMIQUE 58 MM'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.print_outlined, size: 32),
              title: Text(s.printerName.isEmpty ? 'Aucune imprimante' : s.printerName,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(s.printerMac.isEmpty ? 'Appuyez sur « Choisir »' : s.printerMac),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _choosePrinter, child: const Text('Choisir'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: s.printerMac.isEmpty ? null : _test, child: const Text('Ticket de test'))),
          ]),
          header('UTILISATEURS ET ACCÈS'),
          _accountsSection(),
          header('DONNÉES ET SAUVEGARDE'),
          OutlinedButton.icon(
            onPressed: () => _run(() => context.read<BackupService>().shareSalesCsv()),
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Exporter les ventes (CSV / Excel)'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _run(() => context.read<BackupService>().shareBackup()),
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Sauvegarder les données'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _restore,
            icon: const Icon(Icons.restore),
            label: const Text('Restaurer une sauvegarde'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              'Envoyez la sauvegarde sur WhatsApp, e-mail ou Drive pour la garder hors du téléphone.',
              style: TextStyle(fontSize: 12, color: context.pal.muted),
            ),
          ),
          header('MODE DÉMO'),
          _demoSection(),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              'Pour présenter l\'app à un client : produits, stock et ventes d\'exemple, supprimables en un geste.',
              style: TextStyle(fontSize: 12, color: context.pal.muted),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Enregistrer')),
        ],
      ),
    );
  }
}
