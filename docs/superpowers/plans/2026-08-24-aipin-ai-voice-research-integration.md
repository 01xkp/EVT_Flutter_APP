# AIPIN AI Voice Research Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a separately consented AI Voice research flow that records or explicitly copies a local recording, processes it with the temporary ASR service, and lets invited users review research cards without changing the offline local-recording contract.

**Architecture:** Keep local recording and research processing separate. The new `research_beta` feature owns models, Drift tables, private audio copies, controllers, temporary-ASR gateway, and research-only UI. Existing recording ports are reused only through contracts: local recording keeps the 44.1 kHz configuration, while AI Voice creates a separate 16 kHz capture and research file. A persisted capture state machine drives upload, polling, retry, expiry, and UI recovery.

**Tech Stack:** Flutter Material 3, Riverpod, Drift/SQLite, `record`, `just_audio`, native `dart:io` `HttpClient`, `shared_preferences`, `flutter_test`, local `HttpServer` gateway tests.

---

## File Structure

- Create: `lib/features/research_beta/domain/research_capture.dart` - Capture model, origin, processing/inbox states, validation, and immutable transition methods.
- Create: `lib/features/research_beta/domain/research_capture_repository.dart` - Persisted capture and research-event repository contracts.
- Create: `lib/features/research_beta/domain/research_capture_file_store.dart` - Private research audio allocation, copy, validation, and cleanup contract.
- Create: `lib/features/research_beta/domain/research_analytics.dart` - Content-free research events, aggregate model, and allowed event payloads.
- Create: `lib/features/research_beta/domain/temporary_asr_gateway.dart` - Temporary remote-job and note API contract with typed result/failure values.
- Create: `lib/features/research_beta/data/app_research_capture_file_store.dart` - `research_captures/` private-directory implementation.
- Create: `lib/features/research_beta/data/drift_research_capture_repository.dart` - Drift mapping for captures, events, and aggregates.
- Create: `lib/features/research_beta/data/temporary_asr_http_gateway.dart` - Native multipart request/polling implementation, with no hard-coded server URL.
- Create: `lib/features/research_beta/data/shared_preferences_research_trial_store.dart` - Consent, anonymous participant ID, and trial-start store.
- Create: `lib/features/research_beta/application/research_recording_controller.dart` - Direct AI Voice recording lifecycle and 2–60 second validation.
- Create: `lib/features/research_beta/application/research_capture_processing_controller.dart` - Upload, stage transitions, recovery, retry, deletion, retention, and analytics orchestration.
- Create: `lib/features/research_beta/application/research_capture_library_controller.dart` - Capture list, detail actions, and daily-understanding prompt state.
- Create: `lib/features/research_beta/presentation/research_consent_sheet.dart` - Research-service disclosure and explicit consent UI.
- Create: `lib/features/research_beta/presentation/active_research_recording_page.dart` - Direct AI Voice capture screen with elapsed time, waveform, cancellation, and 60-second cap.
- Create: `lib/features/research_beta/presentation/research_capture_list.dart` - Processing/needs-review/handled sections.
- Create: `lib/features/research_beta/presentation/research_capture_card.dart` - Stable capture status/card affordances.
- Create: `lib/features/research_beta/presentation/research_capture_detail_page.dart` - Playback, read-only machine transcript, corrections, feedback, retain/copy/delete actions.
- Create: `lib/features/research_beta/presentation/research_upload_confirmation_sheet.dart` - Per-upload temporary-service warning and confirmation.
- Create: `lib/features/research_beta/presentation/research_settings_section.dart` - Delete-all-research-data and aggregate export actions.
- Create: `lib/core/persistence/tables/research_captures.dart` - Drift capture table.
- Create: `lib/core/persistence/tables/research_events.dart` - Drift content-free event and aggregate tables.
- Modify: `lib/core/persistence/app_database.dart` and generated `lib/core/persistence/app_database.g.dart` - Register research tables and migrate schema 2 to 3.
- Modify: `lib/features/local_recording/data/record_audio_recorder.dart` - Accept injected `record.RecordConfig` rather than a hard-coded static config.
- Modify: `lib/app/providers.dart` - Supply research repository, files, gateway, trial store, controller, and 16 kHz recorder providers.
- Modify: `lib/features/local_recording/presentation/recording_hub_page.dart` - Add the `AI 语音` entry next to existing local recording.
- Modify: `lib/features/local_recording/presentation/recording_list_item.dart` and `local_recording_library_page.dart` - Add explicit `AI 整理` / `查看 AI 结果` action without altering local ownership.
- Modify: `lib/features/records/presentation/records_page.dart` - Add third `AI 语音` segment.
- Modify: `lib/features/settings/presentation/settings_page.dart` - Host research-data controls.
- Modify: `lib/app/app_shell.dart` - Navigate between hub, direct AI recording, AI result detail, and Records AI segment.
- Modify: `android/app/src/main/AndroidManifest.xml` - Add Internet permission only if absent.
- Modify: `README.md` - Document opt-in temporary endpoint configuration and non-sensitive-content restriction.
- Create: focused domain/data/application/presentation tests under `test/features/research_beta/` and fakes under `test/support/`.

Existing worktree changes are user-owned. Review and stage only the files listed by each task; do not add broad generated directories, existing edited files, or unrelated branding/BLE changes to any commit.

### Task 1: Define Research Capture Contracts and Their Failing Tests

**Files:**
- Create: `lib/features/research_beta/domain/research_capture.dart`
- Create: `lib/features/research_beta/domain/research_capture_repository.dart`
- Create: `lib/features/research_beta/domain/research_capture_file_store.dart`
- Create: `lib/features/research_beta/domain/research_analytics.dart`
- Create: `lib/features/research_beta/domain/temporary_asr_gateway.dart`
- Create: `test/features/research_beta/domain/research_capture_test.dart`
- Create: `test/features/research_beta/domain/research_analytics_test.dart`

- [ ] **Step 1: Write state, ownership, and redaction tests before models exist**

```dart
test('a local upload keeps a durable reference to the original recording', () {
  final capture = ResearchCapture.fromLocalRecording(
    id: 'capture-1',
    originalLocalRecordingId: 'local-1',
    relativePath: 'research_captures/capture-1.m4a',
    duration: const Duration(seconds: 12),
    createdAt: DateTime(2026, 8, 24),
  );

  expect(capture.origin, ResearchCaptureOrigin.localRecordingUpload);
  expect(capture.originalLocalRecordingId, 'local-1');
  expect(capture.sourceType, 'research_import');
});

test('invalid AI Voice durations cannot start ASR processing', () {
  expect(() => ResearchCapture.validateDuration(const Duration(seconds: 1)), throwsArgumentError);
  expect(() => ResearchCapture.validateDuration(const Duration(seconds: 61)), throwsArgumentError);
  expect(ResearchCapture.validateDuration(const Duration(seconds: 2)), isNull);
});

test('research events never serialize captured content', () {
  final event = ResearchEvent.captureHandled(
    participantId: 'anonymous-1',
    captureId: 'capture-1',
    action: ResearchCardAction.copied,
    duration: const Duration(seconds: 19),
  );

  expect(event.toDatabaseMap().keys, isNot(containsAll(['audioPath', 'transcript', 'summary', 'title', 'tags', 'copiedText'])));
});
```

- [ ] **Step 2: Run the domain tests to establish the red state**

Run: `flutter test test/features/research_beta/domain/research_capture_test.dart test/features/research_beta/domain/research_analytics_test.dart`

Expected: compilation failure because the research domain files do not exist.

- [ ] **Step 3: Implement the immutable capture state machine and ports**

Create the enums and model with exactly these state values:

```dart
enum ResearchCaptureOrigin { directAiVoice, localRecordingUpload }
enum ResearchProcessingState {
  uploading, transcribing, summarizing, completed,
  uploadFailed, transcriptionFailed, summaryFailed,
}
enum ResearchInboxState { processing, needsReview, handled }
enum ResearchCardAction { retained, edited, copied, useful, notUseful }

class ResearchCapture {
  const ResearchCapture({
    required this.id, required this.participantId, required this.origin,
    required this.sourceType, required this.relativePath, required this.duration,
    required this.createdAt, required this.processingState, required this.inboxState,
    this.originalLocalRecordingId, this.jobId, this.noteId, this.generationTaskId,
    this.rawTranscript, this.correctedTranscript, this.title, this.summary,
    this.tags = const [], this.actionContext, this.failureReason, this.openedAt,
    this.handledAt,
  });

  static const sourceTypeResearchImport = 'research_import';
  static void validateDuration(Duration duration) {
    if (duration < const Duration(seconds: 2) || duration > const Duration(seconds: 60)) {
      throw ArgumentError.value(duration, 'duration', 'AI 语音仅支持 2 至 60 秒');
    }
  }
  // Include factories fromDirectAiVoice/fromLocalRecording and transitions
  // toUploading, toTranscribing, toSummarizing, completed, failed, and handled.
}

abstract interface class ResearchCaptureRepository {
  Future<void> save(ResearchCapture capture);
  Future<void> update(ResearchCapture capture);
  Future<ResearchCapture?> findById(String id);
  Future<ResearchCapture?> findByOriginalLocalRecordingId(String localRecordingId);
  Stream<List<ResearchCapture>> watchAll();
  Future<List<ResearchCapture>> findNonterminal();
  Future<void> delete(String id);
  Future<void> deleteAllCaptures();
  Future<void> saveEvent(ResearchEvent event);
  Future<void> saveAggregate(ResearchAggregate aggregate);
  Future<ResearchAggregate?> loadAggregate(String participantId);
}
```

Define `ResearchCaptureFileStore` with `createPending`, `finalize`, `copyFromLocal`, `resolve`, `delete`, and `deleteAll`. Define `TemporaryAsrGateway` with typed `submitAudio`, `pollJob`, `fetchTranscript`, `createNote`, `pollGenerationTask`, `fetchCompletedNote`, and `deleteNote` methods. Its return types must carry remote IDs, transcript `relativePath`/`variant`/`engine`, and failures without serializing opaque server JSON into the capture.

Define `ResearchEvent` and `ResearchAggregate` using only participant ID, capture ID, event type, stage, duration bucket, action, quality feedback, daily-understanding response, elapsed time, and timestamps. Keep transcript/title/summary/audio path fields out of their constructors and maps.

- [ ] **Step 4: Run domain tests and format the new files**

Run: `dart format lib/features/research_beta/domain test/features/research_beta/domain`

Run: `flutter test test/features/research_beta/domain/research_capture_test.dart test/features/research_beta/domain/research_analytics_test.dart`

Expected: both tests pass and no transition accepts an out-of-range duration.

- [ ] **Step 5: Commit only the domain contract slice**

```powershell
git add lib/features/research_beta/domain test/features/research_beta/domain
git commit -m "feat: define AI voice research domain"
```

### Task 2: Persist Research Captures Separately from Local Recordings

**Files:**
- Create: `lib/core/persistence/tables/research_captures.dart`
- Create: `lib/core/persistence/tables/research_events.dart`
- Modify: `lib/core/persistence/app_database.dart`
- Modify: generated `lib/core/persistence/app_database.g.dart`
- Create: `lib/features/research_beta/data/drift_research_capture_repository.dart`
- Create: `test/features/research_beta/data/drift_research_capture_repository_test.dart`

- [ ] **Step 1: Write repository tests for migration-safe ownership and queries**

```dart
test('saving a research capture does not create a LocalRecordings row', () async {
  final database = AppDatabase.forTesting();
  final repository = DriftResearchCaptureRepository(database);
  await repository.save(_directCapture(id: 'ai-1'));

  expect(await database.select(database.localRecordings).get(), isEmpty);
  expect(await repository.findById('ai-1'), isNotNull);
});

test('an original local-recording lookup returns at most one research capture', () async {
  await repository.save(_localUpload(id: 'ai-1', localId: 'local-1'));
  expect((await repository.findByOriginalLocalRecordingId('local-1'))!.id, 'ai-1');
});
```

- [ ] **Step 2: Run the focused repository test and confirm it fails**

Run: `flutter test test/features/research_beta/data/drift_research_capture_repository_test.dart`

Expected: compilation failure because research Drift tables and repository are absent.

- [ ] **Step 3: Add schema version 3 and research tables**

Create `ResearchCaptures` with a text primary key and columns matching `ResearchCapture`: participant/origin/source type, nullable original local ID with a unique index, relative path, duration milliseconds, persisted state/inbox values, remote IDs, raw/corrected transcript, card fields, JSON tag list, timestamps, and failure reason. Create `ResearchEvents` with only content-free event fields. Create `ResearchAggregates` keyed by participant ID with counts and retention timestamps only.

Register all tables in `@DriftDatabase`, set `schemaVersion` to `3`, and add this ordered migration:

```dart
onUpgrade: (migrator, from, to) async {
  if (from < 2) await migrator.createTable(localRecordings);
  if (from < 3) {
    await migrator.createTable(researchCaptures);
    await migrator.createTable(researchEvents);
    await migrator.createTable(researchAggregates);
  }
},
```

Implement row mappers in `DriftResearchCaptureRepository`; reject duplicate local-upload IDs before insert, watch captures ordered by `createdAt.desc()`, and map enum/database fields explicitly.

- [ ] **Step 4: Generate Drift code and prove the repository behavior**

Run: `dart run build_runner build --delete-conflicting-outputs`

Run: `flutter test test/features/research_beta/data/drift_research_capture_repository_test.dart`

Expected: generated database code compiles, the new table exists in an in-memory database, and local-recording rows remain untouched.

- [ ] **Step 5: Commit the persistence slice**

```powershell
git add lib/core/persistence/app_database.dart lib/core/persistence/app_database.g.dart lib/core/persistence/tables/research_captures.dart lib/core/persistence/tables/research_events.dart lib/features/research_beta/data/drift_research_capture_repository.dart test/features/research_beta/data/drift_research_capture_repository_test.dart
git commit -m "feat: persist AI voice research captures"
```

### Task 3: Store Independent Research Audio and Make Recorder Format Injectable

**Files:**
- Modify: `lib/features/local_recording/data/record_audio_recorder.dart`
- Create: `lib/features/research_beta/data/app_research_capture_file_store.dart`
- Create: `test/features/research_beta/data/app_research_capture_file_store_test.dart`
- Modify: `test/features/local_recording/data/record_audio_recorder_test.dart`

- [ ] **Step 1: Write failing tests for dedicated copy/delete paths and 16 kHz configuration**

```dart
test('copyFromLocal writes an independent research copy', () async {
  final source = await _writeFile('recordings/local-1.m4a', bytes: [1, 2, 3]);
  final copy = await store.copyFromLocal(id: 'capture-1', sourcePath: source.path);
  await File(source.path).delete();

  expect(await File(copy.absolutePath).readAsBytes(), [1, 2, 3]);
});

test('research recorder passes the supplied 16 kHz config to record', () async {
  final recorder = RecordAudioRecorder(recorder: fake, config: researchRecordConfig);
  await recorder.start('capture.m4a');
  expect(fake.lastConfig!.sampleRate, 16000);
  expect(fake.lastConfig!.encoder, record.AudioEncoder.aacLc);
});
```

- [ ] **Step 2: Run the tests to confirm the current implementation is insufficient**

Run: `flutter test test/features/research_beta/data/app_research_capture_file_store_test.dart test/features/local_recording/data/record_audio_recorder_test.dart`

Expected: research file-store import fails and the recorder has no configurable constructor parameter.

- [ ] **Step 3: Implement independent private storage and config injection**

Replace `RecordAudioRecorder`'s static config with a constructor argument whose default is the existing 44.1 kHz AAC-LC mono `RecordConfig`. Export a named immutable `researchRecordConfig` in the research data module with AAC-LC, 64 kbps, mono, and `sampleRate: 16000`.

Implement `AppResearchCaptureFileStore` using `getApplicationDocumentsDirectory()` and a fixed `research_captures` child. Its `copyFromLocal` must use `File(sourcePath).copy(targetPath)`, reject missing/empty output, and return a research-relative path. `delete` and `deleteAll` must only resolve paths below the research directory; they must never accept or remove a `recordings/` path.

- [ ] **Step 4: Run focused file and existing recorder regressions**

Run: `dart format lib/features/local_recording/data/record_audio_recorder.dart lib/features/research_beta/data test/features/research_beta/data test/features/local_recording/data/record_audio_recorder_test.dart`

Run: `flutter test test/features/research_beta/data/app_research_capture_file_store_test.dart test/features/local_recording/data/record_audio_recorder_test.dart test/features/local_recording/data/app_recording_file_store_test.dart`

Expected: research paths are copied and deleted independently, and existing local recording tests still verify 44.1 kHz behavior.

- [ ] **Step 5: Commit the recording/file-boundary slice**

```powershell
git add lib/features/local_recording/data/record_audio_recorder.dart lib/features/research_beta/data/app_research_capture_file_store.dart test/features/local_recording/data/record_audio_recorder_test.dart test/features/research_beta/data/app_research_capture_file_store_test.dart
git commit -m "feat: isolate AI voice audio storage"
```

### Task 4: Implement the Temporary ASR Gateway with Local HTTP Tests

**Files:**
- Create: `lib/features/research_beta/data/temporary_asr_http_gateway.dart`
- Create: `test/features/research_beta/data/temporary_asr_http_gateway_test.dart`
- Create: `test/support/fake_temporary_asr_gateway.dart`

- [ ] **Step 1: Write local-server tests for each documented endpoint and strict result mapper**

```dart
test('submitAudio posts M4A and required empty reference file', () async {
  final request = await server.nextRequest();
  expect(request.method, 'POST');
  expect(request.uri.path, '/api/jobs');
  expect(await request.multipartField('engines'), 'sensevoice');
  expect(await request.multipartField('language'), 'zh');
  expect(await request.multipartField('semantic_eval'), 'false');
  expect(await request.multipartFileBytes('reference_files'), isEmpty);
});

test('only a successful nonempty flat_rows transcript is accepted', () async {
  await server.respondJson({'flat_rows': [{'success': true, 'transcript': ''}]});
  expect(await gateway.fetchTranscript('job-1'), isA<AsrFailure>());
});

test('unknown generation status maps to summary failure instead of invented card data', () async {
  await server.respondJson({'status': 'mystery-complete', 'title': 'ignored'});
  expect(await gateway.pollGenerationTask('note-1', 'task-1'), isA<AsrFailure>());
});
```

- [ ] **Step 2: Run the gateway test before implementation**

Run: `flutter test test/features/research_beta/data/temporary_asr_http_gateway_test.dart`

Expected: compilation failure because `TemporaryAsrHttpGateway` does not exist.

- [ ] **Step 3: Implement the endpoint-configured native client**

Construct the gateway from `String.fromEnvironment('ASR_API_BASE_URL')`. An empty value must return a typed unavailable failure before any network call. Use `HttpClient`, a generated multipart boundary, and streamed file bytes. Submit `files`, empty UTF-8 `reference_files`, `engines=sensevoice`, `language=zh`, and `semantic_eval=false` to `/api/jobs`.

Implement polling helpers that wait exactly two seconds between nonterminal responses. Accept job states `queued` and `running` as pending; on documented completion fetch `/api/jobs/{jobId}/results`; map only a `flat_rows` object with `success == true`, a nonblank `transcript`, and nonblank `relative_path`, `variant`, and `engine` to `AsrTranscript`.

Create notes through `/api/meeting-notes`, persist server-returned note/task IDs, and poll `/api/meeting-notes/{noteId}/generation-tasks/{taskId}`. Keep supported completion status strings and note-field mapping in one explicit private mapper verified by the fixture. Map missing/unknown structure to `AsrFailure.summaryUnsupported`; never build a title or summary from an unrecognized JSON field. Implement remote note deletion using `POST /api/meeting-notes/{noteId}/permanent-delete` and JSON `{ "confirm": true }`; do not claim transcription-job deletion.

- [ ] **Step 4: Run local gateway tests and static analysis**

Run: `dart format lib/features/research_beta/data/temporary_asr_http_gateway.dart test/features/research_beta/data/temporary_asr_http_gateway_test.dart test/support/fake_temporary_asr_gateway.dart`

Run: `flutter test test/features/research_beta/data/temporary_asr_http_gateway_test.dart`

Run: `flutter analyze`

Expected: tests prove request construction and rejection of unknown result shapes without calling a public endpoint.

- [ ] **Step 5: Commit the gateway slice**

```powershell
git add lib/features/research_beta/data/temporary_asr_http_gateway.dart test/features/research_beta/data/temporary_asr_http_gateway_test.dart test/support/fake_temporary_asr_gateway.dart
git commit -m "feat: add temporary ASR gateway"
```

### Task 5: Add Persisted Recording, Processing, Retry, and Retention Controllers

**Files:**
- Create: `lib/features/research_beta/application/research_recording_controller.dart`
- Create: `lib/features/research_beta/application/research_capture_processing_controller.dart`
- Create: `lib/features/research_beta/application/research_capture_library_controller.dart`
- Create: `lib/features/research_beta/data/shared_preferences_research_trial_store.dart`
- Create: `test/features/research_beta/application/research_recording_controller_test.dart`
- Create: `test/features/research_beta/application/research_capture_processing_controller_test.dart`
- Create: `test/features/research_beta/application/research_capture_library_controller_test.dart`
- Create: `test/support/fake_research_capture_repository.dart`
- Create: `test/support/fake_research_capture_file_store.dart`

- [ ] **Step 1: Write failing controller tests for direct recording, upload idempotency, and retention**

```dart
test('direct AI Voice at 61 seconds stops and rejects upload', () async {
  await controller.start();
  fakeRecorder.emitElapsed(const Duration(seconds: 61));
  await controller.stop();
  expect(controller.state.validationMessage, 'AI 语音仅支持 2 至 60 秒');
  expect(fakeGateway.submittedFiles, isEmpty);
});

test('recovery resumes from saved job ID without resubmitting audio', () async {
  await processing.resumePending();
  expect(fakeGateway.submitCount, 0);
  expect(fakeGateway.pollJobIds, contains('job-1'));
});

test('day 21 clears content and preserves content-free aggregate', () async {
  await processing.enforceRetention(now: DateTime(2026, 9, 14));
  expect(await repository.findById('capture-1'), isNull);
  expect((await repository.loadAggregate('participant-1'))!.captureCount, 1);
});
```

- [ ] **Step 2: Run controller tests to confirm the missing behavior**

Run: `flutter test test/features/research_beta/application/research_recording_controller_test.dart test/features/research_beta/application/research_capture_processing_controller_test.dart test/features/research_beta/application/research_capture_library_controller_test.dart`

Expected: compilation failure because no research controllers or test fakes exist.

- [ ] **Step 3: Implement direct AI Voice recording and explicit local-upload creation**

`ResearchRecordingController` must use its research file store and 16 kHz recorder only. It starts only after consent exists, shows the existing microphone-permission state, updates amplitude/elapsed, auto-stops at 60 seconds, discards interrupted/invalid input, and saves a direct `ResearchCapture` only when its finalized file is nonempty and its duration is 2–60 seconds.

`ResearchCaptureProcessingController.createFromLocalRecording` must first reject non-playable or out-of-range local items and then look up the optional original-local ID. It copies the local file, saves one `localRecordingUpload` capture, and starts processing. A later invocation with the same original ID returns the existing capture and does not copy or submit again.

- [ ] **Step 4: Implement persisted stages, retries, lifecycle recovery, deletion, and expiry**

Advance and persist these exact stages: `uploading` -> `transcribing` -> `summarizing` -> `completed`. Save each remote ID as soon as received. Resume nonterminal captures on application startup/resume from their deepest saved identifier, without resubmitting an existing job or note. Cap a processing attempt at 90 seconds and move the capture to `uploadFailed`, `transcriptionFailed`, or `summaryFailed` while keeping audio/transcript. `retry(captureId)` resumes only the failed stage.

On every delete, attempt remote note deletion only when `noteId` exists, record an error event on failure, then always remove the local research file and capture metadata. `deleteAllResearchData` repeats the local cleanup for every capture. Never call the local-recording repository from either delete method.

The trial store writes consent timestamp, trial start timestamp, and an installation UUID participant ID. On launch/resume, aggregate content-free metrics, purge captures/events after 21 calendar days, and remove aggregates 12 months after trial start. The controller's daily-understanding method permits one prompt only on the first completed-card open on a local calendar day.

- [ ] **Step 5: Run controllers and commit this orchestration slice**

Run: `dart format lib/features/research_beta/application lib/features/research_beta/data/shared_preferences_research_trial_store.dart test/features/research_beta/application test/support/fake_research_capture_repository.dart test/support/fake_research_capture_file_store.dart`

Run: `flutter test test/features/research_beta/application`

```powershell
git add lib/features/research_beta/application lib/features/research_beta/data/shared_preferences_research_trial_store.dart test/features/research_beta/application test/support/fake_research_capture_repository.dart test/support/fake_research_capture_file_store.dart
git commit -m "feat: process AI voice research captures"
```

### Task 6: Wire Dependencies and Build the Full Research User Flow

**Files:**
- Modify: `lib/app/providers.dart`
- Modify: `lib/app/app_shell.dart`
- Modify: `lib/features/local_recording/presentation/recording_hub_page.dart`
- Modify: `lib/features/local_recording/presentation/recording_list_item.dart`
- Modify: `lib/features/local_recording/presentation/local_recording_library_page.dart`
- Modify: `lib/features/records/presentation/records_page.dart`
- Modify: `lib/features/settings/presentation/settings_page.dart`
- Create: all files under `lib/features/research_beta/presentation/` listed in File Structure
- Create: `test/features/research_beta/presentation/research_flow_test.dart`
- Modify: `test/features/local_recording/presentation/recording_hub_page_test.dart`
- Modify: `test/features/local_recording/presentation/local_recording_library_page_test.dart`
- Modify: `test/features/records/presentation/records_page_test.dart`

- [ ] **Step 1: Add red widget tests for entry points, confirmation, and segmented record views**

```dart
testWidgets('recording hub exposes separate local and AI Voice entry points', (tester) async {
  await tester.pumpWidget(_hub());
  expect(find.text('开始本机录音'), findsOneWidget);
  expect(find.text('AI 语音'), findsOneWidget);
});

testWidgets('AI organize requires confirmation before an existing local recording is copied', (tester) async {
  await tester.tap(find.byTooltip('AI 整理'));
  await tester.pumpAndSettle();
  expect(find.text('将上传研究副本'), findsOneWidget);
  expect(fakeProcessing.createFromLocalCalls, 0);
  await tester.tap(find.text('确认上传'));
  expect(fakeProcessing.createFromLocalCalls, 1);
});

testWidgets('records provides Local, Device, and AI Voice segments', (tester) async {
  await tester.pumpWidget(_records());
  expect(find.text('AI 语音'), findsOneWidget);
});
```

- [ ] **Step 2: Run the widget tests and confirm the UI contracts are absent**

Run: `flutter test test/features/research_beta/presentation/research_flow_test.dart test/features/local_recording/presentation/recording_hub_page_test.dart test/features/local_recording/presentation/local_recording_library_page_test.dart test/features/records/presentation/records_page_test.dart`

Expected: tests fail because the AI Voice route/entry and third Records segment are absent.

- [ ] **Step 3: Add Riverpod providers and route callbacks without changing local recording behavior**

In `providers.dart`, create providers for the research file store, repository, trial store, gateway, research-configured `RecordAudioRecorder`, `ResearchRecordingController`, `ResearchCaptureProcessingController`, and `ResearchCaptureLibraryController`. Dispose recorder/controller resources through `ref.onDispose`; do not share the local-recording controller instance.

In `RecordingHubPage`, place a secondary `AI 语音` button after the primary local button with an `auto_awesome_outlined` icon and no hardware terminology. In `AppShell`, direct it to consent when consent is absent, otherwise to `ActiveResearchRecordingPage`; after a valid stop, start processing and navigate to the AI Voice Records segment. Preserve the current local recording route and exit-without-save behavior unchanged.

- [ ] **Step 4: Add upload confirmation and local-list state mapping**

For a saved/playable local item in the 2–60-second range, render a 44 px minimum-tap `IconButton` with `auto_awesome_outlined`, tooltip `AI 整理`. Show `ResearchUploadConfirmationSheet` on every tap with the warning that the audio is copied to a temporary unauthenticated research service and must not contain sensitive information. `确认上传` calls `createFromLocalRecording`; cancel does not create a file or row.

If `findByOriginalLocalRecordingId` returns a capture, replace the icon action with `查看 AI 结果`, open that capture detail, and never submit again. Out-of-range/unplayable local recordings do not show an AI action.

- [ ] **Step 5: Implement consent, active recording, cards, detail actions, and settings controls**

Consent must state: closed research Beta, every input is `research_import`, the service is temporary/public/unauthenticated, do not record sensitive content, and local recordings remain offline unless explicitly uploaded. Acceptance persists consent; rejection returns to the recording hub.

The active AI recording page uses the existing visual language with restrained `AnimatedSwitcher`/`AnimatedOpacity` state transitions, 44 px controls, an explicit discard/exit confirmation, and a visible 60-second limit. It does not mention hardware or BLE.

The third Records view groups cards into `处理中`, `待回看`, and `已处理`. Detail shows processing/retry/error states, local research-copy playback, title/summary/tags/action context only after a verified server mapper produced them, expandable read-only machine transcript, separately editable corrected transcript, retain/copy/useful/not-useful actions, quality feedback, and deletion. Opening records `openedAt` but does not mark handled. Retain, edit, copy, useful, or not-useful marks handled; retain/edit/copy/useful increments useful-reuse metrics. At the first daily completed-card opening, show a one-question understanding dialog and save only the answer/time metric.

Settings exposes `删除全部研究数据` with the existing confirmation component and a content-free aggregate export action. Do not expose raw recording, transcript, card fields, or copied text in its export.

- [ ] **Step 6: Run widget tests and commit the UI slice**

Run: `dart format lib/app/providers.dart lib/app/app_shell.dart lib/features/local_recording/presentation lib/features/records/presentation/records_page.dart lib/features/settings/presentation/settings_page.dart lib/features/research_beta/presentation test/features/research_beta/presentation test/features/local_recording/presentation test/features/records/presentation/records_page_test.dart`

Run: `flutter test test/features/research_beta/presentation/research_flow_test.dart test/features/local_recording/presentation/recording_hub_page_test.dart test/features/local_recording/presentation/local_recording_library_page_test.dart test/features/records/presentation/records_page_test.dart`

```powershell
git add lib/app/providers.dart lib/app/app_shell.dart lib/features/local_recording/presentation/recording_hub_page.dart lib/features/local_recording/presentation/recording_list_item.dart lib/features/local_recording/presentation/local_recording_library_page.dart lib/features/records/presentation/records_page.dart lib/features/settings/presentation/settings_page.dart lib/features/research_beta/presentation test/features/research_beta/presentation test/features/local_recording/presentation/recording_hub_page_test.dart test/features/local_recording/presentation/local_recording_library_page_test.dart test/features/records/presentation/records_page_test.dart
git commit -m "feat: add AI voice research experience"
```

### Task 7: Add Platform Configuration, Document the Temporary Endpoint, and Verify End to End

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `README.md`
- Modify: `test/smoke_test.dart`
- Modify: `docs/superpowers/plans/2026-08-24-aipin-ai-voice-research-integration.md` - mark only completed checklist items during execution.

- [ ] **Step 1: Write the final smoke and configuration assertions**

```dart
testWidgets('app keeps local recording available when ASR endpoint is not configured', (tester) async {
  await tester.pumpWidget(_app(asrBaseUrl: ''));
  await tester.tap(find.text('AI 语音'));
  await tester.pumpAndSettle();
  expect(find.text('暂未配置 AI 语音服务'), findsOneWidget);
  expect(find.text('开始本机录音'), findsOneWidget);
});
```

- [ ] **Step 2: Run the smoke test and establish the final expected UI boundary**

Run: `flutter test test/smoke_test.dart`

Expected: pass after the provider supplies an unavailable typed gateway for an empty `ASR_API_BASE_URL`.

- [ ] **Step 3: Apply minimal platform and documentation changes**

If `android.permission.INTERNET` is not already in the manifest, add one normal permission immediately below the manifest tag. Do not add iOS ATS exceptions because the configured endpoint is HTTPS and existing microphone descriptions cover recording.

Add this README command and warning verbatim:

```powershell
flutter run --dart-define=ASR_API_BASE_URL=https://your-temporary-asr-host
```

`AI 语音` is a closed research feature. The temporary service is public and unauthenticated; never use it for sensitive recordings. Omitting `ASR_API_BASE_URL` leaves the offline local-recording flow available and disables AI upload.

- [ ] **Step 4: Run automated quality gates**

Run: `dart format lib test`

Run: `flutter analyze`

Run: `flutter test`

Run: `flutter build apk --debug --dart-define=ASR_API_BASE_URL=https://example.invalid`

Expected: formatting is clean, analyzer has no issues, all test suites pass, and the debug APK compiles without embedding a production endpoint.

- [ ] **Step 5: Perform platform/manual verification with non-sensitive fixture content**

On Android and iOS physical devices, verify: microphone denial; local recording remains 44.1 kHz/offline; AI Voice uses M4A/AAC-LC/mono/16 kHz; 2-second acceptance; 60-second automatic stop; direct AI upload; local `AI 整理` confirmation; no duplicate upload; processing after background/resume; retry from each failed stage; independent deletion in both directions; delete-all research data; daily understanding prompt; and accessible 44 px controls in light/dark themes.

Run the temporary-ASR integration only against a non-sensitive fixture recording. Record the observed documented generation-task completion value and supported note JSON fields in the test fixture before allowing a capture to reach `completed`. If the service returns an unknown status or note shape, verify it becomes retryable `summaryFailed` with original research audio and raw transcript retained.

- [ ] **Step 6: Review and commit the final scoped changes**

```powershell
git diff --check
git status --short
git add android/app/src/main/AndroidManifest.xml README.md test/smoke_test.dart docs/superpowers/plans/2026-08-24-aipin-ai-voice-research-integration.md
git commit -m "docs: document AI voice research setup"
```

Expected: `git diff --check` has no output. The status report may still show user-owned files outside this feature; leave them unstaged.
