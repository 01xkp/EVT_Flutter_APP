# ASR Single-Upload Concurrency Benchmark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an isolated Dart command-line benchmark that measures bounded concurrent submissions of one long audio file to the current ASR API, separating upload, transcription, and optional summary time.

**Architecture:** `tool/asr_benchmark.dart` composes a configuration parser, ASR HTTP transport, fixed-size worker pool, and JSON report writer. It has no Flutter UI, Riverpod, Drift, or production-gateway dependency; it receives a user-supplied path at runtime and does not retain transcript or summary bodies.

**Tech Stack:** Dart 3, `dart:io`, `dart:convert`, `ResearchProcessingPollSchedule`, and `flutter_test`.

---

## File Structure

| File | Responsibility |
|---|---|
| `tool/asr_benchmark.dart` | Entrypoint, aggregate-only terminal output, exit codes. |
| `tool/src/asr_benchmark/benchmark_configuration.dart` | Validates endpoint, input, concurrency, and timeout. |
| `tool/src/asr_benchmark/benchmark_models.dart` | Immutable results, nearest-rank aggregates, JSON-safe serialization. |
| `tool/src/asr_benchmark/asr_benchmark_transport.dart` | ASR HTTP transport and finite error categories. |
| `tool/src/asr_benchmark/asr_benchmark_runner.dart` | Worker pool, polling, retries, and staged timings. |
| `tool/src/asr_benchmark/benchmark_report_writer.dart` | Report output and concise safe summary. |
| `test/tool/asr_benchmark/*.dart` | Unit and local-HTTP contract tests. |
| `docs/qa/asr-single-upload-concurrency-benchmark.md` | Operator guide and live comparison matrix. |

### Task 1: Configuration and Metrics Models

**Files:**
- Create: `tool/src/asr_benchmark/benchmark_configuration.dart`
- Create: `tool/src/asr_benchmark/benchmark_models.dart`
- Create: `test/tool/asr_benchmark/benchmark_configuration_test.dart`
- Create: `test/tool/asr_benchmark/benchmark_models_test.dart`

- [ ] **Step 1: Write the failing configuration tests**

```dart
test('rejects non HTTPS endpoints and concurrency above jobs', () async {
  final audio = await _writeAudio('capture.m4a');
  expect(
    () => BenchmarkConfiguration.parse(
      arguments: <String>[
        '--audio', audio.path, '--jobs', '2', '--concurrency', '3',
        '--report', '${directory.path}/report.json',
      ],
      environment: const <String, String>{
        'ASR_API_BASE_URL': 'http://asr.example',
      },
    ),
    throwsA(isA<FormatException>()),
  );
});

test('accepts a valid bounded configuration', () async {
  final audio = await _writeAudio('capture.m4a');
  final value = BenchmarkConfiguration.parse(
    arguments: <String>[
      '--audio', audio.path, '--jobs', '8', '--concurrency', '4',
      '--summary', '--report', '${directory.path}/run.json',
    ],
    environment: const <String, String>{
      'ASR_API_BASE_URL': 'https://asr.example/api',
    },
  );
  expect(value.baseUri, Uri.parse('https://asr.example/api/'));
  expect(value.includeSummary, isTrue);
  expect(value.jobTimeout, const Duration(minutes: 45));
});
```

- [ ] **Step 2: Run the tests and verify they fail**

Run: `flutter test test/tool/asr_benchmark/benchmark_configuration_test.dart`

Expected: FAIL because `BenchmarkConfiguration` has not been created.

- [ ] **Step 3: Implement the configuration model and parser**

```dart
class BenchmarkConfiguration {
  const BenchmarkConfiguration({
    required this.baseUri,
    required this.audioFile,
    required this.jobCount,
    required this.concurrency,
    required this.includeSummary,
    required this.reportFile,
    required this.jobTimeout,
  });

  final Uri baseUri;
  final File audioFile;
  final int jobCount;
  final int concurrency;
  final bool includeSummary;
  final File reportFile;
  final Duration jobTimeout;

  static BenchmarkConfiguration parse({
    required List<String> arguments,
    required Map<String, String> environment,
  });
}
```

Require `ASR_API_BASE_URL`, `--audio`, `--jobs`, `--concurrency`, and
`--report`. Accept `--summary` and `--job-timeout-minutes`, defaulting timeout
to 45. Reject non-HTTPS endpoints, missing/empty audio, non-positive values,
and `concurrency > jobs`. Normalize the endpoint with a trailing slash. Read
only file existence and byte size, never audio content.

- [ ] **Step 4: Write failing aggregate/redaction tests**

```dart
test('uses nearest-rank percentiles and serializes no transcript field', () {
  final report = BenchmarkReport.fromResults(<BenchmarkJobResult>[
    _completed(1, const Duration(seconds: 1)),
    _completed(2, const Duration(seconds: 2)),
    _completed(3, const Duration(seconds: 3)),
  ]);
  expect(report.aggregate.totalP50Milliseconds, 2000);
  expect(report.aggregate.totalP95Milliseconds, 3000);
  expect(report.aggregate.totalP99Milliseconds, 3000);
  expect(jsonEncode(report.toJson()), isNot(contains('transcript')));
});
```

- [ ] **Step 5: Implement immutable result and aggregate models**

```dart
enum BenchmarkJobStatus { completed, failed, timedOut }

class BenchmarkJobResult {
  const BenchmarkJobResult({
    required this.ordinal,
    required this.status,
    required this.startedAt,
    required this.total,
    this.jobId,
    this.upload,
    this.transcription,
    this.summary,
    this.failureKind,
    this.pollCount = 0,
    this.requestCount = 0,
  });

  final int ordinal;
  final BenchmarkJobStatus status;
  final DateTime startedAt;
  final Duration total;
  final String? jobId;
  final Duration? upload;
  final Duration? transcription;
  final Duration? summary;
  final String? failureKind;
  final int pollCount;
  final int requestCount;

  Map<String, Object?> toJson();
}

class BenchmarkRunMetadata {
  const BenchmarkRunMetadata({
    required this.endpointHost,
    required this.audioByteLength,
    required this.jobCount,
    required this.concurrency,
    required this.includeSummary,
  });

  final String endpointHost;
  final int audioByteLength;
  final int jobCount;
  final int concurrency;
  final bool includeSummary;

  static Future<BenchmarkRunMetadata> fromConfiguration(
    BenchmarkConfiguration configuration,
  );

  Map<String, Object?> toJson();
}
```

`BenchmarkReport.fromResults` calculates P50/P95/P99 from completed total
durations with `max(1, ceil(n * percentile))`, returning `null` when no job
completes. Serialize milliseconds, counts, safe job IDs, state, and finite
failure categories only. Do not add fields for paths, audio bytes, response
bodies, transcripts, or summaries.

- [ ] **Step 6: Run the model and parser tests**

Run: `flutter test test/tool/asr_benchmark/benchmark_configuration_test.dart test/tool/asr_benchmark/benchmark_models_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit the core types**

```bash
git add tool/src/asr_benchmark/benchmark_configuration.dart tool/src/asr_benchmark/benchmark_models.dart test/tool/asr_benchmark/benchmark_configuration_test.dart test/tool/asr_benchmark/benchmark_models_test.dart
git commit -m "feat: add ASR benchmark configuration and metrics"
```

### Task 2: HTTP ASR Transport

**Files:**
- Create: `tool/src/asr_benchmark/asr_benchmark_transport.dart`
- Create: `test/tool/asr_benchmark/asr_benchmark_transport_test.dart`

- [ ] **Step 1: Write failing multipart and redaction contract tests**

```dart
test('submits full audio with the existing ASR multipart fields', () async {
  final resultFuture = transport.submit(audio);
  final request = await server.first;
  final body = await _readRequestBody(request);
  await _respondJson(request, <String, Object?>{
    'job_id': 'job-1', 'status': 'queued',
  });
  expect(request.uri.path, '/api/jobs');
  expect(body, contains('name="files"; filename="capture.m4a"'));
  expect(body, contains('name="reference_files"; filename="reference.txt"'));
  expect(body, contains('name="engines"\r\n\r\nsensevoice'));
  expect(await resultFuture, const BenchmarkSubmission('job-1'));
});

test('extracts source identifiers and discards transcript text', () async {
  final resultFuture = transport.fetchTranscriptSource('job-1');
  final request = await server.first;
  await _respondJson(request, <String, Object?>{
    'flat_rows': <Object?>[
      <String, Object?>{
        'success': true, 'transcript': 'do not retain this',
        'relative_path': 'capture.m4a', 'variant': 'original', 'engine': 'sensevoice',
      },
    ],
  });
  expect(await resultFuture, const BenchmarkTranscriptSource(
    relativePath: 'capture.m4a', variant: 'original', engine: 'sensevoice',
  ));
});
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/tool/asr_benchmark/asr_benchmark_transport_test.dart`

Expected: FAIL because the transport classes do not exist.

- [ ] **Step 3: Define the transport contract and implement HTTP requests**

```dart
abstract interface class AsrBenchmarkTransport {
  Future<BenchmarkSubmission> submit(File audioFile);
  Future<BenchmarkRemoteState> pollTranscription(String jobId);
  Future<BenchmarkTranscriptSource> fetchTranscriptSource(String jobId);
  Future<BenchmarkSummaryTask> createSummary({
    required String jobId,
    required BenchmarkTranscriptSource source,
  });
  Future<BenchmarkRemoteState> pollSummary(BenchmarkSummaryTask task);
}

class HttpAsrBenchmarkTransport implements AsrBenchmarkTransport {
  HttpAsrBenchmarkTransport({
    required Uri baseUri,
    HttpClient Function()? clientFactory,
    Duration requestTimeout = const Duration(seconds: 15),
    Duration uploadTimeout = const Duration(minutes: 3),
    bool allowInsecureHttpForTesting = false,
  });
}

enum BenchmarkRemoteState { pending, completed }
enum BenchmarkFailureKind { network, remote, invalidResponse, transcription, summary }

class BenchmarkSubmission {
  const BenchmarkSubmission(this.jobId);
  final String jobId;
}

class BenchmarkTranscriptSource {
  const BenchmarkTranscriptSource({
    required this.relativePath,
    required this.variant,
    required this.engine,
  });
  final String relativePath;
  final String variant;
  final String engine;
}

class BenchmarkSummaryTask {
  const BenchmarkSummaryTask({required this.noteId, required this.taskId});
  final String noteId;
  final String taskId;
}
```

Stream one full file to `POST /api/jobs` with `files`, empty `reference_files`,
`engines=sensevoice`, `language=zh`, and `semantic_eval=false`. Map
`queued`/`running` to pending and `completed` to complete when polling
`GET /api/jobs/{jobId}`. A nonblank error or any other status is terminal.
Fetch the first successful nonblank flat-row solely to retain `relative_path`,
`variant`, and `engine`; discard its transcript string. Create the summary with
those source identifiers, accepting both `note.id`/`note.note_id` and
`generation_task.id`/`generation_task.task_id`. A summary task containing
`result` completes; `failed` or nonblank error fails; all other values remain
pending because no stable success enum is documented.

Expose only `network`, `remote`, `invalidResponse`, `transcription`, and
`summary` through `BenchmarkTransportException`; never add body text, audio
bytes, or transcript text to the exception. Reject HTTP unless
`allowInsecureHttpForTesting` is true; instantiate the local test transport with
that flag. Close each `HttpClient` in `finally`.

- [ ] **Step 4: Add terminal-state tests**

```dart
test('maps terminal ASR failure to a safe exception', () async {
  final resultFuture = transport.pollTranscription('job-1');
  final request = await server.first;
  await _respondJson(request, <String, Object?>{
    'job_id': 'job-1', 'status': 'failed', 'error': 'engine unavailable',
  });
  await expectLater(resultFuture, throwsA(isA<BenchmarkTransportException>()
      .having((value) => value.kind, 'kind', BenchmarkFailureKind.transcription)));
});

test('recognizes a generation result without fetching its body', () async {
  final resultFuture = transport.pollSummary(
    const BenchmarkSummaryTask(noteId: 'note-1', taskId: 'task-1'),
  );
  final request = await server.first;
  await _respondJson(request, <String, Object?>{
    'generation_task': <String, Object?>{'status': 'unknown', 'result': <String, Object?>{}},
  });
  expect(await resultFuture, BenchmarkRemoteState.completed);
});
```

- [ ] **Step 5: Run tests and commit**

Run: `flutter test test/tool/asr_benchmark/asr_benchmark_transport_test.dart`

Expected: PASS.

```bash
git add tool/src/asr_benchmark/asr_benchmark_transport.dart test/tool/asr_benchmark/asr_benchmark_transport_test.dart
git commit -m "feat: add ASR benchmark HTTP transport"
```

### Task 3: Bounded Concurrent Runner

**Files:**
- Create: `tool/src/asr_benchmark/asr_benchmark_runner.dart`
- Create: `test/tool/asr_benchmark/asr_benchmark_runner_test.dart`

- [ ] **Step 1: Write failing concurrency and isolation tests**

```dart
test('never exceeds configured concurrency and returns all results', () async {
  final transport = _ScriptedTransport(
    transcriptionStates: <BenchmarkRemoteState>[
      BenchmarkRemoteState.pending, BenchmarkRemoteState.completed,
    ],
  );
  final runner = AsrBenchmarkRunner(
    transport: transport, delay: (_) async {}, clock: Stopwatch.new,
  );
  final results = await runner.run(_configuration(jobs: 5, concurrency: 2));
  expect(results, hasLength(5));
  expect(transport.maxActiveSubmissions, lessThanOrEqualTo(2));
  expect(results.where((value) => value.status == BenchmarkJobStatus.completed), hasLength(5));
});

test('a failed job does not cancel the remaining workers', () async {
  final results = await _runnerWithOneFailedJob.run(
    _configuration(jobs: 3, concurrency: 2),
  );
  expect(results.map((value) => value.status), containsAll(<BenchmarkJobStatus>[
    BenchmarkJobStatus.failed,
    BenchmarkJobStatus.completed,
    BenchmarkJobStatus.completed,
  ]));
});
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/tool/asr_benchmark/asr_benchmark_runner_test.dart`

Expected: FAIL because `AsrBenchmarkRunner` does not exist.

- [ ] **Step 3: Implement worker-pool lifecycle execution**

```dart
typedef BenchmarkDelay = Future<void> Function(Duration duration);
typedef BenchmarkStopwatchFactory = Stopwatch Function();

class AsrBenchmarkRunner {
  AsrBenchmarkRunner({
    required AsrBenchmarkTransport transport,
    BenchmarkDelay delay = Future<void>.delayed,
    BenchmarkStopwatchFactory clock = Stopwatch.new,
    ResearchProcessingPollSchedule pollSchedule = const ResearchProcessingPollSchedule(),
  });

  Future<List<BenchmarkJobResult>> run(BenchmarkConfiguration configuration);
}
```

Create exactly `concurrency` workers and allocate ordinals with one shared
counter until `jobCount`. A job submits once, polls transcription with
`pollSchedule.nextDelay(elapsedAfterUpload)`, gets source metadata, then
optionally creates/polls a summary. Record upload, transcription, summary, and
total stopwatches. Sort final results by ordinal regardless of completion order.
Use one deadline across all stages. A transport error becomes failed; expiry
becomes timed out; both leave other workers running. Do not retry submissions.
Retry one polling-network exception after the scheduled delay, then fail it.

- [ ] **Step 4: Add summary, polling, and timeout tests**

```dart
test('records summary separately and uses the initial two-second delay', () async {
  final delays = <Duration>[];
  final runner = AsrBenchmarkRunner(
    transport: _ScriptedTransport.withSummary(),
    delay: (value) async => delays.add(value),
    clock: _IncrementingStopwatch.new,
  );
  final result = (await runner.run(_configuration(
    jobs: 1, concurrency: 1, includeSummary: true,
  ))).single;
  expect(delays, contains(const Duration(seconds: 2)));
  expect(result.transcription, isNotNull);
  expect(result.summary, isNotNull);
});

test('records an expired job rather than dropping it', () async {
  final result = (await _timingOutRunner.run(_configuration(
    jobs: 1, concurrency: 1, jobTimeout: Duration.zero,
  ))).single;
  expect(result.status, BenchmarkJobStatus.timedOut);
  expect(result.failureKind, 'timeout');
});
```

- [ ] **Step 5: Run tests and commit**

Run: `flutter test test/tool/asr_benchmark/asr_benchmark_runner_test.dart`

Expected: PASS.

```bash
git add tool/src/asr_benchmark/asr_benchmark_runner.dart test/tool/asr_benchmark/asr_benchmark_runner_test.dart
git commit -m "feat: add bounded ASR benchmark runner"
```

### Task 4: Report Writer and CLI

**Files:**
- Create: `tool/src/asr_benchmark/benchmark_report_writer.dart`
- Create: `tool/asr_benchmark.dart`
- Create: `test/tool/asr_benchmark/benchmark_report_writer_test.dart`

- [ ] **Step 1: Write a failing report-redaction test**

```dart
test('writes aggregate metadata but not transcript or audio path', () async {
  final destination = File('${directory.path}/nested/report.json');
  await BenchmarkReportWriter().write(
    report: BenchmarkReport.fromResults(<BenchmarkJobResult>[_completed(1, Duration.zero)]),
    metadata: const BenchmarkRunMetadata(
      endpointHost: 'asr.example', audioByteLength: 123, jobCount: 1,
      concurrency: 1, includeSummary: false,
    ),
    destination: destination,
  );
  final body = await destination.readAsString();
  expect(jsonDecode(body)['metadata']['endpoint_host'], 'asr.example');
  expect(body, isNot(contains('capture.m4a')));
  expect(body, isNot(contains('transcript')));
});
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/tool/asr_benchmark/benchmark_report_writer_test.dart`

Expected: FAIL because `BenchmarkReportWriter` does not exist.

- [ ] **Step 3: Implement JSON report and entrypoint**

```dart
class BenchmarkReportWriter {
  Future<void> write({
    required BenchmarkReport report,
    required BenchmarkRunMetadata metadata,
    required File destination,
  }) async {
    await destination.parent.create(recursive: true);
    await destination.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'metadata': metadata.toJson(),
        'report': report.toJson(),
      }),
    );
  }

  List<String> terminalSummary(BenchmarkReport report) => <String>[
    'completed=${report.aggregate.completedCount}',
    'failed=${report.aggregate.failedCount}',
    'timed_out=${report.aggregate.timedOutCount}',
    'total_ms_p50=${report.aggregate.totalP50Milliseconds ?? 'n/a'}',
  ];
}

Future<void> main(List<String> arguments) async {
  try {
    final configuration = BenchmarkConfiguration.parse(
      arguments: arguments,
      environment: Platform.environment,
    );
    final results = await AsrBenchmarkRunner(
      transport: HttpAsrBenchmarkTransport(baseUri: configuration.baseUri),
    ).run(configuration);
    final report = BenchmarkReport.fromResults(results);
    await BenchmarkReportWriter().write(
      report: report,
      metadata: await BenchmarkRunMetadata.fromConfiguration(configuration),
      destination: configuration.reportFile,
    );
    for (final line in BenchmarkReportWriter().terminalSummary(report)) {
      stdout.writeln(line);
    }
    exitCode = report.aggregate.failedCount > 0 ||
            report.aggregate.timedOutCount > 0
        ? 1
        : 0;
  } on FormatException catch (error) {
    stderr.writeln('configuration_error=${error.message}');
    exitCode = 64;
  }
}
```

Create the output parent directory and use `JsonEncoder.withIndent`. Metadata
contains endpoint host, audio byte length, jobs, concurrency, summary flag,
timestamps, and tool version. Never serialize endpoint path/query, input path,
audio bytes, transcript, summary, or decoded body. Terminal output shows only
completed/failed/timed-out counts, total P50, and report filename. A malformed
configuration prints a generic invocation form without echoing an absolute path.

- [ ] **Step 4: Run tests, analyze, and commit**

Run: `flutter test test/tool/asr_benchmark/benchmark_report_writer_test.dart`

Expected: PASS.

Run: `dart analyze tool/asr_benchmark.dart tool/src/asr_benchmark test/tool/asr_benchmark`

Expected: `No issues found!`

```bash
git add tool/asr_benchmark.dart tool/src/asr_benchmark/benchmark_report_writer.dart test/tool/asr_benchmark/benchmark_report_writer_test.dart
git commit -m "feat: add ASR benchmark CLI reporting"
```

### Task 5: Operator Guide and Verification

**Files:**
- Create: `docs/qa/asr-single-upload-concurrency-benchmark.md`
- Modify: `README.md` only when it has an existing developer-tools index; otherwise leave it unchanged.

- [ ] **Step 1: Document exact, safe live-run commands**

Document the HTTPS environment variable, non-sensitive audio requirement,
non-zero exit semantics, and that this is a single-file baseline, not a
chunk-upload comparison. Use the same 30-minute audio and engine for:

```powershell
$env:ASR_API_BASE_URL = 'https://test-asr.example'
dart run tool/asr_benchmark.dart --audio D:\test-data\recording-30min.m4a --jobs 4 --concurrency 1 --report build\asr-benchmark\c1.json
dart run tool/asr_benchmark.dart --audio D:\test-data\recording-30min.m4a --jobs 4 --concurrency 2 --report build\asr-benchmark\c2.json
dart run tool/asr_benchmark.dart --audio D:\test-data\recording-30min.m4a --jobs 4 --concurrency 4 --report build\asr-benchmark\c4.json
dart run tool/asr_benchmark.dart --audio D:\test-data\recording-30min.m4a --jobs 8 --concurrency 8 --report build\asr-benchmark\c8.json
```

Require comparison of upload, transcription, and summary P50/P95 independently.

- [ ] **Step 2: Run all automated verification**

Run: `flutter test test/tool/asr_benchmark`

Expected: PASS.

Run: `dart analyze tool/asr_benchmark.dart tool/src/asr_benchmark test/tool/asr_benchmark`

Expected: `No issues found!`

- [ ] **Step 3: Run live measurements only after a test audio path is supplied**

Run the four documented commands against the explicit test service, never a
production endpoint or user recording. Hand off only aggregate results and
report paths.

- [ ] **Step 4: Commit operator documentation**

```bash
git add docs/qa/asr-single-upload-concurrency-benchmark.md
git commit -m "docs: add ASR concurrency benchmark procedure"
```

## Final Verification Checklist

- [ ] `flutter test test/tool/asr_benchmark` passes.
- [ ] `dart analyze tool/asr_benchmark.dart tool/src/asr_benchmark test/tool/asr_benchmark` reports no issues.
- [ ] Local HTTP tests cover multipart submission, terminal ASR failure, source extraction, and summary completion.
- [ ] Runner tests prove concurrency capping and per-job failure isolation.
- [ ] Generated JSON contains no audio path, audio data, transcript, or summary body.
- [ ] Live timings run only after a non-sensitive test recording and explicit test endpoint are supplied.
