import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:aipin/features/device_session/domain/remembered_device.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DeviceCandidate candidateFor({
    required String connectionId,
    List<int> manufacturerData = const <int>[],
  }) {
    return DeviceCandidate(
      connectionId: connectionId,
      name: 'AIPIN_1234',
      manufacturerData: manufacturerData,
      serviceUuids: const <String>[],
      rssi: -60,
      discoveredAt: DateTime.utc(2026, 9, 4),
    );
  }

  test('matches the V1.5 physical MAC before the platform connection id', () {
    final record = RememberedDevice(
      connectionId: 'ios-transport-uuid',
      physicalMacAddress: 'AA:BB:CC:DD:EE:FF',
      displayName: 'AIPIN',
      lastConnectedAt: DateTime.utc(2026, 9, 4),
    );
    final candidate = candidateFor(
      connectionId: 'different-ios-uuid',
      manufacturerData: const <int>[
        0xA3,
        0x89,
        0xAA,
        0xBB,
        0xCC,
        0xDD,
        0xEE,
        0xFF,
      ],
    );

    expect(record.matches(candidate), isTrue);
  });

  test('falls back to the platform connection id without a broadcast MAC', () {
    final record = RememberedDevice(
      connectionId: 'ios-transport-uuid',
      displayName: 'AIPIN',
      lastConnectedAt: DateTime.utc(2026, 9, 4),
    );

    expect(
      record.matches(candidateFor(connectionId: 'ios-transport-uuid')),
      isTrue,
    );
  });

  test('does not treat a non-V1.5 advertisement as a physical MAC match', () {
    final record = RememberedDevice(
      connectionId: 'ios-transport-uuid',
      physicalMacAddress: 'AA:BB:CC:DD:EE:FF',
      displayName: 'AIPIN',
      lastConnectedAt: DateTime.utc(2026, 9, 4),
    );
    final nonV15Advertisement = const <int>[
      0x01,
      0x02,
      0xAA,
      0xBB,
      0xCC,
      0xDD,
      0xEE,
      0xFF,
    ];

    expect(
      record.matches(
        candidateFor(
          connectionId: 'different-ios-uuid',
          manufacturerData: nonV15Advertisement,
        ),
      ),
      isFalse,
    );
    expect(
      record.matches(
        candidateFor(
          connectionId: 'ios-transport-uuid',
          manufacturerData: nonV15Advertisement,
        ),
      ),
      isTrue,
    );
  });

  test('normalizes valid physical MAC storage values and timestamps', () {
    final record = RememberedDevice(
      connectionId: 'transport',
      physicalMacAddress: 'aa-bb-cc-dd-ee-ff',
      displayName: ' AIPIN ',
      lastConnectedAt: DateTime(2026, 9, 4, 8, 0, 0, 123),
    );

    expect(record.physicalMacAddress, 'AA:BB:CC:DD:EE:FF');
    expect(record.displayName, 'AIPIN');
    expect(record.lastConnectedAt.isUtc, isTrue);
  });

  test('rejects invalid physical MAC storage values', () {
    expect(
      () => RememberedDevice(
        connectionId: 'transport',
        physicalMacAddress: 'raw-device-id',
        displayName: 'AIPIN',
        lastConnectedAt: DateTime.utc(2026),
      ),
      throwsFormatException,
    );
  });
}
