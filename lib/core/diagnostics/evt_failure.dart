enum EvtFailureKind { environment, transport, access, protocol, validation }

class EvtFailure {
  const EvtFailure({
    required this.kind,
    required this.message,
    required this.recoverable,
    required this.occurredAt,
    this.detail,
  });

  final EvtFailureKind kind;
  final String message;
  final bool recoverable;
  final DateTime occurredAt;
  final String? detail;

  factory EvtFailure.environment({required String message, String? detail}) {
    return EvtFailure(
      kind: EvtFailureKind.environment,
      message: message,
      recoverable: true,
      occurredAt: DateTime.now(),
      detail: detail,
    );
  }

  factory EvtFailure.transport({required String message, String? detail}) {
    return EvtFailure(
      kind: EvtFailureKind.transport,
      message: message,
      recoverable: true,
      occurredAt: DateTime.now(),
      detail: detail,
    );
  }

  factory EvtFailure.access({required String message, String? detail}) {
    return EvtFailure(
      kind: EvtFailureKind.access,
      message: message,
      recoverable: false,
      occurredAt: DateTime.now(),
      detail: detail,
    );
  }

  factory EvtFailure.protocol({required String message, String? detail}) {
    return EvtFailure(
      kind: EvtFailureKind.protocol,
      message: message,
      recoverable: true,
      occurredAt: DateTime.now(),
      detail: detail,
    );
  }

  factory EvtFailure.validation({required String message, String? detail}) {
    return EvtFailure(
      kind: EvtFailureKind.validation,
      message: message,
      recoverable: false,
      occurredAt: DateTime.now(),
      detail: detail,
    );
  }
}
