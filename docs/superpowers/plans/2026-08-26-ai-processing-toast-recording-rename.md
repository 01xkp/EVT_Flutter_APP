# AI Processing Toast and Recording Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show background AI processing in one queued top-center notice and let users rename recordings from every local-recording list.

**Architecture:** `ResearchCaptureProcessingController` emits UI-safe stage events. `AppShell` owns foreground and detail-page visibility, forwarding events to a generic design-system queue. The queue owns timing, FIFO completion display, and rendering. Rename reuses `LocalRecording.title`, `RecordingLibraryController.rename`, and `RenameRecordingSheet`.

**Tech Stack:** Flutter, Riverpod, ChangeNotifier, flutter_test.

---

## File Structure

- Create: `lib/core/design_system/widgets/ai_processing_toast.dart`
- Create: `test/core/design_system/ai_processing_toast_test.dart`
- Modify: `lib/features/research_beta/application/research_capture_processing_controller.dart`
- Modify: `test/features/research_beta/application/research_capture_processing_controller_test.dart`
- Modify: `lib/app/app_shell.dart`
- Modify: `test/app/app_shell_test.dart`
- Modify: `lib/features/local_recording/presentation/local_recording_detail_page.dart`
- Modify: `test/features/local_recording/presentation/local_recording_detail_page_test.dart`
- Modify: `lib/features/local_recording/presentation/local_recording_list.dart`
- Modify: `test/features/records/presentation/records_page_test.dart`

### Task 1: Add the Queued AI Notice

**Files:**
- Create: `test/core/design_system/ai_processing_toast_test.dart`
- Create: `lib/core/design_system/widgets/ai_processing_toast.dart`

- [ ] **Step 1: Write the failing widget tests**

```dart
testWidgets('renders a transcription notice at the top center', (tester) async {
  final controller = AiProcessingToastController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(_host(controller));

  controller.showProcessing(
    taskId: 'capture-1',
    stage: AiProcessingToastStage.transcribing,
  );
  await tester.pump();

  expect(find.byKey(const ValueKey('ai-processing-toast')), findsOneWidget);
  expect(find.text('正在转写'), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
  expect(
    tester.getTopLeft(find.byKey(const ValueKey('ai-processing-toast'))).dy,
    greaterThanOrEqualTo(12),
  );

  controller.showProcessing(
    taskId: 'capture-1',
    stage: AiProcessingToastStage.summarizing,
  );
  await tester.pump();
  expect(find.text('正在总结'), findsOneWidget);
});

testWidgets('shows completed tasks one at a time for two seconds', (tester) async {
  final controller = AiProcessingToastController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(_host(controller));

  controller.complete(
    taskId: 'capture-1',
    completedAt: DateTime(2026, 8, 25, 10, 56),
  );
  controller.complete(
    taskId: 'capture-2',
    completedAt: DateTime(2026, 8, 25, 10, 57),
  );
  await tester.pump();
  expect(find.text('8-25 10:56 完成'), findsOneWidget);

  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 180));
  expect(find.text('8-25 10:57 完成'), findsOneWidget);
});

Widget _host(AiProcessingToastController controller) => MaterialApp(
  home: Stack(
    children: [
      const Scaffold(body: SizedBox.expand()),
      AiProcessingToastHost(controller: controller),
    ],
  ),
);
```

- [ ] **Step 2: Verify the new test fails**

Run: `flutter test test/core/design_system/ai_processing_toast_test.dart -r compact`

Expected: FAIL because the toast controller and host do not exist.

- [ ] **Step 3: Implement the component with a presentation-only API**

```dart
enum AiProcessingToastStage { transcribing, summarizing }

class AiProcessingToastController extends ChangeNotifier {
  final Map<String, AiProcessingToastStage> _processing = {};
  final Queue<_CompletedAiTask> _pendingCompletions = Queue();
  _CompletedAiTask? _activeCompletion;
  Timer? _completionTimer;
  bool _presentationEnabled = true;

  AiProcessingToastDisplay? get display {
    if (!_presentationEnabled) return null;
    final completion = _activeCompletion;
    if (completion != null) {
      return AiProcessingToastDisplay.completed(completion.completedAt);
    }
    if (_processing.values.contains(AiProcessingToastStage.transcribing)) {
      return const AiProcessingToastDisplay.processing(
        AiProcessingToastStage.transcribing,
      );
    }
    if (_processing.values.contains(AiProcessingToastStage.summarizing)) {
      return const AiProcessingToastDisplay.processing(
        AiProcessingToastStage.summarizing,
      );
    }
    return null;
  }

  void showProcessing({
    required String taskId,
    required AiProcessingToastStage stage,
  }) {
    _processing[taskId] = stage;
    notifyListeners();
  }

  void complete({required String taskId, required DateTime completedAt}) {
    _processing.remove(taskId);
    _pendingCompletions.add(_CompletedAiTask(taskId, completedAt));
    _startOrResumeCompletion();
    notifyListeners();
  }

  void setPresentationEnabled(bool value) {
    if (_presentationEnabled == value) return;
    _presentationEnabled = value;
    _completionTimer?.cancel();
    _completionTimer = null;
    if (value) _startOrResumeCompletion();
    notifyListeners();
  }

  void _startOrResumeCompletion() {
    if (!_presentationEnabled) return;
    _activeCompletion ??= _pendingCompletions.isEmpty
        ? null
        : _pendingCompletions.removeFirst();
    if (_activeCompletion == null || _completionTimer != null) return;
    _completionTimer = Timer(const Duration(seconds: 2), () {
      _completionTimer = null;
      _activeCompletion = null;
      _startOrResumeCompletion();
      notifyListeners();
    });
  }
}
```

Implement `AiProcessingToastHost` as a `Positioned` child for a `Stack`: `top: MediaQuery.paddingOf(context).top + 12`, left/right 20, and a centered `Container` with `Colors.black.withOpacity(0.76)`, white spinner for stages, white check icon for completion, and `ValueKey('ai-processing-toast')`. Format completion as `${month}-${day} HH:mm 完成`. Use `EvtTheme.componentRadius` and ignore pointer events.

- [ ] **Step 4: Format and verify the component**

Run:

```powershell
dart format lib/core/design_system/widgets/ai_processing_toast.dart test/core/design_system/ai_processing_toast_test.dart
flutter test test/core/design_system/ai_processing_toast_test.dart -r compact
```

Expected: PASS; completion states are FIFO and each remains for two seconds.

- [ ] **Step 5: Commit the standalone component**

```powershell
git add lib/core/design_system/widgets/ai_processing_toast.dart test/core/design_system/ai_processing_toast_test.dart
git commit -m 'feat: add queued AI processing toast'
```

### Task 2: Emit UI-Safe AI Stage Events

**Files:**
- Modify: `test/features/research_beta/application/research_capture_processing_controller_test.dart`
- Modify: `lib/features/research_beta/application/research_capture_processing_controller.dart`

- [ ] **Step 1: Write the failing event-order test**

```dart
test('emits transcription summary and completion updates in order', () async {
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
  final updates = controller.drainUiUpdates();

  expect(
    updates.map((update) => update.kind),
    [
      ResearchCaptureUiUpdateKind.transcribing,
      ResearchCaptureUiUpdateKind.summarizing,
      ResearchCaptureUiUpdateKind.completed,
    ],
  );
  expect(updates.every((update) => update.captureId == 'capture-1'), isTrue);
  expect(updates.last.completedAt, DateTime(2026, 8, 24, 10));
});
```

- [ ] **Step 2: Verify it fails**

Run: `flutter test test/features/research_beta/application/research_capture_processing_controller_test.dart -r compact`

Expected: FAIL because `ResearchCaptureUiUpdateKind` and `drainUiUpdates` are not defined.

- [ ] **Step 3: Add the event model and report persisted visible-state transitions**

```dart
enum ResearchCaptureUiUpdateKind { transcribing, summarizing, completed }

class ResearchCaptureUiUpdate {
  const ResearchCaptureUiUpdate({
    required this.captureId,
    required this.kind,
    this.completedAt,
  });

  final String captureId;
  final ResearchCaptureUiUpdateKind kind;
  final DateTime? completedAt;
}

final List<ResearchCaptureUiUpdate> _pendingUiUpdates = [];

List<ResearchCaptureUiUpdate> drainUiUpdates() {
  final updates = List<ResearchCaptureUiUpdate>.unmodifiable(_pendingUiUpdates);
  _pendingUiUpdates.clear();
  _completedCaptures.clear();
  return updates;
}

void _reportStage(ResearchCapture capture) {
  final kind = switch (capture.processingState) {
    ResearchProcessingState.transcribing => ResearchCaptureUiUpdateKind.transcribing,
    ResearchProcessingState.summarizing => ResearchCaptureUiUpdateKind.summarizing,
    _ => null,
  };
  if (kind == null) return;
  _pendingUiUpdates.add(
    ResearchCaptureUiUpdate(captureId: capture.id, kind: kind),
  );
  notifyListeners();
}

void _reportCompletion(ResearchCapture capture) {
  final completedAt = capture.completedAt;
  if (completedAt == null) return;
  _pendingUiUpdates.add(
    ResearchCaptureUiUpdate(
      captureId: capture.id,
      kind: ResearchCaptureUiUpdateKind.completed,
      completedAt: completedAt,
    ),
  );
  _completedCaptures.add(capture);
  notifyListeners();
}
```

Call `_reportStage` after loading a nonterminal capture in `_processInternal`, after persisting the transcribing capture in `_submitOrResumeJob`, and after persisting the summarizing capture in `_completeTranscription`. Call `_reportCompletion` directly after persisting the completed capture in `_completeSummary`. Do not emit for polling iterations, uploads, transcript text, failures, or raw ASR payloads. Keep `drainCompletedCaptures()` for compatibility; its list is cleared whenever `drainUiUpdates()` is used.

- [ ] **Step 4: Format and verify the controller suite**

Run:

```powershell
dart format lib/features/research_beta/application/research_capture_processing_controller.dart test/features/research_beta/application/research_capture_processing_controller_test.dart
flutter test test/features/research_beta/application/research_capture_processing_controller_test.dart -r compact
```

Expected: PASS, including existing recovery and retry tests.

- [ ] **Step 5: Commit the event contract**

```powershell
git add lib/features/research_beta/application/research_capture_processing_controller.dart test/features/research_beta/application/research_capture_processing_controller_test.dart
git commit -m 'feat: emit AI processing stage updates'
```

### Task 3: Connect AppShell Lifecycle and Detail Visibility

**Files:**
- Modify: `test/features/local_recording/presentation/local_recording_detail_page_test.dart`
- Modify: `lib/features/local_recording/presentation/local_recording_detail_page.dart`
- Modify: `test/app/app_shell_test.dart`
- Modify: `lib/app/app_shell.dart`

- [ ] **Step 1: Write the failing detail callback test**

```dart
testWidgets('reports when a local recording detail page is visible', (tester) async {
  final visibility = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      home: _detailPage(onVisibilityChanged: visibility.add),
    ),
  );

  expect(visibility, [true]);
  await tester.pumpWidget(const SizedBox.shrink());
  expect(visibility, [true, false]);
});
```

Extend the existing `_detailPage` test helper with
`ValueChanged<bool>? onVisibilityChanged` and pass it through to
`LocalRecordingDetailPage`.

- [ ] **Step 2: Verify it fails**

Run: `flutter test test/features/local_recording/presentation/local_recording_detail_page_test.dart -r compact`

Expected: FAIL because `onVisibilityChanged` does not exist.

- [ ] **Step 3: Implement the lifecycle-only callback**

```dart
// LocalRecordingDetailPage constructor and field
this.onVisibilityChanged,
final ValueChanged<bool>? onVisibilityChanged;

@override
void initState() {
  super.initState();
  widget.onVisibilityChanged?.call(true);
}

@override
void dispose() {
  widget.onVisibilityChanged?.call(false);
  super.dispose();
}
```

- [ ] **Step 4: Write failing AppShell expectation for the new completion message**

Replace the current resumed-app expectation in `test/app/app_shell_test.dart` with:

```dart
expect(find.text('8-25 10:00 完成'), findsOneWidget);
expect(find.text('AI 转写和总结已完成'), findsNothing);
```

Retain the host-level two-item FIFO assertion in Task 1, avoiding duplicate timestamp setup in the AppShell test.

- [ ] **Step 5: Verify the AppShell test fails against the current generic Toast**

Run: `flutter test test/app/app_shell_test.dart -r compact`

Expected: FAIL because the shell still shows the coalesced generic completion Toast.

- [ ] **Step 6: Forward UI events from the shell and mount the host**

```dart
final AiProcessingToastController _aiProcessingToast =
    AiProcessingToastController();
final List<ResearchCaptureUiUpdate> _deferredResearchUpdates = [];
var _recordingDetailDepth = 0;

void _onResearchProcessingChanged() {
  final processing = _researchProcessing;
  if (processing == null) return;
  final updates = processing.drainUiUpdates();
  if (updates.isEmpty) return;
  if (!_isAppForeground) {
    _deferredResearchUpdates.addAll(updates);
    return;
  }
  _forwardResearchUpdates(updates);
}

void _forwardResearchUpdates(Iterable<ResearchCaptureUiUpdate> updates) {
  for (final update in updates) {
    switch (update.kind) {
      case ResearchCaptureUiUpdateKind.transcribing:
        _aiProcessingToast.showProcessing(
          taskId: update.captureId,
          stage: AiProcessingToastStage.transcribing,
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
        );
    }
  }
}

void _syncAiToastVisibility() {
  _aiProcessingToast.setPresentationEnabled(
    _isAppForeground && _recordingDetailDepth == 0,
  );
}

void _setRecordingDetailVisible(bool visible) {
  _recordingDetailDepth += visible ? 1 : -1;
  if (_recordingDetailDepth < 0) _recordingDetailDepth = 0;
  _syncAiToastVisibility();
}
```

On resume, set foreground true, call `_syncAiToastVisibility()`, forward and clear `_deferredResearchUpdates`, then call `_recoverResearchCaptures()`. On pause, set foreground false and sync visibility. Dispose `_aiProcessingToast`. Replace the shell root `Scaffold` with a `Stack` containing the current `Scaffold` first and `AiProcessingToastHost(controller: _aiProcessingToast)` second. Pass `onVisibilityChanged: _setRecordingDetailVisible` in `_localRecordingDetailRoute`.

- [ ] **Step 7: Format and verify shell integration**

Run:

```powershell
dart format lib/app/app_shell.dart lib/features/local_recording/presentation/local_recording_detail_page.dart test/app/app_shell_test.dart test/features/local_recording/presentation/local_recording_detail_page_test.dart
flutter test test/app/app_shell_test.dart test/features/local_recording/presentation/local_recording_detail_page_test.dart -r compact
```

Expected: PASS; background completion appears after resume, and detail pages disable only global presentation.

- [ ] **Step 8: Commit the AppShell integration**

```powershell
git add lib/app/app_shell.dart lib/features/local_recording/presentation/local_recording_detail_page.dart test/app/app_shell_test.dart test/features/local_recording/presentation/local_recording_detail_page_test.dart
git commit -m 'feat: show AI progress outside recording detail'
```

### Task 4: Add Rename to Records

**Files:**
- Modify: `test/features/records/presentation/records_page_test.dart`
- Modify: `lib/features/local_recording/presentation/local_recording_list.dart`

- [ ] **Step 1: Write the failing rename flow test**

```dart
testWidgets('records renames a local recording and keeps direct deletion', (tester) async {
  final repository = FakeLocalRecordingRepository([_savedRecording()]);
  final controller = RecordingLibraryController(
    repository: repository,
    files: FakeRecordingFileStore(),
    player: FakeAudioPlayer(),
  );
  addTearDown(controller.close);
  await controller.load();
  await tester.pumpWidget(
    MaterialApp(
      home: RecordsPage(
        recordingController: controller,
        evidenceController: EvidenceHistoryController(FakeEvidenceRepository()),
      ),
    ),
  );

  await tester.tap(find.byTooltip('更多操作'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('修改标题'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '客户访谈复盘');
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();

  expect(repository.values.single.title, '客户访谈复盘');
  expect(find.text('客户访谈复盘'), findsOneWidget);
  expect(find.byTooltip('删除录音'), findsOneWidget);
});
```

- [ ] **Step 2: Verify it fails**

Run: `flutter test test/features/records/presentation/records_page_test.dart -r compact`

Expected: FAIL because `记录 > 本机录音` has no more-actions menu.

- [ ] **Step 3: Reuse `RenameRecordingSheet` in `LocalRecordingList`**

```dart
import 'package:aipin/features/local_recording/presentation/rename_recording_sheet.dart';

return RecordingListItem(
  recording: recording,
  onOpen: onOpen == null ? null : () => onOpen!(recording),
  showActions: true,
  showDeleteAction: false,
  showDeleteButton: true,
  onRename: () => unawaited(_rename(context, recording)),
  onDelete: () => unawaited(_delete(context, recording)),
);

Future<void> _rename(BuildContext context, LocalRecording recording) async {
  final value = await RenameRecordingSheet.show(context, title: recording.title);
  if (value != null) await controller.rename(recording, value);
}
```

Do not modify the repository, model, detail-page title, or delete flow: all already consume the persisted `LocalRecording.title`.

- [ ] **Step 4: Format and verify the records tests**

Run:

```powershell
dart format lib/features/local_recording/presentation/local_recording_list.dart test/features/records/presentation/records_page_test.dart
flutter test test/features/records/presentation/records_page_test.dart -r compact
```

Expected: PASS; the new name remains after reload and direct delete stays available.

- [ ] **Step 5: Commit the rename action**

```powershell
git add lib/features/local_recording/presentation/local_recording_list.dart test/features/records/presentation/records_page_test.dart
git commit -m 'feat: add recording rename action to records'
```

### Task 5: Final Focused Verification

**Files:**
- Modify only when a focused verification reveals a scoped defect.

- [ ] **Step 1: Run all affected tests**

```powershell
flutter test test/core/design_system/ai_processing_toast_test.dart test/features/research_beta/application/research_capture_processing_controller_test.dart test/features/local_recording/presentation/local_recording_detail_page_test.dart test/features/records/presentation/records_page_test.dart test/app/app_shell_test.dart -r compact
```

Expected: PASS.

- [ ] **Step 2: Analyze affected source and test files**

```powershell
dart analyze lib/core/design_system/widgets/ai_processing_toast.dart lib/features/research_beta/application/research_capture_processing_controller.dart lib/app/app_shell.dart lib/features/local_recording/presentation/local_recording_detail_page.dart lib/features/local_recording/presentation/local_recording_list.dart test/core/design_system/ai_processing_toast_test.dart test/features/research_beta/application/research_capture_processing_controller_test.dart test/app/app_shell_test.dart test/features/local_recording/presentation/local_recording_detail_page_test.dart test/features/records/presentation/records_page_test.dart
```

Expected: `No issues found!`.

- [ ] **Step 3: Check final whitespace and scope**

```powershell
git diff --check
git status --short
```

Expected: no whitespace errors; preserve and report pre-existing user-owned changes.
