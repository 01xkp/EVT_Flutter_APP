# Firmware V1.5 Device App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the Flutter App's device-facing V1.5 protocol flows while preserving strict device, archive, and OTA confirmation semantics.

**Architecture:** Keep `SessionController` as the single BLE session owner and route business and WQOTA endpoints through separate clients. Add narrowly scoped controllers and gateways for authentication, archival, realtime audio, and firmware update; views consume immutable controller state through the existing provider pattern.

**Tech Stack:** Flutter, Dart, Riverpod, `flutter_reactive_ble`, Drift, `permission_handler`, existing BLE/protocol codecs.

**Spec:** `docs/superpowers/specs/2026-09-01-firmware-v1-5-device-app-design.md`

## Global Constraints

- Implement only V1.5 device interfaces `0x01`, `0x02`, `0x05`, `0x06`, `0x07`, `0x08`, `0x09`, `0x11`, `0x21`, `0x22`, `0x23`, `0x26`, and WQOTA `7033/2001/2002`.
- Keep deprecated user-mode `0x03`, `0x04`, `0x24`, `0x25`, and business `0x31` out of scope.
- Never report authentication, cloud archival, or OTA success without the corresponding device or HTTPS confirmation.
- Preserve existing uncommitted work; stage and commit only files changed for this implementation.
- Production external services require HTTPS; an unconfigured service must remain visible and actionable rather than simulated.
- Android API 23-30 requests location permission for scan; Android API 31+ requests Bluetooth scan/connect permissions; iOS declares `bluetooth-central` and never attempts programmatic Bluetooth enablement.

---

## File Structure

| Area | Files | Responsibility |
| --- | --- | --- |
| Session integrity | `session_controller.dart`, `session_state.dart`, controller tests | V3 session admission and endpoint ownership |
| Platform BLE | `permission_handler_gateway.dart`, `Info.plist`, permission tests | Correct per-platform scan prerequisites |
| Security | `device_auth_controller.dart`, ticket/security gateways, auth tests | Scoped grants and explicit unbind lifecycle |
| Device control | protocol repository, status view model/detail page/tests | `0x02/0x05/0x06/0x07/0x21` display and writes |
| Files | archive gateway, file import service, file-browser tests | download verification, durable archive, then `0x26` |
| Realtime audio | new controller/domain/presentation/tests | bounded `0x08` capture lifecycle |
| WQOTA | codecs/client, new controller/gateway/page/checkpoint/tests | package validation, resumable transfer, verification |

## Tasks

### Task 1: Separate Business and WQOTA Session Routing

**Files:**
- Modify: `lib/features/device_session/application/session_controller.dart`
- Modify: `lib/features/device_session/application/session_state.dart`
- Modify: `lib/app/providers.dart`
- Test: `test/features/device_session/application/session_controller_test.dart`

- [ ] Write a failing test proving a `2002` WQOTA notification is not decoded as a business `0xED` frame.
- [ ] Run the focused test and confirm the expected failure.
- [ ] Move WQOTA subscription ownership to the WQOTA client/controller boundary and keep the session subscription limited to business notify characteristics.
- [ ] Write a failing V3 admission test for a protocol version other than `3`.
- [ ] Require a successful authoritative `0x01` read with `ProtocolVersion == 3` before state becomes observable, retaining the structured failure reason.
- [ ] Run focused session tests and commit the isolated change.

### Task 2: Correct Android and iOS BLE Prerequisites

**Files:**
- Modify: `lib/core/permissions/permission_handler_gateway.dart`
- Modify: `ios/Runner/Info.plist`
- Test: `test/core/permissions/permission_handler_gateway_test.dart` or existing nearest gateway tests

- [ ] Write failing tests for Android API 23-30 location permission selection and Android API 31+ Bluetooth permission selection.
- [ ] Run focused tests and confirm failures.
- [ ] Implement the API-specific permission branch without changing iOS's manual Bluetooth enablement policy.
- [ ] Add `bluetooth-central` to iOS background modes while retaining current microphone/audio declarations.
- [ ] Run focused tests and static analysis for modified Dart files.

### Task 3: Complete Scoped Authentication and Unbind

**Files:**
- Modify: `lib/features/device_session/application/device_auth_controller.dart`
- Modify: `lib/features/device_session/domain/device_security_gateway.dart`
- Modify: `lib/features/device_session/data/device_protocol_repository.dart`
- Modify: `lib/core/persistence/app_database.dart` and generated code only if checkpoint deletion needs a new DAO call
- Test: `test/features/device_session/application/device_auth_controller_test.dart`

- [ ] Write a failing lifecycle test requiring `clearRequest (0x30)`, user approval, ticket acquisition, `clearConfirm (0x31)`, then `clearStatus (0x32)` polling.
- [ ] Run it and verify the failure demonstrates missing confirmation ordering.
- [ ] Implement explicit pending-clear state; do not use the generic authenticate handshake to send confirm before the user approves.
- [ ] Clear local scoped grants and file checkpoints only after device completion; retain them on cancellation/failure.
- [ ] Add scope checks for file, realtime audio, configuration, OTA and clear actions.
- [ ] Run focused tests and commit the security change.

### Task 4: Expose Authoritative Device Status and Settings

**Files:**
- Modify: `lib/features/device_session/domain/device_snapshot.dart`
- Modify: `lib/features/device_session/application/session_state.dart`
- Modify: `lib/features/device_session/data/device_protocol_repository.dart`
- Modify: `lib/features/device_session/presentation/device_status_view_model.dart`
- Modify: `lib/features/device_session/presentation/device_detail_page.dart`
- Test: existing repository, view-model, and page tests

- [ ] Write failing tests for status fields sourced from `0x11`, `0x05`, `0x06`, and optional `0x21`.
- [ ] Implement typed repository calls and session refresh after a successful full `0x02` write or privacy/consent update.
- [ ] Add controls for documented recording actions `0x07` and disable them when a command is active, session is not observable, or scope is missing.
- [ ] Add lightweight page tests for blocked controls and updated displayed values.
- [ ] Run focused tests and commit.

### Task 5: Require Durable Archive Before Device Archive Confirmation

**Files:**
- Create: `lib/features/device_session/domain/archive_gateway.dart`
- Create: `lib/features/device_session/data/unconfigured_archive_gateway.dart`
- Modify: `lib/features/device_session/data/device_file_import_service.dart`
- Modify: `lib/features/device_session/data/device_protocol_repository.dart`
- Modify: `lib/app/providers.dart`
- Test: `test/features/device_session/data/device_file_import_service_test.dart`

- [ ] Write a failing test showing a verified local file cannot trigger `0x26/0x02` before `ArchiveGateway.archive` returns durable success.
- [ ] Implement archive state and explicit failure/retry behavior while retaining the verified local file and device source file on archive failure.
- [ ] Preserve exact 17-byte filename slots, final length, and CRC32 when sending the confirmation.
- [ ] Add an unconfigured gateway test proving it cannot claim success.
- [ ] Run focused tests and commit.

### Task 6: Add Bounded Realtime Audio Capture

**Files:**
- Create: `lib/features/device_session/domain/realtime_audio_capture.dart`
- Create: `lib/features/device_session/application/realtime_audio_controller.dart`
- Create: `lib/features/device_session/presentation/realtime_audio_panel.dart`
- Modify: `lib/features/device_session/data/device_protocol_repository.dart`
- Modify: `lib/features/device_session/presentation/device_detail_page.dart`
- Modify: `lib/app/providers.dart`
- Test: `test/features/device_session/application/realtime_audio_controller_test.dart`

- [ ] Write a failing test for ordered byte capture and a separate overflow test that disables streaming and reports a recoverable error.
- [ ] Implement the bounded queue, byte counter, start/stop sequence, and raw capture save flow.
- [ ] Subscribe to `0x08` only while the controller is active; preserve unknown codec payloads as exportable raw captures.
- [ ] Add a minimal panel showing live state, byte count, stop, and save actions without claiming unknown audio is playable.
- [ ] Run focused tests and commit.

### Task 7: Implement Resumable WQOTA

**Files:**
- Create: `lib/features/device_session/domain/firmware_package_gateway.dart`
- Create: `lib/features/device_session/data/unconfigured_firmware_package_gateway.dart`
- Create: `lib/features/device_session/application/wqota_update_controller.dart`
- Create: `lib/features/device_session/presentation/firmware_update_page.dart`
- Create: persistence table/repository for OTA checkpoint only if no existing checkpoint can represent package hash and byte position
- Modify: `lib/core/protocol/wqota_client.dart`
- Modify: `lib/app/providers.dart`
- Modify: `lib/features/device_session/presentation/device_detail_page.dart`
- Test: `test/features/device_session/application/wqota_update_controller_test.dart`

- [ ] Write a failing package validator test for target mismatch, invalid payload length, invalid CRC32, and missing protocol prefix.
- [ ] Implement package validation and visible unavailable-gateway state.
- [ ] Write a failing sequence test for `0x02`, `E1`, `E2`, `E3`, windowed `E5`, `E6`, `E8` and user cancellation `E4`.
- [ ] Implement the controller with persisted `{deviceId, packageHash, offset}`, resume only when the same validated package is selected, and propagate endpoint/opcode errors.
- [ ] Verify reconnect and `0x01` version confirmation before declaring completion.
- [ ] Add a compact update page with validation state, progress, cancellation and recovery actions.
- [ ] Run focused tests and commit.

### Task 8: Verification and Device Test Record

**Files:**
- Modify: `docs/app-device-flow.md` only where implemented behavior differs from the documented flow

- [ ] Run `dart format` on modified Dart files.
- [ ] Run `flutter analyze --no-fatal-infos`.
- [ ] Run `flutter test`.
- [ ] Run `flutter build apk --debug`.
- [ ] Record remaining physical-device checks for Android 10/11, Android 12+, and iOS 13+ without claiming they ran when hardware is unavailable.
- [ ] Review only files changed by this implementation, stage only those files, and make focused commits without touching unrelated user changes.
