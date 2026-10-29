import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../data/settings_store.dart';
import '../ui/i18n/tr.dart';
import '../ui/theme.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._store, this.settings) {
    _applyLanguage();
  }
  final SettingsStore _store;
  AppSettings settings;

  /// Keeps the global translator, the date formats and the accent colour on the chosen settings.
  void _applyLanguage() {
    AppAccent.current = AppAccent.byKey(settings.accent);
    Tr.lang = settings.language;
    Intl.defaultLocale = settings.language == 'ar' ? 'ar_TN' : 'fr_FR';
  }

  Future<void> update(AppSettings s) async {
    settings = s;
    _applyLanguage();
    notifyListeners();
    await _store.save(s);
  }
}
