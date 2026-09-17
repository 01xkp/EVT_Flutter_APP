import 'dart:async';

import 'package:aipin/features/device_session/domain/firmware_package.dart';
import 'package:aipin/features/device_session/domain/firmware_update_checkpoint.dart';
import 'package:aipin/features/device_session/domain/wqota_update_gateway.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

enum WqotaUpdatePhase {
  idle,
  preparing,
  transferring,
  verifying,
  awaitingReconnect,
  completed,
  cancelled,
  failed,
}

class WqotaUpdateState {
  const WqotaUpdateState({
    required this.phase,
    this.transferredBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  const WqotaUpdateState.idle() : this(phase: WqotaUpdatePhase.idle);

  final WqotaUpdatePhase phase;
  final int transferredBytes;
  final int totalBytes;
  final String? error;

  bool get isActive =>
      phase == WqotaUpdatePhase.preparing ||
      phase == WqotaUpdatePhase.transferring ||
      phase == WqotaUpdatePhase.verifying;

  WqotaUpdateState copyWith({
    WqotaUpdatePhase? phase,
    int? transferredBytes,
    int? totalBytes,
    String? error,
    bool clearError = false,
  }) => WqotaUpdateState(
    phase: phase ?? this.phase,
    transferredBytes: transferredBytes ?? this.transferredBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    error: clearError ? null : error ?? this.error,
  );
}

/// Coordinates the V1.6 DVT WQOTA sequence after a caller has authenticated
/// the current connection and opened the dedicated 0x7033 channel.
class WqotaUpdateController extends ChangeNotifier {
  WqotaUpdateController({
    required this.gateway,
    required this.checkpoints,
    this.verificationRetryDelay = const Duration(seconds: 1),
    this.maximumVerificationAttempts = 60,
    Future<void> Function(Duration delay)? wait,
  }) : _wait = wait ?? Future<void>.delayed {
    if (verificationRetryDelay < Duration.zero) {
      throw ArgumentError.value(
        verificationRetryDelay,
        'verificationRetryDelay',
        'Must not be negative.',
      );
    }
    if (maximumVerificationAttempts < 1) {
      throw ArgumentError.value(
        maximumVerificationAttempts,
        'maximumVerificationAttempts',
        'Must be at least one.',
      );
    }
  }

  /// Creates the post-reboot half of an update without reopening the WQOTA
  /// transport. V1.6 requires a newly authenticated business `0x01` version
  /// read at this point; a missing or no-longer-advertised 0x7033 service must
  /// not prevent an already-transferred image from being verified.
  factory WqotaUpdateController.forReconnectVerification({
    required Future<bool> Function(String expectedBusinessVersion)
    verifyBusinessVersion,
    required FirmwareUpdateCheckpointRepository checkpoints,
    Duration verificationRetryDelay = const Duration(seconds: 1),
    int maximumVerificationAttempts = 60,
    Future<void> Function(Duration delay)? wait,
  }) => WqotaUpdateController(
    gateway: _ReconnectVerificationGateway(verifyBusinessVersion),
    checkpoints: checkpoints,
    verificationRetryDelay: verificationRetryDelay,
    maximumVerificationAttempts: maximumVerificationAttempts,
    wait: wait,
  );

  static const _imageHeaderBytes = 18;

  final WqotaUpdateGateway gateway;
  final FirmwareUpdateCheckpointRepository checkpoints;
  final Duration verificationRetryDelay;
  final int maximumVerificationAttempts;
  final Future<void> Function(Duration delay) _wait;

  WqotaUpdateState _state = const WqotaUpdateState.idle();
  WqotaUpdateState get state => _state;

  Future<void>? _activeRun;
  String? _deviceId;
  FirmwarePackage? _package;
  bool _cancelRequested = false;

  Future<void> start({
    required String deviceId,
    required FirmwarePackage package,
  }) {
    _ensureNoActiveRun();
    _deviceId = deviceId;
    _package = package;
    _cancelRequested = false;
    _setState(
      WqotaUpdateState(
        phase: WqotaUpdatePhase.preparing,
        totalBytes: package.payload.length,
      ),
    );

    return _trackRun(
      () => _startInternal(deviceId: deviceId, package: package),
    );
  }

  /// Restores the post-reboot half of an OTA operation in a newly created
  /// controller. This intentionally uses only the authenticated business
  /// version read; it never replays WQOTA frames after a reboot.
  Future<void> resumeVerification({
    required String deviceId,
    required FirmwarePackage package,
  }) {
    _ensureNoActiveRun();
    _deviceId = deviceId;
    _package = package;
    _cancelRequested = false;
    _setState(
      WqotaUpdateState(
        phase: WqotaUpdatePhase.preparing,
        totalBytes: package.payload.length,
      ),
    );
    return _trackRun(
      () => _resumeVerificationInternal(deviceId: deviceId, package: package),
    );
  }

  Future<void> _startInternal({
    required String deviceId,
    required FirmwarePackage package,
  }) async {
    var updateModeEntered = false;
    try {
      _throwIfCancelled();
      await gateway.prepareTransport();
      _throwIfCancelled();
      final identity = await gateway.readDeviceIdentity();
      package.validateFor(identity);

      final packageHash = _packageHash(package);
      final checkpoint = await checkpoints.find(deviceId);
      if (checkpoint != null &&
          !_matchesPackage(checkpoint, packageHash, package)) {
        await checkpoints.clear(deviceId);
      } else if (checkpoint?.phase ==
          FirmwareUpdateCheckpointPhase.awaitingReconnect) {
        throw const WqotaUpdateException(
          'WQOTA is waiting for reconnect version verification; do not start a second transfer.',
        );
      } else if (checkpoint != null) {
        _setState(
          state.copyWith(
            transferredBytes: _payloadBytesAt(checkpoint.nextOffset, package),
          ),
        );
      }

      _throwIfCancelled();
      final headerWindow = await gateway.queryFileInfoOffset();
      if (headerWindow.offset != 0 ||
          headerWindow.length != _imageHeaderBytes) {
        throw const WqotaUpdateException(
          'WQOTA E1 did not return the required 0/18 image-header window.',
        );
      }
      _throwIfCancelled();
      await gateway.inquireIfCanUpdate(package.imageHeader);
      _throwIfCancelled();
      var window = await gateway.enterUpdateMode();
      updateModeEntered = true;

      final image = package.image;
      _validateInitialWindow(window, image);
      await _saveCheckpoint(
        deviceId: deviceId,
        package: package,
        packageHash: packageHash,
        window: window,
        phase: FirmwareUpdateCheckpointPhase.transferring,
        image: image,
      );
      _setState(
        state.copyWith(
          phase: WqotaUpdatePhase.transferring,
          transferredBytes: _payloadBytesAt(
            window.isTerminal ? image.length : window.offset,
            package,
          ),
        ),
      );
      while (!window.isTerminal) {
        _throwIfCancelled();
        final expectedEnd = _validateWindow(window, image);
        final bytes = Uint8List.fromList(
          image.sublist(window.offset, expectedEnd),
        );
        final next = await gateway.transferWindow(
          offset: window.offset,
          bytes: bytes,
        );
        _throwIfCancelled();
        _validateNextWindow(next, expectedEnd, image);
        await _saveCheckpoint(
          deviceId: deviceId,
          package: package,
          packageHash: packageHash,
          window: next,
          phase: FirmwareUpdateCheckpointPhase.transferring,
          image: image,
          terminalOffset: expectedEnd,
        );
        _setState(
          state.copyWith(
            transferredBytes: _payloadBytesAt(expectedEnd, package),
          ),
        );
        window = next;
      }

      _throwIfCancelled();
      _setState(state.copyWith(phase: WqotaUpdatePhase.verifying));
      await gateway.refresh();
      await _waitForFinalVerification();
      _throwIfCancelled();
      // Persist this before the 0x03 reboot request. A peripheral can accept reboot and then drop
      // the link before the 0x03 response reaches the phone. The next
      // authenticated connection must verify the business version rather than
      // accidentally start a second transfer.
      await _saveCheckpoint(
        deviceId: deviceId,
        package: package,
        packageHash: packageHash,
        window: const WqotaTransferWindow(offset: 0, length: 0),
        phase: FirmwareUpdateCheckpointPhase.awaitingReconnect,
        image: image,
        terminalOffset: image.length,
      );
      await gateway.reboot();
      _setState(
        state.copyWith(
          phase: WqotaUpdatePhase.awaitingReconnect,
          clearError: true,
        ),
      );
    } on _WqotaUpdateCancelled {
      await _finishCancellation(updateModeEntered);
    } catch (error) {
      Object? exitError;
      if (updateModeEntered && _requiresExplicitExit(error)) {
        try {
          await gateway.exitUpdateMode();
        } catch (cleanupError) {
          exitError = cleanupError;
        }
      }
      _setState(
        state.copyWith(
          phase: WqotaUpdatePhase.failed,
          error: exitError == null
              ? _failureMessage(error)
              : '$error; WQOTA E4 cleanup also failed: $exitError',
        ),
      );
      rethrow;
    }
  }

  Future<void> _resumeVerificationInternal({
    required String deviceId,
    required FirmwarePackage package,
  }) async {
    try {
      // Verify the selected manifest and saved state before reading business
      // 0x01. A wrong manifest must not clear a valid device checkpoint.
      package.validateManifest();
      final checkpoint = await checkpoints.find(deviceId);
      final packageHash = _packageHash(package);
      if (checkpoint == null ||
          !_matchesPackage(checkpoint, packageHash, package) ||
          checkpoint.phase != FirmwareUpdateCheckpointPhase.awaitingReconnect) {
        throw const WqotaUpdateException(
          'No matching WQOTA checkpoint is waiting for reconnect verification.',
        );
      }
      _setState(
        state.copyWith(
          phase: WqotaUpdatePhase.awaitingReconnect,
          transferredBytes: _payloadBytesAt(checkpoint.nextOffset, package),
          clearError: true,
        ),
      );
      _throwIfCancelled();
      await _completeReconnectVerification(
        deviceId: deviceId,
        package: package,
        checkpoint: checkpoint,
      );
    } on _WqotaUpdateCancelled {
      await _finishCancellation(false);
    } catch (error) {
      _setState(
        state.copyWith(phase: WqotaUpdatePhase.failed, error: '$error'),
      );
      rethrow;
    }
  }

  Future<void> _waitForFinalVerification() async {
    for (var attempt = 0; attempt < maximumVerificationAttempts; attempt += 1) {
      _throwIfCancelled();
      switch (await gateway.readImageVerificationState()) {
        case WqotaImageVerificationState.verified:
          return;
        case WqotaImageVerificationState.unavailable:
          throw const WqotaUpdateException(
            'Target firmware has not proved that WQOTA E8 idle means image CRC verification passed.',
          );
        case WqotaImageVerificationState.syncing:
          if (attempt == maximumVerificationAttempts - 1) {
            throw const WqotaVerificationPendingException(
              'WQOTA image verification did not finish.',
            );
          }
          await _wait(verificationRetryDelay);
      }
    }
  }

  Future<void> _completeReconnectVerification({
    required String deviceId,
    required FirmwarePackage package,
    required FirmwareUpdateCheckpoint checkpoint,
  }) async {
    _throwIfCancelled();
    final matches = await gateway.verifyBusinessVersion(
      checkpoint.expectedBusinessVersion,
    );
    _throwIfCancelled();
    if (!matches) {
      // `false` is a definitive business 0x01 answer. Keeping this matching
      // checkpoint would permanently block a deliberate retry with the same
      // package; transport errors instead throw above and preserve it.
      await checkpoints.clear(deviceId);
      throw const WqotaUpdateException(
        'The reconnected device business version does not match the WQOTA package. The stale local checkpoint was cleared; a new transfer can now be started.',
      );
    }
    await checkpoints.clear(deviceId);
    _setState(
      state.copyWith(
        phase: WqotaUpdatePhase.completed,
        transferredBytes: package.payload.length,
        clearError: true,
      ),
    );
  }

  /// The integration layer reconnects, re-authenticates with Action=00, reads
  /// business 0x01, then calls this method to close the DVT upgrade loop.
  Future<void> verifyAfterReconnect() async {
    final deviceId = _deviceId;
    final package = _package;
    if (deviceId == null ||
        package == null ||
        state.phase != WqotaUpdatePhase.awaitingReconnect) {
      throw StateError(
        'No WQOTA update is waiting for reconnect verification.',
      );
    }
    try {
      package.validateManifest();
      final checkpoint = await checkpoints.find(deviceId);
      if (checkpoint == null ||
          !_matchesPackage(checkpoint, _packageHash(package), package) ||
          checkpoint.phase != FirmwareUpdateCheckpointPhase.awaitingReconnect) {
        throw const WqotaUpdateException(
          'No matching WQOTA checkpoint is waiting for reconnect verification.',
        );
      }
      await _completeReconnectVerification(
        deviceId: deviceId,
        package: package,
        checkpoint: checkpoint,
      );
    } catch (error) {
      _setState(
        state.copyWith(phase: WqotaUpdatePhase.failed, error: '$error'),
      );
      rethrow;
    }
  }

  /// Cancellation waits for the active command to settle before E4. This
  /// avoids sending E4 concurrently with an E5 window on Write Without
  /// Response, which would make response serial correlation unsafe.
  Future<void> cancel() async {
    if (!state.isActive) {
      return;
    }
    _cancelRequested = true;
    final active = _activeRun;
    if (active != null) {
      await active;
    }
  }

  Future<void> _finishCancellation(bool updateModeEntered) async {
    try {
      if (updateModeEntered) {
        await gateway.exitUpdateMode();
      }
      _setState(
        state.copyWith(phase: WqotaUpdatePhase.cancelled, clearError: true),
      );
    } catch (error) {
      _setState(
        state.copyWith(
          phase: WqotaUpdatePhase.failed,
          error: 'WQOTA cancellation could not exit update mode: $error',
        ),
      );
      rethrow;
    }
  }

  void _throwIfCancelled() {
    if (_cancelRequested) {
      throw const _WqotaUpdateCancelled();
    }
  }

  static void _validateInitialWindow(
    WqotaTransferWindow window,
    Uint8List image,
  ) {
    if (window.isTerminal) {
      if (window.offset != 0 && window.offset != image.length) {
        throw const WqotaUpdateException(
          'WQOTA terminal E3 window has an invalid offset.',
        );
      }
      return;
    }
    _validateWindow(window, image);
  }

  static int _validateWindow(WqotaTransferWindow window, Uint8List image) {
    if (window.offset < _imageHeaderBytes ||
        window.length <= 0 ||
        window.offset >= image.length) {
      throw const WqotaUpdateException('WQOTA device window is invalid.');
    }
    final end = window.offset + window.length;
    if (end > image.length) {
      throw const WqotaUpdateException(
        'WQOTA device window exceeds the complete firmware image.',
      );
    }
    return end;
  }

  static void _validateNextWindow(
    WqotaTransferWindow next,
    int expectedOffset,
    Uint8List image,
  ) {
    if (next.isTerminal) {
      if (expectedOffset != image.length ||
          (next.offset != 0 && next.offset != image.length)) {
        throw const WqotaUpdateException(
          'WQOTA terminal E5 response has an invalid offset.',
        );
      }
      return;
    }
    if (next.offset != expectedOffset) {
      throw const WqotaUpdateException(
        'WQOTA E5 returned a non-contiguous next offset.',
      );
    }
    _validateWindow(next, image);
  }

  static bool _matchesPackage(
    FirmwareUpdateCheckpoint checkpoint,
    String packageHash,
    FirmwarePackage package,
  ) =>
      checkpoint.packageHash == packageHash &&
      checkpoint.imageCrc32 == package.expectedPayloadCrc32 &&
      checkpoint.packageVersion == package.version &&
      checkpoint.expectedBusinessVersion == package.expectedBusinessVersion;

  Future<void> _saveCheckpoint({
    required String deviceId,
    required FirmwarePackage package,
    required String packageHash,
    required WqotaTransferWindow window,
    required FirmwareUpdateCheckpointPhase phase,
    required Uint8List image,
    int? terminalOffset,
  }) => checkpoints.save(
    FirmwareUpdateCheckpoint(
      deviceId: deviceId,
      packageHash: packageHash,
      imageCrc32: package.expectedPayloadCrc32,
      packageVersion: package.version,
      expectedBusinessVersion: package.expectedBusinessVersion,
      phase: phase,
      nextOffset: window.isTerminal
          ? terminalOffset ?? image.length
          : window.offset,
      nextLength: window.length,
      updatedAt: DateTime.now().toUtc(),
    ),
  );

  void _ensureNoActiveRun() {
    if (_activeRun != null || state.isActive) {
      throw StateError('A WQOTA update is already active.');
    }
  }

  Future<void> _trackRun(Future<void> Function() runOperation) {
    late final Future<void> run;
    run = runOperation().whenComplete(() {
      if (identical(_activeRun, run)) {
        _activeRun = null;
      }
    });
    _activeRun = run;
    return run;
  }

  static bool _requiresExplicitExit(Object error) =>
      error is WqotaUpdateAbortException;

  static String _failureMessage(Object error) =>
      error is WqotaUpdateAbortException
      ? '$error'
      : '$error; WQOTA 传输已停止，已保留设备与本地断点，请重连后恢复。';

  static int _payloadBytesAt(int imageOffset, FirmwarePackage package) {
    return (imageOffset - _imageHeaderBytes)
        .clamp(0, package.payload.length)
        .toInt();
  }

  static String _packageHash(FirmwarePackage package) =>
      sha256.convert(package.image).toString();

  void _setState(WqotaUpdateState state) {
    _state = state;
    notifyListeners();
  }
}

class WqotaUpdateException implements Exception, WqotaUpdateAbortException {
  const WqotaUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The device is still verifying the submitted image. This is deliberately
/// not an E4 condition: the next authenticated connection can recover from
/// the persisted transfer checkpoint rather than discarding the device state.
class WqotaVerificationPendingException implements Exception {
  const WqotaVerificationPendingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _WqotaUpdateCancelled implements Exception {
  const _WqotaUpdateCancelled();
}

/// `resumeVerification` intentionally needs only this callback. Keeping the
/// unsupported transport methods here makes an accidental transfer restart
/// fail closed rather than silently reopening WQOTA after the device rebooted.
class _ReconnectVerificationGateway implements WqotaUpdateGateway {
  const _ReconnectVerificationGateway(this._verifyBusinessVersion);

  final Future<bool> Function(String expectedBusinessVersion)
  _verifyBusinessVersion;

  Never _unsupported() => throw StateError(
    'WQOTA transport is unavailable during post-reconnect version verification.',
  );

  @override
  Future<void> prepareTransport() async => _unsupported();

  @override
  Future<WqotaDeviceIdentity> readDeviceIdentity() async => _unsupported();

  @override
  Future<WqotaTransferWindow> queryFileInfoOffset() async => _unsupported();

  @override
  Future<void> inquireIfCanUpdate(Uint8List header) async => _unsupported();

  @override
  Future<WqotaTransferWindow> enterUpdateMode() async => _unsupported();

  @override
  Future<WqotaTransferWindow> transferWindow({
    required int offset,
    required Uint8List bytes,
  }) async => _unsupported();

  @override
  Future<void> refresh() async => _unsupported();

  @override
  Future<WqotaImageVerificationState> readImageVerificationState() async =>
      _unsupported();

  @override
  Future<void> reboot() async => _unsupported();

  @override
  Future<void> exitUpdateMode() async => _unsupported();

  @override
  Future<bool> verifyBusinessVersion(String expectedBusinessVersion) =>
      _verifyBusinessVersion(expectedBusinessVersion);
}
