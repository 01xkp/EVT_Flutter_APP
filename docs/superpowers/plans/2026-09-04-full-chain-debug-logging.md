# Full-Chain Debug Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Debug-build device operation diagnosable from its UI trigger through BLE/protocol/network/local-storage work, while producing a sanitized Android file visible at `Download/AIPIN/logs`.

**Architecture:** Keep the existing `SafeAppLogger -> PersistentAppLogger -> FileAppLogStore` ownership path, but evolve it into a structured diagnostic event pipeline. A `DiagnosticTrace` is created at a user-visible operation boundary and propagated into command, authentication, import, OTA, recording, and AI work. The canonical sanitized file remains in Application Support; a narrow platform sink mirrors that file to Android MediaStore without exposing raw data or allowing a logging failure to affect product behavior.

**Tech Stack:** Flutter, Dart, Riverpod, Flutter MethodChannel, Android Kotlin/MediaStore, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-04-full-chain-debug-logging-design.md`

## Global Constraints

- Debug builds only; do not add production telemetry or upload diagnostics to a server.
- Persist the same sanitized event content to the viewer, private file, Android public mirror, and exported file.
- Never persist ticket, proof, nonce, secret, token, raw BLE payload, audio, firmware, file/name-slot/path, complete device ID, complete URL/query, transcription, summary, or raw exception text.
- Use a per-install salted short reference for devices and an opaque random trace ID for correlation.
- Preserve current protocol behavior, the V2 `0x09` authentication envelope, and user-owned ASR changes.
- Android 10+ public output must be `Download/AIPIN/logs/aipin-YYYY-MM-DD.log` via MediaStore, with no broad-storage permission; iOS remains Application Support plus explicit export/share.
- Transfer diagnostics must aggregate on terminal marker, retry/failure, window, percentage change, or a bounded time interval; never log every `0x23`, `0x08`, or WQOTA data packet.
- Each observable logging behavior gets a focused regression test written and observed failing before its production implementation.

---

## File Structure

| Path | Responsibility |
| --- | --- |
| `lib/core/diagnostics/diagnostic_event.dart` | Immutable level/scope/trace/stage/result event schema and single-line renderer. |
| `lib/core/diagnostics/diagnostic_trace.dart` | Random trace creation, parent linkage, elapsed-time calculation, and safe operation metadata. |
| `lib/core/diagnostics/diagnostic_install_identity.dart` | Creates and persists a per-install opaque salt, then derives short non-reversible device references. |
| `lib/core/diagnostics/diagnostic_sanitizer.dart` | Recursive allowlist/redaction boundary used before all diagnostic sinks. |
| `lib/core/diagnostics/diagnostic_failure.dart` | Converts an exception into stable safe type/code/status fields without retaining raw text. |
| `lib/features/device_logs/domain/public_diagnostic_log_sink.dart` | Platform-neutral contract and mirror status model. |
| `lib/features/device_logs/data/platform_public_diagnostic_log_sink.dart` | MethodChannel-backed Android mirror and no-op iOS/desktop behavior. |
| `lib/features/device_logs/data/file_app_log_store.dart` | Canonical rolling file, bounded viewer, serialized mirror queue, and mirror status. |
| `android/app/src/main/kotlin/com/aigutta/aipin/MainActivity.kt` | `MediaStore.Downloads` copy implementation for the canonical sanitized file. |
| Existing controllers/repositories | Create or propagate traces and emit semantic events at their existing business boundaries. |

### Task 1: Establish Structured, Sanitized Diagnostic Events

**Files:**
- Create: `lib/core/diagnostics/diagnostic_event.dart`
- Create: `lib/core/diagnostics/diagnostic_trace.dart`
- Create: `lib/core/diagnostics/diagnostic_install_identity.dart`
- Create: `lib/core/diagnostics/diagnostic_sanitizer.dart`
- Create: `lib/core/diagnostics/diagnostic_failure.dart`
- Modify: `lib/core/diagnostics/diagnostic_exporter.dart`
- Modify: `lib/core/diagnostics/safe_app_logger.dart`
- Modify: `lib/features/device_logs/application/app_log_logger.dart`
- Modify: `lib/features/device_logs/domain/app_log_entry.dart`
- Modify: `lib/features/device_logs/domain/app_log_store.dart`
- Create: `test/core/diagnostics/diagnostic_sanitizer_test.dart`
- Modify: `test/core/diagnostics/diagnostic_exporter_test.dart`
- Modify: `test/core/diagnostics/safe_app_logger_test.dart`
- Modify: `test/features/device_logs/data/file_app_log_store_test.dart`

**Interfaces:**
- Produces `DiagnosticInstallIdentity.loadOrCreate()` and `deviceReference(String)` using a persisted random salt plus a short HMAC-derived result; it never writes a physical device ID to disk. `DiagnosticTrace.start(operation:, origin:, deviceReference:)`, `DiagnosticTrace.child(operation:)`, and `DiagnosticEvent` carry `level`, `scope`, `trace`, `stage`, `result`, `elapsed`, and safe fields.
- Evolves `SafeAppLogger` with `info`, `warning`, and `error` methods that accept optional `trace`, `operation`, `stage`, `result`, `elapsed`, and `fields`, while preserving existing call sites that only use `info(event, fields:)`.
- `DiagnosticSanitizer.sanitize(scope:, fields:)` returns recursively safe primitive/map/list values; it never throws.

- [ ] **Step 1: Write failing sanitizer tests.** Cover nested maps/lists containing `ticket`, `proof`, `nonce`, `token`, `authorization`, URL/query, raw payload/audio/firmware bytes, filename/path/name slot, raw error string, and full device ID. Assert that safe command/action/offset/length/status fields survive, that the same device maps to the same non-reversible reference across store reinitialization, and that no blocked source literal appears in `DiagnosticEvent.formatLine()`.

- [ ] **Step 2: Run the focused test to verify RED.**

  Run: `flutter test test/core/diagnostics/diagnostic_sanitizer_test.dart`

  Expected: FAIL because the structured sanitizer/event APIs do not exist.

- [ ] **Step 3: Implement the smallest immutable event and sanitizer contract.** Use an allowlist per scope plus a global blocked-key/value policy. Render a stable line in this order: timestamp, level, scope, trace_id, operation, stage, event, result, elapsed_ms, normalized fields. Map errors only to `error_type`, `error_code`, `gatt_status`, `http_status`, and `stage`; do not interpolate original exception strings.

- [ ] **Step 4: Make `PersistentAppLogger` create the event and make `AppLogStore` persist it.** Convert the existing entry model without breaking its stream/list viewer contract. Keep `info` source compatibility, add warning/error levels, and route every event through sanitizer before any output. Update `DebugSafeAppLogger` and `DiagnosticExporter` to use the same sanitizer, so neither Logcat nor an explicit debug export becomes a raw-data bypass.

- [ ] **Step 5: Run the focused tests to verify GREEN.**

  Run: `flutter test test/core/diagnostics/diagnostic_sanitizer_test.dart test/features/device_logs/data/file_app_log_store_test.dart`

  Expected: PASS; an intentional mutation that bypasses recursive sanitization makes the new test fail.

### Task 2: Add Canonical Log Mirroring and Android Public Storage

**Files:**
- Create: `lib/features/device_logs/domain/public_diagnostic_log_sink.dart`
- Create: `lib/features/device_logs/data/platform_public_diagnostic_log_sink.dart`
- Modify: `lib/features/device_logs/data/file_app_log_store.dart`
- Modify: `lib/features/device_logs/domain/app_log_store.dart`
- Modify: `lib/app/providers.dart`
- Modify: `android/app/src/main/kotlin/com/aigutta/aipin/MainActivity.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `test/features/device_logs/data/platform_public_diagnostic_log_sink_test.dart`
- Modify: `test/features/device_logs/data/file_app_log_store_test.dart`

**Interfaces:**
- `PublicDiagnosticLogSink.mirrorCanonicalFile({required String sourcePath, required String filename})` returns `PublicDiagnosticLogMirrorStatus` with `available`, `relativePath`, `lastUpdatedAt`, and normalized `failureCode`.
- `FileAppLogStore` accepts an optional public sink, exposes `publicMirrorStatus`, and serializes/debounces mirror calls to at most one per second; `flush()` forces the current queued mirror.
- Method channel name: `aipin/public_diagnostic_logs`; method: `mirrorCanonicalLog`; arguments: `sourcePath`, `filename`.

- [ ] **Step 1: Write failing store tests.** Use a fake public sink to prove that a completed canonical write creates exactly `aipin-2026-09-01.log`, debounces rapid events, flushes on demand, retains the private file when mirroring fails, and leaves the operation that emitted the log successful.

- [ ] **Step 2: Write a failing platform-boundary test.** Assert Android target behavior receives the source path plus exact filename and reports `Download/AIPIN/logs/aipin-2026-09-01.log`; assert non-Android uses a no-op status and never attempts a channel call.

- [ ] **Step 3: Run focused tests to verify RED.**

  Run: `flutter test test/features/device_logs/data/file_app_log_store_test.dart test/features/device_logs/data/platform_public_diagnostic_log_sink_test.dart`

  Expected: FAIL because the public sink and status APIs do not exist.

- [ ] **Step 4: Implement the Dart mirror boundary and file-store queue.** The store reads only its canonical already-sanitized file, records bounded `STORAGE` mirror outcomes without recursively re-mirroring those outcome events, and never lets I/O, serialization, permission, or channel errors escape to a caller.

- [ ] **Step 5: Implement Android MediaStore handling.** For API 29+, create or replace the `DISPLAY_NAME` in `MediaStore.Downloads` using `RELATIVE_PATH=Download/AIPIN/logs`, `MIME_TYPE=text/plain`, `IS_PENDING`, and a stream copy from a path verified to be inside the app files directory. For API 28 and below, use the compatible Downloads directory only after confirming legacy permission where required. Return only the public relative path and status; never return/copy file contents through Dart.

- [ ] **Step 6: Run focused tests to verify GREEN and format native/Dart changes.**

  Run: `flutter test test/features/device_logs/data/file_app_log_store_test.dart test/features/device_logs/data/platform_public_diagnostic_log_sink_test.dart`

  Expected: PASS; fake-mirror failure leaves the private-file assertion intact.

### Task 3: Add Command and Authentication Trace Diagnostics

**Files:**
- Modify: `lib/core/protocol/evt_command_client.dart`
- Modify: `lib/core/ble/reactive_ble_transport.dart`
- Modify: `lib/features/device_discovery/application/discovery_controller.dart`
- Modify: `lib/features/device_session/data/device_protocol_repository.dart`
- Modify: `lib/features/device_session/application/device_auth_controller.dart`
- Modify: `lib/features/device_session/application/session_controller.dart`
- Modify: `lib/features/device_session/data/https_ticket_gateway.dart`
- Modify: `lib/features/device_session/data/unconfigured_ticket_gateway.dart`
- Modify: `lib/app/app_shell.dart`
- Modify: `lib/app/providers.dart`
- Modify: `test/core/protocol/evt_command_client_test.dart`
- Modify: `test/core/ble/reactive_ble_transport_test.dart`
- Modify: `test/features/device_discovery/application/discovery_controller_test.dart`
- Modify: `test/features/device_session/application/device_auth_controller_test.dart`
- Modify: `test/features/device_session/data/https_device_gateways_test.dart`

**Interfaces:**
- `EvtCommandRequest` gains optional `DiagnosticTrace? trace` and `String? operation`; `EvtCommandClient` accepts an optional `SafeAppLogger`.
- `DeviceAuthController` accepts a logger/trace factory and exposes no raw exception values in logs.
- UI creates a top-level trace for bind/auth/clear and passes it through controller/session calls; command request logs retain that exact `trace_id`.
- `DiagnosticTrace.run` installs a zone-local trace for scan/connect/session work, and `PersistentAppLogger` resolves explicit trace first, then the zone trace. This lets existing `ReactiveBleTransport` events inherit the scan or connection trace without placing a physical device ID in the log.

- [ ] **Step 1: Write a failing command lifecycle test.** Execute a request with a trace through fake BLE and assert `CMD` records enqueue, encoded request length, expected response identity, write completion, matched response, elapsed time, and terminal success. Add a timeout/retry test that asserts two attempts and a stable timeout code, with no encoded raw frame in any event.

- [ ] **Step 2: Write a failing authentication configuration test.** Invoke bind with `UnconfiguredTicketGateway` and assert an `AUTH` event records `ticket_configuration`, `failure`, and `ticket_service_unconfigured` before the controller throws. Assert no `0x09` command write exists in the fake transport.

- [ ] **Step 3: Write failing scan/connect trace tests.** Start a scan and a connection through existing fake transport/controller fixtures. Assert the user-visible `UI`, `BLE`, and `SESSION` start/terminal events share one trace per operation and that the logged device reference is not the physical BLE identifier.

- [ ] **Step 4: Run focused tests to verify RED.**

  Run: `flutter test test/core/protocol/evt_command_client_test.dart test/core/ble/reactive_ble_transport_test.dart test/features/device_discovery/application/discovery_controller_test.dart test/features/device_session/application/device_auth_controller_test.dart test/features/device_session/data/https_device_gateways_test.dart`

  Expected: FAIL because lifecycle events and trace propagation do not yet exist.

- [ ] **Step 5: Implement scan/connect and command diagnostics.** Wrap user-triggered discovery and connection in `DiagnosticTrace.run`; existing transport logger automatically resolves the active trace. Log safely decoded command/action/subcommand/sequence/characteristic suffix/request length, matching decision, retry, timeout, decode rejection, transport failure, and total duration. Streaming commands emit start, aggregate terminal/failure, and cancellation only; they do not log every data frame.

- [ ] **Step 6: Implement authentication/session/UI diagnostics.** Log ticket service selection, request response status/schema, V2 bind/auth action, challenge/proof validation outcome, grant result, post-auth synchronization, clear preflight/confirm/poll/expiration, phase changes, and the corresponding toast/result. Normalize all catches through `DiagnosticFailure`; keep current user-facing wording.

- [ ] **Step 7: Run focused tests to verify GREEN.**

  Run: `flutter test test/core/protocol/evt_command_client_test.dart test/core/ble/reactive_ble_transport_test.dart test/features/device_discovery/application/discovery_controller_test.dart test/features/device_session/application/device_auth_controller_test.dart test/features/device_session/data/https_device_gateways_test.dart`

  Expected: PASS; changing the command matcher or suppressing the `AUTH` configuration event makes a new test fail.

### Task 4: Instrument File Import and WQOTA Without Packet Flooding

**Files:**
- Modify: `lib/features/device_session/data/device_file_import_service.dart`
- Modify: `lib/features/device_session/data/https_archive_gateway.dart`
- Modify: `lib/features/device_session/application/wqota_update_controller.dart`
- Modify: `lib/features/device_session/data/wqota_ble_update_gateway.dart`
- Modify: `lib/core/protocol/wqota_client.dart`
- Modify: `lib/app/app_shell.dart`
- Modify: `test/features/device_session/data/device_file_import_service_test.dart`
- Modify: `test/features/device_session/application/wqota_update_controller_test.dart`
- Modify: `test/features/device_session/data/wqota_ble_update_gateway_test.dart`

**Interfaces:**
- `DeviceFileImportService.import` creates/accepts a `DiagnosticTrace` and emits only safe file correlation and byte/checkpoint/CRC/archive outcomes.
- `WqotaUpdateController.start` retains one trace through resume/reconnect verification; `WqotaBleUpdateGateway` reports only window aggregates.

- [ ] **Step 1: Write failing import lifecycle tests.** Simulate a resumable import and assert ordered `FILE` events: checkpoint restored/created, requested offset, aggregate byte progress, CRC pass/fail, archive HTTP status, device archive confirmation, checkpoint clear, and terminal success/failure. Assert raw file bytes, filename, local path, and full checksum never appear.

- [ ] **Step 2: Write failing OTA lifecycle tests.** Execute a multi-window upgrade and assert `OTA` package validation, MTU decision, enter-update, one aggregate event per window, checkpoint, image verification, reboot, reconnect-version verification, cancel/failure cleanup, and terminal result. Assert that firmware bytes and package URL/hash do not appear.

- [ ] **Step 3: Run focused tests to verify RED.**

  Run: `flutter test test/features/device_session/data/device_file_import_service_test.dart test/features/device_session/application/wqota_update_controller_test.dart test/features/device_session/data/wqota_ble_update_gateway_test.dart`

  Expected: FAIL because the semantic log lifecycle is absent.

- [ ] **Step 4: Implement import diagnostics.** Emit a start and terminal event, then only progress percentage changes, retries, checkpoint state, CRC result, archive response, and device confirmation. Replace page-level swallowed import errors with safe UI failure logging while preserving the current recovery UI.

- [ ] **Step 5: Implement OTA diagnostics.** Add trace-aware phase events to controller and window-level metrics in the gateway/client. Represent serial, opcode, window offset, length, block count, total bytes, and CRC outcome only. Do not emit one event per E5 block or raw response body.

- [ ] **Step 6: Run focused tests to verify GREEN.**

  Run: `flutter test test/features/device_session/data/device_file_import_service_test.dart test/features/device_session/application/wqota_update_controller_test.dart test/features/device_session/data/wqota_ble_update_gateway_test.dart`

  Expected: PASS; packet-per-block logging or leaked file data makes the test fail.

### Task 5: Instrument Local Recording, AI Processing, and UI Failure Boundaries

**Files:**
- Modify: `lib/features/local_recording/application/recording_controller.dart`
- Modify: `lib/features/local_recording/data/record_audio_recorder.dart`
- Modify: `lib/features/research_beta/application/research_capture_processing_controller.dart`
- Modify: `lib/features/research_beta/data/temporary_asr_http_gateway.dart`
- Modify: `lib/app/app_shell.dart`
- Modify: `lib/app/providers.dart`
- Modify: `lib/main.dart`
- Modify: `test/features/local_recording/application/recording_controller_test.dart`
- Modify: `test/features/research_beta/application/research_capture_processing_controller_test.dart`
- Create: `test/core/diagnostics/app_exception_reporter_test.dart`

**Interfaces:**
- Recording/AI controllers receive a scoped logger and trace factory through existing providers.
- Global Flutter, platform-dispatcher, and zone errors are passed to one `AppExceptionReporter` that creates a sanitized `UI`/`STORAGE` event without affecting existing error presentation.

- [ ] **Step 1: Write failing recording and AI lifecycle tests.** Assert one local-recording trace covers permission decision, foreground-service lifecycle, start/pause/resume/interruption/save/discard/error; assert AI trace covers selection, segment count/duration only, upload/job/poll/retry/state transitions/summary/terminal result. Assert no recording path, audio, transcript, summary, job ID, or raw URL is retained.

- [ ] **Step 2: Write a failing unhandled-error boundary test.** Send an exception containing a URL and a sensitive-looking token into the reporter and assert a structured error event records type/stage but not its source string.

- [ ] **Step 3: Run focused tests to verify RED.**

  Run: `flutter test test/features/local_recording/application/recording_controller_test.dart test/features/research_beta/application/research_capture_processing_controller_test.dart test/core/diagnostics/app_exception_reporter_test.dart`

  Expected: FAIL because controllers and global boundaries have no diagnostics contract.

- [ ] **Step 4: Implement recording and AI semantic events.** Preserve existing product state and polling behavior. Emit safe operation progress at meaningful stage changes only; use a stable error code for unavailable service, upload failure, polling timeout, and summary failure instead of exception strings.

- [ ] **Step 5: Install the global reporter in `main.dart`.** Build the provider container before `runApp`, register `FlutterError.onError`, `PlatformDispatcher.instance.onError`, and `runZonedGuarded`, then keep Flutter's normal debug presentation. Flush diagnostics on app pause/detach through a lifecycle observer.

- [ ] **Step 6: Run focused tests to verify GREEN.**

  Run: `flutter test test/features/local_recording/application/recording_controller_test.dart test/features/research_beta/application/research_capture_processing_controller_test.dart test/core/diagnostics/app_exception_reporter_test.dart`

  Expected: PASS; dropping an AI terminal event or logging a raw exception makes a new test fail.

### Task 6: Upgrade the Real-Time Log Viewer and Export Behavior

**Files:**
- Modify: `lib/features/device_logs/presentation/device_log_page.dart`
- Modify: `lib/features/device_logs/application/app_log_controller.dart`
- Modify: `lib/app/app_shell.dart`
- Modify: `test/features/device_logs/presentation/device_log_page_test.dart`
- Create: `test/features/device_logs/application/app_log_controller_test.dart`

**Interfaces:**
- Viewer consumes structured `AppLogEntry` fields and supports scope/severity filters, trace-ID text search, copying visible trace lines, private path, Android public path, mirror status, and daily-file export.
- `clearView()` remains memory-only and cannot delete private/public diagnostics.

- [ ] **Step 1: Write failing widget/controller tests.** Seed events from two traces and scopes; assert filters isolate one trace, copy uses only visible sanitized lines, private/public path state renders, and clearing the viewer leaves `exportPath()` readable.

- [ ] **Step 2: Run focused tests to verify RED.**

  Run: `flutter test test/features/device_logs/presentation/device_log_page_test.dart test/features/device_logs/application/app_log_controller_test.dart`

  Expected: FAIL because the page has no filter/mirror-status/copy contract.

- [ ] **Step 3: Implement the compact viewer controls.** Keep the current visual language and auto-follow control. Use filters rather than a second persistent store, and report export/mirror errors through sanitized `STORAGE` events plus short existing-style UI feedback.

- [ ] **Step 4: Run focused tests to verify GREEN.**

  Run: `flutter test test/features/device_logs/presentation/device_log_page_test.dart test/features/device_logs/application/app_log_controller_test.dart`

  Expected: PASS; a clear operation that deletes the canonical file makes the test fail.

### Task 7: Format, Verify, and Exercise the Debug Artifact

**Files:**
- Verify: all files modified by Tasks 1-6.
- Modify only if verification exposes a directly related defect.

- [ ] **Step 1: Format all touched Dart files and run static analysis.**

  Run: `dart format lib/core/diagnostics lib/core/ble/reactive_ble_transport.dart lib/core/protocol/evt_command_client.dart lib/core/protocol/wqota_client.dart lib/features/device_logs lib/features/device_discovery/application/discovery_controller.dart lib/features/device_session/application lib/features/device_session/data lib/features/local_recording/application/recording_controller.dart lib/features/local_recording/data/record_audio_recorder.dart lib/features/research_beta/application/research_capture_processing_controller.dart lib/features/research_beta/data/temporary_asr_http_gateway.dart lib/app/app_shell.dart lib/app/providers.dart lib/main.dart test/core/diagnostics test/core/ble/reactive_ble_transport_test.dart test/core/protocol/evt_command_client_test.dart test/features/device_logs test/features/device_discovery/application/discovery_controller_test.dart test/features/device_session/application test/features/device_session/data test/features/local_recording/application/recording_controller_test.dart test/features/research_beta/application/research_capture_processing_controller_test.dart` then `flutter analyze --no-fatal-infos`

  Expected: no analyzer errors and no formatting diff for touched Dart files.

- [ ] **Step 2: Run the focused logging suites and then the full suite.**

  Run: `flutter test test/core/diagnostics test/core/protocol/evt_command_client_test.dart test/features/device_logs test/features/device_session/application/device_auth_controller_test.dart test/features/device_session/data/device_file_import_service_test.dart test/features/device_session/application/wqota_update_controller_test.dart test/features/local_recording/application/recording_controller_test.dart test/features/research_beta/application/research_capture_processing_controller_test.dart` then `flutter test`

  Expected: every command exits `0`.

- [ ] **Step 3: Build a Debug Android APK.**

  Run: `flutter build apk --debug`

  Expected: successful APK build with the Android MediaStore implementation compiled.

- [ ] **Step 4: Perform the device acceptance check.** Install/run the Debug build, trigger a failed bind without `DEVICE_TICKET_API_BASE_URL`, then inspect `Download/AIPIN/logs/aipin-YYYY-MM-DD.log` in the device file manager. Confirm it includes UI/AUTH evidence, indicates ticket-service configuration failure before a `0x09` write, and contains no ticket, URL, device ID, or raw error content.

- [ ] **Step 5: Run final hygiene checks.**

  Run: `git diff --check` and `git status --short`

  Expected: no whitespace errors; report only files changed by this feature and preserve unrelated user changes.
