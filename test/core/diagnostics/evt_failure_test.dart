import 'package:evt_ble_app/core/diagnostics/evt_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('protocol failures retain a recoverable diagnostic detail', () {
    final failure = EvtFailure.protocol(
      message: 'CRC 校验失败',
      detail: 'frame=ED0211520000',
    );

    expect(failure.kind, EvtFailureKind.protocol);
    expect(failure.recoverable, isTrue);
    expect(failure.detail, 'frame=ED0211520000');
  });
}
