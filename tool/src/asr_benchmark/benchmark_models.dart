import 'dart:math' as math;

import 'benchmark_configuration.dart';

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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ordinal': ordinal,
      'status': switch (status) {
        BenchmarkJobStatus.completed => 'completed',
        BenchmarkJobStatus.failed => 'failed',
        BenchmarkJobStatus.timedOut => 'timed_out',
      },
      'job_id': jobId,
      'started_at': startedAt.toIso8601String(),
      'upload_ms': upload?.inMilliseconds,
      'transcription_ms': transcription?.inMilliseconds,
      'summary_ms': summary?.inMilliseconds,
      'total_ms': total.inMilliseconds,
      'failure_kind': failureKind,
      'poll_count': pollCount,
      'request_count': requestCount,
    };
  }
}

class BenchmarkDurationStatistics {
  const BenchmarkDurationStatistics({
    required this.sampleCount,
    required this.minimumMilliseconds,
    required this.averageMilliseconds,
    required this.maximumMilliseconds,
    required this.totalP50Milliseconds,
    required this.totalP95Milliseconds,
    required this.totalP99Milliseconds,
  });

  final int sampleCount;
  final int? minimumMilliseconds;
  final int? averageMilliseconds;
  final int? maximumMilliseconds;
  final int? totalP50Milliseconds;
  final int? totalP95Milliseconds;
  final int? totalP99Milliseconds;

  factory BenchmarkDurationStatistics.fromDurations(
    Iterable<Duration?> durations,
  ) {
    final values =
        durations
            .whereType<Duration>()
            .map((duration) => duration.inMilliseconds)
            .toList(growable: false)
          ..sort();
    if (values.isEmpty) {
      return const BenchmarkDurationStatistics(
        sampleCount: 0,
        minimumMilliseconds: null,
        averageMilliseconds: null,
        maximumMilliseconds: null,
        totalP50Milliseconds: null,
        totalP95Milliseconds: null,
        totalP99Milliseconds: null,
      );
    }
    return BenchmarkDurationStatistics(
      sampleCount: values.length,
      minimumMilliseconds: values.first,
      averageMilliseconds:
          values.reduce((total, value) => total + value) ~/ values.length,
      maximumMilliseconds: values.last,
      totalP50Milliseconds: _nearestRank(values, 0.50),
      totalP95Milliseconds: _nearestRank(values, 0.95),
      totalP99Milliseconds: _nearestRank(values, 0.99),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sample_count': sampleCount,
      'minimum_ms': minimumMilliseconds,
      'average_ms': averageMilliseconds,
      'maximum_ms': maximumMilliseconds,
      'p50_ms': totalP50Milliseconds,
      'p95_ms': totalP95Milliseconds,
      'p99_ms': totalP99Milliseconds,
    };
  }

  static int? _nearestRank(List<int> sortedValues, double percentile) {
    if (sortedValues.isEmpty) {
      return null;
    }
    final index = math.max(1, (sortedValues.length * percentile).ceil()) - 1;
    return sortedValues[index];
  }
}

class BenchmarkAggregate {
  const BenchmarkAggregate({
    required this.completedCount,
    required this.failedCount,
    required this.timedOutCount,
    required this.total,
    required this.upload,
    required this.transcription,
    required this.summary,
  });

  final int completedCount;
  final int failedCount;
  final int timedOutCount;
  final BenchmarkDurationStatistics total;
  final BenchmarkDurationStatistics upload;
  final BenchmarkDurationStatistics transcription;
  final BenchmarkDurationStatistics summary;

  int? get totalP50Milliseconds => total.totalP50Milliseconds;
  int? get totalP95Milliseconds => total.totalP95Milliseconds;
  int? get totalP99Milliseconds => total.totalP99Milliseconds;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'completed_count': completedCount,
      'failed_count': failedCount,
      'timed_out_count': timedOutCount,
      'total_ms_p50': totalP50Milliseconds,
      'total_ms_p95': totalP95Milliseconds,
      'total_ms_p99': totalP99Milliseconds,
      'total': total.toJson(),
      'upload': upload.toJson(),
      'transcription': transcription.toJson(),
      'summary': summary.toJson(),
    };
  }
}

class BenchmarkReport {
  BenchmarkReport._({required this.results, required this.aggregate});

  final List<BenchmarkJobResult> results;
  final BenchmarkAggregate aggregate;

  factory BenchmarkReport.fromResults(List<BenchmarkJobResult> results) {
    final sortedResults = List<BenchmarkJobResult>.of(results)
      ..sort((first, second) => first.ordinal.compareTo(second.ordinal));
    final completed = sortedResults
        .where((result) => result.status == BenchmarkJobStatus.completed)
        .toList(growable: false);
    return BenchmarkReport._(
      results: List<BenchmarkJobResult>.unmodifiable(sortedResults),
      aggregate: BenchmarkAggregate(
        completedCount: completed.length,
        failedCount: sortedResults
            .where((result) => result.status == BenchmarkJobStatus.failed)
            .length,
        timedOutCount: sortedResults
            .where((result) => result.status == BenchmarkJobStatus.timedOut)
            .length,
        total: BenchmarkDurationStatistics.fromDurations(
          completed.map((result) => result.total),
        ),
        upload: BenchmarkDurationStatistics.fromDurations(
          completed.map((result) => result.upload),
        ),
        transcription: BenchmarkDurationStatistics.fromDurations(
          completed.map((result) => result.transcription),
        ),
        summary: BenchmarkDurationStatistics.fromDurations(
          completed.map((result) => result.summary),
        ),
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'jobs': results.map((result) => result.toJson()).toList(growable: false),
      'aggregate': aggregate.toJson(),
    };
  }
}

class BenchmarkRunMetadata {
  const BenchmarkRunMetadata({
    required this.endpointHost,
    required this.audioByteLength,
    required this.jobCount,
    required this.concurrency,
    required this.includeSummary,
    required this.startedAt,
    required this.finishedAt,
    required this.toolVersion,
  });

  final String endpointHost;
  final int audioByteLength;
  final int jobCount;
  final int concurrency;
  final bool includeSummary;
  final String startedAt;
  final String finishedAt;
  final String toolVersion;

  static Future<BenchmarkRunMetadata> fromConfiguration(
    BenchmarkConfiguration configuration, {
    required DateTime startedAt,
    required DateTime finishedAt,
    required String toolVersion,
  }) async {
    return BenchmarkRunMetadata(
      endpointHost: configuration.baseUri.host,
      audioByteLength: await configuration.audioFile.length(),
      jobCount: configuration.jobCount,
      concurrency: configuration.concurrency,
      includeSummary: configuration.includeSummary,
      startedAt: startedAt.toUtc().toIso8601String(),
      finishedAt: finishedAt.toUtc().toIso8601String(),
      toolVersion: toolVersion,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'endpoint_host': endpointHost,
      'audio_byte_length': audioByteLength,
      'job_count': jobCount,
      'concurrency': concurrency,
      'include_summary': includeSummary,
      'started_at': startedAt,
      'finished_at': finishedAt,
      'tool_version': toolVersion,
    };
  }
}
