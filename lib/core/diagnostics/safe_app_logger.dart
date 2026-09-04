import 'package:flutter/foundation.dart' hide DiagnosticLevel;

import 'diagnostic_event.dart';
import 'diagnostic_sanitizer.dart';
import 'diagnostic_trace.dart';

abstract interface class SafeAppLogger {
  void info(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  });

  void warning(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  });

  void error(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  });
}

class DebugSafeAppLogger implements SafeAppLogger {
  const DebugSafeAppLogger({this.scope = 'APP'});

  final String scope;

  @override
  void info(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) {
    _emit(
      DiagnosticLevel.info,
      event,
      trace: trace,
      operation: operation,
      stage: stage,
      result: result,
      elapsed: elapsed,
      fields: fields,
    );
  }

  @override
  void warning(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) {
    _emit(
      DiagnosticLevel.warning,
      event,
      trace: trace,
      operation: operation,
      stage: stage,
      result: result,
      elapsed: elapsed,
      fields: fields,
    );
  }

  @override
  void error(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) {
    _emit(
      DiagnosticLevel.error,
      event,
      trace: trace,
      operation: operation,
      stage: stage,
      result: result,
      elapsed: elapsed,
      fields: fields,
    );
  }

  void _emit(
    DiagnosticLevel level,
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    required Map<String, Object?> fields,
  }) {
    if (!kDebugMode) {
      return;
    }
    final diagnostic = DiagnosticEvent(
      timestamp: DateTime.now(),
      level: level,
      scope: scope,
      trace: trace,
      operation: operation,
      stage: stage,
      event: event,
      result: result,
      elapsed: elapsed,
      fields: const DiagnosticSanitizer().sanitize(
        scope: scope,
        fields: fields,
      ),
    );
    debugPrint(diagnostic.formatLine());
  }
}
