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
import 'package:aipin/features/device_session/domain/device_info.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';

class DeviceProtocolRepository implements DeviceFileTransferGateway {
  DeviceProtocolRepository({
    required this.deviceId,
    required this.profile,
    required this.transport,
    required this.commands,
    required this.codec,
    Duration legacySecurityResponseTimeout = const Duration(seconds: 2),
    Duration fileListResponseTimeout = const Duration(seconds: 2),
    Duration fileTransferIdleTimeout = const Duration(seconds: 15),
    Duration gattReadTimeout = const Duration(seconds: 2),
  }) : // Preserve public named timeout hooks used by the test and integration layers.
       // ignore: prefer_initializing_formals
       _legacySecurityResponseTimeout = legacySecurityResponseTimeout,
       // ignore: prefer_initializing_formals
       _fileListResponseTimeout = fileListResponseTimeout,
       // ignore: prefer_initializing_formals
       _fileTransferIdleTimeout = fileTransferIdleTimeout,
       // ignore: prefer_initializing_formals
       _gattReadTimeout = gattReadTimeout;

  final String deviceId;
  final DeviceProfile profile;
  final BleTransport transport;
  final EvtCommandClient commands;
  final EvtProtocolCodec codec;
  final Duration _legacySecurityResponseTimeout;
  final Duration _fileListResponseTimeout;
  final Duration _fileTransferIdleTimeout;
  final Duration _gattReadTimeout;

  Future<DeviceInfo> readDeviceInfo() async {
    final response = await commands.execute(
      EvtCommandRequest(
        command: 0x01,
        writeCharacteristic: _characteristic(BleLogicalEndpoint.fa10Fa11),
        expectedResponseCommand: 0x81,
        content: const [],
      ),
    );
    return decodeDeviceInfo(response.frame);
  }

  Future<void> writeConfiguration(DeviceConfiguration configuration) async {
    final writer = ProtocolWriter()
      ..u32Le(configuration.systemTime.toUtc().millisecondsSinceEpoch ~/ 1000)
      ..u16Le(configuration.recordDurationSeconds)
      ..u8(configuration.recordMode)
      ..u8(configuration.recordType)
      ..u8(configuration.denoise ? 1 : 0)
      ..u8(configuration.powerOff)
      ..u8(configuration.chargingMode)
      // V1.5 configuration remains 12 bytes; EVT keeps this final reserved
      // byte disabled instead of exposing a later-stage capability.
      ..u8(0);
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
  /// V1.5 defines this as a characteristic read returning a 0x82 frame; it
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

  Future<Uint8List> readStorageFrame() =>
      _readFrame(BleLogicalEndpoint.fa10Fa15, expectedCommand: 0x85);

  Future<DeviceBattery> readBattery() async =>
      decodeBattery(_decodeFrame(await readBatteryFrame()));

  Future<DeviceStorage> readStorage() async =>
      decodeStorage(_decodeFrame(await readStorageFrame()));

  Future<int> readFileCount() async {
    final bytes = await _readFrame(
      BleLogicalEndpoint.ff10Ff11,
      expectedCommand: 0xA1,
    );
    return decodeFileCount(_decodeFrame(bytes));
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
    return response.frame;
  }

  /// Executes the V1 EVT 0x09 envelope: Action:u8 + SecurityCode[6].
  ///
  /// A successful legacy response contains exactly the single byte [0x01].
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
        expectedResponseCommand: 0x89,
        responseMatcher: (frame) => frame.content.length == 1,
        timeout: _legacySecurityResponseTimeout,
        // V1 bind/reset can change the accepted security code. Never replay
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
        // V1.5 does not echo FileListOffset in the 0xA2 response. Retrying a
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

  /// Starts the V1.5 continuous 0x23 Notify transfer with exactly one write.
  /// The device marks the end of the transfer with a zero-length data frame.
  @override
  Stream<EvtDeviceFileTransferEvent> downloadEvtFile({
    required List<int> nameSlot,
    int startOffset = 0,
    int chunkSize = 0,
  }) async* {
    _validateNameSlot(nameSlot);
    if (startOffset < 0 || startOffset > 0xFFFFFFFF) {
      throw RangeError.range(startOffset, 0, 0xFFFFFFFF);
    }
    if (chunkSize < 0 || chunkSize > 0xFFFF) {
      throw RangeError.range(chunkSize, 0, 0xFFFF);
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
        expectedResponseCommand: 0x23,
      ),
      isTerminal: _isFileDataTerminalFrame,
      idleTimeout: _fileTransferIdleTimeout,
    )) {
      final chunk = _decodeFileDataFrame(frame, expectedOffset);
      if (chunk.isEmpty) {
        yield EvtDeviceFileTransferEvent.terminal();
        return;
      }
      expectedOffset += chunk.length;
      yield EvtDeviceFileTransferEvent.data(chunk);
    }
  }

  static DeviceInfo decodeDeviceInfo(EvtFrame frame) {
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
    if (recordStatus > 3) {
      throw const FormatException('设备信息录音状态无效。');
    }
    final recordDataLength = recordStatus == 0 ? 0 : 7;
    final expectedLength = recordOffset + 1 + recordDataLength + 6;
    if (frame.content.length != expectedLength) {
      throw const FormatException('设备信息条件字段长度无效。');
    }
    if (recordStatus != 0) {
      _validateActiveRecordFields(frame.content, recordOffset + 1);
    }
    final batteryOffset = recordOffset + 1 + recordDataLength;
    final batteryLevel = reader.u8(batteryOffset);
    final charging = reader.u8(batteryOffset + 1);
    final buzzer = reader.u8(batteryOffset + 2);
    final powerOff = reader.u8(batteryOffset + 3);
    final chargingMode = reader.u8(batteryOffset + 4);
    _validateDeviceInfoStateFields(
      batteryLevel: batteryLevel,
      charging: charging,
      buzzer: buzzer,
      powerOff: powerOff,
      chargingMode: chargingMode,
    );
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
  /// A stopped state is one byte. Every active, paused, or resumed state
  /// carries the seven recording detail bytes defined by V1.5.
  static void validateRecordState(EvtFrame frame) {
    _expectCommand(frame, 0x87);
    if (frame.content.isEmpty) {
      throw const FormatException('设备录音状态缺失。');
    }
    final recordStatus = frame.content.first;
    if (recordStatus > 3) {
      throw const FormatException('设备录音状态枚举无效。');
    }
    final expectedLength = recordStatus == 0 ? 1 : 8;
    if (frame.content.length != expectedLength) {
      throw const FormatException('设备录音状态条件字段长度无效。');
    }
    if (recordStatus != 0) {
      _validateActiveRecordFields(frame.content, 1);
    }
  }

  /// Matches a V1.5 record-control result without allowing malformed
  /// unsolicited FA17 state events to break the pending command stream.
  static bool _matchesRecordActionResponse(EvtFrame frame, int action) {
    if (frame.command != 0x87 ||
        frame.content.isEmpty ||
        frame.content.first != action) {
      return false;
    }
    try {
      validateRecordState(frame);
      return true;
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

  static bool _isFileDataTerminalFrame(EvtFrame frame) {
    if (frame.content.length < 6) {
      return false;
    }
    return ProtocolReader(frame.content).u16Le(4) == 0;
  }

  static Uint8List _decodeFileDataFrame(EvtFrame frame, int expectedOffset) {
    if (frame.command != 0x23 || frame.content.length < 6) {
      throw const FormatException('设备文件数据帧无效。');
    }
    final reader = ProtocolReader(frame.content);
    final offset = reader.u32Le(0);
    final length = reader.u16Le(4);
    if (frame.content.length != 6 + length || offset != expectedOffset) {
      throw const FormatException('文件数据 offset 或长度不连续。');
    }
    return Uint8List.fromList(frame.content.sublist(6));
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
        // V1.5 explicitly permits one retry for an idempotent GATT Read.
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

  /// V1.5 active record layouts are:
  /// RecordDuration:u16, CurrentDuration:u16, RecordMode:u8,
  /// RecordType:u8, Denoise:u8.
  static void _validateActiveRecordFields(List<int> bytes, int offset) {
    final recordType = bytes[offset + 5];
    final denoise = bytes[offset + 6];
    if ((recordType != 1 && recordType != 2) || !_isBoolean(denoise)) {
      throw const FormatException('设备录音参数枚举无效。');
    }
  }

  static void _validateBatteryFields({
    required int batteryLevel,
    required int charging,
    required int chargingMode,
  }) {
    // V1.5 defines 0=not charging, 1=charging, and 2=fully charged.
    // Treating a fully charged device as malformed interrupts the post-auth
    // 0x01 synchronization path on real hardware.
    if (batteryLevel > 100 || charging > 2 || !_isBoolean(chargingMode)) {
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

  static void _validateNameSlot(List<int> nameSlot) {
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
