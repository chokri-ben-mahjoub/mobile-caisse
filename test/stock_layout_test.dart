import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mob_caisse/data/database.dart';
import 'package:mob_caisse/data/models.dart';
import 'package:mob_caisse/data/settings_store.dart';
import 'package:mob_caisse/logic/products_provider.dart';
import 'package:mob_caisse/logic/settings_provider.dart';
import 'package:mob_caisse/ui/i18n/tr.dart';
import 'package:mob_caisse/ui/screens/stock_screen.dart';
import 'package:mob_caisse/ui/theme.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting();
    // Real fonts, so text widths match a phone (the default test font is wider).
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
    testWidgets('Stock header stays compact on a 360 px phone ($lang)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Real database work must run outside the fake-async test clock.
      final db = (await tester.runAsync(() async {
        final d = await AppDatabase.openAt(inMemoryDatabasePath);
        await d.upsertProduct(const Product(barcode: '1', name: 'Lait', price: 1.5, cost: 1, stock: 4, minStock: 2));
        return d;
      }))!;
      final settings = AppSettings(language: lang);
      Tr.lang = lang;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider(SettingsStore(), settings)),
          ChangeNotifierProvider(create: (_) => ProductsProvider(db)),
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
          home: const Scaffold(body: StockScreen()),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      // The "Achats" shortcut must be a small button, not stretch across the header.
      final button = find.byIcon(Icons.local_shipping_rounded);
      expect(button, findsOneWidget);
      final buttonBox = tester.getRect(find.ancestor(of: button, matching: find.byType(FilledButton)).first);
      expect(buttonBox.width, lessThan(200), reason: 'Achats button is ${buttonBox.width} px wide');
      // The title keeps its line.
      final title = find.text(lang == 'ar' ? 'المخزون' : 'Stock').first;
      expect(tester.getRect(title).height, lessThan(40));
      Tr.lang = 'fr';
    });
  }
}
