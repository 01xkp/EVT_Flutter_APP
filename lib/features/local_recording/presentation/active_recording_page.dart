import 'dart:async';

import 'package:evt_ble_app/core/design_system/evt_theme.dart';
import 'package:evt_ble_app/core/design_system/widgets/app_confirmation_sheet.dart';
import 'package:evt_ble_app/core/design_system/widgets/status_label.dart';
import 'package:evt_ble_app/features/local_recording/application/recording_controller.dart';
import 'package:flutter/material.dart';

class ActiveRecordingPage extends StatefulWidget {
  const ActiveRecordingPage({
    super.key,
    required this.controller,
    this.onFinished,
    this.startOnOpen = true,
  });

  final RecordingController controller;
  final VoidCallback? onFinished;
  final bool startOnOpen;

  @override
  State<ActiveRecordingPage> createState() => _ActiveRecordingPageState();
}

class _ActiveRecordingPageState extends State<ActiveRecordingPage> {
  var _wasActive = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    if (widget.startOnOpen && !widget.controller.state.isCaptureActive) {
      unawaited(widget.controller.start());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    return PopScope<void>(
      canPop: !state.isCaptureActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_confirmExit(context));
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('本机录音')),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) => Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth > 600 ? 520 : double.infinity,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _formatElapsed(state.elapsed),
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                      const SizedBox(height: 20),
                      _LevelMeter(value: state.amplitude),
                      const SizedBox(height: 20),
                      AnimatedSwitcher(
                        duration: EvtTheme.motionDuration,
                        child: _StatusText(state: state),
                      ),
                      const SizedBox(height: 28),
                      AnimatedSwitcher(
                        duration: EvtTheme.motionDuration,
                        child: _Controls(
                          controller: widget.controller,
                          state: state,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onControllerChanged() {
    final active = widget.controller.state.isCaptureActive;
    if (_wasActive &&
        !active &&
        widget.controller.state.phase == ActiveRecordingPhase.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onFinished?.call();
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
    _wasActive = active;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _confirmExit(BuildContext context) async {
    final confirmed = await AppConfirmationSheet.show(
      context,
      title: '结束录音？',
      message: '继续录音可保留当前内容；结束后会保存到本机。',
      cancelLabel: '继续录音',
      confirmLabel: '结束并保存',
    );
    if (confirmed) {
      await widget.controller.stop();
    }
  }

  String _formatElapsed(Duration value) {
    String part(int item) => item.toString().padLeft(2, '0');
    return '${part(value.inHours)}:${part(value.inMinutes.remainder(60))}:${part(value.inSeconds.remainder(60))}';
  }
}

class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final level = value.clamp(0.0, 1.0);
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var index = 0; index < 9; index += 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedContainer(
                duration: EvtTheme.motionDuration,
                width: 4,
                height: 8 + level * (index.isEven ? 28 : 20),
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.state});

  final ActiveRecordingState state;

  @override
  Widget build(BuildContext context) {
    return switch (state.phase) {
      ActiveRecordingPhase.recording => const StatusLabel(
        key: ValueKey('recording'),
        icon: Icons.fiber_manual_record,
        label: '正在录音',
        kind: StatusKind.danger,
      ),
      ActiveRecordingPhase.paused => const StatusLabel(
        key: ValueKey('paused'),
        icon: Icons.pause_outlined,
        label: '已暂停',
        kind: StatusKind.neutral,
      ),
      ActiveRecordingPhase.permissionDenied => const StatusLabel(
        key: ValueKey('permissionDenied'),
        icon: Icons.mic_off_outlined,
        label: '未获得麦克风权限',
        kind: StatusKind.danger,
      ),
      ActiveRecordingPhase.error => StatusLabel(
        key: const ValueKey('error'),
        icon: Icons.error_outline,
        label: state.errorMessage ?? '录音未能保存。',
        kind: StatusKind.danger,
      ),
      _ => const SizedBox(key: ValueKey('waiting'), height: 24),
    };
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller, required this.state});

  final RecordingController controller;
  final ActiveRecordingState state;

  @override
  Widget build(BuildContext context) {
    final buttons = switch (state.phase) {
      ActiveRecordingPhase.recording => [
        _Control(
          tooltip: '暂停录音',
          icon: Icons.pause_outlined,
          onPressed: () => unawaited(controller.pause()),
        ),
        _Control(
          tooltip: '结束录音',
          icon: Icons.stop_outlined,
          destructive: true,
          onPressed: () => unawaited(controller.stop()),
        ),
      ],
      ActiveRecordingPhase.paused => [
        _Control(
          tooltip: '继续录音',
          icon: Icons.play_arrow_outlined,
          onPressed: () => unawaited(controller.resume()),
        ),
        _Control(
          tooltip: '结束录音',
          icon: Icons.stop_outlined,
          destructive: true,
          onPressed: () => unawaited(controller.stop()),
        ),
      ],
      ActiveRecordingPhase.permissionDenied || ActiveRecordingPhase.error => [
        _Control(
          tooltip: '重新开始录音',
          icon: Icons.refresh_outlined,
          onPressed: () => unawaited(controller.start()),
        ),
      ],
      _ => const <_Control>[],
    };
    return SizedBox(
      key: ValueKey(state.phase),
      height: 56,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final button in buttons) ...[
            button,
            if (button != buttons.last) const SizedBox(width: 16),
          ],
        ],
      ),
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton.filled(
      tooltip: tooltip,
      style: destructive
          ? IconButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            )
          : null,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}
