import 'package:evt_ble_app/core/ble/device_profile.dart';
import 'package:evt_ble_app/core/diagnostics/evt_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile blocks GATT operations until all UUIDs are configured', () {
    final profile = DeviceProfile.empty();

    expect(profile.isGattReady, isFalse);
    expect(profile.validationFailure!.kind, EvtFailureKind.access);
  });

  test('profile is ready when every required GATT UUID is valid', () {
    const profile = DeviceProfile(
      namePrefix: 'AIPIN',
      manufacturerPrefixHex: 'A389',
      serviceUuid: '0000AF30-0000-1000-8000-00805F9B34FB',
      gattServiceUuid: '4FAFC201-1FB5-459E-8FCC-C5C9C331914B',
      readCharacteristicUuid: 'BEB5483E-36E1-4688-B7F5-EA07361B26A8',
      notifyCharacteristicUuid: '19B10010-E8F2-537E-4F6C-D104768A1214',
      writeCharacteristicUuid: '19B10011-E8F2-537E-4F6C-D104768A1214',
    );

    expect(profile.isGattReady, isTrue);
    expect(profile.validationFailure, isNull);
  });

  test('profile parses the documented scan configuration from JSON', () {
    final profile = DeviceProfile.fromJson(const {
      'namePrefix': 'AIPIN',
      'manufacturerPrefixHex': 'A389',
      'serviceUuid': '0000AF30-0000-1000-8000-00805F9B34FB',
      'gattServiceUuid': '',
      'readCharacteristicUuid': '',
      'notifyCharacteristicUuid': '',
      'writeCharacteristicUuid': '',
    });

    expect(profile.namePrefix, 'AIPIN');
    expect(profile.manufacturerPrefixBytes, const [0xA3, 0x89]);
  });
}
