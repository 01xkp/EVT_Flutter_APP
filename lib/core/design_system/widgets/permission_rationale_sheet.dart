import 'package:evt_ble_app/core/design_system/widgets/app_button.dart';
import 'package:flutter/material.dart';

abstract final class PermissionRationaleSheet {
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    return await showModalBottomSheet<bool>(
          context: context,
          builder: (context) =>
              _PermissionRationaleSheet(title: title, message: message),
        ) ??
        false;
  }
}

class _PermissionRationaleSheet extends StatelessWidget {
  const _PermissionRationaleSheet({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
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
            AppButton.primary(
              label: '继续',
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
  }
}
