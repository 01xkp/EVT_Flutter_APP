import 'dart:async';

import 'package:evt_ble_app/app/app_destination.dart';
import 'package:evt_ble_app/app/providers.dart';
import 'package:evt_ble_app/core/ble/device_profile.dart';
import 'package:evt_ble_app/core/ble/device_profile_loader.dart';
import 'package:evt_ble_app/core/design_system/widgets/app_navigation_bar.dart';
import 'package:evt_ble_app/core/protocol/evt_protocol_codec.dart';
import 'package:evt_ble_app/features/device_discovery/application/discovery_controller.dart';
import 'package:evt_ble_app/features/device_discovery/domain/advertisement_filter.dart';
import 'package:evt_ble_app/features/device_discovery/domain/device_candidate.dart';
import 'package:evt_ble_app/features/device_discovery/presentation/discovery_page.dart';
import 'package:evt_ble_app/features/device_session/application/session_controller.dart';
import 'package:evt_ble_app/features/device_session/application/session_state.dart';
import 'package:evt_ble_app/features/device_session/domain/device_snapshot.dart';
import 'package:evt_ble_app/features/device_session/presentation/session_dashboard_page.dart';
import 'package:evt_ble_app/features/evidence/application/evidence_history_controller.dart';
import 'package:evt_ble_app/features/evidence/presentation/evidence_history_page.dart';
import 'package:evt_ble_app/features/evidence/presentation/record_observation_sheet.dart';
import 'package:evt_ble_app/features/home/presentation/home_page.dart';
import 'package:evt_ble_app/features/local_recording/application/recording_controller.dart';
import 'package:evt_ble_app/features/local_recording/application/recording_library_controller.dart';
import 'package:evt_ble_app/features/local_recording/application/recording_recovery_service.dart';
import 'package:evt_ble_app/features/local_recording/presentation/active_recording_page.dart';
import 'package:evt_ble_app/features/local_recording/presentation/local_recording_library_page.dart';
import 'package:evt_ble_app/features/local_recording/presentation/recording_hub_page.dart';
import 'package:evt_ble_app/features/observation/domain/observation_scenario.dart';
import 'package:evt_ble_app/features/observation/presentation/observation_page.dart';
import 'package:evt_ble_app/features/onboarding/application/onboarding_controller.dart';
import 'package:evt_ble_app/features/onboarding/presentation/welcome_page.dart';
import 'package:evt_ble_app/features/settings/application/theme_mode_controller.dart';
import 'package:evt_ble_app/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, this.themeController});

  final ThemeModeController? themeController;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
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

  @override
  void initState() {
    super.initState();
    _discoveryController = DiscoveryController(
      ref.read(bleTransportProvider),
      const AdvertisementFilter(),
    );
    _onboardingController = OnboardingController(
      ref.read(onboardingStoreProvider),
    );
    unawaited(_loadOnboarding());
  }

  @override
  void dispose() {
    _discoveryController.dispose();
    _onboardingController.dispose();
    _sessionController?.dispose();
    _evidenceHistoryController?.dispose();
    _recordingController?.removeListener(_syncRecordingLibrary);
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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _onboardingController,
      builder: (context, _) {
        if (!_isOnboardingLoaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!_onboardingController.isComplete) {
          return WelcomePage(
            onConnectDevice: () => unawaited(
              _completeOnboarding(destination: AppDestination.home),
            ),
            onUseLocalRecording: () => unawaited(
              _completeOnboarding(destination: AppDestination.recording),
            ),
          );
        }
        return _buildConsumerShell(context);
      },
    );
  }

  Widget _buildConsumerShell(BuildContext context) {
    final session = _sessionController;
    return AnimatedBuilder(
      animation: session ?? _discoveryController,
      builder: (context, _) {
        final canRecord = session?.state.isObservable ?? false;
        return Scaffold(
          body: switch (_destination) {
            AppDestination.home => HomePage(
              device: _deviceSummary(),
              onConnectDevice: session == null
                  ? _openConnectionJourney
                  : () => _openSessionDashboard(session),
              onStartLocalRecording: _openActiveRecording,
              onOpenSettings: _openSettings,
            ),
            AppDestination.records =>
              _evidenceHistoryController == null
                  ? const SizedBox.shrink()
                  : EvidenceHistoryPage(
                      controller: _evidenceHistoryController!,
                    ),
            AppDestination.recording => RecordingHubPage(
              isHardwareObservable: canRecord,
              onStartLocal: _openActiveRecording,
              onOpenLibrary: _openLocalRecordingLibrary,
              onOpenHardware: canRecord
                  ? () => _openObservation(
                      session!.state,
                      initialScenario: ObservationScenario.vadRecording,
                    )
                  : null,
            ),
          },
          bottomNavigationBar: AppNavigationBar(
            selected: _destination,
            onSelected: _selectDestination,
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
            builder: (context, _) => SessionDashboardPage(
              state: session.state,
              onStartObservation: () => _openObservation(session.state),
              onRetry: () => _retrySession(session),
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
      _sessionController?.dispose();
      final controller = SessionController(
        ref.read(bleTransportProvider),
        profile,
        EvtProtocolCodec(),
      );
      setState(() {
        _sessionController = controller;
        _profile = profile;
        _destination = AppDestination.home;
      });
      await controller.connect(candidate);
    } catch (_) {
      if (mounted) {
        setState(() => _sessionController = null);
      }
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

  void _openEvidenceHistory() {
    _evidenceHistoryController ??= EvidenceHistoryController(
      ref.read(evidenceRepositoryProvider),
    );
    unawaited(_evidenceHistoryController!.load());
    setState(() => _destination = AppDestination.records);
  }

  void _retrySession(SessionController controller) {
    final candidate = controller.state.session?.candidate;
    if (candidate != null) {
      unawaited(controller.connect(candidate));
    }
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
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => ActiveRecordingPage(
          controller: controller,
          onFinished: _onRecordingFinished,
        ),
      ),
    );
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
        ),
      ),
    );
  }

  void _onRecordingFinished() {
    final library = _recordingLibraryController;
    if (library != null) {
      unawaited(library.load());
    }
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
