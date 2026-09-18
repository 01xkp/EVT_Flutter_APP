import 'package:aipin/core/diagnostics/diagnostic_event.dart';
import 'package:aipin/core/diagnostics/diagnostic_install_identity.dart';
import 'package:aipin/core/diagnostics/diagnostic_sanitizer.dart';
import 'package:aipin/core/diagnostics/diagnostic_trace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('retains safe EVT unbind preflight diagnostics', () {
    const sanitizer = DiagnosticSanitizer();

    final fields = sanitizer.sanitize(
      scope: 'SESSION',
      fields: const <String, Object?>{
        'check': 'sync_state',
        'checks': <String>[
          'observable_session',
          'record_state',
          'sync_state',
          'first_file_page',
        ],
        'record_status': 0,
        'sync_state': 0,
        'file_count_on_first_page': 0,
      },
    );

    expect(fields, <String, Object?>{
      'check': 'sync_state',
      'checks': <Object?>[
        'observable_session',
        'record_state',
        'sync_state',
        'first_file_page',
      ],
      'file_count_on_first_page': 0,
      'record_status': 0,
      'sync_state': 0,
    });
    expect(sanitizer.normalizeStage('preflight'), 'preflight');
  });

  test('drops sensitive reason content while retaining fixed explanations', () {
    const sanitizer = DiagnosticSanitizer();
    const normalReason = '【蓝牙连接】已调用系统 GATT 连接，等待连接状态回调';
    const fixedSecurityCodeExplanation =
        '【解绑预检】设备尚未完成认证并进入可用状态，未打开安全码输入，也未发送 Action=2';
    const fixedPreflightExplanation =
        '【解绑预检】设备正在录音或已暂停录音，请先结束录音后再解绑。 '
        '未打开安全码输入，也未发送 Action=2';

    for (final entry in <String, String>{
      'carriage return': '诊断文本\r不应保留',
      'line feed': '诊断文本\n不应保留',
      'pipe delimiter': '诊断文本|不应保留',
      'security code': '安全码=123456',
      'password': 'Password: do-not-log',
      'PIN': 'PIN码：123456',
      'token': 'accessToken=do-not-log',
      'API key': 'API Key=do-not-log',
      'private key': 'private_key=do-not-log',
      'Chinese private key': '私钥：do-not-log',
      'file URI': 'file:///data/user/0/aipin/log.txt',
      'content URI': 'content://media/external/files/1',
      'Unix path': '/data/user/0/aipin/log.txt',
      'Windows path': r'C:\Users\Administrator\evt.log',
      'colon MAC address': 'AA:BB:CC:DD:EE:FF',
      'hyphen MAC address': 'AA-BB-CC-DD-EE-FF',
      'UUID': '550e8400-e29b-41d4-a716-446655440000',
      'continuous hex': 'ED0A0009003030303030',
      'spaced hex': 'ED 0A 00 09 00 30',
    }.entries) {
      expect(
        sanitizer.sanitize(
          scope: 'AUTH',
          fields: <String, Object?>{'reason': entry.value, 'safe': '正常诊断字段'},
        ),
        <String, Object?>{'safe': '正常诊断字段'},
        reason: entry.key,
      );
    }

    expect(
      sanitizer.sanitize(
        scope: 'BLE',
        fields: const <String, Object?>{
          'reason': normalReason,
          'safe': 'token status is a non-reason field',
        },
      ),
      const <String, Object?>{
        'reason': normalReason,
        'safe': 'token status is a non-reason field',
      },
    );
    expect(
      sanitizer.sanitize(
        scope: 'SESSION',
        fields: const <String, Object?>{'reason': fixedSecurityCodeExplanation},
      ),
      const <String, Object?>{'reason': fixedSecurityCodeExplanation},
    );
    expect(
      sanitizer.sanitize(
        scope: 'SESSION',
        fields: const <String, Object?>{'reason': fixedPreflightExplanation},
      ),
      const <String, Object?>{'reason': fixedPreflightExplanation},
    );
  });

  test('retains playback and pre-authentication dashboard stages', () {
    const sanitizer = DiagnosticSanitizer();

    final playback = DiagnosticEvent(
      timestamp: DateTime.utc(2026, 9, 17),
      level: DiagnosticLevel.info,
      scope: 'AUDIO',
      operation: 'audio_playback',
      stage: 'playback',
      event: 'audio_load_completed',
      result: 'success',
      fields: const <String, Object?>{'duration_ms': 1200},
    );
    final preAuthentication = DiagnosticEvent(
      timestamp: DateTime.utc(2026, 9, 17),
      level: DiagnosticLevel.info,
      scope: 'SESSION',
      operation: 'device_connect',
      stage: 'pre_authentication',
      event: 'pre_authentication_device_info_requested',
      result: 'pending',
    );

    expect(sanitizer.normalizeOperation('audio_playback'), 'audio_playback');
    expect(sanitizer.normalizeStage('playback'), 'playback');
    expect(
      sanitizer.normalizeStage('pre_authentication'),
      'pre_authentication',
    );
    expect(
      playback.formatLine(),
      contains('AUDIO | - | audio_playback | playback | audio_load_completed'),
    );
    expect(playback.chineseLogPrefix, contains('阶段：本地播放'));
    expect(
      preAuthentication.formatLine(),
      contains(
        'SESSION | - | device_connect | pre_authentication | '
        'pre_authentication_device_info_requested',
      ),
    );
    expect(preAuthentication.chineseLogPrefix, contains('阶段：预认证读取'));
  });

  test('retains safe reconnect and BLE discovery diagnostics', () {
    const sanitizer = DiagnosticSanitizer();

    final reconnectFields = sanitizer.sanitize(
      scope: 'RECONNECT',
      fields: const <String, Object?>{
        'attempt': 2,
        'phase': 'waiting_to_retry',
        'failure_category': 'connect_rejected',
        'cycle': 4,
      },
    );
    final discoveryFields = sanitizer.sanitize(
      scope: 'BLE',
      fields: const <String, Object?>{
        'service_count': 3,
        'characteristic_count': 11,
        'services': 'must-not-be-retained',
      },
    );
    final reconnectEvent = DiagnosticEvent(
      timestamp: DateTime.utc(2026, 9, 7),
      level: DiagnosticLevel.info,
      scope: 'RECONNECT',
      operation: 'device_reconnect',
      stage: 'waiting_to_retry',
      event: 'reconnect_attempt_failed',
      fields: reconnectFields,
    );

    expect(reconnectFields, <String, Object?>{
      'attempt': 2,
      'cycle': 4,
      'failure_category': 'connect_rejected',
      'phase': 'waiting_to_retry',
    });
    expect(discoveryFields, <String, Object?>{
      'characteristic_count': 11,
      'service_count': 3,
    });
    expect(
      reconnectEvent.formatLine(),
      contains('RECONNECT | - | device_reconnect | waiting_to_retry'),
    );
  });

  test('retains complete packet hex only for Debug BLE and CMD logs', () {
    const rawPacket = 'ED 0A 00 09 00 30 30 30 30 30 30 DF 91';
    const debugSanitizer = DiagnosticSanitizer(allowDebugRawPacketHex: true);
    const releaseSanitizer = DiagnosticSanitizer(allowDebugRawPacketHex: false);

    expect(
      debugSanitizer.sanitize(
        scope: 'BLE',
        fields: const {'raw_packet_hex': rawPacket},
      ),
      const {'raw_packet_hex': rawPacket},
    );
    expect(
      debugSanitizer.sanitize(
        scope: 'CMD',
        fields: const {'raw_packet_hex': rawPacket},
      ),
      const {'raw_packet_hex': rawPacket},
    );
    expect(
      releaseSanitizer.sanitize(
        scope: 'BLE',
        fields: const {'raw_packet_hex': rawPacket},
      ),
      isEmpty,
    );
    expect(
      debugSanitizer.sanitize(
        scope: 'AUTH',
        fields: const {'raw_packet_hex': rawPacket},
      ),
      isEmpty,
    );
    expect(
      debugSanitizer.sanitize(
        scope: 'BLE',
        fields: const {'raw_packet_hex': 'ED 0A raw data'},
      ),
      isEmpty,
    );
  });

  test(
    'recursively removes raw diagnostic data while retaining safe fields',
    () {
      const ticket = 'ticket-source-literal';
      const proof = 'proof-source-literal';
      const nonce = 'nonce-source-literal';
      const token = 'token-source-literal';
      const authorization = 'authorization-source-literal';
      const url = 'https://example.invalid/debug?query=source-literal';
      const payload = 'payload-source-literal';
      const audio = 'audio-source-literal';
      const firmware = 'firmware-source-literal';
      const filename = 'filename-source-literal';
      const path = 'C:/private/path-source-literal';
      const nameSlot = 'name-slot-source-literal';
      const rawError = 'error-source-literal';
      const deviceId = 'AA:BB:CC:DD:EE:FF';
      final sanitizer = DiagnosticSanitizer();

      final fields = sanitizer.sanitize(
        scope: 'AUTH',
        fields: <String, Object?>{
          'command': '0x09',
          'action': '0x10',
          'offset': 128,
          'length': 64,
          'status': 'accepted',
          'ticket': ticket,
          'nested': <String, Object?>{
            'proof': proof,
            'nonce': nonce,
            'token': token,
            'authorization': authorization,
            'url': url,
            'raw_payload': payload,
            'raw_payload_bytes': <int>[1, 2, 3],
            'audio_data': audio,
            'audio_bytes': <int>[4, 5, 6],
            'firmware_data': firmware,
            'firmware_bytes': <int>[7, 8, 9],
            'filename': filename,
            'path': path,
            'name_slot': nameSlot,
            'error': rawError,
            'device_id': deviceId,
            'device': deviceId,
            'safe': <Object?>[
              'accepted',
              <String, Object?>{'length': 3},
            ],
          },
        },
      );

      expect(fields['command'], '0x09');
      expect(fields['action'], '0x10');
      expect(fields['offset'], 128);
      expect(fields['length'], 64);
      expect(fields['status'], 'accepted');
      expect(fields['nested'], <String, Object?>{
        'safe': <Object?>[
          'accepted',
          <String, Object?>{'length': 3},
        ],
      });
    },
  );

  test(
    'retains fixed EVT progress state without widening identity retention',
    () {
      final fields = const DiagnosticSanitizer().sanitize(
        scope: 'SESSION',
        fields: const <String, Object?>{
          'authentication_ready': true,
          'automatic': false,
          'connection_attempt': 2,
          'current_operation': 7,
          'duration_code': 3,
          'duration_seconds': 180,
          'free_mb': 512,
          'gatt_ready': true,
          'granted': true,
          'has_active_or_connecting_session': true,
          'is_foreground': true,
          'ios_ccc_mode_conflict_count': 1,
          'mtu': 247,
          'onboarding_complete': true,
          'onboarding_loaded': true,
          'permissions': <String>['status', 'configuration'],
          'reconnect_paused_for_background': false,
          'record_mode': 1,
          'record_type': 2,
          'reported_write_payload': 244,
          'total_mb': 1024,
          'device_id': 'AA:BB:CC:DD:EE:FF',
          'payload': <int>[0xED, 0x04, 0x00, 0x07],
        },
      );

      expect(fields, <String, Object?>{
        'authentication_ready': true,
        'automatic': false,
        'connection_attempt': 2,
        'current_operation': 7,
        'duration_code': 3,
        'duration_seconds': 180,
        'free_mb': 512,
        'gatt_ready': true,
        'granted': true,
        'has_active_or_connecting_session': true,
        'is_foreground': true,
        'ios_ccc_mode_conflict_count': 1,
        'mtu': 247,
        'onboarding_complete': true,
        'onboarding_loaded': true,
        'permissions': <Object?>['status', 'configuration'],
        'reconnect_paused_for_background': false,
        'record_mode': 1,
        'record_type': 2,
        'reported_write_payload': 244,
        'total_mb': 1024,
      });
    },
  );

  test(
    'device reference is stable across install identity reinitialization',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final first = await DiagnosticInstallIdentity.loadOrCreate();
      final firstReference = first.deviceReference('AA:BB:CC:DD:EE:FF');

      final second = await DiagnosticInstallIdentity.loadOrCreate();

      expect(second.deviceReference('AA:BB:CC:DD:EE:FF'), firstReference);
      expect(firstReference, isNot(contains('AA:BB:CC:DD:EE:FF')));
      expect(firstReference, matches(RegExp(r'^[a-f0-9]{12}$')));
    },
  );

  test(
    'event line has stable structured order without blocked source values',
    () {
      const blocked = <String>[
        'ticket-source-literal',
        'proof-source-literal',
        'nonce-source-literal',
        'token-source-literal',
        'authorization-source-literal',
        'https://example.invalid/debug?query=source-literal',
        'payload-source-literal',
        'audio-source-literal',
        'firmware-source-literal',
        'filename-source-literal',
        'C:/private/path-source-literal',
        'name-slot-source-literal',
        'error-source-literal',
        'AA:BB:CC:DD:EE:FF',
      ];
      final sanitizer = DiagnosticSanitizer();
      final fields = sanitizer.sanitize(
        scope: 'AUTH',
        fields: <String, Object?>{
          'command': '0x09',
          'ticket': blocked.first,
          'nested': <String, Object?>{
            'proof': blocked[1],
            'url': blocked[5],
            'device_id': blocked.last,
          },
        },
      );
      final trace = DiagnosticTrace.start(
        operation: 'device_bind',
        origin: 'UI',
        deviceReference: 'a1b2c3d4e5f6',
        traceId: '8fa2c1',
        startedAt: DateTime.utc(2026, 9, 4, 12, 10),
      );
      final line = DiagnosticEvent(
        timestamp: DateTime.utc(2026, 9, 4, 12, 10, 3, 666),
        level: DiagnosticLevel.info,
        scope: 'AUTH',
        trace: trace,
        stage: 'challenge',
        event: 'command_write_started',
        result: 'pending',
        elapsed: const Duration(milliseconds: 92),
        fields: fields,
      ).formatLine();

      expect(
        line,
        '【AIPIN联调】【认证】【信息】【阶段：认证挑战】【动作：命令写入开始】 '
        '2026-09-04T12:10:03.666Z | INFO | AUTH | 8fa2c1 | '
        'device_bind | challenge | command_write_started | pending | 92 | '
        'command=0x09',
      );
      for (final value in blocked) {
        expect(line, isNot(contains(value)));
      }
    },
  );

  test('event metadata slots never render untrusted source values', () {
    const scope = 'scope-token-source-literal';
    const traceId = 'trace-ticket-source-literal';
    const operation = 'operation-proof-source-literal';
    const stage = 'https://example.invalid/stage?query=source-literal';
    const event = 'event-nonce-source-literal';
    const result = 'AA:BB:CC:DD:EE:FF';
    final diagnostic = DiagnosticEvent(
      timestamp: DateTime.utc(2026, 9, 4),
      level: DiagnosticLevel.error,
      scope: scope,
      trace: DiagnosticTrace.start(
        operation: operation,
        origin: 'UI',
        traceId: traceId,
      ),
      stage: stage,
      event: event,
      result: result,
    );
    final line = diagnostic.formatLine();

    expect(
      line,
      contains(' | ERROR | APP | - | - | - | unknown_event | - | -'),
    );
    expect(diagnostic.trace?.traceId, '-');
    expect(diagnostic.trace?.operation, '-');
    expect(diagnostic.trace?.deviceReference, isNull);
    for (final value in <String>[
      scope,
      traceId,
      operation,
      stage,
      event,
      result,
    ]) {
      expect(line, isNot(contains(value)));
    }
  });

  test('recursively drops unknown nested keys and device identity values', () {
    final fields = const DiagnosticSanitizer().sanitize(
      scope: 'AUTH',
      fields: <String, Object?>{
        'nested': <String, Object?>{
          'serial': 'serial-source-literal',
          'device_name': 'device-name-source-literal',
          'identifier': '550e8400-e29b-41d4-a716-446655440000',
          'safe': <String, Object?>{'length': 3},
        },
      },
    );

    expect(fields, <String, Object?>{
      'nested': <String, Object?>{
        'safe': <String, Object?>{'length': 3},
      },
    });
  });

  test('does not persist device API host values', () {
    final fields = const DiagnosticSanitizer().sanitize(
      scope: 'DEVICE_API',
      fields: const <String, Object?>{
        'host': 'api.example.test',
        'http_status': 200,
      },
    );

    expect(fields, <String, Object?>{'http_status': 200});
  });

  test('preserves safe current and generated semantic event identifiers', () {
    const cases = <String, String>{
      'service discovery start': 'service_discovery_start',
      'service discovery success': 'service_discovery_success',
      'service discovery failure': 'service_discovery_failure',
      'write start': 'write_start',
      'write success': 'write_success',
      'write failure': 'write_failure',
      'write without response start': 'write_without_response_start',
      'write without response success': 'write_without_response_success',
      'write without response failure': 'write_without_response_failure',
      'initial read decode failure': 'initial_read_decode_failure',
      'initial read success': 'initial_read_success',
      'session observable': 'session_observable',
      'device status load failure': 'device_status_load_failed',
      'device battery load failure': 'device_battery_load_failed',
      'device privacy duration load failure':
          'device_privacy_duration_load_failed',
      'device configuration time load failure':
          'device_configuration_time_load_failed',
      'device storage load failure': 'device_storage_load_failed',
      'device file count load failure': 'device_file_count_load_failed',
    };
    const sanitizer = DiagnosticSanitizer();

    for (final entry in cases.entries) {
      expect(
        sanitizer.normalizeEvent(entry.value),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('rejects unsafe event identifiers', () {
    const cases = <String, String>{
      'token fragment': 'access_token_received',
      'secret fragment': 'secret_rotated',
      'authorization fragment': 'authorization_complete',
      'raw payload fragment': 'raw_payload_received',
      'URL': 'https://example.invalid/debug?query=source-literal',
      'whitespace': 'event source literal',
      'device UUID': '550e8400-e29b-41d4-a716-446655440000',
      'device MAC': 'AA:BB:CC:DD:EE:FF',
    };
    const sanitizer = DiagnosticSanitizer();

    for (final entry in cases.entries) {
      expect(
        sanitizer.normalizeEvent(entry.value),
        'unknown_event',
        reason: entry.key,
      );
    }
  });

  test('rejects compact UUID segments embedded in event identifiers', () {
    const event = 'device_550e8400e29b41d4a716446655440000_connected';

    expect(const DiagnosticSanitizer().normalizeEvent(event), 'unknown_event');
  });

  test('recursively removes UUID-shaped values under allowed nested keys', () {
    const deviceUuid = '550e8400-e29b-41d4-a716-446655440000';
    final fields = const DiagnosticSanitizer().sanitize(
      scope: 'AUTH',
      fields: const <String, Object?>{
        'safe': deviceUuid,
        'nested': <String, Object?>{
          'safe': <Object?>[
            deviceUuid,
            <String, Object?>{'safe': deviceUuid, 'length': 3},
            'accepted',
          ],
        },
      },
    );

    expect(fields, <String, Object?>{
      'nested': <String, Object?>{
        'safe': <Object?>[
          <String, Object?>{'length': 3},
          'accepted',
        ],
      },
    });
  });
}
