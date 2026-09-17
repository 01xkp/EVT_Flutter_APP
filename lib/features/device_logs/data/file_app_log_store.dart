import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' hide DiagnosticLevel;
import 'package:path_provider/path_provider.dart';

import 'package:aipin/core/diagnostics/diagnostic_event.dart';
import '../domain/app_log_entry.dart';
import '../domain/app_log_store.dart';
import '../domain/app_log_upload_port.dart';
import '../domain/public_diagnostic_log_sink.dart';

class FileAppLogStore extends ChangeNotifier
    implements AppLogStore, AppLogUploadSnapshotValidator {
  static const _mirrorFailureLogInterval = Duration(minutes: 5);
  static const _defaultWriteDebounce = Duration(milliseconds: 200);
  static const _defaultMirrorDebounce = Duration(seconds: 10);
  static const _defaultMaxFileBytes = 20 * 1024 * 1024;
  static const _defaultKeepFiles = 8;
  static final _logFilenamePattern = RegExp(
    r'^aipin-\d{4}-\d{2}-\d{2}\.log(?:\.\d+)?$',
  );
  static final _mirrorSnapshotFilenamePattern = RegExp(
    r'^aipin-\d{4}-\d{2}-\d{2}\.log(?:\.\d+)?\.mirror-\d+-\d+$',
  );
  static final _exportFilenamePattern = RegExp(
    r'^aipin-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}(?:-\d+)?\.log$',
  );
  static final _rawPacketHexFieldPattern = RegExp(
    r'raw_packet_hex=(?:empty|[0-9A-F]{2}(?: [0-9A-F]{2})*)',
    caseSensitive: false,
  );
  static final _rawPacketHexJsonFieldPattern = RegExp(
    r'"raw_packet_hex":"(?:empty|[0-9A-F]{2}(?: [0-9A-F]{2})*)"',
    caseSensitive: false,
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
  Future<void> _exportQueue = Future<void>.value();
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
  var _mirrorSnapshotSequence = 0;
  var _isClosing = false;
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
    await _pruneMirrorSnapshots();
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
    if (!_enabled || _isClosing || _disposed || _closedStream) {
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
    // A lifecycle or security-operation flush must only wait for the
    // canonical app-private file. A public Download mirror can require user
    // permission on Android 6-9 and must never delay or interrupt BLE work.
    _cancelScheduledWrite();
    await _drainPendingWrites();
  }

  @override
  Future<String?> exportPath() {
    final export = _exportQueue.then((_) => _exportSnapshot());
    _exportQueue = export.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return export;
  }

  @override
  Future<String?> createUploadSnapshot() {
    final snapshot = _exportQueue.then((_) => _uploadSnapshot());
    _exportQueue = snapshot.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return snapshot;
  }

  @override
  Future<bool> isTrustedSnapshot(String snapshotPath) async {
    await initialize();
    final logDirectory = _logDirectory;
    if (logDirectory == null) {
      return false;
    }
    final snapshot = File(snapshotPath);
    if (!_exportFilenamePattern.hasMatch(snapshot.uri.pathSegments.last)) {
      return false;
    }
    final uploadDirectory = Directory(
      '${logDirectory.path}${Platform.pathSeparator}uploads',
    );
    try {
      final resolvedUploadDirectory = await uploadDirectory
          .resolveSymbolicLinks();
      final resolvedSnapshot = await snapshot.resolveSymbolicLinks();
      return File(resolvedSnapshot).parent.path == resolvedUploadDirectory;
    } on FileSystemException {
      return false;
    }
  }

  Future<String?> _exportSnapshot() async {
    await initialize();
    await flush();
    if (_currentFile == null) {
      return null;
    }
    // Serialize the copy with appends and rotation so each export is immutable.
    final copy = _writeQueue.then((_) => _createExportSnapshot());
    _writeQueue = copy.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    final snapshot = await copy;
    await _flushPublicMirror(requestPermission: true, exportFile: snapshot);
    // Keep any storage diagnostic in the canonical log for the next export.
    await flush();
    return snapshot.path;
  }

  Future<String?> _uploadSnapshot() async {
    await initialize();
    await flush();
    if (_currentFile == null) {
      return null;
    }
    // Use the same write queue as exports so the uploaded file cannot include
    // a partial append or rotation. This path intentionally avoids MediaStore.
    final snapshot = _writeQueue.then((_) => _createUploadSnapshot());
    _writeQueue = snapshot.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return (await snapshot).path;
  }

  Future<File> _createExportSnapshot() async {
    final now = _clock();
    final date = _dailyLogFilename(now).replaceFirst('.log', '');
    final time = [
      now.hour,
      now.minute,
      now.second,
    ].map((part) => part.toString().padLeft(2, '0')).join('-');
    final stem = '$date-$time';
    final directory = Directory(
      '${_logDirectory!.path}${Platform.pathSeparator}exports',
    );
    await directory.create(recursive: true);
    final files = await directory
        .list()
        .where(
          (entry) =>
              entry is File &&
              _exportFilenamePattern.hasMatch(entry.uri.pathSegments.last),
        )
        .cast<File>()
        .toList();
    final sameSecond = RegExp('^${RegExp.escape(stem)}(?:-([0-9]+))?\\.log\$');
    var sequence = 0;
    for (final file in files) {
      final match = sameSecond.firstMatch(file.uri.pathSegments.last);
      if (match != null) {
        final next = (int.tryParse(match.group(1) ?? '0') ?? 0) + 1;
        if (next > sequence) sequence = next;
      }
    }
    final suffix = sequence == 0
        ? ''
        : '-${sequence.toString().padLeft(2, '0')}';
    final snapshot = File(
      '${directory.path}${Platform.pathSeparator}$stem$suffix.log',
    );
    await _writeRedactedSnapshot(_currentFile!, snapshot);
    // Export copies have their own retention budget, independent of daily logs.
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    for (final file in files.skip(keepFiles > 0 ? keepFiles - 1 : 0)) {
      try {
        await file.delete();
      } on FileSystemException {
        // A locked old export must not prevent delivering the new snapshot.
      }
    }
    return snapshot;
  }

  Future<File> _createUploadSnapshot() async {
    final now = _clock();
    final date = _dailyLogFilename(now).replaceFirst('.log', '');
    final time = [
      now.hour,
      now.minute,
      now.second,
    ].map((part) => part.toString().padLeft(2, '0')).join('-');
    final stem = '$date-$time';
    final directory = Directory(
      '${_logDirectory!.path}${Platform.pathSeparator}uploads',
    );
    await directory.create(recursive: true);
    final files = await directory
        .list()
        .where(
          (entry) =>
              entry is File &&
              _exportFilenamePattern.hasMatch(entry.uri.pathSegments.last),
        )
        .cast<File>()
        .toList();
    final sameSecond = RegExp('^${RegExp.escape(stem)}(?:-([0-9]+))?\\.log\$');
    var sequence = 0;
    for (final file in files) {
      final match = sameSecond.firstMatch(file.uri.pathSegments.last);
      if (match != null) {
        final next = (int.tryParse(match.group(1) ?? '0') ?? 0) + 1;
        if (next > sequence) sequence = next;
      }
    }
    final suffix = sequence == 0
        ? ''
        : '-${sequence.toString().padLeft(2, '0')}';
    final snapshot = File(
      '${directory.path}${Platform.pathSeparator}$stem$suffix.log',
    );
    await _writeRedactedSnapshot(_currentFile!, snapshot);
    // Upload copies have their own retention budget and never enter MediaStore.
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    for (final file in files.skip(keepFiles > 0 ? keepFiles - 1 : 0)) {
      try {
        await file.delete();
      } on FileSystemException {
        // A locked old snapshot must not prevent the current upload attempt.
      }
    }
    return snapshot;
  }

  /// Outside the app-private Debug log, raw BLE bytes must never travel to
  /// public storage, user exports, or the upload transport.
  Future<void> _writeRedactedSnapshot(File source, File destination) async {
    var completed = false;
    final output = destination.openWrite(encoding: utf8);
    try {
      await for (final line
          in source
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        output.writeln(_sanitizeExternalLine(line));
      }
      await output.flush();
      completed = true;
    } finally {
      await output.close();
      if (!completed && await destination.exists()) {
        try {
          await destination.delete();
        } on Object {
          // A failed cleanup does not expose the source file publicly.
        }
      }
    }
  }

  String _sanitizeExternalLine(String line) {
    return line
        .replaceAll(_rawPacketHexFieldPattern, 'raw_packet_hex=omitted')
        .replaceAll(
          _rawPacketHexJsonFieldPattern,
          '"raw_packet_hex":"omitted"',
        );
  }

  /// Mirrors redacted Debug diagnostics without opening a storage permission
  /// dialog. The app-private canonical file remains the only raw-packet log.
  Future<void> syncPublicMirror() async {
    await flush();
    await _flushPublicMirror(requestPermission: false);
    await flush();
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
    if (_isClosing || _disposed || _closedStream || _writeTimer != null) {
      return;
    }
    _writeTimer = Timer(_writeDebounce, () {
      _writeTimer = null;
      _enqueuePendingWrite();
    });
  }

  Future<void> _drainPendingWrites() async {
    // A write completion can synchronously trigger a closely-following log
    // event (for example, the background reconnect pause). Give that event
    // one additional event-loop turn and drain it too, without turning a
    // continuous diagnostic stream into an unbounded flush.
    for (var pass = 0; pass < 2; pass += 1) {
      _enqueuePendingWrite();
      final queuedWrite = _writeQueue;
      await queuedWrite;
      await Future<void>.microtask(() {});
      if (_pendingLines.isEmpty && identical(queuedWrite, _writeQueue)) {
        return;
      }
      _cancelScheduledWrite();
    }
    _enqueuePendingWrite();
    await _writeQueue;
  }

  void _cancelScheduledWrite() {
    _writeTimer?.cancel();
    _writeTimer = null;
  }

  void _cancelScheduledWork() {
    _cancelScheduledWrite();
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
        await _queueRotatedFileMirror(
          rotated,
          filename: rotated.uri.pathSegments.last,
        );
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
        final target = File('${file.path}.${index + 1}');
        await _queueRotatedFileMirror(
          source,
          filename: target.uri.pathSegments.last,
        );
        await source.rename(target.path);
      }
    }
    final rotated = File('${file.path}.1');
    await file.rename(rotated.path);
    _currentFile = File(file.path);
    await _currentFile!.create();
    return rotated;
  }

  Future<void> _queueRotatedFileMirror(
    File file, {
    required String filename,
  }) async {
    final sink = _publicDiagnosticLogSink;
    if (!_enabled || sink == null || !await file.exists()) {
      return;
    }
    final snapshot = await _createMirrorSnapshot(file);
    if (snapshot == null) {
      return;
    }
    _mirrorQueue = _mirrorQueue.then((_) async {
      try {
        await _mirrorRotatedFile(
          snapshot,
          filename: filename,
          requestPermission: false,
        );
      } finally {
        try {
          await snapshot.delete();
        } on Object {
          // A stale mirror snapshot is removed on the next App start.
        }
      }
    });
  }

  Future<File?> _createMirrorSnapshot(File file) async {
    final snapshot = File(
      '${file.path}.mirror-${_clock().microsecondsSinceEpoch}-${_mirrorSnapshotSequence++}',
    );
    try {
      await _writeRedactedSnapshot(file, snapshot);
      return snapshot;
    } on Object {
      return null;
    }
  }

  Future<void> _mirrorRotatedFile(
    File file, {
    required String filename,
    required bool requestPermission,
  }) async {
    final sink = _publicDiagnosticLogSink;
    if (!_enabled || sink == null || !await file.exists()) {
      return;
    }
    try {
      _publicMirrorStatus = await _mirrorWithTimeout(
        sink,
        sourcePath: file.path,
        filename: filename,
        requestPermission: requestPermission,
      );
    } on Object {
      _publicMirrorStatus = PublicDiagnosticLogMirrorStatus.failure(
        'storage_error',
      );
    }
  }

  void _scheduleMirror() {
    if (_isClosing ||
        _disposed ||
        _closedStream ||
        _publicDiagnosticLogSink == null) {
      return;
    }
    _mirrorPending = true;
    if (_mirrorTimer != null) {
      return;
    }
    _mirrorTimer = Timer(_mirrorDebounce, () {
      _mirrorTimer = null;
      _queuePendingMirror(force: false, requestPermission: false);
    });
  }

  void _queuePendingMirror({
    required bool force,
    required bool requestPermission,
    File? exportFile,
  }) {
    _mirrorQueue = _mirrorQueue.then(
      (_) => _mirrorPendingFile(
        force: force,
        requestPermission: requestPermission,
        exportFile: exportFile,
      ),
    );
  }

  Future<void> _flushPublicMirror({
    required bool requestPermission,
    File? exportFile,
  }) async {
    _mirrorTimer?.cancel();
    _mirrorTimer = null;
    _queuePendingMirror(
      force: true,
      requestPermission: requestPermission,
      exportFile: exportFile,
    );
    await _mirrorQueue;
  }

  Future<void> _mirrorPendingFile({
    required bool force,
    required bool requestPermission,
    File? exportFile,
  }) async {
    if (!_mirrorPending && !force) {
      return;
    }
    _mirrorPending = false;
    final sink = _publicDiagnosticLogSink;
    final file = exportFile ?? _currentFile;
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
    final snapshot = await _createMirrorSnapshot(file);
    if (snapshot == null) {
      _publicMirrorStatus = PublicDiagnosticLogMirrorStatus.failure(
        'storage_error',
      );
    } else {
      try {
        _publicMirrorStatus = await _mirrorWithTimeout(
          sink,
          sourcePath: snapshot.path,
          filename: file.uri.pathSegments.last,
          requestPermission: requestPermission,
        );
      } on Object {
        _publicMirrorStatus = PublicDiagnosticLogMirrorStatus.failure(
          'storage_error',
        );
      } finally {
        try {
          await snapshot.delete();
        } on Object {
          // Stale redacted snapshots are cleaned on the next app start.
        }
      }
    }
    if (_closedStream) {
      return;
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

  Future<PublicDiagnosticLogMirrorStatus> _mirrorWithTimeout(
    PublicDiagnosticLogSink sink, {
    required String sourcePath,
    required String filename,
    required bool requestPermission,
  }) => sink
      .mirrorCanonicalFile(
        sourcePath: sourcePath,
        filename: filename,
        requestPermission: requestPermission,
      )
      .timeout(
        const Duration(seconds: 5),
        onTimeout: () => PublicDiagnosticLogMirrorStatus.failure('timeout'),
      );

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
    if (_closedStream) {
      return;
    }
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

  Future<void> _pruneMirrorSnapshots() async {
    final directory = _logDirectory;
    if (directory == null) {
      return;
    }
    await for (final entry in directory.list()) {
      if (entry is File &&
          _mirrorSnapshotFilenamePattern.hasMatch(
            entry.uri.pathSegments.last,
          )) {
        try {
          await entry.delete();
        } on Object {
          // A failed cleanup does not affect the canonical diagnostic log.
        }
      }
    }
  }

  @override
  Future<void> close() {
    // [dispose] cannot await this work. Stop timers synchronously so a page
    // teardown cannot leave delayed callbacks alive after its owner is gone.
    _isClosing = true;
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
