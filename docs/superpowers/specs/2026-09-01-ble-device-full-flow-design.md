# BLE Device Full Flow Design

**Date:** 2026-09-01  
**Status:** Approved direction, pending implementation review

## Goal

Extend the existing AIPIN Flutter app from BLE discovery and read-only status observation to a maintainable Android/iOS device workflow based on firmware protocol V1.5. The app will support device discovery, connection, authentication boundaries, device information and configuration, device recording control, file synchronization with resume and integrity checks, real-time audio capability plumbing, and the WQOTA transport. Cloud ticket issuance and firmware distribution remain replaceable external services.

## Scope and boundaries

### In scope

- Merge manufacturer advertisement and scan response data defensively on Android and iOS.
- Discover and manage every documented GATT endpoint:
  - FA10: FA11, FA12, FA15, FA16, FA17, FA18, FA19.
  - FB10: FB11.
  - FF10: FF11, FF12, FF13, FF16.
  - WQOTA service 7033 with 2001/2002.
- Encode and decode the business frame `[ED][Length LE][CMD][Content][CRC16 LE]`.
- Match responses by command, sub-command where applicable, and sequence byte where defined.
- Implement commands 0x01, 0x02, 0x05, 0x06, 0x07, 0x08, 0x09, 0x11, 0x21, 0x22, 0x23, and 0x26 according to V1.5.
- Persist device identity, authentication state, file metadata, download checkpoints, and diagnostic events locally.
- Show current device state, configuration, recording status, storage, battery, files, sync progress, and recoverable errors.
- Provide an in-device real-time log view and a Debug-only local log file export.
- Implement the WQOTA framing, windowing, CRC32, resume, and reconnect state machine when a local firmware image is supplied.

### Explicit boundaries

- `TicketGateway` is an interface. Without a configured backend, the app must show “认证服务未配置” and must not claim the device is authenticated.
- Firmware download, signature verification policy, release selection, and OTA authorization are outside the app protocol layer. The OTA engine accepts a validated local image through an interface.
- `ARCHIVE_CONFIRM` is sent only after a cloud archive callback reports durable success. Without that callback, a file remains locally downloaded and the device file is not marked reclaimable.
- VAD algorithms, LED effects, microphone topology, and factory UART/BLE are device responsibilities and are only observed when exposed by protocol state.
- No new wire command is invented; the deprecated direct-delete/format and independent OTA control commands stay disabled.

## Architecture

The feature-first layout remains in place. Protocol details are isolated from pages and controllers:

```text
core/ble
  BleTransport              BLE scan/connect/read/write/subscribe primitives
  DeviceProfile             typed endpoint map loaded from configuration
  ReactiveBleTransport      Android/iOS adapter and platform error mapping
core/protocol
  EvtFrame / EvtProtocolCodec  strict business frame codec and CRC16
  EvtCommandClient           serialized request/response transactions
  WqotaCodec / WqotaClient   independent OTA frame and window protocol
features/device_session
  DeviceProtocolRepository   typed device operations and workflow sequencing
  DeviceSessionController     state machine, reconnect, and UI updates
  domain models               info/config/status/file/auth/transfer values
features/device_sync
  file repository and checkpoint store
features/device_logs
  AppLogStore / LogController memory stream, file sink, export/share
presentation
  device detail, configuration, recording, files, OTA, logs
```

Presentation widgets never call a BLE plugin, parse raw bytes, or write the database. Application controllers depend on interfaces so fake transports and deterministic protocol vectors can be used in tests.

## BLE transport contract

`BleTransport` will expose the following primitives in addition to the existing methods:

- `Future<void> write(BleCharacteristic characteristic, Uint8List bytes)` for Write/Indicate request characteristics.
- `Future<void> writeWithoutResponse(BleCharacteristic characteristic, Uint8List bytes)` for WQOTA.
- `Stream<Uint8List> subscribe(BleCharacteristic characteristic)` for Notify and Indicate.
- A characteristic capability/operation value so the repository cannot accidentally write to a read-only endpoint.

`DeviceProfile` will hold a map keyed by logical endpoint rather than three generic UUIDs. It will validate UUID format, service membership, and required properties before a session can become ready. Short UUIDs from the protocol document are normalized to Bluetooth base UUIDs in configuration loading.

`ReactiveBleTransport` will:

1. Keep one active connection per device ID.
2. Log redacted device IDs and endpoint UUIDs, never security material.
3. Map Android/iOS permission, Bluetooth-off, GATT, and disconnect errors to `BleTransportException`.
4. Preserve stream cancellation and disconnect cleanup on every failure path.
5. Use a bounded timeout for service discovery and every primitive operation.

## Protocol layer

### Business frames

`EvtProtocolCodec` will validate the minimum frame size before reading any header fields, then validate `Length`, total byte count, CRC16/CCITT-FALSE (poly `0x1021`, init `0xFFFF`, no reflection), and command-specific payload lengths. It will provide a frame builder for requests and typed decode helpers for little-endian integers, signed corrections, fixed `FileName[17]`, and response result codes.

### Command client

`EvtCommandClient` owns a single serialized queue per connected device. A transaction contains the request command, expected response command, optional sub-command and sequence byte, timeout, retry count, and a `Completer`. Indicate commands use a 2-second timeout and one retry. Notifications that do not match a pending transaction are published as unsolicited `DeviceEvent`s. A disconnect fails the active transaction and preserves the transfer checkpoint.

### Typed commands

- `0x01`: protocol version, serial/model, firmware and capability fields.
- `0x02`: UTC/time correction, recording parameters, privacy duration, AudioStream switch.
- `0x05`: total/free storage.
- `0x06`: configuration and status subcommands, including privacy and status events.
- `0x07`: start/stop recording and `0x87` state response.
- `0x08`: FA18 audio data notification; no invented sequence or ACK fields.
- `0x09`: versioned bind, authenticate, unbind-clear actions, guarded by `TicketGateway`.
- `0x11`: battery and charging read.
- `0x21`: compatibility file count read.
- `0x22`: paged file list with the exact 17-byte filename slot.
- `0x23`: file data reads using filename and offset, with checkpoint resume.
- `0x26`: GET_META and ARCHIVE_CONFIRM; CRC32 and file-size checks are mandatory.

All response parsers reject malformed or inconsistent lengths and return structured protocol failures. Unknown commands remain diagnostic events.

## Session and user flows

### Connect and restore

`environmentReady -> discovered -> connecting -> servicesDiscovered -> subscribing -> authenticating/ready`.

After GATT discovery, the app subscribes to all documented Indicate/Notify characteristics before issuing reads. It then:

1. Reads 0x01 and verifies `ProtocolVersion=3`.
2. Runs unbound bind or bound authentication when tickets are available.
3. Writes current UTC through 0x02 when the device permits it.
4. Reads 0x07, 0x11, 0x05, and 0x06 to build an authoritative snapshot.
5. Enters `ready` only when required reads and subscriptions succeed.

Reconnect starts a fresh transport sub-session and re-reads authoritative state; cached data is labelled stale and cannot unlock controls.

### Device controls

The device page is organized as summary, status, recording, storage, configuration, files, diagnostics, and OTA. Controls are enabled only for the state and authentication capabilities reported by the device. Starting/stopping device recording waits for the matching 0x87 state and displays finalizing separately from stopped.

### File synchronization

`list -> metadata -> download chunks -> local size/CRC validation -> optional cloud archive -> ARCHIVE_CONFIRM`.

The app keeps a checkpoint per device filename and validates offset continuity. It resumes from the last confirmed offset after a disconnect or app restart. A completed local file becomes playable only after size and CRC match the 0x26 metadata. Until cloud durable-success is reported, the UI labels the device file as retained rather than reclaimable.

### Authentication and unbind

The app never stores or logs raw tickets. `TicketGateway` returns short-lived ticket objects to the repository; failures are shown as configuration, expiry, or rejection errors. Unbind-clear requires an explicit destructive confirmation and a successful two-step device response before local identity and cached checkpoints are removed.

### WQOTA

`WqotaClient` subscribes to 0x2002, reads capabilities, sends E1/E2/E3, streams E5 blocks according to returned windows and delay, calls E6/E8, then reboots and verifies the version over business 0x01. It stores offset, window length, and image identity for resume. It never treats E6 or an early E8 idle value as proof of final CRC verification without the documented completion result.

## Real-time logs and local export

### In-memory stream

`AppLogStore` implements `SafeAppLogger`, keeps a bounded ring of the latest 500 entries, and exposes a broadcast stream plus `ChangeNotifier` snapshot for widgets. Each `LogEntry` contains timestamp, scope, event, and sanitized fields. The device page opens a “实时日志” section that:

- updates as BLE/session/protocol events arrive;
- auto-scrolls only when the user is already at the bottom;
- allows pause/resume of the view without stopping collection;
- provides clear-view and export actions;
- shows an empty state and a disconnected state without implying missing data.

### Debug file sink

In `kDebugMode`, the store appends newline-delimited UTF-8 text to a daily file under the platform application-support directory:

- Android: `<ApplicationSupportDirectory>/logs/aipin-YYYY-MM-DD.log`
- iOS: `<ApplicationSupportDirectory>/logs/aipin-YYYY-MM-DD.log`

The exact absolute path is returned by `AppLogStore.currentFilePath` and shown in the log page. The export action flushes pending writes, returns the file path, and uses the existing share capability when available. The store serializes writes, rotates at 5 MB, and retains the latest seven Debug files. Release builds keep no persistent diagnostic file and keep only normal user-facing error reporting.

Sanitization rules are centralized: device IDs keep only the last four characters, tickets and authorization payloads are replaced with `[redacted]`, audio/file content is represented by byte counts and checksums, and log fields are limited to primitive scalar values.

## Error and recovery policy

- Bluetooth disabled or permission denied: environment remediation, no stale candidates.
- Connection, service, notification, or initial-read failure: interrupted session with retry and cleanup.
- Command timeout: one retry for Indicate, then a typed failure; the queue remains usable.
- Invalid frame/CRC/length: diagnostic event, preserve last valid snapshot, never mark success.
- File mismatch: delete only the partial local artifact, preserve checkpoint for retry, and do not archive.
- Disconnect during file transfer or OTA: pause, persist checkpoint, and resume after a fresh authenticated session.
- App kill: recovery service reloads pending transfers and shows their current state on resume.

## Testing and acceptance

### Unit and controller tests

- Broadcast merge/filter, UUID normalization, endpoint capability validation.
- Minimum/maximum/truncated/extra-byte/CRC-invalid vectors for every command.
- Response matching by command/sub-command/SN and timeout/retry behavior.
- Authentication gates and unbind cleanup.
- File pagination, filename slot rules, offset resume, CRC32, and archive gating.
- WQOTA prefix/flags/opcode, window boundaries, delay, resume, and completion verification.
- Session transitions, disconnect races, stale snapshot protection, and log sanitization.

### Widget tests

- Device page state variants and disabled controls.
- Real-time log append, pause/resume, clear, path display, and export callback.
- File sync progress/error/resume and recording finalizing state.

### Real-device acceptance

Android 10/11 and current iOS devices must each verify scan, connect, all endpoint subscriptions, information/configuration reads, recording control, file sync with a forced disconnect, authentication with real tickets, and OTA with a signed test image. The current Windows/Edge environment can run only unit/widget tests and UI flows.

## Open external inputs

- Production UUID/property profile if it differs from the V1.5 table.
- TicketGateway URL, request/response schema, and key storage policy.
- OTA image provider and signature verification policy.
- A captured WQOTA prefix/flags vector from target firmware to freeze packed bitfield byte order.
