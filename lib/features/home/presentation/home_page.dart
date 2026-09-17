import 'package:aipin/core/design_system/evt_theme.dart';
import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/core/design_system/widgets/app_surface_card.dart';
import 'package:aipin/core/design_system/widgets/app_text_action.dart';
import 'package:flutter/material.dart';

enum DeviceSummaryStatus {
  disconnected,
  searching,
  reconnecting,
  reconnectFailed,
  connected,
}

class DeviceSummary {
  const DeviceSummary._({
    required this.name,
    required this.status,
    required this.connectionLabel,
    required this.recordingLabel,
  });

  const DeviceSummary.disconnected({required String name})
    : this._(
        name: name,
        status: DeviceSummaryStatus.disconnected,
        connectionLabel: '尚未连接',
        recordingLabel: '暂时无法获取',
      );

  const DeviceSummary.searching({required String name})
    : this._(
        name: name,
        status: DeviceSummaryStatus.searching,
        connectionLabel: '正在查找设备',
        recordingLabel: '暂时无法获取',
      );

  const DeviceSummary.connected({
    required String name,
    String recordingLabel = '暂时无法获取',
  }) : this._(
         name: name,
         status: DeviceSummaryStatus.connected,
         connectionLabel: '已连接',
         recordingLabel: recordingLabel,
       );

  const DeviceSummary.reconnecting({required String name})
    : this._(
        name: name,
        status: DeviceSummaryStatus.reconnecting,
        connectionLabel: '正在回连设备',
        recordingLabel: '暂时无法获取',
      );

  const DeviceSummary.reconnectFailed({required String name})
    : this._(
        name: name,
        status: DeviceSummaryStatus.reconnectFailed,
        connectionLabel: '回连失败，可再次尝试',
        recordingLabel: '暂时无法获取',
      );

  final String name;
  final DeviceSummaryStatus status;
  final String connectionLabel;
  final String recordingLabel;

  bool get isConnected => status == DeviceSummaryStatus.connected;
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.device,
    required this.onConnectDevice,
    required this.onOpenSettings,
    this.onOpenDevice,
    this.onOpenFiles,
    this.onOpenSavedRecordings,
    this.onOpenLogs,
  });

  final DeviceSummary device;
  final VoidCallback onConnectDevice;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenDevice;
  final VoidCallback? onOpenFiles;
  final VoidCallback? onOpenSavedRecordings;
  final VoidCallback? onOpenLogs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        actions: [AppTextAction(label: '设置', onPressed: onOpenSettings)],
      ),
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
                  const Text('连接设备 → 输入安全码 → 录音 → 下载 → 播放'),
                  const SizedBox(height: 12),
                  AppSurfaceCard(
                    onTap: onOpenDevice ?? onConnectDevice,
                    child: AnimatedSwitcher(
                      duration: EvtTheme.motionDuration,
                      child: _DeviceSummaryContent(
                        key: ValueKey(device.status),
                        device: device,
                        opensExistingDevice: onOpenDevice != null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (onOpenFiles != null) ...[
                    AppButton.primary(label: '设备录音文件', onPressed: onOpenFiles),
                    const SizedBox(height: 8),
                  ],
                  if (onOpenSavedRecordings != null) ...[
                    AppButton.secondary(
                      label: '已保存录音',
                      onPressed: onOpenSavedRecordings,
                    ),
                    const Text('查看手机里的录音，未连接设备也能播放。'),
                    const SizedBox(height: 8),
                  ],
                  if (onOpenLogs != null) ...[
                    AppButton.secondary(label: '实时日志', onPressed: onOpenLogs),
                    const SizedBox(height: 20),
                  ],
                  Text('设备状态', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  AppSurfaceCard(
                    child: _ActionRow(
                      icon: Icons.memory_outlined,
                      title: '设备录音状态',
                      detail: device.recordingLabel,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceSummaryContent extends StatelessWidget {
  const _DeviceSummaryContent({
    super.key,
    required this.device,
    required this.opensExistingDevice,
  });

  final DeviceSummary device;
  final bool opensExistingDevice;

  @override
  Widget build(BuildContext context) {
    final actionLabel = opensExistingDevice
        ? '查看设备'
        : switch (device.status) {
            DeviceSummaryStatus.disconnected => '连接设备',
            DeviceSummaryStatus.searching => '查看附近设备',
            DeviceSummaryStatus.reconnecting => '正在回连',
            DeviceSummaryStatus.reconnectFailed => '重新连接',
            DeviceSummaryStatus.connected => '查看设备',
          };
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('我的设备', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(switch (device.status) {
              DeviceSummaryStatus.connected => Icons.bluetooth_connected,
              DeviceSummaryStatus.reconnecting => Icons.bluetooth_searching,
              DeviceSummaryStatus.reconnectFailed => Icons.bluetooth_disabled,
              _ => Icons.bluetooth_outlined,
            }),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    device.connectionLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(actionLabel, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward, size: 18),
          ],
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
