import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' hide DiagnosticLevel;
import 'package:path_provider/path_provider.dart';

import 'package:aipin/core/diagnostics/diagnostic_event.dart';
import '../domain/app_log_entry.dart';
import '../domain/app_log_store.dart';

class FileAppLogStore extends ChangeNotifier implements AppLogStore {
  FileAppLogStore({
    Future<Directory> Function()? supportDirectoryProvider,
    DateTime Function()? clock,
    this.maxEntries = 500,
    this.maxFileBytes = 5 * 1024 * 1024,
    this.keepFiles = 7,
    bool? enabled,
  }) : _supportDirectoryProvider = supportDirectoryProvider,
       _clock = clock ?? DateTime.now,
       _enabled = enabled ?? kDebugMode;

  final Future<Directory> Function()? _supportDirectoryProvider;
  final DateTime Function() _clock;
  final bool _enabled;
  final int maxEntries;
  final int maxFileBytes;
  final int keepFiles;
  final List<AppLogEntry> _entries = <AppLogEntry>[];
  final StreamController<AppLogEntry> _stream =
      StreamController<AppLogEntry>.broadcast();
  Future<void> _writeQueue = Future<void>.value();
  Directory? _logDirectory;
  File? _currentFile;
  var _disposed = false;
  var _closedStream = false;

  @override
  List<AppLogEntry> get entries => List.unmodifiable(_entries);

  @override
  Stream<AppLogEntry> get stream => _stream.stream;

  @override
  String? get currentFilePath => _currentFile?.path;

  @override
  bool get isPersistent => _enabled && _currentFile != null;

  @override
  Future<void> initialize() async {
    if (!_enabled || _disposed || _currentFile != null) {
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
    if (!_enabled || _disposed) {
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
    final line = '${sanitizedEntry.formatLine()}\n';
    _writeQueue = _writeQueue.then((_) async {
      try {
        await initialize();
        await _append(line);
      } on Object {
        // Diagnostics must never break the feature that emitted the log.
      }
    });
  }

  @override
  Future<void> flush() => _writeQueue;

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

  Future<void> _append(String line) async {
    final file = _currentFile;
    if (file == null) {
      return;
    }
    final bytes = utf8.encode(line);
    final length = await file.length();
    if (length + bytes.length > maxFileBytes) {
      final rotated = File('${file.path}.1');
      if (await rotated.exists()) {
        await rotated.delete();
      }
      await file.rename(rotated.path);
      _currentFile = File(file.path);
      await _currentFile!.create();
      await _pruneFiles();
    }
    await _currentFile!.writeAsBytes(bytes, mode: FileMode.append, flush: true);
  }

  Future<void> _selectCurrentFile() async {
    final now = _clock();
    final date =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    _currentFile = File(
      '${_logDirectory!.path}${Platform.pathSeparator}aipin-$date.log',
    );
    if (!await _currentFile!.exists()) {
      await _currentFile!.create();
    }
  }

  Future<void> _pruneFiles() async {
    final directory = _logDirectory;
    if (directory == null) {
      return;
    }
    final files = (await directory.list().where((entry) {
      return entry is File &&
          (entry.path.contains('aipin-') || entry.path.contains('.1'));
    }).toList())..sort((a, b) => b.path.compareTo(a.path));
    for (final file in files.skip(keepFiles)) {
      await file.delete();
    }
  }

  @override
  Future<void> close() async {
    if (_closedStream) {
      return;
    }
    _closedStream = true;
    await flush();
    await _stream.close();
  }

  @override
  void dispose() {
    if (_disposed) {
      super.dispose();
      return;
    }
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}
