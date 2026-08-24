# AIPIN 声存 Branding and Package Migration Design

## Purpose

Replace the internal EVT identity with a consumer-facing identity for the
existing intelligent recording companion. The product continues to support
hardware connection and independent local recording; this change affects its
name, icon, and distribution identifiers only.

## Brand Definition

| Item | Decision |
| --- | --- |
| Display name | `AIPIN 声存` |
| Tagline | `让声音表达更简单` |
| Icon concept | The selected "随录" sound-wave mark: a central recording stroke, two restrained side waves, and a small archival dot. |
| Icon colors | `#19212B` background and `#F0F4F8` mark. |
| Visual language | Retain the current restrained, monochrome material theme and 8 px component radius. |

The icon contains no text. This keeps it recognizable at Android launcher,
iOS Home Screen, notification, and Settings sizes. The full product name is
provided by the platform label rather than baked into the bitmap.

## Identifier Migration

| Surface | Current | Target |
| --- | --- | --- |
| Android namespace | `com.xkp.evt_ble_app` | `com.aigutta.aipin` |
| Android application ID | `com.xkp.evt_ble_app` | `com.aigutta.aipin` |
| Android Kotlin package/path | `com.xkp.evt_ble_app` | `com.aigutta.aipin` |
| Android/Dart method channel | `com.xkp.evt_ble_app/bluetooth` | `com.aigutta.aipin/bluetooth` |
| iOS Runner bundle ID | `com.xkp.evtBleApp` | `com.aigutta.aipin` |
| iOS RunnerTests bundle ID | `com.xkp.evtBleApp.RunnerTests` | `com.aigutta.aipin.RunnerTests` |
| Dart package | `evt_ble_app` | `aipin` |

All Dart package imports, test imports, and project metadata will use the new
Dart package name. Existing class and file names remain unchanged unless they
are user-facing, keeping this migration focused and reviewable.

## Platform Assets and Labels

1. Generate one square 1024 px raster source for the approved icon concept.
2. Generate standard Android launcher densities from that source and replace
   each existing `mipmap-*/ic_launcher.png` file.
3. Generate each required iOS `AppIcon.appiconset` rendition from the same
   source and retain the existing `Contents.json` mapping.
4. Set the Android application label and iOS `CFBundleDisplayName` and
   `CFBundleName` to `AIPIN 声存`.
5. Update the README title and product references while retaining `EVT` only
   where it denotes the pre-existing wire protocol or database schema.

## Compatibility and Data Impact

Android and iOS treat the target application IDs as a different application.
An existing `evt_ble_app` install cannot upgrade in place and its sandboxed
recordings, Drift database, preferences, and permissions do not migrate. The
old package remains untouched on a device until a user removes it. The new
package receives fresh platform permissions and a new private storage area.

The BLE protocol, device profile, local recording behavior, database schema,
and permission declarations are not otherwise changed. The method channel is
renamed on both Dart and Android together so Bluetooth enablement continues to
work after the namespace move.

## Verification

1. Run `dart format --set-exit-if-changed lib test`.
2. Run `flutter analyze` and `flutter test` after import and identifier
   migration.
3. Build Android debug APK with `flutter build apk --debug` and inspect the
   generated package name with Android build output.
4. On macOS/Xcode, build the iOS Runner target and confirm the bundle ID and
   app icon in the archive.
5. Install the Android build to verify launcher label, rendered icon,
   Bluetooth enable dialog, local recording, and standard light/dark surfaces.

## Acceptance Criteria

- Android and iOS show `AIPIN 声存` as the application name.
- Both launchers use the selected dark square and ivory sound-wave mark at all
  generated icon sizes.
- Android builds with `com.aigutta.aipin`; iOS project configurations use the
  same Runner bundle identifier.
- The Dart package and all first-party imports no longer use `evt_ble_app`.
- Native Bluetooth enablement still communicates over its matching renamed
  method channel.
- Static analysis and the full Flutter test suite pass.
