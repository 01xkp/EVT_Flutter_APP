# AI Processing Background Resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep AI processing active after users leave a recording detail page, resume persisted work on foreground entry, show one in-app completion toast, and apply progressive polling intervals.

**Architecture:** A pure application policy maps persisted capture age to polling delay. The processing controller records completed captures in a one-shot queue, while `AppShell` owns lifecycle state, consumes that queue, defers notices while backgrounded, and displays coalesced `AppToast` messages after foreground recovery. Navigation remains unchanged because processing is already provider-owned instead of route-owned.

**Tech Stack:** Flutter, Riverpod provider lifetime, `WidgetsBindingObserver`, Drift-backed `ResearchCaptureRepository`, `ChangeNotifier`, `flutter_test`.

---

### Task 1: Add The Progressive Polling Policy

**Files:**
- Create: `lib/features/research_beta/application/research_processing_poll_schedule.dart`
- Create: `test/features/research_beta/application/research_processing_poll_schedule_test.dart`

- [ ] **Step 1: Write the failing boundary tests**

```dart
test('uses two seconds before the first minute', () {
  const schedule = ResearchProcessingPollSchedule();

  expect(schedule.nextDelay(const Duration(seconds: 59)), const Duration(seconds: 2));
});

test('uses five seconds from one minute until five minutes', () {
  const schedule = ResearchProcessingPollSchedule();

  expect(schedule.nextDelay(const Duration(minutes: 1)), const Duration(seconds: 5));
  expect(schedule.nextDelay(const Duration(minutes: 4, seconds: 59)), const Duration(seconds: 5));
});

test('uses ten seconds from five minutes onward', () {
  const schedule = ResearchProcessingPollSchedule();

  expect(schedule.nextDelay(const Duration(minutes: 5)), const Duration(seconds: 10));
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/research_beta/application/research_processing_poll_schedule_test.dart -r compact`

Expected: FAIL because `ResearchProcessingPollSchedule` does not exist.

- [ ] **Step 3: Implement the smallest pure schedule**

```dart
class ResearchProcessingPollSchedule {
  const ResearchProcessingPollSchedule();

  static const _fastUntil = Duration(minutes: 1);
  static const _mediumUntil = Duration(minutes: 5);

  Duration nextDelay(Duration elapsed) {
    if (elapsed < _fastUntil) {
      return const Duration(seconds: 2);
    }
    if (elapsed < _mediumUntil) {
      return const Duration(seconds: 5);
    }
    return const Duration(seconds: 10);
  }
}
```

- [ ] **Step 4: Run the schedule tests**

Run: `flutter test test/features/research_beta/application/research_processing_poll_schedule_test.dart -r compact`

Expected: PASS with 3 tests.

### Task 2: Use The Policy And Emit Completion Notices

**Files:**
- Modify: `lib/features/research_beta/application/research_capture_processing_controller.dart:16-55, 280-470`
- Modify: `test/features/research_beta/application/research_capture_processing_controller_test.dart`
- Test: `test/features/research_beta/application/research_capture_processing_controller_test.dart`

- [ ] **Step 1: Write failing controller tests**

```dart
test('uses the capture age to progressively delay pending transcription polls', () async {
  final delays = <Duration>[];
  final startedAt = DateTime(2026, 8, 25, 10);
  final nowValues = <DateTime>[
    startedAt,
    startedAt,
    startedAt.add(const Duration(seconds: 20)),
    startedAt.add(const Duration(minutes: 1)),
    startedAt.add(const Duration(minutes: 5)),
  ].iterator;
  final pendingGateway = _SequencedPollGateway(
    pendingResponses: 4,
  );
  final progressiveController = ResearchCaptureProcessingController(
    repository: repository,
    researchFiles: files,
    localFiles: FakeRecordingFileStore(),
    gateway: pendingGateway,
    trialStore: trialStore,
    now: () => nowValues.moveNext() ? nowValues.current : startedAt.add(const Duration(minutes: 5)),
    delay: (delay) async => delays.add(delay),
  );

  await repository.save(
    ResearchCapture.fromDirectAiVoice(
      id: 'capture-1',
      participantId: 'participant-1',
      relativePath: 'capture-1.m4a',
      duration: const Duration(seconds: 12),
      createdAt: startedAt,
    ).toTranscribing('job-1'),
  );
  await progressiveController.process('capture-1');

  expect(delays, <Duration>[
    const Duration(seconds: 2),
    const Duration(seconds: 2),
    const Duration(seconds: 5),
    const Duration(seconds: 10),
  ]);
});

test('records a completed capture once until the notice queue is drained', () async {
  await repository.save(
    ResearchCapture.fromDirectAiVoice(
      id: 'capture-1',
      participantId: 'participant-1',
      relativePath: 'capture-1.m4a',
      duration: const Duration(seconds: 12),
      createdAt: DateTime(2026, 8, 25, 10),
    ).toTranscribing('job-1'),
  );

  await controller.process('capture-1');

  expect(controller.drainCompletedCaptures().single.id, 'capture-1');
  expect(controller.drainCompletedCaptures(), isEmpty);
});

class _SequencedPollGateway extends FakeTemporaryAsrGateway {
  _SequencedPollGateway({required this.pendingResponses});

  int pendingResponses;

  @override
  Future<AsrOutcome<AsrJob>> pollJob(String jobId) async {
    pollJobIds.add(jobId);
    if (pendingResponses-- > 0) {
      return AsrSuccess(AsrJob(id: jobId, status: AsrJobStatus.pending));
    }
    return AsrSuccess(AsrJob(id: jobId, status: AsrJobStatus.completed));
  }
}
```

- [ ] **Step 2: Run the controller test to verify it fails**

Run: `flutter test test/features/research_beta/application/research_capture_processing_controller_test.dart -r compact`

Expected: FAIL because the controller exposes neither the schedule dependency nor `drainCompletedCaptures`.

- [ ] **Step 3: Replace the fixed poll interval with the policy and queue completions**

```dart
ResearchCaptureProcessingController({
  // Existing dependencies.
  ResearchProcessingPollSchedule pollSchedule = const ResearchProcessingPollSchedule(),
}) : _pollSchedule = pollSchedule;

final ResearchProcessingPollSchedule _pollSchedule;
final List<ResearchCapture> _completedCaptures = <ResearchCapture>[];

List<ResearchCapture> drainCompletedCaptures() {
  final completed = List<ResearchCapture>.unmodifiable(_completedCaptures);
  _completedCaptures.clear();
  return completed;
}

Duration _nextPollDelay(ResearchCapture capture) {
  final elapsed = _now().difference(capture.createdAt);
  return _pollSchedule.nextDelay(elapsed.isNegative ? Duration.zero : elapsed);
}
```

Replace both pending-state delays with `await _delay(_nextPollDelay(capture));`. When `_completeSummary` writes the completed capture, append it to `_completedCaptures` before returning so the `finally` notification reaches listeners.

- [ ] **Step 4: Run the controller test to verify it passes**

Run: `flutter test test/features/research_beta/application/research_capture_processing_controller_test.dart -r compact`

Expected: PASS, including the new cadence and one-shot completion-notice tests.

### Task 3: Deliver Completion Notices From App Lifecycle

**Files:**
- Modify: `lib/app/app_shell.dart:1-125, 190-220, 538-625`
- Modify: `test/app/app_shell_test.dart`
- Test: `test/app/app_shell_test.dart`

- [ ] **Step 1: Write failing lifecycle widget tests**

```dart
testWidgets('shows one completion toast after a backgrounded capture finishes', (tester) async {
  final processing = _processingControllerWithControllablePendingCapture();
  await tester.pumpWidget(_appWith(processing));

  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await processing.completePendingCapture();
  await tester.pump();
  expect(find.text('AI 转写和总结已完成'), findsNothing);

  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
  expect(find.text('AI 转写和总结已完成'), findsOneWidget);
});

testWidgets('coalesces deferred completion notices into one toast', (tester) async {
  final processing = _processingControllerWithTwoControllableCaptures();
  await tester.pumpWidget(_appWith(processing));

  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await processing.completeAllPendingCaptures();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();

  expect(find.text('2 条 AI 处理已完成'), findsOneWidget);
});
```

- [ ] **Step 2: Run the app-shell test to verify it fails**

Run: `flutter test test/app/app_shell_test.dart -r compact`

Expected: FAIL because `AppShell` does not listen for completed captures or defer notifications while backgrounded.

- [ ] **Step 3: Bind `AppShell` to the provider-owned controller**

Add a lazily initialized processing-controller reference, a foreground flag, and a deferred completed-capture list. Bind a listener when `_requestAiProcessing`, `_recoverResearchCapturesInternal`, or the detail-route builder first needs the controller. Remove the listener in `dispose`.

```dart
void _onResearchProcessingChanged() {
  final completed = _researchProcessing?.drainCompletedCaptures() ?? const <ResearchCapture>[];
  if (completed.isEmpty) return;
  if (!_isForeground) {
    _deferredCompletedCaptures.addAll(completed);
    return;
  }
  _showCompletionToast(completed.length);
}

void _showCompletionToast(int count) {
  if (!mounted || count == 0) return;
  AppToast.show(
    context,
    message: count == 1 ? 'AI 转写和总结已完成' : '$count 条 AI 处理已完成',
  );
}
```

Set `_isForeground` false for non-resumed lifecycle states. On `resumed`, set it true, flush deferred notices immediately, then start the existing retention and pending-work recovery without awaiting it in the lifecycle callback. Keep `resumePending()` idempotent through the controller's existing `_inFlight` map.

- [ ] **Step 4: Run the app-shell test to verify it passes**

Run: `flutter test test/app/app_shell_test.dart -r compact`

Expected: PASS, including no AI provider creation on an unused home screen.

### Task 4: Preserve And Verify Non-Cancelling Route Exit

**Files:**
- Modify: `test/features/local_recording/presentation/local_recording_detail_page_test.dart`
- Test: `test/features/local_recording/presentation/local_recording_detail_page_test.dart`

- [ ] **Step 1: Write the route-exit regression test**

```dart
testWidgets('leaving recording detail does not cancel its pending AI capture', (tester) async {
  final gate = Completer<AsrOutcome<AsrJob>>();
  final gateway = _StalledThenCompletedGateway(gate);
  final processing = ResearchCaptureProcessingController(
    repository: repository,
    researchFiles: researchFiles,
    localFiles: localFiles,
    gateway: gateway,
    trialStore: trialStore,
  );
  await repository.save(
    ResearchCapture.fromDirectAiVoice(
      id: 'capture-1',
      participantId: 'participant-1',
      relativePath: 'capture-1.m4a',
      duration: const Duration(seconds: 12),
      createdAt: DateTime(2026, 8, 25, 10),
    ).toTranscribing('job-1'),
  );
  unawaited(processing.process('capture-1'));
  await tester.pumpWidget(MaterialApp(home: _detailPage(processing: processing)));

  await tester.pageBack();
  gate.complete(const AsrSuccess(AsrJob(id: 'job-1', status: AsrJobStatus.completed)));
  await tester.pump();

  expect((await repository.findById('capture-1'))!.processingState, ResearchProcessingState.completed);
});

class _StalledThenCompletedGateway extends FakeTemporaryAsrGateway {
  _StalledThenCompletedGateway(this.gate);

  final Completer<AsrOutcome<AsrJob>> gate;

  @override
  Future<AsrOutcome<AsrJob>> pollJob(String jobId) => gate.future;
}
```

- [ ] **Step 2: Run the detail-page test to verify the existing route contract**

Run: `flutter test test/features/local_recording/presentation/local_recording_detail_page_test.dart -r compact`

Expected: PASS. `LocalRecordingDetailPage` must remain free of route-owned cancellation. This is an existing behavior that guards the new lifecycle work rather than a new production change.

- [ ] **Step 3: Keep route exit non-cancelling**

Do not add route-owned cancellation, `dispose` cleanup, or a pop confirmation for `ResearchCaptureProcessingController`. If the regression test exposes route wiring that creates a controller outside the app-shell provider, pass the same app-shell controller instance through `LocalRecordingDetailPage` as it already does for detail rendering.

- [ ] **Step 4: Run the detail-page test to verify it passes**

Run: `flutter test test/features/local_recording/presentation/local_recording_detail_page_test.dart -r compact`

Expected: PASS with the pending task reaching completion after the route is popped.

### Task 5: Format And Verify The Integrated Change

**Files:**
- Modify: files from Tasks 1-4 only

- [ ] **Step 1: Format the changed files**

Run:

```powershell
dart format --output=none --set-exit-if-changed `
  lib/features/research_beta/application/research_processing_poll_schedule.dart `
  lib/features/research_beta/application/research_capture_processing_controller.dart `
  lib/app/app_shell.dart `
  test/features/research_beta/application/research_processing_poll_schedule_test.dart `
  test/features/research_beta/application/research_capture_processing_controller_test.dart `
  test/features/local_recording/presentation/local_recording_detail_page_test.dart `
  test/app/app_shell_test.dart
```

Expected: no formatting changes required.

- [ ] **Step 2: Run the focused feature suite**

Run:

```powershell
flutter test `
  test/features/research_beta/application/research_processing_poll_schedule_test.dart `
  test/features/research_beta/application/research_capture_processing_controller_test.dart `
  test/features/local_recording/presentation/local_recording_detail_page_test.dart `
  test/app/app_shell_test.dart `
  --concurrency=1 -r compact
```

Expected: all selected tests pass.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze`

Expected: `No issues found!`
