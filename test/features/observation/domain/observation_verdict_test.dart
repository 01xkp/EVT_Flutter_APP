import 'package:evt_ble_app/features/observation/domain/observation_verdict.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing device data is unverifiable rather than passed', () {
    expect(
      ObservationVerdict.fromRequiredFields(const {}),
      ObservationVerdict.unverifiable,
    );
  });

  test('all required fields allow a result to be evaluated', () {
    expect(
      ObservationVerdict.fromRequiredFields(const {'batteryPercent': true}),
      ObservationVerdict.passed,
    );
  });
}
