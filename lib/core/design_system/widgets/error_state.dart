import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/core/design_system/widgets/status_label.dart';
import 'package:flutter/material.dart';

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusLabel(icon: icon, label: title, kind: StatusKind.danger),
          const SizedBox(height: 8),
          Text(message, style: theme.textTheme.bodySmall),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            AppButton.secondary(
              label: actionLabel!,
              onPressed: onAction,
              icon: Icons.refresh,
            ),
          ],
        ],
      ),
    );
  }
}
