import 'dart:async';

import 'package:aipin/app/app_destination.dart';
import 'package:aipin/app/branding/aipin_brand_splash.dart';
import 'package:aipin/app/providers.dart';
import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/ble/device_profile_loader.dart';
import 'package:aipin/core/design_system/evt_theme.dart';
import 'package:aipin/core/design_system/widgets/app_navigation_bar.dart';
import 'package:aipin/core/design_system/widgets/app_toast.dart';
import 'package:aipin/core/design_system/widgets/ai_processing_toast.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/features/device_discovery/application/discovery_controller.dart';
import 'package:aipin/features/device_discovery/domain/advertisement_filter.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:aipin/features/device_discovery/presentation/discovery_page.dart';
import 'package:aipin/features/device_session/application/session_controller.dart';
import 'package:aipin/features/device_session/application/session_state.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/device_session/presentation/device_detail_page.dart';
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
  late final OnboardingController _onboardingController;
  SessionController? _sessionController;
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
  var _recordingDetailDepth = 0;
  OverlayEntry? _aiProcessingToastEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _discoveryController = DiscoveryController(
      ref.read(bleTransportProvider),
      const AdvertisementFilter(),
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
    _discoveryController.dispose();
    _onboardingController.dispose();
    _sessionController?.removeListener(_syncDiscoveryExclusions);
    _sessionController?.dispose();
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
      return;
    }
    _isAppForeground = false;
    _syncAiToastVisibility();
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
      animation: session ?? _discoveryController,
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
      _discoveryController.start();
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
    if (candidate != null) {
      if (session!.isObservable) {
        final recordingLabel = switch (session.latestSnapshot?.state) {
          DeviceState.recording => '正在录音',
          DeviceState.standby => '未在录音',
          _ => '暂时无法获取',
        };
        return DeviceSummary.connected(
          name: candidate.name,
          recordingLabel: recordingLabel,
        );
      }
      return DeviceSummary.searching(name: candidate.name);
    }
    final discovery = _discoveryController.state;
    final name = discovery.selected?.name ?? 'AIPIN';
    return discovery.isScanning
        ? DeviceSummary.searching(name: name)
        : DeviceSummary.disconnected(name: name);
  }

  void _openConnectionJourney() {
    _discoveryController.start();
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => DiscoveryPage(
            controller: _discoveryController,
            onConnect: _openSession,
            onSettings: _openSettings,
            bluetoothEnableGateway: ref.read(bluetoothEnableGatewayProvider),
            onOpenBluetoothSettings: () async {
              await ref.read(appPermissionGatewayProvider).openSettings();
            },
          ),
        ),
      ),
    );
  }

  void _openSessionDashboard(SessionController session) {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => AnimatedBuilder(
            animation: session,
            builder: (context, _) => DeviceDetailPage(
              state: session.state,
              onDisconnect: () => unawaited(_disconnectSession(session)),
              onRetry: () => _retrySession(session),
              onOpenChecking: () => _openObservation(session.state),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSession(DeviceCandidate candidate) async {
    try {
      await _discoveryController.stop();
      final profile = await const DeviceProfileLoader().load(rootBundle);
      if (!mounted) {
        return;
      }
      _sessionController?.removeListener(_syncDiscoveryExclusions);
      _sessionController?.dispose();
      final controller = SessionController(
        ref.read(bleTransportProvider),
        profile,
        EvtProtocolCodec(),
      );
      controller.addListener(_syncDiscoveryExclusions);
      setState(() {
        _sessionController = controller;
        _profile = profile;
        _destination = AppDestination.home;
      });
      _syncDiscoveryExclusions();
      await controller.connect(candidate);
    } catch (_) {
      _sessionController?.removeListener(_syncDiscoveryExclusions);
      _sessionController?.dispose();
      if (mounted) {
        setState(() => _sessionController = null);
      }
      _syncDiscoveryExclusions();
    }
  }

  void _showRecordObservation(SessionState state) {
    final session = state.session;
    final snapshot = state.latestSnapshot;
    if (session == null || snapshot == null) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => RecordObservationSheet(
        repository: ref.read(evidenceRepositoryProvider),
        deviceId: session.candidate.id,
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
      unawaited(controller.connect(candidate));
    }
  }

  Future<void> _disconnectSession(SessionController controller) async {
    await controller.disconnect();
    _discoveryController.setExcludedDeviceIds(const []);
    if (mounted) {
      setState(() {});
    }
  }

  void _syncDiscoveryExclusions() {
    final session = _sessionController?.state;
    final candidate = session?.session?.candidate;
    _discoveryController.setExcludedDeviceIds(
      session?.hasActiveBleConnection == true && candidate != null
          ? [candidate.id]
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
    if (session == null || snapshot == null) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => ObservationPage(
          repository: ref.read(evidenceRepositoryProvider),
          deviceId: session.candidate.id,
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
