import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// The phone's fingerprint / face unlock, used as a faster alternative to the PIN.
class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// True when the phone has a fingerprint (or face) enrolled.
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported() || !await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Shows the system fingerprint prompt; false when cancelled, refused or unavailable.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, biometricOnly: true);
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }
}
