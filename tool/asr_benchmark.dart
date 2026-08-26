import 'dart:io';

import 'src/asr_benchmark/benchmark_command.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await BenchmarkCommand().run(
    arguments: arguments,
    environment: Platform.environment,
    writeOutput: stdout.writeln,
    writeError: stderr.writeln,
  );
}
