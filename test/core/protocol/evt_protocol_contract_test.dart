import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/protocol/evt_protocol_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('locks the V1.6 DVT command and endpoint allowlists', () {
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
      0x26,
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
            command == 0x23 ||
            command == 0x26,
      );
    }

    expect(
      EvtProtocolContract.subscriptionEndpoints,
      unorderedEquals(<BleLogicalEndpoint>{
        BleLogicalEndpoint.fa10Fa11,
        BleLogicalEndpoint.fa10Fa12,
        BleLogicalEndpoint.fa10Fa15,
        BleLogicalEndpoint.fa10Fa16,
        BleLogicalEndpoint.fa10Fa17,
        BleLogicalEndpoint.fa10Fa19,
        BleLogicalEndpoint.fb10Fb11,
        BleLogicalEndpoint.ff10Ff11,
        BleLogicalEndpoint.ff10Ff12,
        BleLogicalEndpoint.ff10Ff13,
        BleLogicalEndpoint.ff10Ff16,
      }),
    );
    expect(
      EvtProtocolContract.requiredSubscriptionOrder,
      isNot(contains(BleLogicalEndpoint.ff10Ff11)),
    );
    expect(
      EvtProtocolContract.requiredSubscriptionOrder.toSet(),
      unorderedEquals(
        EvtProtocolContract.subscriptionEndpoints.where(
          (endpoint) => endpoint != BleLogicalEndpoint.ff10Ff11,
        ),
      ),
    );
    expect(EvtProtocolContract.optionalSubscriptionOrder, <BleLogicalEndpoint>[
      BleLogicalEndpoint.ff10Ff11,
    ]);
    expect(
      EvtProtocolContract.optionalDvtValidationEndpoints,
      <BleLogicalEndpoint>[
        BleLogicalEndpoint.fa10Fa18,
        BleLogicalEndpoint.wqota2001,
        BleLogicalEndpoint.wqota2002,
      ],
    );
    expect(
      EvtProtocolContract.requiredSubscriptionOrder,
      isNot(contains(BleLogicalEndpoint.fa10Fa18)),
    );
    expect(
      EvtProtocolContract.requiredSubscriptionOrder,
      isNot(contains(BleLogicalEndpoint.wqota2001)),
    );
    expect(
      EvtProtocolContract.requiredSubscriptionOrder,
      isNot(contains(BleLogicalEndpoint.wqota2002)),
    );
  });
}
