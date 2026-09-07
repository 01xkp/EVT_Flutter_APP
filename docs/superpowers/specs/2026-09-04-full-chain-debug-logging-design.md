# Full-Chain Debug Logging Design

## Purpose

Make one device operation explainable from the App UI action through BLE, device protocol, network services, and local persistence. The target reader is an App engineer, firmware engineer, or test engineer debugging a real EVT device.

The change must answer these questions without relying on Android Logcat alone:

1. What did the user try to do?
2. Which App stage was reached?
3. Was a BLE command written, to which characteristic, and with what safe protocol identity?
4. Did the device return a matching response, return an error, or never respond?
5. Did a network dependency fail before BLE communication began?
6. Which local file contains the complete diagnostic trail?

## Scope

The implementation covers debug builds only. It includes:

- structured, human-readable persistent logs;
- trace correlation across UI, BLE, command, authentication, file, OTA, audio, AI, and HTTP work;
- safe Android public-file mirroring to `Download/AIPIN/logs`;
- App-internal storage and Files/share export on iOS;
- a usable in-App real-time log viewer;
- focused automated coverage for the new log contract.

It does not upload diagnostics to a backend, persist raw audio or firmware data, add production telemetry, or alter firmware protocol behavior.

## Existing Gaps

The current `SafeAppLogger -> PersistentAppLogger -> FileAppLogStore` path saves some BLE transport events, but it cannot reconstruct an operation end to end.

- `EvtCommandClient` does not log enqueue, frame construction, response matching, retry, timeout, or total duration.
- Authentication errors such as `认证服务未配置` only become a Toast. They do not create an `AUTH` diagnostic event.
- File import has no operation log for checkpoints, chunks, CRC validation, archive response, or device archive confirmation.
- OTA state transitions and WQOTA progress have no business-level trace.
- Some page-level error handlers discard the underlying reason after showing a generic message.
- Raw error text is currently written in several places and may contain device identifiers, file paths, URLs, or service response details.
- Android persistent logs live only in the private app directory, which a file manager cannot browse.

## Design

### Diagnostic Event

All persistent entries use one event record:

```text
timestamp | level | scope | trace_id | operation | stage | event | result | elapsed_ms | fields
```

Example:

```text
2026-09-04T12:10:03.666 | INFO | CMD | 8fa2c1 | device_bind | fa19_write | command_write_started | pending | - | command=0x09 action=0x10 attempt=1 characteristic=FA19 request_bytes=92
```

Fields are normalized before rendering. The in-memory view, private file, Android public copy, and exported file receive the same sanitized event content.

### Trace Context

`DiagnosticTrace` represents one user-visible operation. It contains a random short trace ID, operation name, originating screen, start time, and a safe device reference. Child events use the same trace ID.

The following operations create a trace:

| Operation | Created when | Ends when |
| --- | --- | --- |
| `device_scan` | User starts scanning | Scan stops or fails |
| `device_connect` | User selects connect | Session becomes authentication-ready or fails |
| `device_bind` | User taps first bind | Binding succeeds or fails |
| `device_authenticate` | User taps authenticate | Authentication and post-auth sync succeed or fail |
| `device_file_import` | User imports one file | Import, CRC, archive, and device confirmation reach a terminal result |
| `device_realtime_audio` | User starts audio reception | Reception stops or fails |
| `device_ota` | User starts an upgrade | Version is verified after reconnect, cancelled, or failed |
| `local_recording` | User starts an App recording | Recording is discarded or saved |
| `ai_transcription` / `ai_summary` | User requests processing | Backend returns terminal success or failure |

Background continuation preserves the original trace ID where the persisted task/checkpoint owns it. A resumed task creates a linked trace with `parent_trace_id`, not a confusing unrelated operation.

### Scopes and Required Events

| Scope | Required diagnostics |
| --- | --- |
| `UI` | User tap, confirmation/cancel, navigation, rendered error/toast result |
| `BLE` | Permission decision, adapter state, scan lifecycle, discovery decision, connection update, service inventory, endpoint capability, MTU, subscription, read, write, disconnect |
| `SESSION` | Phase transition, required endpoint validation, grant expiration, synchronization stage, interruption/reconnect |
| `CMD` | Enqueue, request encoded, write started/completed, expected response, response decoded, response matched/unmatched, retry, timeout, terminal result and elapsed time |
| `AUTH` | Ticket configuration decision, ticket request start/result, bind/auth request, challenge validation, proof validation, grant result, post-auth synchronization result |
| `DEVICE_API` | Request start, response status, response schema validation, elapsed time, normalized failure reason |
| `FILE` | List page, metadata, checkpoint hit/create/clear, requested offset, received byte count, progress, CRC result, archive result, archive-confirm result |
| `OTA` | Package lookup, package validation, MTU admission, checkpoint, operation phase, window aggregate progress, reconnect, version verification, cancellation, terminal result |
| `AUDIO` | Audio reception subscription, stream enable/disable, record control, capture byte aggregate, capacity guard, export result |
| `AI` | Recording selection, upload, job creation, poll attempt, state transition, returned text length, summary result, retry and terminal failure |
| `STORAGE` | Private file initialized, rotation, public mirror success/failure, export start/success/failure |

Every error shown to a user must have a prior or simultaneous structured event with the same trace ID. The event records the stable failure category and stage even when the UI uses a shorter sentence.

### Protocol-Level Logging

The command client becomes the single source for command lifecycle diagnostics. Every request records:

- command (`0x09`, `0x07`, `0x22`, etc.);
- logical operation and write characteristic;
- safe selector such as action, sub-command, sequence, offset, or expected response command;
- encoded frame length and CRC validation result;
- attempt number, timeout setting, duration, and terminal state.

The client must log response identity and matching outcome. It must not log raw command content by default.

For the current security-sensitive and high-volume paths, logging rules are:

| Protocol path | Allowed fields | Never record |
| --- | --- | --- |
| `0x09` authentication | action, transaction hash/reference, request length, response result, grant bits, duration | ticket, proof key, nonce, proof bytes, full transaction ID |
| `0x08` real-time audio | payload length, ordered chunk count, accumulated bytes | audio payload |
| `0x23` file data | offset, chunk length, accumulated bytes, terminal marker, CRC result | file bytes, filename slot, audio path |
| WQOTA `E5` | window index, offset, block count, total bytes, CRC pass/fail, duration | firmware bytes, payload URL, full package hash |
| other commands | command, sub-command/action, length, response status, CRC result | unclassified raw payload unless an explicit safe field decoder exists |

File and OTA transfer diagnostics aggregate frequent packet activity into operation-level progress. They emit on start, percentage change, retry, window/terminal marker, and failure; they do not exhaust the persistent log with one entry for every byte packet.

### Sanitization

Sanitization is moved in front of every sink, including `DebugSafeAppLogger`. It uses an allowlist of safe fields per scope plus common redaction.

- A device reference is an installation-salted, short non-reversible correlation value; it is not the physical BLE ID.
- Ticket, proof, nonce, secret, token, raw payload, audio, firmware, filename, name slot, absolute path, URL, query string, and raw `error` fields are blocked.
- Errors are transformed to `error_type`, `error_code`, `gatt_status`, `http_status`, `stage`, and a safe message.
- File checksums and package hashes are represented only as a short safe verification outcome, not the full value.
- Sanitization is recursive for maps, lists, and values interpolated into debug output.

## Storage and Platform Behavior

### Internal Canonical File

`FileAppLogStore` remains the canonical Debug log owner. It maintains daily rolling files and the in-App real-time viewer. The default remains seven retained files and a 5 MiB per-file rotation threshold unless a trace has an active critical transfer; rotation must never break an active write queue.

### Android Public Mirror

Android Debug builds mirror sanitized completed log content to:

```text
Download/AIPIN/logs/aipin-YYYY-MM-DD.log
```

The mirror is implemented behind a `PublicDiagnosticLogSink` interface.

- Android 10+ uses `MediaStore.Downloads` with `RELATIVE_PATH=Download/AIPIN/logs`; it does not request broad storage access.
- Android 9 and lower uses the compatible downloads path and only requests the legacy write permission when needed.
- Writes are debounced (at most once per second) and also flushed when the app is paused, the user exports, or an operation ends. A public-mirror failure is logged internally but can never break BLE, recording, or AI processing.
- The log viewer displays the public filename and last mirror outcome.

### iOS and Other Platforms

iOS does not silently write to a global Files directory. It keeps the same sanitized Debug log in Application Support and uses the existing export/share action to save a copy to Files. Desktop platforms retain their existing Application Support behavior.

## UI

The real-time log page adds:

- current trace ID and operation label where available;
- scope and severity filters;
- text search and copy of a selected trace;
- displayed internal and public Android log paths;
- visible public-mirror status;
- export of the current daily file.

`清空视图` only clears the in-memory viewer. It must not delete persistent diagnostic files.

## Failure Handling

- Logging must be asynchronous and never throw into the product flow.
- A disk, MediaStore, permission, or serialization error creates a bounded in-memory `STORAGE` event where possible; it does not recursively try to write itself forever.
- If Android public mirroring is unavailable, the private Debug log and in-App viewer continue working.
- If a trace ends unexpectedly due to app process termination, the next startup records a recovery event using any available persisted checkpoint context.

## Test Strategy

Focused tests will be written before production changes and must cover:

1. A command trace records send, matching response, retry, timeout, elapsed time, and terminal result.
2. An unconfigured ticket service records an `AUTH` configuration failure before the UI reports it.
3. Recursive sanitization removes ticket, proof, nonce, URL, filename, raw payload, and raw error content from every sink.
4. File import emits checkpoint, aggregated progress, CRC, archive, and terminal events without file bytes.
5. OTA emits package validation, aggregate window progress, reconnect, version verification, cancellation, and terminal events without firmware bytes.
6. Log rotation and public mirror failure never fail a product operation.
7. Android public mirror receives the expected daily filename and path policy through a mocked platform boundary.
8. The log page filters by scope/trace and shows the public-mirror state.

## Acceptance Criteria

1. A tester can open one Debug log file from `Download/AIPIN/logs` and reconstruct a failed bind from UI tap through ticket configuration, `FA19` write attempt, `0x89` response or timeout, and final UI result.
2. A tester can identify whether an authentication failure occurred before BLE write, during GATT write, during device challenge verification, or after grant synchronization.
3. A 30-minute file import or OTA does not bury its start/failure/terminal events under per-packet noise.
4. No ticket, proof key, nonce, raw audio, raw firmware, full device ID, file name, local path, full URL, or raw protocol payload occurs in persistent logs.
5. Android Debug logs are visible in the phone's Downloads app under `AIPIN/logs`; a mirror failure never breaks the App.
6. Existing real-time log viewing and manual export remain usable on Android and iOS.
