import 'dart:io';

class BenchmarkConfiguration {
  const BenchmarkConfiguration({
    required this.baseUri,
    required this.audioFile,
    required this.jobCount,
    required this.concurrency,
    required this.includeSummary,
    required this.reportFile,
    required this.jobTimeout,
  });

  final Uri baseUri;
  final File audioFile;
  final int jobCount;
  final int concurrency;
  final bool includeSummary;
  final File reportFile;
  final Duration jobTimeout;

  static BenchmarkConfiguration parse({
    required List<String> arguments,
    required Map<String, String> environment,
  }) {
    final parsedArguments = _BenchmarkArguments.parse(arguments);
    final baseUri = _parseBaseUri(environment['ASR_API_BASE_URL']);
    final audioFile = File(parsedArguments.requiredValue('--audio'));
    _validateAudioFile(audioFile);
    final jobCount = _parsePositiveInt(
      parsedArguments.requiredValue('--jobs'),
      option: '--jobs',
    );
    final concurrency = _parsePositiveInt(
      parsedArguments.requiredValue('--concurrency'),
      option: '--concurrency',
    );
    if (concurrency > jobCount) {
      throw const FormatException('--concurrency 不能大于 --jobs。');
    }
    final timeoutMinutes = _parsePositiveInt(
      parsedArguments.value('--job-timeout-minutes') ?? '45',
      option: '--job-timeout-minutes',
    );

    return BenchmarkConfiguration(
      baseUri: baseUri,
      audioFile: audioFile,
      jobCount: jobCount,
      concurrency: concurrency,
      includeSummary: parsedArguments.hasFlag('--summary'),
      reportFile: File(parsedArguments.requiredValue('--report')),
      jobTimeout: Duration(minutes: timeoutMinutes),
    );
  }

  static Uri _parseBaseUri(String? configuredValue) {
    final value = configuredValue?.trim() ?? '';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('ASR_API_BASE_URL 必须是有效的 HTTPS 地址。');
    }
    if (uri.path.endsWith('/')) {
      return uri;
    }
    return uri.replace(path: '${uri.path}/');
  }

  static void _validateAudioFile(File audioFile) {
    try {
      if (!audioFile.existsSync() || audioFile.lengthSync() <= 0) {
        throw const FormatException('录音文件不存在或为空。');
      }
    } on FileSystemException {
      throw const FormatException('录音文件无法读取。');
    }
  }

  static int _parsePositiveInt(String value, {required String option}) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) {
      throw FormatException('$option 必须是大于零的整数。');
    }
    return parsed;
  }
}

class _BenchmarkArguments {
  const _BenchmarkArguments._(this._values, this._flags);

  final Map<String, String> _values;
  final Set<String> _flags;

  static const _valueOptions = <String>{
    '--audio',
    '--jobs',
    '--concurrency',
    '--report',
    '--job-timeout-minutes',
  };
  static const _flagOptions = <String>{'--summary'};

  static _BenchmarkArguments parse(List<String> arguments) {
    final values = <String, String>{};
    final flags = <String>{};
    for (var index = 0; index < arguments.length; index += 1) {
      final option = arguments[index];
      if (_flagOptions.contains(option)) {
        flags.add(option);
        continue;
      }
      if (!_valueOptions.contains(option)) {
        throw FormatException('不支持的参数：$option。');
      }
      if (values.containsKey(option)) {
        throw FormatException('参数重复：$option。');
      }
      if (index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('--')) {
        throw FormatException('参数 $option 缺少值。');
      }
      values[option] = arguments[index + 1];
      index += 1;
    }
    return _BenchmarkArguments._(values, flags);
  }

  bool hasFlag(String option) => _flags.contains(option);

  String requiredValue(String option) {
    final value = _values[option];
    if (value == null || value.trim().isEmpty) {
      throw FormatException('参数 $option 必填。');
    }
    return value;
  }

  String? value(String option) => _values[option];
}
