import 'dart:convert';
import 'dart:io';

import '../../../tool/src/asr_benchmark/asr_benchmark_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory directory;
  late HttpAsrBenchmarkTransport transport;
  late File audio;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    directory = await Directory.systemTemp.createTemp('aipin-asr-transport-');
    audio = File('${directory.path}${Platform.pathSeparator}capture.m4a');
    await audio.writeAsBytes(<int>[1, 2, 3]);
    transport = HttpAsrBenchmarkTransport(
      baseUri: Uri.parse('http://${server.address.address}:${server.port}'),
      allowInsecureHttpForTesting: true,
    );
  });

  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test(
    'submits a complete audio file with required ASR multipart fields',
    () async {
      final submissionFuture = transport.submit(audio);
      final request = await server.first;
      final body = await _readRequestBody(request);
      await _respondJson(request, <String, Object?>{
        'job_id': 'job-1',
        'status': 'queued',
      });

      final submission = await submissionFuture;

      expect(request.method, 'POST');
      expect(request.uri.path, '/api/jobs');
      expect(request.headers.contentType!.mimeType, 'multipart/form-data');
      expect(body, contains('name="files"; filename="capture.m4a"'));
      expect(
        body,
        contains('name="reference_files"; filename="reference.txt"'),
      );
      expect(body, contains('name="engines"\r\n\r\nsensevoice'));
      expect(body, contains('name="language"\r\n\r\nzh'));
      expect(body, contains('name="semantic_eval"\r\n\r\nfalse'));
      expect(submission.jobId, 'job-1');
    },
  );

  test('maps queued transcription state to pending', () async {
    final stateFuture = transport.pollTranscription('job-1');
    final request = await server.first;
    await _respondJson(request, <String, Object?>{
      'job_id': 'job-1',
      'status': 'queued',
    });

    expect(request.uri.path, '/api/jobs/job-1');
    expect(await stateFuture, BenchmarkRemoteState.pending);
  });

  test(
    'discards transcript text while preserving source identifiers',
    () async {
      final sourceFuture = transport.fetchTranscriptSource('job-1');
      final request = await server.first;
      await _respondJson(request, <String, Object?>{
        'flat_rows': <Object?>[
          <String, Object?>{
            'success': true,
            'transcript': 'this content must not enter the benchmark result',
            'relative_path': 'capture.m4a',
            'variant': 'original',
            'engine': 'sensevoice',
          },
        ],
      });

      final source = await sourceFuture;

      expect(request.uri.path, '/api/jobs/job-1/results');
      expect(source.relativePath, 'capture.m4a');
      expect(source.variant, 'original');
      expect(source.engine, 'sensevoice');
    },
  );

  test('maps a terminal ASR error to a safe transcription failure', () async {
    final stateFuture = transport.pollTranscription('job-1');
    final expectation = expectLater(
      stateFuture,
      throwsA(
        isA<BenchmarkTransportException>().having(
          (error) => error.kind,
          'kind',
          BenchmarkFailureKind.transcription,
        ),
      ),
    );
    final request = await server.first;
    await _respondJson(request, <String, Object?>{
      'job_id': 'job-1',
      'status': 'failed',
      'error': 'engine unavailable',
    });

    await expectation;
  });

  test('creates a summary task with only ASR source identifiers', () async {
    final taskFuture = transport.createSummary(
      jobId: 'job-1',
      source: const BenchmarkTranscriptSource(
        relativePath: 'capture.m4a',
        variant: 'original',
        engine: 'sensevoice',
      ),
    );
    final request = await server.first;
    final body = await _readRequestBody(request);
    await _respondJson(request, <String, Object?>{
      'note': <String, Object?>{'note_id': 'note-1'},
      'generation_task': <String, Object?>{'task_id': 'task-1'},
    });

    final task = await taskFuture;

    expect(request.uri.path, '/api/meeting-notes');
    expect(jsonDecode(body), <String, Object?>{
      'job_id': 'job-1',
      'relative_path': 'capture.m4a',
      'variant': 'original',
      'engine': 'sensevoice',
    });
    expect(task.noteId, 'note-1');
    expect(task.taskId, 'task-1');
  });

  test('recognizes a summary result without reading its content', () async {
    final stateFuture = transport.pollSummary(
      const BenchmarkSummaryTask(noteId: 'note-1', taskId: 'task-1'),
    );
    final request = await server.first;
    await _respondJson(request, <String, Object?>{
      'generation_task': <String, Object?>{
        'status': 'unknown',
        'result': <String, Object?>{},
      },
    });

    expect(
      request.uri.path,
      '/api/meeting-notes/note-1/generation-tasks/task-1',
    );
    expect(await stateFuture, BenchmarkRemoteState.completed);
  });
}

Future<String> _readRequestBody(HttpRequest request) async {
  final bytes = await request.fold<List<int>>(<int>[], (buffer, chunk) {
    buffer.addAll(chunk);
    return buffer;
  });
  return latin1.decode(bytes);
}

Future<void> _respondJson(
  HttpRequest request,
  Map<String, Object?> body,
) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}
