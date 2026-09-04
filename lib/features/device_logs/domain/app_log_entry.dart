import 'package:aipin/core/diagnostics/diagnostic_event.dart';
import 'package:aipin/core/diagnostics/diagnostic_trace.dart';

class AppLogEntry {
  AppLogEntry({
    required this.timestamp,
    required this.scope,
    required this.event,
    this.level = DiagnosticLevel.info,
    this.trace,
    this.operation,
    this.stage,
    this.result,
    this.elapsed,
    this.fields = const {},
  });

  factory AppLogEntry.fromEvent(DiagnosticEvent event) {
    return AppLogEntry(
      timestamp: event.timestamp,
      level: event.level,
      scope: event.scope,
      trace: event.trace,
      operation: event.operation,
      stage: event.stage,
      event: event.event,
      result: event.result,
      elapsed: event.elapsed,
      fields: event.fields,
    );
  }

  final DateTime timestamp;
  final DiagnosticLevel level;
  final String scope;
  final DiagnosticTrace? trace;
  final String? operation;
  final String? stage;
  final String event;
  final String? result;
  final Duration? elapsed;
  final Map<String, Object?> fields;

  String formatLine() {
    return DiagnosticEvent(
      timestamp: timestamp,
      level: level,
      scope: scope,
      trace: trace,
      operation: operation,
      stage: stage,
      event: event,
      result: result,
      elapsed: elapsed,
      fields: fields,
    ).formatLine();
  }
}
