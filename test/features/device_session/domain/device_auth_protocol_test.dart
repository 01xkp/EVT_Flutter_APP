import 'package:aipin/features/device_session/domain/device_auth_protocol.dart';
import 'package:aipin/features/device_session/domain/ticket_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches the documented AUTH proof vectors', () {
    final material = TicketMaterial(
      ticket: 'TKT-AUTH-V2'.codeUnits,
      proofKey: List<int>.generate(32, (index) => index),
    );
    final appNonce = List<int>.generate(16, (index) => 0x10 + index);
    final deviceNonce = List<int>.generate(16, (index) => 0x20 + index);
    final expectedDeviceProof = <int>[
      0x8A,
      0x2E,
      0x1D,
      0x12,
      0xD9,
      0xAD,
      0x5C,
      0x16,
      0x76,
      0x8B,
      0xF3,
      0xF3,
      0x2F,
      0xF7,
      0x69,
      0xEF,
    ];

    final verified = DeviceAuthProtocol.verifyDeviceProof(
      action: DeviceAuthAction.authenticate,
      transactionId: 0x05060708,
      material: material,
      appNonce: appNonce,
      deviceNonce: deviceNonce,
      deviceProof: expectedDeviceProof,
    );

    expect(verified, isTrue);
    expect(
      DeviceAuthProtocol.createAppProof(
        beginAction: DeviceAuthAction.authenticate,
        confirmAction: DeviceAuthAction.authenticationResult,
        transactionId: 0x05060708,
        material: material,
        appNonce: appNonce,
        deviceNonce: deviceNonce,
        deviceProof: expectedDeviceProof,
      ),
      <int>[
        0xDB,
        0xFB,
        0x23,
        0x4D,
        0x8A,
        0xB2,
        0x30,
        0xBF,
        0xEA,
        0x7B,
        0x70,
        0x30,
        0xEE,
        0xBC,
        0xE8,
        0x8B,
      ],
    );
  });

  test('encodes the AUTH begin data with its exact ticket length', () {
    final data = DeviceAuthProtocol.beginData(
      appNonce: List<int>.generate(16, (index) => index),
      ticket: const [0x41, 0x42],
    );

    expect(data, <int>[
      ...List<int>.generate(16, (index) => index),
      2,
      0,
      0x41,
      0x42,
    ]);
  });

  test('matches the documented CLEAR confirmation proof vector', () {
    final material = TicketMaterial(
      ticket: 'TKT-CLEAR-V2'.codeUnits,
      proofKey: List<int>.generate(32, (index) => index),
    );

    expect(
      DeviceAuthProtocol.createClearConfirmProof(
        transactionId: 0x0A0B0C0D,
        material: material,
        expectedBindingGeneration: 7,
        confirmNonce: List<int>.generate(16, (index) => 0x30 + index),
        clearScope: 0x3F,
      ),
      <int>[
        0xBB,
        0xF9,
        0xFA,
        0xF5,
        0x72,
        0x62,
        0x98,
        0x57,
        0x93,
        0x52,
        0x43,
        0x76,
        0xC5,
        0xB2,
        0xDA,
        0x68,
      ],
    );
  });
}
