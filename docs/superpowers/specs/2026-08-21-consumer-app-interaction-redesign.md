# Consumer Recording App Interaction Redesign

## Product Decision

Transform the current internal EVT workbench into a consumer-facing smart recording-device companion. Users must understand their next action without seeing BLE, protocol, VAD, evidence, or test terminology as primary navigation.

This is a presentation and interaction redesign. Existing BLE, local-recording, persistence, and platform contracts stay intact unless a subsequent implementation plan explicitly changes a contract.

The approved product rules are:

1. The primary audience is a normal consumer.
2. The App is both an AIPIN smart-device companion and an independent phone-local recorder.
3. Current hardware behavior is observation only. The App cannot start hardware recording, synchronize device audio, or play device audio.
4. Phone-local recordings are independently playable, renameable, and deletable.
5. Engineering checks and evidence remain contextual advanced help, never first-level consumer destinations.

## Research Basis

- [Material 3 navigation bar guidance](https://m3.material.io/components/navigation-bar/overview) recommends three to five stable, equally important mobile destinations. This product uses three persistent destinations and excludes transient actions from the bar.
- [Android Bluetooth permissions guidance](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions) defines nearby-device access as a runtime permission. The product requests it only after the user starts a related connection action.

## Information Architecture

| Destination | User goal | Content | Excluded capability |
| --- | --- | --- | --- |
| 首页 | Understand device readiness and take the next useful action. | Device summary, device action, direct local-recording entry. | Raw scanner, protocol and evidence controls. |
| 录音 | Start or continue phone-local recording. | Start action, active state, recent recording shortcut. | Fake device-recording controls. |
| 记录 | Review saved content. | 本机录音 and separate 设备活动 sections. | Device-audio playback before synchronization exists. |

The settings icon appears on 首页 and device detail. It owns visual preferences, permission state, connection help, and version information.

## First Use

The first launch presents one brief welcome page with two routes:

- 连接我的设备 starts connection preparation. It explains Nearby Devices permission before opening the system permission dialog.
- 先用本机录音 enters the normal home experience. Microphone permission remains deferred until recording starts.

The App does not request Bluetooth and microphone permissions automatically or in a chain of startup dialogs. A user can always use local recording without a device connection.

## Home States

首页 contains, in order, the title and settings button, a 我的设备 card, a high-emphasis 本机录音 action labelled 无需连接设备, and a low-emphasis device recording-status row. The status row is never a hardware-recording button.

| Device state | User-facing content | Primary action | Recovery behavior |
| --- | --- | --- | --- |
| No device | 连接你的录音设备 | 连接设备 | Local recording stays enabled. |
| Known but disconnected | Device name and 尚未连接 | 连接设备 | Card opens connection help. |
| Permission needed | Clear nearby-device reason | 继续 | 暂不 returns to usable home without repeated prompting. |
| Bluetooth unavailable | 请打开蓝牙 or capability message | 前往设置 when applicable | Recheck state after returning from settings. |
| Finding | 正在查找附近设备 with progress | 取消查找 | Local recording stays enabled. |
| Candidate found | Name and signal strength | 连接 [设备名] | One candidate selected at a time. |
| Connecting | Name and progress | 取消连接 | Never show GATT/protocol wording. |
| Connected | Name, battery when available, signal, update time | 查看设备 | Card opens device detail. |
| Failed | Concrete connection reason | 重新连接 | 查看帮助 opens a recovery checklist. |

Completion and failure always appear in the active card or screen. A toast is never the sole confirmation or error surface.

## Device Connection And Detail

The connection sequence is: 首页 -> 连接设备 -> permission rationale -> system permission -> 查找附近设备 -> select candidate -> connecting -> device detail.

The rationale says the permission finds and connects the recording device and is not used for location inference. On denial, the connection screen provides 前往系统设置 and 暂不连接; users are never trapped behind a disabled scan button.

Device detail uses the device name as title and includes:

- connection quality, battery, and last-update time;
- observed recording state only: 正在录音, 未在录音, or 暂时无法获取;
- 连接帮助, 重新连接, and destructive 断开设备 actions;
- contextual 设备检查 entry for the existing advanced observation/evidence path.

断开设备 uses a shared confirmation sheet that states no device data is reset or deleted. An unexpected drop changes the header to 已断开, freezes live values with their timestamp, and makes 重新连接 the only primary action.

The App must not display 开始设备录音, 设备录音文件, or 播放设备录音 until the hardware protocol and file-transfer contract explicitly support each action.

## Phone-Local Recording

All local-recording entries lead to one flow: start -> microphone rationale -> system permission -> starting -> recording <-> paused -> ending -> saved -> records.

The microphone rationale is displayed only after an explicit start action. It states that the microphone records and saves an App-local audio file. Denial shows 前往系统设置 and 暂不录音; it creates no library record.

The active recording page has:

- red status dot plus 正在录音 text;
- fixed-width tabular elapsed timer;
- restrained live level display only while recording;
- accessible icon buttons for pause/resume and stop;
- back confirmation sheet: 继续录音 or 结束并保存.

Pause changes the state label to 已暂停 and swaps the pause action to resume. End enters 正在保存, prevents duplicate stop taps, then confirms duration and offers 继续录音 and 查看全部记录.

### Background And Failure States

- Valid background or locked-screen capture retains the existing Android foreground notification and iOS audio background strategy. Android notification text is 正在录音 and exposes the same safe stop action.
- A system interruption with a playable partial file shows 录音已中断，已保存可用部分; it is stored as interrupted, not normal completion.
- An unrecoverable interruption shows 录音未能保存 with a concrete retry path.
- Storage exhaustion shows 无法保存录音; the UI never claims an unavailable file was saved.
- Starting local recording stops local playback first. Device recording-state changes do not alter local recording state or send BLE commands.

## Records

记录 starts with a text segmented control:

- 本机录音 is the default and contains only real App-local audio.
- 设备活动 contains saved connection changes, state changes, and completed device checks. It contains no unsupported device audio.

The selected segment has text and visual state, preserves per-tab scroll position, and does not alter global navigation.

### Local Recording List

Items group by local calendar day and order newest first. A row has at least a 44px touch target and exposes play/pause, title, creation time, duration, 本机录音 source label, inline active playback progress, and an overflow menu.

Only one local file plays at once. The overflow menu contains only 重命名 and 删除. Rename opens a shared editable sheet with selected existing text; blank or whitespace-only input has inline validation. Delete opens a shared confirmation sheet that says the App-local audio file will also be removed. A failed file deletion retains the row and exposes 重试删除.

The empty state says 还没有本机录音 and offers one 开始录音 action. Loading uses neutral skeletons. Refresh failure retains last valid data and provides 重试. An unavailable file displays 文件不可用 inline with explicit retry/removal; it is never silently deleted.

设备活动 uses consumer wording: 设备已连接, 设备已断开, 录音状态已更新, and 已完成设备检查. Its empty state explains how connection or a device check adds activity.

## Settings And Permission Recovery

| Group | Items | Interaction |
| --- | --- | --- |
| Display | 外观 | Shared selection sheet: follow system, light, dark. Selection persists and changes without restart. |
| Permissions and device | 麦克风, 附近设备, 连接帮助 | Text status and a contextual 前往系统设置 recovery action when denied. |
| About | 版本信息 | Read-only version and product details. |

Returning from settings rechecks actual system capability. The App never treats a permission as granted before the operating system reports it.

## Visual System

All screens use one semantic design system. Presentation code must not add local hex colors or a separate visual palette.

| Role | Light | Dark |
| --- | --- | --- |
| Canvas | #F8F6F3 | #11100E |
| Surface | #FFFFFF | #1D1B18 |
| Subtle/pressed surface | #F0EDE8 | #2B2824 |
| Primary text | #1C1A17 | #EFECE7 |
| Secondary text | #6B655C | #A69E94 |
| Divider | #E5E1DA | #2F2C27 |
| Primary action | #19212B | #F0F4F8 |

Use the platform system sans-serif font with regular, medium, and semibold weights. Headings are 20-26sp, body text 14-16sp, and supporting text is never below 12sp. Timers, duration, and file size use tabular figures.

Controls, cards, menus, sheets, and dialogs use at most 8px corner radius. All touch targets are at least 44x44px. Every status includes text and an icon as well as color.

## Motion, Accessibility, And Back Behavior

- Page transition: 180ms opacity with small positional transition.
- Card-state changes: 160ms cross-fade/size transition.
- Playback progress: smooth monotonic update; recording level animates only while active.
- No decorative looping animation, gradient, layout-shifting load state, or toast-only outcome.
- Android back and iOS back gesture return to the previous meaningful state. Active recording opens its two-action exit sheet instead of ending silently.
- Destination switches preserve state and never stop a recording or disconnect a device.
- Respect reduced motion, safe areas, text scaling, narrow phones, and tablets. Text may wrap but never overlap or clip an action.

## Implementation Boundaries

Keep the existing feature-first architecture and move presentation work into focused units:

| Area | Responsibility |
| --- | --- |
| app/ | Shell navigation, theme, dependency assembly, active-device coordination. |
| features/home/presentation/ | Consumer home, device-summary card, contextual action states. |
| features/device_discovery/presentation/ | Connection preparation, candidate selection, permission and availability recovery. |
| features/device_session/presentation/ | Consumer device detail and contextual advanced help. |
| features/local_recording/presentation/ | Start, active capture, library, playback, rename, deletion. |
| features/evidence/presentation/ | Consumer-readable device activity while retaining immutable evidence rules. |
| core/design_system/widgets/ | Navigation, status/action card, confirmation sheet, permission rationale sheet, dialog, accessible icon buttons. |

Existing domain controllers, Drift records, BLE ports, and audio ports remain the source of truth. Presentation code must not call a plugin, mutate a BLE stream, or turn an observed device event into an implied hardware action.

## Acceptance Criteria

1. First-time users choose device connection or offline recording without unrelated system permission prompts.
2. Every home-device state uses ordinary language and one clear next action.
3. Bottom navigation contains only 首页, 录音, and 记录, with stable state across navigation.
4. Users can start, pause, resume, end, recover, play, rename, and delete local recordings without device connection.
5. Device detail clearly distinguishes observed recording status from phone-local audio and never exposes unsupported hardware controls.
6. Permission denial, Bluetooth unavailability, discovery failure, disconnection, interruption, missing file, delete failure, and storage failure provide contextual recovery actions.
7. Theme, type, buttons, sheets, dialogs, motion, and accessibility rules are consistent in light and dark mode.
8. Existing BLE observation, evidence immutability, local-recording lifecycle, Android foreground capture, and iOS audio-session behavior remain intact.

## Verification Scope

Add focused widget coverage for every acceptance state, light/dark tokens, and enlarged text. Preserve controller tests for recording and device state. Verify on Android and iOS: permission flows, Bluetooth-off recovery, connection, background/lock-screen recording, interruption, playback, rename/delete, narrow-phone/tablet layout, and dark mode. Device activity uses real connected hardware; no simulated event is presented as a real device result.

## Out Of Scope

This redesign does not authorize hardware recording controls, hardware-audio synchronization, cloud backup, transcription, sharing, accounts, firmware changes, or BLE protocol changes. Each requires a separate product decision and implementation plan.
