import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/features/device_session/application/session_controller.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_ble_transport.dart';

void main() {
  test(
    'does not become observable until subscribe and initial read both succeed',
    () async {
      final transport = FakeBleTransport.withGattReadyProfile();
      final controller = SessionController(
        transport,
        transport.profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      transport.emitSubscriptionBytes(FakeBleTransport.validBatteryFrame);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, isNot(SessionPhase.observable));
      controller.completeInitialRead(FakeBleTransport.validBatteryFrame);
      expect(controller.state.phase, SessionPhase.observable);
    },
  );

  test(
    'missing UUID profile reports access block instead of attempting a read',
    () async {
      final transport = FakeBleTransport();
      final controller = SessionController(
        transport,
        DeviceProfile.empty(),
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);

      expect(controller.state.failure!.kind.name, 'access');
      expect(transport.discoveryRequests, isEmpty);
    },
  );

  test(
    'invalid initial data stays unverifiable and never opens observation',
    () async {
      final transport = FakeBleTransport.withGattReadyProfile();
      final controller = SessionController(
        transport,
        transport.profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      controller.completeInitialRead(const [
        0xED,
        0x03,
        0x00,
        0x91,
        0x00,
        0x00,
      ]);

      expect(controller.state.phase, SessionPhase.initialSnapshotRead);
      expect(controller.state.failure, isNotNull);
    },
  );
}
