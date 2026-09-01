import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/core/protocol/crc32.dart';
import 'package:aipin/core/protocol/wqota_client.dart';
import 'package:aipin/core/protocol/wqota_codec.dart';
import 'package:aipin/features/device_session/domain/firmware_package.dart';
import 'package:aipin/features/device_session/domain/wqota_update_gateway.dart';

class WqotaBleUpdateGateway implements WqotaUpdateGateway {
  WqotaBleUpdateGateway({
    required this.client,
    required this.verifyBusinessVersionCallback,
    this.maximumBlockBytes = 497,
  });

  final WqotaClient client;
  final Future<bool> Function(String expectedBusinessVersion)
  verifyBusinessVersionCallback;
  final int maximumBlockBytes;
  var _serialNumber = 0;

  @override
  Future<WqotaDeviceIdentity> readDeviceIdentity() async {
    final response = await _execute(WqotaOpcode.getDeviceInfo, [
      _nextSerial(),
      0,
      0,
      0,
      0x03,
    ]);
    final data = _successData(response, exactLength: null);
    var offset = 2;
    int? vendorId;
    int? productId;
    while (offset < data.length) {
      final itemLength = data[offset];
      if (itemLength < 1 || offset + 1 + itemLength > data.length) {
        throw const FormatException('WQOTA 设备能力 TLV 长度无效。');
      }
      final type = data[offset + 1];
      if (type == 0x01 && itemLength == 5) {
        vendorId = (data[offset + 2] << 8) | data[offset + 3];
        productId = (data[offset + 4] << 8) | data[offset + 5];
      }
      offset += itemLength + 1;
    }
    if (vendorId == null || productId == null) {
      throw const FormatException('WQOTA 设备能力未返回 VID/PID。');
    }
    return WqotaDeviceIdentity(vendorId, productId);
  }

  @override
  Future<WqotaTransferWindow> queryFileInfoOffset() async {
    final response = await _execute(WqotaOpcode.getFileInfoOffset, [
      _nextSerial(),
    ]);
    final data = _successData(response, exactLength: 8);
    return WqotaTransferWindow(
      offset: _u32Be(data, 2),
      length: _u16Be(data, 6),
    );
  }

  @override
  Future<void> inquireIfCanUpdate(Uint8List header) async {
    if (header.length != 18) {
      throw const FormatException('WQOTA 镜像头必须为 18 字节。');
    }
    final response = await _execute(WqotaOpcode.inquiryIfCanUpdate, [
      _nextSerial(),
      ...header,
    ]);
    final data = _successData(response, exactLength: 3);
    if (data[2] != 0x03) {
      throw StateError('设备拒绝升级，结果码：0x${data[2].toRadixString(16)}');
    }
  }

  @override
  Future<WqotaTransferWindow> enterUpdateMode() async {
    final response = await _execute(WqotaOpcode.enterUpdateMode, [
      _nextSerial(),
    ]);
    final data = _successData(response, exactLength: 10);
    if (data[2] != 0 || data[9] != 1) {
      throw StateError('设备未进入可校验的升级模式。');
    }
    return WqotaTransferWindow(
      offset: _u32Be(data, 3),
      length: _u16Be(data, 7),
    );
  }

  @override
  Future<WqotaTransferWindow> transferWindow({
    required int offset,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      throw const FormatException('WQOTA 升级窗口不能为空。');
    }
    final blockCount = (bytes.length / maximumBlockBytes).ceil();
    final lastSerial = (_serialNumber + blockCount) & 0xFF;
    final response = client.waitForNotification(
      opcode: WqotaOpcode.sendFirmwareBlock,
      serialNumber: lastSerial,
    );
    for (var cursor = 0; cursor < bytes.length;) {
      final end = (cursor + maximumBlockBytes).clamp(0, bytes.length);
      final block = bytes.sublist(cursor, end);
      final serial = _nextSerial();
      final crc = Crc32IsoHdlc.calculate(block);
      await client.sendWithoutResponse(
        opcode: WqotaOpcode.sendFirmwareBlock,
        data: [
          serial,
          ((offset + cursor) >> 24) & 0xFF,
          ((offset + cursor) >> 16) & 0xFF,
          ((offset + cursor) >> 8) & 0xFF,
          (offset + cursor) & 0xFF,
          ...block,
          (crc >> 24) & 0xFF,
          (crc >> 16) & 0xFF,
          (crc >> 8) & 0xFF,
          crc & 0xFF,
        ],
      );
      cursor = end;
    }
    final data = _successData((await response).data, exactLength: 11);
    if (data[2] != 0) {
      throw StateError('设备拒绝升级窗口，结果码：0x${data[2].toRadixString(16)}');
    }
    final delay = _u16Be(data, 9);
    if (delay > 0) {
      await Future<void>.delayed(Duration(milliseconds: delay));
    }
    return WqotaTransferWindow(
      offset: _u32Be(data, 3),
      length: _u16Be(data, 7),
    );
  }

  @override
  Future<void> refresh() async {
    final response = await _execute(WqotaOpcode.getRefreshStatus, [
      _nextSerial(),
    ]);
    _successData(response, exactLength: 3);
  }

  @override
  Future<bool> isSyncComplete() async {
    final response = await _execute(WqotaOpcode.getSyncState, [_nextSerial()]);
    final data = _successData(response, exactLength: 3);
    return data[2] == 0;
  }

  @override
  Future<void> reboot() async {
    final response = await _execute(WqotaOpcode.reboot, [_nextSerial(), 0]);
    _successData(response, exactLength: 2);
  }

  @override
  Future<void> exitUpdateMode() async {
    final response = await _execute(WqotaOpcode.exitUpdateMode, [
      _nextSerial(),
    ]);
    _successData(response, exactLength: 3);
  }

  @override
  Future<bool> verifyBusinessVersion(String expectedBusinessVersion) =>
      verifyBusinessVersionCallback(expectedBusinessVersion);

  Future<Uint8List> _execute(WqotaOpcode opcode, List<int> data) async =>
      (await client.execute(
        opcode: opcode,
        data: data,
        serialNumber: data.first,
      )).data;

  Uint8List _successData(Uint8List data, {required int? exactLength}) {
    if (data.length < 2 || data[0] != 0) {
      throw StateError('WQOTA 请求失败。');
    }
    if (exactLength != null && data.length != exactLength) {
      throw const FormatException('WQOTA 响应长度无效。');
    }
    return data;
  }

  int _nextSerial() {
    _serialNumber = (_serialNumber + 1) & 0xFF;
    return _serialNumber;
  }

  static int _u16Be(List<int> bytes, int offset) =>
      (bytes[offset] << 8) | bytes[offset + 1];

  static int _u32Be(List<int> bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}
