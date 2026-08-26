import 'dart:convert';
import 'dart:io';

import 'benchmark_models.dart';

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

  List<String> terminalSummary(BenchmarkReport report) {
    return <String>[
      'completed=${report.aggregate.completedCount}',
      'failed=${report.aggregate.failedCount}',
      'timed_out=${report.aggregate.timedOutCount}',
      'total_ms_p50=${report.aggregate.totalP50Milliseconds ?? 'n/a'}',
    ];
  }
}
