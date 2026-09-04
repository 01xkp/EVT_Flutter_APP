import 'dart:convert';

import 'diagnostic_sanitizer.dart';
import 'diagnostic_trace.dart';

enum DiagnosticLevel { info, warning, error }

/// Immutable, sanitized event shared by the debug viewer and every log sink.
class DiagnosticEvent {
  DiagnosticEvent({
    required this.timestamp,
    required this.level,
    required String scope,
    required String event,
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    this.elapsed,
    Map<String, Object?> fields = const {},
    DiagnosticSanitizer sanitizer = const DiagnosticSanitizer(),
  }) : scope = sanitizer.normalizeScope(scope),
       traceId = sanitizer.normalizeTraceId(trace?.traceId),
       trace = trace == null
           ? null
           : DiagnosticTrace.sanitized(
               source: trace,
               traceId: sanitizer.normalizeTraceId(trace.traceId),
               operation: sanitizer.normalizeOperation(
                 operation ?? trace.operation,
               ),
             ),
       operation = sanitizer.normalizeOperation(operation ?? trace?.operation),
       stage = sanitizer.normalizeStage(stage),
       event = sanitizer.normalizeEvent(event),
       result = sanitizer.normalizeResult(result),
       fields = sanitizer.sanitize(
         scope: sanitizer.normalizeScope(scope),
         fields: fields,
       );

  final DateTime timestamp;
  final DiagnosticLevel level;
  final String scope;
  final DiagnosticTrace? trace;
  final String traceId;
  final String operation;
  final String stage;
  final String event;
  final String result;
  final Duration? elapsed;
  final Map<String, Object?> fields;

  String get effectiveOperation => operation;

  DiagnosticEvent copyWith({Map<String, Object?>? fields}) {
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
      fields: fields ?? this.fields,
    );
  }

  String formatLine() {
    final normalizedFields = fields.entries
        .map((entry) => '${entry.key}=${_formatValue(entry.value)}')
        .join(' ');
    final parts = <String>[
      timestamp.toUtc().toIso8601String(),
      level.name.toUpperCase(),
      scope,
      traceId,
      effectiveOperation,
      stage,
      event,
      result,
      elapsed?.inMilliseconds.toString() ?? '-',
    ];
    if (normalizedFields.isNotEmpty) {
      parts.add(normalizedFields);
    }
    return parts.join(' | ');
  }

  Object? _formatValue(Object? value) {
    if (value is Map || value is Iterable) {
      return jsonEncode(value);
    }
    return value;
  }
}
