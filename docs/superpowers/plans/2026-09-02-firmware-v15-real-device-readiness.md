# Firmware V1.5 Real-Device Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Flutter BLE client safe to validate against V1.5 firmware by enforcing protocol ordering, ATT write capacity and durable recovery behavior.

**Architecture:** Keep capability and MTU admission in `SessionController`, command framing in `EvtCommandClient` and data validation in repositories. File import retains its checkpoint in Drift and only archives after a verified continuous stream completes. OTA independently validates its own minimum single-write capacity so callers cannot bypass session admission.

**Tech Stack:** Flutter, Dart, `flutter_reactive_ble`, Drift, `flutter_test`.

**Spec:** `D:\Downloads\智能吊坠设备-App通讯协议_广播与逐字段示例版_V1.5_20260814.html`

## Global Constraints

- Follow the V1.5 `0x09`, `0x22`, `0x23`, `0x26` and WQOTA one-write requirements.
- Do not access protected status or files before an authenticated grant has been synchronized with UTC/configuration.
- Do not alter user-owned ASR changes in `lib/features/research_beta/data/temporary_asr_http_gateway.dart`.
- Add regression coverage before each production behavior change.

---

### Task 1: Align Session Tests With Safe Admission

**Files:**
- Modify: `test/features/device_session/application/session_controller_test.dart`
- Modify: `test/app/app_shell_test.dart`

**Interfaces:**
- Consumes: `SessionController.synchronizeAfterAuthentication()` and `toggleRealtimeAudio(bool)`.
- Produces: regression coverage proving protected details and audio streaming require authoritative post-auth configuration.

- [ ] Write focused tests that reject a protected refresh before authentication and reject realtime audio without a synchronized configuration.
- [ ] Run the tests and verify the old expectations fail because they assume pre-auth reads and fabricated configuration.
- [ ] Update fixtures and expectations to perform the documented post-auth synchronization sequence.
- [ ] Re-run the focused tests and verify they pass.

### Task 2: Close Protocol Boundary Gaps

**Files:**
- Modify: `lib/features/device_session/presentation/device_file_browser_page.dart`
- Modify: `lib/features/device_session/data/wqota_ble_update_gateway.dart`
- Modify: `test/features/device_session/presentation/device_file_browser_page_test.dart`
- Modify: `test/features/device_session/data/wqota_ble_update_gateway_test.dart`

**Interfaces:**
- Consumes: V1.5 list termination (`Count == 0`) and WQOTA minimum frame capacity (`ATT_MTU >= 27`).
- Produces: bounded pagination for malformed peers and OTA gateway refusal before an invalid E2 write.

- [ ] Write failing tests for a never-ending nonempty list response and a direct OTA gateway call with insufficient ATT capacity.
- [ ] Run those focused tests and verify they fail because no guard exists at the relevant boundary.
- [ ] Add the smallest guards without changing compliant-device behavior.
- [ ] Re-run the focused tests and verify they pass.

### Task 3: Persist Pending Clear Transactions

**Files:**
- Modify: `lib/features/device_session/application/device_auth_controller.dart`
- Modify: `test/features/device_session/application/device_auth_controller_test.dart`
- Create: a focused persistence implementation only if no existing checkpoint store is available.

**Interfaces:**
- Consumes: `requestClear()` and `confirmClear()` transaction ID/nonce values.
- Produces: an app-restart-safe pending clear confirmation record scoped to the target address.

- [ ] Inspect the existing clear controller and persistence conventions; write a failing restoration test at the controller boundary.
- [ ] Verify the new test fails before adding persistence.
- [ ] Persist and restore only the transaction data required by V1.5 confirmation; remove it after success or terminal invalidation.
- [ ] Run the focused controller test and verify it passes.

### Task 4: Whole-Project Verification

**Files:**
- Verify: all modified files and `docs/real-firmware-integration.md`

- [ ] Run `dart format` on touched Dart files.
- [ ] Run `flutter test`, `flutter analyze --no-fatal-infos`, `flutter build apk --debug` and `git diff --check`.
- [ ] Inspect the resulting diff for unrelated changes and report any remaining physical-device prerequisites.
