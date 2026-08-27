# ASR Aggregate Note API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align ASR and AI-summary requests with the 2026-08-27 testing API contract, using aggregate notes for segmented recordings.

**Architecture:** Keep `TemporaryAsrGateway` as the application boundary. Add an aggregate-source DTO and API method there, then let `ResearchCaptureProcessingController` choose the aggregate method only when a capture contains more than one completed ASR segment. The HTTP gateway remains responsible for endpoint JSON, while the controller owns segment order and retry flow.

**Tech Stack:** Flutter, Dart, `dart:io` HTTP client, Flutter test.

---

### Task 1: Extend the ASR Gateway Contract

**Files:**
- Modify: `lib/features/research_beta/domain/temporary_asr_gateway.dart`
- Modify: `test/support/fake_research_beta.dart`
- Test: `test/features/research_beta/application/research_capture_processing_controller_test.dart`

- [ ] **Step 1: Write the failing controller expectation for aggregate summaries**

```dart
expect(gateway.submittedAudioPaths, <String>[
  '/research/capture-1.segment-0000.m4a',
  '/research/capture-1.segment-0001.m4a',
]);
expect(gateway.aggregateSources.single.map((source) => source.segmentIndex),
    <int>[0, 1]);
```

- [ ] **Step 2: Run the controller test to verify it fails**

Run: `flutter test test/features/research_beta/application/research_capture_processing_controller_test.dart --reporter compact`

Expected: compilation failure because the aggregate gateway DTO and fake capture list do not exist, or an assertion showing that the original M4A was submitted for summary.

- [ ] **Step 3: Add the minimal contract and fake support**

```dart
class AsrAggregateSource {
  const AsrAggregateSource({
    required this.segmentIndex,
    required this.jobId,
    required this.transcript,
  });

  final int segmentIndex;
  final String jobId;
  final AsrTranscript transcript;
}

Future<AsrOutcome<AsrNoteTask>> createAggregateNote({
  required String recordingId,
  String? title,
  required List<AsrAggregateSource> sources,
});
```

- [ ] **Step 4: Re-run the controller test**

Run: `flutter test test/features/research_beta/application/research_capture_processing_controller_test.dart --reporter compact`

Expected: still fails only because production processing still submits the original M4A for a segmented summary.

### Task 2: Implement Documented HTTP Aggregate and Status Contracts

**Files:**
- Modify: `lib/features/research_beta/data/temporary_asr_http_gateway.dart`
- Modify: `lib/app/providers.dart`
- Test: `test/features/research_beta/data/temporary_asr_http_gateway_test.dart`

- [ ] **Step 1: Write the failing aggregate HTTP request test**

```dart
expect(request.uri.path, '/api/meeting-notes/aggregate');
expect(body['recording_id'], 'capture-1');
expect(body['sources'], <Object?>[
  <String, Object?>{
    'segment_index': 0,
    'job_id': 'job-1',
    'relative_path': 'capture-1.segment-0000.m4a',
    'variant': 'original',
    'engine': 'sensevoice',
  },
]);
```

- [ ] **Step 2: Run the HTTP gateway test to verify it fails**

Run: `flutter test test/features/research_beta/data/temporary_asr_http_gateway_test.dart --reporter compact`

Expected: compilation failure because `createAggregateNote` is unavailable.

- [ ] **Step 3: Implement the JSON mapping and documented generation status**

```dart
final response = await _sendJson(
  method: 'POST',
  path: '/api/meeting-notes/aggregate',
  body: <String, Object?>{
    'recording_id': recordingId,
    if (title?.trim().isNotEmpty ?? false) 'title': title!.trim(),
    'sources': sources.map(_aggregateSourceBody).toList(growable: false),
  },
);
```

Set `verifiedGenerationCompletionStatuses` in `providers.dart` to `{ 'succeeded' }`; retain `queued`, `running`, and `failed` mappings. Keep `ASR_API_BASE_URL` as the sole environment address source and do not hard-code the document's internal test host.

- [ ] **Step 4: Re-run the HTTP gateway test**

Run: `flutter test test/features/research_beta/data/temporary_asr_http_gateway_test.dart --reporter compact`

Expected: PASS, including aggregate body, `200`/`202` identifier mapping, and `succeeded` status handling.

### Task 3: Route Segmented Summaries Through Aggregate Notes

**Files:**
- Modify: `lib/features/research_beta/application/research_capture_processing_controller.dart`
- Modify: `test/features/research_beta/application/research_capture_processing_controller_test.dart`

- [ ] **Step 1: Preserve segment job IDs and result sources in order**

```dart
final sources = <AsrAggregateSource>[];
for (final segment in segments) {
  final result = await _completeSegmentTranscription(
    capture,
    segment.jobId!,
    deadline,
  );
  // Return the documented source quadruple with the immutable segment index.
  sources.add(AsrAggregateSource(
    segmentIndex: segment.index,
    jobId: segment.jobId!,
    transcript: transcript,
  ));
}
```

- [ ] **Step 2: Create the correct summary task for each recording shape**

```dart
final noteResult = capture.hasMultipleAsrSegments
    ? _gateway.createAggregateNote(
        recordingId: capture.id,
        sources: sources,
      )
    : _gateway.createNote(
        jobId: sourceJobId,
        transcript: sourceTranscript,
      );
```

Delete the original-file summary upload branch. Summary retries rebuild the aggregate request from the completed segment jobs and result sources, without resubmitting audio.

- [ ] **Step 3: Run focused controller regressions**

Run: `flutter test test/features/research_beta/application/research_capture_processing_controller_test.dart --reporter compact`

Expected: PASS; segmented runs submit only segment audio and call aggregate notes, while single-file runs still call `createNote`.

### Task 4: Verify the Integration Boundary

**Files:**
- Test: `test/features/research_beta/data/temporary_asr_http_gateway_test.dart`
- Test: `test/features/research_beta/application/research_capture_processing_controller_test.dart`

- [ ] **Step 1: Run static analysis**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 2: Run the two API-focused test files**

Run: `flutter test test/features/research_beta/data/temporary_asr_http_gateway_test.dart test/features/research_beta/application/research_capture_processing_controller_test.dart --reporter compact`

Expected: `All tests passed!`
