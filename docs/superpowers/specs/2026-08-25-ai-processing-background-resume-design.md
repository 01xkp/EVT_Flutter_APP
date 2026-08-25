# AI Processing Background Resume Design

## Goal

Allow users to leave a recording detail page while AI transcription and summary generation continue. Preserve the remote task, resume status checks when the application returns to the foreground, and show one in-app completion toast without sending a system notification.

## Scope

- Applies to local recordings submitted for AI transcription and summary.
- Applies to uploads, transcription polling, and summary polling.
- Keeps the existing 30-minute processing deadline and retry behavior.
- Does not add Android foreground services, iOS background execution, push notifications, or local system notifications.

## User Experience

The recording detail page keeps its normal back navigation while AI processing is active. Leaving the page never cancels its capture or its server-side job. The detail page, records list, and other app destinations remain usable while processing continues.

If the app is active when a capture reaches the completed state, show a centered toast: `AI 转写和总结已完成`.

If the app is inactive when a capture completes, retain the completion notice in memory. When the app resumes, show the toast after recovery starts. If more than one capture completed while inactive, coalesce notices into one toast: `<count> 条 AI 处理已完成`.

An unsuccessful capture never produces a completion toast. Existing failed-state retry controls remain unchanged.

## Lifecycle And Recovery

`ResearchCaptureProcessingController` remains provider-owned rather than route-owned. Its existing persisted `ResearchCapture` processing state and remote task identifiers remain the source of truth.

On `inactive`, `paused`, `hidden`, or `detached`, the app does not cancel in-flight work. Mobile operating systems may suspend Dart execution in the background; this design does not claim continuous client-side polling while suspended. The remote job remains intact.

On `resumed`, `AppShell` calls `enforceRetention()` and `resumePending()`. `resumePending()` reads every nonterminal capture from local persistence and resumes from saved job, note, and generation-task identifiers. It never re-uploads audio when a job identifier already exists.

`AppShell` listens to the processing controller only after the AI feature is first used, preserving the current lazy AI database initialization on an unused home screen. It drains completed-capture notices from the controller and decides whether to display immediately or defer until the app is foregrounded.

## Polling Policy

The first remote status request is immediate. Every subsequent pending response uses the capture age, measured from `ResearchCapture.createdAt`, to choose its next delay:

| Capture age | Next status poll |
| --- | --- |
| Less than 1 minute | 2 seconds |
| 1 minute to less than 5 minutes | 5 seconds |
| 5 minutes or more | 10 seconds |

The same policy is used for transcription and summary status polling. Calculating from persisted capture creation time keeps the cadence conservative after an app background/foreground cycle or process recreation without a database migration.

## Architecture

Add a small pure `ResearchProcessingPollSchedule` application policy. It maps an elapsed duration to the next polling delay and is independently testable.

`ResearchCaptureProcessingController` uses the policy instead of a single fixed poll interval. When a capture transitions to `completed`, it appends the capture to a drainable completion queue before notifying listeners. Draining clears only delivered notices so a completion is shown once.

`AppShell` owns the foreground state and the listener binding. It queues completion notices received while backgrounded, calls existing recovery on foreground entry, then uses `AppToast` to display a single completion notice. No presentation page directly owns polling, navigation cancellation, or lifecycle recovery.

## Acceptance Criteria

1. A user can navigate back from a processing detail page without cancelling its persisted capture or remote job.
2. A capture that completes after the user leaves its detail page is available in records and produces one completion toast while the app is foregrounded.
3. A capture that completes while the app is inactive produces one completion toast after `resumed`; no system notification is sent.
4. On `resumed`, every persisted nonterminal capture is processed from its saved state and remote identifiers.
5. Pending transcription and summary checks use 2 seconds before one minute, 5 seconds until five minutes, then 10 seconds.
6. Failed captures, duplicate controller notifications, and a user staying on the detail page do not produce duplicate completion toasts.

## Verification

- Unit test the polling policy boundaries.
- Unit test processing completion notices are recorded exactly once and can be drained once.
- Widget test the recording-detail route can pop while a controllable AI task remains pending and completes later.
- Widget test the app-shell lifecycle queues a background completion, resumes pending work, and displays the correct centered toast once.
- Run focused research-processing, local-recording-detail, and app-shell tests, then `flutter analyze`.
