import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/models.dart';
import '../../data/printer_service.dart';
import '../../data/settings_store.dart';
import '../../logic/auth_provider.dart';
import '../../logic/cart_provider.dart';
import '../../logic/credits_provider.dart';
import '../../logic/products_provider.dart';
import '../../logic/sales_provider.dart';
import '../../logic/settings_provider.dart';
import '../theme.dart';
import '../widgets.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  // Snapshot of the cart: it is cleared as soon as the sale is saved.
  late final List<SaleLine> _lines = context.read<CartProvider>().lines;
  late final double _total = context.read<CartProvider>().total;
  late final double _discount = context.read<CartProvider>().discountAmount;
  final _received = TextEditingController();
  final _customer = TextEditingController();
  final _phone = TextEditingController();
  PayMethod _method = PayMethod.cash;
  Sale? _saved;
  bool _working = false;

  double? get _receivedValue => double.tryParse(_received.text.trim().replaceAll(',', '.'));
  double get _change {
    final r = _receivedValue;
    return r == null ? 0 : (r - _total).clamp(0, double.infinity).toDouble();
  }

  Future<Sale> _ensureSaved() async {
    if (_saved != null) return _saved!;
    final r = _method == PayMethod.cash ? _receivedValue : null;
    final sale = Sale(date: DateTime.now(), total: _total, discount: _discount, method: _method, received: r, lines: _lines,
        seller: context.read<AuthProvider>().currentName);
    final saved = await context.read<SalesProvider>().record(sale);
    if (_method == PayMethod.credit && mounted) {
      await context.read<CreditsProvider>().addDebt(
          customer: _customer.text, phone: _phone.text, amount: _total, saleId: saved.id);
    }
    if (!mounted) return saved;
    context.read<CartProvider>().clear();
    context.read<ProductsProvider>().load(); // stock changed
    _saved = saved;
    return saved;
  }

  /// Credit needs a customer to put the amount on.
  bool _creditReady() {
    if (_saved == null && _method == PayMethod.credit && _customer.text.trim().isEmpty) {
      showMsg(context, 'Indiquez le nom du client pour le crédit');
      return false;
    }
    return true;
  }

  Future<void> _print() async {
    if (_working || !_creditReady()) return;
    setState(() => _working = true);
    final printer = context.read<PrinterService>();
    final settings = context.read<SettingsProvider>().settings;
    final sale = await _ensureSaved();
    final err = await printer.printSale(sale, settings);
    if (!mounted) return;
    setState(() => _working = false);
    showMsg(context, err ?? 'Reçu imprimé');
  }

  Future<void> _finish() async {
    if (_working || !_creditReady()) return;
    await _ensureSaved();
    if (!mounted) return;
    Navigator.pop(context);
    showMsg(context, 'Vente enregistrée');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().settings;
    final locked = _saved != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Paiement')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TotalBanner(
              label: 'TOTAL À PAYER',
              amount: s.money(_total),
              sub: _discount > 0 ? 'Remise −${s.money(_discount)}' : null,
            ),
            const SizedBox(height: 14),
            SegmentedButton<PayMethod>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: PayMethod.cash, icon: Icon(Icons.payments_outlined), label: Text('Espèces')),
                ButtonSegment(value: PayMethod.qr, icon: Icon(Icons.qr_code_2), label: Text('QR code')),
                ButtonSegment(value: PayMethod.credit, icon: Icon(Icons.account_balance_wallet_outlined), label: Text('Crédit')),
              ],
              selected: {_method},
              onSelectionChanged: locked ? null : (v) => setState(() => _method = v.first),
            ),
            const SizedBox(height: 14),
            if (_method == PayMethod.cash)
              _cashCard(s)
            else if (_method == PayMethod.credit)
              _creditCard(s)
            else
              _qrCard(s),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _working ? null : _print,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimer le reçu'),
            ),
            const SizedBox(height: 10),
            PrimaryButton(
              onPressed: _working ? null : _finish,
              icon: Icons.check_circle_rounded,
              label: 'Terminer la vente',
            ),
          ],
        ),
      ),
    );
  }

  Widget _cashCard(AppSettings s) {
    final quick = [5, 10, 20, 50];
    final enough = (_receivedValue ?? 0) >= _total && _receivedValue != null;
    Widget chip(String label, VoidCallback? onTap) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), padding: EdgeInsets.zero),
              onPressed: onTap,
              child: Text(label),
            ),
          ),
        );
    return SoftCard(
      child: Column(
        children: [
          TextField(
            controller: _received,
            enabled: _saved == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            decoration: InputDecoration(labelText: 'Montant reçu (facultatif)', suffixText: s.currency),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              chip('Exact',
                  _saved != null ? null : () => setState(() => _received.text = _total.toStringAsFixed(s.decimals))),
              for (final v in quick) chip('$v', _saved != null ? null : () => setState(() => _received.text = '$v')),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: enough ? context.pal.goodBg : context.pal.soft2,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Text('Monnaie à rendre', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(s.money(_change),
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: enough ? context.pal.goodFg : context.pal.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _creditCard(AppSettings s) {
    final accounts = context.watch<CreditsProvider>().accounts;
    final typed = _customer.text.trim().toLowerCase();
    final suggestions = accounts.where((a) => typed.isEmpty || (a.name.toLowerCase().contains(typed) && a.name.toLowerCase() != typed)).take(8).toList();
    final current = accounts.where((a) => a.name.toLowerCase() == typed);
    final owed = current.isEmpty ? 0.0 : current.first.balance;
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Mettre sur le compte du client', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 12),
        TextField(
          controller: _customer,
          enabled: _saved == null,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Nom du client', prefixIcon: Icon(Icons.person_rounded)),
        ),
        if (suggestions.isNotEmpty && _saved == null) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final a in suggestions)
              ActionChip(
                label: Text(a.name),
                onPressed: () => setState(() {
                  _customer.text = a.name;
                  _phone.text = a.phone;
                }),
              ),
          ]),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _phone,
          enabled: _saved == null,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Téléphone (pour la relance WhatsApp)', prefixIcon: Icon(Icons.phone_rounded)),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: context.pal.soft2, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Row(children: [
              const Text('Déjà dû', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(s.money(owed), style: const TextStyle(fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Text('Nouveau solde', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(s.money(owed + _total), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: context.pal.badFg)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _qrCard(AppSettings s) => SoftCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            QrImageView(data: s.qrData(_total), size: 240, backgroundColor: Colors.white),
            const SizedBox(height: 8),
            Text('Faites scanner ce code par le client', style: TextStyle(color: context.pal.muted, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
