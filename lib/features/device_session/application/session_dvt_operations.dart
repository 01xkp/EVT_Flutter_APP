part of 'session_controller.dart';

/// Connection-owned DVT state; protocol orchestration lives outside the UI.
class _DvtSessionRuntime {
  bool metadataBusy = false;
  bool otaActive = false;
  WqotaClient? otaClient;
  WqotaUpdateController? otaController;
  bool audioActive = false;
  bool fileActive = false;
  DeviceConfiguration? configuration;
  bool audioStartedRecording = false;
  StreamSubscription<Uint8List>? audioSubscription;
  final audio = StreamController<Uint8List>.broadcast();
}

class SessionDvtFileGateway
    implements DvtDeviceFileMetadataGateway, DeviceFileTransferGateway {
  SessionDvtFileGateway(this.session) : _attempt = session._connectionAttempt;
  final SessionController session;
  final int _attempt;

  Future<List<DeviceFile>> listFiles({
    required int offset,
    required int pageSize,
  }) {
    session._requireCurrentConnectionAttempt(_attempt);
    return session.listFiles(offset: offset, pageSize: pageSize);
  }

  @override
  Stream<EvtDeviceFileTransferEvent> downloadEvtFile({
    required List<int> nameSlot,
    int startOffset = 0,
    int chunkSize = 0,
    int? expectedFileLength,
  }) async* {
    session._requireCurrentConnectionAttempt(_attempt);
    await for (final event in session.downloadEvtFile(
      nameSlot: nameSlot,
      startOffset: startOffset,
      chunkSize: chunkSize,
      expectedFileLength: expectedFileLength,
    )) {
      session._requireCurrentConnectionAttempt(_attempt);
      yield event;
    }
  }

  @override
  Future<DvtDeviceFileMetadata> readDvtFileMetadata({
    required List<int> nameSlot,
  }) {
    session._requireCurrentConnectionAttempt(_attempt);
    return session.readDvtFileMetadata(nameSlot: nameSlot);
  }

  @override
  Future<DvtDeviceArchiveConfirmationResult> confirmDvtArchive({
    required DvtDeviceArchiveConfirmation confirmation,
  }) {
    session._requireCurrentConnectionAttempt(_attempt);
    return session.confirmDvtArchive(confirmation: confirmation);
  }
}

extension DvtSessionOperations on SessionController {
  bool get dvtTransferBusy => _dvtRuntime.otaActive || _dvtRuntime.audioActive;

  Stream<Uint8List> get dvtAudioPayloads => _dvtRuntime.audio.stream;

  Future<void> startDvtAudioProbe() async {
    if (dvtTransferBusy || _dvtRuntime.fileActive || _dvtRuntime.metadataBusy) {
      throw StateError('请先结束其他传输任务。');
    }
    _requireDevicePermission(DevicePermission.configuration);
    _requireObservableEndpoint(
      BleLogicalEndpoint.fa10Fa18,
      BleOperation.notify,
    );
    final configuration = _dvtRuntime.configuration;
    if (configuration == null) throw StateError('请先完成设备配置同步。');
    final attempt = _connectionAttempt;
    final deviceId = _state.session!.candidate.connectionId;
    _dvtRuntime.audioActive = true;
    try {
      final battery = await _requireProtocol().readBattery();
      final status = await readStatus();
      final info = await readDeviceInfo();
      _requireCurrentConnectionAttempt(attempt);
      if (!status.recordConsent || status.privacy || status.syncState != 0) {
        throw StateError('请先开启录音授权、退出隐私模式并完成文件同步。');
      }
      if (battery.percent == 0 && !battery.isCharging) {
        throw StateError('设备电量为 0%，请充电后验证。');
      }
      if (info.recordStatus != 0 && info.recordStatus != 1) {
        throw StateError('请先结束暂停的录音，再开始音频验证。');
      }
      // V1.6 fixes the encoder block at 480 bytes instead of adapting it to
      // MTU. The ED envelope is 6 bytes and ATT reserves 3 more bytes.
      final mtu = await _ensureAttMtu(489);
      _requireCurrentConnectionAttempt(attempt);
      if (mtu < 489) {
        throw StateError(
          '当前 ATT MTU 为 $mtu，固件固定 480B 音频块要求至少 489；请固件提供兼容分包后再验证。',
        );
      }
      final characteristic = _characteristic(
        deviceId,
        _profile.endpoint(BleLogicalEndpoint.fa10Fa18),
      );
      // FA18 carries at most 480B AudioData plus CMD/CRC. Reject impossible
      // lengths immediately so a corrupt header cannot swallow later audio.
      final assembler = EvtFrameAssembler(maxLengthField: 483);
      _dvtRuntime.audioSubscription = _transport
          .subscribe(characteristic)
          .listen(
            (bytes) {
              if (!_isCurrentConnectionAttempt(attempt)) return;
              final assembled = assembler.add(bytes);
              _commandLogger.info(
                'dvt_audio_native_received',
                fields: {
                  'reason': '【DVT实时音频接收】FA18 原始字节进入组帧器',
                  ...EvtPacketLogSummary.debugRawPacketFields(bytes),
                  'bytes': bytes.length,
                  'discarded_bytes': assembled.discardedByteCount,
                  'rejected_frames': assembled.rejectedFrames.length,
                },
              );
              for (final bytes in assembled.frames) {
                final decoded = _codec.decode(bytes);
                if (!decoded.isSuccess ||
                    decoded.value!.command != 0x88 ||
                    decoded.value!.content.isEmpty ||
                    decoded.value!.content.length > 480) {
                  _logger.warning(
                    'dvt_audio_invalid_frame',
                    fields: {'reason': '【DVT实时音频】丢弃非 0x88 或空数据帧'},
                  );
                  continue;
                }
                _dvtRuntime.audio.add(
                  Uint8List.fromList(decoded.value!.content),
                );
              }
            },
            onError: (Object error, StackTrace stack) {
              if (_isCurrentConnectionAttempt(attempt)) {
                _dvtRuntime.audio.addError(error, stack);
                _onTransportError(
                  error,
                  stack,
                  expectedConnectionAttempt: attempt,
                );
              }
            },
            onDone: () {
              if (_isCurrentConnectionAttempt(attempt) &&
                  _dvtRuntime.audioActive) {
                _onTransportError(
                  StateError('实时音频订阅已关闭。'),
                  StackTrace.current,
                  expectedConnectionAttempt: attempt,
                );
              }
            },
          );
      await _transport
          .awaitSubscriptionReady(characteristic)
          .timeout(SessionController._notificationSetupTimeout);
      _requireCurrentConnectionAttempt(attempt);
      await _writeConfiguration(
        configuration.copyWith(systemTime: DateTime.now(), audioStream: 1),
        refreshDetails: false,
      );
      _requireCurrentConnectionAttempt(attempt);
      if (info.recordStatus == 0) {
        // Set ownership before dispatch: a timeout cannot leave an untracked recording.
        _dvtRuntime.audioStartedRecording = true;
        await setRecordAction(1);
      }
      _logger.info(
        'dvt_audio_started',
        fields: {
          'reason': '【DVT实时音频】CCC、配置和录音状态已确认，等待 0x88',
          'battery': battery.percent,
        },
      );
    } catch (_) {
      if (_isCurrentConnectionAttempt(attempt)) await stopDvtAudioProbe();
      rethrow;
    }
  }

  Future<void> stopDvtAudioProbe() async {
    if (!_dvtRuntime.audioActive) return;
    final attempt = _connectionAttempt;
    try {
      final config = _dvtRuntime.configuration;
      if (_state.hasActiveBleConnection && config != null) {
        await _writeConfiguration(
          config.copyWith(systemTime: DateTime.now(), audioStream: 0),
          refreshDetails: false,
        );
        _requireCurrentConnectionAttempt(attempt);
        if (_dvtRuntime.audioStartedRecording) await setRecordAction(0);
      }
      _logger.info(
        'dvt_audio_stopped',
        fields: {'reason': '【DVT实时音频】音频流已关闭；仅结束本次验证发起的录音'},
      );
    } catch (_) {
      await _invalidateSessionForAmbiguousProtocolResult(
        connectionAttempt: attempt,
        event: 'dvt_audio_stop_failed',
        message: '关闭音频验证未确认，已断开连接停止输出。',
        fields: const {},
      );
      rethrow;
    } finally {
      if (_isCurrentConnectionAttempt(attempt)) {
        _dvtRuntime.audioActive = false;
        _dvtRuntime.audioStartedRecording = false;
        await _dvtRuntime.audioSubscription?.cancel();
        _dvtRuntime.audioSubscription = null;
      }
    }
  }

  Future<void> _resetDvtSession() async {
    final subscription = _dvtRuntime.audioSubscription;
    final otaClient = _dvtRuntime.otaClient;
    _dvtRuntime.otaClient = null;
    _dvtRuntime.otaController = null;
    final hadAudio = _dvtRuntime.audioActive;
    _dvtRuntime.audioSubscription = null;
    _dvtRuntime.audioActive = false;
    _dvtRuntime.audioStartedRecording = false;
    _dvtRuntime.otaActive = false;
    _dvtRuntime.fileActive = false;
    _dvtRuntime.metadataBusy = false;
    _dvtRuntime.configuration = null;
    if (hadAudio && !_dvtRuntime.audio.isClosed) {
      _dvtRuntime.audio.addError(StateError('设备连接已关闭，请重新认证后开始验证。'));
    }
    await subscription?.cancel();
    await otaClient?.close();
  }

  Future<void> verifyDvtArchivePreflight() async {
    if (dvtTransferBusy || _dvtRuntime.fileActive || _dvtRuntime.metadataBusy) {
      throw const EvtUnbindPreflightException('请先完成 OTA、音频验证或文件传输，再解绑。');
    }
    final attempt = _connectionAttempt;
    var offset = 0;
    final seen = <String>{};
    while (true) {
      final page = await listFiles(offset: offset, pageSize: 20);
      _requireCurrentConnectionAttempt(attempt);
      if (page.isEmpty) break;
      for (final file in page) {
        if (!seen.add(file.nameSlot.join(','))) {
          throw const EvtUnbindPreflightException('设备文件列表重复，无法确认安全解绑。');
        }
        final meta = await readDvtFileMetadata(nameSlot: file.nameSlot);
        _requireCurrentConnectionAttempt(attempt);
        if (!meta.state.isArchiveConfirmationTerminal) {
          throw const EvtUnbindPreflightException('设备仍有未归档录音，请完成云端归档后再解绑。');
        }
      }
      offset += page.length;
      if (offset > 0xFFFF) {
        throw const EvtUnbindPreflightException('设备文件数量超过协议范围。');
      }
    }
    _logger.info(
      'dvt_unbind_archive_verified',
      fields: {
        'reason': '【DVT解绑预检】已遍历全部文件，均已归档或设备列表为空；最终判定由固件执行',
        'file_count': seen.length,
      },
    );
  }

  Future<DvtDeviceFileMetadata> readDvtFileMetadata({
    required List<int> nameSlot,
  }) async {
    final frame = await _sendDvtFileCommand(
      DeviceProtocolRepository.encodeDvtReadFileMetadataContent(nameSlot),
    );
    final metadata = DeviceProtocolRepository.decodeDvtFileMetadata(frame);
    if (!listEquals(metadata.nameSlot, nameSlot)) {
      throw StateError('元数据返回的文件键与请求不一致。');
    }
    return metadata;
  }

  Future<DvtDeviceArchiveConfirmationResult> confirmDvtArchive({
    required DvtDeviceArchiveConfirmation confirmation,
  }) async => DeviceProtocolRepository.decodeDvtArchiveConfirmation(
    await _sendDvtFileCommand(
      DeviceProtocolRepository.encodeDvtArchiveConfirmationContent(
        confirmation,
      ),
    ),
  );

  Future<EvtFrame> _sendDvtFileCommand(List<int> content) async {
    if (_dvtRuntime.metadataBusy || _dvtRuntime.fileActive || dvtTransferBusy) {
      throw StateError('设备正在执行其他 DVT 任务，请完成后重试。');
    }
    _dvtRuntime.metadataBusy = true;
    final attempt = _connectionAttempt;
    var commandSubmitted = false;
    try {
      _requireDevicePermission(DevicePermission.files);
      _requireCommandEndpoint(
        BleLogicalEndpoint.ff10Ff16,
        BleOperation.indicate,
      );
      await _ensureResponseSubscription(
        BleLogicalEndpoint.ff10Ff16,
        critical: true,
      );
      final mtu = await _ensureAttMtu(53);
      if (mtu < 53) throw StateError('文件元数据要求 ATT MTU 至少为 53。');
      _requireCurrentConnectionAttempt(attempt);
      _requireDevicePermission(DevicePermission.files);
      final client = _commandClient;
      final deviceId = _state.session?.candidate.connectionId;
      if (client == null || deviceId == null) throw StateError('设备连接已断开。');
      _logger.info(
        'dvt_file_command_requested',
        fields: {
          'reason': '【DVT文件发送】等待 FF16/A6 元数据或归档回包',
          'sub_command': content.first,
          'payload': content,
        },
      );
      commandSubmitted = true;
      final response = await client.execute(
        EvtCommandRequest(
          command: 0x26,
          content: content,
          writeCharacteristic: _characteristic(
            deviceId,
            _profile.endpoint(BleLogicalEndpoint.ff10Ff16),
          ),
          expectedResponseCommand: 0xA6,
          expectedSubCommand: content.first,
          maxRetries: 0,
          timeout: const Duration(seconds: 5),
        ),
      );
      _requireCurrentConnectionAttempt(attempt);
      _logger.info(
        'dvt_file_command_received',
        fields: {
          'reason': '【DVT文件接收】FF16/A6 回包已匹配，开始业务校验',
          'payload': response.frame.content,
        },
      );
      return response.frame;
    } catch (error, stackTrace) {
      // A failed native Write callback does not prove the peripheral rejected
      // the bytes. A6/ARCHIVE_CONFIRM echoes only SubCmd, not the file triple,
      // so its late indication must never complete a later file's request.
      // Setup/admission failures before submission have no pending A6 to drain.
      if (commandSubmitted) {
        final timedOut = error is EvtCommandTimeoutException;
        await _invalidateSessionForAmbiguousProtocolResult(
          connectionAttempt: attempt,
          event: timedOut
              ? 'dvt_file_command_timeout'
              : 'dvt_file_command_response_uncertain',
          message: timedOut
              ? '文件元数据或归档响应超时，请重连后查询或重试。'
              : '文件元数据或归档收发结果不确定，请重连后查询或重试。',
          fields: {
            'sub_command': content.first,
            'error_type': error.runtimeType.toString(),
          },
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (_isCurrentConnectionAttempt(attempt)) {
        _dvtRuntime.metadataBusy = false;
      }
    }
  }
}
