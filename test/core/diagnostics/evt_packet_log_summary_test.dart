import 'package:aipin/core/diagnostics/diagnostic_sanitizer.dart';
import 'package:aipin/core/diagnostics/evt_packet_log_summary.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final codec = EvtProtocolCodec();

  test('retains fixed-shape control frame bytes for persisted diagnostics', () {
    final summary = EvtPacketLogSummary.fromWireBytes(
      codec.encodeRequest(0x07, const [0x01]),
    );

    expect(summary.command, '0x07');
    expect(summary.contentLength, 1);
    expect(summary.frameSummary, 'evt_control cmd=0x07 content=01');
    expect(summary.wireSummary, contains('ED 04 00 07 01'));

    final sanitized = const DiagnosticSanitizer().sanitize(
      scope: 'CMD',
      fields: summary.fields,
    );
    expect(sanitized['frame_summary'], summary.frameSummary);
    expect(sanitized['wire_summary'], summary.wireSummary);
    expect(sanitized['command'], '0x07');
  });

  test(
    'masks only the V1 security code while retaining authentication packet shape',
    () {
      final authenticationRequest = EvtPacketLogSummary.fromWireBytes(
        codec.encodeRequest(0x09, const [
          0x02,
          0xDE,
          0xAD,
          0xBE,
          0xEF,
          0xFA,
          0xCE,
        ]),
      );
      final authenticationResponse = EvtPacketLogSummary.fromWireBytes(
        codec.encodeRequest(0x89, const [0x01]),
      );
      final deviceInfo = EvtPacketLogSummary.fromWireBytes(
        codec.encodeRequest(0x81, const [0x41, 0x49, 0x50, 0x49, 0x4E]),
      );
      final fileData = EvtPacketLogSummary.fromWireBytes(
        codec.encodeRequest(0x23, const [0, 0, 0, 0, 2, 0, 0xAA, 0xBB]),
      );

      expect(
        authenticationRequest.frameSummary,
        'evt_authentication cmd=0x09 action=0x02 security_code=redacted',
      );
      expect(
        authenticationRequest.wireSummary,
        'evt_authentication cmd=0x09 action=0x02 '
        'wire=ED 0A 00 09 02 ** ** ** ** ** ** DE 3C',
      );
      final sanitizedAuthentication = const DiagnosticSanitizer().sanitize(
        scope: 'CMD',
        fields: authenticationRequest.fields,
      );
      expect(
        sanitizedAuthentication['frame_summary'],
        authenticationRequest.frameSummary,
      );
      expect(
        sanitizedAuthentication['wire_summary'],
        authenticationRequest.wireSummary,
      );
      expect(
        authenticationResponse.frameSummary,
        'evt_control cmd=0x89 content=01',
      );
      expect(authenticationResponse.wireSummary, contains('ED 04 00 89 01'));
      expect(
        const DiagnosticSanitizer().sanitize(
          scope: 'CMD',
          fields: authenticationResponse.fields,
        )['wire_summary'],
        authenticationResponse.wireSummary,
      );
      expect(deviceInfo.frameSummary, 'evt_sensitive_content_omitted');
      expect(fileData.frameSummary, 'evt_sensitive_content_omitted');

      final rendered = <String>[
        authenticationRequest.frameSummary,
        authenticationRequest.wireSummary,
        deviceInfo.frameSummary,
        fileData.wireSummary,
      ].join(' ');
      expect(rendered, isNot(contains('DE AD BE EF FA CE')));
      expect(rendered, isNot(contains('41 49 50 49 4E')));
      expect(rendered, isNot(contains('AA BB')));
    },
  );

  test('sanitizer rejects raw packet values and forged summary strings', () {
    final fields = const DiagnosticSanitizer().sanitize(
      scope: 'CMD',
      fields: const <String, Object?>{
        'request_bytes': <int>[0xED, 0x04, 0, 0x07, 0x01, 0, 0],
        'response_bytes': <int>[0xED, 0x04, 0, 0x87, 0x01, 0, 0],
        'frame_summary': 'evt_control cmd=0x09 content=00',
        'wire_summary': 'evt_control cmd=0x09 wire=ED 04 00 09 00 00 00',
      },
    );

    expect(fields, isEmpty);
  });

  test('sanitizer retains only internal missing-endpoint descriptors', () {
    const sanitizer = DiagnosticSanitizer();

    expect(
      sanitizer.sanitize(
        scope: 'SESSION',
        fields: const <String, Object?>{
          'missing_endpoints': 'fa10Fa11.indicate,ff10Ff13.notify',
        },
      ),
      <String, Object?>{
        'missing_endpoints': 'fa10Fa11.indicate,ff10Ff13.notify',
      },
    );
    expect(
      sanitizer.sanitize(
        scope: 'SESSION',
        fields: const <String, Object?>{'missing_endpoints': 'zz10Zz99.read'},
      ),
      isEmpty,
    );
  });
}
