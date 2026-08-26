import 'dart:async';

import 'package:aipin/core/design_system/evt_theme.dart';
import 'package:aipin/core/design_system/widgets/app_confirmation_sheet.dart';
import 'package:aipin/core/design_system/widgets/status_label.dart';
import 'package:aipin/features/local_recording/application/recording_controller.dart';
import 'package:aipin/features/local_recording/presentation/recording_level_meter.dart';
import 'package:flutter/material.dart';

class ActiveRecordingPage extends StatefulWidget {
  const ActiveRecordingPage({
    super.key,
    required this.controller,
    this.startOnOpen = true,
  });

  final RecordingController controller;
  final bool startOnOpen;

  @override
  State<ActiveRecordingPage> createState() => _ActiveRecordingPageState();
}

class _ActiveRecordingPageState extends State<ActiveRecordingPage> {
  var _wasActive = false;
  var _saveRequested = false;
  Animation<double>? _routeAnimation;
  var _startScheduled = false;
  var _routeObservationScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observeRouteAfterFirstFrame();
  }

  void _observeRouteAfterFirstFrame() {
    if (_routeObservationScheduled ||
        !widget.startOnOpen ||
        widget.controller.state.isCaptureActive) {
      return;
    }
    _routeObservationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeObservationScheduled = false;
      if (mounted) {
        _bindRouteAnimation();
      }
    });
  }

  void _bindRouteAnimation() {
    if (!widget.startOnOpen || widget.controller.state.isCaptureActive) {
      return;
    }
    final routeAnimation = ModalRoute.of(context)?.animation;
    if (identical(routeAnimation, _routeAnimation)) {
      return;
    }
    _routeAnimation?.removeStatusListener(_onRouteAnimationChanged);
    _routeAnimation = routeAnimation;
    if (routeAnimation == null ||
        routeAnimation.status == AnimationStatus.completed) {
      _startAfterEntrance();
      return;
    }
    routeAnimation.addStatusListener(_onRouteAnimationChanged);
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteAnimationChanged);
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final theme = Theme.of(context);
    final pageBackground = theme.scaffoldBackgroundColor;
    return AnnotatedRegion(
      value: EvtTheme.systemUiOverlayStyle(theme),
      child: PopScope<void>(
        canPop: !state.isCaptureActive,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            unawaited(_exit());
          }
        },
        child: Scaffold(
          backgroundColor: pageBackground,
          appBar: AppBar(
            backgroundColor: pageBackground,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            title: const Text('本机录音'),
            actions: [
              IconButton(
                tooltip: '退出录音',
                onPressed: () => unawaited(_exit()),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth > 600
                        ? 520
                        : double.infinity,
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
                        RecordingLevelMeter(value: state.amplitude),
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
                            onStop: _stopAndSave,
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
      ),
    );
  }

  void _onControllerChanged() {
    final active = widget.controller.state.isCaptureActive;
    if (_wasActive &&
        !active &&
        widget.controller.state.phase == ActiveRecordingPhase.idle) {
      final result = _saveRequested
          ? widget.controller.lastCompletedRecording
          : null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(result);
        }
      });
    }
    _wasActive = active;
    if (mounted) {
      setState(() {});
    }
  }

  void _onRouteAnimationChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _startAfterEntrance();
        }
      });
    }
  }

  void _startAfterEntrance() {
    if (_startScheduled ||
        !widget.startOnOpen ||
        widget.controller.state.isCaptureActive) {
      return;
    }
    _startScheduled = true;
    unawaited(widget.controller.start());
  }

  Future<void> _exit() async {
    if (widget.controller.state.isCaptureActive) {
      final confirmed = await AppConfirmationSheet.show(
        context,
        title: '退出录音？',
        message: '退出后本次录音不会保存。',
        cancelLabel: '继续录音',
        confirmLabel: '确认退出',
        variant: AppConfirmationVariant.destructive,
      );
      if (confirmed && widget.controller.state.isCaptureActive) {
        _saveRequested = false;
        await widget.controller.discard();
      }
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _stopAndSave() {
    _saveRequested = true;
    unawaited(widget.controller.stop());
  }

  String _formatElapsed(Duration value) {
    String part(int item) => item.toString().padLeft(2, '0');
    return '${part(value.inHours)}:${part(value.inMinutes.remainder(60))}:${part(value.inSeconds.remainder(60))}';
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
      ActiveRecordingPhase.starting => const StatusLabel(
        key: ValueKey('starting'),
        icon: Icons.mic_none_outlined,
        label: '正在准备录音',
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
  const _Controls({
    required this.controller,
    required this.state,
    required this.onStop,
  });

  final RecordingController controller;
  final ActiveRecordingState state;
  final VoidCallback onStop;

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
          onPressed: onStop,
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
          onPressed: onStop,
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
