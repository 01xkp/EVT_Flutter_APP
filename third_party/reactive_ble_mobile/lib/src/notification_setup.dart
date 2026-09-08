import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _notificationSetupChannelName = 'flutter_reactive_ble_method';
const _canonicalUuidPattern =
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';

/// Waits until a characteristic's notification or indication CCC is active.
///
/// A caller may start this wait immediately before or after it listens to
/// `FlutterReactiveBle.subscribeToCharacteristic`. Android and Darwin retain
/// the result for the active subscription, so both orders observe the same
/// native acknowledgement. The caller should apply a timeout because no native
/// acknowledgement exists until it actually starts a subscription.
class ReactiveBleNotificationSetup {
  const ReactiveBleNotificationSetup({
    MethodChannel methodChannel = const MethodChannel(
      _notificationSetupChannelName,
    ),
  }) : _methodChannel = methodChannel;

  final MethodChannel _methodChannel;

  Future<void> awaitNotificationSetup({
    required String deviceId,
    required String characteristicUuid,
  }) async {
    if (deviceId.trim().isEmpty ||
        !RegExp(_canonicalUuidPattern).hasMatch(characteristicUuid)) {
      throw const ReactiveBleNotificationSetupException(
        code: 'invalid_notification_setup_arguments',
        message:
            'deviceId and a canonical 128-bit characteristicUuid are required.',
      );
    }
    if (!_supportsNativeNotificationSetup) {
      throw const ReactiveBleNotificationSetupException(
        code: 'notification_setup_unsupported',
        message:
            'The current platform does not provide native notification setup confirmation.',
      );
    }

    try {
      await _methodChannel.invokeMethod<void>('awaitNotificationSetup', {
        'deviceId': deviceId,
        'characteristicUuid': characteristicUuid,
      });
    } on MissingPluginException {
      throw const ReactiveBleNotificationSetupException(
        code: 'notification_setup_unavailable',
        message:
            'The installed BLE plugin does not provide notification setup confirmation.',
      );
    } on PlatformException catch (error) {
      throw ReactiveBleNotificationSetupException(
        code: error.code,
        message:
            error.message ?? 'Unable to enable characteristic notifications.',
      );
    }
  }

  static bool get _supportsNativeNotificationSetup =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.macOS => true,
        _ => false,
      };
}

class ReactiveBleNotificationSetupException implements Exception {
  const ReactiveBleNotificationSetupException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => 'ReactiveBleNotificationSetupException($code: $message)';
}
