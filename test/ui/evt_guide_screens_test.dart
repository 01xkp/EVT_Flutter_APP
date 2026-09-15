// Actual Flutter widgets with synthetic guide data, never hardware evidence.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/design_system/evt_theme.dart';
import 'package:aipin/core/permissions/app_permission_gateway.dart';
import 'package:aipin/core/protocol/device_event.dart';
import 'package:aipin/features/device_discovery/application/discovery_controller.dart';
import 'package:aipin/features/device_discovery/application/discovery_state.dart';
import 'package:aipin/features/device_discovery/domain/advertisement_filter.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:aipin/features/device_discovery/presentation/discovery_page.dart';
import 'package:aipin/features/device_session/application/session_state.dart';
import 'package:aipin/features/device_session/domain/device_auth_state.dart';
import 'package:aipin/features/device_session/domain/device_capabilities.dart';
import 'package:aipin/features/device_session/domain/device_configuration.dart';
import 'package:aipin/features/device_session/domain/device_info.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/device_file_import_progress.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';
import 'package:aipin/features/device_session/domain/device_session.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:aipin/features/device_session/presentation/device_detail_page.dart';
import 'package:aipin/features/device_session/presentation/device_file_browser_page.dart';
import 'package:aipin/features/device_session/presentation/evt_security_code_sheet.dart';
import 'package:aipin/features/device_logs/data/file_app_log_store.dart';
import 'package:aipin/features/device_logs/domain/app_log_entry.dart';
import 'package:aipin/features/device_logs/domain/public_diagnostic_log_sink.dart';
import 'package:aipin/features/device_logs/presentation/device_log_page.dart';
import 'package:aipin/features/evidence/application/evidence_history_controller.dart';
import 'package:aipin/features/evidence/domain/evidence_bundle.dart';
import 'package:aipin/features/evidence/presentation/record_observation_sheet.dart';
import 'package:aipin/features/local_recording/application/recording_library_controller.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/presentation/device_recording_library_page.dart';
import 'package:aipin/features/local_recording/presentation/audio_playback_panel.dart';
import 'package:aipin/features/onboarding/presentation/welcome_page.dart';
import 'package:aipin/features/observation/domain/observation_scenario.dart';
import 'package:aipin/features/observation/domain/observation_verdict.dart';
import 'package:aipin/features/observation/presentation/observation_page.dart';
import 'package:aipin/features/records/presentation/records_page.dart';
import 'package:aipin/features/settings/application/theme_mode_controller.dart';
import 'package:aipin/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_audio_player.dart';
import '../support/fake_ble_transport.dart';
import '../support/fake_evidence_repository.dart';
import '../support/fake_local_recording_repository.dart';
import '../support/fake_recording_file_store.dart';

const _screenKey = ValueKey('evt-guide-screen');
final _sampleTime = DateTime(2026, 9, 15, 16, 30);
final _candidate = DeviceCandidate(
  connectionId: '00:11:22:33:0A:A2',
  name: 'RECORD_0AA2',
  manufacturerData: const [0xA3, 0x89, 0, 0x11, 0x22, 0x33, 0x0A, 0xA2],
  serviceUuids: const [],
  rssi: -48,
  discoveredAt: _sampleTime,
);
final _snapshot = DeviceSnapshot(
  state: DeviceState.standby,
  observedAt: _sampleTime,
  source: 'guide-fixture',
);

void main() {
  if (Platform.environment['EVT_GUIDE_OUTPUT'] == null) {
    test(
      'guide screenshot generation requires EVT_GUIDE_OUTPUT',
      () {},
      skip: true,
    );
    return;
  }
  setUpAll(() async {
    final fontBytes = File(
      Platform.environment['EVT_GUIDE_FONT'] ?? 'C:/Windows/Fonts/msyh.ttc',
    ).readAsBytes().then(ByteData.sublistView);
    await (FontLoader('monospace')..addFont(fontBytes)).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader('GuideFont')..addFont(
          File(
            Platform.environment['EVT_GUIDE_FONT'] ??
                'C:/Windows/Fonts/msyh.ttc',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });

  testWidgets('capture discovery with a selected example device', (
    tester,
  ) async {
    final transport = FakeBleTransport();
    final controller = _GuideDiscoveryController(transport);
    addTearDown(() async {
      controller.dispose();
      await transport.dispose();
    });
    await _mount(
      tester,
      DiscoveryPage(
        controller: controller,
        onConnect: (_) async => true,
        onSettings: () {},
      ),
    );
    await _save(tester, 'discovery');
  });

  testWidgets('capture idle device, configuration and management dialogs', (
    tester,
  ) async {
    await _mount(tester, _devicePage());
    await _save(tester, 'device-idle');
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    await _save(tester, 'device-settings');
    await tester.tap(find.text('默认隐私时长'));
    await tester.pumpAndSettle();
    await _save(tester, 'privacy-menu');
    await tester.tap(find.text('10 分钟').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('设备管理'), 300);
    await tester.tap(find.text('设备管理'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('解绑设备'));
    await tester.pumpAndSettle();
    await _save(tester, 'device-management');
    await tester.tap(find.text('解绑设备'));
    await tester.pumpAndSettle();
    await _save(tester, 'unbind-confirmation');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('断开设备'));
    await tester.tap(find.text('断开设备'));
    await tester.pumpAndSettle();
    await _save(tester, 'disconnect-confirmation');
  });

  testWidgets('capture saved recordings and local management dialogs', (
    tester,
  ) async {
    final controller = RecordingLibraryController(
      repository: FakeLocalRecordingRepository([
        for (var i = 0; i < 2; i++)
          LocalRecording.saved(
            id: 'guide-$i',
            title: i == 0 ? '06aa8f953.ogg' : '按键录音检查',
            relativePath: 'guide-$i.ogg',
            createdAt: _sampleTime.subtract(Duration(minutes: i * 5)),
            completedAt: _sampleTime,
            duration: Duration(seconds: i == 0 ? 20 : 45),
            sizeBytes: i == 0 ? 40387 : 89920,
          ),
      ]),
      files: FakeRecordingFileStore(),
      player: FakeAudioPlayer(),
    );
    addTearDown(controller.close);
    await controller.load();
    await _mount(
      tester,
      DeviceRecordingLibraryPage(controller: controller, onOpen: (_) {}),
    );
    await _save(tester, 'library');
    await tester.tap(find.byTooltip('更多操作').first);
    await tester.pumpAndSettle();
    await _save(tester, 'library-menu');
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await _save(tester, 'rename-recording');
    await tester.enterText(find.byType(TextField), '按键联调录音');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await _save(tester, 'library-renamed');
    await tester.tap(find.byTooltip('更多操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await _save(tester, 'delete-recording');
  });

  testWidgets('capture check records and observation screens', (tester) async {
    final repository = FakeEvidenceRepository([
      EvidenceBundle.completed(
        deviceId: 'guide-device',
        deviceName: 'RECORD_0AA2',
        verdict: ObservationVerdict.passed,
        reason: '示例：已获得所需设备证据。',
        createdAt: _sampleTime,
      ),
      EvidenceBundle.completed(
        deviceId: 'guide-device',
        deviceName: 'RECORD_0AA2',
        verdict: ObservationVerdict.unverifiable,
        reason: '示例：缺少人工观察记录。',
        createdAt: _sampleTime.subtract(const Duration(minutes: 10)),
      ),
    ]);
    final controller = EvidenceHistoryController(repository);
    addTearDown(controller.dispose);
    await controller.load();
    await _mount(tester, RecordsPage(evidenceController: controller));
    await _save(tester, 'records');
    await _mount(
      tester,
      Builder(
        builder: (context) => ObservationPage(
          repository: repository,
          deviceId: 'guide-device',
          deviceName: 'RECORD_0AA2',
          latestSnapshot: _snapshot,
          initialScenario: ObservationScenario.vadRecording,
          events: [
            for (final kind in [
              DeviceEventKind.recordingStarted,
              DeviceEventKind.silenceEnded,
            ])
              DeviceEvent(
                kind: kind,
                occurredAt: _sampleTime,
                source: 'guide-fixture',
              ),
          ],
          onRecordPhysicalFeedback: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => RecordObservationSheet(
              repository: repository,
              deviceId: 'guide-device',
              deviceName: 'RECORD_0AA2',
              latestSnapshot: _snapshot,
            ),
          ),
        ),
      ),
    );
    await _save(tester, 'observation');
    await tester.tap(find.text('保存验证结果'));
    await tester.pumpAndSettle();
    await _save(tester, 'observation-saved');
    await tester.tap(
      find.text(ObservationScenario.physicalFeedback.title).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录人工观察'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      '示例：短按按键后，LED 提示与 App 录音状态一致。',
    );
    await tester.tap(find.text('LED'));
    await tester.pumpAndSettle();
    await _save(tester, 'manual-observation');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await _save(tester, 'manual-observation-saved');
  });

  testWidgets('capture settings with granted example permission', (
    tester,
  ) async {
    final themeController = ThemeModeController(_GuideThemeStore());
    addTearDown(themeController.dispose);
    await _mount(
      tester,
      SettingsPage(
        profile: DeviceProfile.evtV16(),
        themeController: themeController,
        permissions: _GuidePermissions(),
      ),
    );
    await _save(tester, 'settings');
  });

  testWidgets('capture first launch, authentication and recording states', (
    tester,
  ) async {
    await _mount(tester, WelcomePage(onConnectDevice: () {}));
    await _save(tester, 'welcome');
    await _mount(
      tester,
      DeviceDetailPage(
        state: SessionState(
          phase: SessionPhase.authenticationReady,
          session: DeviceSession(
            candidate: _candidate,
            profile: DeviceProfile.evtV16(),
            startedAt: _sampleTime,
          ),
        ),
        authState: DeviceAuthState.unknown,
        onAuthenticate: () {},
        onBind: () {},
        onDisconnect: () {},
        onOpenLogs: () {},
      ),
    );
    await _save(tester, 'device-unauthenticated');
    await _mount(
      tester,
      DeviceDetailPage(
        state: SessionState(
          phase: SessionPhase.authenticationReady,
          session: DeviceSession(
            candidate: _candidate,
            profile: DeviceProfile.evtV16(),
            startedAt: _sampleTime,
          ),
        ),
        authState: DeviceAuthState.authenticating,
        authenticatingAction: EvtLegacySecurityAction.bind,
        onDisconnect: () {},
        onOpenLogs: () {},
      ),
    );
    await _save(tester, 'binding-wait');
    await _mount(
      tester,
      const Scaffold(
        body: Center(
          child: EvtSecurityCodeSheet(
            title: '认证设备',
            message: '请输入该设备当前的安全码。',
            confirmLabel: '开始认证',
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('显示'));
    await tester.pumpAndSettle();
    await _save(tester, 'security-example');
    await _mount(tester, _devicePage(recordState: DeviceState.recording));
    await _save(tester, 'device-recording');
    await _mount(tester, _devicePage(recordState: DeviceState.paused));
    await _save(tester, 'device-paused');
  });

  testWidgets('capture file download progress, completion and audio playback', (
    tester,
  ) async {
    final pending = Completer<LocalRecording>();
    await _mount(
      tester,
      DeviceFileBrowserPage(
        onListFiles: ({required offset, required pageSize}) async => offset == 0
            ? const [
                DeviceFile(name: '06aa8f953.ogg', nameSlot: [1], length: 40387),
              ]
            : const [],
        onImport: (_, {onProgress}) {
          onProgress?.call(
            const DeviceFileImportProgress(received: 20194, total: 40387),
          );
          return pending.future;
        },
        onOpenRecording: (_) async {},
        onOpenSavedRecordings: () async {},
      ),
    );
    await tester.tap(find.text('保存到 App'));
    await tester.pump(const Duration(milliseconds: 500));
    await _save(tester, 'download-progress');
    pending.complete(
      LocalRecording.saved(
        id: 'guide-download',
        title: '06aa8f953.ogg',
        relativePath: 'guide-download.ogg',
        createdAt: _sampleTime,
        completedAt: _sampleTime,
        duration: const Duration(seconds: 20),
        sizeBytes: 40387,
      ),
    );
    await tester.pumpAndSettle();
    await _save(tester, 'download-saved');
    final player = FakeAudioPlayer()
      ..playDuration = const Duration(seconds: 20);
    await _mount(
      tester,
      Scaffold(
        appBar: AppBar(title: const Text('06aa8f953.ogg')),
        body: AudioPlaybackPanel(
          duration: const Duration(seconds: 20),
          resolvePath: () async => '/guide-fixture.ogg',
          audioPlayerFactory: () => player,
          playbackErrorMessage: '无法播放',
          onPrevious: () {},
          onNext: () {},
        ),
      ),
    );
    await tester.tap(find.text('播放录音'));
    player.emitPosition(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    await _save(tester, 'player-playing');
    await tester.tap(find.text('暂停录音'));
    await tester.pumpAndSettle();
    await _save(tester, 'player-paused');
    final unknownDurationPlayer = FakeAudioPlayer();
    await _mount(
      tester,
      Scaffold(
        appBar: AppBar(title: const Text('06aa8f953.ogg')),
        body: AudioPlaybackPanel(
          duration: Duration.zero,
          resolvePath: () async => '/guide-unknown-duration.ogg',
          audioPlayerFactory: () => unknownDurationPlayer,
          playbackErrorMessage: '无法播放',
          onPrevious: () {},
          onNext: () {},
        ),
      ),
    );
    await tester.tap(find.text('播放录音'));
    unknownDurationPlayer.emitPosition(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('0:05'), findsOneWidget);
    expect(find.text('时长未知'), findsOneWidget);
    await _save(tester, 'player-unknown');
  });

  testWidgets('capture log following, pause and export callback', (
    tester,
  ) async {
    final store = _GuideLogStore();
    addTearDown(store.dispose);
    String? exportedPath;
    store.emit('security_auth_succeeded', 'AUTH');
    store.emit('recording_started', 'SESSION');
    await _mount(
      tester,
      DeviceLogPage(
        store: store,
        onExport: (path) async {
          exportedPath = path;
        },
      ),
    );
    await _save(tester, 'logs');
    await tester.tap(find.text('暂停跟随'));
    await tester.pumpAndSettle();
    await _save(tester, 'logs-paused');
    store.emit('file_transfer_completed', 'FILE');
    await tester.tap(find.text('继续跟随'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出日志'));
    await tester.pumpAndSettle();
    expect(exportedPath, 'Download/AIPIN/logs/aipin-2026-09-15-163000.log');
    await _save(tester, 'logs-exported');
  });
}

DeviceDetailPage _devicePage({DeviceState recordState = DeviceState.standby}) =>
    DeviceDetailPage(
      state: SessionState(
        phase: SessionPhase.observable,
        session: DeviceSession(
          candidate: _candidate,
          profile: DeviceProfile.evtV16(),
          startedAt: _sampleTime,
        ),
        latestSnapshot: DeviceSnapshot(
          state: recordState,
          observedAt: _sampleTime,
          source: 'guide-fixture',
        ),
        deviceInfo: const DeviceInfo(
          capabilities: DeviceCapabilities(protocolVersion: 3),
          deviceCode: 'EVT202609150001',
          softwareVersion: 'V1.6',
          hardwareVersion: 'EVT',
          deviceName: 'RECORD_0AA2',
          totalDiskSpaceMb: 211,
          remainDiskSpaceMb: 192,
          recordStatus: 0,
          batteryLevel: 63,
          charging: 0,
          powerOff: 0,
          chargingMode: 0,
        ),
        deviceBattery: const DeviceBattery(
          percent: 63,
          isCharging: false,
          chargingMode: 0,
        ),
        deviceStorage: const DeviceStorage(
          totalMegabytes: 211,
          freeMegabytes: 192,
        ),
        deviceStatus: const DeviceStatus(
          privacy: false,
          privacyRemainingMinutes: 0,
          recordConsent: true,
          syncState: 0,
        ),
        privacyDurationCode: 1,
        fileCount: 3,
      ),
      authState: DeviceAuthState.authenticated,
      canOpenFiles: true,
      canControlRecording: true,
      canConfigureDevice: true,
      canRefreshDeviceDetails: true,
      onRecordAction: (_) {},
      onRecordConsentChanged: (_) {},
      onPrivacyDurationChanged: (_) {},
      onOpenFiles: () {},
      onOpenLogs: () {},
      onOpenSavedRecordings: () {},
      onRefreshDeviceDetails: () {},
      onOpenChecking: () {},
      onDisconnect: () {},
      onUnbind: () {},
    );

Future<void> _mount(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  final theme = EvtTheme.light();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _screenKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'GuideFont'),
        ),
        home: page,
      ),
    ),
  );
  // Binding and scanning can intentionally animate indefinitely.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _save(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screenKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(Platform.environment['EVT_GUIDE_OUTPUT']!);
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _GuideDiscoveryController extends DiscoveryController {
  _GuideDiscoveryController(FakeBleTransport transport)
    : super(transport, const AdvertisementFilter());

  @override
  DiscoveryState get state =>
      DiscoveryState(candidates: [_candidate], selected: _candidate);
}

class _GuidePermissions implements AppPermissionGateway {
  @override
  Future<AppPermissionState> nearbyDevices() async =>
      AppPermissionState.granted;
  @override
  Future<bool> openSettings() async => true;
}

class _GuideThemeStore implements ThemeModeStore {
  @override
  Future<ThemeMode?> read() async => null;
  @override
  Future<void> write(ThemeMode mode) async {}
  @override
  Future<void> clear() async {}
}

class _GuideLogStore extends FileAppLogStore {
  _GuideLogStore() : super(enabled: false);
  final _entries = <AppLogEntry>[];
  @override
  List<AppLogEntry> get entries => List.unmodifiable(_entries);
  void emit(String event, String scope) {
    _entries.add(
      AppLogEntry(
        timestamp: _sampleTime,
        scope: scope,
        event: event,
        result: 'success',
        fields: const {'fixture': true},
      ),
    );
    notifyListeners();
  }

  @override
  PublicDiagnosticLogMirrorStatus? get publicMirrorStatus =>
      PublicDiagnosticLogMirrorStatus.success(
        relativePath: 'Download/AIPIN/logs/aipin-2026-09-15-163000.log',
        lastUpdatedAt: _sampleTime,
      );
  @override
  Future<String?> exportPath() async =>
      'Download/AIPIN/logs/aipin-2026-09-15-163000.log';
}
