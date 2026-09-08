import 'dart:collection';

/// The single redaction boundary for every diagnostic output sink.
class DiagnosticSanitizer {
  const DiagnosticSanitizer();

  static const _safeScopes = <String>{
    'AI',
    'APP',
    'AUDIO',
    'AUTH',
    'BLE',
    'CMD',
    'DEVICE_API',
    'EXPORT',
    'FILE',
    'RECONNECT',
    'SESSION',
    'STORAGE',
    'UI',
  };

  static const _safeOperations = <String>{
    'ai_summary',
    'ai_transcription',
    'device_authenticate',
    'device_bind',
    'device_connect',
    'device_file_import',
    'device_reconnect',
    'device_scan',
    'local_recording',
  };

  static const _safeStages = <String>{
    'archive',
    'challenge',
    'connect',
    'download',
    'export',
    'fa19_write',
    'import',
    'initialization',
    'read',
    'request',
    'response',
    'sync',
    'ticket_request',
    'upload',
    'validation',
    'write',
    'idle',
    'scanning',
    'connecting',
    'waiting_to_retry',
    'connected',
    'exhausted',
    'suppressed',
  };

  static const _safeResults = <String>{
    'accepted',
    'cancelled',
    'completed',
    'failed',
    'pending',
    'retrying',
    'succeeded',
    'success',
    'unconfigured',
  };

  static final _eventIdentifier = RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$');

  static const _unsafeEventSegments = <String>{
    'authorization',
    'nonce',
    'payload',
    'proof',
    'secret',
    'token',
  };

  static final _uuidValue = RegExp(
    r'^\{?[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\}?$',
    caseSensitive: false,
  );

  static final _compactUuidValue = RegExp(
    r'^[a-f0-9]{32}$',
    caseSensitive: false,
  );

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
    'critical',
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
    'endpoint',
    'percent',
    'platform',
    'protocol_version',
    'reason',
    'required_mtu',
    'result',
    'safe',
    'stage',
    'state',
    'status',
    'subscription_count',
    'sub_command',
    'type',
    'variant',
    'window',
    'error_type',
    'error_code',
    'failure_kind',
    'last_valid_snapshot_at',
    'last_valid_snapshot_source',
    'nested',
    'occurred_at',
  };

  static const _scopeAllowed = <String, Set<String>>{
    'AI': {'segment_count', 'text_length'},
    'AUTH': {'grant_bits', 'transaction_hash'},
    'BLE': {
      'mtu',
      'rssi',
      'has_name',
      'manufacturer_data_length',
      'manufacturer_prefix',
      'service_uuid_present',
      'name_format_valid',
      'service_count',
      'characteristic_count',
      'pairing_required',
    },
    'CMD': {'request_bytes', 'response_bytes'},
    'DEVICE_API': {'host'},
    'FILE': {'chunk_length', 'total_bytes'},
    'RECONNECT': {'phase', 'failure_category', 'cycle'},
    'SESSION': {'mode', 'utc_seconds'},
    'STORAGE': {'file_count'},
  };

  Map<String, Object?> sanitize({
    required String scope,
    required Map<String, Object?> fields,
  }) {
    try {
      return Map<String, Object?>.unmodifiable(
        _sanitizeMap(scope.toUpperCase(), fields),
      );
    } on Object {
      return const <String, Object?>{};
    }
  }

  Map<String, Object?> _sanitizeMap(
    String scope,
    Map<dynamic, dynamic> source,
  ) {
    final output = SplayTreeMap<String, Object?>();
    for (final entry in source.entries) {
      final key = entry.key.toString();
      if (_isBlockedKey(key) || !_isAllowed(scope, key)) {
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
      final sanitized = _sanitizeMap(scope, value);
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

  String normalizeScope(String value) {
    final normalized = value.toUpperCase();
    return _safeScopes.contains(normalized) ? normalized : 'APP';
  }

  String normalizeTraceId(String? value) {
    if (value == null ||
        !RegExp(r'^[a-f0-9]{6,32}$', caseSensitive: false).hasMatch(value)) {
      return '-';
    }
    return value.toLowerCase();
  }

  String normalizeOperation(String? value) {
    return value != null && _safeOperations.contains(value) ? value : '-';
  }

  String normalizeStage(String? value) {
    return value != null && _safeStages.contains(value) ? value : '-';
  }

  String normalizeEvent(String value) {
    if (!_eventIdentifier.hasMatch(value) || _isUnsafeString(value)) {
      return 'unknown_event';
    }
    final segments = value.split('_');
    return segments.any(
          (segment) =>
              _unsafeEventSegments.contains(segment) ||
              _uuidValue.hasMatch(segment) ||
              _compactUuidValue.hasMatch(segment),
        )
        ? 'unknown_event'
        : value;
  }

  String normalizeResult(String? value) {
    return value != null && _safeResults.contains(value) ? value : '-';
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
        _uuidValue.hasMatch(value) ||
        _compactUuidValue.hasMatch(value) ||
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
