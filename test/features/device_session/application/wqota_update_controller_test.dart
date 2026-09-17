import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/core/protocol/wqota_client.dart';
import 'package:aipin/core/protocol/wqota_codec.dart';
import 'package:aipin/features/device_session/application/wqota_update_controller.dart';
import 'package:aipin/features/device_session/domain/firmware_package.dart';
import 'package:aipin/features/device_session/domain/firmware_update_checkpoint.dart';
import 'package:aipin/features/device_session/domain/wqota_update_gateway.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'runs the V1.6 WQOTA order and completes only after reconnect version check',
    () async {
      final gateway = _Gateway();
      final checkpoints = _Checkpoints();
      final controller = WqotaUpdateController(
        gateway: gateway,
        checkpoints: checkpoints,
        wait: (_) async {},
      );

      await controller.start(deviceId: 'device-1', package: _package());

      expect(controller.state.phase, WqotaUpdatePhase.awaitingReconnect);
      expect(gateway.operations, <String>[
        'prepare',
        'identity',
        'e1',
        'e2',
        'e3',
        'e5:18:3',
        'e6',
        'e8',
        'reboot',
      ]);
      expect(checkpoints.saved.last.nextOffset, 21);
      expect(checkpoints.saved.last.nextLength, 0);
      expect(checkpoints.saved.last.imageCrc32, 0x55BC801D);
      expect(
        checkpoints.saved.last.phase,
        FirmwareUpdateCheckpointPhase.awaitingReconnect,
      );
      expect(checkpoints.saved.last.expectedBusinessVersion, '1.0.2');

      await controller.verifyAfterReconnect();

      expect(controller.state.phase, WqotaUpdatePhase.completed);
      expect(gateway.operations.last, 'version:1.0.2');
      expect(checkpoints.cleared, <String>['device-1']);
    },
  );

  test('rejects a non-contiguous E5 response and exits update mode', () async {
    final gateway = _Gateway(
      nextWindow: const WqotaTransferWindow(offset: 19, length: 1),
    );
    final controller = WqotaUpdateController(
      gateway: gateway,
      checkpoints: _Checkpoints(),
      wait: (_) async {},
    );

    await expectLater(
      controller.start(deviceId: 'device-1', package: _package()),
      throwsA(isA<WqotaUpdateException>()),
    );

    expect(controller.state.phase, WqotaUpdatePhase.failed);
    expect(gateway.operations, contains('e4'));
  });

  test(
    'cancellation waits for the active E5 window before sending E4',
    () async {
      final completion = Completer<WqotaTransferWindow>();
      final gateway = _Gateway(transferCompletion: completion);
      final controller = WqotaUpdateController(
        gateway: gateway,
        checkpoints: _Checkpoints(),
        wait: (_) async {},
      );

      final start = controller.start(deviceId: 'device-1', package: _package());
      await Future<void>.delayed(Duration.zero);
      final cancel = controller.cancel();
      expect(gateway.operations, isNot(contains('e4')));

      completion.complete(const WqotaTransferWindow(offset: 0, length: 0));
      await cancel;
      await start;

      expect(controller.state.phase, WqotaUpdatePhase.cancelled);
      expect(gateway.operations.last, 'e4');
    },
  );

  test(
    'keeps the checkpoint and does not send E4 on WQOTA idle timeout',
    () async {
      final gateway = _Gateway(
        transferError: const WqotaIdleTimeoutException(
          opcode: WqotaOpcode.sendFirmwareBlock,
          serial: 1,
        ),
      );
      final checkpoints = _Checkpoints();
      final controller = WqotaUpdateController(
        gateway: gateway,
        checkpoints: checkpoints,
        wait: (_) async {},
      );

      await expectLater(
        controller.start(deviceId: 'device-1', package: _package()),
        throwsA(isA<WqotaIdleTimeoutException>()),
      );

      expect(controller.state.phase, WqotaUpdatePhase.failed);
      expect(gateway.operations, isNot(contains('e4')));
      expect(
        checkpoints.saved.last.phase,
        FirmwareUpdateCheckpointPhase.transferring,
      );
    },
  );

  test(
    'persists reconnect verification before a reboot acknowledgement is lost',
    () async {
      final gateway = _Gateway(rebootError: StateError('reboot link lost'));
      final checkpoints = _Checkpoints();
      final controller = WqotaUpdateController(
        gateway: gateway,
        checkpoints: checkpoints,
        wait: (_) async {},
      );

      await expectLater(
        controller.start(deviceId: 'device-1', package: _package()),
        throwsA(isA<StateError>()),
      );

      expect(controller.state.phase, WqotaUpdatePhase.failed);
      expect(gateway.operations.last, 'reboot');
      expect(gateway.operations, isNot(contains('e4')));
      expect(
        checkpoints.saved.last.phase,
        FirmwareUpdateCheckpointPhase.awaitingReconnect,
      );
    },
  );

  test(
    'restores a reconnect checkpoint before reading the business version',
    () async {
      final package = _package();
      final checkpoints = _Checkpoints();
      await checkpoints.save(
        FirmwareUpdateCheckpoint(
          deviceId: 'device-1',
          packageHash: sha256.convert(package.image).toString(),
          imageCrc32: package.expectedPayloadCrc32,
          packageVersion: package.version,
          expectedBusinessVersion: package.expectedBusinessVersion,
          phase: FirmwareUpdateCheckpointPhase.awaitingReconnect,
          nextOffset: package.image.length,
          nextLength: 0,
          updatedAt: DateTime.utc(2026, 9, 15),
        ),
      );
      final gateway = _Gateway();
      final controller = WqotaUpdateController(
        gateway: gateway,
        checkpoints: checkpoints,
        wait: (_) async {},
      );

      await controller.resumeVerification(
        deviceId: 'device-1',
        package: package,
      );

      expect(gateway.operations, <String>['version:1.0.2']);
      expect(controller.state.phase, WqotaUpdatePhase.completed);
      expect(checkpoints.cleared, <String>['device-1']);
    },
  );

  test(
    'reconnect-only controller checks the saved package without WQOTA transport',
    () async {
      final package = _package();
      final checkpoints = _Checkpoints();
      await checkpoints.save(
        FirmwareUpdateCheckpoint(
          deviceId: 'device-1',
          packageHash: sha256.convert(package.image).toString(),
          imageCrc32: package.expectedPayloadCrc32,
          packageVersion: package.version,
          expectedBusinessVersion: package.expectedBusinessVersion,
          phase: FirmwareUpdateCheckpointPhase.awaitingReconnect,
          nextOffset: package.image.length,
          nextLength: 0,
          updatedAt: DateTime.utc(2026, 9, 15),
        ),
      );
      final checks = <String>[];
      final controller = WqotaUpdateController.forReconnectVerification(
        checkpoints: checkpoints,
        verifyBusinessVersion: (expectedVersion) async {
          checks.add(expectedVersion);
          return true;
        },
      );

      await controller.resumeVerification(
        deviceId: 'device-1',
        package: package,
      );

      expect(checks, <String>['1.0.2']);
      expect(controller.state.phase, WqotaUpdatePhase.completed);
      expect(checkpoints.cleared, <String>['device-1']);
    },
  );

  test(
    'does not read the business version for a mismatched checkpoint',
    () async {
      final package = _package();
      final checkpoints = _Checkpoints();
      await checkpoints.save(
        FirmwareUpdateCheckpoint(
          deviceId: 'device-1',
          packageHash: 'wrong-package',
          imageCrc32: package.expectedPayloadCrc32,
          packageVersion: package.version,
          expectedBusinessVersion: package.expectedBusinessVersion,
          phase: FirmwareUpdateCheckpointPhase.awaitingReconnect,
          nextOffset: package.image.length,
          nextLength: 0,
          updatedAt: DateTime.utc(2026, 9, 15),
        ),
      );
      final gateway = _Gateway();
      final controller = WqotaUpdateController(
        gateway: gateway,
        checkpoints: checkpoints,
        wait: (_) async {},
      );

      await expectLater(
        controller.resumeVerification(deviceId: 'device-1', package: package),
        throwsA(isA<WqotaUpdateException>()),
      );

      expect(gateway.operations, isEmpty);
      expect(checkpoints.cleared, isEmpty);
    },
  );

  test(
    'clears a definitive reconnect mismatch so the same package can retry',
    () async {
      final package = _package();
      final checkpoints = _Checkpoints();
      await _saveAwaitingReconnect(checkpoints, package);
      final gateway = _Gateway(businessVersionMatches: false);
      final controller = WqotaUpdateController(
        gateway: gateway,
        checkpoints: checkpoints,
        wait: (_) async {},
      );

      await expectLater(
        controller.resumeVerification(deviceId: 'device-1', package: package),
        throwsA(isA<WqotaUpdateException>()),
      );

      expect(checkpoints.cleared, <String>['device-1']);
      expect(await checkpoints.find('device-1'), isNull);
      await controller.start(deviceId: 'device-1', package: package);
      expect(controller.state.phase, WqotaUpdatePhase.awaitingReconnect);
      expect(gateway.operations, contains('prepare'));
    },
  );

  test('clears a direct reconnect-version mismatch checkpoint', () async {
    final gateway = _Gateway(businessVersionMatches: false);
    final checkpoints = _Checkpoints();
    final controller = WqotaUpdateController(
      gateway: gateway,
      checkpoints: checkpoints,
      wait: (_) async {},
    );
    final package = _package();

    await controller.start(deviceId: 'device-1', package: package);
    await expectLater(
      controller.verifyAfterReconnect(),
      throwsA(isA<WqotaUpdateException>()),
    );

    expect(checkpoints.cleared, <String>['device-1']);
    expect(await checkpoints.find('device-1'), isNull);
  });

  test(
    'preserves a reconnect checkpoint when version read is inconclusive',
    () async {
      final package = _package();
      final checkpoints = _Checkpoints();
      await _saveAwaitingReconnect(checkpoints, package);
      final gateway = _Gateway(
        businessVersionError: StateError('business version unavailable'),
      );
      final controller = WqotaUpdateController(
        gateway: gateway,
        checkpoints: checkpoints,
        wait: (_) async {},
      );

      await expectLater(
        controller.resumeVerification(deviceId: 'device-1', package: package),
        throwsA(isA<StateError>()),
      );

      expect(checkpoints.cleared, isEmpty);
      expect(await checkpoints.find('device-1'), isNotNull);
    },
  );
}

FirmwarePackage _package() => FirmwarePackage(
  vendorId: 0x1234,
  productId: 0x5678,
  version: 2,
  expectedBusinessVersion: '1.0.2',
  payload: Uint8List.fromList(const <int>[1, 2, 3]),
  expectedPayloadCrc32: 0x55BC801D,
  wireFormat: WqotaWireFormat.captured(
    captureId: 'dvt-v1.6-target-capture-001',
    requestPrefixFlags: const <int>[0x70, 0x07, 0x6E, 0xC1],
    responsePrefixFlags: const <int>[0x70, 0x07, 0x6E, 0x01],
  ),
  finalVerificationSupported: true,
);

Future<void> _saveAwaitingReconnect(
  _Checkpoints checkpoints,
  FirmwarePackage package,
) => checkpoints.save(
  FirmwareUpdateCheckpoint(
    deviceId: 'device-1',
    packageHash: sha256.convert(package.image).toString(),
    imageCrc32: package.expectedPayloadCrc32,
    packageVersion: package.version,
    expectedBusinessVersion: package.expectedBusinessVersion,
    phase: FirmwareUpdateCheckpointPhase.awaitingReconnect,
    nextOffset: package.image.length,
    nextLength: 0,
    updatedAt: DateTime.utc(2026, 9, 15),
  ),
);

class _Gateway implements WqotaUpdateGateway {
  _Gateway({
    this.nextWindow,
    this.transferCompletion,
    this.transferError,
    this.rebootError,
    this.businessVersionError,
    this.businessVersionMatches = true,
  });

  final WqotaTransferWindow? nextWindow;
  final Completer<WqotaTransferWindow>? transferCompletion;
  final Object? transferError;
  final Object? rebootError;
  final Object? businessVersionError;
  final bool businessVersionMatches;
  final List<String> operations = <String>[];

  @override
  Future<void> prepareTransport() async => operations.add('prepare');

  @override
  Future<WqotaDeviceIdentity> readDeviceIdentity() async {
    operations.add('identity');
    return const WqotaDeviceIdentity(vendorId: 0x1234, productId: 0x5678);
  }

  @override
  Future<WqotaTransferWindow> queryFileInfoOffset() async {
    operations.add('e1');
    return const WqotaTransferWindow(offset: 0, length: 18);
  }

  @override
  Future<void> inquireIfCanUpdate(Uint8List header) async =>
      operations.add('e2');

  @override
  Future<WqotaTransferWindow> enterUpdateMode() async {
    operations.add('e3');
    return const WqotaTransferWindow(offset: 18, length: 3);
  }

  @override
  Future<WqotaTransferWindow> transferWindow({
    required int offset,
    required Uint8List bytes,
  }) async {
    operations.add('e5:$offset:${bytes.length}');
    final pending = transferCompletion;
    if (pending != null) {
      return pending.future;
    }
    if (transferError case final error?) {
      return Future<WqotaTransferWindow>.error(error);
    }
    return nextWindow ?? const WqotaTransferWindow(offset: 0, length: 0);
  }

  @override
  Future<void> refresh() async => operations.add('e6');

  @override
  Future<WqotaImageVerificationState> readImageVerificationState() async {
    operations.add('e8');
    return WqotaImageVerificationState.verified;
  }

  @override
  Future<void> reboot() async {
    operations.add('reboot');
    if (rebootError case final error?) {
      throw error;
    }
  }

  @override
  Future<void> exitUpdateMode() async => operations.add('e4');

  @override
  Future<bool> verifyBusinessVersion(String expectedBusinessVersion) async {
    operations.add('version:$expectedBusinessVersion');
    if (businessVersionError case final error?) {
      throw error;
    }
    return businessVersionMatches;
  }
}

class _Checkpoints implements FirmwareUpdateCheckpointRepository {
  final saved = <FirmwareUpdateCheckpoint>[];
  final cleared = <String>[];
  final _byDeviceId = <String, FirmwareUpdateCheckpoint>{};

  @override
  Future<void> clear(String deviceId) async {
    cleared.add(deviceId);
    _byDeviceId.remove(deviceId);
  }

  @override
  Future<FirmwareUpdateCheckpoint?> find(String deviceId) async =>
      _byDeviceId[deviceId];

  @override
  Future<void> save(FirmwareUpdateCheckpoint checkpoint) async {
    saved.add(checkpoint);
    _byDeviceId[checkpoint.deviceId] = checkpoint;
  }
}
