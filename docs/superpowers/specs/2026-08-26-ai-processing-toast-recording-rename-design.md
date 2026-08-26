# AI Processing Toast and Recording Rename Design

## Goal

Show the progress and completion of background AI transcription and summary
tasks without obscuring the recording detail experience. Let users rename local
recordings from every recording-list entry point, and consistently show that
name thereafter.

## Scope

This change covers locally recorded audio that a user explicitly submits for AI
processing. It does not alter audio upload, ASR polling, summary generation,
retention, BLE, or the generic application Toast API.

## User Experience

### AI processing notice

- The notice is a small, semi-transparent black surface at the top center of
  the safe area. It ignores pointer events and does not block user actions.
- A single active task follows this sequence in the same notice:
  `正在转写` with a spinner, then `正在总结` with a spinner, then
  `M-d HH:mm 完成` with a check icon.
- The completed state stays visible for two seconds before it disappears.
- When several tasks run at once, processing states are represented by one
  active notice. Completed tasks are placed into a FIFO completion queue and
  displayed individually for two seconds each. Completion notices are never
  coalesced.
- A transcription state takes precedence over a summary state while both are
  active, because a task cannot enter summary until its transcription has
  completed.
- The notice is hidden while a local recording detail page is visible. That
  page already exposes the matching inline state. The latest active state or
  queued completion notice is shown after leaving the detail page.
- While the app is inactive, no notice is rendered. Processing states and
  completion events remain available; when the app resumes, completed items are
  shown one at a time and pending work resumes through the existing recovery
  flow.
- Failures remain visible in the detail page and are not presented as success
  notices.

### Recording rename

- The existing title field remains the single persisted source of the local
  recording name.
- The existing rename bottom sheet is reused. It trims whitespace, accepts up
  to 60 characters, and rejects an empty name through the existing domain and
  controller validation.
- Both local-recording lists expose `修改标题` in their more-actions menu:
  the dedicated `本机录音` page and the `记录 > 本机录音` tab.
- The `记录` tab keeps its direct delete icon. Its more-actions menu contains
  only rename, so deletion remains a single-tap action followed by its existing
  confirmation dialog.
- Recording rows and the recording-detail title always render the persisted
  title. The generated timestamp title remains the fallback until a user saves
  a custom name.

## Architecture

### Processing controller

`ResearchCaptureProcessingController` remains the owner of persisted work and
of its processing lifecycle. It will expose a lightweight, drainable stream of
UI-safe state updates keyed by capture ID. Updates contain only the capture ID,
processing stage, and completion timestamp; they must never include transcript
or audio content.

The controller emits a stage update after each persisted transition into
transcribing or summarizing, and emits a completion update after the completed
capture is persisted. It retains the existing completion-drain behaviour for
recovery compatibility, adapting it to the richer update payload where needed.

### Global notice host

`AppShell` owns lifecycle visibility, route visibility, and event draining. A
dedicated design-system notice controller/widget owns rendering animation,
completion timing, and FIFO queueing. It receives generic task IDs and display
stages, so the design-system layer does not import research-domain classes.

The existing centered `AppToast` remains unchanged for ordinary notifications
such as save, copy, and export. The new AI notice is rendered in the shell
stack, positioned after the top safe-area inset, and uses the existing theme
motion duration for fade/scale transitions.

### Recording list integration

`LocalRecordingList` gains an optional rename callback and reuses
`RenameRecordingSheet`. `RecordsPage` provides the callback through its
existing `RecordingLibraryController`. No database schema or repository change
is required because `LocalRecording.title` is already persisted and
`RecordingLibraryController.rename` already reloads the ordered list.

## Error Handling

- The notification layer has no retry responsibility. Existing detail-page
  retry and regenerate actions remain the recovery path for failed work.
- A hidden notice must not consume completion events; on return to a visible
  shell it resumes the FIFO queue.
- Empty rename input continues to surface the controller error and does not
  overwrite the persisted title.

## Test Coverage

- Widget tests for the AI notice: top-center placement, spinner stage labels,
  summary transition, completion check state, two-second dismissal, and FIFO
  completion display.
- Controller tests verifying transition events are emitted once and contain no
  transcript text.
- App-shell tests for inactive-to-resumed completion queueing and suppression
  while a recording detail route is visible.
- Records-page widget test that opens the rename action, saves a name, and
  observes the renamed row while retaining direct deletion.

## Acceptance Criteria

- A user sees `正在转写`, then `正在总结`, then a timestamped `完成` notice
  for one background AI task after leaving its detail page.
- Completion notices for two tasks are displayed separately and in completion
  order for two seconds each.
- Existing ordinary center Toasts retain their current visual behaviour.
- A renamed local recording retains its name after the library reloads and that
  name is used in both recording lists and the detail title.
