import 'package:aipin/core/design_system/widgets/status_label.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:flutter/material.dart';

class PhaseIndicator extends StatelessWidget {
  const PhaseIndicator({super.key, required this.phase});

  final SessionPhase phase;

  @override
  Widget build(BuildContext context) {
    final (icon, label, kind) = switch (phase) {
      SessionPhase.observable => (
        Icons.visibility_outlined,
        '状态可观察',
        StatusKind.positive,
      ),
      SessionPhase.interrupted => (
        Icons.error_outline,
        '会话已中断',
        StatusKind.danger,
      ),
      _ => (Icons.sync_outlined, _labelFor(phase), StatusKind.neutral),
    };
    return StatusLabel(icon: icon, label: label, kind: kind);
  }

  static String _labelFor(SessionPhase phase) => switch (phase) {
    SessionPhase.environmentReady => '等待连接',
    SessionPhase.discovered => '已选择设备',
    SessionPhase.connecting => '正在连接',
    SessionPhase.servicesDiscovered => '服务已发现',
    SessionPhase.subscribing => '正在订阅状态',
    SessionPhase.initialSnapshotRead => '正在读取首个状态',
    SessionPhase.observing => '正在观察',
    SessionPhase.verifying => '正在复核',
    SessionPhase.completed => '观察已完成',
    SessionPhase.observable || SessionPhase.interrupted => '',
  };
}
