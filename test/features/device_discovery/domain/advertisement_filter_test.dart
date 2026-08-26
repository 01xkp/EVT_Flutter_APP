import 'package:aipin/features/device_discovery/domain/advertisement_filter.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final matchingCandidate = DeviceCandidate(
    id: 'A3:89:71:BF:E2:3B',
    name: 'AIPIN_8423',
    manufacturerData: const [0xA3, 0x89, 0x71, 0xBF, 0xE2, 0x3B, 0x84, 0x23],
    serviceUuids: const ['0000AF30-0000-1000-8000-00805F9B34FB'],
    rssi: -48,
    discoveredAt: DateTime(2026, 8, 21),
  );

  test(
    'accepts a matching broadcast while discovery filtering is disabled',
    () {
      final evaluation = const AdvertisementFilter().evaluate(
        matchingCandidate,
      );

      expect(evaluation.matches, isTrue);
      expect(evaluation.reasons, isEmpty);
    },
  );

  test('accepts an arbitrary Bluetooth broadcast', () {
    final candidate = matchingCandidate.copyWith(
      name: '',
      manufacturerData: const [],
      serviceUuids: const [],
    );

    expect(const AdvertisementFilter().matches(candidate), isTrue);
  });
}
