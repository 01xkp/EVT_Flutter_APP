import 'package:evt_ble_app/features/device_discovery/domain/advertisement_filter.dart';
import 'package:evt_ble_app/features/device_discovery/domain/device_candidate.dart';
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

  test('accepts a matching documented broadcast', () {
    final evaluation = const AdvertisementFilter().evaluate(matchingCandidate);

    expect(evaluation.matches, isTrue);
    expect(evaluation.reasons, contains('厂商数据 A3 89'));
  });

  test('rejects a candidate that is missing the documented service UUID', () {
    final candidate = matchingCandidate.copyWith(serviceUuids: const []);

    expect(const AdvertisementFilter().matches(candidate), isFalse);
  });
}
