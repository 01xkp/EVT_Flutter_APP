import 'package:aipin/core/diagnostics/diagnostic_exporter.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/device_fixtures.dart';

void main() {
  test('exporter emits sanitized structured failure details', () {
    final output = DiagnosticExporter().format(
      failure: EvtFailure.protocol(message: 'CRC 校验失败'),
      lastSnapshot: snapshot(observedAt: DateTime(2026, 8, 21, 10, 32)),
    );

    expect(output, contains('"error_type": "protocol"'));
    expect(output, isNot(contains('CRC 校验失败')));
    expect(output, contains('2026-08-21T10:32:00.000'));
  });
}
