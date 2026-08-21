import 'package:evt_ble_app/core/design_system/widgets/app_button.dart';
import 'package:flutter/material.dart';

enum AppConfirmationVariant { normal, destructive }

abstract final class AppConfirmationSheet {
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = '取消',
    AppConfirmationVariant variant = AppConfirmationVariant.normal,
  }) async {
    return await showModalBottomSheet<bool>(
          context: context,
          builder: (context) => _AppConfirmationSheet(
            title: title,
            message: message,
            confirmLabel: confirmLabel,
            cancelLabel: cancelLabel,
            variant: variant,
          ),
        ) ??
        false;
  }
}

class _AppConfirmationSheet extends StatelessWidget {
  const _AppConfirmationSheet({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.variant,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final AppConfirmationVariant variant;

  @override
  Widget build(BuildContext context) {
    final isDestructive = variant == AppConfirmationVariant.destructive;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 20),
            AppButton.secondary(
              label: cancelLabel,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            const SizedBox(height: 8),
            isDestructive
                ? AppButton.destructive(
                    label: confirmLabel,
                    onPressed: () => Navigator.of(context).pop(true),
                  )
                : AppButton.primary(
                    label: confirmLabel,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
          ],
        ),
      ),
    );
  }
}
