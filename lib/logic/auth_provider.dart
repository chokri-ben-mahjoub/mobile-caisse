import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../data/settings_store.dart';

/// User accounts, sign-in and access rights.
///
/// With no user the app is open (single-user mode, as before). Once an owner
/// account exists, everyone signs in with a 4-digit PIN and only sees what
/// their role allows.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._db, this._store);
  final AppDatabase _db;
  final SettingsStore _store;

  List<AppUser> users = [];
  AppUser? current;

  /// Users who may sign in with the phone's fingerprint instead of the PIN.
  Set<int> _bio = {};

  int _failures = 0;
  DateTime? _lockedUntil;

  static const maxFailures = 5;
  static const lockSeconds = 30;

  static String hashPin(String pin) => sha256.convert(utf8.encode('caisse:$pin')).toString();

  /// Accounts are in use.
  bool get enabled => users.isNotEmpty;

  /// Needs to sign in before using the app.
  bool get needsLogin => enabled && current == null;

  bool get isOwner => !enabled || (current?.isOwner ?? false);

  /// Access check; everything is allowed when accounts are not enabled.
  bool can(int perm) => !enabled || (current?.can(perm) ?? false);

  String? get currentName => enabled ? current?.name : null;

  /// Seconds left before another PIN attempt is allowed (0 = allowed).
  int get lockRemaining {
    final until = _lockedUntil;
    if (until == null) return 0;
    final left = until.difference(DateTime.now()).inSeconds + 1;
    return left > 0 ? left : 0;
  }

  Future<void> load() async {
    _bio = await _store.loadBioUsers();
    users = await _db.users();
    if (users.isEmpty) {
      // Migrate the single PIN of earlier versions to an owner account.
      final old = await _store.loadPinHash();
      if (old != null) {
        await _db.insertUser(AppUser(name: 'Propriétaire', pinHash: old, role: Role.owner, perms: Perm.all));
        await _store.savePinHash(null);
        users = await _db.users();
      }
    }
    if (current != null && !users.any((u) => u.id == current!.id)) current = null;
    if (current != null) current = users.firstWhere((u) => u.id == current!.id);
    notifyListeners();
  }

  /// Returns true on success. Five wrong PINs lock sign-in for 30 seconds.
  bool login(AppUser user, String pin) {
    if (lockRemaining > 0) return false;
    if (user.pinHash == hashPin(pin)) {
      current = user;
      _failures = 0;
      _lockedUntil = null;
      notifyListeners();
      return true;
    }
    if (++_failures >= maxFailures) {
      _lockedUntil = DateTime.now().add(const Duration(seconds: lockSeconds));
      _failures = 0;
    }
    notifyListeners();
    return false;
  }

  bool bioEnabled(AppUser u) => u.id != null && _bio.contains(u.id);

  Future<void> setBio(AppUser u, bool on) async {
    if (u.id == null) return;
    on ? _bio.add(u.id!) : _bio.remove(u.id!);
    await _store.saveBioUsers(_bio);
    notifyListeners();
  }

  /// Signs [user] in after the phone confirmed the fingerprint (no PIN, no lockout counting).
  bool loginBiometric(AppUser user) {
    if (!bioEnabled(user)) return false;
    current = user;
    _failures = 0;
    _lockedUntil = null;
    notifyListeners();
    return true;
  }

  void logout() {
    if (current == null) return;
    current = null;
    notifyListeners();
  }

  bool verifyCurrentPin(String pin) => current != null && current!.pinHash == hashPin(pin);

  // ---- user management (owner) ----
  /// First owner: enables accounts and signs that owner in.
  Future<void> createFirstOwner(String name, String pin) async {
    final id = await _db.insertUser(AppUser(name: name, pinHash: hashPin(pin), role: Role.owner, perms: Perm.all));
    await load();
    current = users.firstWhere((u) => u.id == id);
    notifyListeners();
  }

  Future<void> addUser(String name, String pin, Role role, int perms) async {
    await _db.insertUser(AppUser(name: name, pinHash: hashPin(pin), role: role, perms: role == Role.owner ? Perm.all : perms));
    await load();
  }

  /// [pin] null keeps the current PIN.
  Future<void> updateUser(AppUser user, {required String name, required Role role, required int perms, String? pin}) async {
    await _db.updateUser(user.copyWith(
      name: name,
      role: role,
      perms: role == Role.owner ? Perm.all : perms,
      pinHash: pin == null ? null : hashPin(pin),
    ));
    await load();
  }

  Future<void> deleteUser(AppUser user) async {
    await setBio(user, false);
    await _db.deleteUser(user.id!);
    await load();
  }

  /// Back to single-user mode: removes every account.
  Future<void> disableAccounts() async {
    await _db.deleteAllUsers();
    current = null;
    await load();
  }

  int ownerCount() => users.where((u) => u.isOwner).length;

  bool nameTaken(String name, {int? exceptId}) =>
      users.any((u) => u.id != exceptId && u.name.toLowerCase() == name.trim().toLowerCase());
}
