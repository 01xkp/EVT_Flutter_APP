import 'package:aipin/features/device_discovery/domain/advertisement_filter.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final matchingCandidate = DeviceCandidate(
    connectionId: 'A3:89:71:BF:E2:3B',
    name: 'AIPIN_8423',
    manufacturerData: const [0xA3, 0x89, 0x71, 0xBF, 0xE2, 0x3B, 0x84, 0x23],
    serviceUuids: const ['0000AF30-0000-1000-8000-00805F9B34FB'],
    rssi: -48,
    discoveredAt: DateTime(2026, 8, 21),
  );

  test('accepts only the V1.5 advertisement identity', () {
    final evaluation = const AdvertisementFilter().evaluate(matchingCandidate);

    expect(evaluation.matches, isTrue);
    expect(evaluation.reasons, isEmpty);
  });

  test('rejects a broadcast missing every required V1.5 identity field', () {
    final candidate = matchingCandidate.copyWith(
      name: 'Other_8423',
      manufacturerData: const [],
      serviceUuids: const [],
    );

    final evaluation = const AdvertisementFilter().evaluate(candidate);

    expect(evaluation.matches, isFalse);
    expect(
      evaluation.reasons,
      containsAll(<String>[
        'name_prefix',
        'manufacturer_prefix',
        'service_uuid',
      ]),
    );
  });

  test('rejects a plausible name when manufacturer bytes do not match', () {
    final candidate = matchingCandidate.copyWith(
      manufacturerData: const [0xA3, 0x88, 0x71],
    );

    final evaluation = const AdvertisementFilter().evaluate(candidate);

    expect(evaluation.matches, isFalse);
    expect(evaluation.reasons, contains('manufacturer_prefix'));
  });

  test(
    'rejects a partial name and a manufacturer payload without all six bytes',
    () {
      final candidate = matchingCandidate.copyWith(
        name: 'AIPIN_demo',
        manufacturerData: const [0xA3, 0x89, 0x71, 0xBF, 0xE2, 0x3B],
      );

      final evaluation = const AdvertisementFilter().evaluate(candidate);

      expect(evaluation.matches, isFalse);
      expect(
        evaluation.reasons,
        containsAll(<String>['name_format', 'manufacturer_format']),
      );
    },
  );

  test('rejects a name whose suffix does not match BtAddressRaw', () {
    final candidate = matchingCandidate.copyWith(name: 'AIPIN_1234');

    final evaluation = const AdvertisementFilter().evaluate(candidate);

    expect(evaluation.matches, isFalse);
    expect(evaluation.reasons, contains('name_address_mismatch'));
  });

  test(
    'derives one physical device ID across Android and iOS connection IDs',
    () {
      final iosCandidate = matchingCandidate.copyWith(
        connectionId: '54CFC0D1-6E6E-4D72-9F11-AAD4D292D751',
      );

      expect(matchingCandidate.physicalDeviceId, '71:BF:E2:3B:84:23');
      expect(iosCandidate.physicalDeviceId, '71:BF:E2:3B:84:23');
    },
  );
}
