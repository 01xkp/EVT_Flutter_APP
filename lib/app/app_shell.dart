import 'dart:async';

import 'package:evt_ble_app/app/providers.dart';
import 'package:evt_ble_app/core/ble/device_profile.dart';
import 'package:evt_ble_app/core/ble/device_profile_loader.dart';
import 'package:evt_ble_app/core/protocol/evt_protocol_codec.dart';
import 'package:evt_ble_app/features/device_discovery/application/discovery_controller.dart';
import 'package:evt_ble_app/features/device_discovery/domain/advertisement_filter.dart';
import 'package:evt_ble_app/features/device_discovery/domain/device_candidate.dart';
import 'package:evt_ble_app/features/device_discovery/presentation/discovery_page.dart';
import 'package:evt_ble_app/features/device_session/application/session_controller.dart';
import 'package:evt_ble_app/features/device_session/application/session_state.dart';
import 'package:evt_ble_app/features/device_session/presentation/session_dashboard_page.dart';
import 'package:evt_ble_app/features/evidence/application/evidence_history_controller.dart';
import 'package:evt_ble_app/features/evidence/presentation/evidence_history_page.dart';
import 'package:evt_ble_app/features/evidence/presentation/record_observation_sheet.dart';
import 'package:evt_ble_app/features/local_recording/application/recording_controller.dart';
import 'package:evt_ble_app/features/local_recording/application/recording_library_controller.dart';
import 'package:evt_ble_app/features/local_recording/application/recording_recovery_service.dart';
import 'package:evt_ble_app/features/local_recording/presentation/active_recording_page.dart';
import 'package:evt_ble_app/features/local_recording/presentation/local_recording_library_page.dart';
import 'package:evt_ble_app/features/local_recording/presentation/recording_hub_page.dart';
import 'package:evt_ble_app/features/observation/domain/observation_scenario.dart';
import 'package:evt_ble_app/features/observation/presentation/observation_page.dart';
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
  SessionController? _sessionController;
  EvidenceHistoryController? _evidenceHistoryController;
  RecordingController? _recordingController;
  RecordingLibraryController? _recordingLibraryController;
  Future<void>? _recordingSetup;
  DeviceProfile? _profile;
  var _destination = 0;

  @override
  void initState() {
    super.initState();
    _discoveryController = DiscoveryController(
      ref.read(bleTransportProvider),
      const AdvertisementFilter(),
    );
  }

  @override
  void dispose() {
    _discoveryController.dispose();
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
    final session = _sessionController;
    return AnimatedBuilder(
      animation: session ?? _discoveryController,
      builder: (context, _) {
        final canRecord = session?.state.isObservable ?? false;
        return Scaffold(
          body: switch (_destination) {
            0 =>
              session == null
                  ? DiscoveryPage(
                      controller: _discoveryController,
                      onConnect: _openSession,
                      onSettings: _openSettings,
                    )
                  : SessionDashboardPage(
                      state: session.state,
                      onStartObservation: () => _openObservation(session.state),
                      onRetry: () => _retrySession(session),
                    ),
            1 =>
              _evidenceHistoryController == null
                  ? const SizedBox.shrink()
                  : EvidenceHistoryPage(
                      controller: _evidenceHistoryController!,
                    ),
            2 => RecordingHubPage(
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
            _ => const SizedBox.shrink(),
          },
          bottomNavigationBar: BottomAppBar(
            child: SizedBox(
              height: 60,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    tooltip: '设备联调',
                    onPressed: () => setState(() => _destination = 0),
                    icon: const Icon(Icons.bluetooth_searching_outlined),
                  ),
                  IconButton(
                    tooltip: '录音',
                    onPressed: () => setState(() => _destination = 2),
                    icon: const Icon(Icons.mic_none_outlined),
                  ),
                  IconButton(
                    tooltip: '查看证据',
                    onPressed: _openEvidenceHistory,
                    icon: const Icon(Icons.fact_check_outlined),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
        _destination = 0;
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
    setState(() => _destination = 1);
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
      await RecordingRecoveryService(repository: repository, files: files)
          .reconcile();
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
