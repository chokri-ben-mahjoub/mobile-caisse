import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mob_caisse/data/models.dart';
import 'package:mob_caisse/data/printer_service.dart';
import 'package:mob_caisse/data/settings_store.dart';
import 'package:mob_caisse/logic/settings_provider.dart';
import 'package:mob_caisse/ui/screens/sale_success_screen.dart';
import 'package:mob_caisse/ui/theme.dart';

Sale _sale() => Sale(
      id: 12,
      date: DateTime(2026, 10, 28, 10, 30),
      total: 7.5,
      method: PayMethod.cash,
      received: 10,
      lines: const [SaleLine(barcode: '1', name: 'Café', price: 2.5, qty: 3)],
    );

void main() {
  test('receipt text lists lines, total and payment', () {
    final t = saleReceiptText(_sale(), const AppSettings(storeName: 'Chez Ali'));
    expect(t, contains('Chez Ali'));
    expect(t, contains('Café × 3'));
    expect(t, contains('TOTAL : 7,500 DT'));
    expect(t, contains('Paiement : Espèces'));
  });

  testWidgets('success screen shows amount and change, then settles', (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider(SettingsStore(), const AppSettings())),
        Provider<PrinterService>(create: (_) => PrinterService()),
      ],
      child: MaterialApp(theme: buildTheme(), home: SaleSuccessScreen(sale: _sale())),
    ));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Vente encaissée !'), findsOneWidget);
    expect(find.text('7,500 DT'), findsOneWidget);
    expect(find.text('2,500 DT'), findsOneWidget); // change to give back
    expect(find.text('Nouvelle vente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
