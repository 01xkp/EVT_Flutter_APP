enum SessionPhase {
  environmentReady,
  discovered,
  connecting,
  servicesDiscovered,
  subscribing,
  authenticationReady,
  initialSnapshotRead,
  observable,
  observing,
  verifying,
  completed,
  interrupted,
}

extension SessionPhaseTransitions on SessionPhase {
  bool canTransitionTo(SessionPhase next) => switch ((this, next)) {
    (SessionPhase.environmentReady, SessionPhase.discovered) => true,
    (SessionPhase.discovered, SessionPhase.connecting) => true,
    (SessionPhase.connecting, SessionPhase.servicesDiscovered) => true,
    (SessionPhase.servicesDiscovered, SessionPhase.subscribing) => true,
    (SessionPhase.subscribing, SessionPhase.authenticationReady) => true,
    (SessionPhase.authenticationReady, SessionPhase.observable) => true,
    (SessionPhase.subscribing, SessionPhase.initialSnapshotRead) => true,
    (SessionPhase.initialSnapshotRead, SessionPhase.observable) => true,
    (SessionPhase.observable, SessionPhase.observing) => true,
    (SessionPhase.observing, SessionPhase.verifying) => true,
    (SessionPhase.verifying, SessionPhase.completed) => true,
    (_, SessionPhase.interrupted) when this != SessionPhase.completed => true,
    _ => false,
  };
}
