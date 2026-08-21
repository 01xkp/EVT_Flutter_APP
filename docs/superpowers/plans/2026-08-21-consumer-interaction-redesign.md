# Consumer Interaction Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Redesign the Flutter app as a consumer-facing AIPIN recording-device companion without changing BLE observation or phone-local audio contracts.

**Architecture:** Preserve Riverpod assembly, ChangeNotifier feature controllers, Drift repositories, and the feature-first layout. Add small consumer presentation mappers and shared widgets. AppShell owns controller lifetime and routes callbacks only; no widget calls a BLE or audio plugin.

**Tech Stack:** Flutter Material 3, flutter_riverpod, flutter_reactive_ble, permission_handler, record, just_audio, Drift, flutter_test.

---

## File Structure

| Path | Responsibility |
| --- | --- |
| lib/core/design_system | Approved tokens, theme, navigation, cards, sheets and confirmation primitives. |
| lib/core/permissions | Testable permission status and settings gateway. |
| lib/features/onboarding | One-time welcome decision. |
| lib/features/home/presentation | Consumer home and device summary states. |
| lib/features/device_discovery/presentation | Connection, candidate choice and recovery. |
| lib/features/device_session/presentation | Consumer device detail and pure status mapping. |
| lib/features/local_recording/presentation | Start, active recording, list and management UI. |
| lib/features/records/presentation | Local recordings and device activity destination. |
| lib/features/evidence/presentation | Consumer activity projection while retaining evidence storage. |
| lib/app | Stable destination enum, navigation shell and dependency coordination. |

### Task 1: Rebuild Theme Tokens And Shared Surfaces

**Files:**
- Create: lib/app/app_destination.dart
- Modify: lib/core/design_system/evt_colors.dart
- Modify: lib/core/design_system/evt_theme.dart
- Modify: lib/core/design_system/widgets/app_dialog.dart
- Create: lib/core/design_system/widgets/app_navigation_bar.dart
- Create: lib/core/design_system/widgets/app_surface_card.dart
- Create: lib/core/design_system/widgets/permission_rationale_sheet.dart
- Create: lib/core/design_system/widgets/app_confirmation_sheet.dart
- Modify: test/core/design_system/evt_theme_test.dart
- Create: test/core/design_system/app_navigation_bar_test.dart
- Create: test/core/design_system/app_confirmation_sheet_test.dart

- [ ] **Step 1: Write failing token and widget tests**

~~~dart
test('light theme uses approved warm semantic tokens', () {
  final theme = EvtTheme.light();

  expect(theme.scaffoldBackgroundColor, const Color(0xFFF8F6F3));
  expect(theme.colorScheme.surface, const Color(0xFFFFFFFF));
  expect(theme.colorScheme.primary, const Color(0xFF19212B));
  expect(theme.dividerColor, const Color(0xFFE5E1DA));
});

testWidgets('navigation has three consumer destinations', (tester) async {
  var selected = AppDestination.home;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AppNavigationBar(
          selected: selected,
          onSelected: (value) => selected = value,
        ),
      ),
    ),
  );

  await tester.tap(find.text('记录'));
  expect(selected, AppDestination.records);
});
~~~

- [ ] **Step 2: Run the failing tests**

Run: flutter test test/core/design_system/evt_theme_test.dart test/core/design_system/app_navigation_bar_test.dart test/core/design_system/app_confirmation_sheet_test.dart

Expected: FAIL because AppDestination, AppNavigationBar and AppConfirmationSheet do not exist, and palette values are old.

- [ ] **Step 3: Implement tokens and primitives**

Set exact semantic tokens in EvtLightColors and EvtDarkColors: canvas F8F6F3/11100E, surface FFFFFF/1D1B18, subtle F0EDE8/2B2824, text 1C1A17/EFECE7, secondary 6B655C/A69E94, divider E5E1DA/2F2C27, action 19212B/F0F4F8. Preserve 8px component radius and 180ms motion.

~~~dart
class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selected.index,
      onDestinationSelected: (index) =>
          onSelected(AppDestination.values[index]),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: '首页',
        ),
        NavigationDestination(
          icon: Icon(Icons.mic_none_outlined),
          selectedIcon: Icon(Icons.mic),
          label: '录音',
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_open_outlined),
          selectedIcon: Icon(Icons.folder_open),
          label: '记录',
        ),
      ],
    );
  }
}
~~~

AppSurfaceCard accepts child, optional onTap and selected state. PermissionRationaleSheet.show returns true only after 继续. AppConfirmationSheet has normal and destructive variants. Make AppDialog.confirmDestructive delegate to AppConfirmationSheet so existing deletion calls keep their contract.

- [ ] **Step 4: Verify the primitive layer**

Run: flutter test test/core/design_system/evt_theme_test.dart test/core/design_system/app_navigation_bar_test.dart test/core/design_system/app_confirmation_sheet_test.dart

Expected: PASS.

- [ ] **Step 5: Format and commit**

Run: dart format lib/core/design_system test/core/design_system

Run: git add lib/core/design_system test/core/design_system

Run: git commit -m "feat: add consumer design primitives"

### Task 2: Add Onboarding And Stable Shell Navigation

**Files:**
- Create: lib/features/onboarding/domain/onboarding_store.dart
- Create: lib/features/onboarding/data/shared_preferences_onboarding_store.dart
- Create: lib/features/onboarding/application/onboarding_controller.dart
- Create: lib/features/onboarding/presentation/welcome_page.dart
- Modify: lib/app/providers.dart
- Modify: lib/app/app_shell.dart
- Create: test/features/onboarding/application/onboarding_controller_test.dart
- Create: test/features/onboarding/presentation/welcome_page_test.dart
- Create: test/support/fake_onboarding_store.dart
- Modify: test/app/app_shell_test.dart

- [ ] **Step 1: Write failing onboarding and shell tests**

~~~dart
test('completion persists the welcome decision', () async {
  final store = FakeOnboardingStore();
  final controller = OnboardingController(store);

  expect(await controller.load(), isFalse);
  await controller.complete();

  expect(store.completed, isTrue);
  expect(controller.isComplete, isTrue);
});

testWidgets('welcome enters either supported first-use route', (tester) async {
  var connectCalls = 0;
  var localCalls = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: WelcomePage(
        onConnectDevice: () => connectCalls += 1,
        onUseLocalRecording: () => localCalls += 1,
      ),
    ),
  );

  await tester.tap(find.text('连接我的设备'));
  await tester.tap(find.text('先用本机录音'));

  expect(connectCalls, 1);
  expect(localCalls, 1);
});
~~~

Update shell expectations from workbench tooltips to 首页, 录音 and 记录.

- [ ] **Step 2: Run the failing tests**

Run: flutter test test/features/onboarding test/app/app_shell_test.dart

Expected: FAIL because onboarding storage, controller, welcome page and consumer navigation are absent.

- [ ] **Step 3: Implement welcome storage and shell gate**

~~~dart
abstract interface class OnboardingStore {
  Future<bool> isComplete();
  Future<void> markComplete();
}

class OnboardingController extends ChangeNotifier {
  OnboardingController(this._store);

  final OnboardingStore _store;
  bool _isComplete = false;

  bool get isComplete => _isComplete;

  Future<bool> load() async {
    _isComplete = await _store.isComplete();
    notifyListeners();
    return _isComplete;
  }

  Future<void> complete() async {
    await _store.markComplete();
    _isComplete = true;
    notifyListeners();
  }
}

final onboardingStoreProvider = Provider<OnboardingStore>(
  (ref) => SharedPreferencesOnboardingStore(),
);
~~~

Create a SharedPreferences implementation and provider. AppShell loads the controller once, renders WelcomePage until completion, and marks completion before routing. The local route selects AppDestination.recording. The connection route selects AppDestination.home and opens the connection journey. Replace integer destinations with AppDestination and use AppNavigationBar. Keep recording/BLE lifecycle methods in AppShell; split only destination widgets into private builders.

- [ ] **Step 4: Verify onboarding and navigation**

Run: flutter test test/features/onboarding test/app/app_shell_test.dart

Expected: PASS.

- [ ] **Step 5: Format and commit**

Run: dart format lib/app lib/features/onboarding test/app test/features/onboarding test/support

Run: git add lib/app lib/features/onboarding test/app test/features/onboarding test/support

Run: git commit -m "feat: add consumer onboarding and navigation"

### Task 3: Build Consumer Home And Connection Journey

**Files:**
- Create: lib/features/home/presentation/home_page.dart
- Create: lib/features/home/presentation/device_summary_card.dart
- Modify: lib/features/device_discovery/presentation/discovery_page.dart
- Modify: lib/features/device_discovery/presentation/device_candidate_row.dart
- Modify: lib/features/device_discovery/application/discovery_controller.dart
- Modify: lib/app/app_shell.dart
- Create: test/features/home/presentation/home_page_test.dart
- Modify: test/features/device_discovery/presentation/discovery_page_test.dart
- Modify: test/app/app_shell_test.dart

- [ ] **Step 1: Write failing home and connection tests**

~~~dart
testWidgets('home keeps local recording available while device is disconnected', (
  tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(
        device: const DeviceSummary.disconnected(name: 'AIPIN-01'),
        onConnectDevice: () {},
        onStartLocalRecording: () {},
        onOpenSettings: () {},
      ),
    ),
  );

  expect(find.text('尚未连接'), findsOneWidget);
  expect(find.text('连接设备'), findsOneWidget);
  expect(find.text('本机录音'), findsOneWidget);
  expect(find.text('无需连接设备'), findsOneWidget);
});

testWidgets('discovery exposes recovery after scan failure', (tester) async {
  final transport = FakeBleTransport();
  final controller = DiscoveryController(transport, const AdvertisementFilter());
  addTearDown(controller.dispose);

  await tester.pumpWidget(MaterialApp(home: DiscoveryPage(controller: controller)));
  await tester.tap(find.text('查找附近设备'));
  transport.emitScanError(StateError('bluetooth unavailable'));
  await tester.pump();

  expect(find.text('重新查找'), findsOneWidget);
  expect(find.text('查看连接帮助'), findsOneWidget);
});
~~~

- [ ] **Step 2: Run the failing tests**

Run: flutter test test/features/home/presentation/home_page_test.dart test/features/device_discovery/presentation/discovery_page_test.dart test/app/app_shell_test.dart

Expected: FAIL because DeviceSummary, HomePage and consumer connection copy do not exist.

- [ ] **Step 3: Implement home state mapping and discovery UI**

Create an immutable presentation model with disconnected, searching and connected factories. HomePage receives only DeviceSummary and callbacks. It renders settings, a My Device card, one current primary device action, high-emphasis local record action and a non-actionable device recording-status row. Use AppSurfaceCard and AnimatedSwitcher with EvtTheme.motionDuration. Do not render raw BLE terms.

Refactor DiscoveryPage to title 连接设备, action 查找附近设备, selected candidate rows with signals 信号良好, 信号一般 or 信号较弱, cancel while scanning, and inline failure panel with 重新查找 plus 查看连接帮助. Preserve AdvertisementFilter and DiscoveryController ordering. AppShell maps its session/discovery data through _deviceSummary() and keeps the existing _openSession(candidate).

- [ ] **Step 4: Verify home and connection**

Run: flutter test test/features/home/presentation/home_page_test.dart test/features/device_discovery/presentation/discovery_page_test.dart test/app/app_shell_test.dart

Expected: PASS.

- [ ] **Step 5: Format and commit**

Run: dart format lib/app lib/features/home lib/features/device_discovery test/app test/features/home test/features/device_discovery

Run: git add lib/app lib/features/home lib/features/device_discovery test/app test/features/home test/features/device_discovery

Run: git commit -m "feat: add consumer home and connection flow"

### Task 4: Present Consumer Device Detail

**Files:**
- Create: lib/features/device_session/presentation/device_status_view_model.dart
- Create: lib/features/device_session/presentation/device_detail_page.dart
- Modify: lib/features/device_session/presentation/session_dashboard_page.dart
- Modify: lib/features/device_session/presentation/session_failure_panel.dart
- Modify: lib/app/app_shell.dart
- Create: test/features/device_session/presentation/device_status_view_model_test.dart
- Modify: test/features/device_session/presentation/session_dashboard_page_test.dart
- Modify: test/app/app_shell_test.dart

- [ ] **Step 1: Write failing status and disconnect tests**

~~~dart
test('recording snapshot maps to ordinary consumer status', () {
  final viewModel = DeviceStatusViewModel.from(
    const SessionState(
      phase: SessionPhase.observable,
      latestSnapshot: DeviceSnapshot(
        state: DeviceState.recording,
        observedAt: DateTime(2026, 8, 21, 9, 41),
        source: 'test',
      ),
    ),
  );

  expect(viewModel.connectionLabel, '已连接');
  expect(viewModel.recordingLabel, '正在录音');
  expect(viewModel.canReconnect, isFalse);
});

testWidgets('detail asks before disconnecting', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: DeviceDetailPage(
        state: SessionState(phase: SessionPhase.observable),
        onDisconnect: _noOp,
      ),
    ),
  );

  await tester.tap(find.text('断开设备'));
  await tester.pumpAndSettle();

  expect(find.text('断开设备？'), findsOneWidget);
});

void _noOp() {}
~~~

- [ ] **Step 2: Run the failing tests**

Run: flutter test test/features/device_session/presentation/device_status_view_model_test.dart test/features/device_session/presentation/session_dashboard_page_test.dart test/app/app_shell_test.dart

Expected: FAIL because DeviceStatusViewModel and DeviceDetailPage do not exist.

- [ ] **Step 3: Implement mapping and detail page**

~~~dart
final class DeviceStatusViewModel {
  const DeviceStatusViewModel({
    required this.connectionLabel,
    required this.recordingLabel,
    required this.updatedAt,
    this.batteryLabel,
    required this.canReconnect,
  });

  factory DeviceStatusViewModel.from(SessionState state) {
    final snapshot = state.latestSnapshot;
    final connected = state.isObservable;
    return DeviceStatusViewModel(
      connectionLabel: connected ? '已连接' : '已断开',
      recordingLabel: switch (snapshot?.state) {
        DeviceState.recording => '正在录音',
        DeviceState.standby => '未在录音',
        _ => '暂时无法获取',
      },
      batteryLabel: snapshot?.batteryPercent?.toString(),
      updatedAt: snapshot?.observedAt,
      canReconnect: !connected,
    );
  }
}
~~~

DeviceDetailPage shows name, connection, observed recording state, battery, timestamp, connection help, reconnect and disconnect. Place existing observation behind 设备检查. Never add start-device-recording, playback or device-file actions. Turn SessionDashboardPage into a compatibility wrapper around DeviceDetailPage or remove all callers in the same commit. Add _disconnectSession() to AppShell, await SessionController.disconnect(), retain state for disconnected detail and route retry to existing connect(candidate).

- [ ] **Step 4: Verify device detail**

Run: flutter test test/features/device_session/presentation/device_status_view_model_test.dart test/features/device_session/presentation/session_dashboard_page_test.dart test/app/app_shell_test.dart

Expected: PASS.

- [ ] **Step 5: Format and commit**

Run: dart format lib/app lib/features/device_session test/app test/features/device_session

Run: git add lib/app lib/features/device_session test/app test/features/device_session

Run: git commit -m "feat: present consumer device detail"

### Task 5: Make Recording And Records Consumer Destinations

**Files:**
- Modify: lib/features/local_recording/presentation/recording_hub_page.dart
- Modify: lib/features/local_recording/presentation/active_recording_page.dart
- Modify: lib/features/local_recording/presentation/local_recording_library_page.dart
- Modify: lib/features/local_recording/presentation/recording_list_item.dart
- Modify: lib/features/local_recording/presentation/rename_recording_sheet.dart
- Create: lib/features/local_recording/presentation/local_recording_list.dart
- Create: lib/features/records/presentation/records_page.dart
- Create: lib/features/evidence/presentation/device_activity_list.dart
- Modify: lib/features/evidence/presentation/evidence_history_page.dart
- Modify: lib/app/app_shell.dart
- Modify: test/features/local_recording/presentation/recording_hub_page_test.dart
- Modify: test/features/local_recording/presentation/active_recording_page_test.dart
- Modify: test/features/local_recording/presentation/local_recording_library_page_test.dart
- Create: test/features/records/presentation/records_page_test.dart
- Modify: test/features/evidence/presentation/evidence_history_page_test.dart

- [ ] **Step 1: Write failing recording and record-tab tests**

~~~dart
testWidgets('recording destination exposes local recording as the only start action', (
  tester,
) async {
  await tester.pumpWidget(
    const MaterialApp(home: RecordingHubPage(isHardwareObservable: false)),
  );

  expect(find.text('开始本机录音'), findsOneWidget);
  expect(find.text('无需连接设备'), findsOneWidget);
  expect(find.text('设备录音状态'), findsOneWidget);
  expect(find.text('开始设备录音'), findsNothing);
});

testWidgets('records switches between local recordings and device activity', (
  tester,
) async {
  final localController = RecordingLibraryController(
    repository: FakeLocalRecordingRepository(),
    files: FakeRecordingFileStore(),
    player: FakeAudioPlayer(),
  );
  final activityController = EvidenceHistoryController(
    FakeEvidenceRepository(),
  );
  addTearDown(localController.close);
  addTearDown(activityController.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: RecordsPage(
        recordingController: localController,
        evidenceController: activityController,
        onStartRecording: () {},
      ),
    ),
  );

  expect(find.text('本机录音'), findsOneWidget);
  await tester.tap(find.text('设备活动'));
  await tester.pumpAndSettle();
  expect(find.text('设备活动'), findsWidgets);
});
~~~

Add active-recorder coverage that presses back while active and expects 继续录音 and 结束并保存. Add list coverage for source label, unavailable-file copy, selected rename text and destructive deletion confirmation.

- [ ] **Step 2: Run the failing tests**

Run: flutter test test/features/local_recording/presentation test/features/records/presentation test/features/evidence/presentation

Expected: FAIL because RecordsPage, consumer copy, exit confirmation and extracted list body do not exist.

- [ ] **Step 3: Implement recording and records surfaces**

RecordingHubPage becomes the 录音 destination. Its primary text is 开始本机录音 and it keeps the library shortcut. Replace hardware action with a non-actionable device-recording-status row that opens device detail only when a session exists.

Wrap ActiveRecordingPage in PopScope and use AppConfirmationSheet if state.isCaptureActive. Preserve RecordingController timing, amplitude, pause, resume, background and finalization logic. Update active copy to 正在录音 and show red dot plus text. Permission-denied state gets an open-settings callback.

Extract LocalRecordingList from LocalRecordingLibraryPage. It groups records by day and displays creation time, duration and 本机录音 while retaining RecordingLibraryController playback, rename and delete calls. Do not alter LocalRecording, file-store or repository contracts.

RecordsPage owns a SegmentedButton between LocalRecordingList and DeviceActivityList. DeviceActivityList receives EvidenceHistoryController and maps saved bundles to consumer text such as 已完成设备检查. It hides raw verdict vocabulary and deletion in the consumer route. Keep EvidenceHistoryPage as contextual advanced history. AppShell lazy-loads recording and evidence controllers before RecordsPage and refreshes both after recording or saved observation.

- [ ] **Step 4: Verify recording and record destinations**

Run: flutter test test/features/local_recording/presentation test/features/records/presentation test/features/evidence/presentation

Expected: PASS.

- [ ] **Step 5: Format and commit**

Run: dart format lib/app lib/features/local_recording lib/features/records lib/features/evidence test/features/local_recording test/features/records test/features/evidence

Run: git add lib/app lib/features/local_recording lib/features/records lib/features/evidence test/features/local_recording test/features/records test/features/evidence

Run: git commit -m "feat: redesign recording and records destinations"

### Task 6: Add Permission Status And Consumer Settings Recovery

**Files:**
- Create: lib/core/permissions/app_permission_gateway.dart
- Create: lib/core/permissions/permission_handler_gateway.dart
- Modify: lib/app/providers.dart
- Modify: lib/features/settings/presentation/settings_page.dart
- Modify: lib/features/device_discovery/presentation/discovery_page.dart
- Modify: lib/features/local_recording/presentation/active_recording_page.dart
- Create: test/core/permissions/permission_handler_gateway_test.dart
- Modify: test/features/settings/presentation/settings_page_test.dart
- Modify: test/features/device_discovery/presentation/discovery_page_test.dart
- Modify: test/features/local_recording/presentation/active_recording_page_test.dart
- Create: test/support/fake_app_permission_gateway.dart

- [ ] **Step 1: Write failing permission-recovery tests**

~~~dart
testWidgets('settings turns denied nearby-device access into recovery action', (
  tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SettingsPage(
        profile: DeviceProfile.empty(),
        permissions: FakeAppPermissionGateway(
          nearbyDevices: AppPermissionState.denied,
        ),
      ),
    ),
  );

  expect(find.text('需要开启'), findsOneWidget);
  await tester.tap(find.text('附近设备'));
  expect(find.text('前往系统设置'), findsOneWidget);
});
~~~

Add discovery coverage that taps 前往系统设置 and checks FakeAppPermissionGateway.openSettingsCalls. Add active-recording permission-denied coverage that sees the same recovery action.

- [ ] **Step 2: Run the failing tests**

Run: flutter test test/core/permissions test/features/settings/presentation/settings_page_test.dart test/features/device_discovery/presentation/discovery_page_test.dart test/features/local_recording/presentation/active_recording_page_test.dart

Expected: FAIL because AppPermissionGateway and recovery UI do not exist.

- [ ] **Step 3: Implement permission gateway and consumer settings**

~~~dart
enum AppPermissionState { granted, denied, permanentlyDenied, unavailable }

abstract interface class AppPermissionGateway {
  Future<AppPermissionState> nearbyDevices();
  Future<AppPermissionState> microphone();
  Future<bool> openSettings();
}
~~~

PermissionHandlerGateway maps Android bluetoothScan/bluetoothConnect, iOS bluetooth and microphone status. It does not request permission; ReactiveBleTransport and RecordAudioRecorder retain existing request timing. Register it in providers.

Replace raw GATT rows in SettingsPage with Display, Permissions and device, and About groups. Keep profile information behind connection help or advanced diagnostic entry. Tapping denied state opens PermissionRationaleSheet with 前往系统设置. Pass gateway/callbacks into DiscoveryPage and ActiveRecordingPage so existing failures gain recovery without direct permission_handler imports.

- [ ] **Step 4: Verify permission recovery**

Run: flutter test test/core/permissions test/features/settings/presentation/settings_page_test.dart test/features/device_discovery/presentation/discovery_page_test.dart test/features/local_recording/presentation/active_recording_page_test.dart

Expected: PASS.

- [ ] **Step 5: Format and commit**

Run: dart format lib/core/permissions lib/app lib/features/settings lib/features/device_discovery lib/features/local_recording test/core/permissions test/features/settings test/features/device_discovery test/features/local_recording test/support

Run: git add lib/core/permissions lib/app lib/features/settings lib/features/device_discovery lib/features/local_recording test/core/permissions test/features/settings test/features/device_discovery test/features/local_recording test/support

Run: git commit -m "feat: add consumer permission recovery"

### Task 7: Document And Verify Whole Journey

**Files:**
- Modify: README.md
- Modify: test/smoke_test.dart
- Modify: test/app/app_shell_test.dart
- Create: test/support/consumer_test_app.dart
- Modify: docs/superpowers/specs/2026-08-21-consumer-app-interaction-redesign.md only if an approved design ambiguity is discovered

- [ ] **Step 1: Update README**

Replace workbench-first startup text with first-use choice, connection, local recording, records, and explicit hardware-audio limitation. Preserve a separate advanced engineering verification section.

- [ ] **Step 2: Add consumer smoke coverage**

~~~dart
testWidgets('consumer can record locally without device connection', (tester) async {
  final recorder = FakeAudioRecorder()
    ..permission = RecorderPermission.granted;
  await tester.pumpWidget(
    buildConsumerTestApp(recorder: recorder),
  );

  await tester.tap(find.text('先用本机录音'));
  await tester.tap(find.text('录音'));
  await tester.tap(find.text('开始本机录音'));
  await tester.pump();

  expect(find.text('正在录音'), findsOneWidget);
});
~~~

Create test/support/consumer_test_app.dart in this task. Its buildConsumerTestApp helper uses ProviderScope overrides for onboardingStoreProvider, bleTransportProvider, localRecordingRepositoryProvider, audioRecorderProvider, recordingFileStoreProvider, recordingBackgroundProvider and evidenceRepositoryProvider. It receives a FakeAudioRecorder and creates the remaining existing fake collaborators so the widget test remains offline and deterministic.

Use existing fake audio recorder, file store, repositories and BLE transport plus a fake onboarding store. Do not create mock device activity that could look like hardware output.

- [ ] **Step 3: Run formatting and analysis**

Run: dart format --set-exit-if-changed lib test

Run: flutter analyze

Expected: both commands exit 0.

- [ ] **Step 4: Run all tests**

Run: flutter test

Expected: all tests pass and consumer interaction tests are not skipped.

- [ ] **Step 5: Build Android debug APK**

Run: flutter build apk --debug

Expected: exit 0 and build/app/outputs/flutter-apk/app-debug.apk exists.

- [ ] **Step 6: Perform physical-device acceptance**

On Android and iOS verify first-use paths, Bluetooth permission states, Bluetooth-off recovery, connection, disconnect/reconnect, record/pause/resume/stop, Android notification and lock screen, iOS background audio, interruption, playback, rename/delete, unavailable-file UI, narrow phone, tablet, enlarged text, light mode, dark mode and device activity from real hardware.

- [ ] **Step 7: Commit final documentation and test updates**

Run: git add README.md test docs/superpowers/specs/2026-08-21-consumer-app-interaction-redesign.md

Run: git commit -m "docs: document consumer recording experience"

## Plan Self-Review

- Spec coverage: Tasks 1-6 cover navigation, onboarding, connection, device detail, local recording, history, permission recovery, theme, motion, accessibility and hardware boundaries. Task 7 covers documentation, automated checks, Android build and physical-device acceptance.
- Boundary coverage: Hardware presentation uses DiscoveryController, SessionController and EvidenceHistoryController. The plan adds no BLE write, device-audio file or hardware recording command.
- Type consistency: AppDestination starts in Task 1 and is consumed by Task 2 shell. onboardingStoreProvider starts in Task 2 and is available to the Task 7 consumer test helper. DeviceStatusViewModel starts in Task 4 and has no widget dependency. AppPermissionGateway starts in Task 6 and reaches widgets only through providers/callbacks.
- Completeness scan: Each task lists exact files, failing test, implementation boundary, passing command and commit command.
