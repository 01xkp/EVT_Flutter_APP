import 'dart:convert';

import '../../../tool/src/asr_benchmark/benchmark_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses nearest-rank percentiles for completed jobs', () {
    final report = BenchmarkReport.fromResults(<BenchmarkJobResult>[
      _completed(ordinal: 1, total: const Duration(seconds: 1)),
      _completed(ordinal: 2, total: const Duration(seconds: 2)),
      _completed(ordinal: 3, total: const Duration(seconds: 3)),
    ]);

    expect(report.aggregate.completedCount, 3);
    expect(report.aggregate.failedCount, 0);
    expect(report.aggregate.timedOutCount, 0);
    expect(report.aggregate.totalP50Milliseconds, 2000);
    expect(report.aggregate.totalP95Milliseconds, 3000);
    expect(report.aggregate.totalP99Milliseconds, 3000);
  });

  test('keeps failures out of completed duration percentiles', () {
    final report = BenchmarkReport.fromResults(<BenchmarkJobResult>[
      _completed(ordinal: 1, total: const Duration(seconds: 2)),
      BenchmarkJobResult(
        ordinal: 2,
        status: BenchmarkJobStatus.failed,
        startedAt: DateTime.utc(2026),
        total: const Duration(minutes: 10),
        failureKind: 'remote',
      ),
      BenchmarkJobResult(
        ordinal: 3,
        status: BenchmarkJobStatus.timedOut,
        startedAt: DateTime.utc(2026),
        total: const Duration(minutes: 45),
        failureKind: 'timeout',
      ),
    ]);

    expect(report.aggregate.completedCount, 1);
    expect(report.aggregate.failedCount, 1);
    expect(report.aggregate.timedOutCount, 1);
    expect(report.aggregate.totalP50Milliseconds, 2000);
  });

  test('aggregates upload transcription and summary durations separately', () {
    final report = BenchmarkReport.fromResults(<BenchmarkJobResult>[
      BenchmarkJobResult(
        ordinal: 1,
        status: BenchmarkJobStatus.completed,
        startedAt: DateTime.utc(2026),
        total: const Duration(seconds: 3),
        upload: const Duration(milliseconds: 100),
        transcription: const Duration(milliseconds: 2000),
        summary: const Duration(milliseconds: 900),
      ),
      BenchmarkJobResult(
        ordinal: 2,
        status: BenchmarkJobStatus.completed,
        startedAt: DateTime.utc(2026),
        total: const Duration(seconds: 7),
        upload: const Duration(milliseconds: 300),
        transcription: const Duration(milliseconds: 5000),
        summary: const Duration(milliseconds: 1100),
      ),
    ]);

    expect(report.aggregate.upload.minimumMilliseconds, 100);
    expect(report.aggregate.upload.averageMilliseconds, 200);
    expect(report.aggregate.upload.maximumMilliseconds, 300);
    expect(report.aggregate.transcription.totalP50Milliseconds, 2000);
    expect(report.aggregate.summary.totalP95Milliseconds, 1100);
  });

  test('serializes only safe result metadata', () {
    final report = BenchmarkReport.fromResults(<BenchmarkJobResult>[
      _completed(ordinal: 1, total: const Duration(seconds: 1), jobId: 'job-1'),
    ]);

    final serialized = jsonEncode(report.toJson());

    expect(serialized, contains('"job_id":"job-1"'));
    expect(serialized, contains('"transcription_ms":800'));
    expect(serialized, isNot(contains('transcript_text')));
    expect(serialized, contains('"summary_ms":null'));
    expect(serialized, isNot(contains('summary_text')));
    expect(serialized, isNot(contains('capture.m4a')));
  });
}

BenchmarkJobResult _completed({
  required int ordinal,
  required Duration total,
  String? jobId,
}) {
  return BenchmarkJobResult(
    ordinal: ordinal,
    status: BenchmarkJobStatus.completed,
    startedAt: DateTime.utc(2026),
    total: total,
    jobId: jobId,
    upload: const Duration(milliseconds: 200),
    transcription: const Duration(milliseconds: 800),
    pollCount: 2,
    requestCount: 4,
  );
}
