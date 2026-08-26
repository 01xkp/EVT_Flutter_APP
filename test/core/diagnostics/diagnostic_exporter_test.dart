import 'package:aipin/core/diagnostics/diagnostic_exporter.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/device_fixtures.dart';

void main() {
  test(
    'exporter includes failure kind, message, and last valid snapshot time',
    () {
      final output = DiagnosticExporter().format(
        failure: EvtFailure.protocol(message: 'CRC 校验失败'),
        lastSnapshot: snapshot(observedAt: DateTime(2026, 8, 21, 10, 32)),
      );

      expect(output, contains('protocol'));
      expect(output, contains('CRC 校验失败'));
      expect(output, contains('2026-08-21T10:32:00.000'));
    },
  );
}
