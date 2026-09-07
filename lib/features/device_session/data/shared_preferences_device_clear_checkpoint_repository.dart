import 'dart:convert';

import 'package:aipin/features/device_session/domain/device_clear_checkpoint.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesDeviceClearCheckpointRepository
    implements DeviceClearCheckpointRepository {
  static const _keyPrefix = 'device.clear.checkpoint.';

  @override
  Future<DeviceClearCheckpoint?> find(String deviceId) async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString('$_keyPrefix$deviceId');
    if (value == null) {
      return null;
    }
    try {
      final json = jsonDecode(value);
      if (json is! Map<String, dynamic>) {
        return null;
      }
      final transactionId = json['transactionId'];
      final expectedBindingGeneration = json['expectedBindingGeneration'];
      final clearScope = json['clearScope'];
      final nonce = json['confirmNonce'];
      if (transactionId is! int ||
          expectedBindingGeneration is! int ||
          clearScope is! int ||
          nonce is! List ||
          nonce.length != 16 ||
          nonce.any((value) => value is! int || value < 0 || value > 0xFF)) {
        return null;
      }
      return DeviceClearCheckpoint(
        deviceId: deviceId,
        transactionId: transactionId,
        expectedBindingGeneration: expectedBindingGeneration,
        confirmNonce: nonce.cast<int>(),
        clearScope: clearScope,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on RangeError {
      return null;
    }
  }

  @override
  Future<void> save(DeviceClearCheckpoint checkpoint) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_keyPrefix${checkpoint.deviceId}',
      jsonEncode({
        'transactionId': checkpoint.transactionId,
        'expectedBindingGeneration': checkpoint.expectedBindingGeneration,
        'confirmNonce': checkpoint.confirmNonce,
        'clearScope': checkpoint.clearScope,
      }),
    );
  }

  @override
  Future<void> clear(String deviceId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('$_keyPrefix$deviceId');
  }
}
