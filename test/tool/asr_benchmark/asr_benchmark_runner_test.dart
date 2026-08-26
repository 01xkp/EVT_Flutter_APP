import 'dart:io';

import '../../../tool/src/asr_benchmark/asr_benchmark_runner.dart';
import '../../../tool/src/asr_benchmark/asr_benchmark_transport.dart';
import '../../../tool/src/asr_benchmark/benchmark_configuration.dart';
import '../../../tool/src/asr_benchmark/benchmark_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'never exceeds configured concurrency and returns every result',
    () async {
      final transport = _ScriptedTransport(
        submissionDelay: const Duration(milliseconds: 5),
      );
      final runner = AsrBenchmarkRunner(
        transport: transport,
        delay: (_) async {},
      );

      final results = await runner.run(_configuration(jobs: 5, concurrency: 2));

      expect(results, hasLength(5));
      expect(transport.maxActiveSubmissions, lessThanOrEqualTo(2));
      expect(
        results.where(
          (result) => result.status == BenchmarkJobStatus.completed,
        ),
        hasLength(5),
      );
      expect(results.map((result) => result.ordinal), <int>[1, 2, 3, 4, 5]);
    },
  );

  test('a failed job does not cancel remaining workers', () async {
    final runner = AsrBenchmarkRunner(
      transport: _ScriptedTransport(failedJobIds: const <String>{'job-1'}),
      delay: (_) async {},
    );

    final results = await runner.run(_configuration(jobs: 3, concurrency: 2));

    expect(results.map((result) => result.status), <BenchmarkJobStatus>[
      BenchmarkJobStatus.failed,
      BenchmarkJobStatus.completed,
      BenchmarkJobStatus.completed,
    ]);
  });

  test(
    'uses progressive polling and records summary time separately',
    () async {
      final clock = _FakeClock();
      final delays = <Duration>[];
      final runner = AsrBenchmarkRunner(
        transport: _ScriptedTransport(pendingTranscriptionPolls: 1),
        now: clock.now,
        delay: (duration) async {
          delays.add(duration);
          clock.advance(duration);
        },
      );

      final result = (await runner.run(
        _configuration(jobs: 1, concurrency: 1, includeSummary: true),
      )).single;

      expect(delays, contains(const Duration(seconds: 2)));
      expect(result.transcription, const Duration(seconds: 2));
      expect(result.summary, Duration.zero);
      expect(result.status, BenchmarkJobStatus.completed);
    },
  );

  test('retries one transient polling network failure', () async {
    final clock = _FakeClock();
    final runner = AsrBenchmarkRunner(
      transport: _ScriptedTransport(networkFailuresBeforeCompletion: 1),
      now: clock.now,
      delay: (duration) async => clock.advance(duration),
    );

    final result = (await runner.run(
      _configuration(jobs: 1, concurrency: 1),
    )).single;

    expect(result.status, BenchmarkJobStatus.completed);
    expect(result.requestCount, 4);
    expect(result.pollCount, 2);
  });

  test(
    'uses the completed transcription source once when creating a summary',
    () async {
      final transport = _ScriptedTransport();
      final runner = AsrBenchmarkRunner(
        transport: transport,
        delay: (_) async {},
      );

      await runner.run(
        _configuration(jobs: 1, concurrency: 1, includeSummary: true),
      );

      expect(transport.sourceRequestCount, 1);
    },
  );

  test('records an expired job instead of dropping it', () async {
    final runner = AsrBenchmarkRunner(
      transport: _ScriptedTransport(),
      delay: (_) async {},
    );

    final result = (await runner.run(
      _configuration(jobs: 1, concurrency: 1, jobTimeout: Duration.zero),
    )).single;

    expect(result.status, BenchmarkJobStatus.timedOut);
    expect(result.failureKind, 'timeout');
    expect(result.requestCount, 0);
  });
}

BenchmarkConfiguration _configuration({
  required int jobs,
  required int concurrency,
  bool includeSummary = false,
  Duration jobTimeout = const Duration(minutes: 45),
}) {
  return BenchmarkConfiguration(
    baseUri: Uri.parse('https://asr.example'),
    audioFile: File('ignored.m4a'),
    jobCount: jobs,
    concurrency: concurrency,
    includeSummary: includeSummary,
    reportFile: File('ignored.json'),
    jobTimeout: jobTimeout,
  );
}

class _FakeClock {
  DateTime value = DateTime.utc(2026);

  DateTime now() => value;

  void advance(Duration duration) {
    value = value.add(duration);
  }
}

class _ScriptedTransport implements AsrBenchmarkTransport {
  _ScriptedTransport({
    this.submissionDelay = Duration.zero,
    this.failedJobIds = const <String>{},
    this.pendingTranscriptionPolls = 0,
    this.networkFailuresBeforeCompletion = 0,
  });

  final Duration submissionDelay;
  final Set<String> failedJobIds;
  final int pendingTranscriptionPolls;
  final int networkFailuresBeforeCompletion;
  int activeSubmissions = 0;
  int maxActiveSubmissions = 0;
  int sourceRequestCount = 0;
  int _nextJob = 0;
  final Map<String, int> _pollsByJob = <String, int>{};

  @override
  Future<BenchmarkSummaryTask> createSummary({
    required String jobId,
    required BenchmarkTranscriptSource source,
  }) async {
    return BenchmarkSummaryTask(noteId: 'note-$jobId', taskId: 'task-$jobId');
  }

  @override
  Future<BenchmarkTranscriptSource> fetchTranscriptSource(String jobId) async {
    sourceRequestCount += 1;
    return const BenchmarkTranscriptSource(
      relativePath: 'capture.m4a',
      variant: 'original',
      engine: 'sensevoice',
    );
  }

  @override
  Future<BenchmarkRemoteState> pollSummary(BenchmarkSummaryTask task) async {
    return BenchmarkRemoteState.completed;
  }

  @override
  Future<BenchmarkRemoteState> pollTranscription(String jobId) async {
    final count = (_pollsByJob[jobId] ?? 0) + 1;
    _pollsByJob[jobId] = count;
    if (failedJobIds.contains(jobId)) {
      throw const BenchmarkTransportException(
        kind: BenchmarkFailureKind.transcription,
        message: 'failed',
      );
    }
    if (count <= networkFailuresBeforeCompletion) {
      throw const BenchmarkTransportException(
        kind: BenchmarkFailureKind.network,
        message: 'network',
      );
    }
    if (count <= networkFailuresBeforeCompletion + pendingTranscriptionPolls) {
      return BenchmarkRemoteState.pending;
    }
    return BenchmarkRemoteState.completed;
  }

  @override
  Future<BenchmarkSubmission> submit(File audioFile) async {
    activeSubmissions += 1;
    maxActiveSubmissions = maxActiveSubmissions > activeSubmissions
        ? maxActiveSubmissions
        : activeSubmissions;
    try {
      if (submissionDelay > Duration.zero) {
        await Future<void>.delayed(submissionDelay);
      }
      _nextJob += 1;
      return BenchmarkSubmission('job-$_nextJob');
    } finally {
      activeSubmissions -= 1;
    }
  }
}
