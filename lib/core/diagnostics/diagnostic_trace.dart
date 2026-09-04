import 'dart:math';

/// Correlates diagnostics that belong to one user-visible operation.
class DiagnosticTrace {
  const DiagnosticTrace._({
    required this.traceId,
    required this.operation,
    required this.origin,
    required this.startedAt,
    this.deviceReference,
    this.parentTraceId,
  });

  final String traceId;
  final String operation;
  final String origin;
  final DateTime startedAt;
  final String? deviceReference;
  final String? parentTraceId;

  factory DiagnosticTrace.start({
    required String operation,
    required String origin,
    String? deviceReference,
    String? traceId,
    DateTime? startedAt,
  }) {
    return DiagnosticTrace._(
      traceId: traceId ?? _newTraceId(),
      operation: operation,
      origin: origin,
      startedAt: startedAt ?? DateTime.now().toUtc(),
      deviceReference: deviceReference,
    );
  }

  DiagnosticTrace child({required String operation}) {
    return DiagnosticTrace._(
      traceId: traceId,
      operation: operation,
      origin: origin,
      startedAt: startedAt,
      deviceReference: deviceReference,
      parentTraceId: parentTraceId,
    );
  }

  factory DiagnosticTrace.sanitized({
    required DiagnosticTrace source,
    required String traceId,
    required String operation,
  }) {
    return DiagnosticTrace._(
      traceId: traceId,
      operation: operation,
      origin: 'diagnostic',
      startedAt: source.startedAt,
    );
  }

  Duration elapsedAt(DateTime timestamp) => timestamp.difference(startedAt);

  static String _newTraceId() {
    const alphabet = '0123456789abcdef';
    final random = Random.secure();
    return List<String>.generate(
      12,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }
}
