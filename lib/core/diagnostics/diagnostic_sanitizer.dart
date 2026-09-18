import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'evt_packet_log_summary.dart';

/// The single redaction boundary for every diagnostic output sink.
class DiagnosticSanitizer {
  const DiagnosticSanitizer({this.allowDebugRawPacketHex = kDebugMode});

  /// Raw packet bytes are available only in a Debug build. Events are
  /// sanitized again before file and viewer output, so the gate lives here.
  final bool allowDebugRawPacketHex;

  static const _safeScopes = <String>{
    'AI',
    'APP',
    'APP_LIFECYCLE',
    'AUDIO',
    'AUTH',
    'BLE',
    'CMD',
    'DEVICE_API',
    'EXPORT',
    'FILE',
    'RECONNECT',
    'SESSION',
    'SESSION_FLOW',
    'STORAGE',
    'UI',
    'DVT_FILE',
    'DVT_ARCHIVE',
    'ARCHIVE',
  };

  static const _safeOperations = <String>{
    'ai_summary',
    'ai_transcription',
    'audio_playback',
    'device_authenticate',
    'device_bind',
    'device_unbind',
    'device_connect',
    'device_file_import',
    'device_ota',
    'device_archive',
    'device_reconnect',
    'device_scan',
    'local_recording',
  };

  static const _safeStages = <String>{
    'archive',
    'cloud_archive',
    'checkpoint',
    'metadata',
    'transfer',
    'verification',
    'local_verification',
    'cloud_upload',
    'device_confirmation',
    'cleanup',
    'pre_authentication',
    'preflight',
    'playback',
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

  static final _rawPacketHexValue = RegExp(
    r'^(?:empty|[0-9A-F]{2}(?: [0-9A-F]{2})*)$',
  );

  // `reason` is the only human-readable diagnostic field. Keep the existing
  // fixed explanations, but reject any free-text value that could carry a
  // credential, identifier, path, URI, or raw protocol bytes.
  static const _knownSafeReasons = <String>{
    'security_code_sheet_cancelled',
    '【解绑预检】设备尚未完成认证并进入可用状态，未打开安全码输入，也未发送 Action=2',
    '【解绑预检】设备空闲、同步状态为空闲且文件列表为空，允许打开安全码输入',
    '【解绑预检】设备处于空闲、未同步文件为空，可以打开安全码输入',
    '【预认证】已收到脱敏设备信息，可据 DeviceCode 取得安全码',
  };

  static const _knownSafeUnbindPreflightMessages = <String>{
    '设备正在录音或已暂停录音，请先结束录音后再解绑。',
    '设备录音状态异常，无法确认可以安全解绑。',
    '设备正在同步或同步状态异常，请完成文件同步后再解绑。',
    '设备仍有未同步录音文件，请先完成文件同步后再解绑。',
    '无法确认设备录音、同步和文件状态，请重新连接后完成文件同步再解绑。',
  };

  static final _unsafeReasonControl = RegExp(r'[\r\n|]');

  static final _unsafeReasonSensitiveName = RegExp(
    r'(?:安全(?:码|代码|密码|口令|密钥)|(?:动态|验证|授权|访问)(?:码|密码|口令|令牌)|'
    r'密码|口令|私钥|密钥|令牌|凭证|'
    r'\b(?:security[\s_-]*code|verification[\s_-]*code|'
    r'pass(?:word|code)?|pwd|pin(?:[\s_-]*(?:code|码))?|'
    r'(?:access[\s_-]*)?token|api[\s_-]*key|private[\s_-]*key|'
    r'(?:client[\s_-]*)?secret(?:[\s_-]*key)?|credential(?:s)?|bearer)(?![a-z]))',
    caseSensitive: false,
  );

  static final _unsafeReasonUri = RegExp(
    r'\b[a-z][a-z0-9+.-]*:(?://|/)',
    caseSensitive: false,
  );

  static final _unsafeReasonUnixPath = RegExp(
    r'(?:^|[\s=:(])(?:/|~/)[^\s/]+(?:/[^\s/]+)*',
  );

  static final _unsafeReasonWindowsPath = RegExp(
    r'(?:^|[^a-z0-9])[a-z]:[\\/]',
    caseSensitive: false,
  );

  static final _unsafeReasonMac = RegExp(
    r'(?:^|[^a-f0-9])(?:[a-f0-9]{2}[:-]){5}[a-f0-9]{2}(?:$|[^a-f0-9])',
    caseSensitive: false,
  );

  static final _unsafeReasonUuid = RegExp(
    r'\{?[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\}?',
    caseSensitive: false,
  );

  static final _unsafeReasonContinuousHex = RegExp(
    r'(?:^|[^a-f0-9])[a-f0-9]{12,}(?:$|[^a-f0-9])',
    caseSensitive: false,
  );

  static final _unsafeReasonSpacedHex = RegExp(
    r'(?:^|[^a-f0-9])(?:[a-f0-9]{2}[ \t]+){5,}[a-f0-9]{2}(?:$|[^a-f0-9])',
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
    'authentication_ready',
    'automatic',
    'bytes',
    'characteristic',
    'characteristic_count',
    'check',
    'checks',
    'critical',
    'command',
    'configured',
    'content_length',
    'crc',
    'crc32',
    'size',
    'size_bytes',
    'file_size_bytes',
    'file_state',
    'device_file_state',
    'listed_size_bytes',
    'session_id',
    'segment_index',
    'expected_size_bytes',
    'expected_crc32',
    'actual_size_bytes',
    'actual_crc32',
    'received_bytes',
    'total_bytes',
    'chunk_bytes',
    'checkpoint_phase',
    'archive_state',
    'discarded_bytes',
    'rejected_frames',
    'duration_ms',
    'elapsed_ms',
    'engine',
    'endpoint_capabilities',
    'event_kind',
    'expected_command',
    'actual_command',
    'authentication_window_ms',
    'code_length',
    'connection_attempt',
    'device_suffix',
    'count',
    'current_operation',
    'duration_code',
    'duration_seconds',
    'error_type',
    'failure_kind',
    'file_count',
    'file_count_on_first_page',
    'foreground_before',
    'free_mb',
    'gatt_cache_refresh_attempted',
    'gatt_cache_refresh_result',
    'gatt_cache_refresh_supported',
    'gatt_ready',
    'granted',
    'gatt_status',
    'granted_permissions',
    'has_active_or_connecting_session',
    'has_name',
    'http_status',
    'is_foreground',
    'ios_ccc_mode_conflict_count',
    'length',
    'method',
    'max_retries',
    'missing_count',
    'missing_endpoints',
    'mtu',
    'operation_name',
    'onboarding_complete',
    'onboarding_loaded',
    'offset',
    'operation',
    'endpoint',
    'percent',
    'platform',
    'phase_from',
    'phase_to',
    'previous_state',
    'permissions',
    'protocol_version',
    'requested_mode',
    'required',
    'reason',
    'reconnect_paused_for_background',
    'record_mode',
    'record_status',
    'record_type',
    'reported_write_payload',
    'required_mtu',
    'result',
    'rssi',
    'safe',
    'service_count',
    'setup_mode',
    'stage',
    'state',
    'status',
    'sync_state',
    'subscription_count',
    'supports_indicate',
    'supports_notify',
    'timeout_ms',
    'total_mb',
    'sub_command',
    'type',
    'variant',
    'window',
    'error_code',
    'file_transfer',
    'last_valid_snapshot_at',
    'last_valid_snapshot_source',
    'nested',
    'occurred_at',
    'raw_packet_hex_omitted',
  };

  static const _scopeAllowed = <String, Set<String>>{
    'AI': {'segment_count', 'text_length'},
    'AUTH': {'grant_bits', 'transaction_hash'},
    'BLE': {
      'instance_id',
      'setup_completed',
      'mtu',
      'rssi',
      'has_name',
      'manufacturer_data_length',
      'manufacturer_prefix',
      'service_uuid_present',
      'name_format_valid',
      'next_action',
      'service_count',
      'characteristic_count',
      'pairing_required',
    },
    'CMD': {
      'wait_id',
      'idle_ms',
      'remaining_ms',
      'response_count',
      // Raw List<int> values remain blocked below. These two fields accept
      // only the fixed EVT summary grammar generated by EvtPacketLogSummary.
      'frame_summary',
      'wire_summary',
      'request_bytes',
      'response_bytes',
    },
    // Host names are transport/configuration data and must never enter the
    // persisted or uploaded diagnostic contract.
    'DEVICE_API': <String>{},
    'FILE': {'chunk_length', 'total_bytes'},
    'RECONNECT': {'phase', 'failure_category', 'cycle'},
    'SESSION': {'mode', 'utc_seconds'},
    'STORAGE': {'file_count'},
  };

  static const _evtLogicalEndpoints = <String>{
    'fa10Fa11',
    'fa10Fa12',
    'fa10Fa15',
    'fa10Fa16',
    'fa10Fa17',
    'fa10Fa18',
    'fa10Fa19',
    'fb10Fb11',
    'ff10Ff11',
    'ff10Ff12',
    'ff10Ff13',
    'ff10Ff16',
    'wqota2001',
    'wqota2002',
  };

  static const _evtEndpointOperations = <String>{
    'read',
    'write',
    'indicate',
    'writeWithoutResponse',
    'notify',
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
      if ((key == 'frame_summary' || key == 'wire_summary') &&
          !EvtPacketLogSummary.isPersistableSummary(key: key, value: value)) {
        return _dropped;
      }
      if (key == 'reason' && _isUnsafeReason(value)) {
        return _dropped;
      }
      if (key == 'device_suffix' && !_isSafeDeviceSuffix(value)) {
        return _dropped;
      }
      if (key == 'raw_packet_hex' && !_rawPacketHexValue.hasMatch(value)) {
        return _dropped;
      }
      if (key == 'missing_endpoints' && !_isSafeMissingEndpoints(value)) {
        return _dropped;
      }
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
    if (key == 'raw_packet_hex') {
      return allowDebugRawPacketHex && (scope == 'BLE' || scope == 'CMD');
    }
    return _commonAllowed.contains(key) ||
        _scopeAllowed[scope]?.contains(key) == true ||
        key == 'nested';
  }

  bool _isSafeDeviceSuffix(String value) =>
      RegExp(r'^\.\.\.[A-Fa-f0-9]{4}$').hasMatch(value);

  bool _isSafeMissingEndpoints(String value) {
    final entries = value.split(',');
    return entries.isNotEmpty &&
        entries.every((entry) {
          final parts = entry.split('.');
          return parts.length == 2 &&
              _evtLogicalEndpoints.contains(parts.first) &&
              _evtEndpointOperations.contains(parts.last);
        });
  }

  bool _isUnsafeReason(String value) {
    if (_isKnownSafeReason(value)) {
      return false;
    }
    return _unsafeReasonControl.hasMatch(value) ||
        _unsafeReasonSensitiveName.hasMatch(value) ||
        _unsafeReasonUri.hasMatch(value) ||
        _unsafeReasonUnixPath.hasMatch(value) ||
        _unsafeReasonWindowsPath.hasMatch(value) ||
        _unsafeReasonMac.hasMatch(value) ||
        _unsafeReasonUuid.hasMatch(value) ||
        _unsafeReasonContinuousHex.hasMatch(value) ||
        _unsafeReasonSpacedHex.hasMatch(value);
  }

  bool _isKnownSafeReason(String value) {
    if (_knownSafeReasons.contains(value)) {
      return true;
    }
    const prefix = '【解绑预检】';
    const suffix = ' 未打开安全码输入，也未发送 Action=2';
    if (!value.startsWith(prefix) || !value.endsWith(suffix)) {
      return false;
    }
    final message = value.substring(
      prefix.length,
      value.length - suffix.length,
    );
    return _knownSafeUnbindPreflightMessages.contains(message);
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
      // This is an integer reported by CoreBluetooth, not a wire payload.
      // It is needed to diagnose whether the negotiated ATT MTU can carry
      // EVT V1.6's largest indication frame.
      'reported_write_payload',
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
