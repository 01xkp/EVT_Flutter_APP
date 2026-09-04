import 'package:aipin/core/diagnostics/diagnostic_event.dart';
import 'package:aipin/core/diagnostics/diagnostic_install_identity.dart';
import 'package:aipin/core/diagnostics/diagnostic_sanitizer.dart';
import 'package:aipin/core/diagnostics/diagnostic_trace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
}
