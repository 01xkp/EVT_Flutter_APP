import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' hide DiagnosticLevel;
import 'package:path_provider/path_provider.dart';

import 'package:aipin/core/diagnostics/diagnostic_event.dart';
import '../domain/app_log_entry.dart';
import '../domain/app_log_store.dart';
import '../domain/public_diagnostic_log_sink.dart';

class FileAppLogStore extends ChangeNotifier implements AppLogStore {
  static const _mirrorFailureLogInterval = Duration(minutes: 5);
  static const _defaultWriteDebounce = Duration(milliseconds: 200);
  static const _defaultMirrorDebounce = Duration(seconds: 10);
  static const _defaultMaxFileBytes = 20 * 1024 * 1024;
  static const _defaultKeepFiles = 8;
  static final _logFilenamePattern = RegExp(
    r'^aipin-\d{4}-\d{2}-\d{2}\.log(?:\.\d+)?$',
  );

  FileAppLogStore({
    this._supportDirectoryProvider,
    DateTime Function()? clock,
    this.maxEntries = 500,
    this.maxFileBytes = _defaultMaxFileBytes,
    this.keepFiles = _defaultKeepFiles,
    bool? enabled,
    bool Function()? isDebugBuild,
    PublicDiagnosticLogSink? publicDiagnosticLogSink,
    Duration mirrorDebounce = _defaultMirrorDebounce,
    Duration writeDebounce = _defaultWriteDebounce,
  }) : _clock = clock ?? DateTime.now,
       _enabled = (enabled ?? true) && (isDebugBuild ?? _isDebugBuild)(),
       // These public parameter names are part of the construction API.
       // ignore: prefer_initializing_formals
       _publicDiagnosticLogSink = publicDiagnosticLogSink,
       // ignore: prefer_initializing_formals
       _mirrorDebounce = mirrorDebounce,
       // ignore: prefer_initializing_formals
       _writeDebounce = writeDebounce;

  final Future<Directory> Function()? _supportDirectoryProvider;
  final DateTime Function() _clock;
  final bool _enabled;
  final int maxEntries;
  final int maxFileBytes;
  final int keepFiles;
  final PublicDiagnosticLogSink? _publicDiagnosticLogSink;
  final Duration _mirrorDebounce;
  final Duration _writeDebounce;
  final List<AppLogEntry> _entries = <AppLogEntry>[];
  final StreamController<AppLogEntry> _stream =
      StreamController<AppLogEntry>.broadcast();
  Future<void> _writeQueue = Future<void>.value();
  Future<void> _mirrorQueue = Future<void>.value();
  final StringBuffer _pendingLines = StringBuffer();
  Directory? _logDirectory;
  File? _currentFile;
  DateTime? _lastMirrorAttemptAt;
  DateTime? _lastMirrorFailureLoggedAt;
  String? _lastMirrorFailureCode;
  PublicDiagnosticLogMirrorStatus? _publicMirrorStatus;
  Timer? _writeTimer;
  Timer? _mirrorTimer;
  var _mirrorPending = false;
  var _disposed = false;
  var _closedStream = false;
  Future<void>? _closeFuture;

  static bool _isDebugBuild() => kDebugMode;

  @override
  List<AppLogEntry> get entries => List.unmodifiable(_entries);

  @override
  Stream<AppLogEntry> get stream => _stream.stream;

  @override
  String? get currentFilePath => _currentFile?.path;

  @override
  bool get isPersistent => _enabled && _currentFile != null;

  @override
  PublicDiagnosticLogMirrorStatus? get publicMirrorStatus =>
      _publicMirrorStatus;

  @override
  Future<void> initialize() async {
    await _initialize(allowAfterDispose: false);
  }

  Future<void> _initialize({required bool allowAfterDispose}) async {
    if (!_enabled ||
        (!allowAfterDispose && _disposed) ||
        _currentFile != null) {
      return;
    }
    final supportDirectory =
        await (_supportDirectoryProvider?.call() ??
            getApplicationSupportDirectory());
    _logDirectory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}logs',
    );
    await _logDirectory!.create(recursive: true);
    await _selectCurrentFile();
    await _pruneFiles();
  }

  @override
  void info(
    String event, {
    String scope = 'APP',
    Map<String, Object?> fields = const {},
  }) {
    record(
      AppLogEntry(
        timestamp: _clock(),
        level: DiagnosticLevel.info,
        scope: scope,
        event: event,
        fields: fields,
      ),
    );
  }

  @override
  void record(AppLogEntry entry) {
    if (!_enabled || _disposed || _closedStream) {
      return;
    }
    final sanitizedEntry = AppLogEntry.fromEvent(
      DiagnosticEvent(
        timestamp: entry.timestamp,
        level: entry.level,
        scope: entry.scope,
        trace: entry.trace,
        operation: entry.operation,
        stage: entry.stage,
        event: entry.event,
        result: entry.result,
        elapsed: entry.elapsed,
        fields: entry.fields,
      ),
    );
    if (_entries.length >= maxEntries) {
      _entries.removeAt(0);
    }
    _entries.add(sanitizedEntry);
    _stream.add(sanitizedEntry);
    notifyListeners();
    _pendingLines.write('${sanitizedEntry.formatLine()}\n');
    _scheduleWrite();
  }

  @override
  Future<void> flush() async {
    _cancelScheduledWork();
    _enqueuePendingWrite();
    await _writeQueue;
    _mirrorQueue = _mirrorQueue.then((_) => _mirrorPendingFile(force: true));
    await _mirrorQueue;
    await _writeQueue;
  }

  @override
  Future<String?> exportPath() async {
    await initialize();
    await flush();
    return currentFilePath;
  }

  @override
  void clearView() {
    _entries.clear();
    notifyListeners();
  }

  /// BLE file import can deliver thousands of Debug entries in a short time.
  /// Coalescing them keeps diagnostic disk I/O from competing with the GATT
  /// callback while [flush], export, and disposal still persist every accepted
  /// line before they complete.
  void _scheduleWrite() {
    if (_writeTimer != null) {
      return;
    }
    _writeTimer = Timer(_writeDebounce, () {
      _writeTimer = null;
      _enqueuePendingWrite();
    });
  }

  void _cancelScheduledWork() {
    _writeTimer?.cancel();
    _writeTimer = null;
    _mirrorTimer?.cancel();
    _mirrorTimer = null;
  }

  void _enqueuePendingWrite() {
    if (_pendingLines.isEmpty) {
      return;
    }
    final lines = _pendingLines.toString();
    _pendingLines.clear();
    _writeQueue = _writeQueue.then((_) async {
      try {
        // Disposal stops new entries but must not discard entries that were
        // already accepted into the serialized write queue.
        await _initialize(allowAfterDispose: true);
        await _append(lines);
        _scheduleMirror();
      } on Object {
        // Diagnostics must never break the feature that emitted the log.
      }
    });
  }

  Future<void> _append(String line) async {
    await _selectCurrentFileForToday();
    final file = _currentFile;
    if (file == null) {
      return;
    }
    final bytes = utf8.encode(line);
    final length = await file.length();
    if (length + bytes.length > maxFileBytes) {
      final rotated = await _rotateCurrentFile(file);
      if (rotated != null) {
        await _mirrorRotatedFile(rotated);
      }
      await _pruneFiles();
    }
    await _currentFile!.writeAsBytes(bytes, mode: FileMode.append, flush: true);
  }

  Future<File?> _rotateCurrentFile(File file) async {
    if (keepFiles <= 1) {
      await file.delete();
      _currentFile = File(file.path);
      await _currentFile!.create();
      return null;
    }

    final oldest = File('${file.path}.${keepFiles - 1}');
    if (await oldest.exists()) {
      await oldest.delete();
    }
    for (var index = keepFiles - 2; index >= 1; index -= 1) {
      final source = File('${file.path}.$index');
      if (await source.exists()) {
        await source.rename('${file.path}.${index + 1}');
      }
    }
    final rotated = File('${file.path}.1');
    await file.rename(rotated.path);
    _currentFile = File(file.path);
    await _currentFile!.create();
    return rotated;
  }

  Future<void> _mirrorRotatedFile(File file) async {
    final sink = _publicDiagnosticLogSink;
    if (!_enabled || sink == null || !await file.exists()) {
      return;
    }
    try {
      _publicMirrorStatus = await sink.mirrorCanonicalFile(
        sourcePath: file.path,
        filename: file.uri.pathSegments.last,
      );
    } on Object {
      _publicMirrorStatus = PublicDiagnosticLogMirrorStatus.failure(
        'storage_error',
      );
    }
  }

  void _scheduleMirror() {
    if (_publicDiagnosticLogSink == null) {
      return;
    }
    _mirrorPending = true;
    if (_mirrorTimer != null) {
      return;
    }
    _mirrorTimer = Timer(_mirrorDebounce, () {
      _mirrorTimer = null;
      _mirrorQueue = _mirrorQueue.then((_) => _mirrorPendingFile());
    });
  }

  Future<void> _mirrorPendingFile({bool force = false}) async {
    if (!_mirrorPending) {
      return;
    }
    _mirrorPending = false;
    final sink = _publicDiagnosticLogSink;
    final file = _currentFile;
    if (!_enabled || sink == null || file == null) {
      return;
    }
    final now = _clock();
    final previousAttempt = _lastMirrorAttemptAt;
    if (!force &&
        previousAttempt != null &&
        now.difference(previousAttempt) < _mirrorDebounce) {
      _mirrorPending = true;
      _scheduleMirror();
      return;
    }
    _lastMirrorAttemptAt = now;
    final previousFailureCode = _lastMirrorFailureCode;
    try {
      _publicMirrorStatus = await sink.mirrorCanonicalFile(
        sourcePath: file.path,
        filename: file.uri.pathSegments.last,
      );
    } on Object {
      _publicMirrorStatus = PublicDiagnosticLogMirrorStatus.failure(
        'storage_error',
      );
    }
    if (_publicMirrorStatus?.failureCode != null) {
      await _recordMirrorFailure(_publicMirrorStatus!.failureCode!);
    } else if (previousFailureCode != null) {
      await _recordMirrorRecovered(previousFailureCode);
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _recordMirrorFailure(String failureCode) async {
    final now = _clock();
    if (_lastMirrorFailureCode == failureCode &&
        _lastMirrorFailureLoggedAt != null &&
        now.difference(_lastMirrorFailureLoggedAt!) <
            _mirrorFailureLogInterval) {
      return;
    }
    _lastMirrorFailureCode = failureCode;
    _lastMirrorFailureLoggedAt = now;
    await _recordMirrorStatus('public_mirror_failed', failureCode);
  }

  Future<void> _recordMirrorRecovered(String previousFailureCode) async {
    _lastMirrorFailureCode = null;
    _lastMirrorFailureLoggedAt = null;
    await _recordMirrorStatus('public_mirror_recovered', previousFailureCode);
  }

  Future<void> _recordMirrorStatus(String event, String failureCode) async {
    if (_entries.length >= maxEntries) {
      _entries.removeAt(0);
    }
    final entry = AppLogEntry.fromEvent(
      DiagnosticEvent(
        timestamp: _clock(),
        level: event == 'public_mirror_recovered'
            ? DiagnosticLevel.info
            : DiagnosticLevel.warning,
        scope: 'STORAGE',
        event: event,
        fields: {'error_code': failureCode},
      ),
    );
    _entries.add(entry);
    _stream.add(entry);
    final line = '${entry.formatLine()}\n';
    _writeQueue = _writeQueue.then((_) async {
      try {
        await _append(line);
      } on Object {
        // A mirror diagnostic must not make its own storage failure visible.
      }
    });
    await _writeQueue;
  }

  Future<void> _selectCurrentFile() async {
    final filename = _dailyLogFilename(_clock());
    _currentFile = File(
      '${_logDirectory!.path}${Platform.pathSeparator}$filename',
    );
    if (!await _currentFile!.exists()) {
      await _currentFile!.create();
    }
  }

  Future<void> _selectCurrentFileForToday() async {
    final expectedFilename = _dailyLogFilename(_clock());
    final current = _currentFile;
    if (current != null && current.uri.pathSegments.last == expectedFilename) {
      return;
    }
    await _selectCurrentFile();
    await _pruneFiles();
  }

  static String _dailyLogFilename(DateTime value) {
    final date =
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    return 'aipin-$date.log';
  }

  Future<void> _pruneFiles() async {
    final directory = _logDirectory;
    if (directory == null) {
      return;
    }
    final files = <File>[];
    await for (final entry in directory.list()) {
      if (entry is File &&
          _logFilenamePattern.hasMatch(entry.uri.pathSegments.last)) {
        files.add(entry);
      }
    }
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    for (final file in files.skip(keepFiles)) {
      await file.delete();
    }
  }

  @override
  Future<void> close() {
    // [dispose] cannot await this work. Stop timers synchronously so a page
    // teardown cannot leave delayed callbacks alive after its owner is gone.
    _cancelScheduledWork();
    return _closeFuture ??= _close();
  }

  Future<void> _close() async {
    if (_closedStream) {
      return;
    }
    _closedStream = true;
    await flush();
    _cancelScheduledWork();
    // A paused external listener makes StreamController.close() wait until
    // that listener resumes. Closing this owner must not keep diagnostics or
    // widget teardown alive indefinitely after file writes have been drained.
    unawaited(_stream.close());
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}
