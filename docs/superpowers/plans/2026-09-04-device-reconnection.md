# Remembered Device Reconnection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remember successful device connections privately, reconnect when an active foreground scan sees a remembered device, and provide bounded automatic and manual retry behavior.

**Architecture:** A private SharedPreferences repository owns validated remembered-device records. A `DeviceReconnectController` matches scan candidates and owns retry state, while AppShell remains responsible for constructing the existing `SessionController` and connecting it. The controller never accesses raw BLE transport objects, so no duplicate GATT connection stream can be created.

**Tech Stack:** Flutter, Dart, Riverpod, SharedPreferences, flutter_test.

**Spec:** `docs/superpowers/specs/2026-09-04-device-reconnection-design.md`

## Global Constraints

- Preserve `SessionController` as the only owner of GATT service discovery, subscriptions, and disconnect cleanup.
- Store a real `connectionId` and optional V1.5 broadcast MAC only in private App preferences; never write either to diagnostic logs, public Downloads logs, exports, UI error messages, or preference key names.
- Android may use a MAC connection ID; iOS must use its CoreBluetooth UUID without claiming that UUID is a MAC address.
- Persist a record only after `SessionPhase.authenticationReady`; retain it after user disconnect; remove it after successful device clear/unbind.
- Auto-reconnection occurs only while the App is foreground and an active foreground scan sees a matching candidate.
- A reconnect cycle allows three total connection attempts with 1-second then 2-second retry delays. It cannot duplicate an in-flight attempt or restart after user disconnect.
- Keep all user-facing copy in Chinese and preserve current manual scan/connect behavior.
- Reconnect diagnostics use safe event/phase/attempt fields only, with no raw device ID, MAC, name, exception text, packet, or URL.

---

### Task 1: Add Private Remembered-Device Storage

**Files:**
- Create: `lib/features/device_session/domain/remembered_device.dart`
- Create: `lib/features/device_session/domain/device_connection_history_repository.dart`
- Create: `lib/features/device_session/data/shared_preferences_device_connection_history_repository.dart`
- Modify: `lib/app/providers.dart`
- Create: `test/features/device_session/domain/remembered_device_test.dart`
- Create: `test/features/device_session/data/shared_preferences_device_connection_history_repository_test.dart`

**Interfaces:**
- Produces immutable `RememberedDevice({required String connectionId, String? physicalMacAddress, required String displayName, required DateTime lastConnectedAt})` with `bool matches(DeviceCandidate candidate)`.
- Produces `DeviceConnectionHistoryRepository.load()`, `upsert(RememberedDevice record)`, and `removeMatching({required String connectionId, String? physicalMacAddress})`.
- Uses one private JSON value under the fixed key `device.connection_history.v1`; no physical identifier is interpolated into a preference key.

- [ ] **Step 1: Write failing domain tests.**

```dart
test('matches the V1.5 physical MAC before the platform connection id', () {
  final record = RememberedDevice(
    connectionId: 'ios-transport-uuid',
    physicalMacAddress: 'AA:BB:CC:DD:EE:FF',
    displayName: 'AIPIN',
    lastConnectedAt: DateTime.utc(2026, 9, 4),
  );
  final candidate = candidateFor(
    connectionId: 'different-ios-uuid',
    manufacturerData: const [0xA3, 0x89, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF],
  );

  expect(record.matches(candidate), isTrue);
});

test('rejects invalid physical MAC storage values', () {
  expect(
    () => RememberedDevice(
      connectionId: 'transport',
      physicalMacAddress: 'raw-device-id',
      displayName: 'AIPIN',
      lastConnectedAt: DateTime.utc(2026),
    ),
    throwsFormatException,
  );
});
```

- [ ] **Step 2: Run the domain test to verify RED.**

Run: `flutter test test/features/device_session/domain/remembered_device_test.dart`

Expected: FAIL because the remembered-device type does not exist.

- [ ] **Step 3: Implement the immutable model and repository contract.**

```dart
abstract interface class DeviceConnectionHistoryRepository {
  Future<List<RememberedDevice>> load();
  Future<void> upsert(RememberedDevice record);
  Future<void> removeMatching({
    required String connectionId,
    String? physicalMacAddress,
  });
}
```

`RememberedDevice.matches` must compare valid MAC addresses first when both
are available, otherwise compare the exact platform `connectionId`. Normalize
MAC values to upper-case colon-separated bytes. Limit display names to a
safe non-empty value and timestamp values to UTC.

- [ ] **Step 4: Write failing SharedPreferences repository tests.**

```dart
test('upsert replaces a matching device and retains at most five records',
    () async {
  await repository.upsert(record('transport-1', minute: 1));
  await repository.upsert(record('transport-1', minute: 2));
  for (var index = 2; index <= 6; index++) {
    await repository.upsert(record('transport-$index', minute: index));
  }

  final records = await repository.load();
  expect(records, hasLength(5));
  expect(records.first.connectionId, 'transport-6');
  expect(records.any((item) => item.connectionId == 'transport-1'), isFalse);
});

test('drops malformed serialized rows instead of throwing', () async {
  await preferences.setString('device.connection_history.v1', '[{"connectionId":1}]');

  expect(await repository.load(), isEmpty);
});
```

- [ ] **Step 5: Run the storage tests to verify RED.**

Run: `flutter test test/features/device_session/data/shared_preferences_device_connection_history_repository_test.dart`

Expected: FAIL because the repository does not exist.

- [ ] **Step 6: Implement the private bounded store and provider.**

Use `SharedPreferences.getInstance()` and a JSON list at
`device.connection_history.v1`. Decode each row defensively, remove invalid
rows, deduplicate with physical MAC first then connection ID, sort descending
by `lastConnectedAt`, and retain five. Register
`deviceConnectionHistoryRepositoryProvider` in `lib/app/providers.dart`.

- [ ] **Step 7: Run focused tests and commit.**

Run: `flutter test test/features/device_session/domain/remembered_device_test.dart test/features/device_session/data/shared_preferences_device_connection_history_repository_test.dart`

Expected: PASS.

Commit:

```text
feat: persist remembered device connections
```

### Task 2: Add Bounded Reconnection Coordination

**Files:**
- Create: `lib/features/device_session/application/device_reconnect_state.dart`
- Create: `lib/features/device_session/application/device_reconnect_controller.dart`
- Create: `test/features/device_session/application/device_reconnect_controller_test.dart`

**Interfaces:**
- Consumes `DeviceConnectionHistoryRepository`, a `Future<void> Function()` scan starter, a `Future<void> Function()` scan stopper, a `Future<bool> Function(DeviceCandidate)` session connector, and `SafeAppLogger`.
- Produces `DeviceReconnectState` with `phase`, `attempt`, `rememberedDevice`, `canRetry`, and safe failure category fields.
- Exposes `restoreAndStart()`, `startExplicitCycle()`, `considerCandidate(DeviceCandidate)`, `markUnexpectedDisconnect()`, `suppressForForeground()`, `rememberSuccessfulConnection(DeviceCandidate)`, and `forgetSuccessfulClear(DeviceCandidate)`.

- [ ] **Step 1: Write failing reconnect-controller tests.**

```dart
test('connects one matching candidate once during one scan cycle', () async {
  await controller.restoreAndStart();
  await controller.considerCandidate(rememberedCandidate);
  await controller.considerCandidate(rememberedCandidate);

  expect(connectCalls, 1);
  expect(stopScanCalls, 1);
});

test('retries a failed reconnect at one and two seconds then exhausts',
    () async {
  connectorResults.addAll([false, false, false]);
  await controller.startExplicitCycle();
  await controller.considerCandidate(rememberedCandidate);
  await advanceRetryDelay(const Duration(seconds: 1));
  await controller.considerCandidate(rememberedCandidate);
  await advanceRetryDelay(const Duration(seconds: 2));
  await controller.considerCandidate(rememberedCandidate);

  expect(controller.state.phase, DeviceReconnectPhase.exhausted);
  expect(controller.state.attempt, 3);
});

test('manual suppression prevents a later candidate from reconnecting',
    () async {
  await controller.restoreAndStart();
  controller.suppressForForeground();
  await controller.considerCandidate(rememberedCandidate);

  expect(connectCalls, 0);
});
```

- [ ] **Step 2: Run the controller test to verify RED.**

Run: `flutter test test/features/device_session/application/device_reconnect_controller_test.dart`

Expected: FAIL because reconnect state/controller APIs do not exist.

- [ ] **Step 3: Implement immutable state and retry controller.**

```dart
enum DeviceReconnectPhase {
  idle,
  scanning,
  connecting,
  waitingToRetry,
  connected,
  exhausted,
  suppressed,
}
```

The controller must load history before scanning, select the most recently
connected record, stop scanning before a connect callback, and guard all
async completions with an internal cycle ID. `Future<bool>` returns true only
after AppShell verifies `SessionPhase.authenticationReady`. A false result
schedules exactly one retry using injected delay behavior; the third failure
sets `exhausted` without another timer. The logger emits only `operation`,
`stage`, `attempt`, and stable failure code fields.

- [ ] **Step 4: Add failed-record and clear cleanup tests.**

```dart
test('remembers only a successful ready candidate', () async {
  await controller.rememberSuccessfulConnection(rememberedCandidate);
  expect(await history.load(), contains(isA<RememberedDevice>()));
});

test('successful clear removes the remembered candidate', () async {
  await controller.rememberSuccessfulConnection(rememberedCandidate);
  await controller.forgetSuccessfulClear(rememberedCandidate);

  expect(await history.load(), isEmpty);
});
```

- [ ] **Step 5: Run focused controller tests and commit.**

Run: `flutter test test/features/device_session/application/device_reconnect_controller_test.dart`

Expected: PASS.

Commit:

```text
feat: coordinate remembered device reconnection
```

### Task 3: Integrate Reconnection with Discovery, Session, and UI

**Files:**
- Modify: `lib/app/app_shell.dart`
- Modify: `lib/features/device_discovery/presentation/discovery_page.dart`
- Modify: `lib/features/home/presentation/home_page.dart`
- Modify: `test/app/app_shell_test.dart`
- Modify: `test/features/device_discovery/presentation/discovery_page_test.dart`
- Modify: `test/features/home/presentation/home_page_test.dart` if absent, otherwise create it.

**Interfaces:**
- Consumes Task 2's controller through a provider-independent AppShell field.
- AppShell's reconnect callback returns `true` only when `_openSession` leaves
  the new session in `SessionPhase.authenticationReady`.
- The discovery view consumes a reconnect phase/attempt display value and
  preserves its existing manual candidate selection and Bluetooth enable flow.

- [ ] **Step 1: Write failing AppShell/discovery tests.**

```dart
testWidgets('a remembered matching scan starts reconnect without a row tap',
    (tester) async {
  await pumpShellWithRememberedDevice(tester);
  fakeTransport.emitScan(rememberedCandidate);
  await tester.pump();

  expect(fakeTransport.connectRequests, ['android-mac-or-ios-id']);
});

testWidgets('a manually disconnected device does not reconnect on a later scan',
    (tester) async {
  await pumpConnectedShell(tester);
  await tester.tap(find.text('断开设备'));
  await confirmSheet(tester);
  fakeTransport.emitScan(rememberedCandidate);
  await tester.pump();

  expect(fakeTransport.connectRequests, isEmpty);
});
```

- [ ] **Step 2: Run integration tests to verify RED.**

Run: `flutter test test/app/app_shell_test.dart test/features/device_discovery/presentation/discovery_page_test.dart`

Expected: FAIL because AppShell does not create or drive a reconnect controller.

- [ ] **Step 3: Wire the AppShell lifecycle and session transitions.**

In `initState`, construct the reconnect controller with history, logger,
discovery start/stop callbacks, and a connector that calls `_openSession`.
Subscribe to discovery updates and pass each current candidate to
`considerCandidate`; cancel/remove that listener in `dispose`. After onboarding
loads, and on foreground resume, call `restoreAndStart` only when no session
is active. On a ready session, call `rememberSuccessfulConnection`; on an
unexpected interrupted session, call `markUnexpectedDisconnect`; before a
user-selected disconnect, call `suppressForForeground`. Extend the successful
clear callback to remove its record after existing checkpoint cleanup.

- [ ] **Step 4: Render concise reconnect state without adding a second flow.**

Use the existing device summary card and discovery scanning content to show
`正在回连设备` while connecting, `正在重新查找设备` while waiting, and
`回连失败，可再次尝试` after exhaustion. Opening the connection journey
calls `startExplicitCycle`, clearing suppression and retry count. Existing
manual list selection calls `_openSession` directly and cancels an active
automatic cycle so a user choice always wins.

- [ ] **Step 5: Run focused integration tests and commit.**

Run: `flutter test test/app/app_shell_test.dart test/features/device_discovery/presentation/discovery_page_test.dart test/features/home/presentation/home_page_test.dart`

Expected: PASS. Existing manual scanning, iOS Bluetooth prompt flow, and
the device-detail retry action remain available.

Commit:

```text
feat: reconnect remembered nearby devices
```

### Task 4: Verify Platform and Privacy Boundaries

**Files:**
- Verify: files changed by Tasks 1-3.
- Modify only if verification exposes a direct reconnect defect.

- [ ] **Step 1: Format and analyze reconnect files.**

Run: `dart format lib/features/device_session/domain/remembered_device.dart lib/features/device_session/domain/device_connection_history_repository.dart lib/features/device_session/data/shared_preferences_device_connection_history_repository.dart lib/features/device_session/application/device_reconnect_state.dart lib/features/device_session/application/device_reconnect_controller.dart lib/app/app_shell.dart lib/features/device_discovery/presentation/discovery_page.dart lib/features/home/presentation/home_page.dart test/features/device_session/domain/remembered_device_test.dart test/features/device_session/data/shared_preferences_device_connection_history_repository_test.dart test/features/device_session/application/device_reconnect_controller_test.dart test/app/app_shell_test.dart test/features/device_discovery/presentation/discovery_page_test.dart test/features/home/presentation/home_page_test.dart` then `flutter analyze --no-fatal-infos`.

Expected: no analyzer errors.

- [ ] **Step 2: Run focused and serial regression suites.**

Run: `flutter test test/features/device_session/domain/remembered_device_test.dart test/features/device_session/data/shared_preferences_device_connection_history_repository_test.dart test/features/device_session/application/device_reconnect_controller_test.dart test/app/app_shell_test.dart test/features/device_discovery/presentation/discovery_page_test.dart` then `flutter test --concurrency=1`.

Expected: every command exits 0.

- [ ] **Step 3: Build and device-check Android Debug.**

Run: `flutter build apk --debug`.

Expected: build succeeds. On a real Android device, connect a V1.5 device,
force an unexpected disconnect, return it to advertising range, and verify
one bounded reconnect cycle. Manually disconnect, repeat the scan, and verify
the App does not reconnect until the user selects reconnect.

- [ ] **Step 4: Check privacy and hygiene.**

Run: `git diff --check` and inspect the private remembered-device preference
only through test fixtures or App-private debugging. Inspect the in-App
diagnostic viewer and `Download/AIPIN/logs` to confirm neither MAC nor
connection ID appears.

Expected: no whitespace errors and no raw identifier in diagnostics.
