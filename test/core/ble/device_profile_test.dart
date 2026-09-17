import 'dart:convert';
import 'dart:io';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile blocks GATT operations until all UUIDs are configured', () {
    final profile = DeviceProfile.empty();

    expect(profile.isGattReady, isFalse);
    expect(profile.validationFailure!.kind, EvtFailureKind.access);
  });

  test(
    'profile is ready when all required DVT V1.6 endpoints are declared',
    () {
      final profile = _evtProfile();

      expect(profile.isGattReady, isTrue);
      expect(profile.validationFailure, isNull);
    },
  );

  test('compiled DVT V1.6 profile is ready and immutable for connections', () {
    final first = DeviceProfile.dvtV16();
    final second = DeviceProfile.dvtV16();

    expect(identical(first, second), isTrue);
    expect(identical(first, DeviceProfile.evtV16()), isTrue);
    expect(first.isGattReady, isTrue);
    expect(
      first.endpoints.keys,
      unorderedEquals(DeviceProfile.dvtV16EndpointOperations.keys),
    );
    expect(
      () => first.endpoints[BleLogicalEndpoint.fa10Fa11] = const BleEndpoint(
        serviceUuid: _fa10,
        characteristicUuid: _fa11,
      ),
      throwsUnsupportedError,
    );
  });

  test('profile parses the documented scan configuration from JSON', () {
    final profile = DeviceProfile.fromJson(const {
      'namePrefix': 'AIPIN',
      'manufacturerPrefixHex': 'A389',
      'serviceUuid': '0000AF30-0000-1000-8000-00805F9B34FB',
      'gattServiceUuid': '',
    });

    expect(profile.namePrefix, 'AIPIN');
    expect(profile.manufacturerPrefixBytes, const [0xA3, 0x89]);
  });

  test(
    'profile maps DVT archive, audio and WQOTA capabilities to documented services',
    () {
      final profile = _evtProfile();

      expect(
        profile.endpoint(BleLogicalEndpoint.fb10Fb11).serviceUuid,
        '0000FB10-1212-EFDE-1523-785FEABCD123',
      );
      expect(profile.endpoint(BleLogicalEndpoint.ff10Ff16).serviceUuid, _ff10);
      expect(
        profile.endpoint(BleLogicalEndpoint.ff10Ff16).operations,
        containsAll(<BleOperation>{BleOperation.write, BleOperation.indicate}),
      );
      expect(
        profile.endpoint(BleLogicalEndpoint.fa10Fa18).serviceUuid,
        '0000FA10-1212-EFDE-1523-785FEABCD123',
      );
      expect(
        profile.endpoint(BleLogicalEndpoint.fa10Fa18).operations,
        contains(BleOperation.notify),
      );
      expect(
        profile.endpoint(BleLogicalEndpoint.wqota2001).serviceUuid,
        _wqota,
      );
      expect(
        profile.endpoint(BleLogicalEndpoint.wqota2001).operations,
        contains(BleOperation.writeWithoutResponse),
      );
      expect(
        profile.endpoint(BleLogicalEndpoint.wqota2002).operations,
        contains(BleOperation.notify),
      );
    },
  );

  test(
    'profile normalizes short UUIDs while parsing endpoint capabilities',
    () {
      final profile = DeviceProfile.fromJson(const {
        'namePrefix': 'AIPIN',
        'manufacturerPrefixHex': 'A389',
        'serviceUuid': 'AF30',
        'endpoints': {
          'fa10': {
            'fa11': {
              'uuid': 'FA11',
              'operations': ['read', 'notify'],
            },
          },
        },
      });

      expect(profile.serviceUuid, '0000AF30-0000-1000-8000-00805F9B34FB');
      expect(
        profile.endpoints[BleLogicalEndpoint.fa10Fa11]!.operations,
        contains(BleOperation.notify),
      );
      expect(
        profile.endpoint(BleLogicalEndpoint.fa10Fa11).characteristicUuid,
        '0000FA11-0000-1000-8000-00805F9B34FB',
      );
    },
  );

  test('profile blocks startup when an EVT endpoint is missing a property', () {
    final endpoints = Map<BleLogicalEndpoint, BleEndpoint>.from(_evtEndpoints);
    endpoints[BleLogicalEndpoint.fa10Fa17] = const BleEndpoint(
      serviceUuid: _fa10,
      characteristicUuid: _fa17,
      operations: {BleOperation.write},
    );
    final profile = _evtProfile(endpoints: endpoints);

    expect(profile.isGattReady, isFalse);
  });

  test('profile blocks startup when an EVT endpoint UUID drifts', () {
    final endpoints = Map<BleLogicalEndpoint, BleEndpoint>.from(_evtEndpoints);
    endpoints[BleLogicalEndpoint.fa10Fa17] = const BleEndpoint(
      serviceUuid: _fa10,
      characteristicUuid: _fa16,
      operations: {BleOperation.write, BleOperation.indicate},
    );

    expect(_evtProfile(endpoints: endpoints).isGattReady, isFalse);
  });

  test('profile blocks startup when the EVT advertisement contract drifts', () {
    final profile = _evtProfile(
      serviceUuid: '0000AF31-0000-1000-8000-00805F9B34FB',
    );

    expect(profile.isGattReady, isFalse);
  });

  test('profile blocks startup when JSON declares a non-EVT endpoint', () {
    final raw =
        jsonDecode(File('assets/config/device_profile.json').readAsStringSync())
            as Map<String, dynamic>;
    final endpoints = raw['endpoints'] as Map<String, dynamic>;
    endpoints['future'] = <String, dynamic>{
      'futureCharacteristic': <String, dynamic>{
        'uuid': '0000F0F0-1212-EFDE-1523-785FEABCD123',
        'operations': <String>['notify'],
      },
    };

    final profile = DeviceProfile.fromJson(raw);

    expect(profile.hasUnsupportedEndpointDeclaration, isTrue);
    expect(profile.isGattReady, isFalse);
  });

  test('optional DVT validation endpoints do not block GATT readiness', () {
    final requiredOnly = Map<BleLogicalEndpoint, BleEndpoint>.fromEntries(
      _evtEndpoints.entries.where(
        (entry) => DeviceProfile.dvtV16RequiredEndpointOperations.containsKey(
          entry.key,
        ),
      ),
    );

    expect(_evtProfile(endpoints: requiredOnly).isGattReady, isTrue);
  });

  test('bundled profile declares the V1.6 DVT endpoint set', () {
    final decoded = jsonDecode(
      File('assets/config/device_profile.json').readAsStringSync(),
    );
    final profile = DeviceProfile.fromJson(decoded as Map<String, Object?>);

    expect(profile.isGattReady, isTrue);
    expect(
      profile.endpoints.keys,
      unorderedEquals(DeviceProfile.dvtV16EndpointOperations.keys),
    );
    expect(
      BleLogicalEndpoint.values,
      unorderedEquals(DeviceProfile.dvtV16EndpointOperations.keys),
    );
    for (final entry in DeviceProfile.dvtV16EndpointOperations.entries) {
      expect(
        profile.endpoints[entry.key]!.operations,
        containsAll(entry.value),
      );
    }
  });

  test('profile rejects operations not declared by an endpoint', () {
    const profile = DeviceProfile(
      namePrefix: 'AIPIN',
      manufacturerPrefixHex: 'A389',
      serviceUuid: 'AF30',
      gattServiceUuid: 'FA10',
      endpoints: {
        BleLogicalEndpoint.fa10Fa15: BleEndpoint(
          serviceUuid: 'FA10',
          characteristicUuid: 'FA15',
          operations: {BleOperation.read},
        ),
      },
    );

    expect(
      profile.canOperate(BleLogicalEndpoint.fa10Fa15, BleOperation.write),
      isFalse,
    );
  });
}

const _fa10 = '0000FA10-1212-EFDE-1523-785FEABCD123';
const _fb10 = '0000FB10-1212-EFDE-1523-785FEABCD123';
const _ff10 = '0000FF10-1212-EFDE-1523-785FEABCD123';
const _fa11 = '0000FA11-1212-EFDE-1523-785FEABCD123';
const _fa12 = '0000FA12-1212-EFDE-1523-785FEABCD123';
const _fa15 = '0000FA15-1212-EFDE-1523-785FEABCD123';
const _fa16 = '0000FA16-1212-EFDE-1523-785FEABCD123';
const _fa17 = '0000FA17-1212-EFDE-1523-785FEABCD123';
const _fa19 = '0000FA19-1212-EFDE-1523-785FEABCD123';
const _fb11 = '0000FB11-1212-EFDE-1523-785FEABCD123';
const _ff11 = '0000FF11-1212-EFDE-1523-785FEABCD123';
const _ff12 = '0000FF12-1212-EFDE-1523-785FEABCD123';
const _ff13 = '0000FF13-1212-EFDE-1523-785FEABCD123';
const _ff16 = '0000FF16-1212-EFDE-1523-785FEABCD123';
const _fa18 = '0000FA18-1212-EFDE-1523-785FEABCD123';
const _wqota = '00007033-0000-1000-8000-00805F9B34FB';

final _evtEndpoints = <BleLogicalEndpoint, BleEndpoint>{
  BleLogicalEndpoint.fa10Fa11: const BleEndpoint(
    serviceUuid: _fa10,
    characteristicUuid: _fa11,
    operations: {BleOperation.write, BleOperation.indicate},
  ),
  BleLogicalEndpoint.fa10Fa12: const BleEndpoint(
    serviceUuid: _fa10,
    characteristicUuid: _fa12,
    operations: {BleOperation.read, BleOperation.write, BleOperation.indicate},
  ),
  BleLogicalEndpoint.fa10Fa15: const BleEndpoint(
    serviceUuid: _fa10,
    characteristicUuid: _fa15,
    operations: {BleOperation.write, BleOperation.indicate},
  ),
  BleLogicalEndpoint.fa10Fa16: const BleEndpoint(
    serviceUuid: _fa10,
    characteristicUuid: _fa16,
    operations: {BleOperation.write, BleOperation.indicate},
  ),
  BleLogicalEndpoint.fa10Fa17: const BleEndpoint(
    serviceUuid: _fa10,
    characteristicUuid: _fa17,
    operations: {BleOperation.write, BleOperation.indicate},
  ),
  BleLogicalEndpoint.fa10Fa18: const BleEndpoint(
    serviceUuid: _fa10,
    characteristicUuid: _fa18,
    operations: {BleOperation.notify},
  ),
  BleLogicalEndpoint.fa10Fa19: const BleEndpoint(
    serviceUuid: _fa10,
    characteristicUuid: _fa19,
    operations: {BleOperation.write, BleOperation.indicate},
  ),
  BleLogicalEndpoint.fb10Fb11: const BleEndpoint(
    serviceUuid: _fb10,
    characteristicUuid: _fb11,
    operations: {BleOperation.read, BleOperation.indicate},
  ),
  BleLogicalEndpoint.ff10Ff11: const BleEndpoint(
    serviceUuid: _ff10,
    characteristicUuid: _ff11,
    operations: {BleOperation.write, BleOperation.indicate},
  ),
  BleLogicalEndpoint.ff10Ff12: const BleEndpoint(
    serviceUuid: _ff10,
    characteristicUuid: _ff12,
    operations: {BleOperation.write, BleOperation.indicate},
  ),
  BleLogicalEndpoint.ff10Ff13: const BleEndpoint(
    serviceUuid: _ff10,
    characteristicUuid: _ff13,
    operations: {BleOperation.write, BleOperation.notify},
  ),
  BleLogicalEndpoint.ff10Ff16: const BleEndpoint(
    serviceUuid: _ff10,
    characteristicUuid: _ff16,
    operations: {BleOperation.write, BleOperation.indicate},
  ),
  BleLogicalEndpoint.wqota2001: const BleEndpoint(
    serviceUuid: _wqota,
    characteristicUuid: '00002001-0000-1000-8000-00805F9B34FB',
    operations: {BleOperation.writeWithoutResponse},
  ),
  BleLogicalEndpoint.wqota2002: const BleEndpoint(
    serviceUuid: _wqota,
    characteristicUuid: '00002002-0000-1000-8000-00805F9B34FB',
    operations: {BleOperation.notify},
  ),
};

DeviceProfile _evtProfile({
  Map<BleLogicalEndpoint, BleEndpoint>? endpoints,
  String serviceUuid = '0000AF30-0000-1000-8000-00805F9B34FB',
}) => DeviceProfile(
  namePrefix: 'AIPIN',
  manufacturerPrefixHex: 'A389',
  serviceUuid: serviceUuid,
  gattServiceUuid: _fa10,
  endpoints: endpoints ?? _evtEndpoints,
);
