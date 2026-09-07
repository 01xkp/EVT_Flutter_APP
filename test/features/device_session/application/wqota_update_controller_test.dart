import 'dart:typed_data';

import 'package:aipin/features/device_session/application/wqota_update_controller.dart';
import 'package:aipin/features/device_session/domain/firmware_package.dart';
import 'package:aipin/features/device_session/domain/firmware_update_checkpoint.dart';
import 'package:aipin/features/device_session/domain/wqota_update_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'uses the V1.5 WQOTA sequence and waits for reconnect verification',
    () async {
      final gateway = _Gateway();
      final checkpoints = _Checkpoints();
      final controller = WqotaUpdateController(
        gateway: gateway,
        checkpoints: checkpoints,
      );
      final package = FirmwarePackage(
        vendorId: 0x1234,
        productId: 0x5678,
        version: 2,
        expectedBusinessVersion: '1.0.2',
        payload: Uint8List.fromList(const [1, 2, 3]),
        expectedPayloadCrc32: 0x55BC801D,
        wqotaRequestPrefixFlags: const [0x70, 0x07, 0x6E, 0xC1],
        wqotaResponsePrefixFlags: const [0x70, 0x07, 0x6E, 0x01],
        wqotaFinalVerificationSupported: true,
      );

      await controller.start(deviceId: 'device-1', package: package);

      expect(controller.state.phase, WqotaUpdatePhase.awaitingReconnect);
      expect(gateway.operations, [
        'prepare',
        'info',
        'offset',
        'admit',
        'enter',
        'block:18:3',
        'refresh',
        'sync',
        'reboot',
      ]);
      expect(checkpoints.saved.single.offset, 21);

      await controller.verifyAfterReconnect();

      expect(controller.state.phase, WqotaUpdatePhase.completed);
      expect(gateway.operations.last, 'verify:1.0.2');
      expect(checkpoints.cleared, ['device-1']);
    },
  );

  test(
    'cancels an in-progress update and retains its checkpoint for resume',
    () async {
      final gateway = _Gateway(holdTransfer: true);
      final checkpoints = _Checkpoints();
      final controller = WqotaUpdateController(
        gateway: gateway,
        checkpoints: checkpoints,
      );
      final package = FirmwarePackage(
        vendorId: 0x1234,
        productId: 0x5678,
        version: 2,
        expectedBusinessVersion: '1.0.2',
        payload: Uint8List.fromList(const [1, 2, 3]),
        expectedPayloadCrc32: 0x55BC801D,
        wqotaRequestPrefixFlags: const [0x70, 0x07, 0x6E, 0xC1],
        wqotaResponsePrefixFlags: const [0x70, 0x07, 0x6E, 0x01],
        wqotaFinalVerificationSupported: true,
      );

      final start = controller.start(deviceId: 'device-1', package: package);
      await Future<void>.delayed(Duration.zero);
      await controller.cancel();
      await start;

      expect(controller.state.phase, WqotaUpdatePhase.cancelled);
      expect(gateway.operations, contains('exit'));
      expect(checkpoints.cleared, isEmpty);
    },
  );

  test('exits update mode when a transfer fails after E3', () async {
    final gateway = _Gateway(failTransfer: true);
    final controller = WqotaUpdateController(
      gateway: gateway,
      checkpoints: _Checkpoints(),
    );
    final package = FirmwarePackage(
      vendorId: 0x1234,
      productId: 0x5678,
      version: 2,
      expectedBusinessVersion: '1.0.2',
      payload: Uint8List.fromList(const [1, 2, 3]),
      expectedPayloadCrc32: 0x55BC801D,
      wqotaRequestPrefixFlags: const [0x70, 0x07, 0x6E, 0xC1],
      wqotaResponsePrefixFlags: const [0x70, 0x07, 0x6E, 0x01],
      wqotaFinalVerificationSupported: true,
    );

    await expectLater(
      controller.start(deviceId: 'device-1', package: package),
      throwsStateError,
    );

    expect(controller.state.phase, WqotaUpdatePhase.failed);
    expect(gateway.operations, [
      'prepare',
      'info',
      'offset',
      'admit',
      'enter',
      'block:18:3',
      'exit',
    ]);
  });

  test('does not exit update mode when E3 did not enter it', () async {
    final gateway = _Gateway(failEnter: true);
    final controller = WqotaUpdateController(
      gateway: gateway,
      checkpoints: _Checkpoints(),
    );
    final package = FirmwarePackage(
      vendorId: 0x1234,
      productId: 0x5678,
      version: 2,
      expectedBusinessVersion: '1.0.2',
      payload: Uint8List.fromList(const [1, 2, 3]),
      expectedPayloadCrc32: 0x55BC801D,
      wqotaRequestPrefixFlags: const [0x70, 0x07, 0x6E, 0xC1],
      wqotaResponsePrefixFlags: const [0x70, 0x07, 0x6E, 0x01],
      wqotaFinalVerificationSupported: true,
    );

    await expectLater(
      controller.start(deviceId: 'device-1', package: package),
      throwsStateError,
    );

    expect(controller.state.phase, WqotaUpdatePhase.failed);
    expect(gateway.operations, ['prepare', 'info', 'offset', 'admit', 'enter']);
  });

  test('does not reboot after an unverified E8 idle state', () async {
    final gateway = _Gateway(
      verificationState: WqotaImageVerificationState.unavailable,
    );
    final controller = WqotaUpdateController(
      gateway: gateway,
      checkpoints: _Checkpoints(),
    );
    final package = FirmwarePackage(
      vendorId: 0x1234,
      productId: 0x5678,
      version: 2,
      expectedBusinessVersion: '1.0.2',
      payload: Uint8List.fromList(const [1, 2, 3]),
      expectedPayloadCrc32: 0x55BC801D,
      wqotaRequestPrefixFlags: const [0x70, 0x07, 0x6E, 0xC1],
      wqotaResponsePrefixFlags: const [0x70, 0x07, 0x6E, 0x01],
      wqotaFinalVerificationSupported: true,
    );

    await expectLater(
      controller.start(deviceId: 'device-1', package: package),
      throwsStateError,
    );

    expect(controller.state.phase, WqotaUpdatePhase.failed);
    expect(gateway.operations, isNot(contains('reboot')));
    expect(gateway.operations, contains('exit'));
  });
}

class _Gateway implements WqotaUpdateGateway {
  _Gateway({
    this.holdTransfer = false,
    this.failTransfer = false,
    this.failEnter = false,
    this.verificationState = WqotaImageVerificationState.verified,
  });

  final bool holdTransfer;
  final bool failTransfer;
  final bool failEnter;
  final WqotaImageVerificationState verificationState;
  final operations = <String>[];

  @override
  Future<void> prepareTransport() async => operations.add('prepare');

  @override
  Future<WqotaDeviceIdentity> readDeviceIdentity() async {
    operations.add('info');
    return const WqotaDeviceIdentity(0x1234, 0x5678);
  }

  @override
  Future<WqotaTransferWindow> queryFileInfoOffset() async {
    operations.add('offset');
    return const WqotaTransferWindow(offset: 0, length: 18);
  }

  @override
  Future<void> inquireIfCanUpdate(Uint8List header) async {
    operations.add('admit');
  }

  @override
  Future<WqotaTransferWindow> enterUpdateMode() async {
    operations.add('enter');
    if (failEnter) {
      throw StateError('simulated enter failure');
    }
    return const WqotaTransferWindow(offset: 18, length: 3);
  }

  @override
  Future<WqotaTransferWindow> transferWindow({
    required int offset,
    required Uint8List bytes,
  }) async {
    operations.add('block:$offset:${bytes.length}');
    if (holdTransfer) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (failTransfer) {
      throw StateError('simulated transfer failure');
    }
    return const WqotaTransferWindow(offset: 0, length: 0);
  }

  @override
  Future<void> refresh() async => operations.add('refresh');

  @override
  Future<WqotaImageVerificationState> readImageVerificationState() async {
    operations.add('sync');
    return verificationState;
  }

  @override
  Future<void> reboot() async => operations.add('reboot');

  @override
  Future<void> exitUpdateMode() async => operations.add('exit');

  @override
  Future<bool> verifyBusinessVersion(String expectedBusinessVersion) async {
    operations.add('verify:$expectedBusinessVersion');
    return true;
  }
}

class _Checkpoints implements FirmwareUpdateCheckpointRepository {
  final saved = <FirmwareUpdateCheckpoint>[];
  final cleared = <String>[];

  @override
  Future<void> clear(String deviceId) async => cleared.add(deviceId);

  @override
  Future<FirmwareUpdateCheckpoint?> find(String deviceId) async => null;

  @override
  Future<void> save(FirmwareUpdateCheckpoint checkpoint) async {
    saved.add(checkpoint);
  }
}
