import 'dart:convert';
import 'dart:io';

import '../../../tool/src/asr_benchmark/benchmark_models.dart';
import '../../../tool/src/asr_benchmark/benchmark_report_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aipin-asr-report-');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('writes timing metadata without audio paths or content bodies', () async {
    final destination = File(
      '${directory.path}${Platform.pathSeparator}nested${Platform.pathSeparator}run.json',
    );
    final report = BenchmarkReport.fromResults(<BenchmarkJobResult>[
      BenchmarkJobResult(
        ordinal: 1,
        status: BenchmarkJobStatus.completed,
        startedAt: DateTime.utc(2026),
        total: const Duration(seconds: 3),
        jobId: 'job-1',
        upload: const Duration(milliseconds: 300),
        transcription: const Duration(seconds: 2),
        summary: const Duration(milliseconds: 700),
        pollCount: 3,
        requestCount: 6,
      ),
    ]);
    const metadata = BenchmarkRunMetadata(
      endpointHost: 'asr.example',
      audioByteLength: 123,
      jobCount: 1,
      concurrency: 1,
      includeSummary: true,
      startedAt: '2026-08-26T00:00:00.000Z',
      finishedAt: '2026-08-26T00:00:03.000Z',
      toolVersion: '1',
    );

    await BenchmarkReportWriter().write(
      report: report,
      metadata: metadata,
      destination: destination,
    );

    final body = await destination.readAsString();
    final decoded = jsonDecode(body) as Map<String, Object?>;

    expect(decoded['metadata'], <String, Object?>{
      'endpoint_host': 'asr.example',
      'audio_byte_length': 123,
      'job_count': 1,
      'concurrency': 1,
      'include_summary': true,
      'started_at': '2026-08-26T00:00:00.000Z',
      'finished_at': '2026-08-26T00:00:03.000Z',
      'tool_version': '1',
    });
    expect(body, contains('"summary_ms": 700'));
    expect(body, isNot(contains('capture.m4a')));
    expect(body, isNot(contains('transcript_text')));
    expect(body, isNot(contains('summary_text')));
  });

  test('formats an aggregate-only terminal summary', () {
    final report = BenchmarkReport.fromResults(<BenchmarkJobResult>[
      BenchmarkJobResult(
        ordinal: 1,
        status: BenchmarkJobStatus.completed,
        startedAt: DateTime.utc(2026),
        total: const Duration(seconds: 3),
      ),
      BenchmarkJobResult(
        ordinal: 2,
        status: BenchmarkJobStatus.failed,
        startedAt: DateTime.utc(2026),
        total: const Duration(seconds: 1),
        failureKind: 'remote',
      ),
    ]);

    expect(BenchmarkReportWriter().terminalSummary(report), <String>[
      'completed=1',
      'failed=1',
      'timed_out=0',
      'total_ms_p50=3000',
    ]);
  });
}
