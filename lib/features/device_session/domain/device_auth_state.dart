/// Connection-scoped security state for the EVT V1.6 security-code flow.
///
/// [unbindPending] is deliberately distinct from [unbound].  A dispatched
/// Action=2 request that loses its final response leaves the device in a
/// recoverable UNBIND_PENDING/UNBINDING state; treating it as an ordinary
/// unbound device could let the UI offer a new bind and lose the old cleanup
/// result.
enum DeviceAuthState {
  unknown,
  unbound,
  unbindPending,
  authenticating,
  authenticated,
  failed,
}
