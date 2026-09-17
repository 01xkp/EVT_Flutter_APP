import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_log_entry.dart';
import 'public_diagnostic_log_sink.dart';

abstract interface class AppLogStore implements Listenable {
  List<AppLogEntry> get entries;
  Stream<AppLogEntry> get stream;
  String? get currentFilePath;
  bool get isPersistent;
  PublicDiagnosticLogMirrorStatus? get publicMirrorStatus;
  void record(AppLogEntry entry);
  void info(
    String event, {
    String scope = 'APP',
    Map<String, Object?> fields = const {},
  });
  Future<void> initialize();
  Future<void> flush();

  /// Creates a private, immutable and transport-safe diagnostic snapshot.
  ///
  /// Unlike [exportPath], this does not mirror anything to public storage or
  /// request legacy storage permission.
  Future<String?> createUploadSnapshot();
  Future<String?> exportPath();
  void clearView();
  Future<void> close();
  void dispose();
}
