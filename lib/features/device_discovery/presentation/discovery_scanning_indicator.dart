import 'package:flutter/material.dart';

class DiscoveryScanningIndicator extends StatefulWidget {
  const DiscoveryScanningIndicator({super.key});

  @override
  State<DiscoveryScanningIndicator> createState() =>
      _DiscoveryScanningIndicatorState();
}

class _DiscoveryScanningIndicatorState extends State<DiscoveryScanningIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: '正在查找附近设备',
      child: SizedBox(
        key: const ValueKey('discoveryScanningLoader'),
        width: 160,
        height: 160,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Stack(
            alignment: Alignment.center,
            children: [
              for (final delay in const [0.0, 1 / 3, 2 / 3])
                _ScanRing(
                  progress: (_controller.value + delay) % 1,
                  color: colors.primary,
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: const SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(Icons.radar_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanRing extends StatelessWidget {
  const _ScanRing({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: (1 - progress) * 0.48,
      child: Transform.scale(
        scale: 0.25 + progress * 0.75,
        child: Container(
          width: 128,
          height: 128,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
        ),
      ),
    );
  }
}
