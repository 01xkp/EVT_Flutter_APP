import 'dart:convert';

import 'package:aipin/features/device_session/domain/device_connection_history_repository.dart';
import 'package:aipin/features/device_session/domain/remembered_device.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class DeviceConnectionHistoryPreferences {
  String? getString(String key);

  Future<bool> setString(String key, String value);

  Future<bool> remove(String key);
}

class DeviceConnectionHistoryStorageException implements Exception {
  const DeviceConnectionHistoryStorageException();

  @override
  String toString() => 'device_connection_history_storage_failure';
}

class SharedPreferencesDeviceConnectionHistoryRepository
    implements DeviceConnectionHistoryRepository {
  SharedPreferencesDeviceConnectionHistoryRepository({
    DeviceConnectionHistoryPreferences? preferences,
  }) {
    _preferences = preferences;
  }

  static const _storageKey = 'device.connection_history.v1';
  static const _maximumRecords = 5;
  DeviceConnectionHistoryPreferences? _preferences;
  Future<void> _operationTail = Future<void>.value();

  @override
  Future<List<RememberedDevice>> load() {
    return _runExclusive(() async {
      final preferences = await _getPreferences();
      return _loadNormalized(preferences);
    });
  }

  @override
  Future<void> upsert(RememberedDevice record) {
    return _runExclusive(() async {
      final preferences = await _getPreferences();
      final existing = await _loadNormalized(preferences);
      final records = _normalizeRecords(<RememberedDevice>[
        record,
        for (final item in existing)
          if (!_isSameDevice(item, record)) item,
      ]);
      await _write(preferences, records);
    });
  }

  @override
  Future<void> removeMatching({
    required String connectionId,
    String? physicalMacAddress,
  }) {
    return _runExclusive(() async {
      final normalizedConnectionId = RememberedDevice.normalizeConnectionId(
        connectionId,
      );
      final normalizedMacAddress = RememberedDevice.normalizePhysicalMacAddress(
        physicalMacAddress,
      );
      final preferences = await _getPreferences();
      final existing = await _loadNormalized(preferences);
      final records = existing
          .where(
            (record) => !_isSameDeviceValues(
              record,
              connectionId: normalizedConnectionId,
              physicalMacAddress: normalizedMacAddress,
            ),
          )
          .toList(growable: false);
      await _write(preferences, records);
    });
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) {
    final result = _operationTail.then<T>((_) => operation());
    _operationTail = result.then<void>((_) {}).catchError((_) {});
    return result;
  }

  Future<DeviceConnectionHistoryPreferences> _getPreferences() async {
    final existing = _preferences;
    if (existing != null) {
      return existing;
    }
    final preferences = _SharedPreferencesDeviceConnectionHistoryPreferences(
      await SharedPreferences.getInstance(),
    );
    _preferences = preferences;
    return preferences;
  }

  Future<List<RememberedDevice>> _loadNormalized(
    DeviceConnectionHistoryPreferences preferences,
  ) async {
    String? storedValue;
    try {
      storedValue = preferences.getString(_storageKey);
    } on TypeError {
      await _removeMalformedValue(preferences);
      return const <RememberedDevice>[];
    }
    if (storedValue == null) {
      return const <RememberedDevice>[];
    }

    final records = _decode(storedValue);
    final normalized = _normalizeRecords(records);
    if (!_hasSameSerializedValue(storedValue, normalized)) {
      await _write(preferences, normalized);
    }
    return normalized;
  }

  List<RememberedDevice> _decode(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) {
        return const <RememberedDevice>[];
      }
      final records = <RememberedDevice>[];
      for (final row in decoded) {
        final record = _decodeRecord(row);
        if (record != null) {
          records.add(record);
        }
      }
      return records;
    } on FormatException {
      return const <RememberedDevice>[];
    } on TypeError {
      return const <RememberedDevice>[];
    }
  }

  RememberedDevice? _decodeRecord(Object? value) {
    if (value is! Map) {
      return null;
    }
    final connectionId = value['connectionId'];
    final physicalMacAddress = value['physicalMacAddress'];
    final displayName = value['displayName'];
    final lastConnectedAt = value['lastConnectedAt'];
    if (connectionId is! String ||
        (physicalMacAddress != null && physicalMacAddress is! String) ||
        displayName is! String ||
        lastConnectedAt is! String) {
      return null;
    }
    final parsedTimestamp = DateTime.tryParse(lastConnectedAt);
    if (parsedTimestamp == null) {
      return null;
    }
    try {
      return RememberedDevice(
        connectionId: connectionId,
        physicalMacAddress: physicalMacAddress as String?,
        displayName: displayName,
        lastConnectedAt: parsedTimestamp,
      );
    } on FormatException {
      return null;
    }
  }

  List<RememberedDevice> _normalizeRecords(Iterable<RememberedDevice> records) {
    final ordered = records.toList()
      ..sort(
        (left, right) => right.lastConnectedAt.compareTo(left.lastConnectedAt),
      );
    final unique = <RememberedDevice>[];
    for (final record in ordered) {
      if (unique.any((item) => _isSameDevice(item, record))) {
        continue;
      }
      unique.add(record);
      if (unique.length == _maximumRecords) {
        break;
      }
    }
    return List.unmodifiable(unique);
  }

  bool _isSameDevice(RememberedDevice left, RememberedDevice right) {
    return _isSameDeviceValues(
      left,
      connectionId: right.connectionId,
      physicalMacAddress: right.physicalMacAddress,
    );
  }

  bool _isSameDeviceValues(
    RememberedDevice record, {
    required String connectionId,
    required String? physicalMacAddress,
  }) {
    if (record.physicalMacAddress != null && physicalMacAddress != null) {
      return record.physicalMacAddress == physicalMacAddress;
    }
    return record.connectionId == connectionId;
  }

  bool _hasSameSerializedValue(
    String storedValue,
    List<RememberedDevice> records,
  ) {
    try {
      return jsonEncode(_encode(records)) ==
          jsonEncode(jsonDecode(storedValue));
    } on FormatException {
      return false;
    }
  }

  Future<void> _write(
    DeviceConnectionHistoryPreferences preferences,
    List<RememberedDevice> records,
  ) async {
    if (records.isEmpty) {
      await _removeMalformedValue(preferences);
      return;
    }
    final persisted = await preferences.setString(
      _storageKey,
      jsonEncode(_encode(records)),
    );
    if (!persisted) {
      throw const DeviceConnectionHistoryStorageException();
    }
  }

  Future<void> _removeMalformedValue(
    DeviceConnectionHistoryPreferences preferences,
  ) async {
    final removed = await preferences.remove(_storageKey);
    if (!removed) {
      throw const DeviceConnectionHistoryStorageException();
    }
  }

  List<Map<String, String>> _encode(Iterable<RememberedDevice> records) {
    final encoded = <Map<String, String>>[];
    for (final record in records) {
      final values = <String, String>{
        'connectionId': record.connectionId,
        'displayName': record.displayName,
        'lastConnectedAt': record.lastConnectedAt.toUtc().toIso8601String(),
      };
      final physicalMacAddress = record.physicalMacAddress;
      if (physicalMacAddress != null) {
        values['physicalMacAddress'] = physicalMacAddress;
      }
      encoded.add(values);
    }
    return encoded;
  }
}

class _SharedPreferencesDeviceConnectionHistoryPreferences
    implements DeviceConnectionHistoryPreferences {
  const _SharedPreferencesDeviceConnectionHistoryPreferences(this._preferences);

  final SharedPreferences _preferences;

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  Future<bool> remove(String key) => _preferences.remove(key);

  @override
  Future<bool> setString(String key, String value) {
    return _preferences.setString(key, value);
  }
}
