import 'dart:typed_data';

import 'package:aipin/features/device_session/domain/firmware_package.dart';

class WqotaTransferWindow {
  const WqotaTransferWindow({required this.offset, required this.length});

  /// Offset in the complete image, including the 18-byte WQOTA image header.
  final int offset;
  final int length;

  bool get isTerminal => length == 0;
}

/// A command was understood but left the device in a known-invalid WQOTA
/// update state. The controller may send E4 for this class of error only;
/// connection loss and transport timeouts deliberately do not implement it.
abstract interface class WqotaUpdateAbortException implements Exception {}

enum WqotaImageVerificationState { syncing, verified, unavailable }

/// The BLE-specific adapter for the WQOTA DVT controller.
abstract interface class WqotaUpdateGateway {
  Future<void> prepareTransport();

  Future<WqotaDeviceIdentity> readDeviceIdentity();

  Future<WqotaTransferWindow> queryFileInfoOffset();

  Future<void> inquireIfCanUpdate(Uint8List header);

  Future<WqotaTransferWindow> enterUpdateMode();

  Future<WqotaTransferWindow> transferWindow({
    required int offset,
    required Uint8List bytes,
  });

  Future<void> refresh();

  Future<WqotaImageVerificationState> readImageVerificationState();

  Future<void> reboot();

  Future<void> exitUpdateMode();

  Future<bool> verifyBusinessVersion(String expectedBusinessVersion);
}
