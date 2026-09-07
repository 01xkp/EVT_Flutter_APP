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

class WqotaUpdateController extends ChangeNotifier {
  WqotaUpdateController({required this.gateway, required this.checkpoints});

  final WqotaUpdateGateway gateway;
  final FirmwareUpdateCheckpointRepository checkpoints;
  WqotaUpdateState _state = const WqotaUpdateState.idle();
  WqotaUpdateState get state => _state;
  String? _deviceId;
  FirmwarePackage? _package;
  bool _cancelRequested = false;

  Future<void> start({
    required String deviceId,
    required FirmwarePackage package,
  }) async {
    if (state.isActive) {
      throw StateError('固件升级正在执行。');
    }
    _deviceId = deviceId;
    _package = package;
    _cancelRequested = false;
    _setState(
      WqotaUpdateState(
        phase: WqotaUpdatePhase.preparing,
        totalBytes: package.payload.length,
      ),
    );
    var updateModeEntered = false;
    try {
      await gateway.prepareTransport();
      final identity = await gateway.readDeviceIdentity();
      package.validateFor(identity);
      final checkpoint = await checkpoints.find(deviceId);
      final packageHash = _packageHash(package);
      if (checkpoint != null && checkpoint.packageHash != packageHash) {
        await checkpoints.clear(deviceId);
      }
      final headerWindow = await gateway.queryFileInfoOffset();
      if (headerWindow.offset != 0 || headerWindow.length != 18) {
        throw StateError('设备未返回 18 字节镜像头窗口。');
      }
      await gateway.inquireIfCanUpdate(package.imageHeader);
      var window = await gateway.enterUpdateMode();
      updateModeEntered = true;
      _setState(state.copyWith(phase: WqotaUpdatePhase.transferring));
      final image = package.image;
      while (window.length > 0) {
        if (_cancelRequested) {
          return;
        }
        if (window.offset < 18 || window.offset >= image.length) {
          throw StateError('设备返回的升级窗口偏移无效。');
        }
        final end = (window.offset + window.length).clamp(18, image.length);
        final bytes = Uint8List.fromList(image.sublist(window.offset, end));
        if (bytes.isEmpty) {
          throw StateError('设备返回的升级窗口不包含有效数据。');
        }
        window = await gateway.transferWindow(
          offset: window.offset,
          bytes: bytes,
        );
        final transferred = end - 18;
        await checkpoints.save(
          FirmwareUpdateCheckpoint(
            deviceId: deviceId,
            packageHash: packageHash,
            offset: window.length == 0 ? end : window.offset,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        _setState(state.copyWith(transferredBytes: transferred));
      }
      if (_cancelRequested) {
        return;
      }
      _setState(state.copyWith(phase: WqotaUpdatePhase.verifying));
      await gateway.refresh();
      var imageVerified = false;
      for (var attempt = 0; attempt < 60; attempt += 1) {
        if (_cancelRequested) {
          return;
        }
        switch (await gateway.readImageVerificationState()) {
          case WqotaImageVerificationState.verified:
            imageVerified = true;
            break;
          case WqotaImageVerificationState.unavailable:
            throw StateError('设备未提供可验证的整镜像校验终态。');
          case WqotaImageVerificationState.syncing:
            if (attempt == 59) {
              throw StateError('设备未完成整镜像校验。');
            }
            await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (imageVerified) {
          break;
        }
      }
      if (!imageVerified) {
        throw StateError('设备未完成整镜像校验。');
      }
      await gateway.reboot();
      _setState(
        state.copyWith(
          phase: WqotaUpdatePhase.awaitingReconnect,
          clearError: true,
        ),
      );
    } catch (error) {
      if (!_cancelRequested) {
        Object? exitError;
        if (updateModeEntered) {
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
                ? '$error'
                : '$error；设备退出升级模式失败：$exitError',
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> verifyAfterReconnect() async {
    final deviceId = _deviceId;
    final package = _package;
    if (deviceId == null ||
        package == null ||
        state.phase != WqotaUpdatePhase.awaitingReconnect) {
      throw StateError('当前没有等待核验的固件升级。');
    }
    try {
      if (!await gateway.verifyBusinessVersion(
        package.expectedBusinessVersion,
      )) {
        throw StateError('重连后设备版本与目标固件不一致。');
      }
      await checkpoints.clear(deviceId);
      _setState(
        state.copyWith(
          phase: WqotaUpdatePhase.completed,
          transferredBytes: package.payload.length,
          clearError: true,
        ),
      );
    } catch (error) {
      _setState(
        state.copyWith(phase: WqotaUpdatePhase.failed, error: '$error'),
      );
      rethrow;
    }
  }

  Future<void> cancel() async {
    if (!state.isActive) {
      return;
    }
    _cancelRequested = true;
    try {
      await gateway.exitUpdateMode();
    } finally {
      _setState(
        state.copyWith(phase: WqotaUpdatePhase.cancelled, clearError: true),
      );
    }
  }

  String _packageHash(FirmwarePackage package) =>
      sha256.convert(package.image).toString();

  void _setState(WqotaUpdateState state) {
    _state = state;
    notifyListeners();
  }
}
