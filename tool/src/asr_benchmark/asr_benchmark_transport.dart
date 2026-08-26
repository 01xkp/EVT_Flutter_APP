import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum BenchmarkRemoteState { pending, completed }

enum BenchmarkFailureKind {
  network,
  remote,
  invalidResponse,
  transcription,
  summary,
}

class BenchmarkTransportException implements Exception {
  const BenchmarkTransportException({
    required this.kind,
    required this.message,
  });

  final BenchmarkFailureKind kind;
  final String message;

  @override
  String toString() => 'BenchmarkTransportException($kind: $message)';
}

class BenchmarkSubmission {
  const BenchmarkSubmission(this.jobId);

  final String jobId;
}

class BenchmarkTranscriptSource {
  const BenchmarkTranscriptSource({
    required this.relativePath,
    required this.variant,
    required this.engine,
  });

  final String relativePath;
  final String variant;
  final String engine;
}

class BenchmarkSummaryTask {
  const BenchmarkSummaryTask({required this.noteId, required this.taskId});

  final String noteId;
  final String taskId;
}

abstract interface class AsrBenchmarkTransport {
  Future<BenchmarkSubmission> submit(File audioFile);
  Future<BenchmarkRemoteState> pollTranscription(String jobId);
  Future<BenchmarkTranscriptSource> fetchTranscriptSource(String jobId);
  Future<BenchmarkSummaryTask> createSummary({
    required String jobId,
    required BenchmarkTranscriptSource source,
  });
  Future<BenchmarkRemoteState> pollSummary(BenchmarkSummaryTask task);
}

class HttpAsrBenchmarkTransport implements AsrBenchmarkTransport {
  HttpAsrBenchmarkTransport({
    required Uri baseUri,
    HttpClient Function()? clientFactory,
    this.requestTimeout = const Duration(seconds: 15),
    this.uploadTimeout = const Duration(minutes: 3),
    bool allowInsecureHttpForTesting = false,
  }) : _baseUri = _validateBaseUri(
         baseUri,
         allowInsecureHttpForTesting: allowInsecureHttpForTesting,
       ),
       _clientFactory = clientFactory ?? HttpClient.new;

  final Uri _baseUri;
  final HttpClient Function() _clientFactory;
  final Duration requestTimeout;
  final Duration uploadTimeout;

  @override
  Future<BenchmarkSubmission> submit(File audioFile) async {
    final client = _clientFactory();
    client.connectionTimeout = requestTimeout;
    try {
      final boundary =
          'aipin-benchmark-${DateTime.now().microsecondsSinceEpoch}';
      final request = await client
          .postUrl(_baseUri.resolve('/api/jobs'))
          .timeout(requestTimeout);
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
        filename: _filenameFor(audioFile),
        contentType: 'audio/mp4',
      );
      await request.addStream(audioFile.openRead()).timeout(uploadTimeout);
      request.add(utf8.encode('\r\n'));
      _writeFileHeader(
        request,
        boundary,
        field: 'reference_files',
        filename: 'reference.txt',
        contentType: 'text/plain; charset=utf-8',
      );
      request.add(utf8.encode('\r\n--$boundary--\r\n'));
      final response = await request.close().timeout(uploadTimeout);
      final value = await _decodeSuccessfulJson(response, uploadTimeout);
      final jobId = _nonBlank(value['job_id']) ?? _nonBlank(value['id']);
      if (jobId == null) {
        throw const BenchmarkTransportException(
          kind: BenchmarkFailureKind.invalidResponse,
          message: 'ASR 服务未返回任务标识。',
        );
      }
      return BenchmarkSubmission(jobId);
    } on BenchmarkTransportException {
      rethrow;
    } on FileSystemException {
      throw const BenchmarkTransportException(
        kind: BenchmarkFailureKind.network,
        message: '测试录音文件无法读取。',
      );
    } on SocketException {
      throw const BenchmarkTransportException(
        kind: BenchmarkFailureKind.network,
        message: '无法连接 ASR 服务。',
      );
    } on HttpException {
      throw const BenchmarkTransportException(
        kind: BenchmarkFailureKind.network,
        message: 'ASR 服务连接异常。',
      );
    } on TimeoutException {
      throw const BenchmarkTransportException(
        kind: BenchmarkFailureKind.network,
        message: 'ASR 上传请求超时。',
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<BenchmarkRemoteState> pollTranscription(String jobId) async {
    final value = await _sendJson(method: 'GET', path: '/api/jobs/$jobId');
    if (_nonBlank(value['error']) != null) {
      throw const BenchmarkTransportException(
        kind: BenchmarkFailureKind.transcription,
        message: 'ASR 转写任务失败。',
      );
    }
    switch (_normalizedStatus(value['status'])) {
      case 'queued':
      case 'running':
        return BenchmarkRemoteState.pending;
      case 'completed':
        return BenchmarkRemoteState.completed;
      default:
        throw const BenchmarkTransportException(
          kind: BenchmarkFailureKind.transcription,
          message: 'ASR 转写任务返回无效状态。',
        );
    }
  }

  @override
  Future<BenchmarkTranscriptSource> fetchTranscriptSource(String jobId) async {
    final value = await _sendJson(
      method: 'GET',
      path: '/api/jobs/$jobId/results',
    );
    final rows = value['flat_rows'];
    if (rows is! List) {
      throw const BenchmarkTransportException(
        kind: BenchmarkFailureKind.invalidResponse,
        message: 'ASR 服务未返回可读取的结果。',
      );
    }
    for (final item in rows) {
      final row = _asMap(item);
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
        return BenchmarkTranscriptSource(
          relativePath: relativePath,
          variant: variant,
          engine: engine,
        );
      }
    }
    throw const BenchmarkTransportException(
      kind: BenchmarkFailureKind.transcription,
      message: 'ASR 转写结果为空或格式无效。',
    );
  }

  @override
  Future<BenchmarkSummaryTask> createSummary({
    required String jobId,
    required BenchmarkTranscriptSource source,
  }) async {
    final value = await _sendJson(
      method: 'POST',
      path: '/api/meeting-notes',
      body: <String, Object?>{
        'job_id': jobId,
        'relative_path': source.relativePath,
        'variant': source.variant,
        'engine': source.engine,
      },
    );
    final note = _asMap(value['note']);
    final task = _asMap(value['generation_task']);
    final noteId = _nonBlank(note?['note_id']) ?? _nonBlank(note?['id']);
    final taskId = _nonBlank(task?['task_id']) ?? _nonBlank(task?['id']);
    if (noteId == null || taskId == null) {
      throw const BenchmarkTransportException(
        kind: BenchmarkFailureKind.invalidResponse,
        message: 'ASR 服务未返回总结任务标识。',
      );
    }
    return BenchmarkSummaryTask(noteId: noteId, taskId: taskId);
  }

  @override
  Future<BenchmarkRemoteState> pollSummary(BenchmarkSummaryTask task) async {
    final value = await _sendJson(
      method: 'GET',
      path: '/api/meeting-notes/${task.noteId}/generation-tasks/${task.taskId}',
    );
    final generationTask = _asMap(value['generation_task']) ?? value;
    if (_nonBlank(generationTask['error']) != null ||
        _nonBlank(generationTask['error_message']) != null ||
        _normalizedStatus(generationTask['status']) == 'failed') {
      throw const BenchmarkTransportException(
        kind: BenchmarkFailureKind.summary,
        message: 'ASR 总结任务失败。',
      );
    }
    if (generationTask['result'] != null) {
      return BenchmarkRemoteState.completed;
    }
    return BenchmarkRemoteState.pending;
  }

  Future<Map<String, Object?>> _sendJson({
    required String method,
    required String path,
    Map<String, Object?>? body,
  }) async {
    final client = _clientFactory();
    client.connectionTimeout = requestTimeout;
    try {
      final request = await client
          .openUrl(method, _baseUri.resolve(path))
          .timeout(requestTimeout);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(body)));
      }
      final response = await request.close().timeout(requestTimeout);
      return await _decodeSuccessfulJson(response, requestTimeout);
    } on BenchmarkTransportException {
      rethrow;
    } on SocketException {
      throw const BenchmarkTransportException(
        kind: BenchmarkFailureKind.network,
        message: '无法连接 ASR 服务。',
      );
    } on HttpException {
      throw const BenchmarkTransportException(
        kind: BenchmarkFailureKind.network,
        message: 'ASR 服务连接异常。',
      );
    } on TimeoutException {
      throw const BenchmarkTransportException(
        kind: BenchmarkFailureKind.network,
        message: 'ASR 服务请求超时。',
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, Object?>> _decodeSuccessfulJson(
    HttpClientResponse response,
    Duration timeout,
  ) async {
    final text = await utf8.decodeStream(response).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const BenchmarkTransportException(
        kind: BenchmarkFailureKind.remote,
        message: 'ASR 服务返回非成功状态。',
      );
    }
    try {
      final value = _asMap(jsonDecode(text));
      if (value == null) {
        throw const FormatException();
      }
      return value;
    } on FormatException {
      throw const BenchmarkTransportException(
        kind: BenchmarkFailureKind.invalidResponse,
        message: 'ASR 服务返回格式无效。',
      );
    }
  }

  static Uri _validateBaseUri(
    Uri baseUri, {
    required bool allowInsecureHttpForTesting,
  }) {
    final allowedHttp = allowInsecureHttpForTesting && baseUri.scheme == 'http';
    if ((baseUri.scheme != 'https' && !allowedHttp) || baseUri.host.isEmpty) {
      throw ArgumentError.value(baseUri, 'baseUri', '必须是有效的 HTTPS 地址。');
    }
    if (baseUri.path.endsWith('/')) {
      return baseUri;
    }
    return baseUri.replace(path: '${baseUri.path}/');
  }

  static Map<String, Object?>? _asMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static String? _nonBlank(Object? value) {
    if (value is! String) {
      return null;
    }
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static String? _normalizedStatus(Object? value) {
    final text = _nonBlank(value);
    return text?.toLowerCase();
  }

  static String _filenameFor(File file) {
    final name = file.uri.pathSegments.lastOrNull;
    if (name == null || name.isEmpty) {
      throw const BenchmarkTransportException(
        kind: BenchmarkFailureKind.invalidResponse,
        message: '测试录音文件名无效。',
      );
    }
    return name;
  }

  static void _writeField(
    HttpClientRequest request,
    String boundary,
    String name,
    String value,
  ) {
    request.add(
      utf8.encode(
        '--$boundary\r\nContent-Disposition: form-data; name="$name"\r\n\r\n$value\r\n',
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
