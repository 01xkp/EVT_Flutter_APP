/// Stable diagnostic representation of a failure without its raw message.
class DiagnosticFailure {
  const DiagnosticFailure({
    required this.errorType,
    this.errorCode,
    this.gattStatus,
    this.httpStatus,
    this.stage,
  });

  final String errorType;
  final String? errorCode;
  final int? gattStatus;
  final int? httpStatus;
  final String? stage;

  factory DiagnosticFailure.from(
    Object error, {
    String? errorCode,
    int? gattStatus,
    int? httpStatus,
    String? stage,
  }) {
    return DiagnosticFailure(
      errorType: error.runtimeType.toString(),
      errorCode: errorCode,
      gattStatus: gattStatus,
      httpStatus: httpStatus,
      stage: stage,
    );
  }

  Map<String, Object?> toFields() {
    return <String, Object?>{
      'error_type': errorType,
      if (errorCode != null) 'error_code': errorCode,
      if (gattStatus != null) 'gatt_status': gattStatus,
      if (httpStatus != null) 'http_status': httpStatus,
      if (stage != null) 'stage': stage,
    };
  }
}
