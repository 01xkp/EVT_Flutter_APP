import 'package:flutter/foundation.dart';

abstract interface class SafeAppLogger {
  void info(String event, {Map<String, Object?> fields = const {}});
}

class DebugSafeAppLogger implements SafeAppLogger {
  const DebugSafeAppLogger();

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {
    if (!kDebugMode) {
      return;
    }
    final details = fields.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    debugPrint('[AIPIN][AI] $event${details.isEmpty ? '' : ' $details'}');
  }
}
