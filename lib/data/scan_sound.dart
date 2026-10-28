import 'package:flutter/services.dart';

/// Scanner-style sounds: a short high beep when an article is read, a low double beep for a problem
/// (unknown code, not enough stock). Played natively so it is instant; falls back to the system click.
class ScanSound {
  ScanSound._();
  static const _channel = MethodChannel('caisse/sound');

  static Future<void> beep() => _play('beep');
  static Future<void> error() => _play('error');

  static Future<void> _play(String name) async {
    try {
      await _channel.invokeMethod<void>(name);
    } on MissingPluginException {
      await SystemSound.play(SystemSoundType.click);
    } on PlatformException {
      await SystemSound.play(SystemSoundType.click);
    }
  }
}
