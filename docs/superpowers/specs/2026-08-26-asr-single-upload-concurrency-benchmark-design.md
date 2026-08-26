# ASR Single-Upload Concurrency Benchmark Design

**Date:** 2026-08-26

## Goal

Measure the existing ASR service's behaviour for a long audio recording, such
as a 30-minute capture, before a production chunk-upload API exists. The
benchmark must separate client upload, transcription, and optional summary
latency, with particular emphasis on bounded concurrent transcription jobs.

This is a developer command-line tool. It does not change the mobile App's
upload behaviour, persistent data model, or UI.

## Scope and Constraints

- The current server supports a single multipart submission at `POST /api/jobs`
  followed by asynchronous status polling. It does not expose an upload session,
  chunk index, checksum, completion, or server-side merge API.
- A valid M4A/AAC recording must not be split into arbitrary byte ranges and
  posted as separate `files` requests. Such ranges are usually not standalone
  audio files, and the current API would create independent ASR results rather
  than one stitched recording.
- The tool receives a locally supplied, non-sensitive test recording at runtime.
  It never creates audio, records audio, copies it into the repository, or logs
  its content or transcript text.
- Summary generation is optional. It is measured separately and does not mask
  upload or transcription performance.
- Requests target only a deliberately configured test endpoint. The endpoint
  must be supplied with `ASR_API_BASE_URL`; no Quick Tunnel address is embedded
  in source code.

## Invocation

The implementation will provide a Dart executable under `tool/`, invoked with
`dart run` and command-line arguments:

```text
dart run tool/asr_benchmark.dart \
  --audio D:\\test-data\\recording-30min.m4a \
  --jobs 8 \
  --concurrency 4 \
  --summary \
  --report build\\asr-benchmark\\run.json
```

`ASR_API_BASE_URL` is read from the environment. The first supported benchmark
is one submission per virtual user. The same local audio file may be reused by
multiple virtual users without copying it to disk. `--jobs` is the total number
of submissions and must be greater than or equal to `--concurrency`.

## Architecture

The tool has four focused units:

| Unit | Responsibility |
|---|---|
| `BenchmarkConfiguration` | Parses and validates the endpoint, audio path, concurrency, timeouts, summary flag, and report destination. |
| `AsrBenchmarkRunner` | Applies a bounded worker pool and collects one isolated result for every virtual user. |
| `AsrBenchmarkJob` | Executes one lifecycle: submit, poll transcription, optionally create and poll summary. |
| `BenchmarkReportWriter` | Produces a JSON report and a concise terminal summary using only metadata and timings. |

The benchmark has no Flutter, Riverpod, Drift, or UI dependency. It reuses the
same HTTP request semantics and response validation as the App where practical,
but keeps the tool isolated so it cannot affect user recordings.

## Data Flow

1. Validate the supplied audio exists and is non-empty, and validate a HTTPS
   endpoint is configured.
2. Create exactly `concurrency` workers. Each worker claims one benchmark job
   until the configured task count completes.
3. Submit the complete audio through `POST /api/jobs`, record upload elapsed
   time, and retain only the returned `jobId`. The request includes the empty
   reference attachment required by the current measurement-oriented ASR API.
4. Poll `GET /api/jobs/{jobId}` with the existing progressive schedule: every
   two seconds during the first minute, then five to ten seconds.
5. On transcription completion, fetch the result metadata. Do not retain or
   write transcript text. If summary is requested, create and poll the summary
   task, then measure that stage separately.
6. Write an aggregate report after all jobs have reached a terminal state.

## Metrics

Each job records:

- anonymized ordinal and remote `jobId`;
- result status and failure category, without response body or transcript;
- upload duration;
- transcription lifecycle duration after upload completion;
- optional summary lifecycle duration;
- total end-to-end duration;
- poll and request counts.

The aggregate report includes attempted, succeeded, failed, and timed-out job
counts; total runtime; latency P50, P95, and P99 when sample size permits; and
minimum, maximum, and average durations per stage. It includes configuration
metadata such as audio byte size, concurrency, task count, and endpoint host.
When summary is disabled, a completed transcription is a successful job. When
summary is enabled, only a completed summary is successful end to end; the
report still separately counts completed transcriptions.

## Failure Handling

- A failure, timeout, malformed response, or terminal ASR error stops only its
  own job. Remaining workers continue.
- The process uses a non-zero exit code if any job fails, after writing the
  complete report.
- Upload submission is never blindly retried because the current API has no
  idempotency key. Polling requests may retry transient network errors within a
  bounded retry policy.
- The tool caps total job duration and reports a timeout rather than polling
  forever.

## Test Strategy

- Unit tests: argument validation, bounded worker scheduling, percentile
  calculation, report redaction, and terminal-state aggregation.
- Local HTTP contract tests: multipart fields, individual job isolation,
  progressive polling, timeout, remote failure, and concurrent completion in a
  different order from submission.
- Live test procedure: run the same recording at concurrency 1, 2, 4, and 8;
  use the same engine and server configuration; archive the generated reports;
  compare stage-level percentiles rather than only total time.

## Future Chunk-Upload Comparison

Once the server provides an explicit upload-session contract, add a second
transport behind the same benchmark job interface. The required server contract
is:

1. Create upload session and return `uploadId`.
2. Upload numbered, checksummed chunks with an idempotency key.
3. Complete the session, validate all chunks, merge the original audio, and
   return one ASR `jobId`.
4. Expose failure, retry, expiration, and cleanup behaviour.

The future chunk transport will use the same audio source, task count,
concurrency level, metrics schema, and report writer. This permits a direct
single-file versus chunked comparison without conflating the result with
multiple independent ASR jobs.
