import 'dart:convert';

import 'package:aipin/features/device_session/domain/dvt_pending_archive_manifest.dart';
import 'package:aipin/features/device_session/domain/dvt_pending_archive_manifest_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class DvtPendingArchiveManifestPreferences {
  String? getString(String key);

  Future<bool> setString(String key, String value);

  Future<bool> remove(String key);
}

class DvtPendingArchiveManifestStorageException implements Exception {
  const DvtPendingArchiveManifestStorageException();

  @override
  String toString() => 'dvt_pending_archive_manifest_storage_failure';
}

/// Versioned SharedPreferences storage for verified files awaiting a terminal
/// DVT archive result. The payload contains no absolute local path or cloud
/// credential, only the relative pointer required to re-open the file.
class SharedPreferencesDvtPendingArchiveManifestRepository
    implements DvtPendingArchiveManifestRepository {
  SharedPreferencesDvtPendingArchiveManifestRepository({
    DvtPendingArchiveManifestPreferences? preferences,
  }) {
    _preferences = preferences;
  }

  static const _storageKey = 'dvt.pending_archive_manifests.v1';
  static const _schemaVersion = 1;

  DvtPendingArchiveManifestPreferences? _preferences;
  Future<void> _operationTail = Future<void>.value();

  @override
  Future<List<DvtPendingArchiveManifest>> listForDevice(String deviceId) {
    return _runExclusive(() async {
      final preferences = await _getPreferences();
      final manifests = await _load(preferences);
      return List<DvtPendingArchiveManifest>.unmodifiable(
        manifests.where((manifest) => manifest.checkpoint.deviceId == deviceId),
      );
    });
  }

  @override
  Future<void> remove(String checkpointId) {
    return _runExclusive(() async {
      final preferences = await _getPreferences();
      final manifests = await _load(preferences);
      final remaining = manifests
          .where((manifest) => manifest.checkpoint.id != checkpointId)
          .toList(growable: false);
      if (remaining.length != manifests.length) {
        await _write(preferences, remaining);
      }
    });
  }

  @override
  Future<void> save(DvtPendingArchiveManifest manifest) {
    if (!manifest.isReadyForRestore) {
      throw const FormatException('DVT 待归档清单字段不一致。');
    }
    return _runExclusive(() async {
      final preferences = await _getPreferences();
      final manifests = await _load(preferences);
      final merged = <DvtPendingArchiveManifest>[
        manifest,
        for (final existing in manifests)
          if (existing.checkpoint.id != manifest.checkpoint.id) existing,
      ];
      await _write(preferences, merged);
    });
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) {
    final result = _operationTail.then<T>((_) => operation());
    _operationTail = result.then<void>((_) {}).catchError((_) {});
    return result;
  }

  Future<DvtPendingArchiveManifestPreferences> _getPreferences() async {
    final existing = _preferences;
    if (existing != null) {
      return existing;
    }
    final loaded = _SharedPreferencesDvtPendingArchiveManifestPreferences(
      await SharedPreferences.getInstance(),
    );
    _preferences = loaded;
    return loaded;
  }

  Future<List<DvtPendingArchiveManifest>> _load(
    DvtPendingArchiveManifestPreferences preferences,
  ) async {
    String? raw;
    try {
      raw = preferences.getString(_storageKey);
    } on TypeError {
      await _remove(preferences);
      return const <DvtPendingArchiveManifest>[];
    }
    if (raw == null) {
      return const <DvtPendingArchiveManifest>[];
    }

    final manifests = _decode(raw);
    final normalized = _deduplicate(manifests);
    if (!_hasSameSerializedValue(raw, normalized)) {
      await _write(preferences, normalized);
    }
    return normalized;
  }

  List<DvtPendingArchiveManifest> _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != _schemaVersion) {
        return const <DvtPendingArchiveManifest>[];
      }
      final rows = decoded['items'];
      if (rows is! List) {
        return const <DvtPendingArchiveManifest>[];
      }
      final manifests = <DvtPendingArchiveManifest>[];
      for (final row in rows) {
        final manifest = DvtPendingArchiveManifest.tryFromJson(row);
        if (manifest != null) {
          manifests.add(manifest);
        }
      }
      return manifests;
    } on FormatException {
      return const <DvtPendingArchiveManifest>[];
    } on TypeError {
      return const <DvtPendingArchiveManifest>[];
    }
  }

  List<DvtPendingArchiveManifest> _deduplicate(
    Iterable<DvtPendingArchiveManifest> manifests,
  ) {
    final unique = <String, DvtPendingArchiveManifest>{};
    for (final manifest in manifests) {
      unique[manifest.checkpoint.id] = manifest;
    }
    return List<DvtPendingArchiveManifest>.unmodifiable(unique.values);
  }

  bool _hasSameSerializedValue(
    String raw,
    List<DvtPendingArchiveManifest> manifests,
  ) {
    try {
      return jsonEncode(_encode(manifests)) == jsonEncode(jsonDecode(raw));
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    }
  }

  Map<String, Object?> _encode(Iterable<DvtPendingArchiveManifest> manifests) {
    return <String, Object?>{
      'version': _schemaVersion,
      'items': manifests.map((manifest) => manifest.toJson()).toList(),
    };
  }

  Future<void> _write(
    DvtPendingArchiveManifestPreferences preferences,
    List<DvtPendingArchiveManifest> manifests,
  ) async {
    if (manifests.isEmpty) {
      await _remove(preferences);
      return;
    }
    final persisted = await preferences.setString(
      _storageKey,
      jsonEncode(_encode(manifests)),
    );
    if (!persisted) {
      throw const DvtPendingArchiveManifestStorageException();
    }
  }

  Future<void> _remove(DvtPendingArchiveManifestPreferences preferences) async {
    final removed = await preferences.remove(_storageKey);
    if (!removed) {
      throw const DvtPendingArchiveManifestStorageException();
    }
  }
}

class _SharedPreferencesDvtPendingArchiveManifestPreferences
    implements DvtPendingArchiveManifestPreferences {
  const _SharedPreferencesDvtPendingArchiveManifestPreferences(
    this._preferences,
  );

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
