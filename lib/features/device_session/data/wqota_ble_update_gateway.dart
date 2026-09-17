import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:aipin/core/protocol/crc32.dart';
import 'package:aipin/core/protocol/wqota_client.dart';
import 'package:aipin/core/protocol/wqota_codec.dart';
import 'package:aipin/features/device_session/domain/firmware_package.dart';
import 'package:aipin/features/device_session/domain/wqota_update_gateway.dart';

class WqotaProtocolException implements Exception, WqotaUpdateAbortException {
  const WqotaProtocolException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Maps V1.6 WQOTA opcode payloads to the generic [WqotaUpdateGateway].
class WqotaBleUpdateGateway implements WqotaUpdateGateway {
  // E2 is a 27-byte characteristic value. ATT reserves three bytes for the
  // opcode and attribute handle, so it needs an ATT MTU of at least 30.
  static const minimumTransportMtu = 30;
  static const _maximumFrameBytes = 672;
  static const _imageHeaderBytes = 18;

  WqotaBleUpdateGateway({
    required this.client,
    required this.requestMtu,
    required this._verifyBusinessVersion,
    required this.finalVerificationSupported,
    Future<void> Function(Duration delay)? delay,
    int? maximumBlockBytes,
  }) : _delay = delay ?? Future<void>.delayed,
       // ignore: prefer_initializing_formals
       _maximumBlockBytes = maximumBlockBytes {
    if (maximumBlockBytes != null &&
        (maximumBlockBytes < 1 || maximumBlockBytes > 655)) {
      throw RangeError.range(maximumBlockBytes, 1, 655, 'maximumBlockBytes');
    }
  }

  final WqotaClient client;
  final Future<int> Function() requestMtu;
  final Future<bool> Function(String expectedBusinessVersion)
  _verifyBusinessVersion;
  final bool finalVerificationSupported;
  final Future<void> Function(Duration delay) _delay;
  int? _maximumBlockBytes;
  var _serialNumber = 0;

  /// V1.6: E5's complete frame is N + 17 and the target pool caps complete
  /// frames at 672 bytes, while the ATT payload capacity is MTU - 3.
  static int maximumBlockBytesForMtu(int mtu) {
    if (mtu < 23) {
      throw RangeError.range(mtu, 23, null, 'mtu');
    }
    return min(655, min(_maximumFrameBytes - 17, mtu - 20));
  }

  @override
  Future<void> prepareTransport() async {
    if (_maximumBlockBytes != null) {
      return;
    }
    final mtu = await requestMtu();
    if (mtu < minimumTransportMtu) {
      throw WqotaProtocolException(
        'WQOTA requires ATT MTU >= $minimumTransportMtu; got $mtu.',
      );
    }
    _maximumBlockBytes = maximumBlockBytesForMtu(mtu);
  }

  @override
  Future<WqotaDeviceIdentity> readDeviceIdentity() async {
    // Request VERSION and VID/PID. The package validates the target VID/PID
    // before E2 sends any image header.
    final response = await _execute(WqotaOpcode.getDeviceInfo, <int>[
      _nextSerial(),
      0,
      0,
      0,
      0x03,
    ]);
    final data = _successData(response, minimumLength: 2);
    if (data.length > 34) {
      throw const WqotaProtocolException(
        'WQOTA GET_DEVICE_INFO TLV exceeds 32 bytes.',
      );
    }
    var offset = 2;
    int? vendorId;
    int? productId;
    while (offset < data.length) {
      final itemLength = data[offset];
      if (itemLength < 1 || offset + 1 + itemLength > data.length) {
        throw const WqotaProtocolException(
          'WQOTA GET_DEVICE_INFO TLV length is invalid.',
        );
      }
      final type = data[offset + 1];
      if (type == 0x01 && itemLength == 5) {
        vendorId = _u16Be(data, offset + 2);
        productId = _u16Be(data, offset + 4);
      }
      offset += itemLength + 1;
    }
    if (vendorId == null || productId == null) {
      throw const WqotaProtocolException(
        'WQOTA GET_DEVICE_INFO did not return VID/PID.',
      );
    }
    return WqotaDeviceIdentity(vendorId: vendorId, productId: productId);
  }

  @override
  Future<WqotaTransferWindow> queryFileInfoOffset() async {
    final data = _successData(
      await _execute(WqotaOpcode.getFileInfoOffset, <int>[_nextSerial()]),
      exactLength: 8,
    );
    final window = WqotaTransferWindow(
      offset: _u32Be(data, 2),
      length: _u16Be(data, 6),
    );
    if (window.offset != 0 || window.length != _imageHeaderBytes) {
      throw const WqotaProtocolException(
        'WQOTA E1 must return the fixed 0/18 image-header window.',
      );
    }
    return window;
  }

  @override
  Future<void> inquireIfCanUpdate(Uint8List header) async {
    if (header.length != _imageHeaderBytes) {
      throw const WqotaProtocolException(
        'WQOTA E2 requires an 18-byte image header.',
      );
    }
    final data = _successData(
      await _execute(WqotaOpcode.inquiryIfCanUpdate, <int>[
        _nextSerial(),
        ...header,
      ]),
      exactLength: 3,
    );
    if (data[2] != 0x03) {
      throw WqotaProtocolException(
        'WQOTA E2 rejected the image with result 0x${data[2].toRadixString(16).padLeft(2, '0')}.',
      );
    }
  }

  @override
  Future<WqotaTransferWindow> enterUpdateMode() async {
    final data = _successData(
      await _execute(WqotaOpcode.enterUpdateMode, <int>[_nextSerial()]),
      exactLength: 10,
    );
    if (data[2] != 0 || data[9] != 1) {
      throw WqotaProtocolException(
        'WQOTA E3 did not enter a CRC-checked update mode (result=0x${data[2].toRadixString(16)} need_crc=${data[9]}).',
      );
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
    if (offset < _imageHeaderBytes || bytes.isEmpty) {
      throw const WqotaProtocolException('WQOTA E5 window is invalid.');
    }
    final maximumBlockBytes = _maximumBlockBytes;
    if (maximumBlockBytes == null) {
      throw const WqotaProtocolException('WQOTA MTU has not been prepared.');
    }

    final blockCount = (bytes.length / maximumBlockBytes).ceil();
    final finalSerial = (_serialNumber + blockCount) & 0xFF;
    // Register before the first write. Firmware may queue the window response
    // immediately after receiving the final E5 block.
    final response = client.waitForNotification(
      opcode: WqotaOpcode.sendFirmwareBlock,
      serialNumber: finalSerial,
    );
    Object? responseError;
    StackTrace? responseStackTrace;
    unawaited(
      response.future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          responseError = error;
          responseStackTrace = stackTrace;
        },
      ),
    );
    try {
      for (var cursor = 0; cursor < bytes.length;) {
        // A response timeout/closed Notify stream may happen while a native
        // write is in flight. Do not submit any further blocks after it; the
        // caller preserves the last confirmed checkpoint for recovery.
        if (responseError case final error?) {
          Error.throwWithStackTrace(error, responseStackTrace!);
        }
        final end = min(cursor + maximumBlockBytes, bytes.length);
        final block = bytes.sublist(cursor, end);
        final crc32 = Crc32IsoHdlc.calculate(block);
        await client.sendWithoutResponse(
          opcode: WqotaOpcode.sendFirmwareBlock,
          data: <int>[
            _nextSerial(),
            ..._u32BeBytes(offset + cursor),
            ...block,
            ..._u32BeBytes(crc32),
          ],
        );
        cursor = end;
      }
    } catch (error, stackTrace) {
      // The wait is registered before the first block to avoid a fast final
      // E5 response race. A failed write invalidates that wait immediately.
      response.cancel(error: error, stackTrace: stackTrace);
      rethrow;
    }

    final data = _successData((await response.future).data, exactLength: 11);
    if (data[2] != 0) {
      throw WqotaProtocolException(
        'WQOTA E5 rejected the window with result 0x${data[2].toRadixString(16).padLeft(2, '0')}.',
      );
    }
    final delayMs = _u16Be(data, 9);
    if (delayMs > 0) {
      await _delay(Duration(milliseconds: delayMs));
    }
    return WqotaTransferWindow(
      offset: _u32Be(data, 3),
      length: _u16Be(data, 7),
    );
  }

  @override
  Future<void> refresh() async {
    final data = _successData(
      await _execute(WqotaOpcode.getRefreshStatus, <int>[_nextSerial()]),
      exactLength: 3,
    );
    if (data[2] != 0) {
      throw WqotaProtocolException(
        'WQOTA E6 failed with result 0x${data[2].toRadixString(16).padLeft(2, '0')}.',
      );
    }
  }

  @override
  Future<WqotaImageVerificationState> readImageVerificationState() async {
    final data = _successData(
      await _execute(WqotaOpcode.getSyncState, <int>[_nextSerial()]),
      exactLength: 3,
    );
    return switch (data[2]) {
      1 => WqotaImageVerificationState.syncing,
      0 when finalVerificationSupported => WqotaImageVerificationState.verified,
      0 => WqotaImageVerificationState.unavailable,
      final state => throw WqotaProtocolException(
        'WQOTA E8 returned unknown state 0x${state.toRadixString(16).padLeft(2, '0')}.',
      ),
    };
  }

  @override
  Future<void> reboot() async {
    _successData(
      await _execute(WqotaOpcode.reboot, <int>[_nextSerial(), 0]),
      exactLength: 2,
    );
  }

  @override
  Future<void> exitUpdateMode() async {
    final data = _successData(
      await _execute(WqotaOpcode.exitUpdateMode, <int>[_nextSerial()]),
      exactLength: 3,
    );
    if (data[2] != 0) {
      throw WqotaProtocolException(
        'WQOTA E4 failed with result 0x${data[2].toRadixString(16).padLeft(2, '0')}.',
      );
    }
  }

  @override
  Future<bool> verifyBusinessVersion(String expectedBusinessVersion) =>
      _verifyBusinessVersion(expectedBusinessVersion);

  Future<Uint8List> _execute(WqotaOpcode opcode, List<int> data) async {
    final response = await client.execute(
      opcode: opcode,
      data: data,
      serialNumber: data.first,
    );
    return response.data;
  }

  static Uint8List _successData(
    Uint8List data, {
    int? exactLength,
    int? minimumLength,
  }) {
    if (data.length < 2) {
      throw const WqotaProtocolException(
        'WQOTA response is shorter than status and serial.',
      );
    }
    if (data[0] != 0) {
      throw WqotaProtocolException(
        'WQOTA command failed with status 0x${data[0].toRadixString(16).padLeft(2, '0')}.',
      );
    }
    if (exactLength != null && data.length != exactLength) {
      throw WqotaProtocolException(
        'WQOTA response length is ${data.length}; expected $exactLength.',
      );
    }
    if (minimumLength != null && data.length < minimumLength) {
      throw WqotaProtocolException(
        'WQOTA response length is ${data.length}; expected at least $minimumLength.',
      );
    }
    return data;
  }

  int _nextSerial() {
    _serialNumber = (_serialNumber + 1) & 0xFF;
    return _serialNumber;
  }

  static int _u16Be(List<int> value, int offset) =>
      (value[offset] << 8) | value[offset + 1];

  static int _u32Be(List<int> value, int offset) =>
      (value[offset] << 24) |
      (value[offset + 1] << 16) |
      (value[offset + 2] << 8) |
      value[offset + 3];

  static List<int> _u32BeBytes(int value) => <int>[
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ];
}
