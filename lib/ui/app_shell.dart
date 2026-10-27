import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../logic/auth_provider.dart';
import '../logic/products_provider.dart';
import 'pin_lock.dart';
import 'screens/cart_screen.dart';
import 'screens/history_screen.dart';
import 'screens/products_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stock_screen.dart';

enum _Tab {
  cashier('Caisse', Icons.point_of_sale_outlined, Icons.point_of_sale, null),
  products('Produits', Icons.inventory_2_outlined, Icons.inventory_2, Perm.products),
  stock('Stock', Icons.warehouse_outlined, Icons.warehouse, Perm.stock),
  history('Historique', Icons.receipt_long_outlined, Icons.receipt_long, Perm.history),
  settings('Réglages', Icons.settings_outlined, Icons.settings, Perm.settings);

  const _Tab(this.label, this.icon, this.selectedIcon, this.perm);
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Required access right; null = open to every user.
  final int? perm;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  _Tab _tab = _Tab.cashier;
  DateTime? _pausedAt;

  /// Signed-in users are signed out after this long in the background.
  static const _backgroundTimeout = Duration(minutes: 2);

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final at = _pausedAt;
      _pausedAt = null;
      if (at != null && DateTime.now().difference(at) > _backgroundTimeout) {
        context.read<AuthProvider>().logout();
      }
    }
  }

  // Only the current tab is built, so the camera is released on other tabs.
  Widget _page(_Tab t) => switch (t) {
        _Tab.cashier => const CartScreen(),
        _Tab.products => const ProductsScreen(),
        _Tab.stock => const StockScreen(),
        _Tab.history => const HistoryScreen(),
        _Tab.settings => const SettingsScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.needsLogin) {
      _tab = _Tab.cashier; // the next user starts on the Caisse
      // Close any screen still open on top (payment, forms) so it is not left reachable.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });
      return const LoginScreen();
    }

    final allowed = _Tab.values.where((t) => t.perm == null || auth.can(t.perm!)).toList();
    if (!allowed.contains(_tab)) _tab = _Tab.cashier;
    final low = context.watch<ProductsProvider>().lowCount;

    return Scaffold(
      body: SafeArea(child: _page(_tab)),
      bottomNavigationBar: allowed.length > 1
          ? NavigationBar(
              selectedIndex: allowed.indexOf(_tab),
              onDestinationSelected: (i) => setState(() => _tab = allowed[i]),
              destinations: [
                for (final t in allowed)
                  NavigationDestination(
                    icon: _icon(t, t.icon, low),
                    selectedIcon: _icon(t, t.selectedIcon, low),
                    label: t.label,
                  ),
              ],
            )
          : null,
    );
  }

  Widget _icon(_Tab t, IconData icon, int low) =>
      t == _Tab.stock ? Badge(isLabelVisible: low > 0, label: Text('$low'), child: Icon(icon)) : Icon(icon);
}
