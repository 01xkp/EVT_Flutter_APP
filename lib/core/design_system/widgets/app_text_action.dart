import 'package:flutter/material.dart';

/// A visible action label with the same accessible tooltip as its old icon.
class AppTextAction extends StatelessWidget {
  const AppTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.tooltip,
  });
  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? label,
    child: TextButton(onPressed: onPressed, child: Text(label)),
  );
}
