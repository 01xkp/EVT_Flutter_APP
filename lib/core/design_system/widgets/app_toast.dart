import 'dart:async';

import 'package:aipin/core/design_system/evt_theme.dart';
import 'package:flutter/material.dart';

abstract final class AppToast {
  static OverlayEntry? _activeEntry;

  static void show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 2),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    _activeEntry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _AppToast(
        message: message,
        duration: duration,
        onDismissed: () {
          if (identical(_activeEntry, entry)) {
            entry.remove();
            _activeEntry = null;
          }
        },
      ),
    );
    _activeEntry = entry;
    overlay.insert(entry);
  }
}

class _AppToast extends StatefulWidget {
  const _AppToast({
    required this.message,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<_AppToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: EvtTheme.motionDuration,
    reverseDuration: EvtTheme.motionDuration,
  );
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _animation.forward();
    _dismissTimer = Timer(widget.duration, () => unawaited(_dismiss()));
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (!mounted) {
      return;
    }
    await _animation.reverse();
    if (mounted) {
      widget.onDismissed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Center(
        child: FadeTransition(
          opacity: _animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(_animation),
            child: Semantics(
              liveRegion: true,
              label: widget.message,
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: const BorderRadius.all(
                        EvtTheme.componentRadius,
                      ),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: colors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Flexible(child: Text(widget.message)),
                        ],
                      ),
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
}
