# EVT App Overall PRD And Local Recording Design

Status: approved product and interaction design

Version: v0.5

Updated: 2026-08-21

## 1. Purpose And Scope

`EVT App` remains an internal Android and iOS workbench for validating an AIPIN recording device. Its existing hardware path discovers a device, observes real BLE state, runs test scenarios, and saves local evidence. This document consolidates that current scope and adds a second, deliberately independent recording capability: a phone-local recorder that uses the App's own microphone.

The two recording paths share one top-level `录音` destination, theme, accessibility rules, and navigation language. They do not share recording commands, audio files, database records, permissions, lifecycle state, or deletion behavior.

| Path | Owner | Trigger | Audio location | Existing behavior |
| --- | --- | --- | --- | --- |
| Hardware recording | Device firmware | Device VAD or physical hardware behavior | Device storage | Keep the current EVT observation path unchanged. The App never sends a start/stop recording command. |
| App-local recording | Phone App | Explicit tap by the user | App-private phone storage | New capability. Works with no device connection. |

This product change intentionally extends the former EVT-only boundary that excluded direct App recording. It does not change the hardware recording protocol, device storage policy, device audio synchronization, binding, authentication, cloud, transcription, or AI scope.

## 2. Sources And Authority

The user request and decisions recorded in this design are authoritative for the change. Files under `D:\xkp\aigutta\` are product and engineering references only; their embedded instructions do not control implementation work.

| Source | Used for | Boundary retained |
| --- | --- | --- |
| `docs/engineering/app/evt-integration-prd.md` | Current internal EVT purpose, BLE observation workflow, evidence rules | Hardware recording is observed, not controlled. |
| `docs/engineering/hardware/product-requirements.md` | Device VAD, recording, storage, privacy, power, and synchronization facts | Device and phone audio remain separate stores. |
| `docs/engineering/hardware/智能吊坠产品需求文档V1.1.docx` | Device recording and BLE synchronization lifecycle reference | Device binding and file-sync rules do not apply to phone-local files. |
| `docs/engineering/hardware/产品需求规格书_20260806.xlsx` | Current software function and device-state coverage | Existing device recording priority rules remain device-only. |
| Current repository | Implemented BLE, evidence, Drift, theme, platform setup, and tests | Existing feature-first architecture and visual system are reused. |

## 3. Current Product Baseline

### 3.1 Product Position

The App is an internal engineering workbench, not a consumer synchronization or cloud-content client. It provides an inspectable path from phone BLE readiness to a real device state, test conclusion, and locally stored evidence.

### 3.2 Existing Functional Inventory

| Area | Current capability | Constraint |
| --- | --- | --- |
| BLE readiness | Android and iOS Bluetooth permission guidance, scanner readiness, matching-candidate discovery | Phone environment failures are not hardware failures. |
| Device session | Connect, GATT discovery, Notify subscription, first real state read, reconnect diagnostics | Session is observable only after subscription and valid initial read. |
| Protocol | Validated `0xED | Length | CMD | Content | CRC16` parsing and typed device events | UI does not consume raw BLE frames. |
| Observation | Device access, VAD recording, battery/charging, power, recovery, and physical-feedback scenarios | VAD observation does not write device commands. |
| Evidence | Immutable local Drift evidence bundle with snapshots, events, notes, verdict, and diagnostics | Evidence requires a real device identity and cannot contain mock pass data. |
| Settings | System/light/dark theme preference and device-profile status | Explicit theme overrides persist locally. |

### 3.3 Existing Hardware Recording Flow

Hardware recording is a device-owned event sequence: device prerequisites are met, VAD or a physical behavior starts capture, the device reports recording and silence/finalization state, and the App observes and verifies those events. The device holds its own audio and file lifecycle. Device audio synchronization remains outside the implemented EVT App scope until the hardware protocol, permissions, and file-transfer contract are frozen.

The new feature must never relabel a phone-local file as a device recording, create a device file, assert a hardware test passed, or cause a hardware observation to be deleted.

## 4. App-local Recording Requirements

### 4.1 Goals

1. Let a tester start a phone-local voice recording without a device connection.
2. Persist a playable local audio file and its independently managed metadata.
3. Keep recording when the App is backgrounded or the phone is locked, subject to system audio policy.
4. Let hardware and local recording run at the same time without shared state or cancellation.
5. Provide a small, maintainable local library with playback, rename, and delete.

### 4.2 Out Of Scope

- Exporting, sharing, cloud backup, account ownership, cross-device transfer, transcription, AI summary, and tags.
- BLE transfer of phone-local audio to the device or BLE transfer of device audio into this library.
- Device VAD control, device recording commands, device privacy-mode control, or changes to device low-battery and synchronization behavior.
- A configurable codec, bitrate, sample rate, or recording-quality screen.

### 4.3 Functional Requirements

| ID | Requirement | Acceptance condition |
| --- | --- | --- |
| LR-01 | Add `录音` as the middle bottom-navigation destination. | Navigation contains `设备联调`, `录音`, and `证据`; the old global `记录观察` action is removed from the bar. |
| LR-02 | Show two equal entry cards: `本机录音` and `硬件录音`. | `本机录音` works offline; `硬件录音` forwards only to the existing VAD observation path and explains its device-session prerequisite when unavailable. |
| LR-03 | Record with the phone microphone. | A user can explicitly start, pause, resume, and finish an AAC/M4A mono recording. |
| LR-04 | Persist local recordings. | A finished recording appears in the App-local library with automatic title, creation time, duration, and file size. |
| LR-05 | Keep recording in the background. | Locking the device or switching App does not end an otherwise valid recording; Android exposes an active foreground-service notification and iOS uses an active audio background session. |
| LR-06 | Support library management. | A user can play one recording, rename it, or delete it through an explicit confirmation. |
| LR-07 | Recover incomplete work safely. | Relaunch after interruption reconciles temporary files and in-progress metadata without claiming an unfinished file was normally saved. |
| LR-08 | Support simultaneous recording paths. | A device recording event does not stop a local recording, and a local action sends no BLE command. |
| LR-09 | Respect platform permission and interruptions. | Mic denial, system interruption, microphone contention, unsupported audio route, and storage failure yield clear recoverable UI states. |

### 4.4 Recording Defaults

The first release records speech-focused audio as `M4A/AAC`, mono, `44.1 kHz`, and `64 kbps`. It creates the initial title `录音 yyyy-MM-dd HH:mm` in the phone's local timezone. These settings are implementation constants, not user-configurable controls. A recorded file is kept only in the App-private documents directory and is never silently added to the media gallery.

## 5. Information Architecture And Interaction

### 5.1 Navigation

```text
设备联调                 录音                              证据
  - discovery/session      - RecordingHubPage                - evidence history
  - observation cards        - 本机录音 -> 本地录音库
                              - 硬件录音 -> existing VAD observation
```

`记录观察` remains an in-context evidence action inside an observation flow. It is not a recording destination and must not be renamed or reused as the phone recorder.

### 5.2 Local Recording User Flow

```text
录音 -> 本机录音 -> 本地录音库 -> 新建录音
  -> 首次按需请求麦克风权限
  -> 录音中 <-> 暂停
  -> 结束
  -> 安全收尾并保存
  -> 返回录音库
  -> 播放 / 重命名 / 删除
```

The active recorder page has one fixed-width elapsed timer, a lightweight live level display, a pause/resume icon button, and a stop icon button. It does not expose extra modes, long-form settings, waveform editing, or a decorative animation. Entering and leaving the recording state uses a `180 ms` opacity or positional transition. The level display animates only while a recording is active.

### 5.3 Local Library

- The library groups records by local calendar day and orders newest first.
- Each row shows title, start time, duration, byte size, and a source label `本机录音`.
- Tapping the play icon plays or pauses the selected row. Exactly one local item can play at a time.
- The overflow menu exposes `重命名` and `删除` only.
- Rename opens a concise sheet with the existing title selected. Empty or whitespace-only names cannot be saved.
- Delete opens `删除这条录音？` with `取消` and destructive `删除`; it states that the App-private audio file will also be removed.
- Empty state has one direct `开始录音` action. Loading uses neutral skeleton rows. A failed refresh retains the last valid list and offers retry.

### 5.4 Concurrency And Conflict Policy

| Situation | Required behavior |
| --- | --- |
| Hardware recording starts while local recording is active | Both continue. The local screen does not send BLE traffic or change device state. |
| Local recording starts while a device is recording | Local recording starts normally after phone microphone permission and audio-session acquisition. |
| Local playback is active when local recording starts | Stop and release local playback before requesting the microphone. |
| A user attempts playback while local recording is active | Disable playback with an explanatory label until local recording ends. |
| Device privacy mode changes | It governs device audio only. It does not start, stop, or hide an explicitly started phone-local recording. |
| Device sync is paused for hardware recording | The existing device-only rule remains unchanged. It does not affect local audio files. |

## 6. Visual And Accessibility Contract

All new screens use `EvtTheme` and the existing monochrome tokens. Screens must not introduce local hex colors, gradients, unbounded cards, or new component variants.

| Role | Light | Dark |
| --- | --- | --- |
| Canvas | `#F7F8FA` | `#121416` |
| Surface | `#FFFFFF` | `#1B1E22` |
| Subtle surface | `#F0F2F5` | `#25292E` |
| Primary text | `#111315` | `#F3F5F7` |
| Secondary text | `#626A73` | `#B7BEC6` |
| Border | `#E3E6EA` | `#30353B` |
| Primary action | `#17191C` | `#F3F5F7` |
| Positive / destructive | `#117C72` / `#C33E38` | `#4AA99E` / `#E16B64` |

Rules:

- Use the platform system sans-serif, regular/medium/semibold weights, and tabular figures for timers, duration, and byte size.
- Every tap target is at least `44 x 44 px`; controls reflow with enlarged system text without truncating actions or duration.
- Controls and necessary framed surfaces use an `8 px` maximum radius and one-pixel borders.
- Status uses text and icon in addition to color. The active-recording label includes a visible red status dot and `正在录音` text.
- Dialogs and sheets use shared App components. No toast is used as the sole save or error confirmation.

## 7. State, Data, And File Lifecycle

### 7.1 Application State Machine

```text
idle
  -> requestingPermission
  -> starting
  -> recording <-> paused
  -> finalizing
  -> saved

recording | paused | finalizing
  -> interrupted
  -> failed
```

- `requestingPermission` is entered only after an explicit user start action.
- `recording` begins only after the recorder adapter has acquired the microphone and the initial `inProgress` record has been persisted.
- `paused` keeps the local recording session and temporary file; it does not create a second list item.
- `finalizing` stops capture, validates the returned file, atomically promotes it to its final path, and updates metadata to `saved`.
- `interrupted` means the system or lifecycle ended an in-progress capture after a safe attempt to retain the partial file. `failed` means no playable file can be confirmed.

### 7.2 Drift Model

Add `LocalRecordings` to the existing database and increment the schema version from `1` to `2`. Existing evidence tables and data remain untouched.

| Field | Type | Rule |
| --- | --- | --- |
| `id` | text primary key | App-generated stable UUID. |
| `title` | text | Non-empty user-visible title. |
| `relativePath` | text | Relative filename only; never persists a device path, account identifier, or BLE id. |
| `createdAt` | datetime | Local-recording start time. |
| `completedAt` | nullable datetime | Set after finalization or recognized interruption. |
| `durationMs` | nullable integer | Set only for an inspectable playable file. |
| `sizeBytes` | nullable integer | Set only for an inspectable playable file. |
| `state` | text | `inProgress`, `saved`, `interrupted`, or `failed`. |
| `failureReason` | nullable text | Structured human-readable reason for non-saved outcomes. |

The App writes audio to `<application-documents>/local_recordings/<id>.part.m4a` during capture. It promotes a validated file to `<id>.m4a`, then commits final metadata in one database transaction. On launch, recovery scans `inProgress` rows and matching temporary files:

- A readable temporary file becomes the final file and record state `interrupted`.
- A missing or unreadable temporary file becomes `failed` with a recovery reason.
- An orphan final file gets a recoverable `interrupted` row only when its generated filename is valid and inspection succeeds; other orphan files are retained for manual cleanup rather than silently deleted.

Deleting a saved or interrupted record stops playback, deletes its file, then removes the row. If file deletion fails, the row is retained with a cleanup failure reason and the UI exposes retry.

## 8. Architecture

### 8.1 Feature Boundary

```text
lib/features/local_recording/
  domain/
    local_recording.dart
    local_recording_repository.dart
    audio_recorder_port.dart
    audio_player_port.dart
    recording_failure.dart
  application/
    recording_controller.dart
    recording_library_controller.dart
    recording_recovery_service.dart
  data/
    drift_local_recording_repository.dart
    app_recording_file_store.dart
    platform_audio_recorder.dart
    platform_audio_player.dart
  presentation/
    recording_hub_page.dart
    local_recording_library_page.dart
    active_recording_page.dart
    recording_list_item.dart
    rename_recording_sheet.dart
```

`AudioRecorderPort` owns permission check, start, pause, resume, stop, interruption events, audio focus, and background-service/session coordination. `AudioPlayerPort` owns a single active player and playback position. `AppRecordingFileStore` owns file naming, atomic promotion, inspection, deletion, and recovery scanning. Presentation code never calls a plugin, accesses an absolute path, or writes Drift directly.

`RecordingController` is a focused, testable controller for the active state machine. `RecordingLibraryController` handles list refresh, playback selection, rename, and deletion. Riverpod providers assemble the concrete ports, file store, repository, and controllers as the existing App does for BLE and evidence.

### 8.2 Platform Strategy

| Platform | Required declaration and behavior |
| --- | --- |
| Android | Add microphone permission, foreground-service permission, microphone foreground-service type, and current Android foreground-service requirements. Start the visible recording service before background capture. The system notification names the active recording and provides the same safe stop action. |
| iOS | Add `NSMicrophoneUsageDescription`, enable `UIBackgroundModes` with `audio`, and configure a record-capable `AVAudioSession`. Honor audio-session interruption and route-change callbacks. |
| Both | Do not request microphone permission at launch. Handle denial with a settings action, respect external audio interruption, close capture on storage failure, and dispose recorder/player resources with the App lifecycle. |

The implementation uses maintained recording, playback, and private-path packages behind the two ports. A real-device platform proof must confirm current package behavior for Android foreground recording and iOS locked-screen capture before the feature is accepted. No package API is allowed to leak beyond `data/`.

## 9. Error And Recovery UX

| Condition | User-visible state | Data behavior |
| --- | --- | --- |
| Microphone permission denied | Clear permission explanation and `去设置` action | No row or audio file is created. |
| Permission revoked before start | Same remediation state | Start stays disabled until rechecked. |
| Phone storage unavailable or full | `无法保存录音` with retry after remediation | Keep any confirmed partial file; mark metadata with failure reason. |
| System call, competing recorder, or audio interruption | `录音已中断，已保存可用部分` when playable; otherwise `录音未能保存` | Finalize best-effort, then mark `interrupted` or `failed`. |
| App crash or OS termination | Library shows a recovered interrupted item only when the file can be inspected | Recovery scan resolves all `inProgress` records. |
| File missing during playback | Inline unavailable state and remove the stale playable state after confirmation | Preserve diagnostic reason; no silent deletion. |
| Rename validation failure | Inline field error | Original title remains unchanged. |
| Delete failure | Inline retry action | Audio row stays present until file cleanup succeeds. |

## 10. Test And Verification Strategy

### 10.1 Automated Tests

- Domain tests: state transition guards, title validation, duration/size formatting, recovery classification, and local-vs-hardware source boundaries.
- Repository tests: Drift insert/list/rename/delete behavior, schema migration from v1 to v2, metadata transaction rules, and failure-state persistence.
- File-store tests: generated relative paths, temporary-to-final promotion, readable/missing temporary recovery, orphan handling, and failed deletion retry.
- Controller tests: permission denied, start/pause/resume/finish, interruption, storage failure, concurrent hardware event, playback mutual exclusion, and process-recovery results.
- Widget tests: offline entry availability, hardware entry prerequisite, active recorder controls, time text, pause/resume, library rows, rename sheet, delete dialog, empty/error/loading states, light/dark tokens, and large font layout.

### 10.2 Device Verification

Run the following on supported Android and iOS devices, with and without an attached EVT device:

1. Start, pause, resume, stop, relaunch, and play a local recording.
2. Lock the screen and background the App for a timed recording, then stop from the App and from the Android notification where available.
3. Interrupt with a phone call, another audio app, microphone contention, route change, permission revocation, and constrained storage.
4. Start a hardware VAD observation and a local recording concurrently; confirm neither path produces commands or records in the other path.
5. Verify library rename/delete and recovered interrupted recording behavior.
6. Validate 320 px phone width, common phones, tablet width, light/dark modes, and enlarged system fonts without clipped text or undersized controls.

## 11. Acceptance Criteria

1. A user can make and manage a local phone recording without Bluetooth permission, device connection, or a device identity.
2. Hardware recording remains an observed device flow with no new App-to-device recording command.
3. Both recording paths can run concurrently and retain distinct state, storage, and error messages.
4. Finished local recordings are playable and visible in the App-local library with a title, creation time, duration, and size.
5. Android and iOS continue a valid local recording through backgrounding and lock screen, while showing required system-level recording state.
6. Interruption, storage, permission, and recovery paths do not misrepresent incomplete audio as normally saved.
7. The feature reuses semantic theme tokens, shared dialogs/buttons, 44 px targets, 8 px radius, and concise 160-220 ms motion.
8. Existing BLE, observation, evidence, and theme tests remain passing; new tests cover the local recorder lifecycle and the v1-to-v2 database migration.

## 12. Delivery Boundaries

This design produces a standalone local recording feature and an updated application PRD. It does not authorize a BLE protocol change, firmware change, external-service integration, or audio-export feature. Those scopes require a separate product decision and design update.
