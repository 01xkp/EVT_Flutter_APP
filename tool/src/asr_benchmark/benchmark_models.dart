import 'dart:math' as math;

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

class BenchmarkAggregate {
  const BenchmarkAggregate({
    required this.completedCount,
    required this.failedCount,
    required this.timedOutCount,
    required this.totalP50Milliseconds,
    required this.totalP95Milliseconds,
    required this.totalP99Milliseconds,
  });

  final int completedCount;
  final int failedCount;
  final int timedOutCount;
  final int? totalP50Milliseconds;
  final int? totalP95Milliseconds;
  final int? totalP99Milliseconds;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'completed_count': completedCount,
      'failed_count': failedCount,
      'timed_out_count': timedOutCount,
      'total_ms_p50': totalP50Milliseconds,
      'total_ms_p95': totalP95Milliseconds,
      'total_ms_p99': totalP99Milliseconds,
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
    final totals =
        completed
            .map((result) => result.total.inMilliseconds)
            .toList(growable: false)
          ..sort();
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
        totalP50Milliseconds: _nearestRank(totals, 0.50),
        totalP95Milliseconds: _nearestRank(totals, 0.95),
        totalP99Milliseconds: _nearestRank(totals, 0.99),
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'jobs': results.map((result) => result.toJson()).toList(growable: false),
      'aggregate': aggregate.toJson(),
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
