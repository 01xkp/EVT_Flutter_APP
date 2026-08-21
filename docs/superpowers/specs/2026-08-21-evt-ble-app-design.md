# EVT BLE App Design

## 1. Goal And Scope

EVT App is an internal Flutter validation instrument for an intelligent pendant. It verifies real device and firmware behavior; it is not a consumer companion application.

The first release closes this evidence loop:

`discover -> connect -> establish observability -> observe hardware behavior -> read final snapshot -> save evidence -> produce verdict`

In scope:

- BLE broadcast discovery, connection, disconnect, and controlled reconnect.
- Read-only, no-binding state observation using notifications and initial/final snapshots.
- VAD recording, battery/charging, standby power, recovery, LED, and recovery-key test scenarios.
- Sample and firmware versions, status timeline, diagnostics, local evidence, and verdicts.
- Android and iOS support with system light/dark modes.

Out of scope:

- Consumer onboarding, device binding, account/cloud synchronization, or remote device control.
- Treating a mock response, cached snapshot, or inferred value as a test result.
- Validating fields that current firmware does not expose.

## 2. Product Principles

1. Each session phase requires a real success result from the preceding phase.
2. Connected and observable are separate states. Observable requires successful status subscription and a usable initial snapshot.
3. A missing, refused, malformed, or stale field yields `unverifiable`; it never yields pass.
4. Evidence records source, timestamp, device identity, firmware version, and final verdict so another engineer can review it.
5. Mock data is restricted to UI and workflow development and cannot be persisted in an evidence bundle.

## 3. Information Architecture

### Discovery

The initial workbench scans for broadcast records matching the documented manufacturer prefix `A3 89`, service UUID `AF30`, and local name prefix `AIPIN`.

It presents a stable, signal-strength sorted device list with name, raw address, RSSI, and match reason. A device must be selected before the connect command enables.

### Device Session

After connection, the workbench progresses through service discovery, subscription, and initial read. The session dashboard only presents hardware facts that have arrived from the real device. It contains:

- Session summary and phase.
- Typed device snapshot values, including their protocol source and timestamp.
- Compact status/event/log segmented views.
- A state-gated observation command.
- An inline recording sheet for physical feedback; it does not navigate away from the session.

### Observation And Verification

Each observation is a named scenario with prerequisites, an event timeline, an initial snapshot, a final snapshot, optional human observations, and a verdict.

Scenarios include device access, VAD recording, charge and low battery, standby power, recovery, LED, and recovery key. The final verdict is `passed`, `failed`, or `unverifiable`, with a reason.

### Evidence

Evidence records are local-first. An `EvidenceBundle` contains device/sample identity, firmware version, session timestamps, snapshots, protocol events, manual notes, errors, the verdict, and an exportable diagnostic representation.

## 4. Visual System

The selected theme is the supplied Mobile Productivity Monochrome Theme. Light and dark modes use the same semantic roles and hierarchy.

| Role | Light | Dark |
| --- | --- | --- |
| Canvas | `#F7F8FA` | `#121416` |
| Surface | `#FFFFFF` | `#1B1E22` |
| Subtle surface | `#F0F2F5` | `#25292E` |
| Primary text | `#111315` | `#F3F5F7` |
| Secondary text | `#626A73` | `#B7BEC6` |
| Tertiary text | `#9299A1` | `#858D96` |
| Primary action | `#17191C` | `#F3F5F7` |
| Border | `#E3E6EA` | `#30353B` |
| Positive | `#117C72` | `#4AA99E` |
| Danger | `#C33E38` | `#E16B64` |

Design rules:

- Use platform system sans-serif with regular, medium, and semibold weights. Data values use tabular numerals.
- Use 1 px separators and a maximum 8 px radius for controls and necessary framed surfaces.
- Maintain 44 x 44 px minimum tap targets and allow the system font scale to reflow content without clipping.
- Keep dashboard content ordered as summary, trend/timeline, then detail.
- Primary commands use the graphite selected treatment. Secondary commands use a subtle surface or outlined treatment.
- Dialogs are concise sheets with explicit cancel and destructive actions. They preserve the current session context.
- Status is expressed by label and icon in addition to semantic color.
- Motions are 160-220 ms opacity or positional transitions. No bounce, glow, gradients, decorative chart colors, or large animated effects.
- Light/dark defaults follow the system; Settings exposes an optional explicit light or dark override.

## 5. Component Contract

The design system exposes semantic components rather than raw screen-level styling:

- `AppScaffold`, `AppAppBar`, `AppBottomNavigation`, `AppSheet`.
- `AppButton` variants: primary, secondary, destructive, loading, disabled.
- `StatusBadge`, `PhaseIndicator`, `EmptyState`, `ErrorState`, and neutral skeleton loaders.
- `DataRow`, `MetricValue`, `SegmentedControl`, and timeline/event items with stable value columns.
- `AppDialog` and `RecordObservationSheet`.

All components read colors, typography, spacing, motion, and accessibility values from shared semantic theme tokens. Screens do not introduce raw colors or local component variants.

## 6. Architecture

Adopt a feature-first layered architecture. Each feature has focused `presentation`, `application`, `domain`, and `data` layers. Files stay bounded by one responsibility; shared code is extracted only when multiple features consume a stable abstraction.

```text
lib/
  app/                    bootstrap, routing, theme, dependency assembly
  core/
    ble/                  transport contracts and platform adapter
    protocol/             frame codec, typed protocol values, CRC validation
    persistence/          local database and migrations
    diagnostics/          structured errors and export formatter
    design_system/        tokens and reusable UI components
  features/
    device_discovery/
    device_session/
    observation/
    evidence/
    settings/
```

Responsibilities:

- Presentation renders immutable view state and delegates user intent to application controllers.
- Application coordinates use cases, state transitions, retries, and prerequisites.
- Domain defines state phases, entities, verdict policies, and repository/transport contracts.
- Data owns real BLE calls, protocol decoding, persistence, and concrete repository implementations.
- UI never consumes raw BLE bytes, directly opens the database, or derives a validation verdict.

State management uses a provider-based dependency graph with testable controllers. The real BLE plugin remains hidden behind `BleTransport`, and all configuration-dependent service/characteristic UUIDs live in a typed device profile rather than page code.

## 7. Session State Machine

```text
environmentReady
  -> discovered
  -> connecting
  -> servicesDiscovered
  -> subscribing
  -> initialSnapshotRead
  -> observable
  -> observing
  -> verifying
  -> completed
```

Key gates:

- `connected` is emitted only after GATT service discovery succeeds.
- `observable` is emitted only after subscription and initial status reading succeed.
- An observation can start only from `observable`.
- A final verdict can be created only after scenario evidence and a final snapshot are evaluated.
- A reconnect creates a new transport sub-session. Recovery comparison references the new snapshot, never a cached value.

## 8. Typed Data Model

| Entity | Required purpose |
| --- | --- |
| `DeviceCandidate` | Discovery identity, raw address, manufacturer data, service UUIDs, RSSI, and discovery time. |
| `DeviceSession` | Session phase, transport capability, device profile, and connection/subscription timestamps. |
| `DeviceSnapshot` | Typed values with protocol source, device-read timestamp, receipt timestamp, and validation metadata. |
| `DeviceEvent` | Parsed notification/read event and its exact timeline position. |
| `ObservationRun` | Scenario, prerequisites, snapshots, manual observations, result, and reason. |
| `EvidenceBundle` | Immutable review/export aggregate for one completed test conclusion. |

The protocol codec validates `0xED | Length | CMD | Content | CRC16` frames before publishing typed values. Unknown commands and parse failures become structured diagnostics rather than silently discarded UI states.

## 9. BLE And Platform Strategy

The documented broadcast contract is parsed defensively because Android and iOS may merge advertising and scan-response data differently. Filtering uses AD structures and values, not a callback ordering assumption.

`BleTransport` provides scan, connect, discover services, subscribe, read, write where permitted, disconnect, and connection-state streams. A concrete Android/iOS adapter handles runtime permissions, Bluetooth state, platform callback differences, and expected disconnects.

The current documents do not provide all GATT service and characteristic UUIDs. The device profile must therefore be configuration-backed. The app can ship its workflow and scanning behavior, but real service discovery, reads, subscriptions, and command verification remain blocked until those UUIDs and access properties are supplied.

Platform requirements:

- Android: request the applicable Bluetooth scan/connect permissions, clearly distinguish a system-disabled scanner from an empty scan result, and support modern Android permission behavior.
- iOS: supply the Bluetooth usage description, reflect unavailable Bluetooth states, and avoid requesting background behavior unless a concrete requirement requires it.
- Both: route denial and disabled Bluetooth into `environmentNotReady` with a direct remediation action.

## 10. Error And Recovery Policy

| Condition | UI state | Evidence effect |
| --- | --- | --- |
| Bluetooth disabled, permission denied, scanner unavailable | Environment not ready with remediation | No fabricated scan activity |
| Connect timeout or remote disconnect | Session interrupted; retain known evidence; controlled reconnect where enabled | Existing events retained with error timestamp |
| Status read rejected | Connected, status temporarily unreadable | Related observations are unverifiable |
| Missing field or invalid CRC | Data incomplete | Preserve diagnostic and last valid snapshot; no pass |
| Device action and reported state disagree | Firmware/device anomaly | Persist both observations and time relation |

Refresh failures retain the last successful content, show its update time, and expose retry. No state is indicated by color alone.

## 11. Testing And Verification

The implementation will use test-first development for observable behavior.

- Unit tests cover broadcast filtering, frame parsing, CRC errors, verdict policies, session transition guards, and evidence serialization.
- Controller tests cover environment failures, connection progress, subscription/read gates, reconnect behavior, and unverifiable outcomes.
- Widget tests cover component state variants, accessible labels, disabled commands, light/dark theme tokens, and enlarged text layouts.
- Integration tests on Android and iOS cover permission flows, scan/connect/subscription with a real device profile, disconnect/reconnect, and evidence persistence.
- Visual checks validate the monochrome theme, component sizing, and non-overlapping text at phone and tablet widths.

## 12. Acceptance Criteria

1. A tester can discover a matching device, connect, subscribe, read a snapshot, run an observation, verify it, and save evidence without leaving the workbench context.
2. The app never shows observable, passed, or verified based on a cache, a mock, or an incomplete real-device response.
3. Every exported result identifies the device, firmware, timestamps, sources, observed values, errors, and verdict reason.
4. Android and iOS present the same state hierarchy and recoverable permission/Bluetooth guidance.
5. All screens use the selected monochrome design tokens and standard components in light and dark modes.
6. New features fit the feature-first layers without expanding a single UI, controller, or service file into a catch-all module.
