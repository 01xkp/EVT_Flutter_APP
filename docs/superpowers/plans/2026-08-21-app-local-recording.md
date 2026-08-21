# App Local Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an offline, background-capable phone-local recording library while preserving the existing device-owned hardware recording observation flow.

**Architecture:** Introduce a feature-first `local_recording` module with domain ports for capture, playback, files, and Android foreground service. A Drift-backed repository stores metadata only; the `AppRecordingFileStore` owns private M4A files and recovery. `AppShell` owns the two local-recording controllers for the process lifetime and routes hardware recording to the existing VAD observation page.

**Tech Stack:** Flutter 3.44.6 / Dart 3.12.2, Material 3, Riverpod, Drift, `record 7.1.1`, `just_audio 0.10.6`, `path_provider 2.1.6`, `uuid 4.6.0`, `flutter_foreground_task 11.0.1`, `permission_handler`, `sqlite3 3.5.2` for migration fixtures, `flutter_test`, Android foreground service, and iOS Audio Session/background audio.

---

## File Structure

```text
lib/
  app/
    app_shell.dart                                      modify navigation and controller ownership
    providers.dart                                      add recording dependency providers
  core/persistence/
    app_database.dart                                   add v2 migration and LocalRecordings table
    tables/local_recordings.dart                         create metadata table
  features/local_recording/
    domain/
      local_recording.dart                               entity and state
      local_recording_repository.dart                    repository contract
      audio_recorder_port.dart                           capture contract and signals
      audio_player_port.dart                             playback contract and state
      recording_file_store.dart                          private-file contract
      recording_background_port.dart                     background-service contract
    application/
      recording_controller.dart                          active capture state machine
      recording_library_controller.dart                  list, playback, rename, delete
      recording_recovery_service.dart                    startup reconciliation
    data/
      drift_local_recording_repository.dart              Drift implementation
      app_recording_file_store.dart                      M4A paths, atomic move, recovery
      record_audio_recorder.dart                         record package adapter
      just_audio_player.dart                             just_audio adapter
      foreground_recording_service.dart                  foreground-task adapter
    presentation/
      recording_hub_page.dart                            local/hardware entry cards
      local_recording_library_page.dart                  local library and new-record action
      active_recording_page.dart                         timer, level, pause, stop
      recording_list_item.dart                           play/list/overflow row
      rename_recording_sheet.dart                        title edit sheet
android/app/src/main/AndroidManifest.xml                 microphone and service declarations
ios/Runner/Info.plist                                    microphone message and audio background mode
pubspec.yaml                                             audio/background dependencies
test/
  support/fake_audio_player.dart
  support/fake_audio_recorder.dart
  support/fake_local_recording_repository.dart
  support/fake_recording_background_service.dart
  support/fake_recording_file_store.dart
  features/local_recording/...                           focused domain, data, application, widget tests
```

## Task 1: Add Recording Domain Contracts

**Files:**
- Create: `lib/features/local_recording/domain/local_recording.dart`
- Create: `lib/features/local_recording/domain/local_recording_repository.dart`
- Create: `lib/features/local_recording/domain/audio_recorder_port.dart`
- Create: `lib/features/local_recording/domain/audio_player_port.dart`
- Create: `lib/features/local_recording/domain/recording_file_store.dart`
- Create: `lib/features/local_recording/domain/recording_background_port.dart`
- Test: `test/features/local_recording/domain/local_recording_test.dart`

- [ ] **Step 1: Write the failing local-recording entity tests**

```dart
test('saved and interrupted records are playable only with inspected metadata', () {
  expect(
    LocalRecording.inProgress(
      id: 'recording-1',
      title: '录音 2026-08-21 09:28',
      relativePath: 'recording-1.m4a',
      createdAt: DateTime(2026, 8, 21, 9, 28),
    ).isPlayable,
    isFalse,
  );
  expect(
    LocalRecording.saved(
      id: 'recording-2',
      title: '客户访谈',
      relativePath: 'recording-2.m4a',
      createdAt: DateTime(2026, 8, 21, 9, 28),
      completedAt: DateTime(2026, 8, 21, 9, 29),
      duration: const Duration(seconds: 12),
      sizeBytes: 160000,
    ).isPlayable,
    isTrue,
  );
});

test('renaming trims text and rejects an empty result', () {
  final record = LocalRecording.inProgress(
    id: 'recording-1',
    title: '初始标题',
    relativePath: 'recording-1.m4a',
    createdAt: DateTime(2026, 8, 21),
  );

  expect(record.renamed('  客户访谈  ').title, '客户访谈');
  expect(() => record.renamed('   '), throwsArgumentError);
});
```

- [ ] **Step 2: Run the domain test to verify it fails**

Run: `flutter test test/features/local_recording/domain/local_recording_test.dart`

Expected: FAIL because the `local_recording` domain library does not exist.

- [ ] **Step 3: Implement the entity and narrow boundary contracts**

```dart
enum LocalRecordingStatus { inProgress, saved, interrupted, failed }

class LocalRecording {
  const LocalRecording({
    required this.id,
    required this.title,
    required this.relativePath,
    required this.createdAt,
    required this.status,
    this.completedAt,
    this.duration,
    this.sizeBytes,
    this.failureReason,
  });

  final String id;
  final String title;
  final String relativePath;
  final DateTime createdAt;
  final LocalRecordingStatus status;
  final DateTime? completedAt;
  final Duration? duration;
  final int? sizeBytes;
  final String? failureReason;

  bool get isPlayable =>
      (status == LocalRecordingStatus.saved ||
          status == LocalRecordingStatus.interrupted) &&
      duration != null &&
      sizeBytes != null &&
      sizeBytes! > 0;

  factory LocalRecording.inProgress({
    required String id,
    required String title,
    required String relativePath,
    required DateTime createdAt,
  }) => LocalRecording(
    id: id,
    title: title,
    relativePath: relativePath,
    createdAt: createdAt,
    status: LocalRecordingStatus.inProgress,
  );

  factory LocalRecording.saved({
    required String id,
    required String title,
    required String relativePath,
    required DateTime createdAt,
    required DateTime completedAt,
    required Duration duration,
    required int sizeBytes,
  }) => LocalRecording(
    id: id,
    title: title,
    relativePath: relativePath,
    createdAt: createdAt,
    status: LocalRecordingStatus.saved,
    completedAt: completedAt,
    duration: duration,
    sizeBytes: sizeBytes,
  );

  LocalRecording renamed(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(value, 'value', '标题不能为空');
    return copyWith(title: trimmed);
  }

  LocalRecording failed(String reason) => copyWith(
    status: LocalRecordingStatus.failed,
    failureReason: reason,
  );

  LocalRecording copyWith({
    String? title,
    LocalRecordingStatus? status,
    DateTime? completedAt,
    Duration? duration,
    int? sizeBytes,
    String? failureReason,
  }) => LocalRecording(
    id: id,
    title: title ?? this.title,
    relativePath: relativePath,
    createdAt: createdAt,
    status: status ?? this.status,
    completedAt: completedAt ?? this.completedAt,
    duration: duration ?? this.duration,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    failureReason: failureReason ?? this.failureReason,
  );
}

abstract interface class LocalRecordingRepository {
  Future<List<LocalRecording>> all();
  Future<void> save(LocalRecording recording);
  Future<void> update(LocalRecording recording);
  Future<void> delete(String id);
}

enum RecorderPermission { granted, denied, permanentlyDenied }

sealed class RecorderSignal {
  const RecorderSignal();
  const factory RecorderSignal.interrupted(String reason) = RecorderInterrupted;
}

class RecorderInterrupted extends RecorderSignal {
  const RecorderInterrupted(this.reason);
  final String reason;
}

class StoppedCapture {
  const StoppedCapture({required this.duration});
  final Duration duration;
}

abstract interface class AudioRecorderPort {
  Future<RecorderPermission> requestPermission();
  Stream<RecorderSignal> get signals;
  Future<void> start(String temporaryPath);
  Future<void> pause();
  Future<void> resume();
  Future<StoppedCapture> stop();
  Future<void> dispose();
}

abstract interface class AudioPlayerPort {
  Future<void> play(String absolutePath);
  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();
}

class PendingRecordingFile {
  const PendingRecordingFile({
    required this.id,
    required this.temporaryPath,
    required this.relativePath,
  });
  final String id;
  final String temporaryPath;
  final String relativePath;
}

class CompletedRecordingFile {
  const CompletedRecordingFile({
    required this.relativePath,
    required this.absolutePath,
    required this.sizeBytes,
  });
  final String relativePath;
  final String absolutePath;
  final int sizeBytes;
}

abstract interface class RecordingFileStore {
  Future<PendingRecordingFile> createPending({required String id});
  Future<CompletedRecordingFile> finalize(PendingRecordingFile pending);
  Future<String> absolutePathFor(String relativePath);
  Future<void> delete(String relativePath);
}

abstract interface class RecordingBackgroundPort {
  Future<void> start();
  Future<void> stop();
}
```

Define `AudioRecorderPort`, `AudioPlayerPort`, `RecordingFileStore`, and `RecordingBackgroundPort` in the other four files. Expose only typed start/pause/resume/stop, playback, temporary-file, final-file, recovery, and background-service operations. Do not import Flutter plugins or `dart:io` from the domain layer.

- [ ] **Step 4: Run the domain test to verify it passes**

Run: `flutter test test/features/local_recording/domain/local_recording_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit the domain boundary**

```bash
git add lib/features/local_recording/domain test/features/local_recording/domain
git commit -m "feat: add local recording domain contracts"
```

## Task 2: Add Packages And Platform Recording Declarations

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`
- Create: `lib/features/local_recording/data/foreground_recording_service.dart`
- Test: `test/features/local_recording/data/foreground_recording_service_test.dart`

- [ ] **Step 1: Write the failing background-service contract test**

```dart
test('non-Android background service is a no-op that remains testable', () async {
  final service = FakeRecordingBackgroundService();

  await service.start();
  await service.stop();

  expect(service.startCalls, 1);
  expect(service.stopCalls, 1);
});
```

- [ ] **Step 2: Add the supported package set**

Run:

```bash
flutter pub add record:7.1.1 just_audio:0.10.6 path_provider:2.1.6 uuid:4.6.0 flutter_foreground_task:11.0.1
flutter pub add dev:sqlite3:3.5.2
```

Expected: `pubspec.yaml` and `pubspec.lock` contain the five direct dependencies without changing existing BLE, Drift, or permission packages.

- [ ] **Step 3: Add platform declarations and background-service adapter**

Add these Android permissions before `<application>`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
```

Declare the foreground-task service inside `<application>` with microphone type:

```xml
<service
    android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
    android:foregroundServiceType="microphone"
    android:exported="false" />
```

Add the iOS microphone message and audio background mode:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>用于录制并保存在本机的语音记录。</string>
<key>UIBackgroundModes</key>
<array><string>audio</string></array>
```

Implement `ForegroundRecordingService` as the Android-only `RecordingBackgroundPort`: initialize the notification channel once, request notification permission only after the user starts recording, start the microphone foreground service before `AudioRecorderPort.start`, update its elapsed recording text, and stop it after finalization. Return a no-op implementation on iOS rather than importing Android behavior into UI code.

- [ ] **Step 4: Run the unit and declaration checks**

Run:

```bash
flutter test test/features/local_recording/data/foreground_recording_service_test.dart
rg -n "RECORD_AUDIO|FOREGROUND_SERVICE_MICROPHONE|foregroundServiceType=\"microphone\"" android/app/src/main/AndroidManifest.xml
rg -n "NSMicrophoneUsageDescription|UIBackgroundModes" ios/Runner/Info.plist
```

Expected: the unit test passes and each required declaration is found exactly once.

- [ ] **Step 5: Commit package and platform scaffolding**

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist lib/features/local_recording/data/foreground_recording_service.dart test/features/local_recording/data/foreground_recording_service_test.dart
git commit -m "feat: configure local recording platforms"
```

## Task 3: Persist Local-recording Metadata In Drift

**Files:**
- Create: `lib/core/persistence/tables/local_recordings.dart`
- Modify: `lib/core/persistence/app_database.dart`
- Modify: `lib/core/persistence/app_database.g.dart`
- Create: `lib/features/local_recording/data/drift_local_recording_repository.dart`
- Test: `test/features/local_recording/data/drift_local_recording_repository_test.dart`

- [ ] **Step 1: Write failing repository and migration tests**

```dart
test('stores local records without device identity and returns newest first', () async {
  final repository = DriftLocalRecordingRepository(database);
  await repository.save(savedRecording(id: 'older', createdAt: DateTime(2026, 8, 20)));
  await repository.save(savedRecording(id: 'newer', createdAt: DateTime(2026, 8, 21)));

  expect((await repository.all()).map((item) => item.id), ['newer', 'older']);
});

test('database version 2 creates LocalRecordings without altering evidence rows', () async {
  final v1File = File('${temporaryDirectory.path}/v1.sqlite');
  seedV1EvidenceDatabase(v1File);
  final database = AppDatabase.forTesting(executor: NativeDatabase(v1File));

  expect(await database.select(database.evidenceBundles).get(), isNotEmpty);
  expect(await database.select(database.localRecordings).get(), isEmpty);
});
```

Create the test-only `seedV1EvidenceDatabase` helper with an explicit v1 SQLite schema and row:

```dart
void seedV1EvidenceDatabase(File file) {
  final legacy = sqlite.sqlite3.open(file.path);
  legacy.execute('''
    CREATE TABLE evidence_bundles (
      id TEXT NOT NULL PRIMARY KEY, session_id TEXT NOT NULL,
      device_id TEXT NOT NULL, device_name TEXT NOT NULL,
      firmware_version TEXT, verdict TEXT NOT NULL, reason TEXT NOT NULL,
      manual_note TEXT, diagnostic_json TEXT NOT NULL, created_at INTEGER NOT NULL
    );
    CREATE TABLE session_events (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, bundle_id TEXT NOT NULL,
      sequence INTEGER NOT NULL, record_kind TEXT NOT NULL, source TEXT NOT NULL,
      occurred_at INTEGER NOT NULL, payload_json TEXT NOT NULL
    );
    INSERT INTO evidence_bundles VALUES (
      'evidence-1', 'session-1', 'device-1', 'AIPIN_8423', NULL,
      'passed', '已获得所需设备证据。', NULL, '{}', 1787302800000
    );
    PRAGMA user_version = 1;
  ''');
  legacy.dispose();
}
```

Import `package:drift/native.dart`, `package:sqlite3/sqlite3.dart` as `sqlite`, and `dart:io`; expose `AppDatabase.forTesting({QueryExecutor? executor})` so this fixture can exercise the real migration.

- [ ] **Step 2: Run the persistence test to verify it fails**

Run: `flutter test test/features/local_recording/data/drift_local_recording_repository_test.dart`

Expected: FAIL because `LocalRecordings`, `localRecordings`, and the repository do not exist.

- [ ] **Step 3: Implement table, migration, and repository**

```dart
@DataClassName('LocalRecordingRow')
class LocalRecordings extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get relativePath => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get sizeBytes => integer().nullable()();
  TextColumn get state => text()();
  TextColumn get failureReason => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
```

Register `LocalRecordings` in `@DriftDatabase`, set `schemaVersion` to `2`, and add a `MigrationStrategy` that calls `m.createAll()` for new databases and `m.createTable(localRecordings)` only when `from < 2`. Make `AppDatabase.forTesting` accept an optional `QueryExecutor` so the v1 fixture can exercise the real migration. Map null duration/size only to non-playable states; never attach a device id, session id, or evidence bundle id.

- [ ] **Step 4: Regenerate Drift and run persistence tests**

Run:

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test test/features/local_recording/data/drift_local_recording_repository_test.dart
```

Expected: generated database code includes `LocalRecordings`, both repository tests pass, and no generated-file conflicts remain.

- [ ] **Step 5: Commit persistence**

```bash
git add lib/core/persistence lib/features/local_recording/data/drift_local_recording_repository.dart test/features/local_recording/data/drift_local_recording_repository_test.dart
git commit -m "feat: persist local recording metadata"
```

## Task 4: Add Private-file Lifecycle And Recovery

**Files:**
- Create: `lib/features/local_recording/data/app_recording_file_store.dart`
- Test: `test/features/local_recording/data/app_recording_file_store_test.dart`

- [ ] **Step 1: Write the failing file-store tests using a temporary directory**

```dart
test('promotes a completed temporary capture to the stable M4A path', () async {
  final store = AppRecordingFileStore.forTesting(root: temporaryDirectory);
  final pending = await store.createPending(id: 'recording-1');
  await File(pending.temporaryPath).writeAsBytes([1, 2, 3]);

  final completed = await store.finalize(pending);

  expect(completed.relativePath, 'recording-1.m4a');
  expect(File(completed.absolutePath).exists(), completion(isTrue));
  expect(File(pending.temporaryPath).exists(), completion(isFalse));
});

test('recovers a readable partial file as interrupted and marks a missing file failed', () async {
  // Seed one .part.m4a file and one missing path, then assert both outcomes.
});
```

- [ ] **Step 2: Run the file-store test to verify it fails**

Run: `flutter test test/features/local_recording/data/app_recording_file_store_test.dart`

Expected: FAIL because `AppRecordingFileStore` does not exist.

- [ ] **Step 3: Implement file creation, promotion, inspection, and cleanup**

```dart
Future<PendingRecordingFile> createPending({required String id}) async {
  final directory = await _recordingsDirectory();
  return PendingRecordingFile(
    id: id,
    temporaryPath: '${directory.path}${Platform.pathSeparator}$id.part.m4a',
    relativePath: '$id.m4a',
  );
}

Future<CompletedRecordingFile> finalize(PendingRecordingFile pending) async {
  final source = File(pending.temporaryPath);
  final sizeBytes = await source.length();
  if (sizeBytes == 0) throw const RecordingFileException('录音文件为空。');
  final destination = File(await absolutePathFor(pending.relativePath));
  await source.rename(destination.path);
  return CompletedRecordingFile(
    relativePath: pending.relativePath,
    absolutePath: destination.path,
    sizeBytes: sizeBytes,
  );
}
```

Use `getApplicationDocumentsDirectory()` in production and an injected directory in tests. Reject paths that are not a generated `<uuid>.m4a` filename. Keep recovery deterministic: readable `.part.m4a` becomes a final file for an `interrupted` row, unreadable/missing files become `failed`, and unexpected orphan files are reported to the recovery result without deletion.

- [ ] **Step 4: Run file lifecycle tests**

Run: `flutter test test/features/local_recording/data/app_recording_file_store_test.dart`

Expected: PASS for promotion, size capture, missing file recovery, partial-file recovery, and failed cleanup retry.

- [ ] **Step 5: Commit private file management**

```bash
git add lib/features/local_recording/data/app_recording_file_store.dart test/features/local_recording/data/app_recording_file_store_test.dart
git commit -m "feat: manage local recording files safely"
```

## Task 5: Implement Recorder And Playback Adapters

**Files:**
- Create: `lib/features/local_recording/data/record_audio_recorder.dart`
- Create: `lib/features/local_recording/data/just_audio_player.dart`
- Create: `test/support/fake_audio_recorder.dart`
- Create: `test/support/fake_audio_player.dart`
- Test: `test/features/local_recording/data/record_audio_recorder_test.dart`
- Test: `test/features/local_recording/data/just_audio_player_test.dart`

- [ ] **Step 1: Write adapter-facing tests against ports and fakes**

```dart
test('recorder exposes pause, resume, and interruption signals', () async {
  final recorder = FakeAudioRecorder()..permission = RecorderPermission.granted;
  await recorder.start('/tmp/recording.part.m4a');
  await recorder.pause();
  await recorder.resume();
  recorder.emit(const RecorderSignal.interrupted('系统音频中断'));

  expect(recorder.operations, ['start', 'pause', 'resume']);
  expect(
    await recorder.signals.first,
    isA<RecorderInterrupted>().having((value) => value.reason, 'reason', '系统音频中断'),
  );
});

test('player stops previous audio before selecting a new file', () async {
  final player = FakeAudioPlayer();
  await player.play('/tmp/one.m4a');
  await player.play('/tmp/two.m4a');
  expect(player.playedPaths, ['/tmp/one.m4a', '/tmp/two.m4a']);
  expect(player.activePath, '/tmp/two.m4a');
});
```

- [ ] **Step 2: Run the adapter tests to verify they fail**

Run:

```bash
flutter test test/features/local_recording/data/record_audio_recorder_test.dart
flutter test test/features/local_recording/data/just_audio_player_test.dart
```

Expected: FAIL because adapters and fakes do not exist.

- [ ] **Step 3: Implement plugin adapters behind the ports**

```dart
const _recordConfig = RecordConfig(
  encoder: AudioEncoder.aacLc,
  bitRate: 64000,
  sampleRate: 44100,
  numChannels: 1,
  autoGain: true,
  echoCancel: true,
  noiseSuppress: true,
);

Future<void> start(String temporaryPath) async {
  if (!await _recorder.hasPermission()) {
    throw const RecorderPermissionException();
  }
  await _recorder.start(_recordConfig, path: temporaryPath);
}
```

`RecordAudioRecorder` maps package errors and amplitude updates to typed domain signals, calls `dispose()` exactly once, and does not decide UI text. `JustAudioPlayer` owns one `AudioPlayer`, calls `stop()` before `setFilePath` for a different item, exposes playback state and position streams, and releases resources in `dispose()`.

- [ ] **Step 4: Run the adapter and analyzer checks**

Run:

```bash
flutter test test/features/local_recording/data/record_audio_recorder_test.dart test/features/local_recording/data/just_audio_player_test.dart
flutter analyze
```

Expected: PASS with no analyzer issues.

- [ ] **Step 5: Commit audio adapters**

```bash
git add lib/features/local_recording/data/record_audio_recorder.dart lib/features/local_recording/data/just_audio_player.dart test/support/fake_audio_recorder.dart test/support/fake_audio_player.dart test/features/local_recording/data
git commit -m "feat: add local recording audio adapters"
```

## Task 6: Implement Active Recording And Recovery Controllers

**Files:**
- Create: `lib/features/local_recording/application/recording_controller.dart`
- Create: `lib/features/local_recording/application/recording_recovery_service.dart`
- Create: `test/support/fake_local_recording_repository.dart`
- Create: `test/support/fake_recording_file_store.dart`
- Create: `test/support/fake_recording_background_service.dart`
- Test: `test/features/local_recording/application/recording_controller_test.dart`
- Test: `test/features/local_recording/application/recording_recovery_service_test.dart`

- [ ] **Step 1: Write failing active-state and recovery tests**

```dart
test('start persists in-progress metadata before capture and finalizes to saved', () async {
  final controller = controllerWithGrantedPermission();

  await controller.start();
  expect(repository.values.single.status, LocalRecordingStatus.inProgress);
  expect(background.startCalls, 1);

  await controller.stop();
  expect(repository.values.single.status, LocalRecordingStatus.saved);
  expect(repository.values.single.duration, const Duration(seconds: 12));
  expect(background.stopCalls, 1);
});

test('an interruption preserves a readable partial capture as interrupted', () async {
  final controller = controllerWithGrantedPermission();
  await controller.start();
  recorder.emit(const RecorderSignal.interrupted('来电占用麦克风'));
  await pumpEventQueue();

  expect(repository.values.single.status, LocalRecordingStatus.interrupted);
  expect(repository.values.single.failureReason, '来电占用麦克风');
});

test('recovery never upgrades a missing temporary file to saved', () async {
  await recoveryService.reconcile();
  expect(repository.values.single.status, LocalRecordingStatus.failed);
});
```

- [ ] **Step 2: Run the controller tests to verify they fail**

Run:

```bash
flutter test test/features/local_recording/application/recording_controller_test.dart
flutter test test/features/local_recording/application/recording_recovery_service_test.dart
```

Expected: FAIL because the controllers do not exist.

- [ ] **Step 3: Implement deterministic recording and recovery state machines**

```dart
Future<void> start() async {
  _setState(_state.copyWith(phase: ActiveRecordingPhase.starting));
  final permission = await _recorder.requestPermission();
  if (permission != RecorderPermission.granted) {
    _setState(_state.copyWith(phase: ActiveRecordingPhase.permissionDenied));
    return;
  }
  final pending = await _files.createPending(id: _uuid.v4());
  final record = LocalRecording.inProgress(
    id: pending.id,
    title: _titleFor(_clock.now()),
    relativePath: pending.relativePath,
    createdAt: _clock.now(),
  );
  await _repository.save(record);
  await _background.start();
  await _recorder.start(pending.temporaryPath);
  _setState(_state.copyWith(phase: ActiveRecordingPhase.recording, recording: record));
}
```

Subscribe once to recorder signals. Pause/resume only from the corresponding active phase. Stop and interruption both call a shared `finalize` method; the normal action yields `saved`, while a readable interruption yields `interrupted`. Every finalization attempts foreground-service shutdown in `finally`. `RecordingRecoveryService.reconcile()` runs once during controller setup and delegates only to repository/file-store contracts.

- [ ] **Step 4: Run controller tests**

Run:

```bash
flutter test test/features/local_recording/application/recording_controller_test.dart test/features/local_recording/application/recording_recovery_service_test.dart
```

Expected: PASS for denied permission, start, pause, resume, normal stop, storage failure, interruption, background-service cleanup, and startup recovery.

- [ ] **Step 5: Commit active recording orchestration**

```bash
git add lib/features/local_recording/application test/support/fake_local_recording_repository.dart test/support/fake_recording_file_store.dart test/support/fake_recording_background_service.dart test/features/local_recording/application
git commit -m "feat: manage local recording lifecycle"
```

## Task 7: Implement Library And Playback Controller

**Files:**
- Create: `lib/features/local_recording/application/recording_library_controller.dart`
- Test: `test/features/local_recording/application/recording_library_controller_test.dart`

- [ ] **Step 1: Write failing library tests**

```dart
test('load keeps prior rows when the repository throws', () async {
  repository.values.add(savedRecording(id: 'one'));
  final controller = RecordingLibraryController(repository, files, player);
  await controller.load();
  repository.failReads = true;
  await controller.load();

  expect(controller.state.items.single.id, 'one');
  expect(controller.state.errorMessage, '本地录音暂时不可读取。');
});

test('starting playback stops the prior selection and blocks it during capture', () async {
  await controller.play('one');
  await controller.play('two');
  expect(player.activePath, endsWith('two.m4a'));

  controller.setCaptureActive(true);
  await controller.play('one');
  expect(controller.state.errorMessage, '录音进行中，结束后可播放。');
});
```

- [ ] **Step 2: Run the library test to verify it fails**

Run: `flutter test test/features/local_recording/application/recording_library_controller_test.dart`

Expected: FAIL because `RecordingLibraryController` does not exist.

- [ ] **Step 3: Implement library operations with file-first deletion**

```dart
Future<void> delete(LocalRecording recording) async {
  await stopPlayback();
  try {
    await _files.delete(recording.relativePath);
    await _repository.delete(recording.id);
  } on RecordingFileException catch (error) {
    await _repository.update(recording.failed(error.message));
    _setState(_state.copyWith(errorMessage: '无法删除录音，可重试。'));
  }
  await load();
}
```

Implement `load`, `play`, `pause`, `stopPlayback`, `rename`, and `delete`. Sort records by `createdAt` descending in the repository, retain the last list on load error, prevent playback while active capture is recording or paused, and expose a stable selected playback id/position state for widgets.

- [ ] **Step 4: Run the library tests**

Run: `flutter test test/features/local_recording/application/recording_library_controller_test.dart`

Expected: PASS for load, error retention, one-player selection, rename validation, file-first delete, delete retry, and capture/playback mutual exclusion.

- [ ] **Step 5: Commit library orchestration**

```bash
git add lib/features/local_recording/application/recording_library_controller.dart test/features/local_recording/application/recording_library_controller_test.dart
git commit -m "feat: manage local recording library"
```

## Task 8: Build Recording Pages And Shared Controls

**Files:**
- Create: `lib/features/local_recording/presentation/recording_hub_page.dart`
- Create: `lib/features/local_recording/presentation/local_recording_library_page.dart`
- Create: `lib/features/local_recording/presentation/active_recording_page.dart`
- Create: `lib/features/local_recording/presentation/recording_list_item.dart`
- Create: `lib/features/local_recording/presentation/rename_recording_sheet.dart`
- Test: `test/features/local_recording/presentation/recording_hub_page_test.dart`
- Test: `test/features/local_recording/presentation/local_recording_library_page_test.dart`
- Test: `test/features/local_recording/presentation/active_recording_page_test.dart`

- [ ] **Step 1: Write failing widget tests for entry states and destructive actions**

```dart
testWidgets('hub leaves local recording enabled offline and explains unavailable hardware', (tester) async {
  await tester.pumpWidget(
    MaterialApp(home: RecordingHubPage(isHardwareObservable: false)),
  );

  expect(find.text('本机录音'), findsOneWidget);
  expect(find.byTooltip('开始本机录音'), findsOneWidget);
  expect(find.text('连接设备后观察录音状态'), findsOneWidget);
});

testWidgets('active recorder renders a fixed timer and pause then stop controls', (tester) async {
  await tester.pumpWidget(MaterialApp(home: ActiveRecordingPage(controller: controller)));
  expect(find.text('00:00:00'), findsOneWidget);
  expect(find.byTooltip('暂停录音'), findsOneWidget);
  expect(find.byTooltip('结束录音'), findsOneWidget);
});

testWidgets('library delete asks for explicit confirmation', (tester) async {
  await tester.tap(find.byTooltip('更多操作'));
  await tester.tap(find.text('删除'));
  await tester.pumpAndSettle();
  expect(find.text('删除这条录音？'), findsOneWidget);
});
```

- [ ] **Step 2: Run widget tests to verify they fail**

Run:

```bash
flutter test test/features/local_recording/presentation/recording_hub_page_test.dart
flutter test test/features/local_recording/presentation/local_recording_library_page_test.dart
flutter test test/features/local_recording/presentation/active_recording_page_test.dart
```

Expected: FAIL because the presentation files do not exist.

- [ ] **Step 3: Implement focused UI components with semantic theme values**

```dart
AnimatedSwitcher(
  duration: EvtTheme.motionDuration,
  child: switch (state.phase) {
    ActiveRecordingPhase.recording => _ActiveControls(
        key: const ValueKey('recording'),
        onPause: controller.pause,
        onStop: controller.stop,
      ),
    ActiveRecordingPhase.paused => _PausedControls(
        key: const ValueKey('paused'),
        onResume: controller.resume,
        onStop: controller.stop,
      ),
    _ => const SizedBox.shrink(),
  },
)
```

Use `AppButton`, `AppDialog.confirmDestructive`, `StatusLabel`, `Theme.of(context)`, standard Material icons, and `EvtTheme.motionDuration`. Keep timers tabular and fixed-width. Use `ListView.separated` for the library, `showModalBottomSheet` for rename, `AppDialog` for delete, and `Semantics` labels for every icon-only button. Do not add raw color constants, gradients, local radius values, or a second nested card surface.

- [ ] **Step 4: Run widget and visual-layout tests**

Run:

```bash
flutter test test/features/local_recording/presentation
flutter test test/core/design_system/evt_theme_test.dart
```

Expected: PASS in light/dark widgets, offline entry, active controls, list empty/error/content states, rename, delete confirmation, and enlarged-text layout checks.

- [ ] **Step 5: Commit presentation**

```bash
git add lib/features/local_recording/presentation test/features/local_recording/presentation
git commit -m "feat: add local recording screens"
```

## Task 9: Wire App Navigation, Providers, And Hardware Handoff

**Files:**
- Modify: `lib/app/providers.dart`
- Modify: `lib/app/app_shell.dart`
- Modify: `lib/features/observation/presentation/observation_page.dart`
- Modify: `test/app/app_shell_test.dart`

- [ ] **Step 1: Write the failing shell navigation tests**

```dart
testWidgets('recording destination works offline and retains hardware handoff', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: localRecordingProviderOverrides(),
      child: const EvtApp(),
    ),
  );

  await tester.tap(find.byTooltip('录音'));
  await tester.pumpAndSettle();
  expect(find.text('本机录音'), findsOneWidget);
  expect(find.text('硬件录音'), findsOneWidget);
});

testWidgets('hardware recording opens VAD observation with the matching scenario selected', (tester) async {
  // Connect FakeBleTransport, select the hardware card, and expect VAD 录音 selected.
});
```

- [ ] **Step 2: Run the shell test to verify it fails**

Run: `flutter test test/app/app_shell_test.dart`

Expected: FAIL because the middle navigation action is still `记录观察`.

- [ ] **Step 3: Assemble dependencies and route the two paths**

```dart
final localRecordingRepositoryProvider = Provider<LocalRecordingRepository>((ref) {
  return DriftLocalRecordingRepository(ref.watch(appDatabaseProvider));
});

final recordingControllerProvider = Provider<RecordingController>((ref) {
  final controller = RecordingController(
    repository: ref.watch(localRecordingRepositoryProvider),
    recorder: ref.watch(audioRecorderProvider),
    files: ref.watch(recordingFileStoreProvider),
    background: ref.watch(recordingBackgroundProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
```

Replace the global `记录观察` bottom-bar action with `录音`. Keep `RecordObservationSheet` reachable only from `ObservationPage`. Make `AppShell` create and own the active/local-library controllers once, call recovery during initialization, and dispose them after recorder/player resources are released. Add `initialScenario` to `ObservationPage`, defaulting to `deviceAccess`; the hardware card passes `ObservationScenario.vadRecording` only when `session.state.isObservable` is true.

- [ ] **Step 4: Run the app navigation regression tests**

Run:

```bash
flutter test test/app/app_shell_test.dart
flutter test test/features/observation/presentation/observation_page_test.dart
```

Expected: PASS for offline local entry, selected VAD hardware handoff, preserved contextual observation notes, and evidence navigation.

- [ ] **Step 5: Commit App integration**

```bash
git add lib/app/providers.dart lib/app/app_shell.dart lib/features/observation/presentation/observation_page.dart test/app/app_shell_test.dart test/features/observation/presentation/observation_page_test.dart
git commit -m "feat: integrate local recording navigation"
```

## Task 10: Verify Build, Platform Lifecycle, And Product Acceptance

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-08-21-evt-app-recording-product-design.md` only if implementation forces a product-approved design correction
- Test: all existing and newly added tests

- [ ] **Step 1: Document completed local capability without changing scope**

Add this concise README capability statement after the evidence feature description:

```markdown
- Phone-local recording: offline M4A capture, background/lock-screen continuity, local playback, rename, delete, and recovery. Device-owned recording and phone-local recording remain independent.
```

- [ ] **Step 2: Run complete static and automated verification**

Run:

```bash
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

Expected: formatter reports no changes, analyzer reports `No issues found!`, all tests pass, and the debug APK is generated.

- [ ] **Step 3: Run Android physical lifecycle verification**

On a physical Android device: grant microphone and notification permission; start local recording; background and lock for two minutes; confirm the microphone foreground-service notification remains visible; return and stop; play the result; repeat with a hardware VAD observation active; then interrupt with another recorder and verify an `interrupted` library row or explicit failure.

Expected: local capture survives background/lock, hardware flow continues independently, and the system-interruption result is truthful.

- [ ] **Step 4: Run iOS physical lifecycle verification**

On a physical iPhone: grant microphone permission; start local recording; lock for two minutes; unlock and stop; play the result; interrupt with a call or competing audio application; verify a truthful recovered result; repeat while a hardware observation is connected.

Expected: audio background mode maintains valid capture, interruption does not claim normal completion, and BLE state is unaffected.

- [ ] **Step 5: Commit completed feature and report evidence**

```bash
git add README.md docs/superpowers/specs/2026-08-21-evt-app-recording-product-design.md
git commit -m "docs: document local recording capability"
```

Report the exact automated command outputs, Android APK path, physical-device models/OS versions, permissions result, background/lock outcome, interruption outcome, and any residual platform limitation. Do not mark the feature complete without both platform lifecycle checks.

## Plan Self-review

- Scope coverage: Tasks 1-9 implement every approved local-recording requirement; Task 10 verifies the Android/iOS background and concurrent-hardware acceptance criteria.
- Existing boundaries: Tasks 8-9 preserve `RecordObservationSheet`, VAD observation, BLE state, and evidence records; no task sends a device recording command or stores local audio in evidence.
- Test coverage: each domain, persistence, file, controller, UI, shell, migration, and platform rule has a failing-test-first step or explicit physical verification where device behavior is the only meaningful evidence.
- Completeness check: no task depends on an unnamed file, unspecified package, or deferred product decision.
