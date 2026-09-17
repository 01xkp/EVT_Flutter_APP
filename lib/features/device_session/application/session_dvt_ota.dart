part of 'session_controller.dart';

extension DvtOtaSessionOperations on SessionController {
  /// Recreates only the V1.6 post-reboot version check. The WQOTA transport
  /// ends when the device reboots, so this path must not require 0x2001/2002
  /// discovery, CCC setup, MTU negotiation, or a new OTA preflight.
  Future<WqotaUpdateController> createDvtOtaVerificationController(
    FirmwarePackage package,
  ) async {
    if (dvtTransferBusy || _dvtRuntime.fileActive || _dvtRuntime.metadataBusy) {
      throw StateError('请先结束文件传输或音频验证，再核验升级版本。');
    }
    _requireDevicePermission(DevicePermission.status);
    package.validateManifest();
    final attempt = _connectionAttempt;
    final physicalId = _state.session?.candidate.physicalDeviceId;
    if (physicalId == null) throw StateError('设备连接已断开。');
    _logger.info(
      'dvt_ota_reconnect_verification_controller_created',
      operation: 'device_ota',
      stage: 'verification',
      result: 'accepted',
      fields: SessionController._sessionFields(
        '【DVT OTA】【重连核验】无需重新打开 WQOTA，仅准备认证后的 0x01 版本核验',
        {
          'connection_attempt': attempt,
          'target_version': package.expectedBusinessVersion,
          'wqota_transport_opened': false,
        },
      ),
    );
    return WqotaUpdateController.forReconnectVerification(
      checkpoints: SharedPreferencesFirmwareUpdateCheckpointRepository(),
      verifyBusinessVersion: (expectedBusinessVersion) async {
        _requireCurrentConnectionAttempt(attempt);
        _requireDevicePermission(DevicePermission.status);
        if (_state.session?.candidate.physicalDeviceId != physicalId) {
          throw StateError('核验设备与升级设备不一致。');
        }
        _logger.info(
          'dvt_ota_reconnect_version_check_requested',
          operation: 'device_ota',
          stage: 'verification',
          result: 'pending',
          fields: SessionController._sessionFields(
            '【DVT OTA】【重连核验】通过 FA11/0x01 读取已认证设备版本',
            {
              'connection_attempt': attempt,
              'expected_version': expectedBusinessVersion,
              'endpoint': BleLogicalEndpoint.fa10Fa11.name,
            },
          ),
        );
        final info = await readDeviceInfo();
        _requireCurrentConnectionAttempt(attempt);
        final matched = info.softwareVersion == expectedBusinessVersion;
        _logger.info(
          'dvt_ota_reconnect_version_check_completed',
          operation: 'device_ota',
          stage: 'verification',
          result: matched ? 'success' : 'failed',
          fields: SessionController._sessionFields(
            '【DVT OTA】【重连核验】已收到 0x01 版本并完成目标版本比对',
            {
              'connection_attempt': attempt,
              'expected_version': expectedBusinessVersion,
              'reported_version': info.softwareVersion,
              'matched': matched,
            },
          ),
        );
        return matched;
      },
    );
  }

  Future<WqotaUpdateController> createDvtOtaController(
    FirmwarePackage package,
  ) async {
    if (dvtTransferBusy || _dvtRuntime.fileActive || _dvtRuntime.metadataBusy) {
      throw StateError('请先结束文件传输或音频验证。');
    }
    _requireDevicePermission(DevicePermission.configuration);
    _requireObservableEndpoint(
      BleLogicalEndpoint.wqota2001,
      BleOperation.writeWithoutResponse,
    );
    _requireObservableEndpoint(
      BleLogicalEndpoint.wqota2002,
      BleOperation.notify,
    );
    final attempt = _connectionAttempt;
    final deviceId = _state.session!.candidate.connectionId;
    final physicalId = _state.session!.candidate.physicalDeviceId;
    final info = await readDeviceInfo();
    final status = await readStatus();
    _requireCurrentConnectionAttempt(attempt);
    if (info.recordStatus != 0 ||
        status.syncState != 0 ||
        _state.isRecordActionInFlight ||
        dvtTransferBusy ||
        _dvtRuntime.fileActive ||
        _dvtRuntime.metadataBusy) {
      throw StateError('请结束录音及文件同步，再开始 OTA。');
    }
    _dvtRuntime.otaActive = true;
    WqotaClient? client;
    WqotaUpdateController? controller;
    try {
      final openedClient = await WqotaClient.open(
        transport: _transport,
        writeCharacteristic: WqotaGatt.writeCharacteristic(deviceId),
        notifyCharacteristic: WqotaGatt.notifyCharacteristic(deviceId),
        codec: WqotaCodec(wireFormat: package.wireFormat),
        beforeWrite: () {
          _requireCurrentConnectionAttempt(attempt);
          _requireDevicePermission(DevicePermission.configuration);
          if (!_dvtRuntime.otaActive) throw StateError('OTA 会话已经结束。');
          if (!identical(_dvtRuntime.otaController, controller)) {
            throw StateError('OTA 控制器已被新的页面会话替换。');
          }
        },
        logger: _commandLogger,
      );
      client = openedClient;
      if (!_isCurrentConnectionAttempt(attempt)) {
        await openedClient.close();
        throw StateError('订阅 OTA 时连接已改变。');
      }
      final gateway = WqotaBleUpdateGateway(
        client: openedClient,
        requestMtu: () async {
          _requireCurrentConnectionAttempt(attempt);
          return _ensureAttMtu(247);
        },
        finalVerificationSupported: package.finalVerificationSupported,
        verifyBusinessVersion: (expected) async {
          if (_state.session?.candidate.physicalDeviceId != physicalId) {
            throw StateError('核验设备与升级设备不一致。');
          }
          _requireDevicePermission(DevicePermission.status);
          final info = await readDeviceInfo();
          return info.softwareVersion == expected;
        },
      );
      controller = WqotaUpdateController(
        gateway: gateway,
        checkpoints: SharedPreferencesFirmwareUpdateCheckpointRepository(),
      );
      _dvtRuntime.otaClient = openedClient;
      _dvtRuntime.otaController = controller;
      return controller;
    } catch (_) {
      if (identical(_dvtRuntime.otaController, controller)) {
        _dvtRuntime.otaController = null;
      }
      if (identical(_dvtRuntime.otaClient, client)) {
        _dvtRuntime.otaClient = null;
      }
      if (_isCurrentConnectionAttempt(attempt)) {
        _dvtRuntime.otaActive = false;
      }
      await client?.close();
      rethrow;
    }
  }

  /// Releases only the WQOTA client owned by [owner]. A stale page can finish
  /// its asynchronous dispose after a newer page has acquired WQOTA; it must
  /// never close the newer page's client.
  Future<void> releaseDvtOta({WqotaUpdateController? owner}) async {
    if (owner == null || !identical(_dvtRuntime.otaController, owner)) {
      return;
    }
    final client = _dvtRuntime.otaClient;
    _dvtRuntime.otaClient = null;
    _dvtRuntime.otaController = null;
    _dvtRuntime.otaActive = false;
    await client?.close();
  }
}
