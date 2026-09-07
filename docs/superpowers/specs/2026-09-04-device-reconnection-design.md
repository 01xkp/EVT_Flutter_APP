# Remembered Device Reconnection Design

## Purpose

Allow the App to reconnect to a device that previously completed a BLE
connection. The App must save a private connection record, watch active
foreground scans for that record, and make bounded retry attempts after an
unexpected connection failure.

This is a product feature, not diagnostic telemetry. The real BLE identifier
and broadcast MAC are stored only in private App preferences. Persistent
diagnostics use the existing installation-salted device reference and never
contain either raw identifier.

## Platform Identity

`DeviceCandidate.connectionId` is the identifier used by the BLE transport.
Android normally supplies a BLE MAC address; iOS supplies a CoreBluetooth
UUID. The V1.5 manufacturer advertisement can additionally expose a
six-byte physical Bluetooth address through `DeviceCandidate.physicalDeviceId`.

The stored record contains both values when available:

- `connectionId`: required for platform BLE operations and matching a newly
  scanned candidate.
- `physicalMacAddress`: normalized V1.5 broadcast address when present.
- `displayName`: last non-empty user-visible device name.
- `lastConnectedAt`: UTC timestamp used for ordering and expiry decisions.

Matching prefers the physical MAC when both records have it, then falls back
to the platform connection ID. This supports iOS without pretending the
CoreBluetooth UUID is a MAC address.

## Storage

`DeviceConnectionHistoryRepository` owns a bounded private list of recent
records in SharedPreferences. The list keeps the five most recent records and
has atomic read/validate/replace behavior. Invalid or duplicated serialized
records are discarded safely. A successful `SessionPhase.authenticationReady`
connection upserts the record. A user-initiated disconnect retains it. A
completed device clear/unbind removes the matching record.

No connection record is written for a connection that drops before required
GATT endpoints and subscriptions are ready.

## Reconnection Flow

1. After onboarding is loaded, and when the App returns to the foreground,
   the App loads history and starts a foreground scan only when there is no
   active session and auto-reconnection has not been suppressed.
2. A scanned candidate matching a remembered record starts one reconnect
   attempt. The scanner stops before the existing session connection sequence
   runs.
3. On `authenticationReady`, the attempt succeeds, history is refreshed, and
   retry state is cleared.
4. If setup reaches an interrupted or failed state, the App restarts scanning
   after delays of 1 second then 2 seconds. It attempts at most three times
   per reconnect cycle.
5. After the cap is reached, automatic work stops. The existing device detail
   retry action and a reconnect action on the connection journey start a new
   explicit cycle.
6. A user-selected `disconnect` suppresses automatic reconnection for the
   current foreground session. A user explicitly opening the connection
   journey clears the suppression and starts a new cycle.

The App never runs background BLE scans just to reconnect. Normal platform
Bluetooth permissions and adapter state remain prerequisites. If Bluetooth is
off or the record is not observed during the scan window, the App stays in a
recoverable disconnected state and exposes the normal reconnect action.

## Components

| Layer | Component | Responsibility |
| --- | --- | --- |
| Domain | `RememberedDevice`, `DeviceConnectionHistoryRepository` | Validated record and private storage contract. |
| Data | `SharedPreferencesDeviceConnectionHistoryRepository` | Serialize, validate, cap, upsert, and remove private records. |
| Application | `DeviceReconnectController` | Match scans, own the three-attempt backoff state, prevent duplicate attempts, and expose immutable reconnect state. |
| Presentation | App shell and discovery/detail views | Start/cancel explicit cycles, render reconnect progress/failure, and keep manual controls responsive. |

The reconnect controller receives callbacks for scan start/stop and session
connection instead of directly constructing BLE controllers. This keeps the
existing `SessionController` as the sole owner of GATT setup and avoids
duplicate connection streams.

## Error Handling and Diagnostics

- Attempt stages use stable safe events such as `reconnect_scan_started`,
  `reconnect_candidate_matched`, `reconnect_attempt_failed`, and
  `reconnect_exhausted`.
- Events include attempt number, safe connection phase, and elapsed time only.
  They do not include MAC, CoreBluetooth UUID, device name, raw BLE frames,
  or exception text.
- History I/O errors do not block a manual connection. The App treats the
  record as unavailable and keeps normal discovery usable.
- Stale scan candidates cannot restart a cycle after scanning has stopped or
  an active connection exists.

## Acceptance Criteria

1. A device that reaches `authenticationReady` is remembered and remains
   available after an App restart.
2. When an active foreground scan observes that device, the App attempts
   reconnection without requiring the user to select the row again.
3. A failed attempt retries at most twice after the first attempt, then stops
   and leaves an explicit reconnect action available.
4. Manual disconnect stops automatic reconnection until the user explicitly
   requests it or starts a new App foreground session.
5. Successful clear/unbind removes the record; a later scan no longer
   auto-connects it.
6. Android storage contains the transport ID/MAC as applicable; iOS stores
   its transport UUID and optional V1.5 broadcast MAC without requiring an
   unavailable system MAC API.
7. No raw MAC, connection ID, device name, or exception text appears in the
   diagnostic viewer, private diagnostic file, Android public mirror, or
   export.

## Test Strategy

Focused unit/widget tests cover record validation/upsert/removal, Android and
iOS identifier matching, one reconnect per scan candidate, bounded backoff,
manual disconnect suppression, unbind cleanup, and user-visible retry state.
Existing discovery/session tests verify that normal scanning and direct manual
connection behavior remain unchanged.
