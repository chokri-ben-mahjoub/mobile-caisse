import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mob_caisse/ui/theme.dart';
import 'package:mob_caisse/ui/widgets/floating_nav.dart';

void main() {
  for (final mode in [Brightness.light, Brightness.dark]) {
    testWidgets('floating nav fits 6 tabs on a 360 px phone and switches ($mode)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var selected = 0;
      await tester.pumpWidget(StatefulBuilder(
        builder: (context, set) => MaterialApp(
          theme: buildTheme(mode),
          home: Scaffold(
            bottomNavigationBar: FloatingNav(
              selected: selected,
              onSelected: (i) => set(() => selected = i),
              items: const [
                FloatingNavItem(label: 'Accueil', icon: Icons.home_outlined, selectedIcon: Icons.home),
                FloatingNavItem(label: 'Caisse', icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale),
                FloatingNavItem(label: 'Produits', icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2),
                FloatingNavItem(label: 'Stock', icon: Icons.warehouse_outlined, selectedIcon: Icons.warehouse, badge: 3),
                FloatingNavItem(label: 'Historique', icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long),
                FloatingNavItem(label: 'Réglages', icon: Icons.settings_outlined, selectedIcon: Icons.settings),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Caisse'), findsNothing); // only the selected tab shows its label
      expect(find.text('3'), findsOneWidget); // stock badge

      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();
      expect(selected, 4);
      expect(find.text('Historique'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
