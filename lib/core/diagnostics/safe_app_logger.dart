import 'package:flutter/foundation.dart';

abstract interface class SafeAppLogger {
  void info(String event, {Map<String, Object?> fields = const {}});
}

class DebugSafeAppLogger implements SafeAppLogger {
  const DebugSafeAppLogger({this.scope = 'APP'});

  final String scope;

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {
    if (!kDebugMode) {
      return;
    }
    final details = fields.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    debugPrint(
      '[AIPIN][$scope] ${DateTime.now().toIso8601String()} $event'
      '${details.isEmpty ? '' : ' $details'}',
    );
  }
}
