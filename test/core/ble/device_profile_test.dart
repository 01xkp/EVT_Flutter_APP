import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
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

  test(
    'profile supports documented read and notification endpoints on separate services',
    () {
      const profile = DeviceProfile(
        namePrefix: 'AIPIN',
        manufacturerPrefixHex: 'A389',
        serviceUuid: '0000AF30-0000-1000-8000-00805F9B34FB',
        gattServiceUuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
        readServiceUuid: '0000FB10-1212-EFDE-1523-785FEABCD123',
        readCharacteristicUuid: '0000FB11-1212-EFDE-1523-785FEABCD123',
        notifyServiceUuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
        notifyCharacteristicUuid: '0000FA16-1212-EFDE-1523-785FEABCD123',
        writeServiceUuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
        writeCharacteristicUuid: '0000FA16-1212-EFDE-1523-785FEABCD123',
      );

      expect(
        profile.readEndpoint.serviceUuid,
        '0000FB10-1212-EFDE-1523-785FEABCD123',
      );
      expect(
        profile.notifyEndpoint.serviceUuid,
        '0000FA10-1212-EFDE-1523-785FEABCD123',
      );
    },
  );

  test('profile normalizes short UUIDs and exposes endpoint capabilities', () {
    final profile = DeviceProfile.fromJson(const {
      'namePrefix': 'AIPIN',
      'manufacturerPrefixHex': 'A389',
      'serviceUuid': 'AF30',
      'endpoints': {
        'fa10': {
          'fa11': {'uuid': 'FA11', 'operations': ['read', 'notify']},
          'fa15': {'uuid': 'FA15', 'operations': ['write']},
        },
        'wqota': {
          '2001': {'uuid': '2001', 'operations': ['writeWithoutResponse']},
        },
      },
    });

    expect(profile.serviceUuid, '0000AF30-0000-1000-8000-00805F9B34FB');
    expect(profile.endpoints[BleLogicalEndpoint.fa10Fa11]!.operations,
        contains(BleOperation.notify));
    expect(profile.endpoints[BleLogicalEndpoint.fa10Fa15]!.operations,
        contains(BleOperation.write));
    expect(profile.endpoints[BleLogicalEndpoint.wqota2001]!.operations,
        contains(BleOperation.writeWithoutResponse));
    expect(profile.endpoint(BleLogicalEndpoint.fa10Fa11).characteristicUuid,
        '0000FA11-0000-1000-8000-00805F9B34FB');
  });

  test('profile rejects operations not declared by an endpoint', () {
    const profile = DeviceProfile(
      namePrefix: 'AIPIN',
      manufacturerPrefixHex: 'A389',
      serviceUuid: 'AF30',
      gattServiceUuid: 'FA10',
      readCharacteristicUuid: 'FB11',
      notifyCharacteristicUuid: 'FA16',
      writeCharacteristicUuid: 'FA15',
      endpoints: {
        BleLogicalEndpoint.fa10Fa15: BleEndpoint(
          serviceUuid: 'FA10',
          characteristicUuid: 'FA15',
          operations: {BleOperation.read},
        ),
      },
    );

    expect(profile.canOperate(BleLogicalEndpoint.fa10Fa15, BleOperation.write),
        isFalse);
  });
}
