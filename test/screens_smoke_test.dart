import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mob_caisse/data/credit.dart';
import 'package:mob_caisse/data/database.dart';
import 'package:mob_caisse/data/models.dart';
import 'package:mob_caisse/data/purchase.dart';
import 'package:mob_caisse/data/settings_store.dart';
import 'package:mob_caisse/data/report_service.dart';
import 'package:mob_caisse/logic/auth_provider.dart';
import 'package:mob_caisse/logic/credits_provider.dart';
import 'package:mob_caisse/logic/quotes_provider.dart';
import 'package:mob_caisse/logic/sales_provider.dart';
import 'package:mob_caisse/ui/screens/dashboard_screen.dart';
import 'package:mob_caisse/logic/products_provider.dart';
import 'package:mob_caisse/logic/purchases_provider.dart';
import 'package:mob_caisse/logic/settings_provider.dart';
import 'package:mob_caisse/ui/i18n/tr.dart';
import 'package:mob_caisse/ui/screens/credits_screen.dart';
import 'package:mob_caisse/ui/screens/new_purchase_screen.dart';
import 'package:mob_caisse/ui/screens/purchases_screen.dart';
import 'package:mob_caisse/ui/theme.dart';

/// Renders the new screens on a 360 px phone, in French and Arabic, with real fonts and data:
/// any layout error (overflow, infinite width…) fails the test.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting();
    Future<void> load(String family, List<String> files) async {
      final loader = FontLoader(family);
      for (final f in files) {
        loader.addFont(Future.value(ByteData.view(File(f).readAsBytesSync().buffer)));
      }
      await loader.load();
    }

    await load('Roboto', ['assets/fonts/Roboto-Regular.ttf', 'assets/fonts/Roboto-Medium.ttf', 'assets/fonts/Roboto-Bold.ttf']);
    await load('Tajawal', ['assets/fonts/Tajawal-Regular.ttf', 'assets/fonts/Tajawal-Medium.ttf', 'assets/fonts/Tajawal-Bold.ttf']);
  });

  for (final lang in ['fr', 'ar']) {
    group('screens on 360 px ($lang)', () {
      late AppDatabase db;

      Future<void> pump(WidgetTester tester, Widget screen) async {
        await tester.binding.setSurfaceSize(const Size(360, 780));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        Tr.lang = lang;
        addTearDown(() => Tr.lang = 'fr');
        db = (await tester.runAsync(() async {
          final d = await AppDatabase.openAt(inMemoryDatabasePath);
          await d.upsertProduct(const Product(barcode: '1', name: 'Lait demi-écrémé 1L', price: 1.5, cost: 1, stock: 4, minStock: 2));
          await d.insertPurchase(Purchase(
            date: DateTime(2026, 10, 2),
            supplier: 'Société Délice Danone',
            phone: '20123456',
            invoice: 'BL-2026-0042',
            paid: 5,
            lines: const [PurchaseLine(barcode: '1', name: 'Lait demi-écrémé 1L', qty: 24, cost: 1.2)],
          ));
          await d.insertCredit(CreditEntry(customer: 'Mohamed Ben Salah', phone: '98123456', amount: 85.5, date: DateTime(2026, 9, 1)));
          return d;
        }))!;
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsProvider(SettingsStore(), AppSettings(language: lang))),
            ChangeNotifierProvider(create: (_) => ProductsProvider(db)),
            ChangeNotifierProvider(create: (_) => PurchasesProvider(db)),
            ChangeNotifierProvider(create: (_) => CreditsProvider(db)),
            ChangeNotifierProvider(create: (_) => SalesProvider(db)),
            ChangeNotifierProvider(create: (_) => QuotesProvider(db)),
            ChangeNotifierProvider(create: (_) => AuthProvider(db, SettingsStore())),
            Provider<ReportService>(create: (_) => ReportService(db)),
          ],
          child: MaterialApp(
            theme: buildTheme(Brightness.light, lang == 'ar'),
            locale: Locale(lang),
            supportedLocales: const [Locale('fr'), Locale('ar')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: screen,
          ),
        ));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pump(const Duration(milliseconds: 600));
      }

      testWidgets('Achats fournisseurs: list, suppliers tab, detail sheets', (tester) async {
        await pump(tester, const PurchasesScreen());
        expect(tester.takeException(), isNull);
        await tester.tap(find.byIcon(Icons.storefront_rounded).first);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byIcon(Icons.inventory_rounded).first);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byType(InkWell).first);
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
      });

      testWidgets('Nouvel achat: empty and with a product line', (tester) async {
        await pump(tester, const NewPurchaseScreen());
        expect(tester.takeException(), isNull);
        await tester.tap(find.byIcon(Icons.add_rounded).first);
        await tester.pump(const Duration(milliseconds: 600));
        // The product list loads lazily from the database.
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.byType(ListTile).first);
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
      });

      testWidgets('Accueil: dashboard with figures, shortcuts and alerts', (tester) async {
        await pump(tester, DashboardScreen(onGo: (_) {}));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
        await tester.pump(const Duration(milliseconds: 900));
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      });

      testWidgets('Crédit clients: list and account sheet', (tester) async {
        await pump(tester, const CreditsScreen());
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(InkWell).first);
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
      });
    });
  }
}
