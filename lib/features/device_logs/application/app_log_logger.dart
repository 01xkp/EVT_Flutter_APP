import 'package:flutter/foundation.dart' hide DiagnosticLevel;

import 'package:aipin/core/diagnostics/diagnostic_event.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/core/diagnostics/diagnostic_trace.dart';
import 'package:aipin/features/device_logs/domain/app_log_entry.dart';
import 'package:aipin/features/device_logs/domain/app_log_store.dart';

/// Bridges the app-wide diagnostic contract to the persistent debug log.
class PersistentAppLogger implements SafeAppLogger {
  const PersistentAppLogger(this._store, {this.scope = 'APP'});

  final AppLogStore _store;
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
    _record(
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
    _record(
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
    _record(
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

  void _record(
    DiagnosticLevel level,
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    required Map<String, Object?> fields,
  }) {
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
      fields: fields,
    );
    // Debug output and the persistent file intentionally share one sanitized
    // line so an engineer can correlate Logcat/Xcode with the exported file.
    if (kDebugMode) {
      debugPrint(diagnostic.formatLine());
    }
    _store.record(AppLogEntry.fromEvent(diagnostic));
  }
}
