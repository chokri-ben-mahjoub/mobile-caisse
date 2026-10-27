import 'package:flutter/foundation.dart';

import '../data/settings_store.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._store, this.settings);
  final SettingsStore _store;
  AppSettings settings;

  Future<void> update(AppSettings s) async {
    settings = s;
    notifyListeners();
    await _store.save(s);
  }
}
