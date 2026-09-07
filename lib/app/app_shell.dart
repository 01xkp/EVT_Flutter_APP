import 'dart:async';

import 'package:aipin/app/app_destination.dart';
import 'package:aipin/app/branding/aipin_brand_splash.dart';
import 'package:aipin/app/providers.dart';
import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/ble/device_profile_loader.dart';
import 'package:aipin/core/design_system/evt_theme.dart';
import 'package:aipin/core/design_system/widgets/app_navigation_bar.dart';
import 'package:aipin/core/design_system/widgets/app_toast.dart';
import 'package:aipin/core/design_system/widgets/ai_processing_toast.dart';
import 'package:aipin/features/device_session/application/realtime_audio_controller.dart';
import 'package:aipin/features/device_session/application/device_reconnect_controller.dart';
import 'package:aipin/features/device_session/application/device_reconnect_state.dart';
import 'package:aipin/features/device_session/application/wqota_update_controller.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/core/protocol/wqota_client.dart';
import 'package:aipin/core/protocol/wqota_codec.dart';
import 'package:aipin/features/device_discovery/application/discovery_controller.dart';
import 'package:aipin/features/device_discovery/domain/advertisement_filter.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:aipin/features/device_discovery/presentation/discovery_page.dart';
import 'package:aipin/features/device_session/application/session_controller.dart';
import 'package:aipin/features/device_session/application/device_auth_controller.dart';
import 'package:aipin/features/device_session/application/session_state.dart';
import 'package:aipin/features/device_session/domain/device_auth_state.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/device_session/domain/realtime_audio_capture.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:aipin/features/device_session/presentation/device_detail_page.dart';
import 'package:aipin/features/device_session/presentation/device_file_browser_page.dart';
import 'package:aipin/features/device_session/presentation/firmware_update_page.dart';
import 'package:aipin/features/device_session/data/device_file_import_service.dart';
import 'package:aipin/features/device_session/data/wqota_ble_update_gateway.dart';
import 'package:aipin/features/device_logs/presentation/device_log_page.dart';
import 'package:aipin/features/evidence/application/evidence_history_controller.dart';
import 'package:aipin/features/evidence/presentation/record_observation_sheet.dart';
import 'package:aipin/features/home/presentation/home_page.dart';
import 'package:aipin/features/local_recording/application/recording_controller.dart';
import 'package:aipin/features/local_recording/application/recording_library_controller.dart';
import 'package:aipin/features/local_recording/application/recording_recovery_service.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/presentation/active_recording_page.dart';
import 'package:aipin/features/local_recording/presentation/local_recording_detail_page.dart';
import 'package:aipin/features/local_recording/presentation/local_recording_library_page.dart';
import 'package:aipin/features/local_recording/presentation/recording_hub_page.dart';
import 'package:aipin/features/observation/domain/observation_scenario.dart';
import 'package:aipin/features/observation/presentation/observation_page.dart';
import 'package:aipin/features/onboarding/application/onboarding_controller.dart';
import 'package:aipin/features/onboarding/presentation/welcome_page.dart';
import 'package:aipin/features/records/presentation/records_page.dart';
import 'package:aipin/features/research_beta/application/research_capture_processing_controller.dart';
import 'package:aipin/features/research_beta/domain/research_capture.dart';
import 'package:aipin/features/research_beta/presentation/research_consent_sheet.dart';
import 'package:aipin/features/research_beta/presentation/research_upload_confirmation_sheet.dart';
import 'package:aipin/features/settings/application/theme_mode_controller.dart';
import 'package:aipin/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, this.themeController});

  final ThemeModeController? themeController;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  late final DiscoveryController _discoveryController;
  late final DeviceReconnectController _reconnectController;
  late final OnboardingController _onboardingController;
  SessionController? _sessionController;
  DeviceAuthController? _deviceAuthController;
  EvidenceHistoryController? _evidenceHistoryController;
  RecordingController? _recordingController;
  RecordingLibraryController? _recordingLibraryController;
  Future<void>? _recordingSetup;
  DeviceProfile? _profile;
  var _destination = AppDestination.home;
  var _isOnboardingLoaded = false;
  var _recordsInitialSelection = 0;
  Future<void>? _researchRecovery;
  ResearchCaptureProcessingController? _researchProcessing;
  final AiProcessingToastController _aiProcessingToast =
      AiProcessingToastController();
  final List<ResearchCaptureUiUpdate> _deferredResearchUpdates =
      <ResearchCaptureUiUpdate>[];
  Future<void> _researchUpdateForwarding = Future<void>.value();
  var _isAppForeground = true;
  var _reconnectPausedForBackground = false;
  Future<void>? _reconnectBackgroundPause;
  var _recordingDetailDepth = 0;
  var _sessionReachedAuthenticationReady = false;
  var _sessionHistoryPersisted = false;
  var _unexpectedReconnectStarted = false;
  Future<void>? _sessionHistoryPersistence;
  var _sessionConnectionOperation = 0;
  OverlayEntry? _aiProcessingToastEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _discoveryController = DiscoveryController(
      ref.read(bleTransportProvider),
      const AdvertisementFilter(),
    );
    _discoveryController.addListener(_onDiscoveryChanged);
    _reconnectController = DeviceReconnectController(
      history: ref.read(deviceConnectionHistoryRepositoryProvider),
      startScan: () async {
        _discoveryController.start();
      },
      stopScan: _discoveryController.stop,
      connect: _connectRememberedDevice,
      logger: ref.read(scopedAppLoggerProvider('RECONNECT')),
    );
    _onboardingController = OnboardingController(
      ref.read(onboardingStoreProvider),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _attachAiProcessingToast();
      }
    });
    unawaited(_loadOnboarding());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _discoveryController.removeListener(_onDiscoveryChanged);
    _reconnectController.dispose();
    _discoveryController.dispose();
    _onboardingController.dispose();
    _sessionController?.removeListener(_onSessionChanged);
    _sessionController?.dispose();
    _deviceAuthController?.dispose();
    _evidenceHistoryController?.dispose();
    _recordingController?.removeListener(_syncRecordingLibrary);
    _researchProcessing?.removeListener(_onResearchProcessingChanged);
    _aiProcessingToastEntry?.remove();
    _aiProcessingToast.dispose();
    final recordingController = _recordingController;
    final recordingLibraryController = _recordingLibraryController;
    if (recordingLibraryController != null) {
      unawaited(recordingLibraryController.close());
    }
    if (recordingController != null) {
      unawaited(recordingController.close());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppForeground = true;
      _syncAiToastVisibility();
      _flushDeferredResearchUpdates();
      unawaited(_recoverResearchCaptures());
      if (_reconnectPausedForBackground) {
        _reconnectPausedForBackground = false;
        unawaited(_restoreRememberedDevice());
      }
      return;
    }
    _isAppForeground = false;
    _syncAiToastVisibility();
    if (_isReconnectBackgroundState(state)) {
      _reconnectPausedForBackground = true;
      unawaited(_pauseReconnectForBackground());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _onboardingController,
      builder: (context, _) {
        return AnimatedSwitcher(
          duration: EvtTheme.motionDuration,
          child: !_isOnboardingLoaded
              ? const AipinBrandSplash()
              : !_onboardingController.isComplete
              ? WelcomePage(
                  onConnectDevice: () => unawaited(
                    _completeOnboarding(destination: AppDestination.home),
                  ),
                  onUseLocalRecording: () => unawaited(
                    _completeOnboarding(destination: AppDestination.recording),
                  ),
                )
              : _buildConsumerShell(context),
        );
      },
    );
  }

  Widget _buildConsumerShell(BuildContext context) {
    final session = _sessionController;
    return AnimatedBuilder(
      animation: Listenable.merge([
        _discoveryController,
        _reconnectController,
        ?session,
      ]),
      builder: (context, _) {
        final canRecord = session?.state.isObservable ?? false;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: EvtTheme.systemUiOverlayStyle(Theme.of(context)),
          child: Scaffold(
            body: switch (_destination) {
              AppDestination.home => HomePage(
                device: _deviceSummary(),
                onConnectDevice: _openConnectionJourney,
                onStartLocalRecording: _openActiveRecording,
                onOpenSettings: _openSettings,
                onOpenDevice: session == null
                    ? null
                    : () => _openSessionDashboard(session),
              ),
              AppDestination.records =>
                _evidenceHistoryController == null ||
                        _recordingLibraryController == null
                    ? const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      )
                    : RecordsPage(
                        key: ValueKey('records-$_recordsInitialSelection'),
                        recordingController: _recordingLibraryController!,
                        evidenceController: _evidenceHistoryController!,
                        initialSelection: _recordsInitialSelection,
                        onOpenRecording: (recording) =>
                            unawaited(_openLocalRecordingDetail(recording)),
                      ),
              AppDestination.recording => RecordingHubPage(
                isHardwareObservable: canRecord,
                onStartLocal: _openActiveRecording,
                onOpenLibrary: _openLocalRecordingLibrary,
                onOpenHardware: canRecord
                    ? () => _openSessionDashboard(session!)
                    : null,
              ),
            },
            bottomNavigationBar: AppNavigationBar(
              selected: _destination,
              onSelected: _selectDestination,
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadOnboarding() async {
    await _onboardingController.load();
    if (mounted) {
      setState(() => _isOnboardingLoaded = true);
      if (_onboardingController.isComplete) {
        unawaited(_restoreRememberedDevice());
      }
    }
  }

  Future<void> _recoverResearchCaptures() async {
    final active = _researchRecovery;
    if (active != null) {
      return active;
    }
    final work = _recoverResearchCapturesInternal();
    _researchRecovery = work;
    try {
      await work;
    } finally {
      if (identical(_researchRecovery, work)) {
        _researchRecovery = null;
      }
    }
  }

  Future<void> _recoverResearchCapturesInternal() async {
    final processing = _researchProcessingController;
    await processing.enforceRetention();
    await processing.resumePending();
  }

  ResearchCaptureProcessingController get _researchProcessingController {
    final existing = _researchProcessing;
    if (existing != null) {
      return existing;
    }
    final processing = ref.read(researchCaptureProcessingControllerProvider);
    processing.addListener(_onResearchProcessingChanged);
    _researchProcessing = processing;
    return processing;
  }

  void _onResearchProcessingChanged() {
    final processing = _researchProcessing;
    if (processing == null) {
      return;
    }
    final updates = processing.drainUiUpdates();
    if (updates.isEmpty) {
      return;
    }
    if (!_isAppForeground) {
      _deferredResearchUpdates.addAll(updates);
      return;
    }
    _forwardResearchUpdates(updates);
  }

  void _flushDeferredResearchUpdates() {
    if (_deferredResearchUpdates.isEmpty) {
      return;
    }
    final updates = List<ResearchCaptureUiUpdate>.of(_deferredResearchUpdates);
    _deferredResearchUpdates.clear();
    _forwardResearchUpdates(updates);
  }

  void _forwardResearchUpdates(Iterable<ResearchCaptureUiUpdate> updates) {
    final batch = List<ResearchCaptureUiUpdate>.of(updates);
    _researchUpdateForwarding = _researchUpdateForwarding.then(
      (_) => _forwardResearchUpdatesInOrder(batch),
    );
  }

  Future<void> _forwardResearchUpdatesInOrder(
    Iterable<ResearchCaptureUiUpdate> updates,
  ) async {
    for (final update in updates) {
      switch (update.kind) {
        case ResearchCaptureUiUpdateKind.transcribing:
          _aiProcessingToast.showProcessing(
            taskId: update.captureId,
            stage: AiProcessingToastStage.transcribing,
          );
        case ResearchCaptureUiUpdateKind.transcriptionCompleted:
          _aiProcessingToast.complete(
            taskId: update.captureId,
            completedAt: update.completedAt!,
            recordingName: await _recordingNameFor(update),
            completionLabel: '转写完成',
            showCompletion: _recordingDetailDepth == 0,
          );
        case ResearchCaptureUiUpdateKind.summarizing:
          _aiProcessingToast.showProcessing(
            taskId: update.captureId,
            stage: AiProcessingToastStage.summarizing,
          );
        case ResearchCaptureUiUpdateKind.completed:
          _aiProcessingToast.complete(
            taskId: update.captureId,
            completedAt: update.completedAt!,
            recordingName: await _recordingNameFor(update),
          );
        case ResearchCaptureUiUpdateKind.failed:
          _aiProcessingToast.dismiss(
            update.captureId,
            failureLabel: switch (update.processingState) {
              ResearchProcessingState.transcriptionFailed => '转写失败',
              ResearchProcessingState.summaryFailed => 'AI 总结失败',
              ResearchProcessingState.uploadFailed => '上传失败',
              _ => 'AI 处理失败',
            },
          );
      }
    }
  }

  Future<String> _recordingNameFor(ResearchCaptureUiUpdate update) async {
    final recordingId = update.originalLocalRecordingId;
    if (recordingId == null) {
      return 'AI 语音';
    }
    final recordings = await ref.read(localRecordingRepositoryProvider).all();
    for (final recording in recordings) {
      if (recording.id == recordingId && recording.title.trim().isNotEmpty) {
        return recording.title.trim();
      }
    }
    return '录音';
  }

  void _syncAiToastVisibility() {
    _aiProcessingToast.setPresentationEnabled(
      _isAppForeground && _recordingDetailDepth == 0,
    );
  }

  void _setRecordingDetailVisible(bool visible) {
    if (!mounted) {
      return;
    }
    _recordingDetailDepth += visible ? 1 : -1;
    if (_recordingDetailDepth < 0) {
      _recordingDetailDepth = 0;
    }
    _syncAiToastVisibility();
  }

  void _attachAiProcessingToast() {
    if (!mounted || _aiProcessingToastEntry != null) {
      return;
    }
    final entry = OverlayEntry(
      builder: (_) => AiProcessingToastHost(controller: _aiProcessingToast),
    );
    _aiProcessingToastEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  Future<void> _completeOnboarding({
    required AppDestination destination,
  }) async {
    await _onboardingController.complete();
    if (!mounted) {
      return;
    }
    setState(() {
      _isOnboardingLoaded = true;
      _destination = destination;
    });
    if (destination == AppDestination.home) {
      unawaited(_restoreRememberedDevice(startDiscoveryWhenNoRecord: true));
    }
  }

  void _selectDestination(AppDestination destination) {
    if (destination == AppDestination.records) {
      _openEvidenceHistory();
      return;
    }
    setState(() => _destination = destination);
  }

  DeviceSummary _deviceSummary() {
    final session = _sessionController?.state;
    final candidate = session?.session?.candidate;
    final reconnect = _reconnectController.state;
    if (candidate != null) {
      if (session!.isObservable) {
        final recordingLabel = switch (session.latestSnapshot?.state) {
          DeviceState.recording => '正在录音',
          DeviceState.paused => '已暂停',
          DeviceState.standby => '未在录音',
          _ => '暂时无法获取',
        };
        return DeviceSummary.connected(
          name: candidate.name,
          recordingLabel: recordingLabel,
        );
      }
      if (reconnect.phase == DeviceReconnectPhase.connecting ||
          reconnect.phase == DeviceReconnectPhase.waitingToRetry ||
          reconnect.phase == DeviceReconnectPhase.scanning) {
        return DeviceSummary.reconnecting(name: candidate.name);
      }
      if (reconnect.phase == DeviceReconnectPhase.exhausted) {
        return DeviceSummary.reconnectFailed(name: candidate.name);
      }
      if (session.phase == SessionPhase.interrupted) {
        return DeviceSummary.disconnected(name: candidate.name);
      }
      return DeviceSummary.searching(name: candidate.name);
    }
    final discovery = _discoveryController.state;
    final rememberedName = reconnect.rememberedDevice?.displayName;
    final name = discovery.selected?.name ?? rememberedName ?? 'AIPIN';
    if (reconnect.phase == DeviceReconnectPhase.connecting ||
        reconnect.phase == DeviceReconnectPhase.waitingToRetry ||
        reconnect.phase == DeviceReconnectPhase.scanning) {
      return DeviceSummary.reconnecting(name: name);
    }
    if (reconnect.phase == DeviceReconnectPhase.exhausted) {
      return DeviceSummary.reconnectFailed(name: name);
    }
    return discovery.isScanning
        ? DeviceSummary.searching(name: name)
        : DeviceSummary.disconnected(name: name);
  }

  void _openConnectionJourney() {
    unawaited(_startExplicitConnectionJourney());
    unawaited(
      Navigator.of(context)
          .push<void>(
            MaterialPageRoute(
              builder: (context) => DiscoveryPage(
                controller: _discoveryController,
                onConnect: _openSession,
                onStartScan: _startExplicitConnectionJourney,
                onStopScan: _stopConnectionJourneyScan,
                onSettings: _openSettings,
                bluetoothEnableGateway: ref.read(
                  bluetoothEnableGatewayProvider,
                ),
                onOpenBluetoothSettings: () async {
                  await ref.read(appPermissionGatewayProvider).openSettings();
                },
              ),
            ),
          )
          .whenComplete(() => unawaited(_onConnectionJourneyClosed())),
    );
  }

  Future<void> _startExplicitConnectionJourney() async {
    if (_hasActiveOrConnectingSession) {
      return;
    }
    await _reconnectController.startExplicitCycle();
    if (!mounted || _hasActiveOrConnectingSession) {
      return;
    }
    // A first-time device has no private history, so the explicit reconnect
    // cycle intentionally does not own a scan in that case.
    if (!_discoveryController.state.isScanning) {
      _discoveryController.start();
    }
  }

  Future<void> _onConnectionJourneyClosed() async {
    if (_hasActiveOrConnectingSession) {
      return;
    }
    await _reconnectController.cancelAutomaticCycle();
  }

  Future<void> _stopConnectionJourneyScan() async {
    await _reconnectController.cancelAutomaticCycle();
  }

  Future<void> _restoreRememberedDevice({
    bool startDiscoveryWhenNoRecord = false,
  }) async {
    if (!mounted ||
        !_isAppForeground ||
        !_isOnboardingLoaded ||
        !_onboardingController.isComplete ||
        _hasActiveOrConnectingSession) {
      return;
    }
    await _reconnectController.restoreAndStart();
    if (!mounted ||
        !_isAppForeground ||
        _hasActiveOrConnectingSession ||
        !startDiscoveryWhenNoRecord ||
        _discoveryController.state.isScanning) {
      return;
    }
    _discoveryController.start();
  }

  bool get _hasActiveOrConnectingSession {
    final phase = _sessionController?.state.phase;
    return phase != null && phase != SessionPhase.interrupted;
  }

  bool _isReconnectBackgroundState(AppLifecycleState state) => switch (state) {
    AppLifecycleState.paused ||
    AppLifecycleState.hidden ||
    AppLifecycleState.detached => true,
    _ => false,
  };

  Future<void> _pauseReconnectForBackground() {
    final activePause = _reconnectBackgroundPause;
    if (activePause != null) {
      return activePause;
    }
    final pause = _reconnectController.pauseForBackground();
    _reconnectBackgroundPause = pause;
    return pause.whenComplete(() {
      if (identical(_reconnectBackgroundPause, pause)) {
        _reconnectBackgroundPause = null;
      }
    });
  }

  void _onDiscoveryChanged() {
    final state = _discoveryController.state;
    if (!state.isScanning) {
      _reconnectController.notifyScanStopped();
    }
    for (final candidate in state.candidates) {
      unawaited(_reconnectController.considerCandidate(candidate));
    }
  }

  void _openSessionDashboard(SessionController session) {
    final auth = _deviceAuthController;
    final realtimeAudio = RealtimeAudioController(
      gateway: session,
      codec: EvtProtocolCodec(),
    );
    unawaited(
      Navigator.of(context)
          .push<void>(
            MaterialPageRoute(
              builder: (context) => AnimatedBuilder(
                animation: Listenable.merge([session, realtimeAudio, ?auth]),
                builder: (context, _) => DeviceDetailPage(
                  state: session.state,
                  onDisconnect: () => unawaited(_disconnectSession(session)),
                  onRetry: () => _retrySession(session),
                  onOpenChecking: () => _openObservation(session.state),
                  onOpenLogs: _openDeviceLogs,
                  onOpenFiles: () => unawaited(_openDeviceFiles(session)),
                  onRecordAction: (action) =>
                      unawaited(_setHardwareRecordAction(session, action)),
                  onRefreshDeviceDetails: () =>
                      unawaited(_refreshDeviceDetails(session)),
                  onRecordConsentChanged: (granted) =>
                      unawaited(_setDeviceRecordConsent(session, granted)),
                  onPrivacyDurationChanged: (durationCode) =>
                      unawaited(_setPrivacyDuration(session, durationCode)),
                  authState: auth?.state ?? DeviceAuthState.unknown,
                  onAuthenticate: auth == null
                      ? null
                      : () => unawaited(_authenticateDevice(session, auth)),
                  onBind: auth == null
                      ? null
                      : () => unawaited(_bindDevice(session, auth)),
                  clearPreparation: auth?.pendingClear,
                  onPrepareClear: auth == null
                      ? null
                      : () => _prepareDeviceClear(session, auth),
                  onConfirmClear: auth == null
                      ? null
                      : () => _confirmDeviceClear(session, auth),
                  canOpenFiles:
                      (auth?.allows(DevicePermission.files) ?? false) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.ff10Ff12,
                        BleOperation.write,
                      ) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.ff10Ff12,
                        BleOperation.indicate,
                      ) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.ff10Ff13,
                        BleOperation.write,
                      ) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.ff10Ff13,
                        BleOperation.notify,
                      ) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.ff10Ff16,
                        BleOperation.write,
                      ) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.ff10Ff16,
                        BleOperation.indicate,
                      ),
                  canControlRecording:
                      (auth?.allows(DevicePermission.configuration) ?? false) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.fa10Fa17,
                        BleOperation.write,
                      ) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.fa10Fa17,
                        BleOperation.indicate,
                      ),
                  canConfigureDevice:
                      (auth?.allows(DevicePermission.configuration) ?? false) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.fa10Fa12,
                        BleOperation.write,
                      ) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.fa10Fa12,
                        BleOperation.indicate,
                      ) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.fa10Fa16,
                        BleOperation.write,
                      ) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.fa10Fa16,
                        BleOperation.indicate,
                      ),
                  canRefreshDeviceDetails:
                      (auth?.allows(DevicePermission.status) ?? false) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.fa10Fa16,
                        BleOperation.write,
                      ) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.fa10Fa16,
                        BleOperation.indicate,
                      ),
                  onOpenFirmwareUpdate: () =>
                      unawaited(_openFirmwareUpdate(session)),
                  canUpdateFirmware:
                      (auth?.allows(DevicePermission.ota) ?? false) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.wqota2001,
                        BleOperation.writeWithoutResponse,
                      ) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.wqota2002,
                        BleOperation.notify,
                      ),
                  realtimeAudioController: realtimeAudio,
                  canCaptureRealtimeAudio:
                      (auth?.allows(DevicePermission.realtimeAudio) ?? false) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.fa10Fa12,
                        BleOperation.write,
                      ) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.fa10Fa12,
                        BleOperation.indicate,
                      ) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.fa10Fa17,
                        BleOperation.write,
                      ) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.fa10Fa17,
                        BleOperation.indicate,
                      ) &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.fa10Fa18,
                        BleOperation.notify,
                      ),
                  onExportRealtimeAudio: _exportRealtimeAudio,
                ),
              ),
            ),
          )
          .whenComplete(realtimeAudio.dispose),
    );
  }

  Future<void> _exportRealtimeAudio(RealtimeAudioCapture capture) async {
    try {
      await ref
          .read(binaryDocumentExporterProvider)
          .export(
            fileName: capture.exportFileName,
            bytes: capture.bytes,
            mimeType: 'application/octet-stream',
          );
      if (mounted) {
        AppToast.show(context, message: '实时音频原始数据已导出');
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, message: '原始数据导出失败，请重试');
      }
    }
  }

  Future<void> _openFirmwareUpdate(SessionController session) async {
    final candidate = session.state.session?.candidate;
    final physicalDeviceId = candidate?.physicalDeviceId;
    if (candidate == null ||
        physicalDeviceId == null ||
        _deviceAuthController?.allows(DevicePermission.ota) != true ||
        !session.state.supportsEndpoint(
          BleLogicalEndpoint.wqota2001,
          BleOperation.writeWithoutResponse,
        ) ||
        !session.state.supportsEndpoint(
          BleLogicalEndpoint.wqota2002,
          BleOperation.notify,
        )) {
      return;
    }
    WqotaClient? updateClient;

    Future<void> closeUpdateChannel() async {
      final client = updateClient;
      updateClient = null;
      if (client != null) {
        await session.closeWqotaClient(client);
      }
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FirmwareUpdatePage(
          deviceId: physicalDeviceId,
          deviceName: candidate.name,
          loadPackage: () => ref
              .read(firmwarePackageGatewayProvider)
              .loadForDevice(physicalDeviceId),
          createUpdateController: (package) {
            final client = session.openWqotaClient(
              WqotaCodec(
                wireFormat: WqotaWireFormat(
                  requestPrefixFlags: package.wqotaRequestPrefixFlags,
                  responsePrefixFlags: package.wqotaResponsePrefixFlags,
                ),
              ),
            );
            updateClient = client;
            return WqotaUpdateController(
              checkpoints: ref.read(firmwareUpdateCheckpointRepositoryProvider),
              gateway: WqotaBleUpdateGateway(
                client: client,
                requestMtu: session.requestWqotaMtu,
                wqotaFinalVerificationSupported:
                    package.wqotaFinalVerificationSupported,
                verifyBusinessVersionCallback: (expectedBusinessVersion) async {
                  final actual = session.state.deviceInfo?.softwareVersion;
                  return actual?.trim() == expectedBusinessVersion.trim();
                },
              ),
            );
          },
          reconnectAndVerify: (controller) async {
            await session.connect(candidate);
            await _waitForAuthenticationReadySession(session);
            final auth = _deviceAuthController;
            if (auth == null) {
              throw StateError('设备认证控制器不可用。');
            }
            await auth.authenticate(session, deviceId: physicalDeviceId);
            await session.synchronizeAfterAuthentication(
              _grantedPermissions(auth),
            );
            await controller.verifyAfterReconnect();
          },
          closeUpdateChannel: closeUpdateChannel,
        ),
      ),
    );
  }

  Future<void> _waitForAuthenticationReadySession(
    SessionController session,
  ) async {
    if (session.state.isAuthenticationReady) {
      return;
    }
    final ready = Completer<void>();
    void listener() {
      if (session.state.isAuthenticationReady && !ready.isCompleted) {
        ready.complete();
      } else if (session.state.phase == SessionPhase.interrupted &&
          !ready.isCompleted) {
        ready.completeError(
          StateError(session.state.failure?.message ?? '设备重连失败。'),
        );
      }
    }

    session.addListener(listener);
    listener();
    try {
      await ready.future.timeout(const Duration(seconds: 20));
    } finally {
      session.removeListener(listener);
    }
  }

  Future<bool> _connectRememberedDevice(DeviceCandidate candidate) {
    return _openSession(candidate, automaticallyReconnect: true);
  }

  Future<bool> _openSession(
    DeviceCandidate candidate, {
    bool automaticallyReconnect = false,
  }) async {
    final operation = ++_sessionConnectionOperation;
    if (!automaticallyReconnect) {
      await _reconnectController.takeOverManualConnection();
      if (!_isCurrentSessionConnectionOperation(operation)) {
        return false;
      }
    }

    SessionController? createdSession;
    DeviceAuthController? createdAuth;
    try {
      final physicalDeviceId = candidate.physicalDeviceId;
      if (physicalDeviceId == null) {
        throw StateError('设备广播身份无效。');
      }
      await _discoveryController.stop();
      if (!_isCurrentSessionConnectionOperation(operation)) {
        return false;
      }
      final profile = await const DeviceProfileLoader().load(rootBundle);
      if (!_isCurrentSessionConnectionOperation(operation)) {
        return false;
      }
      _disposeCurrentSessionControllers();
      final controller = SessionController(
        ref.read(bleTransportProvider),
        profile,
        EvtProtocolCodec(),
        logger: ref.read(scopedAppLoggerProvider('SESSION')),
      );
      final authController = DeviceAuthController(
        ticketGateway: ref.read(ticketGatewayProvider),
        onClearCompleted: (deviceId) async {
          await ref
              .read(deviceFileDownloadCheckpointRepositoryProvider)
              .removeAllForDevice(deviceId);
          await _reconnectController.forgetSuccessfulClear(candidate);
        },
        clearCheckpoints: ref.read(deviceClearCheckpointRepositoryProvider),
      );
      createdSession = controller;
      createdAuth = authController;
      controller.addListener(_onSessionChanged);
      if (!_isCurrentSessionConnectionOperation(operation)) {
        controller.removeListener(_onSessionChanged);
        controller.dispose();
        authController.dispose();
        return false;
      }
      setState(() {
        _sessionController = controller;
        _deviceAuthController = authController;
        _profile = profile;
        _destination = AppDestination.home;
      });
      _syncDiscoveryExclusions();
      await controller.connect(candidate);
      if (!_isCurrentSessionConnectionOperation(operation) ||
          !identical(_sessionController, controller)) {
        return false;
      }
      final connected = controller.state.isAuthenticationReady;
      if (connected) {
        unawaited(
          _resumePendingDeviceClear(
            controller,
            authController,
            physicalDeviceId,
          ),
        );
      }
      return connected;
    } catch (_) {
      if (_isCurrentSessionConnectionOperation(operation) &&
          identical(_sessionController, createdSession)) {
        _disposeCurrentSessionControllers();
        setState(() {
          _sessionController = null;
          _deviceAuthController = null;
        });
      } else if (!identical(_sessionController, createdSession)) {
        createdSession?.removeListener(_onSessionChanged);
        createdSession?.dispose();
        createdAuth?.dispose();
      }
      _syncDiscoveryExclusions();
      return false;
    }
  }

  bool _isCurrentSessionConnectionOperation(int operation) {
    return mounted && operation == _sessionConnectionOperation;
  }

  void _disposeCurrentSessionControllers() {
    _sessionController?.removeListener(_onSessionChanged);
    _sessionController?.dispose();
    _deviceAuthController?.dispose();
    _resetSessionReconnectTracking();
  }

  void _resetSessionReconnectTracking() {
    _sessionReachedAuthenticationReady = false;
    _sessionHistoryPersisted = false;
    _unexpectedReconnectStarted = false;
    _sessionHistoryPersistence = null;
  }

  void _onSessionChanged() {
    _syncDiscoveryExclusions();
    final controller = _sessionController;
    final state = controller?.state;
    if (state == null) {
      return;
    }

    // SessionController emits this transition at the beginning of every
    // connection attempt, including a manual retry on the same controller.
    if (state.phase == SessionPhase.discovered ||
        state.phase == SessionPhase.connecting) {
      _resetSessionReconnectTracking();
      return;
    }
    final candidate = state.session?.candidate;
    if (candidate == null) {
      return;
    }
    if (state.isAuthenticationReady) {
      _sessionReachedAuthenticationReady = true;
      if (!_sessionHistoryPersisted) {
        _sessionHistoryPersisted = true;
        final persistence = _reconnectController.rememberSuccessfulConnection(
          candidate,
        );
        _sessionHistoryPersistence = persistence;
        unawaited(persistence);
      }
      return;
    }
    if (state.phase == SessionPhase.interrupted &&
        _sessionReachedAuthenticationReady &&
        !_unexpectedReconnectStarted) {
      _unexpectedReconnectStarted = true;
      final persistence = _sessionHistoryPersistence;
      if (persistence == null) {
        unawaited(_reconnectController.markUnexpectedDisconnect());
      } else {
        unawaited(_reconnectAfterHistoryPersists(persistence));
      }
    }
  }

  Future<void> _reconnectAfterHistoryPersists(Future<void> persistence) async {
    try {
      await persistence;
    } catch (_) {
      // The reconnect controller handles storage errors as a recoverable
      // condition; a lost session can still use any previous record.
    }
    if (!mounted ||
        !_unexpectedReconnectStarted ||
        _sessionController?.state.phase != SessionPhase.interrupted) {
      return;
    }
    await _reconnectController.markUnexpectedDisconnect();
  }

  void _showRecordObservation(SessionState state) {
    final session = state.session;
    final snapshot = state.latestSnapshot;
    final physicalDeviceId = session?.candidate.physicalDeviceId;
    if (session == null || snapshot == null || physicalDeviceId == null) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => RecordObservationSheet(
        repository: ref.read(evidenceRepositoryProvider),
        deviceId: physicalDeviceId,
        deviceName: session.candidate.name,
        latestSnapshot: snapshot,
        events: state.events,
        onSaved: () {
          final controller = _evidenceHistoryController;
          if (controller != null) {
            unawaited(controller.load());
          }
        },
      ),
    );
  }

  void _openEvidenceHistory({int initialSelection = 0}) {
    _evidenceHistoryController ??= EvidenceHistoryController(
      ref.read(evidenceRepositoryProvider),
    );
    setState(() {
      _destination = AppDestination.records;
      _recordsInitialSelection = initialSelection;
    });
    unawaited(_prepareRecords());
    unawaited(_recoverResearchCaptures());
  }

  Future<void> _prepareRecords() async {
    await _ensureRecordingControllers();
    final library = _recordingLibraryController;
    final evidence = _evidenceHistoryController;
    if (library != null) {
      unawaited(library.load());
    }
    if (evidence != null) {
      unawaited(evidence.load());
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _retrySession(SessionController controller) {
    final candidate = controller.state.session?.candidate;
    if (candidate != null) {
      unawaited(_retrySessionExplicitly(controller, candidate));
    }
  }

  Future<void> _retrySessionExplicitly(
    SessionController controller,
    DeviceCandidate candidate,
  ) async {
    _sessionConnectionOperation += 1;
    await _reconnectController.takeOverManualConnection();
    if (!mounted || !identical(_sessionController, controller)) {
      return;
    }
    await controller.connect(candidate);
  }

  Future<void> _disconnectSession(SessionController controller) async {
    _sessionConnectionOperation += 1;
    await _reconnectController.suppressForForeground();
    if (!mounted || !identical(_sessionController, controller)) {
      return;
    }
    await controller.disconnect();
    _discoveryController.setExcludedDeviceIds(const []);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _resumePendingDeviceClear(
    SessionController session,
    DeviceAuthController auth,
    String deviceId,
  ) async {
    try {
      await _waitForAuthenticationReadySession(session);
      if (!await auth.restorePendingClear(deviceId)) {
        return;
      }
      await auth.resumeClearStatus(session);
      if (mounted) {
        AppToast.show(context, message: '设备数据清除已完成');
      }
    } catch (error) {
      ref
          .read(scopedAppLoggerProvider('AUTH'))
          .info('clear_resume_failed', fields: {'error': '$error'});
    }
  }

  Future<void> _openDeviceLogs() async {
    final store = ref.read(appLogStoreProvider);
    await store.initialize();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => DeviceLogPage(store: store)),
    );
  }

  Future<void> _setHardwareRecordAction(
    SessionController session,
    int action,
  ) async {
    if (_deviceAuthController?.allows(DevicePermission.configuration) != true) {
      if (mounted) {
        AppToast.show(context, message: '当前认证未授予设备录音控制权限');
      }
      return;
    }
    try {
      await session.setRecordAction(action);
    } catch (error) {
      if (mounted) {
        AppToast.show(context, message: '设备录音操作失败，请重试');
      }
    }
  }

  Future<void> _refreshDeviceDetails(SessionController session) async {
    if (_deviceAuthController?.allows(DevicePermission.status) != true) {
      if (mounted) {
        AppToast.show(context, message: '当前认证未授予设备状态读取权限');
      }
      return;
    }
    try {
      await session.refreshDeviceDetails(const {DevicePermission.status});
    } catch (_) {
      if (mounted) {
        AppToast.show(context, message: '设备状态刷新失败，请重试');
      }
    }
  }

  Future<void> _setDeviceRecordConsent(
    SessionController session,
    bool granted,
  ) async {
    if (_deviceAuthController?.allows(DevicePermission.configuration) != true) {
      if (mounted) {
        AppToast.show(context, message: '当前认证未授予设备配置权限');
      }
      return;
    }
    try {
      await session.setRecordConsent(granted);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, message: '设备录音授权更新失败，请重试');
      }
    }
  }

  Future<void> _setPrivacyDuration(
    SessionController session,
    int durationCode,
  ) async {
    if (_deviceAuthController?.allows(DevicePermission.configuration) != true) {
      if (mounted) {
        AppToast.show(context, message: '当前认证未授予设备配置权限');
      }
      return;
    }
    try {
      await session.setPrivacyDuration(durationCode);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, message: '默认隐私时长更新失败，请重试');
      }
    }
  }

  Future<void> _authenticateDevice(
    SessionController session,
    DeviceAuthController auth,
  ) async {
    final deviceId = session.state.session?.candidate.physicalDeviceId;
    if (deviceId == null) {
      return;
    }
    try {
      await auth.authenticate(session, deviceId: deviceId);
      await session.synchronizeAfterAuthentication(_grantedPermissions(auth));
      if (mounted) {
        AppToast.show(context, message: '设备认证完成');
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(context, message: '$error');
      }
    }
  }

  Future<void> _bindDevice(
    SessionController session,
    DeviceAuthController auth,
  ) async {
    final deviceId = session.state.session?.candidate.physicalDeviceId;
    if (deviceId == null) {
      return;
    }
    try {
      await auth.bind(session, deviceId: deviceId);
      await session.synchronizeAfterAuthentication(_grantedPermissions(auth));
      if (mounted) {
        AppToast.show(context, message: '设备绑定完成');
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(context, message: '$error');
      }
    }
  }

  Set<DevicePermission> _grantedPermissions(DeviceAuthController auth) => {
    for (final permission in DevicePermission.values)
      if (auth.allows(permission)) permission,
  };

  Future<void> _prepareDeviceClear(
    SessionController session,
    DeviceAuthController auth,
  ) async {
    final deviceId = session.state.session?.candidate.physicalDeviceId;
    if (deviceId == null) {
      return;
    }
    try {
      await auth.prepareClear(session, deviceId: deviceId);
      if (mounted) {
        AppToast.show(context, message: '请确认设备清除范围');
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(context, message: '$error');
      }
    }
  }

  Future<void> _confirmDeviceClear(
    SessionController session,
    DeviceAuthController auth,
  ) async {
    final deviceId = session.state.session?.candidate.physicalDeviceId;
    if (deviceId == null) {
      return;
    }
    try {
      await auth.confirmClear(session, deviceId: deviceId);
      _sessionConnectionOperation += 1;
      await _reconnectController.suppressForForeground();
      if (!mounted || !identical(_sessionController, session)) {
        return;
      }
      await session.disconnect();
      if (mounted) {
        AppToast.show(context, message: '设备已解除绑定并完成数据清除');
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(context, message: '$error');
      }
    }
  }

  Future<void> _openDeviceFiles(SessionController session) async {
    if (_deviceAuthController?.allows(DevicePermission.files) != true) {
      if (mounted) {
        AppToast.show(context, message: '当前认证未授予设备文件权限');
      }
      return;
    }
    final deviceId = session.state.session?.candidate.physicalDeviceId;
    if (deviceId == null || !session.state.isObservable || !mounted) {
      return;
    }
    final importer = DeviceFileImportService(
      deviceId: deviceId,
      gateway: session,
      archive: ref.read(archiveGatewayProvider),
      files: ref.read(recordingFileStoreProvider),
      checkpoints: ref.read(deviceFileDownloadCheckpointRepositoryProvider),
      recordings: ref.read(localRecordingRepositoryProvider),
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DeviceFileBrowserPage(
          onListFiles: ({required offset, required pageSize}) =>
              session.listFiles(offset: offset, pageSize: pageSize),
          onImport: importer.import,
        ),
      ),
    );
    if (mounted) {
      await _recordingLibraryController?.load();
    }
  }

  void _syncDiscoveryExclusions() {
    final session = _sessionController?.state;
    final candidate = session?.session?.candidate;
    if (session?.hasActiveBleConnection != true) {
      _deviceAuthController?.revokeForConnectionLoss();
    }
    _discoveryController.setExcludedDeviceIds(
      session?.hasActiveBleConnection == true && candidate != null
          ? [candidate.connectionId]
          : const [],
    );
  }

  Future<void> _ensureRecordingControllers() async {
    if (_recordingController != null && _recordingLibraryController != null) {
      return;
    }
    final activeSetup = _recordingSetup;
    if (activeSetup != null) {
      return activeSetup;
    }
    final setup = _createRecordingControllers();
    _recordingSetup = setup;
    try {
      await setup;
    } finally {
      _recordingSetup = null;
    }
  }

  Future<void> _createRecordingControllers() async {
    final repository = ref.read(localRecordingRepositoryProvider);
    final files = ref.read(recordingFileStoreProvider);
    final controller = RecordingController(
      repository: repository,
      recorder: ref.read(audioRecorderProvider),
      files: files,
      background: ref.read(recordingBackgroundProvider),
    );
    final library = RecordingLibraryController(
      repository: repository,
      files: files,
      player: ref.read(audioPlayerProvider),
    );
    try {
      await RecordingRecoveryService(
        repository: repository,
        files: files,
      ).reconcile();
    } catch (_) {
      // The library surfaces repository failures when the user opens it.
    }
    if (!mounted) {
      await library.close();
      await controller.close();
      return;
    }
    controller.addListener(_syncRecordingLibrary);
    setState(() {
      _recordingController = controller;
      _recordingLibraryController = library;
    });
  }

  Future<void> _openActiveRecording() async {
    await _ensureRecordingControllers();
    final controller = _recordingController;
    if (!mounted || controller == null) {
      return;
    }
    final saved = await Navigator.of(context).push<LocalRecording?>(
      PageRouteBuilder<LocalRecording?>(
        transitionDuration: EvtTheme.motionDuration,
        reverseTransitionDuration: EvtTheme.motionDuration,
        pageBuilder: (_, _, _) => ActiveRecordingPage(controller: controller),
        transitionsBuilder: (_, animation, _, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curvedAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: child,
            ),
          );
        },
      ),
    );
    if (!mounted) {
      return;
    }
    if (saved != null) {
      await _requestAiProcessing(saved);
      if (!mounted) {
        return;
      }
      _openSavedRecording();
      return;
    }
    final library = _recordingLibraryController;
    if (library != null) {
      unawaited(library.load());
    }
  }

  Future<void> _openLocalRecordingLibrary() async {
    await _ensureRecordingControllers();
    final library = _recordingLibraryController;
    if (!mounted || library == null) {
      return;
    }
    await library.load();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => LocalRecordingLibraryPage(
          controller: library,
          onStartRecording: _openActiveRecording,
          onOpen: (recording) =>
              unawaited(_openLocalRecordingDetail(recording)),
        ),
      ),
    );
  }

  void _openSavedRecording() {
    _openEvidenceHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppToast.show(context, message: '录音已保存到记录');
      }
    });
  }

  Future<ResearchCapture?> _requestAiProcessing(
    LocalRecording recording,
  ) async {
    if (!_canUseAiProcessing(recording)) {
      return null;
    }
    if (!await _ensureResearchConsent()) {
      return null;
    }
    if (!mounted) {
      return null;
    }
    final approved = await ResearchUploadConfirmationSheet.show(context);
    if (!approved || !mounted) {
      return null;
    }
    final capture = await _researchProcessingController
        .createFromLocalRecording(recording);
    if (mounted) {
      AppToast.show(context, message: '已开始 AI 转写和总结');
    }
    return capture;
  }

  Future<bool> _ensureResearchConsent() async {
    final library = ref.read(researchCaptureLibraryControllerProvider);
    if (await library.hasAcceptedConsent()) {
      return true;
    }
    if (!mounted || !await ResearchConsentSheet.show(context)) {
      return false;
    }
    await library.acceptConsent();
    return true;
  }

  Future<void> _openLocalRecordingDetail(LocalRecording recording) async {
    await _ensureRecordingControllers();
    final library = _recordingLibraryController;
    if (library == null) {
      return;
    }
    await library.load();
    if (!mounted) {
      return;
    }
    _setRecordingDetailVisible(true);
    try {
      await Navigator.of(
        context,
      ).push<void>(_localRecordingDetailRoute(recording, library.state.items));
    } finally {
      _setRecordingDetailVisible(false);
    }
  }

  void _replaceLocalRecordingDetail(
    LocalRecording recording,
    List<LocalRecording> recordings,
  ) {
    if (!mounted) {
      return;
    }
    _setRecordingDetailVisible(true);
    unawaited(
      Navigator.of(context)
          .pushReplacement<void, void>(
            _localRecordingDetailRoute(recording, recordings),
          )
          .whenComplete(() => _setRecordingDetailVisible(false)),
    );
  }

  MaterialPageRoute<void> _localRecordingDetailRoute(
    LocalRecording recording,
    List<LocalRecording> recordings,
  ) {
    return MaterialPageRoute<void>(
      builder: (context) => LocalRecordingDetailPage(
        recording: recording,
        recordings: recordings,
        onOpenRecording: (next) =>
            _replaceLocalRecordingDetail(next, recordings),
        localFiles: ref.read(recordingFileStoreProvider),
        audioPlayerFactory: ref.read(audioPlayerFactoryProvider),
        researchRepository: ref.read(researchCaptureRepositoryProvider),
        researchLibrary: ref.read(researchCaptureLibraryControllerProvider),
        researchProcessing: _researchProcessingController,
        onRequestAiProcessing: _requestAiProcessing,
      ),
    );
  }

  bool _canUseAiProcessing(LocalRecording recording) {
    final duration = recording.duration;
    return recording.isPlayable &&
        duration != null &&
        duration >= const Duration(seconds: 2);
  }

  void _syncRecordingLibrary() {
    _recordingLibraryController?.setCaptureActive(
      _recordingController?.state.isCaptureActive ?? false,
    );
  }

  Future<void> _openObservation(
    SessionState state, {
    ObservationScenario initialScenario = ObservationScenario.deviceAccess,
  }) async {
    final session = state.session;
    final snapshot = state.latestSnapshot;
    final physicalDeviceId = session?.candidate.physicalDeviceId;
    if (session == null || snapshot == null || physicalDeviceId == null) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => ObservationPage(
          repository: ref.read(evidenceRepositoryProvider),
          deviceId: physicalDeviceId,
          deviceName: session.candidate.name,
          latestSnapshot: snapshot,
          events: state.events,
          initialScenario: initialScenario,
          onRecordPhysicalFeedback: () => _showRecordObservation(state),
          onSaved: _refreshEvidenceHistory,
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    DeviceProfile profile;
    try {
      profile = _profile ?? await const DeviceProfileLoader().load(rootBundle);
    } catch (_) {
      profile = DeviceProfile.empty();
    }
    if (!mounted) {
      return;
    }
    setState(() => _profile = profile);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          profile: profile,
          themeController: widget.themeController,
          permissions: ref.read(appPermissionGatewayProvider),
          researchProcessing: _researchProcessingController,
        ),
      ),
    );
  }

  void _refreshEvidenceHistory() {
    final controller = _evidenceHistoryController;
    if (controller != null) {
      unawaited(controller.load());
    }
  }
}
