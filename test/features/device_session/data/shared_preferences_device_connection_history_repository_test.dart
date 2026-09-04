import 'dart:async';

import 'package:aipin/features/device_session/data/shared_preferences_device_connection_history_repository.dart';
import 'package:aipin/features/device_session/domain/remembered_device.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const historyKey = 'device.connection_history.v1';

  RememberedDevice record(
    String connectionId, {
    required int minute,
    String? physicalMacAddress,
  }) {
    return RememberedDevice(
      connectionId: connectionId,
      physicalMacAddress: physicalMacAddress,
      displayName: 'AIPIN',
      lastConnectedAt: DateTime.utc(2026, 9, 4, 10, minute),
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'upsert replaces a matching device and retains at most five records',
    () async {
      final repository = SharedPreferencesDeviceConnectionHistoryRepository();

      await repository.upsert(record('transport-1', minute: 1));
      await repository.upsert(record('transport-1', minute: 2));
      for (var index = 2; index <= 6; index += 1) {
        await repository.upsert(record('transport-$index', minute: index));
      }

      final records = await repository.load();
      expect(records, hasLength(5));
      expect(records.first.connectionId, 'transport-6');
      expect(
        records.any((item) => item.connectionId == 'transport-1'),
        isFalse,
      );
    },
  );

  test('upsert treats a matching physical MAC as the same device', () async {
    final repository = SharedPreferencesDeviceConnectionHistoryRepository();

    await repository.upsert(
      record(
        'old-ios-uuid',
        minute: 1,
        physicalMacAddress: 'AA:BB:CC:DD:EE:FF',
      ),
    );
    await repository.upsert(
      record(
        'new-ios-uuid',
        minute: 2,
        physicalMacAddress: 'aa-bb-cc-dd-ee-ff',
      ),
    );

    final records = await repository.load();
    expect(records, hasLength(1));
    expect(records.single.connectionId, 'new-ios-uuid');
  });

  test('drops malformed serialized rows instead of throwing', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      historyKey: '[{"connectionId":1}]',
    });
    final repository = SharedPreferencesDeviceConnectionHistoryRepository();

    expect(await repository.load(), isEmpty);
  });

  test('treats a non-string SharedPreferences value as missing', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{historyKey: 1});
    final repository = SharedPreferencesDeviceConnectionHistoryRepository();

    expect(await repository.load(), isEmpty);
  });

  test('drops rows with an empty physical MAC address', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      historyKey:
          '[{"connectionId":"transport","physicalMacAddress":"",'
          '"displayName":"AIPIN","lastConnectedAt":"2026-09-04T10:00:00Z"}]',
    });
    final repository = SharedPreferencesDeviceConnectionHistoryRepository();

    expect(await repository.load(), isEmpty);
  });

  test(
    'removes a record by physical MAC before a changed connection id',
    () async {
      final repository = SharedPreferencesDeviceConnectionHistoryRepository();
      await repository.upsert(
        record(
          'old-ios-uuid',
          minute: 1,
          physicalMacAddress: 'AA:BB:CC:DD:EE:FF',
        ),
      );

      await repository.removeMatching(
        connectionId: 'new-ios-uuid',
        physicalMacAddress: 'AA:BB:CC:DD:EE:FF',
      );

      expect(await repository.load(), isEmpty);
    },
  );

  test('serializes concurrent upserts without losing records', () async {
    final preferences = _DelayedWritePreferences();
    final repository = SharedPreferencesDeviceConnectionHistoryRepository(
      preferences: preferences,
    );
    final operations = <Future<void>>[
      for (var index = 1; index <= 5; index += 1)
        repository.upsert(record('transport-$index', minute: index)),
    ];

    await preferences.firstWriteStarted;
    preferences.releaseWrites();
    await Future.wait(operations);

    final records = await repository.load();
    expect(records, hasLength(5));
    expect(
      records.map((item) => item.connectionId),
      containsAll(<String>[
        'transport-1',
        'transport-2',
        'transport-3',
        'transport-4',
        'transport-5',
      ]),
    );
  });

  test('throws a controlled error when saving the history is rejected', () {
    final repository = SharedPreferencesDeviceConnectionHistoryRepository(
      preferences: _InMemoryHistoryPreferences(setResult: false),
    );

    expect(
      repository.upsert(record('transport', minute: 1)),
      throwsA(isA<DeviceConnectionHistoryStorageException>()),
    );
  });

  test(
    'throws a controlled error when removing the history is rejected',
    () async {
      final preferences = _InMemoryHistoryPreferences();
      final repository = SharedPreferencesDeviceConnectionHistoryRepository(
        preferences: preferences,
      );
      await repository.upsert(record('transport', minute: 1));
      preferences.removeResult = false;

      expect(
        repository.removeMatching(connectionId: 'transport'),
        throwsA(isA<DeviceConnectionHistoryStorageException>()),
      );
    },
  );
}

class _InMemoryHistoryPreferences
    implements DeviceConnectionHistoryPreferences {
  _InMemoryHistoryPreferences({this.setResult = true});

  final Map<String, String> _values = <String, String>{};
  bool setResult;
  bool removeResult = true;

  @override
  String? getString(String key) => _values[key];

  @override
  Future<bool> remove(String key) async {
    if (removeResult) {
      _values.remove(key);
    }
    return removeResult;
  }

  @override
  Future<bool> setString(String key, String value) async {
    if (setResult) {
      _values[key] = value;
    }
    return setResult;
  }
}

class _DelayedWritePreferences extends _InMemoryHistoryPreferences {
  final Completer<void> _firstWriteStarted = Completer<void>();
  final Completer<void> _writesReleased = Completer<void>();

  Future<void> get firstWriteStarted => _firstWriteStarted.future;

  void releaseWrites() {
    if (!_writesReleased.isCompleted) {
      _writesReleased.complete();
    }
  }

  @override
  Future<bool> setString(String key, String value) async {
    if (!_firstWriteStarted.isCompleted) {
      _firstWriteStarted.complete();
    }
    await _writesReleased.future;
    return super.setString(key, value);
  }
}
