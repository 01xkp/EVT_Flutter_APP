import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/protocol/evt_command_client.dart';
import 'package:aipin/core/protocol/evt_frame.dart';
import 'package:aipin/core/protocol/evt_protocol_contract.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/core/protocol/protocol_reader.dart';
import 'package:aipin/core/protocol/protocol_writer.dart';
import 'package:aipin/features/device_session/domain/device_configuration.dart';
import 'package:aipin/features/device_session/domain/device_capabilities.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/device_file_transfer_gateway.dart';
import 'package:aipin/features/device_session/domain/dvt_device_file_metadata_gateway.dart';
import 'package:aipin/features/device_session/domain/device_info.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';

/// Indicates that a structurally valid 0xA3 data frame cannot fit within the
/// negotiated ATT MTU. It remains a [StateError] so callers can handle it as a
/// protocol-state failure while retaining the values needed for diagnostics.
final class EvtFileTransferChunkMtuException extends StateError {
  EvtFileTransferChunkMtuException({
    required this.chunkBytes,
    required this.maxChunkBytes,
    this.attMtu,
  }) : super(
         '设备文件数据块 $chunkBytes 字节超过当前 ATT MTU 可承载上限 '
         '$maxChunkBytes。',
       );

  final int chunkBytes;
  final int maxChunkBytes;
  final int? attMtu;
}

class DeviceProtocolRepository implements DeviceFileTransferGateway {
  DeviceProtocolRepository({
    required this.deviceId,
    required this.profile,
    required this.transport,
    required this.commands,
    required this.codec,
    Duration legacySecurityResponseTimeout = const Duration(seconds: 2),
    Duration legacyBindResponseTimeout = const Duration(seconds: 65),
    Duration legacyUnbindResponseTimeout = const Duration(seconds: 120),
    Duration fileListResponseTimeout = const Duration(seconds: 2),
    Duration fileTransferIdleTimeout = const Duration(seconds: 15),
    Duration gattReadTimeout = const Duration(seconds: 2),
    int? Function()? negotiatedAttMtuProvider,
  }) : // Preserve public named timeout hooks used by the test and integration layers.
       // ignore: prefer_initializing_formals
       _legacySecurityResponseTimeout = legacySecurityResponseTimeout,
       // V1.6 gives BIND a 60-second button window plus response margin.
       // ignore: prefer_initializing_formals
       _legacyBindResponseTimeout = legacyBindResponseTimeout,
       // ignore: prefer_initializing_formals
       _legacyUnbindResponseTimeout = legacyUnbindResponseTimeout,
       // ignore: prefer_initializing_formals
       _fileListResponseTimeout = fileListResponseTimeout,
       // ignore: prefer_initializing_formals
       _fileTransferIdleTimeout = fileTransferIdleTimeout,
       // ignore: prefer_initializing_formals
       _gattReadTimeout = gattReadTimeout,
       // ignore: prefer_initializing_formals
       _negotiatedAttMtuProvider = negotiatedAttMtuProvider;

  final String deviceId;
  final DeviceProfile profile;
  final BleTransport transport;
  final EvtCommandClient commands;
  final EvtProtocolCodec codec;
  final Duration _legacySecurityResponseTimeout;
  final Duration _legacyBindResponseTimeout;
  final Duration _legacyUnbindResponseTimeout;
  final Duration _fileListResponseTimeout;
  final Duration _fileTransferIdleTimeout;
  final Duration _gattReadTimeout;

  /// Returns the ATT MTU negotiated for the active connection, when the
  /// repository is owned by [SessionController]. Keeping this optional keeps
  /// the data layer usable in isolated protocol tests and integrations that
  /// do not expose MTU state.
  final int? Function()? _negotiatedAttMtuProvider;

  /// Reads 0x01 from FA11. During connection admission V1.6 returns a fixed
  /// 90-byte redacted payload before Action=00; callers pass [unauthenticated]
  /// so the resulting model cannot be mistaken for an authoritative snapshot.
  Future<DeviceInfo> readDeviceInfo({bool unauthenticated = false}) async {
    final response = await commands.execute(
      EvtCommandRequest(
        command: 0x01,
        writeCharacteristic: _characteristic(BleLogicalEndpoint.fa10Fa11),
        expectedResponseCommand: 0x81,
        content: const [],
      ),
    );
    return decodeDeviceInfo(response.frame, redacted: unauthenticated);
  }

  Future<void> writeConfiguration(DeviceConfiguration configuration) async {
    _validateConfiguration(configuration);
    final writer = ProtocolWriter()
      ..u32Le(configuration.systemTime.toUtc().millisecondsSinceEpoch ~/ 1000)
      ..u16Le(configuration.recordDurationSeconds)
      ..u8(configuration.recordMode)
      ..u8(configuration.recordType)
      ..u8(configuration.denoise ? 1 : 0)
      ..u8(configuration.powerOff)
      ..u8(configuration.chargingMode)
      // V1.6 keeps AudioStream in the fixed 12-byte configuration payload.
      // DVT enables value 1 only after the FA18 CCC subscription is ready.
      // That operation-level ordering is enforced by SessionController;
      // this repository remains the protocol encoder and accepts 0/1.
      ..u8(configuration.audioStream);
    final response = await commands.execute(
      EvtCommandRequest(
        command: 0x02,
        content: writer.bytes,
        writeCharacteristic: _characteristic(BleLogicalEndpoint.fa10Fa12),
        expectedResponseCommand: 0x82,
        responseMatcher: (frame) => frame.content.length == 1,
      ),
    );
    _expectContentLength(response.frame, 1);
    if (response.frame.content.first != 1) {
      throw StateError('设备拒绝了录音配置。');
    }
  }

  /// Reads the device's current UTC through FA12 GATT Read.
  ///
  /// V1.6 defines this as a characteristic read returning a 0x82 frame; it
  /// must not be encoded as an empty 0x02 business write.
  Future<DateTime> readConfigurationTime() async {
    final frame = _decodeFrame(
      await _readFrame(BleLogicalEndpoint.fa10Fa12, expectedCommand: 0x82),
    );
    _expectContentLength(frame, 4);
    final seconds = ProtocolReader(frame.content).u32Le(0);
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  Future<DeviceStatus> readStatus() async {
    final response = await _executeStatusCommand(0x01);
    return decodeStatus(response.frame);
  }

  Future<void> setRecordConsent(bool granted) async {
    final response = await _executeStatusCommand(0x02, [granted ? 1 : 0]);
    _expectEmptyStatusData(response.frame, subCommand: 0x02);
  }

  Future<int> readPrivacyDuration() async {
    final response = await _executeStatusCommand(0x03);
    final data = _readStatusData(response.frame, subCommand: 0x03);
    if (data.length != 1 || data.single > 3) {
      throw const FormatException('设备隐私时长响应无效。');
    }
    return data.single;
  }

  Future<void> setPrivacyDuration(int durationCode) async {
    if (durationCode < 0 || durationCode > 3) {
      throw RangeError.range(durationCode, 0, 3);
    }
    final response = await _executeStatusCommand(0x04, [durationCode]);
    _expectEmptyStatusData(response.frame, subCommand: 0x04);
  }

  Future<Uint8List> readBatteryFrame() =>
      _readFrame(BleLogicalEndpoint.fb10Fb11, expectedCommand: 0x91);

  /// V1.6 changed FA15 from a GATT Read to a framed Write + Indicate
  /// exchange. The request has an empty Content field.
  Future<Uint8List> readStorageFrame() async {
    final response = await commands.execute(
      EvtCommandRequest(
        command: 0x05,
        content: const [],
        writeCharacteristic: _characteristic(BleLogicalEndpoint.fa10Fa15),
        expectedResponseCommand: 0x85,
        responseMatcher: (frame) => frame.content.length == 8,
      ),
    );
    _expectContentLength(response.frame, 8);
    // Keep the exact device response for diagnostics and downstream import.
    // A frame constructed by a test or legacy caller may not have raw bytes;
    // retain the canonical fallback for that case.
    return response.frame.rawBytes ??
        codec.encodeRequest(response.frame.command, response.frame.content);
  }

  Future<DeviceBattery> readBattery() async =>
      decodeBattery(_decodeFrame(await readBatteryFrame()));

  Future<DeviceStorage> readStorage() async =>
      decodeStorage(_decodeFrame(await readStorageFrame()));

  Future<int> readFileCount() async {
    // V1.6 changed FF11 from a GATT Read to a framed Write + Indicate
    // exchange. Keep this compatibility command optional at the session
    // layer, but encode its wire direction correctly when available.
    final response = await commands.execute(
      EvtCommandRequest(
        command: 0x21,
        content: const [],
        writeCharacteristic: _characteristic(BleLogicalEndpoint.ff10Ff11),
        expectedResponseCommand: 0xA1,
        responseMatcher: (frame) => frame.content.length == 2,
      ),
    );
    return decodeFileCount(response.frame);
  }

  Future<EvtFrame> setRecordAction(int action) async {
    if (action < 0 || action > 3) {
      throw RangeError.range(action, 0, 3);
    }
    final response = await commands.execute(
      EvtCommandRequest(
        command: 0x07,
        content: [action],
        writeCharacteristic: _characteristic(BleLogicalEndpoint.fa10Fa17),
        expectedResponseCommand: 0x87,
        // FA17 also carries unsolicited device state changes. A response to
        // this request is only authoritative when it reports the state that
        // the requested action should have reached; otherwise an unrelated
        // VAD/key/privacy event could complete the pending user action.
        responseMatcher: (frame) => _matchesRecordActionResponse(frame, action),
        // A lost indication does not mean that the device ignored a record
        // action. Re-sending a non-idempotent action can produce a different
        // device state, so callers must resolve a timeout by reading status.
        maxRetries: 0,
      ),
    );
    validateRecordState(response.frame);
    final errorCode = recordStateErrorCode(response.frame);
    if (errorCode != null) {
      // V1.6 reports command failures as a valid 0x87 state frame. Keep the
      // original frame attached so the session layer and diagnostics can
      // distinguish a device-reported error from a lost indication timeout.
      throw EvtRecordActionException(
        action: action,
        errorCode: errorCode,
        frame: response.frame,
      );
    }
    return response.frame;
  }

  /// Executes the V1.6 EVT 0x09 envelope: Action:u8 + SecurityCode[6].
  ///
  /// A successful V1.6 response contains exactly the single byte [0x01].
  /// The strict response matcher rejects any differently shaped 0x89 frame.
  Future<bool> executeEvtLegacySecurity(
    EvtLegacySecurityRequest request,
  ) async {
    if (!EvtProtocolContract.allowsBusinessCommand(0x09)) {
      throw StateError('当前阶段不允许发送设备认证命令。');
    }
    final response = await commands.execute(
      EvtCommandRequest(
        command: 0x09,
        content: request.content,
        writeCharacteristic: _characteristic(BleLogicalEndpoint.fa10Fa19),
        // V1.6 permits only a previously submitted UNBIND to be retried on a
        // fresh connection without Action=00.  Keep the exception explicit
        // in the command request so the session admission gate can inspect it
        // immediately before the native write; it has no wire representation.
        allowUnauthenticatedUnbindRecovery: request.recovery,
        expectedResponseCommand: 0x89,
        responseMatcher: (frame) => frame.content.length == 1,
        timeout: switch (request.action) {
          EvtLegacySecurityAction.authenticate =>
            _legacySecurityResponseTimeout,
          EvtLegacySecurityAction.bind => _legacyBindResponseTimeout,
          EvtLegacySecurityAction.unbind => _legacyUnbindResponseTimeout,
        },
        // V1.6 bind/unbind can change the accepted security code. Never replay
        // the frame when the Indicate result was lost.
        maxRetries: 0,
      ),
    );
    final result = response.frame.content.single;
    if (result != 0 && result != 1) {
      throw const FormatException('EVT 认证响应结果无效。');
    }
    return result == 1;
  }

  Future<List<DeviceFile>> listFiles({
    int offset = 0,
    int pageSize = 10,
  }) async {
    if (offset < 0 || offset > 0xFFFF) {
      throw RangeError.range(offset, 0, 0xFFFF);
    }
    if (pageSize < 1 || pageSize > 20) {
      throw RangeError.range(pageSize, 1, 20);
    }
    final writer = ProtocolWriter()
      ..u16Le(offset)
      ..u8(pageSize);
    final response = await commands.execute(
      EvtCommandRequest(
        command: 0x22,
        content: writer.bytes,
        writeCharacteristic: _characteristic(BleLogicalEndpoint.ff10Ff12),
        expectedResponseCommand: 0xA2,
        timeout: _fileListResponseTimeout,
        // V1.6 does not echo FileListOffset in the 0xA2 response. Retrying a
        // timed-out page on the same connection lets a late first response be
        // mistaken for the retry or the next page. The session controller
        // resets the transport after this timeout before a new listing starts.
        maxRetries: 0,
      ),
    );
    final files = decodeFileList(response.frame);
    if (files.length > pageSize) {
      throw const FormatException('设备文件列表条目超过请求页大小。');
    }
    return files;
  }

  /// Starts the V1.6 continuous 0x23 request / 0xA3 Notify transfer with
  /// exactly one write.
  /// The device marks the end of the transfer with a zero-length data frame.
  @override
  Stream<EvtDeviceFileTransferEvent> downloadEvtFile({
    required List<int> nameSlot,
    int startOffset = 0,
    int chunkSize = 0,
    int? expectedFileLength,
  }) async* {
    _validateNameSlot(nameSlot);
    if (startOffset < 0 || startOffset > 0xFFFFFFFF) {
      throw RangeError.range(startOffset, 0, 0xFFFFFFFF);
    }
    if (chunkSize < 0 || chunkSize > 0xFFFF) {
      throw RangeError.range(chunkSize, 0, 0xFFFF);
    }
    if (chunkSize > 480) {
      throw RangeError.range(chunkSize, 0, 480);
    }
    if (expectedFileLength != null &&
        (expectedFileLength < 0 || expectedFileLength > 0xFFFFFFFF)) {
      throw RangeError.range(expectedFileLength, 0, 0xFFFFFFFF);
    }
    if (expectedFileLength != null && startOffset > expectedFileLength) {
      throw StateError('文件起始偏移超过 0x22 声明的文件长度。');
    }
    final negotiatedMtu = _negotiatedAttMtuProvider?.call();
    final effectiveChunkLimit = _effectiveFileChunkLimit(negotiatedMtu);
    if (negotiatedMtu != null && negotiatedMtu < 33) {
      throw StateError('当前 ATT MTU 不足，无法承载 0x23 文件数据。');
    }
    if (chunkSize > 0 && chunkSize > effectiveChunkLimit) {
      throw StateError(
        '请求分块 $chunkSize 字节超过当前 ATT MTU 可承载上限 '
        '$effectiveChunkLimit。',
      );
    }
    final writer = ProtocolWriter()..addAll(nameSlot);
    if (startOffset != 0 || chunkSize != 0) {
      writer
        ..u32Le(startOffset)
        ..u16Le(chunkSize);
    }
    var expectedOffset = startOffset;
    await for (final frame in commands.executeStreaming(
      EvtCommandRequest(
        command: 0x23,
        content: writer.bytes,
        writeCharacteristic: _characteristic(BleLogicalEndpoint.ff10Ff13),
        expectedResponseCommand: 0xA3,
      ),
      isTerminal: _isFileDataTerminalFrame,
      idleTimeout: _fileTransferIdleTimeout,
    )) {
      final chunk = _decodeFileDataFrame(
        frame,
        expectedOffset,
        maxChunkSize: effectiveChunkLimit,
        attMtu: negotiatedMtu,
      );
      if (chunk.isEmpty) {
        if (expectedFileLength != null &&
            expectedOffset != expectedFileLength) {
          throw StateError(
            '设备文件结束偏移 $expectedOffset 与 0x22 声明长度 '
            '$expectedFileLength 不一致。',
          );
        }
        yield EvtDeviceFileTransferEvent.terminal();
        return;
      }
      if (expectedFileLength != null &&
          expectedOffset + chunk.length > expectedFileLength) {
        throw StateError('设备文件数据超过 0x22 声明的文件长度。');
      }
      expectedOffset += chunk.length;
      yield EvtDeviceFileTransferEvent.data(chunk);
    }
  }

  static DeviceInfo decodeDeviceInfo(EvtFrame frame, {bool redacted = false}) {
    _expectCommand(frame, 0x81);
    final reader = ProtocolReader(frame.content);
    if (frame.content.length < 83) {
      throw const FormatException('设备信息字段长度不足。');
    }
    final protocolVersion = reader.u8(0);
    final deviceCode = _paddedAscii(frame.content, 1, 20);
    final software = _paddedAscii(frame.content, 21, 8);
    final hardware = _paddedAscii(frame.content, 29, 8);
    final name = _paddedUtf8(frame.content, 45, 29);
    final total = reader.u32Le(74);
    final remain = reader.u32Le(78);
    if (remain > total) {
      throw const FormatException('设备信息中的剩余存储空间无效。');
    }
    final reserved = reader.u8(82);
    final recordOffset = reserved == 0 ? 83 : 113;
    if (frame.content.length < recordOffset + 1) {
      throw const FormatException('设备信息缺少录音状态。');
    }
    final recordStatus = reader.u8(recordOffset);
    if (recordStatus != 0 &&
        recordStatus != 1 &&
        recordStatus != 2 &&
        recordStatus != 0xFF) {
      throw const FormatException('设备信息录音状态无效。');
    }
    // 0x01 uses a compact one-byte ERROR state. Unlike the 0x07 status
    // indication, it does not append an ErrorCode in this response.
    final recordDataLength = recordStatus == 1 || recordStatus == 2 ? 7 : 0;
    final expectedLength = recordOffset + 1 + recordDataLength + 6;
    if (frame.content.length != expectedLength) {
      throw const FormatException('设备信息条件字段长度无效。');
    }
    if (recordStatus == 1 || recordStatus == 2) {
      _validateActiveRecordFields(frame.content, recordOffset + 1);
    }
    final batteryOffset = recordOffset + 1 + recordDataLength;
    final batteryLevel = reader.u8(batteryOffset);
    final charging = reader.u8(batteryOffset + 1);
    final buzzer = reader.u8(batteryOffset + 2);
    final powerOff = reader.u8(batteryOffset + 3);
    final chargingMode = reader.u8(batteryOffset + 4);
    final audioStream = reader.u8(batteryOffset + 5);
    _validateDeviceInfoStateFields(
      batteryLevel: batteryLevel,
      charging: charging,
      buzzer: buzzer,
      powerOff: powerOff,
      chargingMode: chargingMode,
    );
    if (redacted) {
      // V1.6 defines the pre-auth response as exactly 90 bytes with all
      // user-state fields zeroed. Accepting a non-zero placeholder here would
      // let an unauthenticated payload leak into the live device snapshot.
      if (frame.content.length != 90 ||
          reserved != 0 ||
          recordStatus != 0 ||
          total != 0 ||
          remain != 0 ||
          batteryLevel != 0 ||
          charging != 0 ||
          buzzer != 0 ||
          powerOff != 0 ||
          chargingMode != 0 ||
          audioStream != 0) {
        throw const FormatException('未认证设备信息不符合 V1.6 脱敏布局。');
      }
    }
    return DeviceInfo(
      capabilities: DeviceCapabilities(protocolVersion: protocolVersion),
      deviceCode: deviceCode,
      softwareVersion: software,
      hardwareVersion: hardware,
      deviceName: name,
      totalDiskSpaceMb: total,
      remainDiskSpaceMb: remain,
      recordStatus: recordStatus,
      batteryLevel: batteryLevel,
      charging: charging,
      powerOff: powerOff,
      chargingMode: chargingMode,
      reservedFeatureStatus: reserved,
      audioStream: audioStream,
      recordDurationSeconds: recordStatus == 1 || recordStatus == 2
          ? reader.u16Le(recordOffset + 1)
          : null,
      currentDurationSeconds: recordStatus == 1 || recordStatus == 2
          ? reader.u16Le(recordOffset + 3)
          : null,
      recordMode: recordStatus == 1 || recordStatus == 2
          ? reader.u8(recordOffset + 5)
          : null,
      recordType: recordStatus == 1 || recordStatus == 2
          ? reader.u8(recordOffset + 6)
          : null,
      denoise: recordStatus == 1 || recordStatus == 2
          ? reader.u8(recordOffset + 7)
          : null,
      // The 0x81 device-information response uses a compact one-byte
      // RecordStatus for ERROR. V1.6 deliberately does not append an
      // ErrorCode here; the six following bytes are the normal battery/state
      // tail. ErrorCode is only carried by the dedicated 0x87 indication.
      errorCode: null,
      isRedacted: redacted,
    );
  }

  static DeviceStatus decodeStatus(EvtFrame frame) =>
      _decodeStatus(frame, expectedSubCommand: 0x01);

  static DeviceStatus decodeStatusEvent(EvtFrame frame) =>
      _decodeStatus(frame, expectedSubCommand: 0x80);

  static DeviceStatus _decodeStatus(
    EvtFrame frame, {
    required int expectedSubCommand,
  }) {
    _expectCommand(frame, 0x86);
    if (frame.content.length < 8 ||
        frame.content[0] != expectedSubCommand ||
        frame.content[1] != 0) {
      throw const FormatException('设备状态响应无效。');
    }
    final reader = ProtocolReader(frame.content);
    final length = reader.u8(2);
    if (length != 5 || frame.content.length != 3 + length) {
      throw const FormatException('设备状态长度无效。');
    }
    final privacy = reader.u8(3);
    final recordConsent = reader.u8(6);
    final syncState = reader.u8(7);
    if (!_isBoolean(privacy) || !_isBoolean(recordConsent) || syncState > 3) {
      throw const FormatException('设备状态枚举无效。');
    }
    return DeviceStatus(
      privacy: privacy != 0,
      privacyRemainingMinutes: reader.u16Le(4),
      recordConsent: recordConsent != 0,
      syncState: syncState,
    );
  }

  static DeviceBattery decodeBattery(EvtFrame frame) {
    _expectCommand(frame, 0x91);
    _expectContentLength(frame, 3);
    final batteryLevel = frame.content[0];
    final charging = frame.content[1];
    final chargingMode = frame.content[2];
    _validateBatteryFields(
      batteryLevel: batteryLevel,
      charging: charging,
      chargingMode: chargingMode,
    );
    return DeviceBattery(
      percent: batteryLevel,
      isCharging: charging != 0,
      chargingMode: chargingMode,
    );
  }

  /// Validates the EVT 0x87 variable-layout recording state frame.
  ///
  /// V1.6 defines STOPPED as one byte, RECORDING/PAUSED as eight bytes, and
  /// ERROR as three bytes (`0xFF` plus a signed u16 error code).
  static void validateRecordState(EvtFrame frame) {
    _expectCommand(frame, 0x87);
    if (frame.content.isEmpty) {
      throw const FormatException('设备录音状态缺失。');
    }
    final recordStatus = frame.content.first;
    if (recordStatus != 0 &&
        recordStatus != 1 &&
        recordStatus != 2 &&
        recordStatus != 0xFF) {
      throw const FormatException('设备录音状态枚举无效。');
    }
    final expectedLength = switch (recordStatus) {
      0 => 1,
      1 || 2 => 8,
      0xFF => 3,
      _ => -1,
    };
    if (frame.content.length != expectedLength) {
      throw const FormatException('设备录音状态条件字段长度无效。');
    }
    if (recordStatus == 1 || recordStatus == 2) {
      _validateActiveRecordFields(frame.content, 1);
    }
  }

  /// Returns the signed V1.6 ErrorCode carried by a 0x87 error state, or null
  /// for a valid stopped/recording/paused state. The frame is validated before
  /// decoding so callers cannot accidentally interpret a truncated payload.
  static int? recordStateErrorCode(EvtFrame frame) {
    validateRecordState(frame);
    if (frame.content.first != 0xFF) {
      return null;
    }
    final raw = frame.content[1] | (frame.content[2] << 8);
    return raw >= 0x8000 ? raw - 0x10000 : raw;
  }

  /// Matches a V1.6 record-control result without allowing malformed
  /// unsolicited FA17 state events to break the pending command stream.
  static bool _matchesRecordActionResponse(EvtFrame frame, int action) {
    if (frame.command != 0x87 || frame.content.isEmpty) {
      return false;
    }
    try {
      validateRecordState(frame);
      // The V1.6 response carries resulting RecordStatus, not the request
      // action. Match the resulting state so an unrelated asynchronous event
      // cannot complete a pending control command.
      final expectedStatus = switch (action) {
        0 => 0,
        1 => 1,
        2 => 2,
        3 => 1,
        _ => -1,
      };
      // 0xFF is a valid command-level error response. It has no action field,
      // so when a command is pending it is the only terminal error signal the
      // protocol provides; setRecordAction converts it to a typed exception.
      return frame.content.first == 0xFF ||
          frame.content.first == expectedStatus;
    } on FormatException {
      return false;
    }
  }

  static DeviceStorage decodeStorage(EvtFrame frame) {
    _expectCommand(frame, 0x85);
    if (frame.content.length != 8) {
      throw const FormatException('设备存储状态长度无效。');
    }
    final reader = ProtocolReader(frame.content);
    final totalMegabytes = reader.u32Le(0);
    final freeMegabytes = reader.u32Le(4);
    if (freeMegabytes > totalMegabytes) {
      throw const FormatException('设备存储空间无效。');
    }
    return DeviceStorage(
      totalMegabytes: totalMegabytes,
      freeMegabytes: freeMegabytes,
    );
  }

  static int decodeFileCount(EvtFrame frame) {
    _expectCommand(frame, 0xA1);
    if (frame.content.length != 2) {
      throw const FormatException('设备文件数量长度无效。');
    }
    return ProtocolReader(frame.content).u16Le(0);
  }

  static List<DeviceFile> decodeFileList(EvtFrame frame) {
    _expectCommand(frame, 0xA2);
    final reader = ProtocolReader(frame.content);
    final count = reader.u8(0);
    if (count > 20) {
      throw const FormatException('文件列表 Count 超出 EVT 上限。');
    }
    if (frame.content.length != 1 + count * 21) {
      throw const FormatException('文件列表长度无效。');
    }
    return [
      for (var index = 0; index < count; index += 1) _decodeFile(reader, index),
    ];
  }

  /// Builds the V1.6 DVT `0x26 / GET_META` Content payload.
  ///
  /// This is intentionally a codec helper only. A DVT-gated session adapter
  /// owns the FF16 write/indicate transaction and the shared command queue
  /// continues to serialize it with other protocol operations.
  static List<int> encodeDvtReadFileMetadataContent(List<int> nameSlot) {
    _validateNameSlot(nameSlot);
    return List<int>.unmodifiable(<int>[0x01, 0x11, ...nameSlot]);
  }

  /// Builds the V1.6 DVT `0x26 / ARCHIVE_CONFIRM` Content payload.
  ///
  /// The last byte is fixed to `ArchiveResult=1`; callers reach this helper
  /// only after a separate archive gateway has reported durable persistence.
  static List<int> encodeDvtArchiveConfirmationContent(
    DvtDeviceArchiveConfirmation confirmation,
  ) {
    _validateNameSlot(confirmation.nameSlot);
    if (confirmation.fileSize < 0 || confirmation.fileSize > 0xFFFFFFFF) {
      throw RangeError.range(confirmation.fileSize, 0, 0xFFFFFFFF, 'fileSize');
    }
    if (confirmation.crc32 < 0 || confirmation.crc32 > 0xFFFFFFFF) {
      throw RangeError.range(confirmation.crc32, 0, 0xFFFFFFFF, 'crc32');
    }
    final data = ProtocolWriter()
      ..addAll(confirmation.nameSlot)
      ..u32Le(confirmation.fileSize)
      ..u32Le(confirmation.crc32)
      ..u8(DvtDeviceArchiveConfirmation.archiveResult);
    return List<int>.unmodifiable(<int>[
      0x02,
      data.bytes.length,
      ...data.bytes,
    ]);
  }

  /// Decodes the V1.6 DVT `0xA6 / GET_META` success envelope.
  ///
  /// V1.6 removed V1.5's `DurationS`, making the Data field exactly 41 bytes.
  static DvtDeviceFileMetadata decodeDvtFileMetadata(EvtFrame frame) {
    final data = _readDvtSuccessData(
      frame,
      subCommand: 0x01,
      expectedDataLength: 41,
      operation: '文件元数据',
    );
    final reader = ProtocolReader(data);
    final clockQuality = reader.u8(27);
    if (clockQuality > 2) {
      throw const FormatException('DVT 文件元数据 ClockQuality 无效。');
    }
    final recordingSessionId = reader.u32Le(21);
    if (recordingSessionId == 0) {
      throw const FormatException('DVT 文件元数据 RecordingSessionId 无效。');
    }
    final fileSize = reader.u32Le(32);
    if (fileSize == 0) {
      throw const FormatException('DVT 文件元数据 FileSize 无效。');
    }
    return DvtDeviceFileMetadata(
      name: reader.asciiSlot17(0),
      nameSlot: List<int>.unmodifiable(reader.bytes.sublist(0, 17)),
      startUtc: DateTime.fromMillisecondsSinceEpoch(
        reader.u32Le(17) * 1000,
        isUtc: true,
      ),
      recordingSessionId: recordingSessionId,
      segmentIndex: reader.u16Le(25),
      clockQuality: clockQuality,
      utcCorrectionMilliseconds: reader.s32Le(28),
      fileSize: fileSize,
      crc32: reader.u32Le(36),
      state: DvtDeviceFileState.fromWireValue(reader.u8(40)),
    );
  }

  /// Decodes a V1.6 DVT `0xA6 / ARCHIVE_CONFIRM` success envelope.
  ///
  /// `DEVICE_CONFIRMED (3)` was a V1.5 terminal state only and deliberately
  /// fails here. V1.6 requires either `DELETE (6)` or `RECLAIMABLE (4)`.
  static DvtDeviceArchiveConfirmationResult decodeDvtArchiveConfirmation(
    EvtFrame frame,
  ) {
    final data = _readDvtSuccessData(
      frame,
      subCommand: 0x02,
      expectedDataLength: 1,
      operation: '文件归档确认',
    );
    final result = DvtDeviceArchiveConfirmationResult(
      DvtDeviceFileState.fromWireValue(data.single),
    );
    if (!result.isTerminal) {
      throw FormatException('DVT 文件归档确认状态无效：${result.state.name}。');
    }
    return result;
  }

  static List<int> _readDvtSuccessData(
    EvtFrame frame, {
    required int subCommand,
    required int expectedDataLength,
    required String operation,
  }) {
    _expectCommand(frame, 0xA6);
    if (frame.content.length < 3 || frame.content[0] != subCommand) {
      throw FormatException('DVT $operation响应包头无效。');
    }
    final result = frame.content[1];
    final dataLength = frame.content[2];
    if (frame.content.length != 3 + dataLength) {
      throw FormatException('DVT $operation响应长度无效。');
    }
    if (result != 0) {
      // Failed 0x26 operations normally carry no Data. Reject an unexpected
      // success-shaped payload too, so no caller can parse stale bytes.
      if (dataLength != 0) {
        throw FormatException('DVT $operation失败响应不应包含数据。');
      }
      throw FormatException('DVT $operation被设备拒绝，Result=$result。');
    }
    if (dataLength != expectedDataLength) {
      throw FormatException('DVT $operation响应数据长度无效。');
    }
    return List<int>.unmodifiable(frame.content.sublist(3));
  }

  static bool _isFileDataTerminalFrame(EvtFrame frame) {
    if (frame.content.length < 6) {
      return false;
    }
    return ProtocolReader(frame.content).u16Le(4) == 0;
  }

  static Uint8List _decodeFileDataFrame(
    EvtFrame frame,
    int expectedOffset, {
    int maxChunkSize = 480,
    int? attMtu,
  }) {
    if (frame.command != 0xA3 || frame.content.length < 6) {
      throw const FormatException('设备文件数据帧无效。');
    }
    final reader = ProtocolReader(frame.content);
    final offset = reader.u32Le(0);
    final length = reader.u16Le(4);
    // Keep an oversized but otherwise structurally valid chunk distinguishable
    // from a malformed or out-of-order frame. The session layer needs the
    // exact size to emit its MTU diagnostic before invalidating the connection.
    if (length > maxChunkSize && frame.content.length == 6 + length) {
      throw EvtFileTransferChunkMtuException(
        chunkBytes: length,
        maxChunkBytes: maxChunkSize,
        attMtu: attMtu,
      );
    }
    if (frame.content.length != 6 + length || offset != expectedOffset) {
      throw const FormatException('文件数据 offset 或长度不连续。');
    }
    return Uint8List.fromList(frame.content.sublist(6));
  }

  /// V1.6 reserves 32 bytes of an ATT packet for the outer business frame and
  /// the FileOffset/DataLength fields. A repository used without a session
  /// MTU provider still enforces the protocol's absolute 480-byte cap.
  static int _effectiveFileChunkLimit(int? attMtu) {
    if (attMtu == null) {
      return 480;
    }
    final available = attMtu - 32;
    if (available <= 0) {
      return 0;
    }
    return available < 480 ? available : 480;
  }

  Future<Uint8List> _readFrame(
    BleLogicalEndpoint endpoint, {
    required int expectedCommand,
  }) async {
    final characteristic = _characteristic(endpoint);
    for (var attempt = 0; attempt < 2; attempt += 1) {
      try {
        final bytes = await transport
            .read(characteristic)
            .timeout(_gattReadTimeout);
        final result = codec.decode(bytes);
        if (!result.isSuccess || result.value!.command != expectedCommand) {
          throw FormatException(
            '设备读取响应 CMD 不匹配：0x${expectedCommand.toRadixString(16)}',
          );
        }
        return Uint8List.fromList(bytes);
      } on TimeoutException {
        // V1.6 explicitly permits one retry for an idempotent GATT Read.
        if (attempt == 1) {
          rethrow;
        }
      }
    }
    throw StateError('设备读取重试状态异常。');
  }

  EvtFrame _decodeFrame(Uint8List bytes) {
    final result = codec.decode(bytes);
    if (!result.isSuccess || result.value == null) {
      throw const FormatException('设备读取帧无效。');
    }
    return result.value!;
  }

  Future<EvtCommandResponse> _executeStatusCommand(
    int subCommand, [
    List<int> data = const [],
  ]) {
    return commands.execute(
      EvtCommandRequest(
        command: 0x06,
        content: data.isEmpty
            ? [subCommand]
            : [subCommand, data.length, ...data],
        writeCharacteristic: _characteristic(BleLogicalEndpoint.fa10Fa16),
        expectedResponseCommand: 0x86,
        expectedSubCommand: subCommand,
      ),
    );
  }

  static List<int> _readStatusData(EvtFrame frame, {required int subCommand}) {
    _expectCommand(frame, 0x86);
    if (frame.content.length < 3 ||
        frame.content[0] != subCommand ||
        frame.content[1] != 0) {
      throw const FormatException('设备状态配置响应无效。');
    }
    final length = frame.content[2];
    if (frame.content.length != 3 + length) {
      throw const FormatException('设备状态配置响应长度无效。');
    }
    return frame.content.sublist(3);
  }

  static void _expectEmptyStatusData(
    EvtFrame frame, {
    required int subCommand,
  }) {
    if (_readStatusData(frame, subCommand: subCommand).isNotEmpty) {
      throw const FormatException('设备状态配置响应不应包含数据。');
    }
  }

  BleCharacteristic _characteristic(BleLogicalEndpoint endpoint) {
    final value = profile.endpoints[endpoint];
    if (value == null || value.characteristicUuid.isEmpty) {
      throw StateError('BLE 端点未配置：$endpoint');
    }
    return BleCharacteristic(
      deviceId: deviceId,
      serviceUuid: value.serviceUuid,
      characteristicUuid: value.characteristicUuid,
    );
  }

  static DeviceFile _decodeFile(ProtocolReader reader, int index) {
    final offset = 1 + index * 21;
    final slot = List<int>.unmodifiable(
      reader.bytes.sublist(offset, offset + 17),
    );
    return DeviceFile(
      name: reader.asciiSlot17(offset),
      nameSlot: slot,
      length: reader.u32Le(offset + 17),
    );
  }

  static String _paddedAscii(List<int> bytes, int offset, int length) {
    final value = _paddedSlot(bytes, offset, length);
    if (value.any((byte) => byte < 0x20 || byte > 0x7E)) {
      throw const FormatException('设备信息 ASCII 固定槽无效。');
    }
    return ascii.decode(value);
  }

  static String _paddedUtf8(List<int> bytes, int offset, int length) {
    final value = _paddedSlot(bytes, offset, length, requireNul: true);
    if (value.length > 27) {
      throw const FormatException('设备名称超过 EVT 固定槽上限。');
    }
    return utf8.decode(value, allowMalformed: false);
  }

  static List<int> _paddedSlot(
    List<int> bytes,
    int offset,
    int length, {
    bool requireNul = false,
  }) {
    final slot = bytes.sublist(offset, offset + length);
    final nul = slot.indexOf(0);
    if (nul < 0) {
      if (requireNul) {
        throw const FormatException('设备信息固定槽缺少 NUL 终止符。');
      }
      return slot;
    }
    if (slot.skip(nul + 1).any((byte) => byte != 0)) {
      throw const FormatException('设备信息固定槽 NUL 后必须补零。');
    }
    return slot.take(nul).toList();
  }

  static bool _isBoolean(int value) => value == 0 || value == 1;

  /// V1.6 active record layouts are:
  /// RecordDuration:u16, CurrentDuration:u16, RecordMode:u8,
  /// RecordType:u8, Denoise:u8.
  static void _validateActiveRecordFields(List<int> bytes, int offset) {
    final recordMode = bytes[offset + 4];
    final recordType = bytes[offset + 5];
    final denoise = bytes[offset + 6];
    if (recordMode != 1 ||
        (recordType != 1 && recordType != 2) ||
        !_isBoolean(denoise)) {
      throw const FormatException('设备录音参数枚举无效。');
    }
  }

  static void _validateBatteryFields({
    required int batteryLevel,
    required int charging,
    required int chargingMode,
  }) {
    // V1.6 restricts Charging to 0 (not charging) or 1 (charging).
    if (batteryLevel > 100 ||
        !_isBoolean(charging) ||
        !_isBoolean(chargingMode)) {
      throw const FormatException('设备电池状态枚举无效。');
    }
  }

  static void _validateDeviceInfoStateFields({
    required int batteryLevel,
    required int charging,
    required int buzzer,
    required int powerOff,
    required int chargingMode,
  }) {
    _validateBatteryFields(
      batteryLevel: batteryLevel,
      charging: charging,
      chargingMode: chargingMode,
    );
    if (!_isBoolean(buzzer) || !_isBoolean(powerOff)) {
      throw const FormatException('设备状态布尔字段无效。');
    }
  }

  /// Validates the values that the App is about to place in the fixed V1.6
  /// 0x02 payload. ProtocolWriter catches byte-width overflow, but it cannot
  /// distinguish an in-range value that violates a field's documented enum.
  static void _validateConfiguration(DeviceConfiguration configuration) {
    if (configuration.recordDurationSeconds < 0 ||
        configuration.recordDurationSeconds > 0xFFFF) {
      throw RangeError.range(
        configuration.recordDurationSeconds,
        0,
        0xFFFF,
        'recordDurationSeconds',
      );
    }
    if (configuration.recordMode != 1) {
      throw const FormatException('RecordMode 当前 EVT 固定为 1。');
    }
    if (configuration.recordType != 1 && configuration.recordType != 2) {
      throw const FormatException('RecordType 必须为 1 或 2。');
    }
    if (!_isBoolean(configuration.powerOff)) {
      throw const FormatException('PowerOff 必须为 0 或 1。');
    }
    if (!_isBoolean(configuration.chargingMode)) {
      throw const FormatException('ChargingMode 必须为 0 或 1。');
    }
    if (configuration.audioStream < 0 || configuration.audioStream > 0xFF) {
      throw RangeError.range(configuration.audioStream, 0, 0xFF, 'audioStream');
    }
    if (configuration.audioStream != 0 && configuration.audioStream != 1) {
      throw const FormatException('AudioStream 必须为 0 或 1。');
    }
  }

  static void _validateNameSlot(List<int> nameSlot) {
    if (nameSlot.length != 17) {
      throw const FormatException('FileName[17] 必须固定为 17 字节。');
    }
    ProtocolReader(nameSlot).asciiSlot17(0);
  }

  static void _expectCommand(EvtFrame frame, int command) {
    if (frame.command != command) {
      throw FormatException('响应 CMD 不匹配：${frame.command}');
    }
  }

  static void _expectContentLength(EvtFrame frame, int length, {int? or}) {
    if (frame.content.length != length &&
        (or == null || frame.content.length != or)) {
      throw const FormatException('设备响应长度无效。');
    }
  }
}

/// A valid EVT 0x87 response that reports a device-side recording error.
///
/// The V1.6 frame has no request/action identifier, so the originating action
/// is supplied by the pending App command. [frame] is retained for diagnostics
/// and for callers that need the exact wire-level payload.
class EvtRecordActionException implements Exception {
  const EvtRecordActionException({
    required this.action,
    required this.errorCode,
    required this.frame,
  });

  final int action;
  final int errorCode;
  final EvtFrame frame;

  @override
  String toString() {
    final actionHex = action.toRadixString(16).padLeft(2, '0').toUpperCase();
    final errorHex = (errorCode & 0xFFFF)
        .toRadixString(16)
        .padLeft(4, '0')
        .toUpperCase();
    return 'EvtRecordActionException(action=0x$actionHex, '
        'errorCode=$errorCode (0x$errorHex))';
  }
}
