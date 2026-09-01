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
    this.onOpenLogs,
    this.onOpenFiles,
    this.onRecordAction,
  });

  final SessionState state;
  final VoidCallback? onStartObservation;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenLogs;
  final VoidCallback? onOpenFiles;
  final ValueChanged<int>? onRecordAction;

  @override
  Widget build(BuildContext context) {
    return DeviceDetailPage(
      state: state,
      onRetry: onRetry,
      onOpenChecking: onStartObservation,
      onOpenLogs: onOpenLogs,
      onOpenFiles: onOpenFiles,
      onRecordAction: onRecordAction,
    );
  }
}
