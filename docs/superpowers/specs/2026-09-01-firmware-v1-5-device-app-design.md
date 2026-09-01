# Firmware V1.5 Device App Design

## Goal

Complete the Flutter App's V1.5 device-facing flow for BLE business commands,
secure device access, file import and archive confirmation, realtime audio,
and WQOTA. The App must never report secure access, durable archive, or OTA
success without the corresponding device or HTTPS service confirmation.

## Scope

Included firmware interfaces are business commands `0x01`, `0x02`, `0x05`,
`0x06`, `0x07`, `0x08`, `0x09`, `0x11`, `0x21`, `0x22`, `0x23`, and `0x26`,
plus the independent WQOTA service (`7033/2001/2002`). Deprecated user-mode
commands `0x03`, `0x04`, `0x24`, `0x25`, and business `0x31` remain absent.

This scope does not implement factory, UART, or cloud server internals. The
App exposes typed HTTPS-facing contracts for the security ticket, durable
archive, and firmware package services. An unavailable service is a visible
blocked state, never a simulated success.

## Session And Compatibility

`SessionController` remains the owner of one BLE connection. After service
discovery it subscribes only to business endpoints for business-frame routing,
performs the authoritative `0x01` read, and accepts the session only when
`ProtocolVersion == 3`. It then loads `0x11`, `0x05`, `0x06`, and optionally
`0x21` into typed session state.

Subscription, initial-read, version, authentication, transfer, and OTA
failures retain their exact stage and characteristic/opcode in safe logs and
in the recoverable UI failure. A failed initial read closes the link only
after that reason has been recorded. The App does not silently fall back to
another protocol version.

WQOTA uses a separate client and its own notification subscription to `2002`.
Business `0xED` decoding must never receive WQOTA notifications.

## Security

`DeviceAuthController` owns one short-lived grant. It uses `TicketGateway` to
obtain ticket and proof-key material only for the requested action. Bind and
authenticate use the V2 `0x09` envelope and proof verification already
defined in `DeviceAuthProtocol`.

Unbind is explicit: `clearRequest (0x30)`, user confirmation, ticket issue,
`clearConfirm (0x31)`, `clearStatus (0x32)` polling, then local grant and file
download checkpoint deletion only after the device confirms completion.
Files, realtime audio, OTA, device configuration, and clear operations are
enabled only when the grant contains their documented scope bit.

## Configuration And Recording

The Device page displays authoritative information for device metadata,
battery, storage, privacy, consent, and file count. Configuration UI writes
the complete `0x02` payload, including current UTC seconds. Consent and
privacy duration use the documented `0x06` subcommands. Values are refreshed
from the device after a successful write.

Hardware recording uses `0x07` actions `0`, `1`, `2`, and `3`, with `0x87`
responses and notifications driving the visible record state. Actions remain
disabled while a command is in flight or required permission is absent.

## File Import And Archive

The file flow is strictly ordered:

1. Page through `0x22` and preserve the entire 17-byte filename slot.
2. Read `0x26/0x01` metadata.
3. Read `0x23` chunks from the stored checkpoint, then verify length and
   CRC-32/ISO-HDLC before promoting the local audio file.
4. Send the verified file identity, metadata and local path to `ArchiveGateway`.
5. Send `0x26/0x02` with the original slot, exact length, CRC32, and success
   result only after `ArchiveGateway` returns durable success.

The archive failure leaves the verified local copy and the device file intact,
and offers a retry from the archive stage. A device archive state other than
the documented success state is an error.

## Realtime Audio

`RealtimeAudioController` owns the `FA18` subscription and exposes stream
state, bytes received, and recoverable errors. It enables `0x02.AudioStream`,
uses `0x07` when user-initiated recording is required, and accepts `0x08`
payloads into a bounded queue. Queue overflow stops the stream cleanly,
disables `AudioStream`, and records an error rather than growing memory.

The initial UI supports live reception status and saving an ordered raw
capture. Playback or codec decoding is enabled only when firmware's audio
payload codec is identified by the received metadata; unknown content remains
an exportable capture, not falsely labeled playable audio.

## OTA

`FirmwarePackageGateway` returns a package whose manifest contains target
device identifiers, version, payload length, CRC-32, the captured WQOTA
four-byte prefix/flags, and the payload bytes or verified local path. The App
rejects a package with invalid length, CRC32, target identifiers, or missing
prefix before writing to `2001`.

`WqotaUpdateController` runs the documented sequence: subscribe `2002`, read
capability (`0x02`), query position (`E1`), admission (`E2`), enter (`E3`),
windowed CRC32 block writes (`E5`), refresh (`E6`), sync polling (`E8`), and
completion/reconnect/version verification. It sends `E4` on user cancellation
or recoverable transfer failure. Progress is persisted by device identity and
package hash so reconnect can resume only the same verified package.

## Platform Requirements

On Android API 23-30 the scan flow requests location permission before BLE
scan; on API 31+ it requests `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT`. Android
uses the existing enable-Bluetooth system request only after Connect permission
is granted.

On iOS the App declares Bluetooth usage and `bluetooth-central` background
mode. iOS does not attempt to turn Bluetooth on programmatically; it directs
the user to the system Bluetooth context and retries scanning on resume.
Production ticket, archive, and firmware services require HTTPS. Any debug
HTTP exception is explicit, debug-only, and limited to the configured host.

## Verification

Unit tests cover packet lengths, response matching, V3 rejection, permission
selection, auth clear ordering, archive-before-confirm ordering, realtime
queue bounds, WQOTA sequence and resume. Widget tests cover disabled controls
and visible blocked states. `flutter analyze`, `flutter test`, and Android
debug APK build must pass. Android 10/11, Android 12+, and iOS 13+ physical
device validation covers scan, connect, required subscriptions, authentication,
download resume, archive confirmation, background reconnect, and OTA.
