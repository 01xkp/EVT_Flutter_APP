import 'package:evt_ble_app/core/design_system/widgets/app_button.dart';
import 'package:evt_ble_app/features/device_session/application/session_state.dart';
import 'package:evt_ble_app/features/device_session/domain/session_phase.dart';
import 'package:evt_ble_app/features/device_session/presentation/phase_indicator.dart';
import 'package:evt_ble_app/features/device_session/presentation/session_failure_panel.dart';
import 'package:evt_ble_app/features/device_session/presentation/snapshot_table.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('设备快照')),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PhaseIndicator(phase: state.phase),
              if (state.failure case final failure?) ...[
                const SizedBox(height: 16),
                SessionFailurePanel(
                  failure: failure,
                  lastSnapshot: state.latestSnapshot,
                  onRetry: onRetry,
                ),
              ],
              const SizedBox(height: 24),
              Text('状态详情', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: SnapshotTable(snapshot: state.latestSnapshot),
                ),
              ),
              if (state.latestSnapshot case final snapshot?)
                Text(
                  '${snapshot.source} · ${TimeOfDay.fromDateTime(snapshot.observedAt).format(context)}',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                Text(
                  '尚未收到真实设备状态',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 16),
              AppButton.primary(
                label: '开始观察',
                onPressed: state.isObservable ? onStartObservation : null,
                icon: Icons.visibility_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
