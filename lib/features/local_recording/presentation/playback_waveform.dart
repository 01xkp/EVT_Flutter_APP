import 'dart:math' as math;

import 'package:flutter/material.dart';

class PlaybackWaveform extends StatefulWidget {
  const PlaybackWaveform({
    super.key,
    required this.progress,
    required this.isPlaying,
  });

  final double progress;
  final bool isPlaying;

  @override
  State<PlaybackWaveform> createState() => _PlaybackWaveformState();
}

class _PlaybackWaveformState extends State<PlaybackWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motionController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    _updateMotion();
  }

  @override
  void didUpdateWidget(covariant PlaybackWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      _updateMotion();
    }
  }

  @override
  void dispose() {
    _motionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 148,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _motionController,
              builder: (context, _) => CustomPaint(
                painter: _PlaybackWaveformPainter(
                  progress: widget.progress,
                  phase: _motionController.value,
                  activeColor: colors.primary,
                  inactiveColor: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _updateMotion() {
    if (widget.isPlaying) {
      _motionController.repeat();
    } else {
      _motionController.stop();
    }
  }
}

class _PlaybackWaveformPainter extends CustomPainter {
  const _PlaybackWaveformPainter({
    required this.progress,
    required this.phase,
    required this.activeColor,
    required this.inactiveColor,
  });

  final double progress;
  final double phase;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    const horizontalPadding = 14.0;
    const waveformHeight = 78.0;
    const gap = 3.0;
    final availableWidth = size.width - horizontalPadding * 2;
    final count = (availableWidth / 7).floor().clamp(28, 52);
    final barWidth = (availableWidth - gap * (count - 1)) / count;
    final normalizedProgress = progress.clamp(0.0, 1.0);

    for (var index = 0; index < count; index += 1) {
      final position = index / (count - 1);
      final wave =
          math.sin(index * 0.71 + phase * math.pi * 2) * 0.24 +
          math.sin(index * 0.29 - phase * math.pi) * 0.16 +
          0.6;
      final height = 13 + wave * (waveformHeight - 13);
      final left = horizontalPadding + index * (barWidth + gap);
      final top = size.height / 2 - height / 2;
      final color = position <= normalizedProgress
          ? activeColor.withValues(alpha: 0.88)
          : inactiveColor.withValues(alpha: 0.23);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, height),
          Radius.circular(barWidth / 2),
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlaybackWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
