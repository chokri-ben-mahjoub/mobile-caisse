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
import '../pin_lock.dart';
import '../widgets.dart';

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
    try {
      if (await backup.restoreFromPicker()) {
        cart.clear();
        await products.load();
        await sales.load();
        if (mounted) showMsg(context, 'Sauvegarde restaurée');
      }
    } on FormatException {
      if (mounted) showMsg(context, 'Ce fichier n\'est pas une sauvegarde Caisse.');
    } catch (e) {
      if (mounted) showMsg(context, 'Erreur : $e');
    }
  }

  Widget _pinSection() {
    final auth = context.watch<AuthProvider>();
    if (!auth.hasPin) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.lock_outline),
        label: const Text('Activer le code PIN'),
        onPressed: () async {
          final pin = await askNewPin(context);
          if (pin != null && mounted) {
            await context.read<AuthProvider>().setPin(pin);
            if (mounted) showMsg(context, 'Code PIN activé');
          }
        },
      );
    }
    return Row(children: [
      Expanded(
        child: OutlinedButton(
          onPressed: () async {
            final pin = await askNewPin(context);
            if (pin != null && mounted) await context.read<AuthProvider>().setPin(pin);
          },
          child: const Text('Changer le PIN'),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: OutlinedButton(
          onPressed: () async {
            await context.read<AuthProvider>().removePin();
            if (mounted) showMsg(context, 'Code PIN désactivé');
          },
          child: const Text('Désactiver'),
        ),
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
          header('SÉCURITÉ'),
          _pinSection(),
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
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              'Envoyez la sauvegarde sur WhatsApp, e-mail ou Drive pour la garder hors du téléphone.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Enregistrer')),
        ],
      ),
    );
  }
}
