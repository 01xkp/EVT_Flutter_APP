import 'package:evt_ble_app/core/design_system/evt_theme.dart';
import 'package:flutter/material.dart';

class AppSurfaceCard extends StatelessWidget {
  const AppSurfaceCard({
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isInteractive = onTap != null;
    final backgroundColor = selected
        ? theme.extension<EvtStatusColors>()?.subtle ??
              theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surface;
    final borderRadius = const BorderRadius.all(EvtTheme.componentRadius);

    return Semantics(
      button: isInteractive,
      selected: selected,
      child: Material(
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
