// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/research_beta/data/ai_voice_service_configuration.dart';
import 'package:aipin/features/research_beta/domain/temporary_asr_gateway.dart';

typedef VerifiedNoteMapper =
    AsrGeneratedNote? Function(Map<String, Object?> note);

class TemporaryAsrHttpGateway implements TemporaryAsrGateway {
  TemporaryAsrHttpGateway({
    String? baseUrl,
    Set<String> verifiedGenerationPendingStatuses = const <String>{},
    Set<String> verifiedGenerationCompletionStatuses = const <String>{},
    Set<String> verifiedGenerationFailureStatuses = const <String>{},
    VerifiedNoteMapper? verifiedNoteMapper,
    Duration requestTimeout = const Duration(seconds: 15),
    Duration uploadRequestTimeout = const Duration(minutes: 3),
    bool allowInsecureHttpForTesting = false,
    HttpClient Function()? clientFactory,
    SafeAppLogger? logger,
  }) : _baseUri = _parseBaseUri(
         AiVoiceServiceConfiguration.resolveBaseUrl(explicitValue: baseUrl),
         allowInsecureHttpForTesting: allowInsecureHttpForTesting,
       ),
       _verifiedGenerationPendingStatuses = _normaliseStatuses(
         verifiedGenerationPendingStatuses,
       ),
       _verifiedGenerationCompletionStatuses = _normaliseStatuses(
         verifiedGenerationCompletionStatuses,
       ),
       _verifiedGenerationFailureStatuses = _normaliseStatuses(
         verifiedGenerationFailureStatuses,
       ),
       _verifiedNoteMapper = verifiedNoteMapper,
       _requestTimeout = requestTimeout,
       _uploadRequestTimeout = uploadRequestTimeout,
       _clientFactory = clientFactory ?? HttpClient.new,
       _logger = logger ?? const DebugSafeAppLogger() {
    _logger.info(
      'gateway_initialized',
      fields: <String, Object?>{
        'configured': _baseUri != null,
        'host': _baseUri?.host ?? 'none',
      },
    );
  }

  final Uri? _baseUri;
  final Set<String> _verifiedGenerationPendingStatuses;
  final Set<String> _verifiedGenerationCompletionStatuses;
  final Set<String> _verifiedGenerationFailureStatuses;
  final VerifiedNoteMapper? _verifiedNoteMapper;
  final Duration _requestTimeout;
  final Duration _uploadRequestTimeout;
  final HttpClient Function() _clientFactory;
  final SafeAppLogger _logger;

  @override
  Future<AsrOutcome<AsrNoteTask>> createNote({
    required String jobId,
    required AsrTranscript transcript,
  }) async {
    final response = await _sendJson(
      method: 'POST',
      path: '/api/meeting-notes',
      body: <String, Object?>{
        'job_id': jobId,
        'relative_path': transcript.relativePath,
        'variant': transcript.variant,
        'engine': transcript.engine,
      },
    );
    switch (response) {
      case AsrFailure<Map<String, Object?>>(:final kind, :final message):
        return AsrFailure<AsrNoteTask>(kind: kind, message: message);
      case AsrSuccess<Map<String, Object?>>(:final value):
        final note = _mapValue(value['note']);
        final task = _mapValue(value['generation_task']);
        final noteId = _nonBlank(note?['note_id']) ?? _nonBlank(note?['id']);
        final taskId = _nonBlank(task?['task_id']) ?? _nonBlank(task?['id']);
        if (noteId == null || taskId == null) {
          return const AsrFailure<AsrNoteTask>(
            kind: AsrFailureKind.invalidResponse,
            message: 'AI 整理服务未返回可继续处理的任务标识。',
          );
        }
        return AsrSuccess(
          AsrNoteTask(noteId: noteId, generationTaskId: taskId),
        );
    }
  }

  @override
  Future<AsrOutcome<void>> deleteNote(String noteId) async {
    final response = await _sendJson(
      method: 'POST',
      path: '/api/meeting-notes/$noteId/permanent-delete',
      body: const <String, Object?>{'confirm': true},
    );
    switch (response) {
      case AsrFailure<Map<String, Object?>>(:final kind, :final message):
        return AsrFailure<void>(kind: kind, message: message);
      case AsrSuccess<Map<String, Object?>>():
        return const AsrSuccess<void>(null);
    }
  }

  @override
  Future<AsrOutcome<AsrGeneratedNote>> fetchCompletedNote(String noteId) async {
    final response = await _sendJson(
      method: 'GET',
      path: '/api/meeting-notes/$noteId',
    );
    switch (response) {
      case AsrFailure<Map<String, Object?>>(:final kind, :final message):
        return AsrFailure<AsrGeneratedNote>(kind: kind, message: message);
      case AsrSuccess<Map<String, Object?>>(:final value):
        final note = _mapValue(value['note']);
        final mapper = _verifiedNoteMapper;
        if (note == null || mapper == null) {
          return const AsrFailure<AsrGeneratedNote>(
            kind: AsrFailureKind.summaryUnsupported,
            message: '当前 AI 整理结果结构尚未通过研究夹具验证。',
          );
        }
        final generated = mapper(note);
        if (generated == null ||
            generated.title.trim().isEmpty ||
            generated.summary.trim().isEmpty) {
          return const AsrFailure<AsrGeneratedNote>(
            kind: AsrFailureKind.summaryUnsupported,
            message: '当前 AI 整理结果不包含已验证的卡片字段。',
          );
        }
        return AsrSuccess(generated);
    }
  }

  @override
  Future<AsrOutcome<AsrTranscript>> fetchTranscript(String jobId) async {
    final response = await _sendJson(
      method: 'GET',
      path: '/api/jobs/$jobId/results',
    );
    switch (response) {
      case AsrFailure<Map<String, Object?>>(:final kind, :final message):
        return AsrFailure<AsrTranscript>(kind: kind, message: message);
      case AsrSuccess<Map<String, Object?>>(:final value):
        final rows = value['flat_rows'];
        if (rows is! List) {
          return const AsrFailure<AsrTranscript>(
            kind: AsrFailureKind.invalidResponse,
            message: '转写服务未返回可读取的结果。',
          );
        }
        AsrTranscript? source;
        final segments = <String>[];
        for (final item in rows) {
          final row = _mapValue(item);
          if (row == null || row['success'] != true) {
            continue;
          }
          final transcript = _nonBlank(row['transcript']);
          final relativePath = _nonBlank(row['relative_path']);
          final variant = _nonBlank(row['variant']);
          final engine = _nonBlank(row['engine']);
          if (transcript != null &&
              relativePath != null &&
              variant != null &&
              engine != null) {
            final candidate = AsrTranscript(
              text: transcript,
              relativePath: relativePath,
              variant: variant,
              engine: engine,
            );
            if (source == null) {
              source = candidate;
              segments.add(candidate.text);
              continue;
            }
            if (candidate.relativePath == source.relativePath &&
                candidate.variant == source.variant &&
                candidate.engine == source.engine) {
              segments.add(candidate.text);
            }
          }
        }
        if (source != null) {
          final text = segments.join('\n');
          _logger.info(
            'transcript_accepted',
            fields: <String, Object?>{
              'job_id': jobId,
              'segment_count': segments.length,
              'text_length': text.length,
              'engine': source.engine,
              'variant': source.variant,
            },
          );
          return AsrSuccess(
            AsrTranscript(
              text: text,
              relativePath: source.relativePath,
              variant: source.variant,
              engine: source.engine,
            ),
          );
        }
        return const AsrFailure<AsrTranscript>(
          kind: AsrFailureKind.transcription,
          message: '转写结果为空或格式无效。',
        );
    }
  }

  @override
  Future<AsrOutcome<AsrJob>> pollJob(String jobId) async {
    final response = await _sendJson(method: 'GET', path: '/api/jobs/$jobId');
    switch (response) {
      case AsrFailure<Map<String, Object?>>(:final kind, :final message):
        return AsrFailure<AsrJob>(kind: kind, message: message);
      case AsrSuccess<Map<String, Object?>>(:final value):
        if (_nonBlank(value['error']) != null) {
          return AsrFailure<AsrJob>(
            kind: AsrFailureKind.transcription,
            message: _nonBlank(value['error'])!,
          );
        }
        return _jobFromResponse(value, fallbackId: jobId, fromPolling: true);
    }
  }

  @override
  Future<AsrOutcome<AsrGenerationStatus>> pollGenerationTask({
    required String noteId,
    required String generationTaskId,
  }) async {
    final response = await _sendJson(
      method: 'GET',
      path: '/api/meeting-notes/$noteId/generation-tasks/$generationTaskId',
    );
    switch (response) {
      case AsrFailure<Map<String, Object?>>(:final kind, :final message):
        return AsrFailure<AsrGenerationStatus>(kind: kind, message: message);
      case AsrSuccess<Map<String, Object?>>(:final value):
        final task = _mapValue(value['generation_task']) ?? value;
        final status = _normaliseStatus(_nonBlank(task['status']));
        final failureMessage =
            _nonBlank(task['error_message']) ?? _nonBlank(task['error']);
        if (failureMessage != null ||
            status == 'failed' ||
            (status != null &&
                _verifiedGenerationFailureStatuses.contains(status))) {
          return AsrFailure<AsrGenerationStatus>(
            kind: AsrFailureKind.remote,
            message: failureMessage ?? 'AI 整理服务处理失败。',
          );
        }
        if (status != null &&
            _verifiedGenerationPendingStatuses.contains(status)) {
          return const AsrSuccess<AsrGenerationStatus>(
            AsrGenerationStatus.pending,
          );
        }
        if (status != null &&
            _verifiedGenerationCompletionStatuses.contains(status)) {
          return const AsrSuccess<AsrGenerationStatus>(
            AsrGenerationStatus.completed,
          );
        }
        if (task['result'] != null) {
          return const AsrSuccess<AsrGenerationStatus>(
            AsrGenerationStatus.completed,
          );
        }
        return const AsrFailure<AsrGenerationStatus>(
          kind: AsrFailureKind.summaryUnsupported,
          message: 'AI 整理服务返回了未经验证的任务状态。',
        );
    }
  }

  @override
  Future<AsrOutcome<AsrJob>> submitAudio(String absoluteAudioPath) async {
    final baseUri = _baseUri;
    if (baseUri == null) {
      _logger.info(
        'request_skipped',
        fields: const {'stage': 'submit', 'reason': 'unconfigured'},
      );
      return const AsrFailure<AsrJob>(
        kind: AsrFailureKind.unavailable,
        message: '暂未配置 AI 语音服务。',
      );
    }
    final source = File(absoluteAudioPath);
    try {
      if (!await source.exists() || await source.length() == 0) {
        _logger.info(
          'request_skipped',
          fields: const {'stage': 'submit', 'reason': 'empty_audio'},
        );
        return const AsrFailure<AsrJob>(
          kind: AsrFailureKind.upload,
          message: '研究录音文件不可用。',
        );
      }
    } on FileSystemException {
      _logger.info(
        'request_skipped',
        fields: const {'stage': 'submit', 'reason': 'unreadable_audio'},
      );
      return const AsrFailure<AsrJob>(
        kind: AsrFailureKind.upload,
        message: '研究录音文件不可用。',
      );
    }

    final sourceSizeBytes = await source.length();
    final client = _clientFactory();
    client.connectionTimeout = _requestTimeout;
    try {
      _logger.info(
        'request_started',
        fields: <String, Object?>{
          'stage': 'submit',
          'method': 'POST',
          'bytes': sourceSizeBytes,
        },
      );
      final boundary = 'aipin-${DateTime.now().microsecondsSinceEpoch}';
      final request = await _withRequestTimeout(
        client.postUrl(baseUri.resolve('/api/jobs')),
      );
      request.headers.contentType = ContentType(
        'multipart',
        'form-data',
        parameters: <String, String>{'boundary': boundary},
      );
      _writeField(request, boundary, 'engines', 'sensevoice');
      _writeField(request, boundary, 'language', 'zh');
      _writeField(request, boundary, 'semantic_eval', 'false');
      _writeFileHeader(
        request,
        boundary,
        field: 'files',
        filename: _filenameFor(source),
        contentType: 'audio/mp4',
      );
      await _withRequestTimeout(
        request.addStream(source.openRead()),
        timeout: _uploadRequestTimeout,
      );
      request.add(utf8.encode('\r\n'));
      _writeFileHeader(
        request,
        boundary,
        field: 'reference_files',
        filename: 'reference.txt',
        contentType: 'text/plain; charset=utf-8',
      );
      request.add(utf8.encode('\r\n--$boundary--\r\n'));
      final response = await _withRequestTimeout(
        request.close(),
        timeout: _uploadRequestTimeout,
      );
      final decoded = await _withRequestTimeout(
        _decodeJsonResponse(response, stage: 'submit'),
        timeout: _uploadRequestTimeout,
      );
      switch (decoded) {
        case AsrFailure<Map<String, Object?>>(:final kind, :final message):
          return AsrFailure<AsrJob>(kind: kind, message: message);
        case AsrSuccess<Map<String, Object?>>(:final value):
          return _jobFromResponse(value, fromPolling: false);
      }
    } on HttpException catch (error) {
      _logger.info(
        'request_failed',
        fields: {'stage': 'submit', 'error': error.runtimeType},
      );
      return AsrFailure<AsrJob>(
        kind: AsrFailureKind.network,
        message: '无法连接 AI 语音服务：${error.message}',
      );
    } on SocketException catch (error) {
      _logger.info(
        'request_failed',
        fields: {'stage': 'submit', 'error': error.runtimeType},
      );
      return AsrFailure<AsrJob>(
        kind: AsrFailureKind.network,
        message: '无法连接 AI 语音服务：${error.message}',
      );
    } on TimeoutException {
      _logger.info(
        'request_failed',
        fields: const {'stage': 'submit', 'error': 'timeout'},
      );
      return const AsrFailure<AsrJob>(
        kind: AsrFailureKind.network,
        message: 'AI 语音服务请求超时。',
      );
    } on FileSystemException catch (error) {
      _logger.info(
        'request_failed',
        fields: {'stage': 'submit', 'error': error.runtimeType},
      );
      return AsrFailure<AsrJob>(
        kind: AsrFailureKind.upload,
        message: '无法读取研究录音文件：${error.message}',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<AsrOutcome<Map<String, Object?>>> _sendJson({
    required String method,
    required String path,
    Map<String, Object?>? body,
  }) async {
    final baseUri = _baseUri;
    if (baseUri == null) {
      _logger.info(
        'request_skipped',
        fields: {'stage': path, 'reason': 'unconfigured'},
      );
      return const AsrFailure<Map<String, Object?>>(
        kind: AsrFailureKind.unavailable,
        message: '暂未配置 AI 语音服务。',
      );
    }
    final client = _clientFactory();
    client.connectionTimeout = _requestTimeout;
    try {
      _logger.info(
        'request_started',
        fields: {'stage': path, 'method': method},
      );
      final request = await _withRequestTimeout(
        client.openUrl(method, baseUri.resolve(path)),
      );
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await _withRequestTimeout(request.close());
      return await _withRequestTimeout(
        _decodeJsonResponse(response, stage: path),
      );
    } on HttpException catch (error) {
      _logger.info(
        'request_failed',
        fields: {'stage': path, 'error': error.runtimeType},
      );
      return AsrFailure<Map<String, Object?>>(
        kind: AsrFailureKind.network,
        message: '无法连接 AI 语音服务：${error.message}',
      );
    } on SocketException catch (error) {
      _logger.info(
        'request_failed',
        fields: {'stage': path, 'error': error.runtimeType},
      );
      return AsrFailure<Map<String, Object?>>(
        kind: AsrFailureKind.network,
        message: '无法连接 AI 语音服务：${error.message}',
      );
    } on TimeoutException {
      _logger.info(
        'request_failed',
        fields: {'stage': path, 'error': 'timeout'},
      );
      return const AsrFailure<Map<String, Object?>>(
        kind: AsrFailureKind.network,
        message: 'AI 语音服务请求超时。',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<T> _withRequestTimeout<T>(Future<T> request, {Duration? timeout}) {
    return request.timeout(timeout ?? _requestTimeout);
  }

  Future<AsrOutcome<Map<String, Object?>>> _decodeJsonResponse(
    HttpClientResponse response, {
    required String stage,
  }) async {
    final text = await utf8.decodeStream(response);
    Map<String, Object?>? decoded;
    try {
      decoded = _mapValue(jsonDecode(text));
    } on FormatException {
      decoded = null;
    }
    final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
    _logger.info(
      'response_received',
      fields: {
        'stage': stage,
        'status': response.statusCode,
        'success': isSuccess,
      },
    );
    if (!isSuccess) {
      return AsrFailure<Map<String, Object?>>(
        kind: AsrFailureKind.remote,
        message:
            _nonBlank(decoded?['message']) ??
            _nonBlank(decoded?['detail']) ??
            'AI 语音服务请求失败（${response.statusCode}）。',
      );
    }
    if (decoded == null) {
      return const AsrFailure<Map<String, Object?>>(
        kind: AsrFailureKind.invalidResponse,
        message: 'AI 语音服务返回格式无效。',
      );
    }
    return AsrSuccess(decoded);
  }

  AsrOutcome<AsrJob> _jobFromResponse(
    Map<String, Object?> value, {
    String? fallbackId,
    required bool fromPolling,
  }) {
    final id =
        _nonBlank(value['job_id']) ?? _nonBlank(value['id']) ?? fallbackId;
    final status = _normaliseStatus(_nonBlank(value['status']));
    if (id == null || status == null) {
      return const AsrFailure<AsrJob>(
        kind: AsrFailureKind.invalidResponse,
        message: '转写服务未返回有效任务状态。',
      );
    }
    if (status == 'queued' || status == 'running') {
      return AsrSuccess(AsrJob(id: id, status: AsrJobStatus.pending));
    }
    if (status == 'completed') {
      return AsrSuccess(AsrJob(id: id, status: AsrJobStatus.completed));
    }
    return AsrFailure<AsrJob>(
      kind: AsrFailureKind.transcription,
      message:
          _nonBlank(value['error']) ??
          (fromPolling ? '转写服务处理失败。' : '转写任务未被接受。'),
    );
  }

  static Uri? _parseBaseUri(
    String rawValue, {
    required bool allowInsecureHttpForTesting,
  }) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    final scheme = uri?.scheme.toLowerCase();
    final isTestLoopbackHttp =
        allowInsecureHttpForTesting &&
        scheme == 'http' &&
        _isLoopbackHost(uri?.host);
    if (uri == null ||
        (scheme != 'https' && !isTestLoopbackHttp) ||
        uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  static bool _isLoopbackHost(String? host) =>
      host == '127.0.0.1' || host == 'localhost' || host == '::1';

  static Set<String> _normaliseStatuses(Set<String> values) {
    return values.map(_normaliseStatus).whereType<String>().toSet();
  }

  static String? _normaliseStatus(String? value) {
    final trimmed = value?.trim().toLowerCase();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static Map<String, Object?>? _mapValue(Object? value) {
    if (value is! Map) {
      return null;
    }
    return value.map<String, Object?>(
      (key, entry) => MapEntry(key.toString(), entry),
    );
  }

  static String? _nonBlank(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _filenameFor(File file) {
    final segments = file.uri.pathSegments;
    return segments.isEmpty ? 'capture.m4a' : segments.last;
  }

  static void _writeField(
    HttpClientRequest request,
    String boundary,
    String name,
    String value,
  ) {
    request.add(
      utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="$name"\r\n\r\n'
        '$value\r\n',
      ),
    );
  }

  static void _writeFileHeader(
    HttpClientRequest request,
    String boundary, {
    required String field,
    required String filename,
    required String contentType,
  }) {
    request.add(
      utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="$field"; filename="$filename"\r\n'
        'Content-Type: $contentType\r\n\r\n',
      ),
    );
  }
}
