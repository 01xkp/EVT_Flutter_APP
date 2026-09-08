import 'dart:typed_data';

/// It maps only to `0x23`: App supplies the exact 17-byte name slot returned
/// by `0x22`, receives contiguous data, and stores it locally. The terminal
/// event represents the protocol-required zero-length 0x23 frame. No other
/// file operation is exposed through this build's transfer gateway.
abstract interface class DeviceFileTransferGateway {
  Stream<EvtDeviceFileTransferEvent> downloadEvtFile({
    required List<int> nameSlot,
    int startOffset,
    int chunkSize,
  });
}

/// One decoded EVT 0x23 transfer frame.
///
/// A data frame always has bytes. A terminal event is emitted only after the
/// firmware's zero-length data frame has passed offset and frame validation.
final class EvtDeviceFileTransferEvent {
  EvtDeviceFileTransferEvent.data(Uint8List data)
    : bytes = Uint8List.fromList(data),
      isTerminal = false {
    if (data.isEmpty) {
      throw ArgumentError.value(data, 'data', '数据帧不能为空。');
    }
  }

  EvtDeviceFileTransferEvent.terminal()
    : bytes = Uint8List(0),
      isTerminal = true;

  final Uint8List bytes;
  final bool isTerminal;
}
