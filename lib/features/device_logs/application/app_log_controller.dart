import 'dart:async';

import '../data/file_app_log_store.dart';

class AppLogController {
  AppLogController(this.store);

  final FileAppLogStore store;

  Future<void> initialize() => store.initialize();

  Future<String?> export() => store.exportPath();

  void clearView() => store.clearView();

  Future<void> dispose() async {
    await store.close();
    store.dispose();
  }
}
