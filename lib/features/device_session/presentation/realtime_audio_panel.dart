import 'dart:async';

import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/core/design_system/widgets/app_surface_card.dart';
import 'package:aipin/features/device_session/application/realtime_audio_controller.dart';
import 'package:aipin/features/device_session/domain/realtime_audio_capture.dart';
import 'package:flutter/material.dart';

class RealtimeAudioPanel extends StatelessWidget {
  const RealtimeAudioPanel({
    super.key,
    required this.controller,
    required this.onExport,
  });

  final RealtimeAudioController controller;
  final Future<void> Function(RealtimeAudioCapture capture) onExport;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RealtimeAudioState>(
      valueListenable: controller,
      builder: (context, state, _) => AppSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('实时音频', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              _statusLabel(state),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '未知编码原始数据，不能直接播放',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (state.error case final error?) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppButton.primary(
                    label: state.isActive ? '停止接收' : '开始接收',
                    icon: state.isActive
                        ? Icons.stop_outlined
                        : Icons.graphic_eq_outlined,
                    onPressed:
                        state.phase == RealtimeAudioPhase.starting ||
                            state.phase == RealtimeAudioPhase.stopping
                        ? null
                        : state.isActive
                        ? () => unawaited(controller.stop())
                        : () => unawaited(controller.start()),
                  ),
                ),
                if (state.canExportRaw) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton.secondary(
                      label: '导出原始数据',
                      icon: Icons.ios_share_outlined,
                      onPressed: () {
                        final capture = controller.capture();
                        if (capture != null) {
                          unawaited(onExport(capture));
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(RealtimeAudioState state) => switch (state.phase) {
    RealtimeAudioPhase.idle => '尚未开始接收',
    RealtimeAudioPhase.starting => '正在开启设备音频流',
    RealtimeAudioPhase.capturing => '正在接收 ${_formatBytes(state.receivedBytes)}',
    RealtimeAudioPhase.stopping => '正在关闭设备音频流',
    RealtimeAudioPhase.completed => '接收完成 ${_formatBytes(state.receivedBytes)}',
    RealtimeAudioPhase.failed => '接收失败 ${_formatBytes(state.receivedBytes)}',
  };

  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
}
