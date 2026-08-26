import 'dart:async';

import 'package:aipin/features/research_beta/application/research_processing_poll_schedule.dart';

import 'asr_benchmark_transport.dart';
import 'benchmark_configuration.dart';
import 'benchmark_models.dart';

typedef BenchmarkDelay = Future<void> Function(Duration duration);
typedef BenchmarkNow = DateTime Function();

class AsrBenchmarkRunner {
  AsrBenchmarkRunner({
    required this.transport,
    this.delay = Future<void>.delayed,
    this.now = DateTime.now,
    this.pollSchedule = const ResearchProcessingPollSchedule(),
  });

  final AsrBenchmarkTransport transport;
  final BenchmarkDelay delay;
  final BenchmarkNow now;
  final ResearchProcessingPollSchedule pollSchedule;

  Future<List<BenchmarkJobResult>> run(
    BenchmarkConfiguration configuration,
  ) async {
    final results = <BenchmarkJobResult>[];
    var nextOrdinal = 1;

    Future<void> worker() async {
      while (true) {
        final ordinal = nextOrdinal;
        nextOrdinal += 1;
        if (ordinal > configuration.jobCount) {
          return;
        }
        results.add(await _runJob(ordinal, configuration));
      }
    }

    await Future.wait<void>(
      List<Future<void>>.generate(configuration.concurrency, (_) => worker()),
    );
    results.sort((first, second) => first.ordinal.compareTo(second.ordinal));
    return List<BenchmarkJobResult>.unmodifiable(results);
  }

  Future<BenchmarkJobResult> _runJob(
    int ordinal,
    BenchmarkConfiguration configuration,
  ) async {
    final startedAt = now();
    final deadline = startedAt.add(configuration.jobTimeout);
    var requestCount = 0;
    var pollCount = 0;
    String? jobId;
    Duration? upload;
    Duration? transcription;
    Duration? summary;

    Future<T> request<T>(Future<T> Function() action) async {
      requestCount += 1;
      return _requestBeforeDeadline(action, deadline);
    }

    try {
      _ensureBeforeDeadline(deadline);
      final uploadStartedAt = now();
      final submission = await request(
        () => transport.submit(configuration.audioFile),
      );
      upload = _elapsed(uploadStartedAt);
      jobId = submission.jobId;
      final uploadCompletedAt = now();

      final transcriptionStartedAt = now();
      await _waitForCompletion(
        deadline: deadline,
        elapsedSinceUpload: () => _elapsed(uploadCompletedAt),
        poll: () async {
          pollCount += 1;
          return request(() => transport.pollTranscription(jobId!));
        },
      );
      final source = await request(
        () => transport.fetchTranscriptSource(jobId!),
      );
      transcription = _elapsed(transcriptionStartedAt);

      if (configuration.includeSummary) {
        final summaryStartedAt = now();
        final task = await request(
          () => transport.createSummary(jobId: jobId!, source: source),
        );
        await _waitForCompletion(
          deadline: deadline,
          elapsedSinceUpload: () => _elapsed(uploadCompletedAt),
          poll: () async {
            pollCount += 1;
            return request(() => transport.pollSummary(task));
          },
        );
        summary = _elapsed(summaryStartedAt);
      }

      return BenchmarkJobResult(
        ordinal: ordinal,
        status: BenchmarkJobStatus.completed,
        startedAt: startedAt,
        total: _elapsed(startedAt),
        jobId: jobId,
        upload: upload,
        transcription: transcription,
        summary: summary,
        pollCount: pollCount,
        requestCount: requestCount,
      );
    } on _BenchmarkDeadlineExceeded {
      return BenchmarkJobResult(
        ordinal: ordinal,
        status: BenchmarkJobStatus.timedOut,
        startedAt: startedAt,
        total: _elapsed(startedAt),
        jobId: jobId,
        upload: upload,
        transcription: transcription,
        summary: summary,
        failureKind: 'timeout',
        pollCount: pollCount,
        requestCount: requestCount,
      );
    } on TimeoutException {
      return BenchmarkJobResult(
        ordinal: ordinal,
        status: BenchmarkJobStatus.timedOut,
        startedAt: startedAt,
        total: _elapsed(startedAt),
        jobId: jobId,
        upload: upload,
        transcription: transcription,
        summary: summary,
        failureKind: 'timeout',
        pollCount: pollCount,
        requestCount: requestCount,
      );
    } on BenchmarkTransportException catch (error) {
      return BenchmarkJobResult(
        ordinal: ordinal,
        status: BenchmarkJobStatus.failed,
        startedAt: startedAt,
        total: _elapsed(startedAt),
        jobId: jobId,
        upload: upload,
        transcription: transcription,
        summary: summary,
        failureKind: error.kind.name,
        pollCount: pollCount,
        requestCount: requestCount,
      );
    }
  }

  Future<void> _waitForCompletion({
    required DateTime deadline,
    required Duration Function() elapsedSinceUpload,
    required Future<BenchmarkRemoteState> Function() poll,
  }) async {
    while (true) {
      _ensureBeforeDeadline(deadline);
      final state = await _pollWithOneNetworkRetry(
        deadline: deadline,
        elapsedSinceUpload: elapsedSinceUpload,
        poll: poll,
      );
      if (state == BenchmarkRemoteState.completed) {
        return;
      }
      await _waitForNextPoll(
        pollSchedule.nextDelay(elapsedSinceUpload()),
        deadline,
      );
    }
  }

  Future<BenchmarkRemoteState> _pollWithOneNetworkRetry({
    required DateTime deadline,
    required Duration Function() elapsedSinceUpload,
    required Future<BenchmarkRemoteState> Function() poll,
  }) async {
    try {
      return await poll();
    } on BenchmarkTransportException catch (error) {
      if (error.kind != BenchmarkFailureKind.network) {
        rethrow;
      }
      await _waitForNextPoll(
        pollSchedule.nextDelay(elapsedSinceUpload()),
        deadline,
      );
      return poll();
    }
  }

  Future<T> _requestBeforeDeadline<T>(
    Future<T> Function() action,
    DateTime deadline,
  ) async {
    final remaining = deadline.difference(now());
    if (remaining <= Duration.zero) {
      throw const _BenchmarkDeadlineExceeded();
    }
    return action().timeout(remaining);
  }

  Future<void> _waitForNextPoll(Duration scheduled, DateTime deadline) async {
    final remaining = deadline.difference(now());
    if (remaining <= Duration.zero) {
      throw const _BenchmarkDeadlineExceeded();
    }
    final delay = scheduled <= remaining ? scheduled : remaining;
    await this.delay(delay);
    _ensureBeforeDeadline(deadline);
  }

  void _ensureBeforeDeadline(DateTime deadline) {
    if (deadline.difference(now()) <= Duration.zero) {
      throw const _BenchmarkDeadlineExceeded();
    }
  }

  Duration _elapsed(DateTime startedAt) {
    final elapsed = now().difference(startedAt);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }
}

class _BenchmarkDeadlineExceeded implements Exception {
  const _BenchmarkDeadlineExceeded();
}
