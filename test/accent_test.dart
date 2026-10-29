import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mob_caisse/data/settings_store.dart';
import 'package:mob_caisse/logic/settings_provider.dart';
import 'package:mob_caisse/ui/theme.dart';

void main() {
  tearDown(() => AppAccent.current = AppAccent.blue);

  test('blue stays the default and the original look', () {
    expect(const AppSettings().accent, 'blue');
    expect(kBlue, const Color(0xFF2563EB));
    expect(buildTheme().colorScheme.primary, const Color(0xFF2563EB));
    expect(buildTheme().extension<AppPalette>()!.soft, AppPalette.light.soft);
  });

  test('choosing a colour recolours the theme, the gradient and the palette', () {
    final sp = SettingsProvider(SettingsStore(), const AppSettings(accent: 'violet'));
    expect(AppAccent.current.key, 'violet');
    expect(kBlue, AppAccent.violet.main);
    expect(kHeroGradient.colors, [AppAccent.violet.deep, AppAccent.violet.main, AppAccent.violet.light]);
    final light = buildTheme();
    expect(light.colorScheme.primary, AppAccent.violet.main);
    expect(light.extension<AppPalette>()!.accent, AppAccent.violet.deep);
    expect(light.extension<AppPalette>()!.soft, isNot(AppPalette.light.soft));
    expect(buildTheme(Brightness.dark).colorScheme.primary, AppAccent.violet.light);
    expect(sp.settings.accent, 'violet');
  });

  test('every colour has distinct shades and an unknown key falls back to blue', () {
    for (final a in AppAccent.all) {
      expect({a.deep, a.main, a.light}.length, 3, reason: a.key);
    }
    expect(AppAccent.all.map((a) => a.key).toSet().length, AppAccent.all.length);
    expect(AppAccent.byKey('nope').key, 'blue');
  });
}
