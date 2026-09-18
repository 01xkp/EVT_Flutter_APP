import 'dart:async';
import 'package:aipin/features/device_session/domain/device_file.dart';

import 'package:aipin/app/app_destination.dart';
import 'package:aipin/app/branding/aipin_brand_splash.dart';
import 'package:aipin/app/providers.dart';
import 'package:aipin/core/ble/ble_background_monitoring_gateway.dart';
import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/design_system/evt_theme.dart';
import 'package:aipin/core/design_system/widgets/app_navigation_bar.dart';
import 'package:aipin/core/design_system/widgets/app_toast.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_session/application/device_reconnect_controller.dart';
import 'package:aipin/features/device_session/application/device_reconnect_state.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/features/device_discovery/application/discovery_controller.dart';
import 'package:aipin/features/device_discovery/domain/advertisement_filter.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:aipin/features/device_discovery/presentation/discovery_page.dart';
import 'package:aipin/features/device_session/application/session_controller.dart';
import 'package:aipin/features/device_session/application/evt_legacy_auth_controller.dart';
import 'package:aipin/features/device_session/application/evt_legacy_security_failure_message.dart';
import 'package:aipin/features/device_session/application/session_state.dart';
import 'package:aipin/features/device_session/domain/device_auth_state.dart';
import 'package:aipin/features/device_session/domain/device_permission.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';
import 'package:aipin/features/device_session/domain/evt_unbind_preflight.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:aipin/features/device_session/presentation/device_detail_page.dart';
import 'package:aipin/features/device_session/presentation/device_file_browser_page.dart';
import 'package:aipin/features/device_session/data/dvt_device_file_import_service.dart';
import 'package:aipin/features/device_session/data/dvt_device_file_archive_service.dart';
import 'package:aipin/features/device_session/data/https_firmware_package_source.dart';
import 'package:aipin/features/device_session/application/dvt_audio_probe_controller.dart';
import 'package:aipin/features/device_session/presentation/dvt_audio_probe_page.dart';
import 'package:aipin/features/device_session/presentation/dvt_firmware_update_page.dart';
import 'package:aipin/features/device_session/presentation/evt_security_code_sheet.dart';
import 'package:aipin/features/device_logs/data/file_app_log_store.dart';
import 'package:aipin/features/device_logs/presentation/device_log_page.dart';
import 'package:aipin/features/evidence/application/evidence_history_controller.dart';
import 'package:aipin/features/evidence/presentation/record_observation_sheet.dart';
import 'package:aipin/features/home/presentation/home_page.dart';
import 'package:aipin/features/local_recording/application/recording_library_controller.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/presentation/device_recording_detail_page.dart';
import 'package:aipin/features/local_recording/presentation/device_recording_library_page.dart';
import 'package:aipin/features/observation/domain/observation_scenario.dart';
import 'package:aipin/features/observation/presentation/observation_page.dart';
import 'package:aipin/features/onboarding/application/onboarding_controller.dart';
import 'package:aipin/features/onboarding/presentation/welcome_page.dart';
import 'package:aipin/features/records/presentation/records_page.dart';
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
  static const _evtAdvertisementFilter = AdvertisementFilter();
  // EVT firmware broadcast fields are still being aligned. Keep manual
  // discovery compatible with named peripherals until the strict identity
  // filter can be re-enabled for production qualification.
  static const _useStrictEvtAdvertisementFilter = false;

  late final DiscoveryController _discoveryController;
  late final DeviceReconnectController _reconnectController;
  late final BleBackgroundMonitoringController
  _backgroundBleMonitoringController;
  late final OnboardingController _onboardingController;
  SessionController? _sessionController;
  EvtLegacyAuthController? _deviceAuthController;
  EvidenceHistoryController? _evidenceHistoryController;
  DeviceProfile? _profile;
  var _destination = AppDestination.home;
  var _isOnboardingLoaded = false;
  var _isAppForeground = true;
  var _reconnectPausedForBackground = false;
  Future<void>? _reconnectBackgroundPause;
  var _sessionReachedAuthenticationReady = false;
  var _sessionHistoryPersisted = false;
  var _unexpectedReconnectStarted = false;
  // V1.6 UNBIND is resumable after a timeout/disconnect.  Keep only the
  // device identity, never the six-byte security code, so recreating the
  // connection-scoped auth controller cannot lose the recovery intent.
  final Set<String> _pendingUnbindRecoveryDeviceKeys = <String>{};
  Future<void>? _sessionHistoryPersistence;
  Future<void>? _sessionTeardown;
  var _sessionConnectionOperation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _discoveryController = DiscoveryController(
      ref.read(bleTransportProvider),
      _evtAdvertisementFilter,
      logger: ref.read(scopedAppLoggerProvider('BLE')),
      filterByV16Advertisement: _useStrictEvtAdvertisementFilter,
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
      advertisementFilter: _evtAdvertisementFilter,
      filterByV16Advertisement: _useStrictEvtAdvertisementFilter,
    );
    _backgroundBleMonitoringController = BleBackgroundMonitoringController(
      ref.read(bleBackgroundMonitoringGatewayProvider),
      logger: ref.read(scopedAppLoggerProvider('APP_LIFECYCLE')),
    );
    _onboardingController = OnboardingController(
      ref.read(onboardingStoreProvider),
    );
    unawaited(_loadOnboarding());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_backgroundBleMonitoringController.deactivate());
    _discoveryController.removeListener(_onDiscoveryChanged);
    _reconnectController.dispose();
    _discoveryController.dispose();
    _onboardingController.dispose();
    _sessionController?.removeListener(_onSessionChanged);
    _sessionController?.dispose();
    _deviceAuthController?.removeListener(_onDeviceAuthChanged);
    _deviceAuthController?.dispose();
    _evidenceHistoryController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lifecycleLogger = ref.read(scopedAppLoggerProvider('APP_LIFECYCLE'));
    lifecycleLogger.info(
      'app_lifecycle_changed',
      fields: {
        'state': state.name,
        'foreground_before': _isAppForeground,
        'reconnect_paused_for_background': _reconnectPausedForBackground,
      },
    );
    if (_shouldFlushDiagnosticsForLifecycle(state)) {
      final logStore = ref.read(appLogStoreProvider);
      lifecycleLogger.info(
        'app_lifecycle_diagnostics_flush_requested',
        fields: {'state': state.name},
      );
      unawaited(
        _flushDiagnostics(
          logStore: logStore,
          onError: (error) => lifecycleLogger.warning(
            'app_lifecycle_diagnostics_flush_failed',
            fields: {
              'state': state.name,
              'error_type': error.runtimeType.toString(),
            },
          ),
        ),
      );
    }
    if (state == AppLifecycleState.resumed) {
      _isAppForeground = true;
      unawaited(_syncBackgroundBleMonitoring(_sessionController?.state));
      if (_reconnectPausedForBackground) {
        _reconnectPausedForBackground = false;
        ref
            .read(scopedAppLoggerProvider('APP_LIFECYCLE'))
            .info('remembered_device_restore_requested');
        unawaited(_restoreRememberedDevice());
      }
      unawaited(_refreshCurrentSessionAfterForeground());
      return;
    }
    _isAppForeground = false;
    if (_isReconnectBackgroundState(state)) {
      _reconnectPausedForBackground = true;
      final pause = _pauseReconnectForBackground();
      if (_shouldFlushDiagnosticsForLifecycle(state)) {
        final logStore = ref.read(appLogStoreProvider);
        unawaited(
          _flushDiagnosticsAfterBackgroundPause(
            pause,
            logStore: logStore,
            logger: lifecycleLogger,
            state: state,
          ),
        );
      }
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
              ? WelcomePage(onConnectDevice: _completeOnboarding)
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
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: EvtTheme.systemUiOverlayStyle(Theme.of(context)),
          child: Scaffold(
            body: switch (_destination) {
              AppDestination.home => HomePage(
                device: _deviceSummary(),
                onConnectDevice: _openConnectionJourney,
                onOpenSettings: _openSettings,
                onOpenLogs: _openDeviceLogs,
                onOpenSavedRecordings: () =>
                    unawaited(_openSavedDeviceRecordings()),
                onOpenFiles: () {
                  if (session == null) {
                    _openConnectionJourney();
                  } else if (_deviceAuthController?.allows(
                        DevicePermission.files,
                      ) !=
                      true) {
                    _openSessionDashboard(session);
                  } else {
                    unawaited(_openDeviceFiles(session));
                  }
                },
                onOpenDevice: session == null
                    ? null
                    : () => _openSessionDashboard(session),
              ),
              AppDestination.records =>
                _evidenceHistoryController == null
                    ? const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      )
                    : RecordsPage(
                        evidenceController: _evidenceHistoryController!,
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

  Future<void> _completeOnboarding() async {
    await _onboardingController.complete();
    if (!mounted) {
      return;
    }
    setState(() {
      _isOnboardingLoaded = true;
      _destination = AppDestination.home;
    });
    unawaited(_restoreRememberedDevice(startDiscoveryWhenNoRecord: true));
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
          .push<DeviceCandidate>(
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
              ),
            ),
          )
          .then((candidate) async {
            await _onConnectionJourneyClosed();
            if (candidate == null || !mounted) {
              return;
            }
            final session = _sessionController;
            if (session != null && session.state.isAuthenticationReady) {
              _openSessionDashboard(session);
            }
          }),
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
    // A very quick background -> foreground transition can arrive while the
    // prior platform scan cancellation is still pending. Let that cleanup
    // finish first so its late native completion cannot stop this new scan.
    final backgroundPause = _reconnectBackgroundPause;
    if (backgroundPause != null) {
      await backgroundPause;
    }
    // The shell can be disposed while a native scan cancellation is still
    // pending. Do not read providers or start a reconnect after that await.
    if (!mounted) {
      return;
    }
    if (!_isAppForeground ||
        !_isOnboardingLoaded ||
        !_onboardingController.isComplete ||
        _hasActiveOrConnectingSession) {
      ref
          .read(scopedAppLoggerProvider('APP_LIFECYCLE'))
          .info(
            'remembered_device_restore_skipped',
            fields: {
              'is_foreground': _isAppForeground,
              'onboarding_loaded': _isOnboardingLoaded,
              'onboarding_complete': _onboardingController.isComplete,
              'has_active_or_connecting_session': _hasActiveOrConnectingSession,
            },
          );
      return;
    }
    ref
        .read(scopedAppLoggerProvider('APP_LIFECYCLE'))
        .info('remembered_device_restore_started');
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
    // Mark automatic reconnect paused before stopping the shared scan. This
    // keeps a late scan callback from starting a connection while the app is
    // moving to the background. DiscoveryController also owns first-time and
    // manual scans, so it must be stopped here as well.
    final pause = () async {
      // Both flows own the same native scan subscription. Stop the automatic
      // reconnect cycle first, then clean up a possible manual scan. Running
      // the two cancellations concurrently can leave a stale cancellation
      // Future ahead of the foreground restore scan on some platforms.
      await _reconnectController.pauseForBackground();
      await _discoveryController.stop();
    }();
    _reconnectBackgroundPause = pause;
    return pause.whenComplete(() {
      if (identical(_reconnectBackgroundPause, pause)) {
        _reconnectBackgroundPause = null;
      }
    });
  }

  Future<void> _flushDiagnosticsAfterBackgroundPause(
    Future<void> pause, {
    required FileAppLogStore logStore,
    required SafeAppLogger logger,
    required AppLifecycleState state,
  }) async {
    try {
      await pause;
    } catch (error) {
      logger.warning(
        'app_lifecycle_background_pause_failed',
        fields: {
          'state': state.name,
          'error_type': error.runtimeType.toString(),
        },
      );
    }
    await _flushDiagnostics(
      logStore: logStore,
      onError: (error) => logger.warning(
        'app_lifecycle_diagnostics_flush_failed',
        fields: {
          'state': state.name,
          'error_type': error.runtimeType.toString(),
        },
      ),
    );
  }

  /// Reads current device state after foreground restore when the existing
  /// V1 authorization window remains valid. A disconnect, session replacement
  /// or expired authorization simply leaves the next user action to re-auth.
  Future<void> _refreshCurrentSessionAfterForeground() async {
    final session = _sessionController;
    final auth = _deviceAuthController;
    final operation = _sessionConnectionOperation;
    if (session == null ||
        auth == null ||
        !session.state.isObservable ||
        !auth.allows(DevicePermission.status)) {
      return;
    }

    final logger = ref.read(scopedAppLoggerProvider('SESSION_FLOW'));
    logger.info(
      'foreground_status_refresh_started',
      fields: {'operation': operation},
    );
    try {
      await session.readStatus();
      if (!mounted ||
          !identical(_sessionController, session) ||
          operation != _sessionConnectionOperation) {
        return;
      }
      logger.info(
        'foreground_status_refresh_finished',
        fields: {'operation': operation},
      );
    } catch (error) {
      // Foreground restoration should not replace a recoverable connection
      // state with UI noise. The session layer keeps the protocol failure and
      // a later manual refresh can retry it.
      if (!mounted ||
          !identical(_sessionController, session) ||
          operation != _sessionConnectionOperation) {
        return;
      }
      logger.warning(
        'foreground_status_refresh_failed',
        fields: {
          'operation': operation,
          'error_type': error.runtimeType.toString(),
        },
      );
    }
  }

  void _onDiscoveryChanged() {
    final state = _discoveryController.state;
    if (!state.isScanning) {
      _reconnectController.notifyScanStopped();
    }
    if (_reconnectController.state.phase != DeviceReconnectPhase.scanning) {
      return;
    }
    for (final candidate in state.candidates) {
      unawaited(_reconnectController.considerCandidate(candidate));
    }
  }

  void _openSessionDashboard(SessionController session) {
    final auth = _deviceAuthController;
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => AnimatedBuilder(
            animation: Listenable.merge([session, ?auth]),
            builder: (context, _) => DeviceDetailPage(
              state: session.state,
              onDisconnect: () => unawaited(_disconnectSession(session)),
              onRetry: () => _retrySession(session),
              onOpenChecking: () => _openObservation(session.state),
              onOpenLogs: _openDeviceLogs,
              onOpenFiles: () => unawaited(_openDeviceFiles(session)),
              onOpenSavedRecordings: () =>
                  unawaited(_openSavedDeviceRecordings()),
              onOpenDvtAudio:
                  session.state.isObservable &&
                      session.state.supportsEndpoint(
                        BleLogicalEndpoint.fa10Fa18,
                        BleOperation.notify,
                      )
                  ? () => unawaited(_openDvtAudio(session))
                  : null,
              onOpenDvtOta: session.state.isObservable
                  ? () => unawaited(_openDvtOta(session))
                  : null,
              onRecordAction: (action) =>
                  unawaited(_setHardwareRecordAction(session, action)),
              onRefreshDeviceDetails: () =>
                  unawaited(_refreshDeviceDetails(session)),
              onRecordConsentChanged: (granted) =>
                  unawaited(_setDeviceRecordConsent(session, granted)),
              onPrivacyDurationChanged: (durationCode) =>
                  unawaited(_setPrivacyDuration(session, durationCode)),
              authState: auth?.state ?? DeviceAuthState.unknown,
              authenticatingAction: auth?.activeAction,
              onAuthenticate: auth == null
                  ? null
                  : () =>
                        unawaited(_promptAndAuthenticateDevice(session, auth)),
              onBind: auth == null
                  ? null
                  : () => unawaited(_promptAndBindDevice(session, auth)),
              onUnbind: auth == null
                  ? null
                  : () => unawaited(_promptAndUnbindDevice(session, auth)),
              onUnbindRecovery: auth == null
                  ? null
                  : () => unawaited(_promptAndUnbindRecovery(session, auth)),
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
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _connectRememberedDevice(DeviceCandidate candidate) {
    return _openSession(candidate, automaticallyReconnect: true);
  }

  Future<bool> _openSession(
    DeviceCandidate candidate, {
    bool automaticallyReconnect = false,
  }) async {
    final logger = ref.read(scopedAppLoggerProvider('SESSION_FLOW'));
    // A user can manually try any named scan result during EVT. The GATT
    // contract remains the hard gate before an EVT session becomes usable.
    // Automatic reconnect still requires a locally remembered-device match in
    // DeviceReconnectController. During EVT, it follows the same relaxed
    // advertisement policy as manual discovery, because the firmware's
    // broadcast fields are still being aligned.
    if (automaticallyReconnect &&
        _useStrictEvtAdvertisementFilter &&
        !_evtAdvertisementFilter.matches(candidate)) {
      logger.warning(
        'session_open_rejected_advertisement',
        fields: {'automatic': automaticallyReconnect},
      );
      return false;
    }
    final operation = ++_sessionConnectionOperation;
    logger.info(
      'session_open_requested',
      fields: {'operation': operation, 'automatic': automaticallyReconnect},
    );
    // Start Android's connected-device foreground service while this user
    // initiated flow is still foreground. Waiting for GATT discovery or the
    // FA11/FA19 CCC setup leaves Android 12+ free to reject the start after a
    // quick Home gesture. The service never owns GATT; it only keeps this
    // existing Flutter/RxAndroidBle process eligible to receive the link.
    await _activateBackgroundBleMonitoringForConnection(
      candidate,
      operation: operation,
      logger: logger,
    );
    if (!_isCurrentSessionConnectionOperation(operation)) {
      return false;
    }
    if (!automaticallyReconnect) {
      // takeOverManualConnection invalidates its automatic cycle before its
      // first await. Its scan cleanup can then finish in parallel with the
      // explicit scan stop below; waiting for that housekeeping used to leave
      // a user-selected connection behind a stale reconnect operation.
      unawaited(_reconnectController.takeOverManualConnection());
      logger.info(
        'session_open_manual_takeover_started',
        fields: {'operation': operation},
      );
    }

    SessionController? createdSession;
    EvtLegacyAuthController? createdAuth;
    try {
      logger.info(
        'session_open_scan_stop_requested',
        fields: {'operation': operation},
      );
      final scanStop = _discoveryController.stop();
      unawaited(
        scanStop.then<void>(
          (_) => logger.info(
            'session_open_scan_stop_finished',
            fields: {'operation': operation},
          ),
          onError: (Object error, StackTrace _) => logger.warning(
            'session_open_scan_stop_failed',
            fields: {'operation': operation, 'error_type': error.runtimeType},
          ),
        ),
      );
      if (!_isCurrentSessionConnectionOperation(operation)) {
        logger.warning(
          'session_open_superseded_after_scan_stop_requested',
          fields: {
            'operation': operation,
            'current_operation': _sessionConnectionOperation,
          },
        );
        return false;
      }
      logger.info(
        'session_open_evt_profile_ready',
        fields: {'operation': operation},
      );
      final profile = DeviceProfile.dvtV16();
      logger.info(
        'session_open_evt_profile_verified',
        fields: {'operation': operation, 'gatt_ready': profile.isGattReady},
      );
      if (!_isCurrentSessionConnectionOperation(operation)) {
        logger.warning(
          'session_open_superseded_after_profile_ready',
          fields: {
            'operation': operation,
            'current_operation': _sessionConnectionOperation,
          },
        );
        return false;
      }
      // Capture a pending UNBIND before the old connection-scoped controller
      // is disposed.  Automatic reconnect creates a fresh controller below.
      _capturePendingUnbindRecovery();
      // The incoming foreground monitor has already been activated above.
      // Retain it while replacing the old controller so Android does not
      // briefly lose its foreground-service eligibility between connections.
      await _disposeCurrentSessionControllers(
        preserveBackgroundBleMonitoring: true,
      );
      if (!_isCurrentSessionConnectionOperation(operation)) {
        logger.warning(
          'session_open_superseded_after_previous_session_closed',
          fields: {
            'operation': operation,
            'current_operation': _sessionConnectionOperation,
          },
        );
        return false;
      }
      final recoveryStore = ref.read(unbindRecoveryStoreProvider);
      final recoveryKeys = _unbindRecoveryKeys(candidate).toList();
      final persistedRecovery = await recoveryStore.containsAny(recoveryKeys);
      if (!_isCurrentSessionConnectionOperation(operation)) return false;
      if (persistedRecovery) {
        _pendingUnbindRecoveryDeviceKeys.addAll(recoveryKeys);
      }
      final unbindRecoveryPending = _hasPendingUnbindRecovery(candidate);
      if (unbindRecoveryPending) {
        logger.info(
          'session_open_unbind_recovery_marker_restored',
          fields: {
            'operation': operation,
            'identity_source': candidate.physicalDeviceId == null
                ? 'connection_id'
                : 'physical_mac',
          },
        );
      }
      final authController = EvtLegacyAuthController(
        unbindRecoveryPending: unbindRecoveryPending,
        persistUnbindIntent: (pending) =>
            recoveryStore.setPending(recoveryKeys, pending),
        logger: ref.read(scopedAppLoggerProvider('AUTH')),
      );
      final controller = SessionController(
        ref.read(bleTransportProvider),
        profile,
        EvtProtocolCodec(),
        logger: ref.read(scopedAppLoggerProvider('SESSION')),
        commandLogger: ref.read(scopedAppLoggerProvider('CMD')),
        permissionGate: authController,
      );
      createdSession = controller;
      createdAuth = authController;
      controller.addListener(_onSessionChanged);
      authController.addListener(_onDeviceAuthChanged);
      if (!_isCurrentSessionConnectionOperation(operation)) {
        controller.removeListener(_onSessionChanged);
        authController.removeListener(_onDeviceAuthChanged);
        await _disposeSessionControllers(controller, authController);
        return false;
      }
      setState(() {
        _sessionController = controller;
        _deviceAuthController = authController;
        _profile = profile;
        _destination = AppDestination.home;
      });
      _syncDiscoveryExclusions();
      logger.info(
        'session_open_gatt_connect_start',
        fields: {'operation': operation},
      );
      await controller.connect(candidate);
      if (!_isCurrentSessionConnectionOperation(operation) ||
          !identical(_sessionController, controller)) {
        logger.warning(
          'session_open_superseded_after_gatt_connect',
          fields: {
            'operation': operation,
            'current_operation': _sessionConnectionOperation,
          },
        );
        return false;
      }
      final ready = controller.state.isAuthenticationReady;
      logger.info(
        'session_open_gatt_connect_finished',
        fields: {'operation': operation, 'authentication_ready': ready},
      );
      return ready;
    } catch (error) {
      logger.warning(
        'session_open_failed',
        fields: {'operation': operation, 'error_type': error.runtimeType},
      );
      if (_isCurrentSessionConnectionOperation(operation) &&
          identical(_sessionController, createdSession)) {
        await _disposeCurrentSessionControllers();
        if (!mounted || !_isCurrentSessionConnectionOperation(operation)) {
          return false;
        }
        setState(() {
          _sessionController = null;
          _deviceAuthController = null;
        });
      } else if (!identical(_sessionController, createdSession)) {
        createdSession?.removeListener(_onSessionChanged);
        createdAuth?.removeListener(_onDeviceAuthChanged);
        await _disposeSessionControllers(createdSession, createdAuth);
      }
      _syncDiscoveryExclusions();
      return false;
    }
  }

  bool _isCurrentSessionConnectionOperation(int operation) {
    return mounted && operation == _sessionConnectionOperation;
  }

  Future<void> _disposeCurrentSessionControllers({
    bool preserveBackgroundBleMonitoring = false,
  }) {
    final activeTeardown = _sessionTeardown;
    if (activeTeardown != null) {
      return activeTeardown;
    }
    final session = _sessionController;
    final auth = _deviceAuthController;
    if (session == null && auth == null) {
      _resetSessionReconnectTracking();
      return Future<void>.value();
    }
    session?.removeListener(_onSessionChanged);
    auth?.removeListener(_onDeviceAuthChanged);
    _resetSessionReconnectTracking();
    late final Future<void> teardown;
    teardown =
        () async {
          if (!preserveBackgroundBleMonitoring) {
            await _backgroundBleMonitoringController.deactivate();
          }
          await _disposeSessionControllers(session, auth);
        }().whenComplete(() {
          if (identical(_sessionController, session)) {
            _sessionController = null;
          }
          if (identical(_deviceAuthController, auth)) {
            _deviceAuthController = null;
          }
          if (identical(_sessionTeardown, teardown)) {
            _sessionTeardown = null;
          }
        });
    _sessionTeardown = teardown;
    return teardown;
  }

  Future<void> _activateBackgroundBleMonitoringForConnection(
    DeviceCandidate candidate, {
    required int operation,
    required SafeAppLogger logger,
  }) async {
    if (!_isAppForeground) {
      logger.warning(
        'session_open_background_monitoring_not_foreground',
        fields: {
          'operation': operation,
          'reason': '【后台BLE】连接请求到达时应用已在后台，不再从后台新建 GATT 连接。',
        },
      );
      return;
    }
    if (candidate.connectionId.trim().isEmpty ||
        candidate.name.trim().isEmpty) {
      logger.warning(
        'session_open_background_monitoring_skipped',
        fields: {
          'operation': operation,
          'reason': '【后台BLE】候选设备缺少稳定标识或名称，跳过平台保活服务。',
        },
      );
      return;
    }
    logger.info(
      'session_open_background_monitoring_requested',
      fields: {
        'operation': operation,
        'reason': '【后台BLE】在 GATT 连接前申请平台保活，防止用户切后台后丢失监听。',
      },
    );
    await _backgroundBleMonitoringController.updateForSession(
      shouldMonitor: true,
      deviceId: candidate.connectionId,
      deviceName: candidate.name,
      canStart: true,
    );
    logger.info(
      'session_open_background_monitoring_finished',
      fields: {
        'operation': operation,
        'active': _backgroundBleMonitoringController.isActive,
        'reason': _backgroundBleMonitoringController.isActive
            ? '【后台BLE】平台保活已确认，继续建立 Flutter GATT 连接。'
            : '【后台BLE】平台保活未确认，继续前台连接并保留失败日志。',
      },
    );
  }

  Future<void> _disposeSessionControllers(
    SessionController? session,
    EvtLegacyAuthController? auth,
  ) async {
    try {
      await session?.close();
    } catch (error) {
      ref
          .read(scopedAppLoggerProvider('SESSION_FLOW'))
          .warning(
            'session_close_failed',
            fields: {'error_type': error.runtimeType},
          );
    } finally {
      session?.dispose();
      auth?.dispose();
    }
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
    unawaited(_syncBackgroundBleMonitoring(state));

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
    final auth = _deviceAuthController;
    if (state.isObservable && auth?.isAuthenticated == true) {
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
    final unbindRecoveryPending =
        auth?.hasUnbindRecoveryPending == true ||
        _hasPendingUnbindRecovery(candidate);
    if (state.phase == SessionPhase.interrupted &&
        (_sessionReachedAuthenticationReady || unbindRecoveryPending) &&
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

  void _onDeviceAuthChanged() {
    _capturePendingUnbindRecovery();
    unawaited(_syncBackgroundBleMonitoring(_sessionController?.state));
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _syncBackgroundBleMonitoring(SessionState? state) {
    final candidate = state?.session?.candidate;
    // Android 12+ may reject startForegroundService once the activity is
    // already backgrounded. Enable the same service when a foreground flow
    // starts GATT, rather than waiting for FA11/FA19 setup. It never creates
    // another GATT client: Flutter/RxAndroidBle remains the only connection
    // and CCC owner.
    final hasForegroundInitiatedGattFlow =
        state?.phase == SessionPhase.connecting ||
        state?.hasActiveBleConnection == true;
    return _backgroundBleMonitoringController.updateForSession(
      shouldMonitor:
          hasForegroundInitiatedGattFlow &&
          candidate != null &&
          candidate.connectionId.trim().isNotEmpty &&
          candidate.name.trim().isNotEmpty,
      deviceId: candidate?.connectionId,
      deviceName: candidate?.name,
      canStart: _isAppForeground,
    );
  }

  /// Mirrors the controller's recovery marker into an AppShell-level map.
  ///
  /// The auth controller is intentionally connection-scoped and is recreated
  /// for every reconnect.  Keeping this marker here preserves the V1.6
  /// recovery path without retaining the security code itself.
  void _capturePendingUnbindRecovery() {
    final session = _sessionController?.state.session;
    final auth = _deviceAuthController;
    final candidate = session?.candidate;
    if (candidate == null || auth == null) {
      return;
    }
    if (auth.hasUnbindRecoveryPending) {
      var changed = false;
      for (final key in _unbindRecoveryKeys(candidate)) {
        changed = _pendingUnbindRecoveryDeviceKeys.add(key) || changed;
      }
      if (changed) {
        ref
            .read(scopedAppLoggerProvider('AUTH'))
            .info(
              'unbind_recovery_marker_saved',
              operation: 'device_unbind',
              stage: 'challenge',
              result: 'pending',
              fields: {
                'identity_source': candidate.physicalDeviceId == null
                    ? 'connection_id'
                    : 'physical_mac',
                'security_code_stored': false,
              },
            );
      }
      return;
    }
    if (auth.state == DeviceAuthState.unbound) {
      _clearPendingUnbindRecovery(candidate);
    }
  }

  bool _hasPendingUnbindRecovery(DeviceCandidate candidate) {
    return _unbindRecoveryKeys(
      candidate,
    ).any(_pendingUnbindRecoveryDeviceKeys.contains);
  }

  void _clearPendingUnbindRecovery(DeviceCandidate candidate) {
    var changed = false;
    for (final key in _unbindRecoveryKeys(candidate)) {
      changed = _pendingUnbindRecoveryDeviceKeys.remove(key) || changed;
    }
    if (changed) {
      ref
          .read(scopedAppLoggerProvider('AUTH'))
          .info(
            'unbind_recovery_marker_cleared',
            operation: 'device_unbind',
            stage: 'challenge',
            result: 'completed',
            fields: {
              'identity_source': candidate.physicalDeviceId == null
                  ? 'connection_id'
                  : 'physical_mac',
              'security_code_stored': false,
            },
          );
    }
  }

  Iterable<String> _unbindRecoveryKeys(DeviceCandidate candidate) sync* {
    final physicalId = candidate.physicalDeviceId;
    if (physicalId != null) {
      yield 'physical:$physicalId';
    }
    yield 'connection:${candidate.connectionId}';
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

  void _openEvidenceHistory() {
    _evidenceHistoryController ??= EvidenceHistoryController(
      ref.read(evidenceRepositoryProvider),
    );
    setState(() => _destination = AppDestination.records);
    unawaited(_evidenceHistoryController!.load());
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
    _deviceAuthController?.revokeForConnectionLoss();
    await controller.connect(candidate);
  }

  Future<void> _disconnectSession(SessionController controller) async {
    _sessionConnectionOperation += 1;
    await _reconnectController.suppressForForeground();
    if (!mounted || !identical(_sessionController, controller)) {
      return;
    }
    _deviceAuthController?.revokeForConnectionLoss();
    await controller.disconnect();
    _discoveryController.setExcludedDeviceIds(const []);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openDeviceLogs() async {
    final store = ref.read(appLogStoreProvider);
    final uploadController = ref.read(appLogUploadControllerProvider);
    await store.initialize();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DeviceLogPage(
          store: store,
          onExport: (_) => _showLogExportResult(store),
          onUpload: uploadController.uploadLatest,
        ),
      ),
    );
  }

  Future<void> _showLogExportResult(FileAppLogStore store) async {
    if (!mounted) {
      return;
    }
    final publicPath = store.publicMirrorStatus?.available == true
        ? store.publicMirrorStatus?.relativePath
        : null;
    AppToast.show(
      context,
      message: publicPath == null ? '脱敏日志已导出到应用内部存储' : '脱敏日志已更新到 $publicPath',
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
      await session.refreshDeviceDetails(
        _deviceAuthController!.grantedPermissions,
      );
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

  Future<void> _promptAndAuthenticateDevice(
    SessionController session,
    EvtLegacyAuthController auth,
  ) async {
    final connectionOperation = _sessionConnectionOperation;
    final logger = ref.read(scopedAppLoggerProvider('AUTH'));
    final logStore = ref.read(appLogStoreProvider);
    _logSecurityUi(
      'security_code_sheet_opened',
      action: 'authenticate',
      logger: logger,
    );
    final code = await EvtSecurityCodeSheet.show(
      context,
      title: '认证设备',
      message: '请输入该设备当前的安全码。',
      confirmLabel: '开始认证',
    );
    if (code == null ||
        !_isCurrentSecurityUiOperation(session, connectionOperation)) {
      _logSecurityUi(
        'security_code_sheet_cancelled',
        action: 'authenticate',
        logger: logger,
      );
      await _flushSecurityDiagnostics(
        EvtLegacySecurityAction.authenticate,
        reason: 'security_code_sheet_cancelled',
        logger: logger,
        logStore: logStore,
      );
      return;
    }
    _logSecurityUi(
      'security_code_sheet_confirmed',
      action: 'authenticate',
      fields: {'length': code.length},
      logger: logger,
    );
    try {
      await auth.authenticate(session, securityCode: code);
      if (!_isCurrentSecurityUiOperation(session, connectionOperation)) {
        return;
      }
      _requestSecurityPrivateDiagnosticsFlush(
        EvtLegacySecurityAction.authenticate,
        reason: 'v1_security_exchange_completed',
        logger: logger,
        logStore: logStore,
      );
      _logSecurityUi(
        'security_post_auth_synchronization_started',
        action: 'authenticate',
        logger: logger,
      );
      await session.synchronizeAfterAuthentication(auth.grantedPermissions);
      if (!_isCurrentSecurityUiOperation(session, connectionOperation)) {
        return;
      }
      _logSecurityUi(
        'security_ui_operation_completed',
        action: 'authenticate',
        result: 'success',
        logger: logger,
      );
      if (mounted) {
        AppToast.show(context, message: '设备认证完成');
      }
    } catch (error) {
      await _handleSecurityUiFailure(
        session: session,
        connectionOperation: connectionOperation,
        action: EvtLegacySecurityAction.authenticate,
        error: error,
        logger: logger,
      );
    } finally {
      await _flushSecurityDiagnostics(
        EvtLegacySecurityAction.authenticate,
        reason: 'security_operation_terminal',
        logger: logger,
        logStore: logStore,
      );
    }
  }

  Future<void> _promptAndBindDevice(
    SessionController session,
    EvtLegacyAuthController auth,
  ) async {
    final connectionOperation = _sessionConnectionOperation;
    final logger = ref.read(scopedAppLoggerProvider('AUTH'));
    final logStore = ref.read(appLogStoreProvider);
    _logSecurityUi(
      'security_code_sheet_opened',
      action: 'bind',
      logger: logger,
    );
    final code = await EvtSecurityCodeSheet.show(
      context,
      title: '首次绑定设备',
      message: '请输入待绑定的安全码。提交后请在 60 秒内短按设备按键确认。',
      confirmLabel: '确认绑定',
    );
    if (code == null ||
        !_isCurrentSecurityUiOperation(session, connectionOperation)) {
      _logSecurityUi(
        'security_code_sheet_cancelled',
        action: 'bind',
        logger: logger,
      );
      await _flushSecurityDiagnostics(
        EvtLegacySecurityAction.bind,
        reason: 'security_code_sheet_cancelled',
        logger: logger,
        logStore: logStore,
      );
      return;
    }
    _logSecurityUi(
      'security_code_sheet_confirmed',
      action: 'bind',
      fields: {'length': code.length},
      logger: logger,
    );
    try {
      await auth.bind(session, securityCode: code);
      if (!_isCurrentSecurityUiOperation(session, connectionOperation)) {
        return;
      }
      _requestSecurityPrivateDiagnosticsFlush(
        EvtLegacySecurityAction.bind,
        reason: 'v1_security_exchange_completed',
        logger: logger,
        logStore: logStore,
      );
      _logSecurityUi(
        'security_post_auth_synchronization_started',
        action: 'bind',
        logger: logger,
      );
      await session.synchronizeAfterAuthentication(auth.grantedPermissions);
      if (!_isCurrentSecurityUiOperation(session, connectionOperation)) {
        return;
      }
      _logSecurityUi(
        'security_ui_operation_completed',
        action: 'bind',
        result: 'success',
        logger: logger,
      );
      if (mounted) {
        AppToast.show(context, message: '设备绑定完成');
      }
    } catch (error) {
      await _handleSecurityUiFailure(
        session: session,
        connectionOperation: connectionOperation,
        action: EvtLegacySecurityAction.bind,
        error: error,
        logger: logger,
      );
    } finally {
      await _flushSecurityDiagnostics(
        EvtLegacySecurityAction.bind,
        reason: 'security_operation_terminal',
        logger: logger,
        logStore: logStore,
      );
    }
  }

  Future<void> _promptAndUnbindDevice(
    SessionController session,
    EvtLegacyAuthController auth,
  ) => _promptAndUnbind(session, auth, recovery: false);

  Future<void> _promptAndUnbindRecovery(
    SessionController session,
    EvtLegacyAuthController auth,
  ) => _promptAndUnbind(session, auth, recovery: true);

  Future<void> _promptAndUnbind(
    SessionController session,
    EvtLegacyAuthController auth, {
    required bool recovery,
  }) async {
    var connectionOperation = _sessionConnectionOperation;
    final logger = ref.read(scopedAppLoggerProvider('AUTH'));
    final logStore = ref.read(appLogStoreProvider);
    final checkpoints = ref.read(
      deviceFileDownloadCheckpointRepositoryProvider,
    );
    if (!recovery) {
      final preflightPassed = await _verifyNormalUnbindPreflight(
        session,
        auth,
        connectionOperation: connectionOperation,
        logger: logger,
      );
      if (!preflightPassed) {
        await _flushSecurityDiagnostics(
          EvtLegacySecurityAction.unbind,
          reason: 'unbind_preflight_rejected',
          logger: logger,
          logStore: logStore,
        );
        return;
      }
      if (!_isCurrentSecurityUiOperation(session, connectionOperation)) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    _logSecurityUi(
      'security_code_sheet_opened',
      action: recovery ? 'unbind_recovery' : 'unbind',
      logger: logger,
    );
    final code = await EvtSecurityCodeSheet.show(
      context,
      title: recovery ? '恢复解绑' : '解绑设备',
      message: recovery
          ? '设备上一次解绑尚未确认完成。请输入同一设备当前的安全码，继续恢复清除流程。'
          : '请输入当前安全码。解绑前请先完成设备文件归档；设备会清除设备数据，最长等待 120 秒。',
      confirmLabel: recovery ? '恢复解绑' : '确认解绑',
    );
    if (code == null ||
        !_isCurrentSecurityUiOperation(session, connectionOperation)) {
      _logSecurityUi(
        'security_code_sheet_cancelled',
        action: recovery ? 'unbind_recovery' : 'unbind',
        logger: logger,
      );
      await _flushSecurityDiagnostics(
        EvtLegacySecurityAction.unbind,
        reason: 'security_code_sheet_cancelled',
        logger: logger,
        logStore: logStore,
      );
      return;
    }
    _logSecurityUi(
      'security_code_sheet_confirmed',
      action: recovery ? 'unbind_recovery' : 'unbind',
      fields: {'length': code.length},
      logger: logger,
    );
    try {
      if (recovery) {
        await auth.unbindRecovery(session, securityCode: code);
      } else {
        await auth.unbind(session, securityCode: code);
      }
      if (!_isCurrentSecurityUiOperation(session, connectionOperation)) {
        return;
      }
      _requestSecurityPrivateDiagnosticsFlush(
        EvtLegacySecurityAction.unbind,
        reason: 'v1_security_exchange_completed',
        logger: logger,
        logStore: logStore,
      );
      _logSecurityUi(
        'security_ui_operation_completed',
        action: recovery ? 'unbind_recovery' : 'unbind',
        result: 'success',
        logger: logger,
      );
      final candidate = session.state.session?.candidate;
      if (candidate != null) {
        _clearPendingUnbindRecovery(candidate);
      }
      final deviceId = candidate?.physicalDeviceId;
      if (deviceId != null) {
        await checkpoints.removeAllForDevice(deviceId);
      }
      if (!_isCurrentSecurityUiOperation(session, connectionOperation)) {
        return;
      }
      if (candidate != null) {
        await _reconnectController.forgetSuccessfulClear(candidate);
      }
      if (!_isCurrentSecurityUiOperation(session, connectionOperation)) {
        return;
      }
      connectionOperation = ++_sessionConnectionOperation;
      await _reconnectController.suppressForForeground();
      if (!_isCurrentSecurityUiOperation(session, connectionOperation)) {
        return;
      }
      await session.disconnect();
      if (mounted &&
          _isCurrentSecurityUiOperation(session, connectionOperation)) {
        AppToast.show(context, message: '设备已解绑并清除设备数据');
      }
    } catch (error) {
      // The controller marks the intent as soon as Action=2 is dispatched.
      // Capture it even if the connection disappears before its listener can
      // run, so the next connection still exposes recovery.
      _capturePendingUnbindRecovery();
      await _handleSecurityUiFailure(
        session: session,
        connectionOperation: connectionOperation,
        action: EvtLegacySecurityAction.unbind,
        error: error,
        logger: logger,
      );
    } finally {
      await _flushSecurityDiagnostics(
        EvtLegacySecurityAction.unbind,
        reason: 'security_operation_terminal',
        logger: logger,
        logStore: logStore,
      );
    }
  }

  Future<bool> _verifyNormalUnbindPreflight(
    SessionController session,
    EvtLegacyAuthController auth, {
    required int connectionOperation,
    required SafeAppLogger logger,
  }) async {
    _logSecurityUi(
      'security_unbind_preflight_requested',
      action: 'unbind',
      logger: logger,
    );
    if (!_isCurrentSecurityUiOperation(session, connectionOperation)) {
      return false;
    }
    if (!auth.isAuthenticated || !session.state.isObservable) {
      const message = '设备尚未完成认证并进入可用状态，暂时不能解绑。';
      _logSecurityUi(
        'security_unbind_preflight_rejected',
        action: 'unbind',
        result: 'failed',
        fields: const {
          'check': 'authenticated_observable_session',
          'reason': '【解绑预检】设备尚未完成认证并进入可用状态，未打开安全码输入，也未发送 Action=2',
        },
        logger: logger,
      );
      if (mounted) {
        AppToast.show(context, message: message);
      }
      return false;
    }
    try {
      await session.verifyEvtUnbindPreflight();
    } catch (error) {
      if (!_isCurrentSecurityUiOperation(session, connectionOperation)) {
        return false;
      }
      final message = switch (error) {
        EvtUnbindPreflightException() => error.message,
        _ => '无法确认设备录音、同步和文件状态，请重新连接后完成文件同步再解绑。',
      };
      _logSecurityUi(
        'security_unbind_preflight_rejected',
        action: 'unbind',
        result: 'failed',
        fields: {
          'check': 'device_state',
          'reason': '【解绑预检】$message 未打开安全码输入，也未发送 Action=2',
          'error_type': error.runtimeType.toString(),
        },
        logger: logger,
      );
      if (mounted) {
        AppToast.show(context, message: message);
      }
      return false;
    }
    if (!_isCurrentSecurityUiOperation(session, connectionOperation)) {
      return false;
    }
    _logSecurityUi(
      'security_unbind_preflight_completed',
      action: 'unbind',
      result: 'success',
      fields: const {'reason': '【解绑预检】设备空闲、同步状态为空闲且文件列表为空，允许打开安全码输入'},
      logger: logger,
    );
    return true;
  }

  void _logSecurityUi(
    String event, {
    required String action,
    String? result,
    Map<String, Object?> fields = const {},
    SafeAppLogger? logger,
  }) {
    final SafeAppLogger resolvedLogger =
        logger ?? ref.read(scopedAppLoggerProvider('AUTH'));
    final operation = switch (action) {
      'bind' => 'device_bind',
      'unbind' || 'unbind_recovery' => 'device_unbind',
      _ => 'device_authenticate',
    };
    resolvedLogger.info(
      event,
      operation: operation,
      stage: 'challenge',
      result: result,
      fields: {'action': action, ...fields},
    );
  }

  Future<void> _handleSecurityUiFailure({
    required SessionController session,
    required int connectionOperation,
    required EvtLegacySecurityAction action,
    required Object error,
    required SafeAppLogger logger,
  }) async {
    if (!_isCurrentSecurityUiOperation(session, connectionOperation)) {
      _logSecurityUi(
        'security_ui_stale_result_ignored',
        action: action.name,
        result: 'cancelled',
        fields: {
          'reason': '【认证界面】连接已更换或用户已主动断开，旧请求仅记录日志，不再弹出失败提示',
          'attempt': connectionOperation,
          'error_type': error.runtimeType.toString(),
        },
        logger: logger,
      );
      return;
    }
    _logSecurityUi(
      'security_ui_operation_failed',
      action: action.name,
      result: 'failed',
      fields: {'error_type': error.runtimeType.toString()},
      logger: logger,
    );
    if (mounted) {
      AppToast.show(
        context,
        message: evtLegacySecurityFailureMessage(action: action, error: error),
      );
    }
  }

  bool _isCurrentSecurityUiOperation(
    SessionController session,
    int connectionOperation,
  ) =>
      _isCurrentSessionConnectionOperation(connectionOperation) &&
      identical(_sessionController, session);

  static bool _shouldFlushDiagnosticsForLifecycle(AppLifecycleState state) =>
      state == AppLifecycleState.paused || state == AppLifecycleState.detached;

  void _requestSecurityPrivateDiagnosticsFlush(
    EvtLegacySecurityAction action, {
    required String reason,
    required SafeAppLogger logger,
    required FileAppLogStore logStore,
  }) {
    unawaited(
      _flushDiagnostics(
        logStore: logStore,
        onError: (error) => _logSecurityUi(
          'security_ui_diagnostics_flush_failed',
          action: action.name,
          result: 'failed',
          fields: {
            'reason': reason,
            'error_type': error.runtimeType.toString(),
          },
          logger: logger,
        ),
      ),
    );
  }

  Future<void> _flushSecurityDiagnostics(
    EvtLegacySecurityAction action, {
    required String reason,
    required SafeAppLogger logger,
    required FileAppLogStore logStore,
  }) async {
    _logSecurityUi(
      'security_ui_diagnostics_flush_requested',
      action: action.name,
      result: 'pending',
      fields: {'reason': reason},
      logger: logger,
    );
    await _flushDiagnostics(
      logStore: logStore,
      onError: (error) => _logSecurityUi(
        'security_ui_diagnostics_flush_failed',
        action: action.name,
        result: 'failed',
        fields: {'reason': reason, 'error_type': error.runtimeType.toString()},
        logger: logger,
      ),
    );
    await _syncSecurityPublicDiagnostics(
      action,
      reason: reason,
      logger: logger,
      logStore: logStore,
    );
  }

  Future<void> _syncSecurityPublicDiagnostics(
    EvtLegacySecurityAction action, {
    required String reason,
    required SafeAppLogger logger,
    required FileAppLogStore logStore,
  }) async {
    try {
      await logStore.syncPublicMirror().timeout(const Duration(seconds: 2));
    } catch (error) {
      _logSecurityUi(
        'security_ui_public_diagnostics_sync_failed',
        action: action.name,
        result: 'failed',
        fields: {'reason': reason, 'error_type': error.runtimeType.toString()},
        logger: logger,
      );
      await _flushDiagnostics(logStore: logStore, onError: (_) {});
    }
  }

  Future<void> _flushDiagnostics({
    required FileAppLogStore logStore,
    required void Function(Object error) onError,
  }) async {
    try {
      await logStore.flush().timeout(const Duration(seconds: 2));
    } catch (error) {
      onError(error);
    }
  }

  Future<void> _openDvtAudio(SessionController session) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DvtAudioProbePage(
          controller: DvtAudioProbeController(
            validatedAudioPayloads: session.dvtAudioPayloads,
            startDvtAudioProbe: session.startDvtAudioProbe,
            stopDvtAudioProbe: session.stopDvtAudioProbe,
          ),
        ),
      ),
    );
  }

  Future<void> _openDvtOta(SessionController session) async {
    final deviceId = session.state.session?.candidate.physicalDeviceId;
    if (deviceId == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DvtFirmwareUpdatePage(
          deviceId: deviceId,
          loadPackage: HttpsFirmwarePackageSource().load,
          createController: session.createDvtOtaController,
          createVerificationController:
              session.createDvtOtaVerificationController,
          releaseTransport: session.releaseDvtOta,
        ),
      ),
    );
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
    final metadataGateway = SessionDvtFileGateway(session);
    final importer = DvtDeviceFileImportService(
      pendingArchives: ref.read(dvtPendingArchiveRepositoryProvider),
      deviceId: deviceId,
      metadataGateway: metadataGateway,
      transferGateway: metadataGateway,
      files: ref.read(recordingFileStoreProvider),
      checkpoints: ref.read(deviceFileDownloadCheckpointRepositoryProvider),
      recordings: ref.read(localRecordingRepositoryProvider),
      logger: ref.read(scopedAppLoggerProvider('DVT_FILE')),
    );
    final archiver = DvtDeviceFileArchiveService(
      pendingArchives: ref.read(dvtPendingArchiveRepositoryProvider),
      metadataGateway: metadataGateway,
      archiveGateway: ref.read(dvtArchiveGatewayProvider),
      checkpoints: ref.read(deviceFileDownloadCheckpointRepositoryProvider),
      logger: ref.read(scopedAppLoggerProvider('DVT_ARCHIVE')),
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DeviceFileBrowserPage(
          onListFiles: ({required offset, required pageSize}) =>
              metadataGateway.listFiles(offset: offset, pageSize: pageSize),
          onImport: (file, {onProgress}) async =>
              (await importer.import(file, onProgress: onProgress)).recording,
          onMetadata: (file) =>
              metadataGateway.readDvtFileMetadata(nameSlot: file.nameSlot),
          onListPendingArchives: () async => [
            for (final imported in await importer.restoreReadyImports())
              DeviceFile(
                name: imported.metadata.name,
                nameSlot: imported.metadata.nameSlot,
                length: imported.metadata.fileSize,
              ),
          ],
          onRetryArchive: (file) async {
            final ready = await importer.restoreReadyImports();
            final matches = ready.where(
              (item) => item.metadata.matchesListedFile(file),
            );
            if (matches.length != 1) throw StateError('本地恢复文件缺失或校验失败，请查看日志。');
            final result = await archiver.archiveAndConfirm(matches.single);
            return result.deviceConfirmation.deviceDeleted
                ? '归档已确认，设备源文件已释放'
                : '归档已确认，设备源文件等待固件回收';
          },
          onArchive: (file) async {
            final imported = await importer.import(file);
            final result = await archiver.archiveAndConfirm(imported);
            return result.deviceConfirmation.deviceDeleted
                ? '归档完成，设备源文件已释放，本地录音保留'
                : '归档已确认，设备源文件等待固件回收，本地录音保留';
          },
          onOpenSavedRecordings: _openSavedDeviceRecordings,
          isSavedRecordingAvailable: (recording) => ref
              .read(recordingFileStoreProvider)
              .exists(recording.relativePath),
          onOpenRecording: (recording) =>
              _openDeviceRecordingDetail(recording, [recording]),
        ),
      ),
    );
  }

  Future<void> _openSavedDeviceRecordings() async {
    final library = RecordingLibraryController(
      repository: ref.read(localRecordingRepositoryProvider),
      files: ref.read(recordingFileStoreProvider),
      player: ref.read(deviceAudioPlayerFactoryProvider)(),
    );
    try {
      await library.load();
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DeviceRecordingLibraryPage(
            controller: library,
            onOpen: (recording) => unawaited(
              _openDeviceRecordingDetail(recording, library.state.items),
            ),
          ),
        ),
      );
    } finally {
      await library.close();
    }
  }

  Future<void> _openDeviceRecordingDetail(
    LocalRecording recording,
    List<LocalRecording> recordings,
  ) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DeviceRecordingDetailPage(
          recording: recording,
          recordings: recordings,
          files: ref.read(recordingFileStoreProvider),
          audioPlayerFactory: ref.read(deviceAudioPlayerFactoryProvider),
          onOpenRecording: (next) =>
              unawaited(_replaceDeviceRecordingDetail(next, recordings)),
        ),
      ),
    );
  }

  Future<void> _replaceDeviceRecordingDetail(
    LocalRecording recording,
    List<LocalRecording> recordings,
  ) {
    return Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(
        builder: (_) => DeviceRecordingDetailPage(
          recording: recording,
          recordings: recordings,
          files: ref.read(recordingFileStoreProvider),
          audioPlayerFactory: ref.read(deviceAudioPlayerFactoryProvider),
          onOpenRecording: (next) =>
              unawaited(_replaceDeviceRecordingDetail(next, recordings)),
        ),
      ),
    );
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
    final profile = _profile ?? DeviceProfile.evtV16();
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
