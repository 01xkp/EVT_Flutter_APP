import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/protocol/evt_protocol_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('locks the V1.6 EVT command and endpoint allowlists', () {
    const expectedCommands = <int>{
      0x01,
      0x02,
      0x05,
      0x06,
      0x07,
      0x09,
      0x11,
      0x21,
      0x22,
      0x23,
    };

    expect(
      EvtProtocolContract.businessCommands,
      unorderedEquals(expectedCommands),
    );
    for (var command = 0; command <= 0xFF; command += 1) {
      expect(
        EvtProtocolContract.allowsBusinessCommand(command),
        command == 0x01 ||
            command == 0x02 ||
            command == 0x05 ||
            command == 0x06 ||
            command == 0x07 ||
            command == 0x09 ||
            command == 0x11 ||
            command == 0x21 ||
            command == 0x22 ||
            command == 0x23,
      );
    }

    expect(
      EvtProtocolContract.subscriptionEndpoints,
      unorderedEquals(BleLogicalEndpoint.values),
    );
    expect(
      EvtProtocolContract.requiredSubscriptionOrder,
      isNot(contains(BleLogicalEndpoint.ff10Ff11)),
    );
    expect(
      EvtProtocolContract.requiredSubscriptionOrder.toSet(),
      unorderedEquals(
        BleLogicalEndpoint.values.where(
          (endpoint) => endpoint != BleLogicalEndpoint.ff10Ff11,
        ),
      ),
    );
    expect(EvtProtocolContract.optionalSubscriptionOrder, <BleLogicalEndpoint>[
      BleLogicalEndpoint.ff10Ff11,
    ]);
  });
}
