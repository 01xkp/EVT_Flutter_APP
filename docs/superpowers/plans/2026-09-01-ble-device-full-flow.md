# BLE Device Full Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the firmware V1.5 App-device BLE workflow in the existing Flutter app, including protocol commands, device controls, file synchronization, WQOTA plumbing, and real-time/local Debug logs.

**Architecture:** Preserve the feature-first Riverpod architecture. Extend BLE primitives first, then add a serialized command client and typed device repository; presentation widgets consume immutable controller state. Keep ticket issuance, archive confirmation, and firmware distribution behind interfaces so missing external services are visible and cannot create false success.

**Tech Stack:** Flutter/Dart 3.12, `flutter_reactive_ble`, Riverpod, Drift, `path_provider`, `share_plus`, Flutter test.

**Spec:** `docs/superpowers/specs/2026-09-01-ble-device-full-flow-design.md`

## Global Constraints

- Business frames remain `[ED][Length LE][CMD][Content][CRC16 LE]`; CRC16 is CCITT-FALSE poly `0x1021`, init `0xFFFF`, no reflection.
- File names use exactly 16 ASCII bytes plus one NUL byte (`FileName[17]`); do not silently truncate or accept unsafe bytes.
- Indicate requests use a 2-second timeout and at most one retry; all per-device command requests are serialized.
- Authentication is required before sensitive configuration, file, unbind, or OTA operations; absent tickets show `认证服务未配置`.
- `ARCHIVE_CONFIRM` is sent only after a durable cloud archive callback; without it, downloaded files remain retained on the device.
- WQOTA is independent from the business frame and uses the documented packed prefix/flags, BE integer fields, CRC32, window, and resume rules.
- Logs redact device IDs, tickets, audio/file content, and firmware content; Debug files only, seven daily files, 5 MB rotation.
- UI uses existing semantic theme tokens, minimum 44 px targets, and Android/iOS platform behavior without raw plugin calls in widgets.

---

### Task 1: Freeze endpoint model and transport primitives

**Files:**
- Modify: `lib/core/ble/ble_models.dart`
- Modify: `lib/core/ble/ble_transport.dart`
- Modify: `lib/core/ble/device_profile.dart`
- Modify: `assets/config/device_profile.json`
- Modify: `lib/core/ble/reactive_ble_transport.dart`
- Test: `test/core/ble/ble_transport_contract_test.dart`
- Test: `test/core/ble/device_profile_test.dart`

**Interfaces:**
- Produce `BleOperation`, endpoint capability metadata, `BleTransport.write`, and `BleTransport.writeWithoutResponse`.
- Produce a typed logical endpoint map for FA10/FB10/FF10/WQOTA.

- [ ] Add failing contract tests for write, write-without-response, endpoint capability validation, and short UUID normalization.
- [ ] Run the focused tests and confirm they fail for the missing interface.
- [ ] Implement the smallest model/profile changes while keeping the old generic endpoint getters as compatibility adapters.
- [ ] Implement Reactive BLE writes with bounded timeout, redacted logs, and platform error mapping.
- [ ] Update the checked-in profile schema with documented logical endpoint keys, leaving unavailable production UUID values explicitly unconfigured.
- [ ] Run focused tests and `dart analyze`.
- [ ] Commit: `feat: extend BLE transport endpoint capabilities`.

### Task 2: Harden business frame codec and typed protocol primitives

**Files:**
- Modify: `lib/core/protocol/evt_protocol_codec.dart`
- Modify: `lib/core/protocol/evt_frame.dart`
- Create: `lib/core/protocol/protocol_reader.dart`
- Create: `lib/core/protocol/protocol_writer.dart`
- Create: `lib/core/protocol/crc32.dart`
- Modify: `lib/core/protocol/device_event.dart`
- Test: `test/core/protocol/evt_protocol_codec_test.dart`
- Create: `test/core/protocol/protocol_reader_test.dart`
- Create: `test/core/protocol/crc32_test.dart`

**Interfaces:**
- Produce strict `EvtProtocolCodec.encodeRequest`/decode behavior and reusable little-endian/fixed-slot readers.
- Produce CRC32/ISO-HDLC for file and WQOTA checks.

- [ ] Add failing vectors for truncated header, wrong declared length, extra bytes, invalid CRC, response result, and fixed 17-byte filename rules.
- [ ] Add failing CRC32 vector `123456789 = 0xCBF43926`.
- [ ] Implement validation before every field access and structured protocol failures.
- [ ] Implement typed readers/writers for u8/u16/u32/s32 LE and u16/u32 BE where explicitly required.
- [ ] Extend event classification for status, recording, audio, file metadata, and unknown commands without dropping payloads.
- [ ] Run protocol tests and `dart analyze`.
- [ ] Commit: `feat: add strict V1.5 protocol codecs`.

### Task 3: Add serialized command transaction client

**Files:**
- Create: `lib/core/protocol/evt_command_client.dart`
- Create: `lib/core/protocol/evt_command_transaction.dart`
- Modify: `lib/core/diagnostics/evt_failure.dart`
- Test: `test/core/protocol/evt_command_client_test.dart`
- Modify: `test/support/fake_ble_transport.dart`

**Interfaces:**
- `EvtCommandClient.execute(EvtCommandRequest request)` returns a typed `EvtCommandResponse`.
- `EvtCommandClient.events` publishes unmatched unsolicited frames.

- [ ] Add failing tests for command response matching, subcommand/SN matching, serialization, timeout, one retry, and disconnect failure.
- [ ] Implement a per-device queue that subscribes before sending and completes only on a validated matching response.
- [ ] Ensure retries reuse the same logical request but never complete twice; preserve diagnostics for mismatches.
- [ ] Wire transport errors to fail pending transactions and expose a resumable state to callers.
- [ ] Run focused tests and `dart analyze`.
- [ ] Commit: `feat: serialize BLE command transactions`.

### Task 4: Build typed device repository and session state machine

**Files:**
- Create: `lib/features/device_session/domain/device_capabilities.dart`
- Create: `lib/features/device_session/domain/device_info.dart`
- Create: `lib/features/device_session/domain/device_configuration.dart`
- Create: `lib/features/device_session/domain/device_file.dart`
- Create: `lib/features/device_session/domain/device_auth_state.dart`
- Create: `lib/features/device_session/data/device_protocol_repository.dart`
- Modify: `lib/features/device_session/application/session_state.dart`
- Modify: `lib/features/device_session/application/session_controller.dart`
- Test: `test/features/device_session/data/device_protocol_repository_test.dart`
- Test: `test/features/device_session/application/session_controller_test.dart`

**Interfaces:**
- Produce typed operations for 0x01/0x02/0x05/0x06/0x07/0x09/0x11/0x21/0x22/0x23/0x26.
- Produce explicit `authenticating`, `ready`, `syncing`, `recording`, `interrupted`, and `unconfigured` states.

- [ ] Add failing repository tests for each command's request payload and response field decoding.
- [ ] Add failing controller tests for connect -> discover -> subscribe-all -> info/auth/status restore and auth-gated controls.
- [ ] Implement endpoint subscription registration for every documented Indicate/Notify characteristic.
- [ ] Implement typed repository command methods with no raw bytes exposed to UI.
- [ ] Update session transitions so `ready` requires protocol version validation, subscriptions, and authoritative reads.
- [ ] Keep reconnect and disconnect cleanup from the existing fix, adding fresh snapshot reads after reconnect.
- [ ] Run session/repository tests and `dart analyze`.
- [ ] Commit: `feat: add typed device session workflow`.

### Task 5: Implement device information, configuration, and recording controls

**Files:**
- Create: `lib/features/device_session/application/device_control_controller.dart`
- Create: `lib/features/device_session/presentation/device_configuration_page.dart`
- Create: `lib/features/device_session/presentation/device_recording_panel.dart`
- Modify: `lib/features/device_session/presentation/device_detail_page.dart`
- Modify: `lib/app/app_shell.dart`
- Test: `test/features/device_session/application/device_control_controller_test.dart`
- Create: `test/features/device_session/presentation/device_configuration_page_test.dart`

- [ ] Add failing controller tests for time sync, recording parameter update, privacy duration, AudioStream toggle, start/stop recording, and finalizing state.
- [ ] Add widget tests for disabled unauthenticated controls and accessible loading/error states.
- [ ] Implement controller methods that call the typed repository and wait for matching 0x87/0x86 state.
- [ ] Add device page sections for firmware/protocol, battery/charging, storage, recording, configuration, and current errors while preserving existing layout.
- [ ] Keep local recording controls independent from device recording controls.
- [ ] Run focused tests and `dart analyze`.
- [ ] Commit: `feat: add device controls and recording status`.

### Task 6: Implement device file listing, metadata, download, resume, and archive gating

**Files:**
- Create: `lib/features/device_sync/domain/device_sync_job.dart`
- Create: `lib/features/device_sync/domain/device_sync_checkpoint.dart`
- Create: `lib/features/device_sync/domain/device_sync_repository.dart`
- Create: `lib/features/device_sync/data/drift_device_sync_repository.dart`
- Create: `lib/features/device_sync/application/device_sync_controller.dart`
- Create: `lib/features/device_sync/presentation/device_files_page.dart`
- Modify: `lib/core/persistence/app_database.dart`
- Modify: `lib/core/persistence/app_database.g.dart`
- Modify: `lib/app/providers.dart`
- Test: `test/features/device_sync/`

- [ ] Add failing tests for paged 0x22 parsing, 17-byte filename validation, 0x26 metadata, offset continuity, forced disconnect resume, CRC mismatch, and archive callback gating.
- [ ] Add the Drift table/migration for device file metadata and checkpoints without changing existing recording/research tables.
- [ ] Implement list -> metadata -> chunk download with bounded chunks and checkpoint persistence after confirmed responses.
- [ ] Validate local file size and CRC32 before marking playable; retain partial files only with an explicit resumable checkpoint.
- [ ] Add an `ArchiveGateway` interface; block 0x26 ARCHIVE_CONFIRM until it reports durable success and make the UI show retained state otherwise.
- [ ] Add file list and per-file progress/error/retry controls; route complete files into the existing playback detail flow.
- [ ] Run sync tests, Drift generation/checks, and `dart analyze`.
- [ ] Commit: `feat: add resumable device file synchronization`.

### Task 7: Add authentication and unbind ticket boundary

**Files:**
- Create: `lib/features/device_session/domain/ticket_gateway.dart`
- Create: `lib/features/device_session/data/unconfigured_ticket_gateway.dart`
- Create: `lib/features/device_session/application/device_auth_controller.dart`
- Modify: `lib/app/providers.dart`
- Modify: `lib/features/device_session/presentation/device_detail_page.dart`
- Test: `test/features/device_session/application/device_auth_controller_test.dart`

- [ ] Add failing tests for missing configuration, ticket expiry/rejection, bind-confirm, auth-confirm, and destructive unbind cleanup.
- [ ] Implement the gateway contract and unconfigured implementation that returns a typed configuration failure.
- [ ] Implement 0x09 action serialization, authentication state persistence, and sensitive-operation guards.
- [ ] Add bind/auth/unbind UI with concise confirmation and no raw ticket display.
- [ ] Run focused tests and `dart analyze`.
- [ ] Commit: `feat: gate device security flows behind ticket gateway`.

### Task 8: Implement WQOTA transport engine

**Files:**
- Create: `lib/core/protocol/wqota_frame.dart`
- Create: `lib/core/protocol/wqota_codec.dart`
- Create: `lib/core/protocol/wqota_client.dart`
- Create: `lib/features/ota/domain/ota_image_source.dart`
- Create: `lib/features/ota/application/ota_controller.dart`
- Create: `lib/features/ota/presentation/ota_page.dart`
- Modify: `lib/app/providers.dart`
- Modify: `lib/app/app_shell.dart`
- Test: `test/core/protocol/wqota_codec_test.dart`
- Test: `test/core/protocol/wqota_client_test.dart`
- Test: `test/features/ota/application/ota_controller_test.dart`

- [ ] Add failing vectors for packed prefix/flags, BE lengths, E1-E8 fields, data-block CRC32, window boundaries, delay, and zero-length completion.
- [ ] Implement codec with explicit target-firmware prefix/flags configuration and reject unknown values.
- [ ] Implement windowed E5 send, checkpoint persistence, disconnect resume, E6/E8 completion verification, reboot, and post-reconnect 0x01 version check.
- [ ] Add a local image source interface; show “固件来源未配置” when no image provider exists.
- [ ] Add OTA progress/error/cancel UI gated by authentication and device state.
- [ ] Run focused tests and `dart analyze`.
- [ ] Commit: `feat: add resumable WQOTA engine`.

### Task 9: Add persistent real-time Debug logging

**Files:**
- Create: `lib/features/device_logs/domain/app_log_entry.dart`
- Create: `lib/features/device_logs/domain/app_log_store.dart`
- Create: `lib/features/device_logs/data/file_app_log_store.dart`
- Create: `lib/features/device_logs/application/app_log_controller.dart`
- Create: `lib/features/device_logs/presentation/device_log_page.dart`
- Modify: `lib/core/diagnostics/safe_app_logger.dart`
- Modify: `lib/app/providers.dart`
- Modify: `lib/features/device_session/presentation/device_detail_page.dart`
- Modify: `lib/app/app_shell.dart`
- Test: `test/features/device_logs/data/file_app_log_store_test.dart`
- Test: `test/features/device_logs/presentation/device_log_page_test.dart`
- Modify: `test/core/diagnostics/safe_app_logger_test.dart`

- [ ] Add failing tests for ring-buffer limit, stream updates, sanitization, serialized writes, path reporting, 5 MB rotation, and Debug/release behavior.
- [ ] Implement a single logger/store adapter used by BLE, session, protocol, sync, and OTA layers.
- [ ] Use `<ApplicationSupportDirectory>/logs/aipin-YYYY-MM-DD.log` on Android and iOS; expose the absolute current path.
- [ ] Add the device-page “实时日志” entry with pause/resume view, clear view, auto-scroll-at-bottom, empty state, and export/share callback.
- [ ] Ensure pending writes flush before export and retain only seven Debug files.
- [ ] Run focused tests and `dart analyze`.
- [ ] Commit: `feat: add device realtime and local debug logs`.

### Task 10: Wire providers, routing, and recovery behavior

**Files:**
- Modify: `lib/app/providers.dart`
- Modify: `lib/app/app_shell.dart`
- Modify: `lib/features/device_session/presentation/device_detail_page.dart`
- Modify: `lib/features/device_discovery/presentation/discovery_page.dart`
- Test: `test/app/app_shell_test.dart`
- Test: `test/features/device_session/presentation/session_dashboard_page_test.dart`

- [ ] Add failing shell tests for opening device detail, files, configuration, recording, OTA, and logs without duplicating controllers.
- [ ] Register repository/client/controller lifetimes in Riverpod and dispose all stream subscriptions on session replacement.
- [ ] Restore pending file/OTA jobs on app resume and show completion/failure toasts only when the user is not inside the related detail page.
- [ ] Keep Bluetooth permission and platform Bluetooth-enable behavior unchanged for Android/iOS.
- [ ] Run app/widget tests and `dart analyze`.
- [ ] Commit: `feat: wire complete device workflow into app shell`.

### Task 11: Documentation and verification matrix

**Files:**
- Modify: `docs/app-device-flow.md`
- Create: `docs/qa/ble-v1.5-device-test-matrix.md`
- Test: `test/integration_test.dart` (only if the repository integration harness is enabled)

- [ ] Document each App -> device request, endpoint, response/event, state transition, and recovery path.
- [ ] Document the Debug log absolute path and how to export it from the device page.
- [ ] Add the V1.5 vector matrix for minimum/maximum/truncated/extra-byte/invalid CRC and Android/iOS acceptance cases.
- [ ] Run `flutter test`, `dart analyze`, and `flutter build apk --debug`.
- [ ] Record that real-device validation remains required on Android 10/11 and iOS with production UUIDs and ticket/image services.
- [ ] Commit: `docs: document V1.5 device workflow and verification`.

## Definition of done

- All focused unit/widget tests and the full existing test suite pass.
- `dart analyze` is clean and a Debug APK builds.
- No UI reads raw BLE bytes or calls a platform plugin directly.
- No operation reports authenticated, archived, or OTA-complete without its documented prerequisite.
- The device page can open a real-time log view and exposes the actual local Debug log path.
- Remaining external prerequisites are visible in the UI and documented rather than silently skipped.
