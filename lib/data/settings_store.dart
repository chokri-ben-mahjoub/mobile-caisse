import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final String storeName;
  final String currency;
  final int decimals;
  final String qrTemplate;
  final String printerMac;
  final String printerName;

  const AppSettings({
    this.storeName = 'Ma boutique',
    this.currency = 'DT',
    this.decimals = 3,
    this.qrTemplate = 'https://pay.exemple.tn/?m={amount}',
    this.printerMac = '',
    this.printerName = '',
  });

  AppSettings copyWith({
    String? storeName,
    String? currency,
    int? decimals,
    String? qrTemplate,
    String? printerMac,
    String? printerName,
  }) =>
      AppSettings(
        storeName: storeName ?? this.storeName,
        currency: currency ?? this.currency,
        decimals: decimals ?? this.decimals,
        qrTemplate: qrTemplate ?? this.qrTemplate,
        printerMac: printerMac ?? this.printerMac,
        printerName: printerName ?? this.printerName,
      );

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
    );
  }

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
  }
}
