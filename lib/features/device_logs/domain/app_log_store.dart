import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_log_entry.dart';

abstract interface class AppLogStore implements Listenable {
  List<AppLogEntry> get entries;
  Stream<AppLogEntry> get stream;
  String? get currentFilePath;
  bool get isPersistent;
  void info(String event, {String scope = 'APP', Map<String, Object?> fields = const {}});
  Future<void> initialize();
  Future<void> flush();
  Future<String?> exportPath();
  void clearView();
  Future<void> close();
  void dispose();
}
