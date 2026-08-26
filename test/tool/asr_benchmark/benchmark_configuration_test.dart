import 'dart:io';

import '../../../tool/src/asr_benchmark/benchmark_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aipin-asr-benchmark-');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('rejects a non-HTTPS ASR endpoint', () async {
    final audio = await _writeAudio(directory, 'capture.m4a');

    expect(
      () => BenchmarkConfiguration.parse(
        arguments: <String>[
          '--audio',
          audio.path,
          '--jobs',
          '2',
          '--concurrency',
          '2',
          '--report',
          '${directory.path}${Platform.pathSeparator}run.json',
        ],
        environment: const <String, String>{
          'ASR_API_BASE_URL': 'http://asr.example',
        },
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects an empty audio file and invalid worker allocation', () async {
    final emptyAudio = File(
      '${directory.path}${Platform.pathSeparator}empty.m4a',
    );
    await emptyAudio.create();

    expect(
      () => BenchmarkConfiguration.parse(
        arguments: <String>[
          '--audio',
          emptyAudio.path,
          '--jobs',
          '2',
          '--concurrency',
          '3',
          '--report',
          '${directory.path}${Platform.pathSeparator}run.json',
        ],
        environment: const <String, String>{
          'ASR_API_BASE_URL': 'https://asr.example',
        },
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('parses a bounded benchmark configuration', () async {
    final audio = await _writeAudio(directory, 'capture.m4a');
    final reportPath = '${directory.path}${Platform.pathSeparator}run.json';

    final configuration = BenchmarkConfiguration.parse(
      arguments: <String>[
        '--audio',
        audio.path,
        '--jobs',
        '8',
        '--concurrency',
        '4',
        '--summary',
        '--report',
        reportPath,
      ],
      environment: const <String, String>{
        'ASR_API_BASE_URL': 'https://asr.example/api',
      },
    );

    expect(configuration.baseUri, Uri.parse('https://asr.example/api/'));
    expect(configuration.audioFile.path, audio.path);
    expect(configuration.jobCount, 8);
    expect(configuration.concurrency, 4);
    expect(configuration.includeSummary, isTrue);
    expect(configuration.reportFile.path, reportPath);
    expect(configuration.jobTimeout, const Duration(minutes: 45));
  });
}

Future<File> _writeAudio(Directory directory, String filename) async {
  final file = File('${directory.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(<int>[1, 2, 3]);
  return file;
}
