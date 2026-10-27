import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/settings_store.dart';

/// Optional 4-digit PIN protecting Produits, Historique and Réglages.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._store, this._hash);
  final SettingsStore _store;
  String? _hash;
  bool _unlocked = false;
  int _failures = 0;

  bool get hasPin => _hash != null;
  bool get locked => hasPin && !_unlocked;
  int get failures => _failures;

  static String _h(String pin) => sha256.convert(utf8.encode('caisse:$pin')).toString();

  bool unlock(String pin) {
    if (_hash == _h(pin)) {
      _unlocked = true;
      _failures = 0;
      notifyListeners();
      return true;
    }
    _failures++;
    notifyListeners();
    return false;
  }

  void lock() {
    if (!hasPin) return;
    _unlocked = false;
    notifyListeners();
  }

  Future<void> setPin(String pin) async {
    _hash = _h(pin);
    _unlocked = true;
    notifyListeners();
    await _store.savePinHash(_hash);
  }

  Future<void> removePin() async {
    _hash = null;
    _unlocked = false;
    notifyListeners();
    await _store.savePinHash(null);
  }
}
