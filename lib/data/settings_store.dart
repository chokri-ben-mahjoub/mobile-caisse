import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final String storeName;
  final String currency;
  final int decimals;
  final String qrTemplate;
  final String printerMac;
  final String printerName;

  /// Daily sales target (0 = disabled).
  final double dailyGoal;

  /// `system`, `light`, `dark` or `auto` (dark in the evening, see [isDarkAt]).
  final String themeMode;

  /// Interface language: `fr` or `ar` (Tunisian Arabic, right to left).
  final String language;

  const AppSettings({
    this.storeName = 'Ma boutique',
    this.currency = 'DT',
    this.decimals = 3,
    this.qrTemplate = 'https://pay.exemple.tn/?m={amount}',
    this.printerMac = '',
    this.printerName = '',
    this.dailyGoal = 500,
    this.themeMode = 'system',
    this.language = 'fr',
  });

  AppSettings copyWith({
    String? storeName,
    String? currency,
    int? decimals,
    String? qrTemplate,
    String? printerMac,
    String? printerName,
    double? dailyGoal,
    String? themeMode,
    String? language,
  }) =>
      AppSettings(
        storeName: storeName ?? this.storeName,
        currency: currency ?? this.currency,
        decimals: decimals ?? this.decimals,
        qrTemplate: qrTemplate ?? this.qrTemplate,
        printerMac: printerMac ?? this.printerMac,
        printerName: printerName ?? this.printerName,
        dailyGoal: dailyGoal ?? this.dailyGoal,
        themeMode: themeMode ?? this.themeMode,
        language: language ?? this.language,
      );

  /// Evening dark mode runs from this hour (inclusive) to [autoDarkEnd] (exclusive) the next morning.
  static const autoDarkStart = 19;
  static const autoDarkEnd = 7;

  static bool isDarkAt(DateTime t) => t.hour >= autoDarkStart || t.hour < autoDarkEnd;

  ThemeMode resolveThemeMode(DateTime now) => switch (themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'auto' => isDarkAt(now) ? ThemeMode.dark : ThemeMode.light,
        _ => ThemeMode.system,
      };

  String money(double v) => '${v.toStringAsFixed(decimals).replaceAll('.', ',')} $currency';

  String qrData(double amount) =>
      qrTemplate.replaceAll('{amount}', amount.toStringAsFixed(decimals));
}

class SettingsStore {
  Future<AppSettings> load() async {
    final sp = await SharedPreferences.getInstance();
    const d = AppSettings();
    return AppSettings(
      storeName: sp.getString('storeName') ?? d.storeName,
      currency: sp.getString('currency') ?? d.currency,
      decimals: sp.getInt('decimals') ?? d.decimals,
      qrTemplate: sp.getString('qrTemplate') ?? d.qrTemplate,
      printerMac: sp.getString('printerMac') ?? '',
      printerName: sp.getString('printerName') ?? '',
      dailyGoal: sp.getDouble('dailyGoal') ?? d.dailyGoal,
      themeMode: sp.getString('themeMode') ?? d.themeMode,
      language: sp.getString('language') ?? d.language,
    );
  }

  /// Ids of the users who turned on fingerprint sign-in.
  Future<Set<int>> loadBioUsers() async =>
      ((await SharedPreferences.getInstance()).getStringList('bioUsers') ?? const <String>[]).map(int.parse).toSet();

  Future<void> saveBioUsers(Set<int> ids) async =>
      (await SharedPreferences.getInstance()).setStringList('bioUsers', ids.map((e) => '$e').toList());

  Future<String?> loadPinHash() async => (await SharedPreferences.getInstance()).getString('pinHash');

  Future<void> savePinHash(String? hash) async {
    final sp = await SharedPreferences.getInstance();
    if (hash == null) {
      await sp.remove('pinHash');
    } else {
      await sp.setString('pinHash', hash);
    }
  }

  Future<void> save(AppSettings s) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('storeName', s.storeName);
    await sp.setString('currency', s.currency);
    await sp.setInt('decimals', s.decimals);
    await sp.setString('qrTemplate', s.qrTemplate);
    await sp.setString('printerMac', s.printerMac);
    await sp.setString('printerName', s.printerName);
    await sp.setDouble('dailyGoal', s.dailyGoal);
    await sp.setString('themeMode', s.themeMode);
    await sp.setString('language', s.language);
  }
}
