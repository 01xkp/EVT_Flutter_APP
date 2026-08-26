import 'package:aipin/features/device_session/application/session_state.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:aipin/features/device_session/presentation/device_detail_page.dart';
import 'package:flutter/material.dart';

class SessionDashboardPage extends StatelessWidget {
  const SessionDashboardPage({
    super.key,
    this.state = const SessionState(phase: SessionPhase.environmentReady),
    this.onStartObservation,
    this.onRetry,
  });

  final SessionState state;
  final VoidCallback? onStartObservation;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return DeviceDetailPage(
      state: state,
      onRetry: onRetry,
      onOpenChecking: onStartObservation,
    );
  }
}
