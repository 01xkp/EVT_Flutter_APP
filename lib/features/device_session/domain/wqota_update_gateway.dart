import 'dart:typed_data';

import 'package:aipin/features/device_session/domain/firmware_package.dart';

class WqotaTransferWindow {
  const WqotaTransferWindow({required this.offset, required this.length});

  final int offset;
  final int length;
}

enum WqotaImageVerificationState { syncing, verified, unavailable }

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
