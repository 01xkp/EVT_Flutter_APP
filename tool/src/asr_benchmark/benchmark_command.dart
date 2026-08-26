import 'asr_benchmark_runner.dart';
import 'asr_benchmark_transport.dart';
import 'benchmark_configuration.dart';
import 'benchmark_models.dart';
import 'benchmark_report_writer.dart';

typedef BenchmarkLineWriter = void Function(String line);
typedef BenchmarkTransportFactory = AsrBenchmarkTransport Function(Uri baseUri);
typedef BenchmarkRunnerFactory =
    AsrBenchmarkRunner Function(AsrBenchmarkTransport transport);

class BenchmarkCommand {
  BenchmarkCommand({
    BenchmarkNow? now,
    BenchmarkTransportFactory? transportFactory,
    BenchmarkRunnerFactory? runnerFactory,
    BenchmarkReportWriter? reportWriter,
  }) : now = now ?? DateTime.now,
       transportFactory =
           transportFactory ??
           ((baseUri) => HttpAsrBenchmarkTransport(baseUri: baseUri)),
       runnerFactory =
           runnerFactory ??
           ((transport) => AsrBenchmarkRunner(transport: transport)),
       reportWriter = reportWriter ?? BenchmarkReportWriter();

  static const toolVersion = '1';

  final BenchmarkNow now;
  final BenchmarkTransportFactory transportFactory;
  final BenchmarkRunnerFactory runnerFactory;
  final BenchmarkReportWriter reportWriter;

  Future<int> run({
    required List<String> arguments,
    required Map<String, String> environment,
    required BenchmarkLineWriter writeOutput,
    required BenchmarkLineWriter writeError,
  }) async {
    try {
      final configuration = BenchmarkConfiguration.parse(
        arguments: arguments,
        environment: environment,
      );
      final startedAt = now();
      final transport = transportFactory(configuration.baseUri);
      final results = await runnerFactory(transport).run(configuration);
      final finishedAt = now();
      final report = BenchmarkReport.fromResults(results);
      final metadata = await BenchmarkRunMetadata.fromConfiguration(
        configuration,
        startedAt: startedAt,
        finishedAt: finishedAt,
        toolVersion: toolVersion,
      );
      await reportWriter.write(
        report: report,
        metadata: metadata,
        destination: configuration.reportFile,
      );
      for (final line in reportWriter.terminalSummary(report)) {
        writeOutput(line);
      }
      writeOutput(
        'report_file=${configuration.reportFile.uri.pathSegments.last}',
      );
      return report.aggregate.failedCount > 0 ||
              report.aggregate.timedOutCount > 0
          ? 1
          : 0;
    } on FormatException catch (error) {
      writeError('configuration_error=${error.message}');
      writeError(
        'usage=dart run tool/asr_benchmark.dart --audio <file> --jobs <count> --concurrency <count> --report <file> [--summary]',
      );
      return 64;
    } catch (_) {
      writeError('benchmark_error=unexpected');
      return 1;
    }
  }
}
