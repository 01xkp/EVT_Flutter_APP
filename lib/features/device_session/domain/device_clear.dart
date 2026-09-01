import 'dart:typed_data';

const fullUserClearScope = 0x3F;

class DeviceClearPreparation {
  DeviceClearPreparation({
    required this.pendingFiles,
    required List<int> confirmNonce,
    required this.pendingBytes,
    required this.effectiveClearScope,
    required this.riskFlags,
    required this.prepareTtlSeconds,
  }) : confirmNonce = Uint8List.fromList(confirmNonce);

  final int pendingFiles;
  final Uint8List confirmNonce;
  final int pendingBytes;
  final int effectiveClearScope;
  final int riskFlags;
  final int prepareTtlSeconds;

  factory DeviceClearPreparation.fromResponse(List<int> data) {
    if (data.length != 29) {
      throw const FormatException('设备清除预检查响应长度无效。');
    }
    return DeviceClearPreparation(
      pendingFiles: _u16Le(data, 0),
      confirmNonce: data.sublist(2, 18),
      pendingBytes: _u32Le(data, 18),
      effectiveClearScope: _u32Le(data, 22),
      riskFlags: data[26],
      prepareTtlSeconds: _u16Le(data, 27),
    );
  }
}

enum DeviceClearProgressState {
  prepared(1),
  clearing(2),
  done(3),
  failed(4);

  const DeviceClearProgressState(this.wireValue);

  final int wireValue;

  static DeviceClearProgressState fromWireValue(int value) {
    return DeviceClearProgressState.values.firstWhere(
      (state) => state.wireValue == value,
      orElse: () => throw FormatException('未知的设备清除状态：$value。'),
    );
  }
}

class DeviceClearStatus {
  const DeviceClearStatus({
    required this.progress,
    required this.finalResult,
    required this.state,
    required this.finalMode,
    required this.clearedScope,
    required this.stage,
  });

  final int progress;
  final int finalResult;
  final DeviceClearProgressState state;
  final int finalMode;
  final int clearedScope;
  final int stage;

  factory DeviceClearStatus.fromResponse(List<int> data) {
    if (data.length != 9 || data[0] > 100) {
      throw const FormatException('设备清除状态响应无效。');
    }
    return DeviceClearStatus(
      progress: data[0],
      finalResult: data[1],
      state: DeviceClearProgressState.fromWireValue(data[2]),
      finalMode: data[3],
      clearedScope: _u32Le(data, 4),
      stage: data[8],
    );
  }
}

int _u16Le(List<int> data, int offset) =>
    data[offset] | (data[offset + 1] << 8);

int _u32Le(List<int> data, int offset) =>
    data[offset] |
    (data[offset + 1] << 8) |
    (data[offset + 2] << 16) |
    (data[offset + 3] << 24);
