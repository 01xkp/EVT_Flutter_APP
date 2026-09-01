import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/protocol/evt_command_client.dart';
import 'package:aipin/core/protocol/evt_frame.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/core/protocol/protocol_reader.dart';
import 'package:aipin/core/protocol/protocol_writer.dart';
import 'package:aipin/features/device_session/domain/device_configuration.dart';
import 'package:aipin/features/device_session/domain/device_capabilities.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/device_file_gateway.dart';
import 'package:aipin/features/device_session/domain/device_info.dart';
import 'package:aipin/features/device_session/domain/device_security_gateway.dart';
import 'package:aipin/features/device_session/domain/ticket_gateway.dart';

class DeviceProtocolRepository
    implements DeviceFileGateway, DeviceSecurityGateway {
  DeviceProtocolRepository({
    required this.deviceId,
    required this.profile,
    required this.transport,
    required this.commands,
    required this.codec,
  });

  final String deviceId;
  final DeviceProfile profile;
  final BleTransport transport;
  final EvtCommandClient commands;
  final EvtProtocolCodec codec;

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
      ..u8(configuration.audioStreamEnabled ? 1 : 0);
    final response = await commands.execute(
      EvtCommandRequest(
        command: 0x02,
        content: writer.bytes,
        writeCharacteristic: _characteristic(BleLogicalEndpoint.fa10Fa12),
        expectedResponseCommand: 0x82,
      ),
    );
    _expectContentLength(response.frame, 1);
    if (response.frame.content.first != 1) {
      throw StateError('设备拒绝了录音配置。');
    }
  }

  Future<DeviceStatus> readStatus() async {
    final response = await _executeStatusCommand(0x01);
    return decodeStatus(response.frame);
  }

  Future<void> setRecordConsent(bool granted) async {
    final response = await _executeStatusCommand(0x02, [granted ? 1 : 0]);
    _readStatusData(response.frame, subCommand: 0x02);
  }

  Future<int> readPrivacyDuration() async {
    final response = await _executeStatusCommand(0x03);
    return _readStatusData(response.frame, subCommand: 0x03).single;
  }

  Future<void> setPrivacyDuration(int durationCode) async {
    if (durationCode < 0 || durationCode > 3) {
      throw RangeError.range(durationCode, 0, 3);
    }
    final response = await _executeStatusCommand(0x04, [durationCode]);
    _readStatusData(response.frame, subCommand: 0x04);
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
      ),
    );
    _expectContentLength(response.frame, 1, or: 8);
    return response.frame;
  }

  @override
  Future<DeviceSecurityResponse> execute(DeviceSecurityRequest request) async {
    final action = request.action;
    final transactionId = request.transactionId;
    final data = request.data;
    if (transactionId < 0 || transactionId > 0xFFFFFFFF) {
      throw RangeError.range(transactionId, 0, 0xFFFFFFFF);
    }
    if (data.length > 0xFFFF) {
      throw RangeError.range(data.length, 0, 0xFFFF, 'data');
    }
    final writer = ProtocolWriter()
      ..u8(0xF2)
      ..u8(action.wireValue)
      ..u32Le(transactionId)
      ..u16Le(data.length)
      ..addAll(data);
    final response = await commands.execute(
      EvtCommandRequest(
        command: 0x09,
        content: writer.bytes,
        writeCharacteristic: _characteristic(BleLogicalEndpoint.fa10Fa19),
        expectedResponseCommand: 0x89,
        responseMatcher: (frame) => _matchesAuthenticationResponse(
          frame,
          action: action,
          transactionId: transactionId,
        ),
      ),
    );
    return decodeSecurityResponse(
      response.frame,
      expectedAction: action,
      expectedTransactionId: transactionId,
    );
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
      ),
    );
    return decodeFileList(response.frame);
  }

  @override
  Future<DeviceFileMetadata> readFileMetadata(List<int> nameSlot) async {
    _validateNameSlot(nameSlot);
    final content = [0x01, 0x11, ...nameSlot];
    final response = await commands.execute(
      EvtCommandRequest(
        command: 0x26,
        content: content,
        writeCharacteristic: _characteristic(BleLogicalEndpoint.ff10Ff16),
        expectedResponseCommand: 0xA6,
        expectedSubCommand: 0x01,
      ),
    );
    return decodeFileMetadata(response.frame);
  }

  Future<int> confirmArchive({
    required List<int> nameSlot,
    required int fileSize,
    required int crc32,
  }) async {
    _validateNameSlot(nameSlot);
    if (fileSize < 0 || fileSize > 0xFFFFFFFF) {
      throw RangeError.range(fileSize, 0, 0xFFFFFFFF);
    }
    if (crc32 < 0 || crc32 > 0xFFFFFFFF) {
      throw RangeError.range(crc32, 0, 0xFFFFFFFF);
    }
    final writer = ProtocolWriter()
      ..addAll(nameSlot)
      ..u32Le(fileSize)
      ..u32Le(crc32)
      ..u8(1);
    final response = await commands.execute(
      EvtCommandRequest(
        command: 0x26,
        content: [0x02, writer.bytes.length, ...writer.bytes],
        writeCharacteristic: _characteristic(BleLogicalEndpoint.ff10Ff16),
        expectedResponseCommand: 0xA6,
        expectedSubCommand: 0x02,
      ),
    );
    final content = response.frame.content;
    if (content.length != 4 || content[0] != 0x02 || content[1] != 0) {
      throw const FormatException('设备归档确认响应无效。');
    }
    if (content[2] != 1) {
      throw const FormatException('设备归档确认数据长度无效。');
    }
    return content[3];
  }

  @override
  Future<Uint8List> readFileChunk({
    required List<int> nameSlot,
    int startOffset = 0,
    int chunkSize = 0,
  }) async {
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
    final response = await commands.execute(
      EvtCommandRequest(
        command: 0x23,
        content: writer.bytes,
        writeCharacteristic: _characteristic(BleLogicalEndpoint.ff10Ff13),
        expectedResponseCommand: 0x23,
      ),
    );
    final reader = ProtocolReader(response.frame.content);
    final offset = reader.u32Le(0);
    final length = reader.u16Le(4);
    if (response.frame.content.length != 6 + length || offset != startOffset) {
      throw FormatException('文件数据 offset 或长度不连续。');
    }
    return Uint8List.fromList(response.frame.content.sublist(6));
  }

  static DeviceInfo decodeDeviceInfo(EvtFrame frame) {
    _expectCommand(frame, 0x81);
    final reader = ProtocolReader(frame.content);
    if (frame.content.length < 90) {
      throw const FormatException('设备信息字段长度不足。');
    }
    final protocolVersion = reader.u8(0);
    final deviceCode = _paddedText(frame.content, 1, 20);
    final software = _paddedText(frame.content, 21, 8);
    final hardware = _paddedText(frame.content, 29, 8);
    final name = _paddedText(frame.content, 45, 29);
    final total = reader.u32Le(74);
    final remain = reader.u32Le(78);
    final reserved = reader.u8(82);
    final recordOffset = reserved == 0 ? 83 : 113;
    if (frame.content.length <= recordOffset) {
      throw const FormatException('设备信息缺少录音状态。');
    }
    final recordStatus = reader.u8(recordOffset);
    final tail = recordStatus == 0
        ? recordOffset + 1 + 6
        : recordOffset + 8 + 6;
    if (frame.content.length < tail) {
      throw const FormatException('设备信息缺少电量或录音参数。');
    }
    final batteryOffset = recordStatus == 0
        ? recordOffset + 1
        : recordOffset + 8;
    return DeviceInfo(
      capabilities: DeviceCapabilities(protocolVersion: protocolVersion),
      deviceCode: deviceCode,
      softwareVersion: software,
      hardwareVersion: hardware,
      deviceName: name,
      totalDiskSpaceMb: total,
      remainDiskSpaceMb: remain,
      recordStatus: recordStatus,
      batteryLevel: reader.u8(batteryOffset),
      charging: reader.u8(batteryOffset + 1),
      audioStreamEnabled: reader.u8(batteryOffset + 5) != 0,
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
    return DeviceStatus(
      privacy: reader.u8(3) != 0,
      privacyRemainingMinutes: reader.u16Le(4),
      recordConsent: reader.u8(6) != 0,
      syncState: reader.u8(7),
    );
  }

  static DeviceBattery decodeBattery(EvtFrame frame) {
    _expectCommand(frame, 0x91);
    if (frame.content.length != 3 || frame.content[0] > 100) {
      throw const FormatException('设备电池状态无效。');
    }
    return DeviceBattery(
      percent: frame.content[0],
      isCharging: frame.content[1] != 0,
      chargingMode: frame.content[2],
    );
  }

  static DeviceStorage decodeStorage(EvtFrame frame) {
    _expectCommand(frame, 0x85);
    if (frame.content.length != 8) {
      throw const FormatException('设备存储状态长度无效。');
    }
    final reader = ProtocolReader(frame.content);
    return DeviceStorage(
      totalMegabytes: reader.u32Le(0),
      freeMegabytes: reader.u32Le(4),
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
    if (frame.content.length != 1 + count * 21) {
      throw const FormatException('文件列表长度无效。');
    }
    return [
      for (var index = 0; index < count; index += 1) _decodeFile(reader, index),
    ];
  }

  static DeviceFileMetadata decodeFileMetadata(EvtFrame frame) {
    _expectCommand(frame, 0xA6);
    if (frame.content.length < 4 ||
        frame.content[0] != 0x01 ||
        frame.content[1] != 0) {
      throw const FormatException('文件元数据响应无效。');
    }
    final dataLength = frame.content[2];
    if (dataLength != 45 || frame.content.length != 3 + dataLength) {
      throw const FormatException('文件元数据长度无效。');
    }
    final data = ProtocolReader(frame.content.sublist(3));
    return DeviceFileMetadata(
      name: data.asciiSlot17(0),
      nameSlot: List.unmodifiable(data.bytes.sublist(0, 17)),
      startUtc: DateTime.fromMillisecondsSinceEpoch(
        data.u32Le(17) * 1000,
        isUtc: true,
      ),
      durationSeconds: data.u32Le(21),
      recordingSessionId: data.u32Le(25),
      segmentIndex: data.u16Le(29),
      clockQuality: data.u8(31),
      utcCorrectionMilliseconds: data.s32Le(32),
      length: data.u32Le(36),
      crc32: data.u32Le(40),
      state: data.u8(44),
    );
  }

  static DeviceSecurityResponse decodeSecurityResponse(
    EvtFrame frame, {
    required DeviceAuthAction expectedAction,
    required int expectedTransactionId,
  }) {
    _expectCommand(frame, 0x89);
    final reader = ProtocolReader(frame.content);
    if (frame.content.length < 9 ||
        reader.u8(0) != 0xF2 ||
        reader.u8(1) != expectedAction.wireValue ||
        reader.u32Le(2) != expectedTransactionId) {
      throw const FormatException('认证响应与当前事务不匹配。');
    }
    final result = reader.u8(6);
    final length = reader.u16Le(7);
    if (frame.content.length != 9 + length || (result != 0 && length != 0)) {
      throw const FormatException('认证响应长度无效。');
    }
    return DeviceSecurityResponse(
      action: expectedAction,
      transactionId: expectedTransactionId,
      result: result,
      data: frame.content.sublist(9),
    );
  }

  Future<Uint8List> _readFrame(
    BleLogicalEndpoint endpoint, {
    required int expectedCommand,
  }) async {
    final bytes = await transport.read(_characteristic(endpoint));
    final result = codec.decode(bytes);
    if (!result.isSuccess || result.value!.command != expectedCommand) {
      throw FormatException(
        '设备读取响应 CMD 不匹配：0x${expectedCommand.toRadixString(16)}',
      );
    }
    return Uint8List.fromList(bytes);
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
        content: [subCommand, ...data],
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

  static String _paddedText(List<int> bytes, int offset, int length) {
    final value = bytes.sublist(offset, offset + length);
    final end = value.indexOf(0);
    return String.fromCharCodes(end < 0 ? value : value.sublist(0, end));
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

  static bool _matchesAuthenticationResponse(
    EvtFrame frame, {
    required DeviceAuthAction action,
    required int transactionId,
  }) {
    if (frame.command != 0x89 || frame.content.length < 9) {
      return false;
    }
    final reader = ProtocolReader(frame.content);
    return reader.u8(0) == 0xF2 &&
        reader.u8(1) == action.wireValue &&
        reader.u32Le(2) == transactionId &&
        frame.content.length == 9 + reader.u16Le(7);
  }
}
