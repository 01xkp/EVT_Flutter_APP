import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the opaque per-install salt used to correlate a device safely.
class DiagnosticInstallIdentity {
  const DiagnosticInstallIdentity._(this._salt);

  static const _storageKey = 'diagnostic.install_salt.v1';

  final List<int> _salt;

  static Future<DiagnosticInstallIdentity> loadOrCreate() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_storageKey);
    final salt = _decodeSalt(stored);
    if (salt != null) {
      return DiagnosticInstallIdentity._(salt);
    }

    final generated = List<int>.generate(
      32,
      (_) => Random.secure().nextInt(256),
    );
    await preferences.setString(_storageKey, base64UrlEncode(generated));
    return DiagnosticInstallIdentity._(generated);
  }

  /// Returns a short, stable reference without storing or exposing [deviceId].
  String deviceReference(String deviceId) {
    final digest = Hmac(sha256, _salt).convert(utf8.encode(deviceId));
    return digest.toString().substring(0, 12);
  }

  static List<int>? _decodeSalt(String? value) {
    if (value == null) {
      return null;
    }
    try {
      final decoded = base64Url.decode(value);
      return decoded.length == 32 ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
