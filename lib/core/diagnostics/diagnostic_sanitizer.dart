import 'dart:collection';

/// The single redaction boundary for every diagnostic output sink.
class DiagnosticSanitizer {
  const DiagnosticSanitizer();

  static const _blockedFragments = <String>{
    'ticket',
    'proof',
    'nonce',
    'token',
    'secret',
    'authorization',
    'payload',
    'audio',
    'firmware',
    'filename',
    'file_name',
    'name_slot',
    'path',
    'url',
    'query',
    'error',
    'exception',
    'device_id',
    'deviceid',
  };

  static const _commonAllowed = <String>{
    'action',
    'attempt',
    'bytes',
    'characteristic',
    'command',
    'configured',
    'content_length',
    'crc',
    'duration_ms',
    'elapsed_ms',
    'engine',
    'gatt_status',
    'http_status',
    'length',
    'method',
    'offset',
    'operation',
    'percent',
    'reason',
    'result',
    'safe',
    'stage',
    'state',
    'status',
    'sub_command',
    'type',
    'variant',
    'window',
    'error_type',
    'error_code',
    'failure_kind',
    'last_valid_snapshot_at',
    'last_valid_snapshot_source',
    'occurred_at',
  };

  static const _scopeAllowed = <String, Set<String>>{
    'AI': {'segment_count', 'text_length'},
    'AUTH': {'grant_bits', 'transaction_hash'},
    'BLE': {'mtu', 'rssi'},
    'CMD': {'request_bytes', 'response_bytes'},
    'DEVICE_API': {'host'},
    'FILE': {'chunk_length', 'total_bytes'},
    'OTA': {'block_count', 'total_bytes'},
    'STORAGE': {'file_count'},
  };

  Map<String, Object?> sanitize({
    required String scope,
    required Map<String, Object?> fields,
  }) {
    try {
      return Map<String, Object?>.unmodifiable(
        _sanitizeMap(scope.toUpperCase(), fields, isRoot: true),
      );
    } on Object {
      return const <String, Object?>{};
    }
  }

  Map<String, Object?> _sanitizeMap(
    String scope,
    Map<dynamic, dynamic> source, {
    required bool isRoot,
  }) {
    final output = SplayTreeMap<String, Object?>();
    for (final entry in source.entries) {
      final key = entry.key.toString();
      if (_isBlockedKey(key) || (isRoot && !_isAllowed(scope, key))) {
        continue;
      }
      final value = _sanitizeValue(scope, key, entry.value);
      if (value != _dropped) {
        output[key] = value;
      }
    }
    return output;
  }

  Object? _sanitizeValue(String scope, String key, Object? value) {
    if (value == null || value is bool || value is num) {
      return value;
    }
    if (value is String) {
      return _isUnsafeString(value) ? _dropped : value;
    }
    if (value is Uri || value is List<int>) {
      return _dropped;
    }
    if (value is Map) {
      final sanitized = _sanitizeMap(scope, value, isRoot: false);
      return sanitized.isEmpty
          ? _dropped
          : Map<String, Object?>.unmodifiable(sanitized);
    }
    if (value is Iterable) {
      final values = <Object?>[];
      for (final item in value) {
        final safe = _sanitizeValue(scope, key, item);
        if (safe != _dropped) {
          values.add(safe);
        }
      }
      return List<Object?>.unmodifiable(values);
    }
    return _dropped;
  }

  bool _isAllowed(String scope, String key) {
    return _commonAllowed.contains(key) ||
        _scopeAllowed[scope]?.contains(key) == true ||
        key == 'nested';
  }

  bool _isBlockedKey(String key) {
    final normalized = key.toLowerCase();
    if (const <String>{
      'error_type',
      'error_code',
      'gatt_status',
      'http_status',
      'stage',
    }.contains(normalized)) {
      return false;
    }
    if (normalized == 'device' || normalized == 'name') {
      return true;
    }
    return _blockedFragments.any(normalized.contains);
  }

  bool _isUnsafeString(String value) {
    final normalized = value.toLowerCase();
    return normalized.contains('://') ||
        normalized.contains('?') ||
        RegExp(
          r'([a-f0-9]{2}:){5}[a-f0-9]{2}',
          caseSensitive: false,
        ).hasMatch(value) ||
        value.contains('\\') ||
        RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(value);
  }
}

const _DroppedValue _dropped = _DroppedValue();

class _DroppedValue {
  const _DroppedValue();
}
