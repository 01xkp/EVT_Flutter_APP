/// Raised when the EVT App cannot prove that a normal V1.6 UNBIND is safe.
///
/// The App deliberately does not send Action=2 when the device is recording,
/// synchronizing, still has device files, or cannot provide a current answer
/// for those checks. The recovery path after an already-dispatched Action=2
/// is intentionally outside this guard.
class EvtUnbindPreflightException implements Exception {
  const EvtUnbindPreflightException(this.message);

  final String message;

  @override
  String toString() => message;
}
