import 'package:evt_ble_app/core/design_system/evt_theme.dart';
import 'package:flutter/material.dart';

enum StatusKind { neutral, positive, danger }

class StatusLabel extends StatelessWidget {
  const StatusLabel({
    super.key,
    required this.icon,
    required this.label,
    required this.kind,
  });

  final IconData icon;
  final String label;
  final StatusKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColors = theme.extension<EvtStatusColors>()!;
    final color = switch (kind) {
      StatusKind.neutral => theme.colorScheme.onSurfaceVariant,
      StatusKind.positive => statusColors.positive,
      StatusKind.danger => statusColors.danger,
    };

    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}
