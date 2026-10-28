import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'data/backup_service.dart';
import 'data/biometric_service.dart';
import 'data/closing_service.dart';
import 'data/database.dart';
import 'data/printer_service.dart';
import 'data/report_service.dart';
import 'logic/credits_provider.dart';
import 'logic/purchases_provider.dart';
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
      Provider<BiometricService>(create: (_) => BiometricService()),
      ChangeNotifierProvider(create: (_) => SettingsProvider(store, settings)),
      ChangeNotifierProvider(create: (_) => CartProvider(db)),
      ChangeNotifierProvider(create: (_) => ProductsProvider(db)),
      ChangeNotifierProvider(create: (_) => SalesProvider(db)),
      ChangeNotifierProvider(create: (_) => QuotesProvider(db)),
      ChangeNotifierProvider(create: (_) => CreditsProvider(db)),
      ChangeNotifierProvider(create: (_) => PurchasesProvider(db)),
    ],
    child: const CaisseApp(),
  ));
}

class CaisseApp extends StatefulWidget {
  const CaisseApp({super.key});

  @override
  State<CaisseApp> createState() => _CaisseAppState();
}

class _CaisseAppState extends State<CaisseApp> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Re-evaluate the evening dark mode while the app stays open.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.select<SettingsProvider, String>((p) => p.settings.themeMode);
    return MaterialApp(
      title: 'Caisse POS',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: AppSettings(themeMode: mode).resolveThemeMode(DateTime.now()),
      home: const AppShell(),
    );
  }
}
