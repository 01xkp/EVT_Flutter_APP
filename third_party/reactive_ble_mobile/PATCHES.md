# Local Patch Record

Source: `reactive_ble_mobile` 5.5.0 from pub.dev.

## Android legacy advertising scan

`ReactiveBleClient.kt` uses `ScanSettings.Builder.setLegacy(true)` instead of
the upstream `false` value on Android 8.0 (API 26) and newer. Android 7.x
keeps its platform default because the method is not available before API 26.

The EVT V1.6 firmware publishes its `AIPIN_XXXX` name, `AF30` service UUID,
and `A3 89 + BtAddressRaw` manufacturer data through a legacy primary
advertisement and scan response. Android's extended-only scan misses those
packets. The scan setting is Android-only; the iOS CoreBluetooth implementation
is kept unfiltered as described below.

When upgrading the plugin, reapply this behavioral patch and verify device
discovery on Android 7.x and Android 8+ before replacing this vendor copy.

The app manifest intentionally sets `BLUETOOTH_SCAN` with
`neverForLocation`. The App requests Android 12+ nearby-device access without
location, and the pinned RxAndroidBle permission gate requires this flag to
avoid incorrectly reporting an unauthorized scan because fine location was not
granted. EVT discovery remains unfiltered at the app layer; this permission
declaration does not add an App-side advertisement filter.

## iOS unfiltered foreground scan

`Central.swift` converts an empty service list to `nil` before calling
`CBCentralManager.scanForPeripherals`. CoreBluetooth documents `nil` as the
unfiltered scan form; the EVT App begins unfiltered so it can receive both the
legacy primary advertisement and its Scan Response before validating
`A3 89`, `AF30`, and `AIPIN_XXXX` in Dart.

This remains a foreground scan rule. iOS background discovery is intentionally
not relied on by the App's reconnect flow because CoreBluetooth requires an
explicit advertised-service filter and substantially throttles background
scanning.

## Notification setup acknowledgement

`ReactiveBleNotificationSetup.awaitNotificationSetup` is a public local
facade for the native `awaitNotificationSetup` method. It completes only after
the characteristic CCC has been acknowledged, rather than after Dart merely
starts a notification stream.

Android preserves RxAndroidBle's outer notification observable, which is
emitted after CCC setup. Darwin retains the matching CoreBluetooth
`didUpdateNotificationStateFor` result. Both implementations support a wait
registered immediately before or after the stream subscription and reject
replacement, cancellation, disconnect, invalid arguments, and unsupported
platforms with explicit errors. The application must still apply its own
timeout when no stream subscription is ever requested.

## EVT V1.6 CCC mode validation on iOS

CoreBluetooth exposes one `setNotifyValue` API for both notifications and
indications. The V1.6 DVT protocol nevertheless assigns a fixed mode: FA11,
FA12, FA15, FA16, FA17, FA19, FB11, FF11, FF12 and FF16 are Indicate; FA18,
FF13 and WQOTA `7033/2002` are Notify. The WQOTA mapping is qualified by its
service UUID because `2002` is a standard 16-bit UUID and must not alter an
unrelated peripheral. The Darwin implementation rejects a protocol
characteristic when the expected property is missing or when both Notify and
Indicate are advertised, because iOS cannot select the required CCC value in
that ambiguous case. Encryption-required variants of either property are
reported to Dart as the corresponding capability. Android selects the protocol
mode explicitly through RxAndroidBle and requires a real CCCD write for all of
these DVT response channels.

When upgrading the plugin, retain this validation and verify that a malformed
dual-mode EVT characteristic fails before any command is sent.

## Persistent Android receive subscription and diagnostics

Keep the outer RxAndroidBle setup observable subscribed for the whole GATT
subscription lifetime. Do not apply `take(1)`: its disposal unregisters the
local listener and disables the CCC. Subscribe to the inner values before
reporting readiness, propagate errors and unexpected completion, and prevent
obsolete instances from removing a replacement subscription.

The native debug bridge forwards CCC, writes, packet receipt and dropped-sink
diagnostics into the App's existing local logger. Control packets retain their
Debug hex bytes; FF13 native logs are sampled because Dart already records the
full file-transfer packet stream.

Android scan restarts wait for a 250 ms cooldown after a real stop. Cancelling
the scan also cancels a scheduled restart.
