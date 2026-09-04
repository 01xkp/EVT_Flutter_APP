import 'dart:convert';

import 'diagnostic_sanitizer.dart';
import 'diagnostic_trace.dart';

enum DiagnosticLevel { info, warning, error }

/// Immutable, sanitized event shared by the debug viewer and every log sink.
class DiagnosticEvent {
  DiagnosticEvent({
    required this.timestamp,
    required this.level,
    required this.scope,
    required this.event,
    this.trace,
    this.operation,
    this.stage,
    this.result,
    this.elapsed,
    Map<String, Object?> fields = const {},
    DiagnosticSanitizer sanitizer = const DiagnosticSanitizer(),
  }) : fields = sanitizer.sanitize(scope: scope, fields: fields);

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

  String get traceId => trace?.traceId ?? '-';

  String get effectiveOperation => operation ?? trace?.operation ?? '-';

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
      stage ?? '-',
      event,
      result ?? '-',
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
