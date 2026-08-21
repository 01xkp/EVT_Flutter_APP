import 'package:flutter/material.dart';

class RecordingHubPage extends StatelessWidget {
  const RecordingHubPage({
    super.key,
    required this.isHardwareObservable,
    this.onStartLocal,
    this.onOpenLibrary,
    this.onOpenHardware,
  });

  final bool isHardwareObservable;
  final VoidCallback? onStartLocal;
  final VoidCallback? onOpenLibrary;
  final VoidCallback? onOpenHardware;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('录音')),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final localCard = _RecordingEntryCard(
              icon: Icons.mic_none_outlined,
              title: '本机录音',
              detail: '离线保存到本机',
              actionTooltip: '开始本机录音',
              actionIcon: Icons.fiber_manual_record,
              onAction: onStartLocal,
              secondaryTooltip: '查看本机录音',
              secondaryIcon: Icons.library_music_outlined,
              onSecondaryAction: onOpenLibrary,
            );
            final hardwareCard = _RecordingEntryCard(
              icon: Icons.memory_outlined,
              title: '硬件录音',
              detail: isHardwareObservable ? '观察已连接设备的录音状态' : '连接设备后观察录音状态',
              actionTooltip: '查看硬件录音',
              actionIcon: Icons.arrow_forward,
              onAction: isHardwareObservable ? onOpenHardware : null,
            );
            final content = constraints.maxWidth > 600
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: localCard),
                      const SizedBox(width: 16),
                      Expanded(child: hardwareCard),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      localCard,
                      const SizedBox(height: 12),
                      hardwareCard,
                    ],
                  );
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text('录音', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      '选择录音来源',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    content,
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RecordingEntryCard extends StatelessWidget {
  const _RecordingEntryCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.actionTooltip,
    required this.actionIcon,
    required this.onAction,
    this.secondaryTooltip,
    this.secondaryIcon,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String actionTooltip;
  final IconData actionIcon;
  final VoidCallback? onAction;
  final String? secondaryTooltip;
  final IconData? secondaryIcon;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(detail, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (secondaryTooltip case final tooltip?)
              IconButton(
                tooltip: tooltip,
                onPressed: onSecondaryAction,
                icon: Icon(secondaryIcon),
              ),
            IconButton.filled(
              tooltip: actionTooltip,
              onPressed: onAction,
              icon: Icon(actionIcon),
            ),
          ],
        ),
      ),
    );
  }
}
