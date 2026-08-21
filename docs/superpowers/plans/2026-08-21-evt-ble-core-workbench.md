# EVT BLE Core Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Android/iOS Flutter EVT workbench that discovers target devices, establishes an observable BLE session, runs evidence-backed observations, and persists verdicts using the approved monochrome design system.

**Architecture:** Use feature-first layers: `presentation`, `application`, `domain`, and `data` inside discovery, session, observation, evidence, and settings features. `core` owns platform BLE transport, protocol codec, persistence, diagnostics, and the design system. Riverpod controllers expose immutable view state; UI never receives raw BLE bytes or directly reads local storage.

**Tech Stack:** Flutter 3.44.6 / Dart 3.12.2, Material 3, `flutter_riverpod`, `flutter_reactive_ble`, `drift` with `drift_flutter`, `permission_handler`, `shared_preferences`, `flutter_test`, and `integration_test`.

**Precondition:** The application can scan using the documented broadcast filter immediately. Real service discovery, subscription, reads, and command verification require the device's service UUID and read/write/notify characteristic UUIDs in `assets/config/device_profile.json`. The profile validator blocks those operations until these values are supplied.

---

## File Structure

```text
assets/config/device_profile.json                 real-device GATT configuration
lib/main.dart                                     production entry point
lib/app/evt_app.dart                              MaterialApp, provider scope, app lifecycle
lib/app/app_shell.dart                            three-destination shell and session handoff
lib/core/design_system/                           tokens, theme, reusable components
lib/core/ble/                                     transport contract, reactive adapter, profile loader
lib/core/protocol/                                frame reader, CRC16, typed protocol events
lib/core/persistence/                             Drift database and evidence repositories
lib/core/diagnostics/                             structured failures and export formatter
lib/features/device_discovery/                    broadcast filter, scan controller, scan page
lib/features/device_session/                      session state machine, controller, dashboard
lib/features/observation/                         scenario definitions, verifier, observation page
lib/features/evidence/                            local evidence history and record sheet
lib/features/settings/                            system/theme preference and device profile status
test/                                             unit and widget regression tests
integration_test/                                 Android/iOS permission and real-device journeys
```

## Task 1: Bootstrap The Flutter Workspace And Quality Baseline

**Files:**
- Create: `pubspec.yaml`
- Create: `analysis_options.yaml`
- Create: `lib/main.dart`
- Create: `test/smoke_test.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`

- [ ] **Step 1: Generate the Android/iOS Flutter project and add dependencies**

Run:

```powershell
flutter create --project-name evt_ble_app --org com.xkp --platforms=android,ios .
flutter pub add flutter_riverpod flutter_reactive_ble drift drift_flutter permission_handler shared_preferences
flutter pub add dev:build_runner dev:drift_dev
```

Expected: `pubspec.yaml`, `android/`, `ios/`, `lib/`, and `test/` exist; `flutter pub get` completes successfully.

- [ ] **Step 2: Replace the generated counter test with a failing application identity test**

```dart
// test/smoke_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:evt_ble_app/app/evt_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('renders the EVT workbench shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: EvtApp()));

    expect(find.text('设备联调'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the test and confirm the intended red state**

Run: `flutter test test/smoke_test.dart`

Expected: FAIL because `package:evt_ble_app/app/evt_app.dart` and `EvtApp` do not exist.

- [ ] **Step 4: Create the smallest compilable application shell**

```dart
// lib/main.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/evt_app.dart';

void main() => runApp(const ProviderScope(child: EvtApp()));
```

```dart
// lib/app/evt_app.dart
import 'package:flutter/material.dart';

class EvtApp extends StatelessWidget {
  const EvtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: Scaffold(body: Text('设备联调')));
  }
}
```

Add `flutter_lints` to `dev_dependencies` and configure `analysis_options.yaml` to include `package:flutter_lints/flutter.yaml`.

- [ ] **Step 5: Verify and commit the bootstrap**

Run:

```powershell
flutter test test/smoke_test.dart
flutter analyze
git add pubspec.yaml pubspec.lock analysis_options.yaml lib test android ios
git commit -m "chore: bootstrap Flutter EVT workbench"
```

Expected: the smoke test passes and analyzer reports no issues.

## Task 2: Implement Semantic Monochrome Theme Tokens And Base Components

**Files:**
- Create: `lib/core/design_system/evt_colors.dart`
- Create: `lib/core/design_system/evt_theme.dart`
- Create: `lib/core/design_system/widgets/app_button.dart`
- Create: `lib/core/design_system/widgets/status_label.dart`
- Create: `test/core/design_system/evt_theme_test.dart`
- Create: `test/core/design_system/app_button_test.dart`
- Modify: `lib/app/evt_app.dart`

- [ ] **Step 1: Write failing theme and component tests**

```dart
test('light theme uses the approved cool-white canvas', () {
  final theme = EvtTheme.light();
  expect(theme.scaffoldBackgroundColor, const Color(0xFFF7F8FA));
  expect(theme.colorScheme.primary, const Color(0xFF17191C));
});

test('dark theme uses graphite canvas rather than black', () {
  final theme = EvtTheme.dark();
  expect(theme.scaffoldBackgroundColor, const Color(0xFF121416));
  expect(theme.scaffoldBackgroundColor, isNot(const Color(0xFF000000)));
});
```

```dart
testWidgets('disabled primary button cannot invoke its command', (tester) async {
  var calls = 0;
  await tester.pumpWidget(MaterialApp(
    home: AppButton.primary(label: '连接设备', onPressed: null),
  ));
  await tester.tap(find.text('连接设备'));
  expect(calls, 0);
});
```

- [ ] **Step 2: Confirm the tests fail**

Run: `flutter test test/core/design_system`

Expected: FAIL because `EvtTheme` and `AppButton` do not exist.

- [ ] **Step 3: Implement the token-owned theme and components**

```dart
// lib/core/design_system/evt_colors.dart
abstract final class EvtLightColors {
  static const canvas = Color(0xFFF7F8FA);
  static const surface = Color(0xFFFFFFFF);
  static const subtle = Color(0xFFF0F2F5);
  static const primaryText = Color(0xFF111315);
  static const secondaryText = Color(0xFF626A73);
  static const tertiaryText = Color(0xFF9299A1);
  static const action = Color(0xFF17191C);
  static const border = Color(0xFFE3E6EA);
  static const positive = Color(0xFF117C72);
  static const danger = Color(0xFFC33E38);
}
```

Implement matching dark tokens (`#121416`, `#1B1E22`, `#25292E`, `#F3F5F7`, `#B7BEC6`, `#858D96`, `#30353B`, `#4AA99E`, `#E16B64`) and produce `ThemeData` with 8 px maximum component radii, 44 px button heights, tabular numeral typography, and Material 3 dialog/sheet colors. `AppButton` exposes `primary`, `secondary`, and `destructive` constructors with loading and disabled behavior. `StatusLabel` always takes an icon, text, and semantic kind.

- [ ] **Step 4: Apply the system themes at the root and verify green**

```dart
return MaterialApp(
  theme: EvtTheme.light(),
  darkTheme: EvtTheme.dark(),
  themeMode: ThemeMode.system,
  home: const Scaffold(body: Text('设备联调')),
);
```

Run: `flutter test test/core/design_system test/smoke_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit the design system**

```powershell
git add lib/core/design_system lib/app/evt_app.dart test/core/design_system test/smoke_test.dart
git commit -m "feat: add monochrome EVT design system"
```

## Task 3: Define Session Phases, Verdicts, And Structured Failures

**Files:**
- Create: `lib/core/diagnostics/evt_failure.dart`
- Create: `lib/features/device_session/domain/session_phase.dart`
- Create: `lib/features/observation/domain/observation_verdict.dart`
- Create: `test/features/device_session/domain/session_phase_test.dart`
- Create: `test/core/diagnostics/evt_failure_test.dart`

- [ ] **Step 1: Write failing guard tests**

```dart
test('observable requires subscription and initial snapshot', () {
  expect(
    SessionPhase.subscribing.canTransitionTo(SessionPhase.observable),
    isFalse,
  );
  expect(
    SessionPhase.initialSnapshotRead.canTransitionTo(SessionPhase.observable),
    isTrue,
  );
});

test('missing device data is unverifiable rather than passed', () {
  expect(ObservationVerdict.fromRequiredFields({}), ObservationVerdict.unverifiable);
});
```

- [ ] **Step 2: Run the focused tests**

Run: `flutter test test/features/device_session/domain/session_phase_test.dart test/core/diagnostics/evt_failure_test.dart`

Expected: FAIL because session domain types are absent.

- [ ] **Step 3: Implement the domain-only rules**

```dart
enum SessionPhase {
  environmentReady,
  discovered,
  connecting,
  servicesDiscovered,
  subscribing,
  initialSnapshotRead,
  observable,
  observing,
  verifying,
  completed,
  interrupted,
}

enum EvtFailureKind { environment, transport, access, protocol, validation }

class EvtFailure {
  const EvtFailure({
    required this.kind,
    required this.message,
    required this.recoverable,
    required this.occurredAt,
    this.detail,
  });

  final EvtFailureKind kind;
  final String message;
  final bool recoverable;
  final DateTime occurredAt;
  final String? detail;

  factory EvtFailure.protocol({required String message, String? detail}) => EvtFailure(
    kind: EvtFailureKind.protocol,
    message: message,
    recoverable: true,
    occurredAt: DateTime.now(),
    detail: detail,
  );
}

extension SessionPhaseTransitions on SessionPhase {
  bool canTransitionTo(SessionPhase next) => switch ((this, next)) {
    (SessionPhase.environmentReady, SessionPhase.discovered) => true,
    (SessionPhase.discovered, SessionPhase.connecting) => true,
    (SessionPhase.connecting, SessionPhase.servicesDiscovered) => true,
    (SessionPhase.servicesDiscovered, SessionPhase.subscribing) => true,
    (SessionPhase.subscribing, SessionPhase.initialSnapshotRead) => true,
    (SessionPhase.initialSnapshotRead, SessionPhase.observable) => true,
    (SessionPhase.observable, SessionPhase.observing) => true,
    (SessionPhase.observing, SessionPhase.verifying) => true,
    (SessionPhase.verifying, SessionPhase.completed) => true,
    (_, SessionPhase.interrupted) => true,
    _ => false,
  };
}
```

Define `EvtFailure` with `environment`, `transport`, `access`, `protocol`, and `validation` kinds plus `message`, `recoverable`, `occurredAt`, and optional diagnostic detail. Define `ObservationVerdict.passed`, `.failed`, and `.unverifiable`.

- [ ] **Step 4: Verify the domain layer**

Run: `flutter test test/features/device_session/domain test/core/diagnostics`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/core/diagnostics lib/features/device_session/domain lib/features/observation/domain test
git commit -m "feat: add session phase and verdict domain rules"
```

## Task 4: Add Device Profile Validation And Broadcast Filtering

**Files:**
- Create: `assets/config/device_profile.json`
- Create: `lib/core/ble/device_profile.dart`
- Create: `lib/core/ble/device_profile_loader.dart`
- Create: `lib/features/device_discovery/domain/device_candidate.dart`
- Create: `lib/features/device_discovery/domain/advertisement_filter.dart`
- Create: `test/core/ble/device_profile_test.dart`
- Create: `test/features/device_discovery/domain/advertisement_filter_test.dart`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Write failing profile and advertisement tests**

```dart
test('profile blocks GATT operations until all UUIDs are configured', () {
  final profile = DeviceProfile.empty();
  expect(profile.isGattReady, isFalse);
  expect(profile.validationFailure!.kind, EvtFailureKind.access);
});

test('accepts a matching documented broadcast', () {
  final candidate = DeviceCandidate(
    name: 'AIPIN_8423',
    manufacturerData: [0xA3, 0x89, 0x71, 0xBF, 0xE2, 0x3B, 0x84, 0x23],
    serviceUuids: const ['0000AF30-0000-1000-8000-00805F9B34FB'],
    rssi: -48,
    discoveredAt: DateTime(2026, 8, 21),
  );

  expect(const AdvertisementFilter().matches(candidate), isTrue);
});
```

- [ ] **Step 2: Run tests and confirm red**

Run: `flutter test test/core/ble/device_profile_test.dart test/features/device_discovery/domain/advertisement_filter_test.dart`

Expected: FAIL because profile and filter implementations are missing.

- [ ] **Step 3: Implement a typed, asset-backed profile and pure filter**

Use this asset schema:

```json
{
  "namePrefix": "AIPIN",
  "manufacturerPrefixHex": "A389",
  "serviceUuid": "0000AF30-0000-1000-8000-00805F9B34FB",
  "gattServiceUuid": "",
  "readCharacteristicUuid": "",
  "notifyCharacteristicUuid": "",
  "writeCharacteristicUuid": ""
}
```

`DeviceProfile.isGattReady` returns true only when all required GATT strings parse as UUIDs. `AdvertisementFilter.matches` requires manufacturer prefix, name prefix, and service UUID, then returns a reason list used by the UI.

- [ ] **Step 4: Verify and register the asset**

Run:

```powershell
flutter test test/core/ble/device_profile_test.dart test/features/device_discovery/domain/advertisement_filter_test.dart
flutter pub get
```

Expected: PASS and the asset is included by the `flutter/assets` section in `pubspec.yaml`.

- [ ] **Step 5: Commit**

```powershell
git add assets/config lib/core/ble lib/features/device_discovery/domain pubspec.yaml test
git commit -m "feat: add validated BLE device profile and discovery filter"
```

## Task 5: Parse And Validate EVT Protocol Frames

**Files:**
- Create: `lib/core/protocol/crc16.dart`
- Create: `lib/core/protocol/evt_frame.dart`
- Create: `lib/core/protocol/evt_protocol_codec.dart`
- Create: `lib/core/protocol/device_event.dart`
- Create: `test/core/protocol/evt_protocol_codec_test.dart`

- [ ] **Step 1: Write failing codec tests for valid, invalid, and unknown frames**

```dart
test('decodes a complete 0xED frame after CRC validation', () {
  final bytes = <int>[0xED, 0x02, 0x11, 0x52, 0x00, 0x00];
  final result = EvtProtocolCodec().decode(bytes);
  expect(result.isSuccess, isTrue);
  expect(result.value!.command, 0x11);
});

test('rejects a frame whose declared length differs from content', () {
  final result = EvtProtocolCodec().decode(<int>[0xED, 0x04, 0x11, 0x52, 0x00, 0x00]);
  expect(result.failure!.kind, EvtFailureKind.protocol);
});
```

- [ ] **Step 2: Execute the red tests**

Run: `flutter test test/core/protocol/evt_protocol_codec_test.dart`

Expected: FAIL because the codec is absent.

- [ ] **Step 3: Implement only validated frame publication**

```dart
class EvtFrame {
  const EvtFrame({required this.command, required this.content});
  final int command;
  final Uint8List content;
}

enum DeviceEventKind { recordingStarted, silenceEnded, batteryChanged, statusChanged, unknown }

class DeviceEvent {
  const DeviceEvent({
    required this.kind,
    required this.occurredAt,
    required this.source,
  });

  final DeviceEventKind kind;
  final DateTime occurredAt;
  final String source;
}

sealed class ProtocolDecodeResult {
  const ProtocolDecodeResult();
  const factory ProtocolDecodeResult.success(EvtFrame frame) = ProtocolDecodeSuccess;
  const factory ProtocolDecodeResult.failure(EvtFailure failure) = ProtocolDecodeFailure;
}
```

`EvtProtocolCodec.decode` verifies leading `0xED`, declared length, and CRC16 before returning `EvtFrame`. Define `DeviceEventKind` and immutable `DeviceEvent` in `device_event.dart`; map known commands `0x01`, `0x05`, `0x06`, `0x07`, `0x08`, `0x09`, `0x11`, `0x21`, `0x22`, and `0x23` into those typed events. Preserve unknown command payloads as diagnostics rather than discarding them.

- [ ] **Step 4: Verify codec behavior**

Run: `flutter test test/core/protocol/evt_protocol_codec_test.dart`

Expected: PASS for valid frame, invalid length, invalid CRC, and unknown command cases.

- [ ] **Step 5: Commit**

```powershell
git add lib/core/protocol test/core/protocol
git commit -m "feat: add validated EVT protocol codec"
```

## Task 6: Introduce The BLE Transport Contract And Reactive Adapter

**Files:**
- Create: `lib/core/ble/ble_transport.dart`
- Create: `lib/core/ble/reactive_ble_transport.dart`
- Create: `lib/core/ble/ble_models.dart`
- Create: `test/support/fake_ble_transport.dart`
- Create: `test/core/ble/ble_transport_contract_test.dart`

- [ ] **Step 1: Write a failing contract test with an in-memory transport**

```dart
test('transport exposes scan candidates and controlled disconnect', () async {
  final transport = FakeBleTransport();
  final candidates = <DeviceCandidate>[];
  final subscription = transport.scan().listen(candidates.add);

  transport.emitCandidate(FakeBleTransport.matchingCandidate);
  await Future<void>.delayed(Duration.zero);

  expect(candidates, [FakeBleTransport.matchingCandidate]);
  await subscription.cancel();
});
```

- [ ] **Step 2: Run the red contract test**

Run: `flutter test test/core/ble/ble_transport_contract_test.dart`

Expected: FAIL because the transport interface and fake are missing.

- [ ] **Step 3: Define the interface and the only plugin-facing adapter**

```dart
abstract interface class BleTransport {
  Stream<DeviceCandidate> scan();
  Stream<BleConnectionState> connect(String deviceId);
  Future<List<BleService>> discoverServices(String deviceId);
  Stream<Uint8List> subscribe(BleCharacteristic characteristic);
  Future<Uint8List> read(BleCharacteristic characteristic);
  Future<void> disconnect(String deviceId);
}
```

`ReactiveBleTransport` is the sole owner of `FlutterReactiveBle`. It converts plugin-specific data into `ble_models.dart` types and maps plugin failures to `EvtFailure`. It does not parse protocol bytes or calculate UI state.

- [ ] **Step 4: Verify the fake contract and analyzer**

Run:

```powershell
flutter test test/core/ble/ble_transport_contract_test.dart
flutter analyze
```

Expected: PASS with no direct `FlutterReactiveBle` references outside `lib/core/ble/reactive_ble_transport.dart`.

- [ ] **Step 5: Commit**

```powershell
git add lib/core/ble test/support test/core/ble
git commit -m "feat: isolate real BLE transport adapter"
```

## Task 7: Build Discovery Controller And Scan Workbench

**Files:**
- Create: `lib/features/device_discovery/application/discovery_state.dart`
- Create: `lib/features/device_discovery/application/discovery_controller.dart`
- Create: `lib/features/device_discovery/presentation/discovery_page.dart`
- Create: `lib/features/device_discovery/presentation/device_candidate_row.dart`
- Create: `test/features/device_discovery/application/discovery_controller_test.dart`
- Create: `test/features/device_discovery/presentation/discovery_page_test.dart`

- [ ] **Step 1: Write failing discovery behavior tests**

```dart
test('only matching candidates become selectable and sort by strongest RSSI', () async {
  final transport = FakeBleTransport();
  final controller = DiscoveryController(transport, const AdvertisementFilter());
  controller.start();
  transport.emitCandidate(FakeBleTransport.weakMatchingCandidate);
  transport.emitCandidate(FakeBleTransport.matchingCandidate);

  await Future<void>.delayed(Duration.zero);

  expect(controller.state.candidates.first.name, 'AIPIN_8423');
  expect(controller.state.connectEnabled, isFalse);
});
```

```dart
testWidgets('connection command stays disabled until a device is selected', (tester) async {
  await tester.pumpWidget(const DiscoveryPage());
  expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
});
```

- [ ] **Step 2: Run the focused red tests**

Run: `flutter test test/features/device_discovery`

Expected: FAIL because the controller and page are absent.

- [ ] **Step 3: Implement immutable scan state and a compact candidate table**

```dart
class DiscoveryState {
  const DiscoveryState({
    this.isScanning = false,
    this.candidates = const [],
    this.selected,
    this.failure,
  });

  final bool isScanning;
  final List<DeviceCandidate> candidates;
  final DeviceCandidate? selected;
  final EvtFailure? failure;
  bool get connectEnabled => selected != null && failure == null;
}
```

The page shows summary count, scanning progress, stable name/RSSI/address columns, match reason, neutral skeleton while waiting, remediation for unavailable scanning, and an enabled connection command only after selection. Dispose scan subscriptions through the controller lifecycle.

- [ ] **Step 4: Verify discovery behavior**

Run: `flutter test test/features/device_discovery`

Expected: PASS for filtering, sorting, selection gate, scanner failure, and enlarged-text widget layout.

- [ ] **Step 5: Commit**

```powershell
git add lib/features/device_discovery test/features/device_discovery
git commit -m "feat: add filtered BLE discovery workbench"
```

## Task 8: Build Gated Device Session Controller And Dashboard

**Files:**
- Create: `lib/features/device_session/domain/device_session.dart`
- Create: `lib/features/device_session/domain/device_snapshot.dart`
- Create: `lib/features/device_session/application/session_state.dart`
- Create: `lib/features/device_session/application/session_controller.dart`
- Create: `lib/features/device_session/presentation/session_dashboard_page.dart`
- Create: `lib/features/device_session/presentation/phase_indicator.dart`
- Create: `lib/features/device_session/presentation/snapshot_table.dart`
- Create: `test/features/device_session/application/session_controller_test.dart`
- Create: `test/features/device_session/presentation/session_dashboard_page_test.dart`
- Create: `test/support/device_fixtures.dart`

- [ ] **Step 1: Write failing observable-state and blocked-profile tests**

```dart
test('does not become observable until subscribe and initial read both succeed', () async {
  final transport = FakeBleTransport.withGattReadyProfile();
  final controller = SessionController(transport, transport.profile, EvtProtocolCodec());

  await controller.connect(FakeBleTransport.matchingCandidate);
  transport.emitSubscriptionBytes(FakeBleTransport.validBatteryFrame);

  expect(controller.state.phase, isNot(SessionPhase.observable));
  await controller.completeInitialRead(FakeBleTransport.validStatusFrame);
  expect(controller.state.phase, SessionPhase.observable);
});

test('missing UUID profile reports access block instead of attempting a read', () async {
  final controller = SessionController(FakeBleTransport(), DeviceProfile.empty(), EvtProtocolCodec());
  await controller.connect(FakeBleTransport.matchingCandidate);
  expect(controller.state.failure!.kind, EvtFailureKind.access);
});
```

- [ ] **Step 2: Run the red session tests**

Run: `flutter test test/features/device_session/application/session_controller_test.dart`

Expected: FAIL because session controller state is missing.

- [ ] **Step 3: Implement the only legal session progression**

`SessionController.connect` performs, in order: connect stream success, configured-service discovery, notification subscription, and initial read. It validates every transport result, transitions via `SessionPhase.canTransitionTo`, creates typed `DeviceSnapshot` values from codec events, and stores each phase/event timestamp. It transitions to `interrupted` for transport failure and preserves already-received snapshots as read-only evidence.

```dart
enum DeviceState { standby, recording, charging, unknown }

class DeviceSnapshot {
  const DeviceSnapshot({
    required this.state,
    required this.observedAt,
    required this.source,
    this.batteryPercent,
    this.standbyPowerMilliwatts,
  });

  final DeviceState state;
  final DateTime observedAt;
  final String source;
  final int? batteryPercent;
  final double? standbyPowerMilliwatts;
}
```

Create this shared test fixture so subsequent test snippets have concrete helpers:

```dart
// test/support/device_fixtures.dart
DeviceSnapshot snapshot({
  DeviceState state = DeviceState.standby,
  DateTime? observedAt,
  String source = 'test',
}) => DeviceSnapshot(
  state: state,
  observedAt: observedAt ?? DateTime(2026, 8, 21),
  source: source,
);

DeviceEvent event(DeviceEventKind kind) => DeviceEvent(
  kind: kind,
  occurredAt: DateTime(2026, 8, 21),
  source: 'test',
);
```

Implement dashboard view states with these facts:

```dart
class SessionState {
  const SessionState({
    required this.phase,
    this.session,
    this.latestSnapshot,
    this.events = const [],
    this.failure,
  });
  final SessionPhase phase;
  final DeviceSession? session;
  final DeviceSnapshot? latestSnapshot;
  final List<DeviceEvent> events;
  final EvtFailure? failure;
  bool get isObservable => phase == SessionPhase.observable;
}
```

The dashboard labels a snapshot with source and received time, shows unavailable values as `不可验证`, and enables `开始观察` only for `isObservable`.

- [ ] **Step 4: Verify controller and widget behavior**

Run: `flutter test test/features/device_session`

Expected: PASS for phase order, rejected initial read, interrupted session, missing profile, state labels, and disabled observation command.

- [ ] **Step 5: Commit**

```powershell
git add lib/features/device_session test/features/device_session
git commit -m "feat: add gated observable device session"
```

## Task 9: Assemble The Workbench Shell And Explicit Theme Preference

**Files:**
- Create: `lib/app/app_shell.dart`
- Create: `lib/features/settings/application/theme_mode_controller.dart`
- Create: `lib/features/settings/presentation/settings_page.dart`
- Create: `test/support/fake_theme_mode_store.dart`
- Create: `test/app/app_shell_test.dart`
- Create: `test/features/settings/application/theme_mode_controller_test.dart`
- Modify: `lib/app/evt_app.dart`

- [ ] **Step 1: Write failing navigation and preference tests**

```dart
testWidgets('selected discovery candidate opens its session without losing shell navigation', (tester) async {
  await tester.pumpWidget(const ProviderScope(child: EvtApp()));
  await tester.tap(find.text('AIPIN_8423'));
  await tester.tap(find.text('连接设备'));
  expect(find.text('设备快照'), findsOneWidget);
});

test('theme defaults to system until an explicit override is saved', () async {
  final controller = ThemeModeController(FakeThemeModeStore());
  expect(await controller.load(), ThemeMode.system);
  await controller.set(ThemeMode.dark);
  expect(await controller.load(), ThemeMode.dark);
});
```

- [ ] **Step 2: Run tests and confirm red**

Run: `flutter test test/app/app_shell_test.dart test/features/settings/application/theme_mode_controller_test.dart`

Expected: FAIL because shell and preference controller are absent.

- [ ] **Step 3: Implement shell boundaries and theme persistence**

The shell owns three destinations: `联调`, central `记录`, and `证据`. The central record control is visibly disabled until an active observable session exists; its bottom-sheet action is connected when the evidence feature is introduced in Task 12. Use a simple `Navigator` route handoff from discovery to session; do not introduce a routing package for this single-stack flow. Persist only explicit `ThemeMode.light` or `.dark` selections; `ThemeMode.system` remains the default.

```dart
abstract interface class ThemeModeStore {
  Future<ThemeMode?> read();
  Future<void> write(ThemeMode mode);
}

// test/support/fake_theme_mode_store.dart
class FakeThemeModeStore implements ThemeModeStore {
  ThemeMode? value;

  @override
  Future<ThemeMode?> read() async => value;

  @override
  Future<void> write(ThemeMode mode) async => value = mode;
}
```

- [ ] **Step 4: Verify navigation and dark/light rendering**

Run: `flutter test test/app test/features/settings`

Expected: PASS, including app shell rendering under both `Brightness.light` and `Brightness.dark` test environments.

- [ ] **Step 5: Commit**

```powershell
git add lib/app lib/features/settings test/app test/features/settings
git commit -m "feat: assemble workbench shell and theme preference"
```

## Task 10: Model Observation Scenarios And Verification Rules

**Files:**
- Create: `lib/features/observation/domain/observation_scenario.dart`
- Create: `lib/features/observation/domain/observation_run.dart`
- Create: `lib/features/observation/domain/observation_verifier.dart`
- Create: `lib/features/observation/application/observation_controller.dart`
- Create: `lib/features/observation/presentation/observation_page.dart`
- Create: `test/features/observation/domain/observation_verifier_test.dart`
- Create: `test/features/observation/application/observation_controller_test.dart`

- [ ] **Step 1: Write failing scenario verification tests**

```dart
test('VAD scenario passes only when final snapshot returns to standby', () {
  final run = ObservationRun.vad(
    initial: snapshot(state: DeviceState.standby),
    events: [event(DeviceEventKind.recordingStarted), event(DeviceEventKind.silenceEnded)],
    finalSnapshot: snapshot(state: DeviceState.standby),
  );
  expect(ObservationVerifier().verify(run), ObservationVerdict.passed);
});

test('missing standby power fields are unverifiable', () {
  final run = ObservationRun.standbyPower(initial: snapshot(), finalSnapshot: snapshot());
  expect(ObservationVerifier().verify(run), ObservationVerdict.unverifiable);
});
```

- [ ] **Step 2: Run the red tests**

Run: `flutter test test/features/observation`

Expected: FAIL because scenario and verifier types are absent.

- [ ] **Step 3: Implement reusable scenario definitions**

Define the six scenarios `deviceAccess`, `vadRecording`, `batteryAndCharging`, `standbyPower`, `recovery`, and `physicalFeedback`. Each definition declares required snapshot fields, expected event sequence, and required manual note policy. `ObservationVerifier` returns a `VerificationResult` with verdict, reason, expected evidence, and missing fields. It returns `unverifiable` for every absent required field, rejected access response, or invalid protocol event.

- [ ] **Step 4: Verify tests and scenario presentation**

Run: `flutter test test/features/observation`

Expected: PASS for VAD success/failure, battery changes, recovery new-session comparison, physical-feedback note requirement, and missing data handling.

- [ ] **Step 5: Commit**

```powershell
git add lib/features/observation test/features/observation
git commit -m "feat: add evidence-backed observation scenarios"
```

## Task 11: Persist Evidence Locally With Drift

**Files:**
- Create: `lib/core/persistence/app_database.dart`
- Create: `lib/core/persistence/tables/evidence_bundles.dart`
- Create: `lib/core/persistence/tables/session_events.dart`
- Create: `lib/features/evidence/domain/evidence_bundle.dart`
- Create: `lib/features/evidence/data/drift_evidence_repository.dart`
- Create: `lib/features/evidence/domain/evidence_repository.dart`
- Create: `test/features/evidence/data/drift_evidence_repository_test.dart`
- Generate: `lib/core/persistence/app_database.g.dart`

- [ ] **Step 1: Write a failing in-memory repository test**

```dart
test('persists an immutable verdict with device identity and source snapshots', () async {
  final database = AppDatabase.forTesting();
  final repository = DriftEvidenceRepository(database);
  final bundle = EvidenceBundle.completed(
    deviceName: 'AIPIN_8423',
    firmwareVersion: 'V1.5',
    verdict: ObservationVerdict.unverifiable,
    reason: '待机功耗字段未上报',
    snapshots: [snapshot()],
  );

  await repository.save(bundle);

  final saved = await repository.byId(bundle.id);
  expect(saved!.reason, '待机功耗字段未上报');
  expect(saved.snapshots.single.source, isNotEmpty);
});
```

- [ ] **Step 2: Run the red repository test**

Run: `flutter test test/features/evidence/data/drift_evidence_repository_test.dart`

Expected: FAIL because the database and repository do not exist.

- [ ] **Step 3: Implement tables, repository, and generated database code**

Store bundle id, session id, device identity, firmware version, timestamps, verdict, reason, and JSON diagnostic payload in `EvidenceBundles`. Store ordered event/source records in `SessionEvents`. `EvidenceRepository.save` rejects bundles that contain `isMock == true` or have no device identity. Add `AppDatabase.forTesting()` using an in-memory executor.

Run: `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 4: Verify persistence and generation**

Run:

```powershell
dart run build_runner build --delete-conflicting-outputs
flutter test test/features/evidence/data/drift_evidence_repository_test.dart
```

Expected: generated source is current and repository tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/core/persistence lib/features/evidence test/features/evidence
git commit -m "feat: persist immutable local evidence bundles"
```

## Task 12: Add Inline Observation Recording And Evidence History

**Files:**
- Create: `lib/features/evidence/application/evidence_history_controller.dart`
- Create: `lib/features/evidence/presentation/record_observation_sheet.dart`
- Create: `lib/features/evidence/presentation/evidence_history_page.dart`
- Modify: `lib/app/app_shell.dart`
- Create: `test/features/evidence/presentation/record_observation_sheet_test.dart`
- Create: `test/features/evidence/presentation/evidence_history_page_test.dart`

- [ ] **Step 1: Write failing recording-sheet tests**

```dart
testWidgets('record sheet saves a valid physical observation without leaving the session', (tester) async {
  await tester.pumpWidget(const SessionDashboardPage());
  await tester.tap(find.byTooltip('记录观察'));
  await tester.enterText(find.byType(TextField), 'LED 与状态上报时间一致');
  await tester.tap(find.text('保存'));

  expect(find.text('设备快照'), findsOneWidget);
  expect(find.text('已保存'), findsOneWidget);
});
```

- [ ] **Step 2: Run the red widget tests**

Run: `flutter test test/features/evidence/presentation`

Expected: FAIL because the sheet and evidence history page are absent.

- [ ] **Step 3: Implement the half-height record sheet and history table**

`RecordObservationSheet` opens with input plus `LED`, `按键`, and `异常` tags. Its save action becomes enabled only for non-empty text, persists through `EvidenceRepository`, and displays inline `已保存` state rather than a toast. The history page uses a stable left name/right verdict layout and exposes detail, export-ready diagnostics, and destructive delete confirmation through `AppDialog`. Update `AppShell` so the central record action becomes enabled only when the active `SessionState.isObservable` is true, calls `showModalBottomSheet` with `RecordObservationSheet`, and keeps the existing session dashboard visible behind the sheet.

- [ ] **Step 4: Verify sheet and history behavior**

Run: `flutter test test/features/evidence/presentation`

Expected: PASS for disabled save, successful autosave indication, retained dashboard context, history rendering, and explicit destructive confirmation.

- [ ] **Step 5: Commit**

```powershell
git add lib/app/app_shell.dart lib/features/evidence test/features/evidence
git commit -m "feat: add inline observation recording and evidence history"
```

## Task 13: Surface Structured Diagnostics And Recovery Guidance

**Files:**
- Create: `lib/core/diagnostics/diagnostic_exporter.dart`
- Create: `lib/core/design_system/widgets/error_state.dart`
- Create: `lib/features/device_session/presentation/session_failure_panel.dart`
- Create: `test/core/diagnostics/diagnostic_exporter_test.dart`
- Create: `test/features/device_session/presentation/session_failure_panel_test.dart`

- [ ] **Step 1: Write failing diagnostic tests**

```dart
test('exporter includes failure kind, source, and last valid snapshot time', () {
  final output = DiagnosticExporter().format(
    failure: EvtFailure.protocol(message: 'CRC 校验失败'),
    lastSnapshot: snapshot(observedAt: DateTime(2026, 8, 21, 10, 32)),
  );
  expect(output, contains('protocol'));
  expect(output, contains('2026-08-21T10:32:00.000'));
});
```

- [ ] **Step 2: Run the red tests**

Run: `flutter test test/core/diagnostics/diagnostic_exporter_test.dart test/features/device_session/presentation/session_failure_panel_test.dart`

Expected: FAIL because exporter and failure panel are missing.

- [ ] **Step 3: Implement explicit error presentation**

Map environment failures to Bluetooth/permission remediation, transport failures to retry or reconnect, access failures to `状态暂不可读取`, and protocol/missing-field failures to `不可验证`. The panel always retains the last successful snapshot timestamp when available and never assigns a positive verdict to an error state.

- [ ] **Step 4: Verify structured failure UI**

Run: `flutter test test/core/diagnostics test/features/device_session/presentation/session_failure_panel_test.dart`

Expected: PASS for labeled status, retry affordance, last-updated time, and no color-only error meaning.

- [ ] **Step 5: Commit**

```powershell
git add lib/core/diagnostics lib/core/design_system/widgets lib/features/device_session/presentation test
git commit -m "feat: add recoverable diagnostics and failure panels"
```

## Task 14: Configure Android And iOS BLE Permissions And Device Profile Status

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/build.gradle.kts` or `android/app/build.gradle`
- Modify: `ios/Runner/Info.plist`
- Modify: `lib/features/settings/presentation/settings_page.dart`
- Create: `integration_test/permission_and_profile_test.dart`
- Create: `test/features/settings/presentation/settings_page_test.dart`

- [ ] **Step 1: Write failing profile-status and permission-gate tests**

```dart
testWidgets('settings identifies an incomplete GATT profile', (tester) async {
  await tester.pumpWidget(SettingsPage(profile: DeviceProfile.empty()));
  expect(find.text('GATT 配置未完成'), findsOneWidget);
  expect(find.text('扫描规则可用，连接验证已阻止'), findsOneWidget);
});
```

- [ ] **Step 2: Run the red settings test**

Run: `flutter test test/features/settings/presentation/settings_page_test.dart`

Expected: FAIL because profile status presentation is absent.

- [ ] **Step 3: Add required platform declarations and profile visibility**

Android declares `android.permission.BLUETOOTH_SCAN` and `android.permission.BLUETOOTH_CONNECT`, with legacy location declaration only for Android versions that require it. iOS declares `NSBluetoothAlwaysUsageDescription` with an internal-testing explanation. Do not add background Bluetooth modes. Settings shows loaded profile identity, GATT readiness, and an exact incomplete-profile block message.

- [ ] **Step 4: Verify static and widget checks**

Run:

```powershell
flutter test test/features/settings/presentation/settings_page_test.dart
flutter analyze
```

Expected: PASS with analyzer clean. On a physical Android device, first launch shows the platform Bluetooth permission request before scan begins.

- [ ] **Step 5: Commit**

```powershell
git add android ios lib/features/settings integration_test test/features/settings
git commit -m "feat: configure BLE permissions and profile status"
```

## Task 15: Add Android/iOS Integration Journeys And Final Verification

**Files:**
- Create: `integration_test/real_session_journey_test.dart`
- Create: `integration_test/reconnect_evidence_journey_test.dart`
- Modify: `README.md`

- [ ] **Step 1: Write integration journeys before device execution**

```dart
testWidgets('real session reaches observable only after subscription and initial read', (tester) async {
  await tester.pumpWidget(const EvtApp());
  await tester.tap(find.text('开始扫描'));
  await tester.tap(find.text('AIPIN_8423'));
  await tester.tap(find.text('连接设备'));

  await tester.pumpAndSettle();
  expect(find.text('状态可观察'), findsOneWidget);
  expect(find.text('开始观察'), findsOneWidget);
});
```

The integration runner reads the real device profile asset and skips with a clear profile-readiness failure when required UUIDs are blank. It must not replace the device with a mock in this journey.

- [ ] **Step 2: Run unit/widget suite before device verification**

Run: `flutter test`

Expected: PASS before installing to a physical device.

- [ ] **Step 3: Execute Android real-device journey with configured UUIDs**

Run:

```powershell
flutter devices
flutter test integration_test/permission_and_profile_test.dart -d <android-device-id>
flutter test integration_test/real_session_journey_test.dart -d <android-device-id>
flutter test integration_test/reconnect_evidence_journey_test.dart -d <android-device-id>
```

Expected: scanner permission, candidate filtering, observable state gate, controlled reconnect, and persisted evidence all pass against the target pendant.

- [ ] **Step 4: Execute the corresponding iOS journey on macOS**

Run:

```bash
flutter test integration_test/permission_and_profile_test.dart -d <ios-device-id>
flutter test integration_test/real_session_journey_test.dart -d <ios-device-id>
flutter test integration_test/reconnect_evidence_journey_test.dart -d <ios-device-id>
flutter build ios --debug --no-codesign
```

Expected: the same state labels, phase gates, and evidence behavior as Android. The iOS build command must run on macOS.

- [ ] **Step 5: Run final static/build checks, update runbook, and commit**

Run:

```powershell
dart format --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter build apk --debug
git add README.md lib test integration_test android ios assets pubspec.yaml pubspec.lock
git commit -m "test: verify EVT BLE workbench journeys"
```

Document in `README.md`: profile configuration, Android/iOS permission behavior, device-run commands, evidence export location, and the rule that missing fields are unverifiable.

Expected: formatter produces no changes, analyzer has no issues, tests pass, and a debug Android APK is generated.

## Plan Self-Review

### Spec Coverage

- Discovery, connection, auto-reconnect, no-binding state reads, protocol parsing, evidence, diagnostics, and final verdicts are covered by Tasks 4-15.
- VAD, battery/charging, standby power, recovery, LED, and recovery key are represented by required scenario definitions and verifier tests in Task 10.
- The selected light/dark monochrome theme, typography, component contract, motion, and accessibility constraints are handled by Task 2 and verified in Tasks 7-9.
- Android/iOS permission behavior and real-device journeys are covered by Tasks 14-15.
- UUID ambiguity is handled as a concrete device profile readiness gate in Tasks 4, 8, 14, and 15.

### Uncovered-Work Check

No implementation step defers behavior to an unspecified future task. Physical device commands use the supplied UUID values through the profile and are deliberately blocked by code until the profile validates.

### Type Consistency

`DeviceCandidate`, `DeviceProfile`, `BleTransport`, `SessionPhase`, `DeviceSnapshot`, `ObservationRun`, `ObservationVerdict`, `EvtFailure`, and `EvidenceBundle` are introduced before their consuming tasks and retain the same names throughout the plan.
