import '../../../tool/src/asr_benchmark/benchmark_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns usage exit code without echoing an input path', () async {
    final output = <String>[];
    final errors = <String>[];

    final exitCode = await BenchmarkCommand().run(
      arguments: const <String>['--audio', r'C:\sensitive\capture.m4a'],
      environment: const <String, String>{},
      writeOutput: output.add,
      writeError: errors.add,
    );

    expect(exitCode, 64);
    expect(output, isEmpty);
    expect(errors.first, startsWith('configuration_error='));
    expect(errors.join('\n'), isNot(contains(r'C:\sensitive\capture.m4a')));
  });
}
