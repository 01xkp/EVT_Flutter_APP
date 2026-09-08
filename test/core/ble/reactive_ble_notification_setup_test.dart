import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactive_ble_mobile/reactive_ble_mobile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_reactive_ble_method');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'passes the canonical subscription identity to the native barrier',
    () async {
      MethodCall? receivedCall;
      messenger.setMockMethodCallHandler(channel, (call) async {
        receivedCall = call;
        return null;
      });

      await const ReactiveBleNotificationSetup().awaitNotificationSetup(
        deviceId: 'device-1',
        characteristicUuid: '0000fa19-0000-1000-8000-00805f9b34fb',
      );

      expect(receivedCall?.method, 'awaitNotificationSetup');
      expect(receivedCall?.arguments, <String, Object>{
        'deviceId': 'device-1',
        'characteristicUuid': '0000fa19-0000-1000-8000-00805f9b34fb',
      });
    },
  );

  test(
    'rejects a noncanonical characteristic UUID before calling native code',
    () async {
      await expectLater(
        const ReactiveBleNotificationSetup().awaitNotificationSetup(
          deviceId: 'device-1',
          characteristicUuid: 'fa19',
        ),
        throwsA(
          isA<ReactiveBleNotificationSetupException>().having(
            (error) => error.code,
            'code',
            'invalid_notification_setup_arguments',
          ),
        ),
      );
    },
  );

  test('maps an absent native implementation to an explicit error', () async {
    await expectLater(
      const ReactiveBleNotificationSetup().awaitNotificationSetup(
        deviceId: 'device-1',
        characteristicUuid: '0000fa19-0000-1000-8000-00805f9b34fb',
      ),
      throwsA(
        isA<ReactiveBleNotificationSetupException>().having(
          (error) => error.code,
          'code',
          'notification_setup_unavailable',
        ),
      ),
    );
  });
}
