# AIPIN AI Voice Research Integration Design

## Status

Approved for implementation as an internal, temporary ASR integration in the AIPIN Flutter application. This design does not make the temporary ASR service suitable for production or sensitive recordings.

## Goal And Boundary

AIPIN keeps its existing offline local-recording experience and adds an explicit AI Voice path for the closed research Beta. The recording page has two entry points:

- **Start local recording** creates and keeps an offline local M4A recording. It never uploads audio.
- **AI Voice** records an independent research input and sends it through the temporary ASR and AI-summary flow after consent.

Every saved local recording also exposes an explicit **AI organize** action. It requires an upload confirmation and creates an independent research copy. It never changes the original local recording into a cloud-backed item.

All AI Voice records use `source_type = research_import`. The application must not describe, count, or export them as pendant captures. Pendant recording, BLE audio transfer, device binding, sync, OTA, public distribution, production accounts, and consumer privacy controls remain out of scope.

## User Experience

`RecordingHubPage` presents the existing local-recording primary action and a secondary AI Voice action. AI Voice opens the research-consent screen until the user has accepted the temporary-service disclosure, then opens a dedicated active recording page.

`RecordingListItem` adds a visible `auto_awesome_outlined` icon action with tooltip **AI organize** when a local recording is saved, playable, between two and sixty seconds, and has no existing research capture. The action shows an upload confirmation every time. Once a capture exists, the action becomes **View AI result** and never uploads the local file twice.

`RecordsPage` adds the third segmented view **AI Voice**, beside Local recordings and Device activity. It groups research captures as Needs review, Processing, and Handled. Card detail shows local playback, processing status, title, summary, tags, optional action context, expandable read-only machine transcript, separately editable corrected transcript, and feedback controls.

AI Voice uses the current design system, 44 px minimum tap targets, existing confirmation sheets, app dialogs, toast messages, and restrained animation. It displays no pendant, BLE, or hardware claims.

## Recording And File Ownership

The existing `local_recording` feature continues using its current controller, `LocalRecordings` table, and `recordings/` private directory. No AI state is added to `LocalRecording`.

The new `research_beta` feature owns a separate `research_captures/` private directory and a `ResearchCaptureFileStore`.

- Direct AI Voice recording writes a new audio file into `research_captures/`.
- AI organize first copies the original saved local M4A into `research_captures/`; it never moves or renames the original file.
- Deleting a research capture removes only its research copy and research metadata. It must not delete the original local recording.
- Deleting the original local recording does not delete an existing research copy or AI card.

Direct AI Voice recording config is M4A, AAC-LC, mono, 16 kHz, and 64 kbps. The existing local controller retains its current 44.1 kHz config. AI Voice rejects recordings shorter than two seconds, longer than sixty seconds, empty files, invalid file paths, and recording interruptions before upload.

## Architecture

The implementation follows the repository's presentation, application, domain, data, and Drift patterns.

```text
presentation: research consent, active AI recording, capture inbox, capture detail
application: research recording controller, capture processing controller, library controller
domain: ResearchCapture, state transitions, repositories, ASR gateway, analytics event contract
data: Drift repository, research file store, native HttpClient ASR gateway
core/persistence: ResearchCaptures, ResearchEvents, and ResearchAggregates tables with Drift migration
```

`ResearchRecordingController` is separate from `RecordingController` because their persistence, upload, deletion, and data-retention contracts differ. It may reuse `AudioRecorderPort`, `RecordingBackgroundPort`, and the existing player port. `RecordAudioRecorder` accepts an injected `RecordConfig`; the existing provider supplies the local config and a new provider supplies the AI Voice 16 kHz config.

`ResearchCaptureProcessingController` owns stage changes, persistence, polling, retry, and recovery. It does not render widgets and never owns UI navigation. Pages observe controllers through the existing Riverpod provider pattern.

## ASR Integration

The temporary endpoint is read from `String.fromEnvironment('ASR_API_BASE_URL')`; no endpoint is embedded in source. The feature is Android and iOS only, so the native `dart:io` `HttpClient` can call the HTTPS service directly and browser CORS is irrelevant. Empty configuration disables AI upload with an explanatory state.

The `TemporaryAsrGateway` uses only the documented endpoints:

1. `POST /api/jobs` sends the copied M4A as `files`, attaches an empty UTF-8 text `reference_files` attachment solely because the temporary evaluation service requires it, and sets `engines=sensevoice`, `language=zh`, and `semantic_eval=false`.
2. It persists `job_id` and polls `GET /api/jobs/{job_id}` every two seconds. `queued` and `running` remain pending; `completed` fetches `/results`; any other terminal value or non-null error fails transcription.
3. It accepts only a `flat_rows` item whose `success` is true and whose `transcript` is nonempty. It persists the exact `relative_path`, `variant`, and `engine` used to create the note.
4. It creates one note through `POST /api/meeting-notes` and stores both note ID and generation-task ID. Repeated responses reuse those IDs rather than resubmitting.
5. It polls the generation task every two seconds and reads the note only after observed completion. The task status enum and note fields are not documented; a non-sensitive integration fixture must establish the supported completion values and note-field mapper before the feature can transition production data to Completed.

The mapper only creates a card when it can read title, summary, tags, and optional action context from a verified note shape. Otherwise it marks `summaryFailed`, preserves the copied audio and machine transcript, and exposes a retry. It never invents a summary from opaque JSON.

The temporary service is public, unauthenticated, and not guaranteed to delete transcription jobs. Consent and confirmation state that it must not be used for sensitive recordings.

## State, Recovery, And Deletion

`ResearchCapture` stores an anonymous installation participant ID, origin (`directAiVoice` or `localRecordingUpload`), optional original local-recording ID, private research file path, duration, source type, ASR references, raw transcript, corrected transcript, card fields, processing state, inbox state, timestamps, and failure reason.

Processing states are `uploading`, `transcribing`, `summarizing`, `completed`, `uploadFailed`, `transcriptionFailed`, and `summaryFailed`. Inbox states are `processing`, `needsReview`, and `handled`. Opening a card records `openedAt` but does not handle it. Retain, edit, copy, useful feedback, and unuseful feedback mark it handled; only retain, edit, copy, and useful feedback count toward the required useful-reuse metric.

On application launch and resume, the processing controller loads nonterminal captures and continues from their persisted remote IDs. It never resubmits a job or note when a usable ID already exists. A 90-second processing timeout changes the capture to the relevant retryable failure state while preserving local data.

Deleting one AI capture attempts `POST /api/meeting-notes/{noteId}/permanent-delete` with `{ "confirm": true }`, then removes the local research copy and metadata. A remote-note failure is shown and recorded; it cannot block local deletion. The ASR API exposes no transcription-job deletion endpoint, so the application must not claim remote job deletion. Delete all research data performs the same local cleanup for all captures after confirmation.

## Research Signals And Retention

Research events are stored separately from capture content. They include only anonymous participant ID, capture ID, event type, processing stage, duration bucket, card action, quality feedback, daily-understanding response, and elapsed time. They never include audio, raw transcript, corrected transcript, title, summary, tags, or copied text. `ResearchAggregates` holds only participant-level counts, handled and useful-reuse counts, quality-feedback totals, and daily-understanding timing totals. The AI Voice area can export this aggregate payload for manual study calculation.

Every user sees the daily understanding prompt only on the first opened completed card for a local calendar day. Quality feedback offers transcription accurate/inaccurate and summary faithful/unfaithful.

The app stores research trial start time when consent is accepted. On launch and resume it derives and saves the content-free aggregate, then clears research audio, card metadata, and per-capture events at day 21. It retains only `ResearchAggregates` until twelve months, then deletes them. This is a local best effort; it cannot replace server-side expiry while the app is closed.

## Platform And Validation

Android adds only the Internet permission if it is absent. iOS uses HTTPS and the existing microphone declaration; no platform exception is required for the documented endpoint. Existing microphone permission, foreground recording service, interruption handling, and local playback behavior remain unchanged for local recordings.

Automated tests cover domain state transitions, audio validation, ASR request construction and error mapping, Drift migration and repositories, no-duplicate recovery, local-to-research copy and deletion separation, event redaction, expiry, controller behavior, and entry/list/detail widgets. Platform verification covers Android and iOS recording format, microphone denial, 60-second stop, background/resume recovery, direct AI Voice, explicit local upload, retry, deletion, and a non-sensitive temporary-ASR fixture. The real-service test is opt-in and must not be run with participant content.
