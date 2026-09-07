import 'dart:typed_data';

class DeviceClearCheckpoint {
  DeviceClearCheckpoint({
    required this.deviceId,
    required this.transactionId,
    required this.expectedBindingGeneration,
    required List<int> confirmNonce,
    required this.clearScope,
  }) : confirmNonce = Uint8List.fromList(confirmNonce) {
    if (transactionId < 0 || transactionId > 0xFFFFFFFF) {
      throw RangeError.range(transactionId, 0, 0xFFFFFFFF, 'transactionId');
    }
    if (expectedBindingGeneration < 0 ||
        expectedBindingGeneration > 0xFFFFFFFF) {
      throw RangeError.range(
        expectedBindingGeneration,
        0,
        0xFFFFFFFF,
        'expectedBindingGeneration',
      );
    }
    if (this.confirmNonce.length != 16) {
      throw const FormatException('设备清除确认 nonce 必须为 16 字节。');
    }
    if (clearScope < 0 || clearScope > 0xFFFFFFFF) {
      throw RangeError.range(clearScope, 0, 0xFFFFFFFF, 'clearScope');
    }
  }

  final String deviceId;
  final int transactionId;
  final int expectedBindingGeneration;
  final Uint8List confirmNonce;
  final int clearScope;
}

abstract interface class DeviceClearCheckpointRepository {
  Future<DeviceClearCheckpoint?> find(String deviceId);

  Future<void> save(DeviceClearCheckpoint checkpoint);

  Future<void> clear(String deviceId);
}
