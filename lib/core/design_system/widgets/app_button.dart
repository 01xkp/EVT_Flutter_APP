import 'package:flutter/material.dart';

enum AppButtonVariant { primary, secondary, destructive }

class AppButton extends StatelessWidget {
  const AppButton._({
    required this.label,
    required this.variant,
    this.onPressed,
    this.loading = false,
    this.icon,
  });

  factory AppButton.primary({
    required String label,
    required VoidCallback? onPressed,
    bool loading = false,
    IconData? icon,
  }) {
    return AppButton._(
      label: label,
      variant: AppButtonVariant.primary,
      onPressed: onPressed,
      loading: loading,
      icon: icon,
    );
  }

  factory AppButton.secondary({
    required String label,
    required VoidCallback? onPressed,
    bool loading = false,
    IconData? icon,
  }) {
    return AppButton._(
      label: label,
      variant: AppButtonVariant.secondary,
      onPressed: onPressed,
      loading: loading,
      icon: icon,
    );
  }

  factory AppButton.destructive({
    required String label,
    required VoidCallback? onPressed,
    bool loading = false,
    IconData? icon,
  }) {
    return AppButton._(
      label: label,
      variant: AppButtonVariant.destructive,
      onPressed: onPressed,
      loading: loading,
      icon: icon,
    );
  }

  final String label;
  final AppButtonVariant variant;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabledCommand = loading ? null : onPressed;
    final child = _ButtonContent(label: label, loading: loading, icon: icon);

    return switch (variant) {
      AppButtonVariant.primary => FilledButton(
          onPressed: enabledCommand,
          child: child,
        ),
      AppButtonVariant.secondary => OutlinedButton(
          onPressed: enabledCommand,
          child: child,
        ),
      AppButtonVariant.destructive => FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: enabledCommand,
          child: child,
        ),
    };
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({required this.label, required this.loading, this.icon});

  final String label;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon case final icon?) ...[
          Icon(icon, size: 18),
          const SizedBox(width: 8),
        ],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
