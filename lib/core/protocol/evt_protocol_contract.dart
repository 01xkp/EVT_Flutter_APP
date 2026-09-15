import 'package:aipin/core/ble/ble_models.dart';

/// The V1.6 subset that is intentionally enabled in the EVT build.
///
/// Only the commands and endpoints listed here participate in connection,
/// subscription, and UI flows. Keeping the boundary in one place prevents a
/// newly discovered GATT characteristic from becoming an EVT capability.
abstract final class EvtProtocolContract {
  /// ProtocolVersion carried by the V1.6 EVT device-information response.
  ///
  /// The admission check is intentionally disabled during the current
  /// hardware integration window, but keeping the value here prevents
  /// call-sites from scattering the magic number.
  static const evtV16ProtocolVersion = 3;

  /// @deprecated Use [evtV16ProtocolVersion].
  @Deprecated('Use EvtProtocolContract.evtV16ProtocolVersion')
  static const protocolVersion = evtV16ProtocolVersion;
  static const legacySecurityCodeBytes = 6;

  /// Largest response in the enabled EVT subset: 0xA3 carries up to 480B
  /// FileData plus FileOffset (4B), DataLength (2B), CMD (1B), CRC (2B).
  /// File lists are at most 424B and device information at most 130B.
  static const maxResponseLengthField = 489;

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

  /// GATT endpoint used by each EVT command that the App writes as a framed
  /// request.  `0x11` is intentionally absent: V1.6 exposes that operation as
  /// a native GATT Read and it must never be sent through the framed write
  /// queue.  Keeping this map next to the command allow-list makes it harder
  /// for a new caller to accidentally write a valid frame to the wrong
  /// characteristic.
  static const writeCommandEndpoints = <int, BleLogicalEndpoint>{
    0x01: BleLogicalEndpoint.fa10Fa11,
    0x02: BleLogicalEndpoint.fa10Fa12,
    0x05: BleLogicalEndpoint.fa10Fa15,
    0x06: BleLogicalEndpoint.fa10Fa16,
    0x07: BleLogicalEndpoint.fa10Fa17,
    0x09: BleLogicalEndpoint.fa10Fa19,
    0x21: BleLogicalEndpoint.ff10Ff11,
    0x22: BleLogicalEndpoint.ff10Ff12,
    0x23: BleLogicalEndpoint.ff10Ff13,
  };

  /// Returns the endpoint for a framed write command, or `null` for commands
  /// that are read-only/otherwise not valid as a write (currently 0x11).
  static BleLogicalEndpoint? writeEndpointForCommand(int command) =>
      writeCommandEndpoints[command];

  /// Validates the V1.6 wire payload before it reaches the native BLE write.
  ///
  /// The codec only checks byte width and frame CRC.  It cannot know that a
  /// particular command has a fixed payload or that a field is an enum, so
  /// those checks belong at the final command-admission boundary.  Throwing
  /// here guarantees malformed requests never reach a real peripheral.
  static void validateWritePayload(int command, List<int> content) {
    _validateByteValues(content);
    switch (command) {
      case 0x01:
      case 0x05:
      case 0x21:
        _requireLength(command, content, 0);
        return;
      case 0x02:
        _requireLength(command, content, 12);
        // V1.6 keeps the existing recording mode and explicitly fixes it to
        // value 1.  The field is not exposed as a user setting, but validating
        // it here prevents a future caller from sending an unsupported mode.
        if (content[6] != 1) {
          _invalid(command, 'RecordMode 当前 EVT 固定为 1。');
        }
        if (content[7] != 1 && content[7] != 2) {
          _invalid(command, 'RecordType 必须为 1 或 2。');
        }
        _requireBoolean(command, content[8], 'Denoise');
        _requireBoolean(command, content[9], 'PowerOff');
        _requireBoolean(command, content[10], 'ChargingMode');
        // AudioStream belongs to the fixed V1.6 payload, but the FA18
        // real-time audio feature is outside this EVT build. Enforce zero at
        // the final admission boundary so direct command-client callers
        // cannot reactivate a retained P2/PVT stream state.
        if (content[11] != 0) {
          _invalid(command, 'AudioStream 当前 EVT 固定为 0。');
        }
        return;
      case 0x06:
        _validateStatusPayload(content);
        return;
      case 0x07:
        _requireLength(command, content, 1);
        if (content[0] > 3) {
          _invalid(command, 'RecordAction 只能为 0、1、2 或 3。');
        }
        return;
      case 0x09:
        _requireLength(command, content, 7);
        if (content[0] > 2) {
          _invalid(command, 'BindAction 只能为 0、1 或 2。');
        }
        return;
      case 0x22:
        _requireLength(command, content, 3);
        final pageSize = content[2];
        if (pageSize < 1 || pageSize > 20) {
          _invalid(command, 'PageSize 必须在 1 到 20 之间。');
        }
        return;
      case 0x23:
        if (content.length != 17 && content.length != 23) {
          _invalid(command, 'FileName[17] 请求只能是 17B 或 23B。');
        }
        _validateFileNameSlot(content.sublist(0, 17), command);
        if (content.length == 23) {
          final chunkSize = content[21] | (content[22] << 8);
          if (chunkSize > 480) {
            _invalid(command, 'ChunkSize 不能超过 480B。');
          }
        }
        return;
      case 0x11:
        _invalid(command, '0x11 仅支持 GATT Read，不允许通过业务写入发送。');
      default:
        // The command client normally rejects commands outside the EVT
        // allow-list first. Keep this helper defensive for direct callers.
        _invalid(command, '命令未纳入 EVT V1.6 写入协议。');
    }
  }

  static void _validateStatusPayload(List<int> content) {
    if (content.isEmpty) {
      _invalid(0x06, '缺少 SubCmd。');
    }
    final subCommand = content[0];
    switch (subCommand) {
      case 0x01: // GET_STATUS
      case 0x03: // PRIVACY_DURATION_GET
        _requireLength(0x06, content, 1);
        return;
      case 0x02: // RECORD_CONSENT_SET
        _requireLength(0x06, content, 3);
        if (content[1] != 1) {
          _invalid(0x06, 'RECORD_CONSENT_SET 的 DataLength 必须为 1。');
        }
        _requireBoolean(0x06, content[2], 'Granted');
        return;
      case 0x04: // PRIVACY_DURATION_SET
        _requireLength(0x06, content, 3);
        if (content[1] != 1) {
          _invalid(0x06, 'PRIVACY_DURATION_SET 的 DataLength 必须为 1。');
        }
        if (content[2] > 3) {
          _invalid(0x06, 'DurationCode 必须在 0 到 3 之间。');
        }
        return;
      default:
        _invalid(0x06, 'SubCmd 只能为 0x01、0x02、0x03 或 0x04。');
    }
  }

  static void _validateFileNameSlot(List<int> slot, int command) {
    final nul = slot.indexOf(0);
    if (nul <= 0) {
      _invalid(command, 'FileName[17] 必须包含非空名称和 NUL 终止符。');
    }
    for (var index = 0; index < nul; index += 1) {
      final byte = slot[index];
      if (byte < 0x20 || byte > 0x7E || byte == 0x2F || byte == 0x5C) {
        _invalid(command, 'FileName[17] 只能包含无路径分隔符的 ASCII 字符。');
      }
    }
    for (var index = nul + 1; index < slot.length; index += 1) {
      if (slot[index] != 0) {
        _invalid(command, 'FileName[17] 的 NUL 后必须全部补零。');
      }
    }
  }

  static void _validateByteValues(List<int> content) {
    for (final byte in content) {
      if (byte < 0 || byte > 0xFF) {
        throw RangeError.range(byte, 0, 0xFF, 'content');
      }
    }
  }

  static void _requireLength(int command, List<int> content, int expected) {
    if (content.length != expected) {
      _invalid(command, 'Content 长度必须为 ${expected}B，实际为 ${content.length}B。');
    }
  }

  static void _requireBoolean(int command, int value, String field) {
    if (value != 0 && value != 1) {
      _invalid(command, '$field 必须为 0 或 1。');
    }
  }

  static Never _invalid(int command, String detail) {
    final commandHex = command < 0 || command > 0xFF
        ? 'out_of_range'
        : '0x${command.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    throw StateError('EVT $commandHex 请求数据无效：$detail');
  }

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

  /// CCCs that must be enabled before an unauthenticated device-information
  /// request. V1.6 deliberately keeps this pre-auth surface tiny: FA11
  /// carries the redacted identity response and FA19 carries 0x09 auth.
  static const preAuthenticationSubscriptionOrder = <BleLogicalEndpoint>[
    BleLogicalEndpoint.fa10Fa11,
    BleLogicalEndpoint.fa10Fa19,
  ];

  /// CCCs enabled only after the current connection has completed Action=00.
  /// Keeping this separate from the pre-auth list prevents a device from
  /// exposing protected state merely because CCC configuration succeeded.
  static const postAuthenticationSubscriptionOrder = <BleLogicalEndpoint>[
    BleLogicalEndpoint.fa10Fa12,
    BleLogicalEndpoint.fa10Fa15,
    BleLogicalEndpoint.fa10Fa16,
    BleLogicalEndpoint.fa10Fa17,
    BleLogicalEndpoint.fb10Fb11,
    BleLogicalEndpoint.ff10Ff12,
    BleLogicalEndpoint.ff10Ff13,
  ];

  /// Compatibility alias for callers that need the complete mandatory set.
  /// Production connection setup uses the two phase lists above.
  static const requiredSubscriptionOrder = <BleLogicalEndpoint>[
    ...preAuthenticationSubscriptionOrder,
    ...postAuthenticationSubscriptionOrder,
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
