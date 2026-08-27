import 'dart:convert';
import 'dart:io';

import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/research_beta/data/ai_voice_service_configuration.dart';
import 'package:aipin/features/research_beta/data/temporary_asr_http_gateway.dart';
import 'package:aipin/features/research_beta/domain/temporary_asr_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory directory;
  late TemporaryAsrHttpGateway gateway;
  late _CapturingLogger logger;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    directory = await Directory.systemTemp.createTemp('aipin-asr-gateway-');
    logger = _CapturingLogger();
    gateway = TemporaryAsrHttpGateway(
      baseUrl: 'http://${server.address.address}:${server.port}',
      allowInsecureHttpForTesting: true,
      logger: logger,
    );
  });

  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test(
    'submitAudio posts audio and required empty reference attachment',
    () async {
      final audio = File(
        '${directory.path}${Platform.pathSeparator}capture.m4a',
      );
      await audio.writeAsBytes(<int>[1, 2, 3]);

      final outcomeFuture = gateway.submitAudio(audio.path);
      final request = await server.first;
      final body = await _readBody(request);
      await _respondJson(request, <String, Object?>{
        'job_id': 'job-1',
        'status': 'queued',
      });
      final outcome = await outcomeFuture;

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
      expect(outcome, isA<AsrSuccess<AsrJob>>());
    },
  );

  test(
    'submitAudio sends a multipart request with a known content length',
    () async {
      final audio = File(
        '${directory.path}${Platform.pathSeparator}sized-capture.m4a',
      );
      await audio.writeAsBytes(
        List<int>.generate(1024, (index) => index % 256),
      );

      final outcomeFuture = gateway.submitAudio(audio.path);
      final request = await server.first;
      final body = await _readBodyBytes(request);
      await _respondJson(request, <String, Object?>{
        'job_id': 'job-1',
        'status': 'queued',
      });

      expect(request.headers.contentLength, body.length);
      expect(request.headers.value(HttpHeaders.transferEncodingHeader), isNull);
      expect(await outcomeFuture, isA<AsrSuccess<AsrJob>>());
    },
  );

  test(
    'audio submission is not limited by the regular request timeout',
    () async {
      final audio = File(
        '${directory.path}${Platform.pathSeparator}long-capture.m4a',
      );
      await audio.writeAsBytes(<int>[1, 2, 3]);
      final shortRequestGateway = TemporaryAsrHttpGateway(
        baseUrl: 'http://${server.address.address}:${server.port}',
        requestTimeout: const Duration(milliseconds: 10),
        allowInsecureHttpForTesting: true,
      );

      final outcomeFuture = shortRequestGateway.submitAudio(audio.path);
      final request = await server.first;
      await _readBody(request);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      await _respondJson(request, <String, Object?>{
        'job_id': 'job-1',
        'status': 'queued',
      });

      expect(await outcomeFuture, isA<AsrSuccess<AsrJob>>());
    },
  );

  test('empty successful transcript is rejected', () async {
    final outcomeFuture = gateway.fetchTranscript('job-1');
    final request = await server.first;
    await _respondJson(request, <String, Object?>{
      'flat_rows': <Object?>[
        <String, Object?>{
          'success': true,
          'transcript': '',
          'relative_path': 'capture.m4a',
          'variant': 'original',
          'engine': 'sensevoice',
        },
      ],
    });

    expect(request.uri.path, '/api/jobs/job-1/results');
    expect(await outcomeFuture, isA<AsrFailure<AsrTranscript>>());
  });

  test(
    'combines successful transcript segments from the same source',
    () async {
      final outcomeFuture = gateway.fetchTranscript('job-1');
      final request = await server.first;
      await _respondJson(request, <String, Object?>{
        'flat_rows': <Object?>[
          <String, Object?>{
            'success': true,
            'transcript': '第一段',
            'relative_path': 'capture.m4a',
            'variant': 'original',
            'engine': 'sensevoice',
          },
          <String, Object?>{
            'success': true,
            'transcript': '备用引擎结果',
            'relative_path': 'capture.m4a',
            'variant': 'original',
            'engine': 'other-engine',
          },
          <String, Object?>{
            'success': true,
            'transcript': '第二段',
            'relative_path': 'capture.m4a',
            'variant': 'original',
            'engine': 'sensevoice',
          },
        ],
      });

      final outcome = await outcomeFuture;

      expect(request.uri.path, '/api/jobs/job-1/results');
      expect(
        outcome,
        isA<AsrSuccess<AsrTranscript>>().having(
          (value) => value.value.text,
          'text',
          '第一段\n第二段',
        ),
      );
    },
  );

  test('logs non-sensitive metadata after accepting a transcript', () async {
    final outcomeFuture = gateway.fetchTranscript('job-1');
    final request = await server.first;
    await _respondJson(request, <String, Object?>{
      'flat_rows': <Object?>[
        <String, Object?>{
          'success': true,
          'transcript': '已解析的转写文本',
          'relative_path': 'capture.m4a',
          'variant': 'original',
          'engine': 'sensevoice',
        },
      ],
    });

    expect(await outcomeFuture, isA<AsrSuccess<AsrTranscript>>());
    expect(
      logger.events,
      contains(
        _LoggedEvent('transcript_accepted', const <String, Object?>{
          'job_id': 'job-1',
          'segment_count': 1,
          'text_length': 8,
          'engine': 'sensevoice',
          'variant': 'original',
        }),
      ),
    );
  });

  test('accepts deployed note and generation task identifiers', () async {
    final outcomeFuture = gateway.createNote(
      jobId: 'job-1',
      transcript: const AsrTranscript(
        text: '转写内容',
        relativePath: 'capture.m4a',
        variant: 'original',
        engine: 'sensevoice',
      ),
    );
    final request = await server.first;
    await _respondJson(request, <String, Object?>{
      'note': <String, Object?>{'note_id': 'note-1'},
      'generation_task': <String, Object?>{'task_id': 'task-1'},
    });

    expect(request.uri.path, '/api/meeting-notes');
    expect(
      await outcomeFuture,
      isA<AsrSuccess<AsrNoteTask>>()
          .having((value) => value.value.noteId, 'note ID', 'note-1')
          .having((value) => value.value.generationTaskId, 'task ID', 'task-1'),
    );
  });

  test(
    'posts ordered source quadruples to the aggregate note endpoint',
    () async {
      final outcomeFuture = gateway.createAggregateNote(
        recordingId: 'capture-1',
        sources: const <AsrAggregateSource>[
          AsrAggregateSource(
            segmentIndex: 0,
            jobId: 'job-first',
            transcript: AsrTranscript(
              text: '第一段',
              relativePath: 'capture-1.segment-0000.m4a',
              variant: 'original',
              engine: 'sensevoice',
            ),
          ),
          AsrAggregateSource(
            segmentIndex: 1,
            jobId: 'job-second',
            transcript: AsrTranscript(
              text: '第二段',
              relativePath: 'capture-1.segment-0001.m4a',
              variant: 'original',
              engine: 'sensevoice',
            ),
          ),
        ],
      );
      final request = await server.first;
      final body = await _readJsonBody(request);
      await _respondJson(request, <String, Object?>{
        'note': <String, Object?>{'note_id': 'note-aggregate'},
        'generation_task': <String, Object?>{'task_id': 'task-aggregate'},
      });

      expect(request.uri.path, '/api/meeting-notes/aggregate');
      expect(body['recording_id'], 'capture-1');
      expect(body['title'], isNull);
      expect(body['sources'], <Object?>[
        <String, Object?>{
          'segment_index': 0,
          'job_id': 'job-first',
          'relative_path': 'capture-1.segment-0000.m4a',
          'variant': 'original',
          'engine': 'sensevoice',
        },
        <String, Object?>{
          'segment_index': 1,
          'job_id': 'job-second',
          'relative_path': 'capture-1.segment-0001.m4a',
          'variant': 'original',
          'engine': 'sensevoice',
        },
      ]);
      expect(
        await outcomeFuture,
        isA<AsrSuccess<AsrNoteTask>>()
            .having((value) => value.value.noteId, 'note ID', 'note-aggregate')
            .having(
              (value) => value.value.generationTaskId,
              'task ID',
              'task-aggregate',
            ),
      );
    },
  );

  test('accepts the documented succeeded generation status', () async {
    final outcomeFuture = gateway.pollGenerationTask(
      noteId: 'note-1',
      generationTaskId: 'task-1',
    );
    final request = await server.first;
    await _respondJson(request, <String, Object?>{
      'generation_task': <String, Object?>{'status': 'succeeded'},
    });

    expect(
      await outcomeFuture,
      isA<AsrSuccess<AsrGenerationStatus>>().having(
        (value) => value.value,
        'status',
        AsrGenerationStatus.completed,
      ),
    );
  });

  test('uses the deployed generation failure message', () async {
    final outcomeFuture = gateway.pollGenerationTask(
      noteId: 'note-1',
      generationTaskId: 'task-1',
    );
    final request = await server.first;
    await _respondJson(request, <String, Object?>{
      'generation_task': <String, Object?>{
        'status': 'failed',
        'error_code': 'provider_unavailable',
        'error_message': '总结服务暂不可用。',
      },
    });

    expect(
      await outcomeFuture,
      isA<AsrFailure<AsrGenerationStatus>>()
          .having((value) => value.kind, 'kind', AsrFailureKind.remote)
          .having((value) => value.message, 'message', '总结服务暂不可用。'),
    );
  });

  test('unknown generation status is not treated as completed', () async {
    final outcomeFuture = gateway.pollGenerationTask(
      noteId: 'note-1',
      generationTaskId: 'task-1',
    );
    final request = await server.first;
    await _respondJson(request, <String, Object?>{
      'generation_task': <String, Object?>{'status': 'mystery-complete'},
    });

    expect(
      request.uri.path,
      '/api/meeting-notes/note-1/generation-tasks/task-1',
    );
    expect(await outcomeFuture, isA<AsrFailure<AsrGenerationStatus>>());
  });

  test(
    'unconfigured endpoint fails before opening a network connection',
    () async {
      final unavailable = TemporaryAsrHttpGateway(baseUrl: '');

      final outcome = await unavailable.pollJob('job-1');

      expect(
        outcome,
        isA<AsrFailure<AsrJob>>().having(
          (value) => value.kind,
          'kind',
          AsrFailureKind.unavailable,
        ),
      );
    },
  );

  test(
    'uses a debug fallback only when no explicit service address exists',
    () {
      expect(
        AiVoiceServiceConfiguration.resolveBaseUrl(
          dartDefineValue: '',
          debugFallbackValue: 'https://debug.example',
        ),
        'https://debug.example',
      );
      expect(
        AiVoiceServiceConfiguration.resolveBaseUrl(
          dartDefineValue: 'https://define.example',
          debugFallbackValue: 'https://debug.example',
        ),
        'https://define.example',
      );
    },
  );

  test('rejects a plaintext endpoint before opening a request', () async {
    final insecure = TemporaryAsrHttpGateway(
      baseUrl: 'http://127.0.0.1:1',
      requestTimeout: const Duration(milliseconds: 10),
    );

    final outcome = await insecure.pollJob('job-1');

    expect(
      outcome,
      isA<AsrFailure<AsrJob>>().having(
        (value) => value.kind,
        'kind',
        AsrFailureKind.unavailable,
      ),
    );
  });

  test('accepts a private-network HTTP endpoint only for explicit testing', () {
    final internal = TemporaryAsrHttpGateway(
      baseUrl: 'http://192.168.0.156:8000',
      allowInsecureHttpForTesting: true,
    );

    expect(internal.isConfigured, isTrue);
  });

  test('a response timeout returns a retryable network failure', () async {
    final timeoutGateway = TemporaryAsrHttpGateway(
      baseUrl: 'http://${server.address.address}:${server.port}',
      requestTimeout: const Duration(milliseconds: 10),
      allowInsecureHttpForTesting: true,
    );

    final outcomeFuture = timeoutGateway.pollJob('job-1');
    await server.first;
    final outcome = await outcomeFuture.timeout(
      const Duration(milliseconds: 100),
    );

    expect(
      outcome,
      isA<AsrFailure<AsrJob>>().having(
        (value) => value.kind,
        'kind',
        AsrFailureKind.network,
      ),
    );
  });
}

Future<String> _readBody(HttpRequest request) async {
  final bytes = await _readBodyBytes(request);
  return latin1.decode(bytes);
}

Future<Map<String, Object?>> _readJsonBody(HttpRequest request) async {
  final value = jsonDecode(await utf8.decodeStream(request));
  return (value as Map).map<String, Object?>(
    (key, item) => MapEntry('$key', item),
  );
}

Future<List<int>> _readBodyBytes(HttpRequest request) {
  return request.fold<List<int>>(<int>[], (buffer, chunk) {
    buffer.addAll(chunk);
    return buffer;
  });
}

Future<void> _respondJson(
  HttpRequest request,
  Map<String, Object?> value,
) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(value));
  await request.response.close();
}

class _CapturingLogger implements SafeAppLogger {
  final List<_LoggedEvent> events = <_LoggedEvent>[];

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {
    events.add(_LoggedEvent(event, Map<String, Object?>.from(fields)));
  }
}

class _LoggedEvent {
  const _LoggedEvent(this.name, this.fields);

  final String name;
  final Map<String, Object?> fields;

  @override
  bool operator ==(Object other) {
    return other is _LoggedEvent &&
        other.name == name &&
        _mapsEqual(other.fields, fields);
  }

  @override
  int get hashCode => Object.hash(name, Object.hashAll(fields.entries));
}

bool _mapsEqual(Map<String, Object?> first, Map<String, Object?> second) {
  if (first.length != second.length) {
    return false;
  }
  return first.entries.every((entry) => second[entry.key] == entry.value);
}
