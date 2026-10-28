import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'data/backup_service.dart';
import 'data/closing_service.dart';
import 'data/database.dart';
import 'data/printer_service.dart';
import 'data/report_service.dart';
import 'logic/quotes_provider.dart';
import 'data/settings_store.dart';
import 'logic/auth_provider.dart';
import 'logic/cart_provider.dart';
import 'logic/products_provider.dart';
import 'logic/sales_provider.dart';
import 'logic/settings_provider.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  final db = await AppDatabase.open();
  final store = SettingsStore();
  final settings = await store.load();
  final auth = AuthProvider(db, store);
  await auth.load(); // so the sign-in screen shows straight away when accounts exist

  runApp(MultiProvider(
    providers: [
      Provider<BackupService>(create: (_) => BackupService(db)),
      Provider<ClosingService>(create: (_) => ClosingService(db)),
      Provider<ReportService>(create: (_) => ReportService(db)),
      ChangeNotifierProvider.value(value: auth),
      Provider<PrinterService>(create: (_) => PrinterService()),
      ChangeNotifierProvider(create: (_) => SettingsProvider(store, settings)),
      ChangeNotifierProvider(create: (_) => CartProvider(db)),
      ChangeNotifierProvider(create: (_) => ProductsProvider(db)),
      ChangeNotifierProvider(create: (_) => SalesProvider(db)),
      ChangeNotifierProvider(create: (_) => QuotesProvider(db)),
    ],
    child: const CaisseApp(),
  ));
}

class CaisseApp extends StatelessWidget {
  const CaisseApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Caisse POS',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const AppShell(),
      );
}
