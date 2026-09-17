import 'dart:async';

import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/core/design_system/widgets/app_surface_card.dart';
import 'package:aipin/core/design_system/widgets/status_label.dart';
import 'package:aipin/features/device_session/application/dvt_audio_probe_controller.dart';
import 'package:flutter/material.dart';

/// DVT-only screen for observing FA18/0x88 delivery from a connected device.
///
/// The page owns no BLE API. Its [controller] is wired to SessionController's
/// `dvtAudioPayloads`, `startDvtAudioProbe`, and `stopDvtAudioProbe` APIs by
/// the app shell.
class DvtAudioProbePage extends StatefulWidget {
  const DvtAudioProbePage({
    super.key,
    required this.controller,
    this.disposeController = true,
  });

  final DvtAudioProbeController controller;
  final bool disposeController;

  @override
  State<DvtAudioProbePage> createState() => _DvtAudioProbePageState();
}

class _DvtAudioProbePageState extends State<DvtAudioProbePage> {
  var _allowPop = false;
  var _isStoppingForPop = false;

  @override
  void dispose() {
    if (widget.disposeController) {
      widget.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        return PopScope(
          canPop: _allowPop || !state.mayRequireStop,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              unawaited(_stopBeforeLeaving());
            }
          },
          child: Scaffold(
            appBar: AppBar(title: const Text('实时音频验证')),
            body: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) => Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth > 600
                          ? 640
                          : double.infinity,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        AppSurfaceCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'DVT 实时音频',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              _ProbePhaseLabel(phase: state.phase),
                              if (state.failureMessage case final message?) ...[
                                const SizedBox(height: 12),
                                Text(
                                  message,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                              if (state.isBusy) ...[
                                const SizedBox(height: 12),
                                const LinearProgressIndicator(minHeight: 2),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        AppSurfaceCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '接收指标',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 24,
                                runSpacing: 20,
                                children: [
                                  _Metric(
                                    label: '帧数',
                                    value: '${state.frameCount}',
                                  ),
                                  _Metric(
                                    label: '接收字节',
                                    value: _formatBytes(state.byteCount),
                                  ),
                                  _Metric(
                                    label: '时长',
                                    value: _formatDuration(state.elapsed),
                                  ),
                                  _Metric(
                                    label: '吞吐',
                                    value: _formatRate(state.bytesPerSecond),
                                  ),
                                ],
                              ),
                              const Divider(height: 32),
                              Text(
                                DvtAudioProbeState.packetLossUnavailableMessage,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (state.canStart)
                          AppButton.primary(
                            label: state.phase == DvtAudioProbePhase.failed
                                ? '重新开始'
                                : '开始验证',
                            onPressed: _start,
                            icon: Icons.play_arrow_outlined,
                          ),
                        if (state.canStop) ...[
                          if (state.canStart) const SizedBox(height: 12),
                          AppButton.secondary(
                            label: '停止验证',
                            onPressed: _stop,
                            icon: Icons.stop_outlined,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _start() => widget.controller.start();

  Future<void> _stop() => widget.controller.stop();

  Future<void> _stopBeforeLeaving() async {
    if (_isStoppingForPop) {
      return;
    }
    setState(() => _isStoppingForPop = true);
    await widget.controller.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      _allowPop = true;
      _isStoppingForPop = false;
    });
    Navigator.of(context).pop();
  }
}

class _ProbePhaseLabel extends StatelessWidget {
  const _ProbePhaseLabel({required this.phase});

  final DvtAudioProbePhase phase;

  @override
  Widget build(BuildContext context) {
    final status = switch (phase) {
      DvtAudioProbePhase.idle => (
        Icons.radio_button_unchecked,
        '未开始',
        StatusKind.neutral,
      ),
      DvtAudioProbePhase.starting => (Icons.sync, '正在启动', StatusKind.neutral),
      DvtAudioProbePhase.streaming => (
        Icons.graphic_eq,
        '正在接收',
        StatusKind.positive,
      ),
      DvtAudioProbePhase.stopping => (Icons.sync, '正在停止', StatusKind.neutral),
      DvtAudioProbePhase.completed => (
        Icons.check_circle_outline,
        '已停止',
        StatusKind.positive,
      ),
      DvtAudioProbePhase.failed => (
        Icons.error_outline,
        '验证失败',
        StatusKind.danger,
      ),
    };
    return StatusLabel(icon: status.$1, label: status.$2, kind: status.$3);
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 116,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatRate(double bytesPerSecond) =>
    '${_formatBytes(bytesPerSecond.round())}/s';

String _formatDuration(Duration value) {
  final totalSeconds = value.inSeconds;
  final hours = totalSeconds ~/ Duration.secondsPerHour;
  final minutes =
      (totalSeconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
  final seconds = totalSeconds % Duration.secondsPerMinute;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
