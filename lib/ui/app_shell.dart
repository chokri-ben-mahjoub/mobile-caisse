import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/auth_provider.dart';
import '../logic/products_provider.dart';
import 'pin_lock.dart';
import 'screens/cart_screen.dart';
import 'screens/history_screen.dart';
import 'screens/products_screen.dart';
import 'screens/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;

  // Only the current tab is built, so the camera is released on other tabs.
  static const _pages = <Widget>[CartScreen(), ProductsScreen(), HistoryScreen(), SettingsScreen()];
  static const _titles = ['Caisse', 'Produits', 'Historique', 'Réglages'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-lock when the app goes to the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) context.read<AuthProvider>().lock();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final protectedTab = _index != 0;
    final low = context.watch<ProductsProvider>().lowCount;

    return Scaffold(
      body: SafeArea(
        child: protectedTab && auth.locked ? PinLockView(title: _titles[_index]) : _pages[_index],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          if (i == 0) auth.lock();
          setState(() => _index = i);
        },
        destinations: [
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'Caisse'),
          NavigationDestination(
            icon: Badge(isLabelVisible: low > 0, label: Text('$low'), child: const Icon(Icons.inventory_2_outlined)),
            selectedIcon: Badge(isLabelVisible: low > 0, label: Text('$low'), child: const Icon(Icons.inventory_2)),
            label: 'Produits',
          ),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Historique'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Réglages'),
        ],
      ),
    );
  }
}
