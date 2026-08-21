import 'package:evt_ble_app/core/design_system/evt_theme.dart';
import 'package:evt_ble_app/core/design_system/widgets/app_surface_card.dart';
import 'package:flutter/material.dart';

enum DeviceSummaryStatus { disconnected, searching, connected }

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
    required this.onStartLocalRecording,
    required this.onOpenSettings,
  });

  final DeviceSummary device;
  final VoidCallback onConnectDevice;
  final VoidCallback onStartLocalRecording;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        actions: [
          IconButton(
            tooltip: '设置',
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
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
                  AppSurfaceCard(
                    onTap: onConnectDevice,
                    child: AnimatedSwitcher(
                      duration: EvtTheme.motionDuration,
                      child: _DeviceSummaryContent(
                        key: ValueKey(device.status),
                        device: device,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text('录音', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  AppSurfaceCard(
                    onTap: onStartLocalRecording,
                    child: const _ActionRow(
                      icon: Icons.mic_none_outlined,
                      title: '本机录音',
                      detail: '无需连接设备',
                      trailing: Icons.arrow_forward,
                    ),
                  ),
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
  const _DeviceSummaryContent({super.key, required this.device});

  final DeviceSummary device;

  @override
  Widget build(BuildContext context) {
    final actionLabel = switch (device.status) {
      DeviceSummaryStatus.disconnected => '连接设备',
      DeviceSummaryStatus.searching => '查看附近设备',
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
            Icon(
              device.isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_outlined,
            ),
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
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String detail;
  final IconData? trailing;

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
        if (trailing case final icon?) Icon(icon, size: 18),
      ],
    );
  }
}
