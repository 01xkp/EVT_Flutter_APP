import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/core/design_system/widgets/app_confirmation_sheet.dart';
import 'package:aipin/core/design_system/widgets/app_surface_card.dart';
import 'package:aipin/features/device_session/application/session_state.dart';
import 'package:aipin/features/device_session/presentation/device_status_view_model.dart';
import 'package:aipin/features/device_session/presentation/session_failure_panel.dart';
import 'package:flutter/material.dart';

class DeviceDetailPage extends StatelessWidget {
  const DeviceDetailPage({
    super.key,
    required this.state,
    this.onDisconnect,
    this.onRetry,
    this.onOpenChecking,
  });

  final SessionState state;
  final VoidCallback? onDisconnect;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenChecking;

  @override
  Widget build(BuildContext context) {
    final status = DeviceStatusViewModel.from(state);
    final deviceName = state.session?.candidate.name ?? '我的设备';
    return Scaffold(
      appBar: AppBar(title: const Text('设备详情')),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth > 600 ? 640 : double.infinity,
              ),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    deviceName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  AppSurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DetailRow(
                          label: '连接状态',
                          value: status.connectionLabel,
                        ),
                        const Divider(height: 24),
                        _DetailRow(
                          label: '设备录音状态',
                          value: status.recordingLabel,
                        ),
                        if (status.batteryLabel case final battery?) ...[
                          const Divider(height: 24),
                          _DetailRow(label: '电量', value: '$battery%'),
                        ],
                        if (status.updatedAt case final updatedAt?) ...[
                          const Divider(height: 24),
                          _DetailRow(
                            label: '最近更新',
                            value: TimeOfDay.fromDateTime(
                              updatedAt,
                            ).format(context),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (state.failure case final failure?) ...[
                    const SizedBox(height: 16),
                    SessionFailurePanel(
                      failure: failure,
                      lastSnapshot: state.latestSnapshot,
                      onRetry: onRetry,
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: () => _showConnectionHelp(context),
                    icon: const Icon(Icons.help_outline),
                    label: const Text('连接帮助'),
                  ),
                  if (state.isObservable) ...[
                    const SizedBox(height: 8),
                    AppButton.secondary(
                      label: '设备检查',
                      onPressed: onOpenChecking,
                      icon: Icons.fact_check_outlined,
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (status.canReconnect)
                    AppButton.primary(
                      label: '重新连接',
                      onPressed: onRetry,
                      icon: Icons.refresh,
                    )
                  else
                    AppButton.secondary(
                      label: '断开设备',
                      onPressed: onDisconnect == null
                          ? null
                          : () => _confirmDisconnect(context),
                      icon: Icons.bluetooth_disabled_outlined,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDisconnect(BuildContext context) async {
    final confirmed = await AppConfirmationSheet.show(
      context,
      title: '断开设备？',
      message: '断开后将无法查看设备当前状态。',
      confirmLabel: '断开设备',
    );
    if (confirmed) {
      onDisconnect?.call();
    }
  }

  void _showConnectionHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('连接帮助', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text('请确认设备已开机并靠近手机，再重新连接。'),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 16),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}
