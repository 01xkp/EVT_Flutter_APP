import 'package:aipin/core/ble/ble_models.dart';

/// The V1.5 subset that is intentionally enabled in the EVT build.
///
/// Only the commands and endpoints listed here participate in connection,
/// subscription, and UI flows. Keeping the boundary in one place prevents a
/// newly discovered GATT characteristic from becoming an EVT capability.
abstract final class EvtProtocolContract {
  static const protocolVersion = 3;
  static const legacySecurityCodeBytes = 6;

  static const businessCommands = <int>{
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

  /// EVT subscribes only to declared response characteristics that can emit an
  /// indication or notification.
  static const subscriptionEndpoints = <BleLogicalEndpoint>{
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
  };

  /// Mandatory CCC registrations issued after GATT discovery and before the
  /// V1 `0x09` security request. Keeping the order explicit makes the
  /// over-the-air setup trace deterministic for EVT joint testing.
  static const requiredSubscriptionOrder = <BleLogicalEndpoint>[
    BleLogicalEndpoint.fa10Fa19,
    BleLogicalEndpoint.fa10Fa11,
    BleLogicalEndpoint.fa10Fa12,
    BleLogicalEndpoint.fa10Fa15,
    BleLogicalEndpoint.fa10Fa16,
    BleLogicalEndpoint.fa10Fa17,
    BleLogicalEndpoint.fb10Fb11,
    BleLogicalEndpoint.ff10Ff12,
    BleLogicalEndpoint.ff10Ff13,
  ];

  /// `FF11 / 0x21` only provides a compatibility file-count summary. The
  /// regular file list on `FF12 / 0x22` is the required EVT path.
  static const optionalSubscriptionOrder = <BleLogicalEndpoint>[
    BleLogicalEndpoint.ff10Ff11,
  ];

  static bool allowsBusinessCommand(int command) =>
      businessCommands.contains(command);

  static void requireBusinessCommand(int command) {
    if (!allowsBusinessCommand(command)) {
      throw EvtProtocolUnavailableException(
        'EVT 阶段未开放设备命令 0x${command.toRadixString(16).padLeft(2, '0').toUpperCase()}。',
      );
    }
  }

  static void rejectUnavailableCapability(String capability) {
    throw EvtProtocolUnavailableException('EVT 阶段未开放$capability。');
  }
}

class EvtProtocolUnavailableException implements Exception {
  const EvtProtocolUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
