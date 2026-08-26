import 'package:aipin/core/design_system/widgets/error_state.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:flutter/material.dart';

class SessionFailurePanel extends StatelessWidget {
  const SessionFailurePanel({
    super.key,
    required this.failure,
    this.lastSnapshot,
    this.onRetry,
  });

  final EvtFailure failure;
  final DeviceSnapshot? lastSnapshot;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final guidance = switch (failure.kind) {
      EvtFailureKind.environment => (
        Icons.bluetooth_disabled_outlined,
        '蓝牙或权限不可用',
        '请打开蓝牙，并在系统设置中允许本应用扫描和连接设备。',
      ),
      EvtFailureKind.transport => (
        Icons.bluetooth_disabled_outlined,
        '连接已中断',
        '请靠近设备后重试；如仍失败，请重新连接。',
      ),
      EvtFailureKind.access => (
        Icons.lock_outline,
        '状态暂不可读取',
        '设备已连接，但当前固件未提供所需状态访问。',
      ),
      EvtFailureKind.protocol || EvtFailureKind.validation => (
        Icons.data_object_outlined,
        '当前数据不可验证',
        '状态帧不完整或校验失败，请保留现场并重新读取。',
      ),
    };
    final detail = [guidance.$3, failure.message].join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ErrorState(
          icon: guidance.$1,
          title: guidance.$2,
          message: detail,
          actionLabel: onRetry == null ? null : '重试',
          onAction: onRetry,
        ),
        if (lastSnapshot case final snapshot?) ...[
          const SizedBox(height: 8),
          Text(
            '最后有效状态：${snapshot.source} · ${snapshot.observedAt.toIso8601String()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
